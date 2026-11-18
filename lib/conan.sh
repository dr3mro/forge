# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by other modules
# Forge Conan 2 adapter.
# API: conan_check conan_has_deps conan_lock_create conan_install
#      conan_toolchain_path conan_lock_stale
# Inputs: FORGE_ROOT, FORGE_MANIFEST_JSON, FORGE_OFFLINE, run_cmd.
# Outputs: conan.lock and generated CMake files inside the build tree.
# Side effects: invokes Conan only; never resolves the graph itself.

# Require Conan 2 when the project uses Conan dependencies.
conan_check() {
  require_tool conan
  local v
  v=$(conan --version 2>/dev/null | awk '{print $NF}')
  version_ge "${v:-0}" 2 \
    || die "${EXIT_TOOL}" "Conan 2 is required (found '${v:-none}')"
}

# Report whether the current manifest declares Conan dependencies.
conan_has_deps() {
  (( $(mq '[((.dependencies // {}) | to_entries[] | select(.value.source == "conan"))] | length') > 0 ))
}

# True when any project in the reachable workspace graph uses Conan.
conan_graph_has_deps() {
  local node json
  workspace_collect_graph "${FORGE_ROOT}"
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    [[ -f "${node}/Forge.toml" ]] || continue
    json=$(manifest_to_json "${node}/Forge.toml") || continue
    if (( $(printf '%s' "${json}" \
        | jq '[((.dependencies // {}) | to_entries[] | select(.value.source == "conan"))] | length') > 0 )); then
      return 0
    fi
  done
  return 1
}

# All Conan requirements across the graph, as "ref<TAB>options-json" lines.
# Used when rendering the ROOT conanfile so one `conan install` covers every
# member, while each member still declares its own dependencies in Forge.toml.
FORGE_CONAN_ALL_REFS=()
FORGE_CONAN_REQUIREMENTS_MODE="local"

# Collect unique workspace requirements and reject conflicting options.
conan_prepare_requirements() {
  local root="$1" node json ref opts key
  local -A seen=()
  workspace_collect_graph "${root}"
  FORGE_CONAN_ALL_REFS=()
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    [[ -f "${node}/Forge.toml" ]] || continue
    json=$(manifest_to_json "${node}/Forge.toml") || continue
    while IFS=$'\t' read -r ref opts; do
      [[ -n "${ref}" ]] || continue
      if [[ -n "${seen[${ref}]+x}" && "${seen[${ref}]}" != "${opts}" ]]; then
        die "${EXIT_DEP}" "conflicting Conan options for '${ref}' in ${node#"${root}"/}"
      fi
      [[ -n "${seen[${ref}]+x}" ]] && continue
      seen["${ref}"]="${opts}"
      FORGE_CONAN_ALL_REFS+=("${ref}"$'\t'"${opts}")
    done < <(printf '%s' "${json}" | jq -r '
      ((.dependencies // {}) | to_entries[]
        | select(.value.source == "conan")
        | [.value.ref, ((.value.conan_options // {}) | tojson)] | @tsv)')
  done
}

# Hash only the Conan-relevant manifest data, so a post-lock `forge sync`
# (which rewrites conanfile.txt) does not invalidate an otherwise correct lock.
conan_manifest_sha() {
  local data node json
  workspace_collect_graph "${FORGE_ROOT}"
  data=""
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    [[ -f "${node}/Forge.toml" ]] || continue
    json=$(manifest_to_json "${node}/Forge.toml") || continue
    data+="${node#"${FORGE_ROOT}"/}="
    data+=$(printf '%s' "${json}" | jq -c '
      [((.dependencies // {}) | to_entries[]
        | select(.value.source == "conan")
        | {ref: .value.ref, options: (.value.conan_options // {})})]')
    data+=";"
  done
  sha256_str "${data}"
}

# Compare the recorded lock fingerprint with the current graph.
conan_lock_stale() {
  local lock="${FORGE_ROOT}/conan.lock" state="${FORGE_ROOT}/.forge/state.json" recorded
  [[ -f "${lock}" && -f "${state}" ]] || return 0
  recorded=$(state_read conan_lock_manifest_sha "${state}") || return 0
  [[ -n "${recorded}" ]] || return 0
  [[ "${recorded}" == "$(conan_manifest_sha)" ]] && return 1
  return 0
}

# Resolve the Conan graph and record the lock fingerprint.
conan_lock_create() {
  conan_check
  local lock="${FORGE_ROOT}/conan.lock" tmp_dir signature
  state_load
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would create ${lock#"${FORGE_ROOT}"/}"
    return 0
  fi
  # Lock against a freshly rendered recipe (the on-disk one may predate sync).
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/forge-conan.XXXXXX") \
    || die "${EXIT_OTHER}" "could not create temp directory"
  forge_add_tmpdir "${tmp_dir}"
  [[ ! -L "${lock}" && ( ! -e "${lock}" || -f "${lock}" ) ]] \
    || die "${EXIT_CONFLICT}" "refusing to replace an unsafe conan.lock path"
  signature=$(conan_manifest_sha) || die "${EXIT_DEP}" "could not fingerprint the Conan graph"
  conan_prepare_requirements "${FORGE_ROOT}"
  FORGE_CONAN_REQUIREMENTS_MODE="graph"
  render_conanfile > "${tmp_dir}/conanfile.txt" \
    || die "${EXIT_OTHER}" "could not render the Conan lock recipe"
  FORGE_CONAN_REQUIREMENTS_MODE="local"
  local -a args=(lock create "${tmp_dir}/conanfile.txt" "--lockfile-out=${tmp_dir}/conan.lock")
  if [[ -f "${lock}" ]]; then
    args+=("--lockfile=${lock}" --lockfile-partial --lockfile-clean)
  else
    args+=(--lockfile=)
  fi
  (( FORGE_OFFLINE )) && args+=(--build=never --no-remote)
  progress "Running Conan ${args[0]}"
  run_cmd conan "${args[@]}" \
    || die "${EXIT_DEP}" "conan lock create failed"
  [[ "${signature}" == "$(conan_manifest_sha)" ]] \
    || die "${EXIT_CONFLICT}" "Conan dependencies changed while locking; retry"
  atomic_write "${lock}" < "${tmp_dir}/conan.lock" \
    || die "${EXIT_OTHER}" "could not publish conan.lock"
  state_set conan_lock_manifest_sha "${signature}" \
    || die "${EXIT_OTHER}" "could not record Conan lock state"
  progress_finish
  out "wrote conan.lock"
}

# Install locked Conan packages and generate CMake integration files.
conan_install() {
  local build_dir="$1" profile="$2" lock="${FORGE_ROOT}/conan.lock" bt
  conan_check
  [[ -f "${lock}" ]] \
    || die "${EXIT_DEP}" "conan.lock is missing (run 'forge deps lock')"
  ! conan_lock_stale \
    || die "${EXIT_DEP}" "conan.lock is stale relative to conanfile.txt (run 'forge deps lock')"

  local conanfile="${FORGE_ROOT}/conanfile.txt"
  [[ -f "${conanfile}" ]] \
    || die "${EXIT_DEP}" "conanfile.txt is missing (run 'forge sync --apply')"

  case "${profile}" in
    release | Release) bt="Release" ;;
    *)                 bt="Debug" ;;
  esac
  local -a args=(install "${conanfile}" "-of=${build_dir}" "-s=build_type=${bt}"
    "--lockfile=${lock}" -c "tools.cmake.cmaketoolchain:user_presets=")
  if (( FORGE_OFFLINE )); then
    args+=(--build=never --no-remote)
  else
    args+=("--build=missing")
  fi
  progress "Running Conan ${args[0]}"
  run_cmd conan "${args[@]}" \
    || die "${EXIT_DEP}" "conan install failed"
  progress_finish
  status "Conan graph installed for ${bt}"
}

# Forget Conan's legacy includes of fingerprinted Forge builds. Preserve other
# includes and only touch a file explicitly marked by Conan.
conan_prune_user_presets() {
  local file="${FORGE_ROOT}/CMakeUserPresets.json" filtered
  [[ -f "${file}" && ! -L "${file}" ]] || return 0
  filtered=$(jq '
    def forge_preset:
      type == "string" and test("^target/(?:[A-Za-z_][A-Za-z0-9_-]*-[a-f0-9]{12}|(?:debug|release)(?:/[.]forge-conan)?)/CMakePresets[.]json$");
    select(type == "object" and (.vendor | type == "object" and has("conan"))
      and (.include | type == "array" and any(.[]; forge_preset)))
    | .include |= map(select(forge_preset | not))
  ' "${file}" 2>/dev/null) || return 0
  [[ -n "${filtered}" ]] || return 0
  printf '%s\n' "${filtered}" | atomic_write "${file}"
}

# Locate the toolchain file emitted by Conan.
conan_toolchain_path() {
  local build_dir="$1"
  find "${build_dir}" -name conan_toolchain.cmake -print -quit 2>/dev/null
}

# Fail a reference lookup with the versions the configured remotes offer.
_conan_metadata_failure() {
  local ref="$1" name="$2" versions=""
  if (( ! FORGE_OFFLINE )); then
    versions=$(conan list "${name}/*" -r '*' --format=json 2>/dev/null \
      | jq -r '[.[] | keys[]] | unique[]' 2>/dev/null \
      | sort -V | paste -sd, - 2>/dev/null | sed 's/,/, /g' || :)
  fi
  if [[ -n "${versions}" ]]; then
    die "${EXIT_DEP}" "${ref} is not available in Conan remotes. Available versions: ${versions}"
  fi
  die "${EXIT_DEP}" "could not inspect ${ref}; supply --cmake-target and --cmake-package to use explicit CMake names"
}

# Read the selected package's CMake consumer properties from Conan install JSON.
conan_cmake_metadata() (
  local ref="$1" profile="$2" explicit_target="$3"
  shift 3
  conan_check
  local tmp bt=Debug option name="${ref%%/*}"
  [[ "${profile}" != release ]] || bt=Release
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/forge-conan-metadata.XXXXXX") || exit "${EXIT_OTHER}"
  trap 'rm -rf -- "${tmp}"' EXIT
  local -a args=(install "--requires=${ref}" "--lockfile=" --build=never --format=json
    "-s=build_type=${bt}" "-of=${tmp}")
  (( ! FORGE_OFFLINE )) || args+=(--no-remote)
  for option in "$@"; do args+=("-o=${name}/*:${option}"); done
  conan "${args[@]}" > "${tmp}/metadata.json" \
    || _conan_metadata_failure "${ref}" "${name}"
  local metadata
  metadata=$(jq -ce --arg name "${name}" --arg chosen "${explicit_target}" '
    [.graph.nodes[] | select(.name == $name and .context == "host")] | first as $node
    | $node.cpp_info | select(.root != null)
    | .root.properties as $root
    | select(($root.cmake_find_mode // "config") | IN("config", "both"))
    | [to_entries[] | select(.key != "root")
        | (.value.properties.cmake_target_name // ($name + "::" + .key))] | unique as $components
    | {
        package: ($root.cmake_file_name // $name),
        target: (if $chosen != "" then $chosen
          else $root.cmake_target_name // (if ($components | length) > 1 then null
          elif ($components | length) == 1 then $components[0]
          else $name + "::" + $name end) end),
        components: $components, version: ($node.version // "")
      }' "${tmp}/metadata.json") \
    || die "${EXIT_DEP}" "Conan did not report usable CMake config metadata for ${ref}"
  if ! jq -e '.target != null' <<< "${metadata}" >/dev/null; then
    die "${EXIT_USAGE}" "choose --cmake-target from: $(jq -r '.components | join(", ")' <<< "${metadata}")"
  fi
  jq -r '[.package, .target, .version] | @tsv' <<< "${metadata}"
)
