# shellcheck shell=bash
# Forge manifest — TOML->JSON adapter, schema validation, JSON queries.
# API:
#   manifest_to_json FILE       # TOML (1.0) -> compact JSON on stdout
#   manifest_validate_json JSON # emits errors, returns 0/1
#   manifest_load               # discover + parse + validate; set globals
#   mq FILTER [args...]         # jq -r query over the loaded manifest
#   mq_json FILTER [args...]    # jq -c query over the loaded manifest
# Inputs: FORGE_MANIFEST_PATH / FORGE_ROOT; python3 tomllib; jq.
# Outputs: sets FORGE_MANIFEST_JSON. No writes.
# Side effects: none. Manifest parsing NEVER executes project scripts.

FORGE_MANIFEST_JSON=""

# Parse a TOML manifest with Python and emit JSON.
manifest_to_json() {
  local file="$1"
  require_tool python3
  if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
    die "${EXIT_TOOL}" "python3 3.11+ with stdlib tomllib is required (run 'forge doctor')"
  fi
  python3 - "${file}" <<'PY'
import json
import sys
import tomllib

path = sys.argv[1]
try:
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
except Exception as exc:  # noqa: BLE001 - surface any parse error cleanly
    sys.stderr.write("forge: cannot parse %s: %s\n" % (path, exc))
    sys.exit(2)
json.dump(data, sys.stdout, separators=(",", ":"))
PY
}

# Check a parsed manifest against the Forge schema.
manifest_validate_json() {
  local json="$1" errs
  require_tool jq
  if ! errs=$(printf '%s' "${json}" | jq -r -f "${FORGE_LIB}/schema.jq" 2>&1); then
    fail "schema validator failed to run"
    return 1
  fi
  if [[ -n "${errs}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && fail "${line}"
    done <<< "${errs}"
    return 1
  fi
  return 0
}

# Discover, parse, and validate the current project's manifest.
manifest_load() {
  require_project
  FORGE_MANIFEST_JSON=$(manifest_to_json "${FORGE_MANIFEST_PATH}") \
    || die "${EXIT_USAGE}" "could not parse ${FORGE_MANIFEST_PATH}"
  manifest_validate_json "${FORGE_MANIFEST_JSON}" \
    || die "${EXIT_USAGE}" "invalid manifest: ${FORGE_MANIFEST_PATH}"
}

# Query the loaded manifest. Ensure manifest_load has been called first.
mq() {
  printf '%s' "${FORGE_MANIFEST_JSON}" | jq -r "$@"
}

# Query the loaded manifest and emit compact JSON.
mq_json() {
  printf '%s' "${FORGE_MANIFEST_JSON}" | jq -c "$@"
}

# --- Block-level edits (transactional, no general TOML writer) -------------
# See docs/decisions/0002-manifest-editing.md.
FORGE_EDIT_LINES=()

# Load the manifest into the line buffer used for edits.
_manifest_read_lines() {
  local file="$1"
  mapfile -t FORGE_EDIT_LINES < "${file}" \
    || die "${EXIT_OTHER}" "could not read ${file}"
}

# Escape a value for a TOML basic string.
_toml_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

# Save a copy of the manifest before replacing it.
_manifest_backup() {
  local file="$1" dir backup_dir ts
  dir=$(dirname -- "${file}")
  backup_dir="${dir}/.forge/backups"
  mkdir -p "${backup_dir}"
  ts="$(date +%s).$$"
  cp -- "${file}" "${backup_dir}/Forge.toml.${ts}" \
    || die "${EXIT_OTHER}" "could not back up ${file}"
}

# Validate the candidate text, then replace the manifest atomically.
_manifest_commit() {
  local file="$1" tmp json
  tmp=$(mktemp "$(dirname -- "${file}")/.forge-tmp.XXXXXX") \
    || die "${EXIT_OTHER}" "could not create temp file"
  printf '%s\n' "${FORGE_EDIT_LINES[@]}" > "${tmp}"
  if ! json=$(manifest_to_json "${tmp}"); then
    rm -f -- "${tmp}"
    die "${EXIT_USAGE}" "edit produced invalid TOML; refusing to write"
  fi
  if ! manifest_validate_json "${json}"; then
    rm -f -- "${tmp}"
    die "${EXIT_USAGE}" "edit produced an invalid manifest; refusing to write"
  fi
  if ! cat -- "${tmp}" | atomic_write "${file}"; then
    rm -f -- "${tmp}"
    die "${EXIT_OTHER}" "atomic write failed for ${file}"
  fi
  rm -f -- "${tmp}"
}

# Find the index of a dependency's header. Echoes -1 if absent.
_manifest_dep_header() {
  local name="$1" i line re
  re="^[[:space:]]*\\[dependencies\\.${name}\\][[:space:]]*(#.*)?$"
  for (( i = 0; i < ${#FORGE_EDIT_LINES[@]}; i++ )); do
    line="${FORGE_EDIT_LINES[i]}"
    [[ "${line}" =~ ${re} ]] && { printf '%s' "${i}"; return 0; }
  done
  printf '%s' "-1"
}

# Append a dependency table and validate the edited manifest.
manifest_add_dependency() {
  local file="$1" name="$2" source="$3"
  shift 3
  local ref="" url="" rev="" path="" cmake_target="" cmake_package="" port="" version="" vcpkg_baseline="" link_target="" kv key value
  local -a options=()
  for kv in "$@"; do
    key="${kv%%=*}" value="${kv#*=}"
    case "${key}" in
      ref) ref="${value}" ;;
      url) url="${value}" ;;
      rev) rev="${value}" ;;
      path) path="${value}" ;;
      cmake_target) cmake_target="${value}" ;;
      cmake_package) cmake_package="${value}" ;;
      port) port="${value}" ;;
      version) version="${value}" ;;
      vcpkg_baseline) vcpkg_baseline="${value}" ;;
      link_target) link_target="${value}" ;;
      option) options+=("${value}") ;;
      *) die "${EXIT_USAGE}" "unknown dependency field: ${key}" ;;
    esac
  done

  _manifest_read_lines "${file}"
  [[ "$(_manifest_dep_header "${name}")" == "-1" ]] \
    || die "${EXIT_USAGE}" "dependency '${name}' already exists"

  local -a block=("[dependencies.${name}]" "source = \"$(_toml_escape "${source}")\"")
  case "${source}" in
    conan)
      [[ -n "${ref}" ]] || die "${EXIT_USAGE}" "conan dependency needs --ref"
      block+=("ref = \"$(_toml_escape "${ref}")\"")
      ;;
    vcpkg)
      block+=("port = \"$(_toml_escape "${port}")\"")
      [[ -z "${version}" ]] || block+=("version = \"$(_toml_escape "${version}")\"")
      ;;
    git)
      [[ -n "${url}" ]] || die "${EXIT_USAGE}" "git dependency needs --url"
      [[ "${rev}" =~ ^[0-9a-fA-F]{40}$ ]] \
        || die "${EXIT_USAGE}" "git dependency needs a full 40-char --rev (use 'forge deps pin')"
      block+=("url = \"$(_toml_escape "${url}")\"")
      block+=("rev = \"$(_toml_escape "${rev}")\"")
      ;;
    path)
      [[ -n "${path}" ]] || die "${EXIT_USAGE}" "path dependency needs --path"
      path_is_safe_relative "${path}" || die "${EXIT_USAGE}" "unsafe path: ${path}"
      block+=("path = \"$(_toml_escape "${path}")\"")
      ;;
    *) die "${EXIT_USAGE}" "unknown source '${source}' (use conan, vcpkg, git or path)" ;;
  esac
  [[ -n "${cmake_target}" ]] || die "${EXIT_USAGE}" "dependency needs --cmake-target"
  block+=("cmake_target = \"$(_toml_escape "${cmake_target}")\"")

  if [[ -n "${cmake_package}" ]]; then
    block+=("cmake_package = \"$(_toml_escape "${cmake_package}")\"")
  fi
  if [[ -n "${link_target}" ]]; then
    _manifest_link_target "${file}" "${link_target}" "${name}"
  fi

  [[ -z "${vcpkg_baseline}" ]] || _manifest_insert_vcpkg_baseline "${file}" "${vcpkg_baseline}"

  local last="${FORGE_EDIT_LINES[${#FORGE_EDIT_LINES[@]}-1]:-}"
  [[ -z "${last}" ]] || FORGE_EDIT_LINES+=("")
  FORGE_EDIT_LINES+=("${block[@]}")
  if (( ${#options[@]} )); then
    local opt key val
    FORGE_EDIT_LINES+=("" "[dependencies.${name}.conan_options]")
    for opt in "${options[@]}"; do
      key="${opt%%=*}" val="${opt#*=}"
      [[ -n "${key}" && "${key}" != "${opt}" ]] \
        || die "${EXIT_USAGE}" "--option must be KEY=VALUE"
      FORGE_EDIT_LINES+=("${key} = \"$(_toml_escape "${val}")\"")
    done
  fi

  _manifest_backup "${file}"
  _manifest_commit "${file}"
  printf '%s\n' "${block[@]}"
}

# Add the workspace baseline to the edit buffer without replacing the build table.
_manifest_insert_vcpkg_baseline() {
  local file="$1" baseline="$2" i json
  for (( i=0; i<${#FORGE_EDIT_LINES[@]}; i++ )); do
    if [[ "${FORGE_EDIT_LINES[i]}" =~ ^[[:space:]]*\[build\][[:space:]]*(#.*)?$ ]]; then
      FORGE_EDIT_LINES=("${FORGE_EDIT_LINES[@]:0:i+1}" "vcpkg_baseline = \"${baseline}\"" "${FORGE_EDIT_LINES[@]:i+1}")
      return 0
    fi
  done
  json=$(manifest_to_json "${file}") || return $?
  if jq -e 'has("build") | not' <<< "${json}" >/dev/null; then
    FORGE_EDIT_LINES+=("" "[build]" "vcpkg_baseline = \"${baseline}\"")
    return 0
  fi
  die "${EXIT_USAGE}" "set build.vcpkg_baseline in the workspace root or use a [build] table"
}

manifest_set_vcpkg_baseline() {
  local file="$1" baseline="$2"
  _manifest_read_lines "${file}"
  _manifest_insert_vcpkg_baseline "${file}" "${baseline}"
  _manifest_backup "${file}"
  _manifest_commit "${file}"
}

# Add a link to one target in the current edit buffer before the manifest commit.
_manifest_link_target() {
  local file="$1" target="$2" dependency="$3" start end i row block links
  local -a edited=()
  local name_pattern="^[[:space:]]*name[[:space:]]*=[[:space:]]*[\"']${target}[\"'][[:space:]]*(#.*)?$"
  for (( i=0; i<${#FORGE_EDIT_LINES[@]}; i++ )); do
    [[ "${FORGE_EDIT_LINES[i]}" =~ ^[[:space:]]*\[\[(bin|lib|test)\]\]([[:space:]]*(#.*)?)$ ]] || continue
    start=$i
    for (( end=start+1; end<${#FORGE_EDIT_LINES[@]}; end++ )); do
      [[ "${FORGE_EDIT_LINES[end]}" =~ ^[[:space:]]*\[ ]] && break
    done
    for (( row=start+1; row<end; row++ )); do
      [[ "${FORGE_EDIT_LINES[row]}" =~ ${name_pattern} ]] || continue
      local selection existing_length addition comma=""
      selection=$(mq_json --arg target "${target}" --arg dep "${dependency}" '
        . as $project
        | ((.bin // []) + (.lib // []) + (.test // []))[]
        | select(.name == $target)
        | (.links // []) as $before
        | {length: ($before | length), new: (if ($before | index($dep)) != null then []
          elif ($before | length) > 0 then [$dep]
          else ([($project.dependencies // {}) | to_entries[]
            | select(.value | has("cmake_package") | not) | .key] + [$dep] | unique)
          end)}
      ') || die "${EXIT_USAGE}" "could not read links for ${target}"
      links=$(jq -c '.new' <<< "${selection}")
      [[ "${links}" != '[]' ]] || return 0
      existing_length=$(jq -r '.length' <<< "${selection}")
      if (( existing_length )); then comma=", "; fi
      addition="${links:1:${#links}-2}${comma}"
      for (( block=start+1; block<end; block++ )); do
        [[ "${FORGE_EDIT_LINES[block]}" =~ ^[[:space:]]*links[[:space:]]*= ]] || continue
        [[ "${FORGE_EDIT_LINES[block]}" =~ ^([[:space:]]*links[[:space:]]*=[[:space:]]*\[) ]] \
          || die "${EXIT_USAGE}" "could not locate the links array in ${file}"
        local prefix="${BASH_REMATCH[1]}"
        FORGE_EDIT_LINES[block]="${prefix}${addition}${FORGE_EDIT_LINES[block]#"${prefix}"}"
        return
      done
      edited=("${FORGE_EDIT_LINES[@]:0:row+1}" "links = ${links}" "${FORGE_EDIT_LINES[@]:row+1}")
      FORGE_EDIT_LINES=("${edited[@]}")
      return
    done
    i=$((end-1))
  done
  die "${EXIT_USAGE}" "could not locate target '${target}' in ${file}"
}

# Link a previously declared dependency to another local target.
manifest_link_existing_dependency() {
  _manifest_read_lines "$1"
  _manifest_link_target "$1" "$2" "$3"
  _manifest_backup "$1"
  _manifest_commit "$1"
}

# Apply a targeted TOML edit, checking that its parsed meaning matches the plan.
manifest_remove_entry() {
  local file="$1" name="$2" member="$3" links="$4" edited
  edited=$(python3 "${FORGE_LIB}/remove-entry.py" "${file}" "${name}" "${member}" "${links}") \
    || die "${EXIT_USAGE}" "could not safely edit ${file}; edit the entry and its links manually and run forge sync"
  mapfile -t FORGE_EDIT_LINES <<< "${edited}"
  _manifest_backup "${file}"
  _manifest_commit "${file}"
}

# Append a link name to every [[bin]] / [[lib]] / [[test]] target in the
# manifest. Used by `generate lib` so a new member is immediately usable.
manifest_add_link_to_targets() {
  local file="$1" link="$2"
  local i j n start end line prefix rest inner tail new_inner inserted found
  _manifest_read_lines "${file}"
  n=${#FORGE_EDIT_LINES[@]}
  local -a lines_out=()

  i=0
  while (( i < n )); do
    line="${FORGE_EDIT_LINES[i]}"
    if [[ "${line}" =~ ^[[:space:]]*\[\[(bin|lib|test)\]\][[:space:]]*(#.*)?$ ]]; then
      start=${i}
      end=${n}
      for (( j = start + 1; j < n; j++ )); do
        [[ "${FORGE_EDIT_LINES[j]}" =~ ^[[:space:]]*\[ ]] && { end=${j}; break; }
      done
      lines_out+=("${line}")

      found=0
      for (( j = start + 1; j < end; j++ )); do
        line="${FORGE_EDIT_LINES[j]}"
        if [[ "${line}" =~ ^[[:space:]]*links[[:space:]]*= ]]; then
          prefix="${line%%\[*}"
          rest="${line#*\[}"
          inner="${rest%%\]*}"
          tail="${rest#*]}"
          if [[ "${inner}" == *"\"${link}\""* ]]; then
            found=1
          else
            if [[ -n "${inner//[[:space:]]/}" ]]; then
              new_inner="${inner}, \"${link}\""
            else
              new_inner="\"${link}\""
            fi
            line="${prefix}[${new_inner}]${tail}"
            found=1
          fi
        fi
        lines_out+=("${line}")
      done

      if (( ! found )); then
        inserted=0
        for (( j = start + 1; j < end; j++ )); do
          lines_out+=("${FORGE_EDIT_LINES[j]}")
          if [[ "${FORGE_EDIT_LINES[j]}" =~ ^[[:space:]]*name[[:space:]]*= && ${inserted} -eq 0 ]]; then
            lines_out+=("links = [\"${link}\"]")
            inserted=1
          fi
        done
      fi
      i=${end}
    else
      lines_out+=("${line}")
      i=$((i + 1))
    fi
  done

  FORGE_EDIT_LINES=("${lines_out[@]}")
  _manifest_backup "${file}"
  _manifest_commit "${file}"
  out "linked '${link}' into all targets"
}

# Add a workspace member; bumps schema to 2 and creates [workspace] if absent.
manifest_add_workspace_member() {
  local file="$1" path="$2" i line prefix inner tail new_inner found_ws=0 found_members=0
  path_is_safe_relative "${path}" || die "${EXIT_USAGE}" "unsafe workspace member path: ${path}"
  _manifest_read_lines "${file}"

  for (( i = 0; i < ${#FORGE_EDIT_LINES[@]}; i++ )); do
    line="${FORGE_EDIT_LINES[i]}"
    if [[ "${line}" =~ ^schema[[:space:]]*=[[:space:]]*1[[:space:]]*$ ]]; then
      FORGE_EDIT_LINES[i]="schema = 2"
    fi
    [[ "${line}" =~ ^[[:space:]]*\[workspace\][[:space:]]*(#.*)?$ ]] && found_ws=1
  done

  if (( found_ws )); then
    for (( i = 0; i < ${#FORGE_EDIT_LINES[@]}; i++ )); do
      line="${FORGE_EDIT_LINES[i]}"
      [[ "${line}" =~ ^[[:space:]]*members[[:space:]]*= ]] || continue
      [[ "${line}" == *\[*\]* ]] || die "${EXIT_USAGE}" "cannot parse workspace members line"
      prefix="${line%%\[*}"
      inner="${line#*\[}"
      inner="${inner%%\]*}"
      tail="${line#*]}"
      if [[ "${inner}" == *"\"${path}\""* ]]; then
        out "workspace member '${path}' is already registered"
        return 0
      fi
      if [[ -n "${inner//[[:space:]]/}" ]]; then
        new_inner="${inner}, \"${path}\""
      else
        new_inner=" \"${path}\""
      fi
      FORGE_EDIT_LINES[i]="${prefix}[${new_inner}]${tail}"
      found_members=1
      break
    done
    (( found_members )) || die "${EXIT_USAGE}" "[workspace] has no parseable 'members' line"
  else
    local last="${FORGE_EDIT_LINES[${#FORGE_EDIT_LINES[@]}-1]:-}"
    [[ -z "${last}" ]] || FORGE_EDIT_LINES+=("")
    FORGE_EDIT_LINES+=("[workspace]" "members = [\"${path}\"]")
  fi

  _manifest_backup "${file}"
  _manifest_commit "${file}"
  out "registered workspace member '${path}'"
}

# Set one field inside a dependency block (used by 'deps pin').
manifest_set_dep_field() {
  local file="$1" name="$2" field="$3" value="$4"
  local start end i line n found=0 re
  _manifest_read_lines "${file}"
  start=$(_manifest_dep_header "${name}")
  [[ "${start}" != "-1" ]] || die "${EXIT_USAGE}" "no dependency named '${name}'"
  n=${#FORGE_EDIT_LINES[@]}
  end=${n}
  for (( i = start + 1; i < n; i++ )); do
    [[ "${FORGE_EDIT_LINES[i]}" =~ ^[[:space:]]*\[ ]] && { end=${i}; break; }
  done
  re="^([[:space:]]*${field}[[:space:]]*=[[:space:]]*\")[^\"]*(\".*)$"
  for (( i = start; i < end; i++ )); do
    line="${FORGE_EDIT_LINES[i]}"
    if [[ "${line}" =~ ${re} ]]; then
      FORGE_EDIT_LINES[i]="${BASH_REMATCH[1]}$(_toml_escape "${value}")${BASH_REMATCH[2]}"
      found=1
      break
    fi
  done
  (( found )) || die "${EXIT_USAGE}" "dependency '${name}' has no '${field}' field"
  _manifest_backup "${file}"
  _manifest_commit "${file}"
}
