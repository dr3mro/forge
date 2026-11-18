# shellcheck shell=bash
# Forge command: add (dependency).

# Validate a dependency, edit its module manifest, and apply workspace sync.
cmd_add() {
  local name="" source="" ref="" url="" rev="" tag="" branch="" path=""
  local cmake_target="" cmake_package="" shortcut="" target="" port="" conan_name="" port_version=""
  local -a options=() fields=()
  local selected="" wizard=0
  while (( $# > 0 )); do
    case "$1" in
      --conan | --vcpkg | --github)
        selected="${1#--}"
        if [[ "${selected}" == github ]]; then selected=git; fi
        [[ -z "${shortcut}" || "${shortcut}" == "${selected}" ]] \
          || die "${EXIT_USAGE}" "choose only one of --conan, --vcpkg, or --github"
        shortcut="${selected}"
        shift
        ;;
      --source=*)
        source="${1#*=}"
        [[ -n "${source}" ]] || die "${EXIT_USAGE}" "--source requires a value"
        shift
        ;;
      --source | --ref | --url | --rev | --sha | --tag | --branch | --path | --cmake-target | --cmake-package | --target | --option)
        [[ -n "${2:-}" && "$2" != --* ]] || die "${EXIT_USAGE}" "$1 requires a value"
        case "$1" in
          --source) source="$2" ;;
          --ref) ref="$2" ;;
          --url) url="$2" ;;
          --rev | --sha | --tag | --branch)
            [[ -z "${rev}${tag}${branch}" ]] \
              || die "${EXIT_USAGE}" "choose one Git selector: --sha, --tag or --branch"
            case "$1" in
              --rev | --sha) rev="$2" ;;
              --tag) tag="$2" ;;
              --branch) branch="$2" ;;
            esac
            ;;
          --path) path="$2" ;;
          --cmake-target) cmake_target="$2" ;;
          --cmake-package) cmake_package="$2" ;;
          --target) target="$2" ;;
          --option) options+=("$2") ;;
        esac
        shift 2
        ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'add': $1" ;;
      *) [[ -z "${name}" ]] || die "${EXIT_USAGE}" "add accepts one NAME"; name="$1"; shift ;;
    esac
  done

  [[ -n "${name}" ]] || die "${EXIT_USAGE}" "add requires a dependency NAME"
  if [[ -z "${source}${shortcut}" ]]; then
    if [[ -t 0 || -p /dev/stdin || -f /dev/stdin ]]; then
      add_prompt selected "Dependency source [conan/vcpkg/github]" ""
      case "${selected}" in
        1 | conan) shortcut=conan ;;
        2 | vcpkg) shortcut=vcpkg ;;
        3 | github | git) shortcut=git ;;
        *) die "${EXIT_USAGE}" "choose conan, vcpkg, or github (see 'forge add --help')" ;;
      esac
      wizard=1
    else
      die "${EXIT_USAGE}" "choose --conan, --vcpkg, --github, or --source (see 'forge add --help')"
    fi
  fi
  if [[ -n "${shortcut}" ]]; then
    [[ -z "${source}" || "${source}" == "${shortcut}" ]] \
      || die "${EXIT_USAGE}" "dependency source conflicts with --${shortcut}"
    source="${shortcut}"
  fi
  case "${source}" in
    conan | vcpkg | git | path) ;;
    *) die "${EXIT_USAGE}" "add requires a source: conan, vcpkg, git or path" ;;
  esac
  if [[ -n "${target}" && -z "${shortcut}" && "${source}" != vcpkg ]]; then
    die "${EXIT_USAGE}" "--target requires --conan, --vcpkg, or --github"
  fi
  if [[ "${source}" == conan || "${source}" == vcpkg ]]; then
    [[ -z "${url}${rev}${tag}${branch}${path}" ]] \
      || die "${EXIT_USAGE}" "Git and path flags conflict with ${source}"
  elif [[ -n "${cmake_package}" ]]; then
    die "${EXIT_USAGE}" "--cmake-package requires Conan or vcpkg"
  fi
  if [[ "${shortcut}" == git ]]; then
    if [[ -z "${url}" ]]; then add_prompt url "Git repository URL" ""; fi
    if [[ -z "${rev}${tag}${branch}" ]]; then
      add_prompt selected "Git revision type [tag/branch/sha]" tag
      case "${selected}" in
        tag) add_prompt tag "Git tag" "" ;;
        branch) add_prompt branch "Git branch" "" ;;
        sha) add_prompt rev "Full Git commit SHA" "" ;;
        *) die "${EXIT_USAGE}" "choose tag, branch, or sha" ;;
      esac
    fi
    if [[ -z "${cmake_target}" ]]; then add_prompt cmake_target "Upstream CMake target" ""; fi
  elif [[ "${shortcut}" == conan ]]; then
    if [[ "${name}" == */* ]]; then
      [[ -z "${ref}" || "${ref}" == "${name}" ]] \
        || die "${EXIT_USAGE}" "positional reference conflicts with --ref"
      ref="${name}"
      name="${name%%/*}"
    fi
    if [[ "${name}" == fmt && -z "${ref}" ]]; then ref=fmt/12.1.0; fi
    [[ "${name}" =~ ^[a-z0-9_][a-z0-9_.+-]*$ ]] || die "${EXIT_USAGE}" "invalid Conan package name"
    if [[ -n "${ref}" ]]; then
      [[ "${ref}" == "${name}/"* && "${ref#*/}" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]] \
        || die "${EXIT_USAGE}" "use NAME/VERSION or supply an exact --ref for ${name}"
    fi
    conan_name="${name}"
    if [[ "${name}" == fmt ]]; then
      local has_header_only=0 option
      for option in "${options[@]}"; do
        [[ "${option}" != header_only=* ]] || has_header_only=1
      done
      (( has_header_only )) || options+=(header_only=True)
    fi
    name="${name//[.+-]/_}"
    [[ "${name}" != [0-9]* ]] || name="conan_${name}"
  elif [[ "${source}" == vcpkg ]]; then
    if [[ "${name}" == */* ]]; then
      port_version="${name#*/}"
      name="${name%%/*}"
      [[ "${port_version}" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*(#[0-9]+)?$ ]] \
        || die "${EXIT_USAGE}" "use PORT/VERSION or PORT/VERSION#PORT_VERSION for vcpkg"
    fi
    [[ "${name}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "${EXIT_USAGE}" "invalid vcpkg port: ${name}"
    [[ -z "${ref}" && ${#options[@]} -eq 0 ]] \
      || die "${EXIT_USAGE}" "use PORT/VERSION to pin a vcpkg port"
    port="${name}"
    name="${name//-/_}"
    [[ "${name}" != [0-9]* ]] || name="vcpkg_${name}"
    case "${port}" in
      fmt) cmake_target="${cmake_target:-fmt::fmt}" ;;
      sqlite3)
        cmake_package="${cmake_package:-unofficial-sqlite3}"
        cmake_target="${cmake_target:-unofficial::sqlite3::sqlite3}" ;;
    esac
    if (( wizard )) && [[ -z "${cmake_target}" ]]; then
      add_prompt cmake_target "Upstream CMake target" ""
    fi
    cmake_package="${cmake_package:-${port}}"
  fi
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid dependency name: ${name}"
  [[ "${shortcut}" == conan || -n "${cmake_target}" ]] || die "${EXIT_USAGE}" "add requires --cmake-target"

  manifest_load
  deps_check_collisions || die "${EXIT_DEP}" "dependency collisions detected"
  if [[ "${source}" == vcpkg ]] && vcpkg_target_is_local "${cmake_target}" "${FORGE_MANIFEST_JSON}"; then
    die "${EXIT_USAGE}" "--cmake-target '${cmake_target}' names a project target; use the imported target exported by the vcpkg port"
  fi
  if [[ "${shortcut}" == conan && -z "${ref}" ]]; then
    ref=$(mq --arg name "${name}" '(.dependencies[$name] // {}) | select(.source == "conan") | .ref // empty')
    if [[ -n "${ref}" && "${ref}" != "${conan_name}/"* ]]; then
      die "${EXIT_CONFLICT}" "dependency name '${name}' is already used by a different Conan package"
    fi
  fi
  local opt
  for opt in "${options[@]}"; do
    [[ "${opt}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || die "${EXIT_USAGE}" "--option must be KEY=VALUE"
    fields+=("option=${opt}")
  done

  if [[ -n "${shortcut}" || "${source}" == vcpkg || -n "${target}" ]]; then
    target=$(add_select_target "${target}") || return $?
  fi
  if (( FORGE_DRY_RUN )) && [[ -n "${target}" ]]; then
    local requested="${ref:-${port:-${name}}}"
    [[ -z "${port_version}" ]] || requested="${port}/${port_version}"
    status "dry-run: would add '${requested}' (${source}) to ${FORGE_MANIFEST_PATH} and link '${target}'"
    return "${EXIT_OK}"
  fi
  if [[ "${source}" == git && -z "${rev}" && ( -n "${tag}" || -n "${branch}" ) ]]; then
    (( FORGE_OFFLINE )) \
      && die "${EXIT_DEP}" "--offline cannot resolve a tag/branch; supply --sha"
    url="${url:-$(mq --arg n "${name}" '(.dependencies // {})[$n].url // empty')}"
    [[ -n "${url}" ]] || die "${EXIT_USAGE}" "git dependency needs --url"
    local selector=--branch
    if [[ -n "${tag}" ]]; then selector=--tag; fi
    rev=$(fetchcontent_resolve_ref "${url}" "${selector}" "${tag:-${branch}}") || return $?
    status "resolved ${tag:-${branch}} -> ${rev}"
  fi
  if [[ -n "${target}" ]] && mq -e --arg name "${name}" '.dependencies[$name] != null' >/dev/null; then
    local requested_options
    requested_options=$(printf '%s\n' "${options[@]}" | jq -Rn '[inputs | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$")] | from_entries')
    mq -e --arg name "${name}" --arg source "${source}" --arg ref "${ref}" --arg port "${port}" --arg version "${port_version}" \
      --arg url "${url}" --arg rev "${rev}" --arg imported "${cmake_target}" --arg package "${cmake_package}" --argjson options "${requested_options}" '
        .dependencies[$name] as $d
        | $d.source == $source and (($d.ref // "") == $ref) and (($d.port // "") == $port)
        and ($version == "" or ($d.version // "") == $version)
        and ($source != "git" or ($d.url == $url and $d.rev == $rev))
        and ($imported == "" or $d.cmake_target == $imported)
        and ($package == "" or $d.cmake_package == $package)
        and (($d.conan_options // {} | map_values(if . == true then "True" elif . == false then "False" else tostring end)) == $options)
      ' >/dev/null || die "${EXIT_CONFLICT}" "dependency '${name}' already exists with different settings"
    if mq -e --arg target "${target}" --arg name "${name}" '
      ((.bin // []) + (.lib // []) + (.test // []))[]
      | select(.name == $target) | (.links // []) | index($name) != null
    ' >/dev/null; then
      out "dependency '${name}' already linked to '${target}'"
    else
      sync_check_destinations "${FORGE_ROOT}"
      manifest_link_existing_dependency "${FORGE_MANIFEST_PATH}" "${target}" "${name}"
      out "linked '${name}' to '${target}'"
    fi
    add_sync_dependency "${source}"
    return $?
  fi

  if [[ "${shortcut}" == conan ]]; then
    if [[ -z "${ref}" || -z "${cmake_package}" || -z "${cmake_target}" ]]; then
      local metadata profile root
      root=$(workspace_enclosing_root "${FORGE_ROOT}") || return "${EXIT_CONFLICT}"
      profile=$(manifest_to_json "${root}/Forge.toml" | jq -r '.build.default_profile // "debug"') || return "${EXIT_USAGE}"
      local query="${ref:-${conan_name}/[*]}" discovered_package discovered_target resolved_version
      metadata=$(conan_cmake_metadata "${query}" "${profile}" "${cmake_target}" "${options[@]}") || return $?
      IFS=$'\t' read -r discovered_package discovered_target resolved_version <<< "${metadata}"
      if [[ -z "${ref}" ]]; then
        [[ "${resolved_version}" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]] \
          || die "${EXIT_DEP}" "Conan did not report an exact version for ${conan_name}"
        ref="${conan_name}/${resolved_version}"
      fi
      cmake_package="${cmake_package:-${discovered_package}}"
      cmake_target="${cmake_target:-${discovered_target}}"
    fi
  fi

  if (( $(mq '((.dependencies // {}) | length)') == 0 )); then
    warn "Conan recipes and CMake dependencies can run third-party code during builds."
  fi

  [[ -n "${ref}" ]] && fields+=("ref=${ref}")
  [[ -n "${url}" ]] && fields+=("url=${url}")
  [[ -n "${rev}" ]] && fields+=("rev=${rev}")
  [[ -n "${path}" ]] && fields+=("path=${path}")
  fields+=("cmake_target=${cmake_target}")
  [[ -z "${cmake_package}" ]] || fields+=("cmake_package=${cmake_package}")
  [[ -z "${port}" ]] || fields+=("port=${port}")
  [[ -z "${target}" ]] || fields+=("link_target=${target}")

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would add dependency '${name}' (${source}) to ${FORGE_MANIFEST_PATH}"
    return "${EXIT_OK}"
  fi

  local baseline="" root_manifest=""
  if [[ -n "${port_version}" ]]; then
    vcpkg_validate_version "${port}" "${port_version}" || return $?
    fields+=("version=${port_version}")
    local workspace_root
    workspace_root=$(workspace_enclosing_root "${FORGE_ROOT}") || return "${EXIT_CONFLICT}"
    root_manifest="${workspace_root}/Forge.toml"
    if [[ "${workspace_root}" == "${FORGE_ROOT}" ]]; then root_manifest="${FORGE_MANIFEST_PATH}"; fi
    local root_json
    root_json=$(manifest_to_json "${root_manifest}") || return "${EXIT_USAGE}"
    manifest_validate_json "${root_json}" || return "${EXIT_USAGE}"
    if [[ "$(jq -r '.build.vcpkg_baseline // empty' <<< "${root_json}")" == "" ]]; then
      baseline=$(vcpkg_registry_baseline) || return $?
      [[ ! -L "${root_manifest}" ]] || die "${EXIT_CONFLICT}" "refusing to edit symlinked ${root_manifest}"
      sync_check_destinations "${root_manifest%/*}"
      if [[ "${root_manifest}" == "${FORGE_MANIFEST_PATH}" ]]; then
        fields+=("vcpkg_baseline=${baseline}")
      else
        # Check the root edit before writing the member manifest.
        ( _manifest_read_lines "${root_manifest}"; _manifest_insert_vcpkg_baseline "${root_manifest}" "${baseline}" ) || return $?
      fi
    fi
  fi

  sync_check_destinations "${FORGE_ROOT}"
  progress "Updating Forge.toml"
  manifest_add_dependency "${FORGE_MANIFEST_PATH}" "${name}" "${source}" "${fields[@]}"
  if [[ -n "${baseline}" && "${root_manifest}" != "${FORGE_MANIFEST_PATH}" ]]; then
    manifest_set_vcpkg_baseline "${root_manifest}" "${baseline}"
  fi
  progress_finish
  [[ -z "${baseline}" ]] || status "recorded vcpkg registry baseline ${baseline} in ${root_manifest}"

  out "added dependency '${name}' to ${FORGE_MANIFEST_PATH}"

  # Git/path dependencies have no cmake_package, so the renderer treats them
  # as implicit links for targets with an empty links array. A target that
  # already has explicit links (for example a Conan shortcut added earlier)
  # would otherwise miss the new dependency, breaking mixed-project builds.
  # Explicitly link the new dependency into every such target as well.
  # A selected target (shortcut/vcpkg/--target) is already linked inside
  # manifest_add_dependency, and FORGE_MANIFEST_JSON is stale at this point.
  if [[ "${source}" == git || "${source}" == path ]] && [[ -z "${target}" ]]; then
    local linked_target json
    json=$(manifest_to_json "${FORGE_MANIFEST_PATH}") || return $?
    while IFS= read -r linked_target; do
      [[ -n "${linked_target}" ]] || continue
      manifest_link_existing_dependency "${FORGE_MANIFEST_PATH}" "${linked_target}" "${name}" \
        || return $?
      out "linked '${name}' to '${linked_target}'"
    done < <(printf '%s' "${json}" | jq -r '
      ((.bin // []) + (.lib // []) + (.test // []))[]
      | select(((.links // []) | length) > 0) | .name')
  fi

  add_sync_dependency "${source}"
}

# Read one required answer or use the supplied default.
add_prompt() {
  local field="$1" prompt="$2" fallback="$3" answer
  if [[ -n "${fallback}" ]]; then prompt+=" (${fallback})"; fi
  printf '%s: ' "${prompt}" >&2
  read -r answer || die "${EXIT_USAGE}" "input ended while asking for ${prompt} (see 'forge add --help')"
  answer="${answer:-${fallback}}"
  [[ -n "${answer}" && "${answer}" != -* ]] || die "${EXIT_USAGE}" "a value is required for ${prompt}"
  printf -v "${field}" '%s' "${answer}"
}

# Apply workspace changes before locking, so conflicts leave the prior lock intact.
add_sync_dependency() {
  local source="$1" answer="" prompt="Sync the workspace now?"
  if [[ "${source}" == conan ]]; then prompt="Sync the workspace and refresh the Conan lock now?"; fi
  if (( ! FORGE_YES )); then
    if [[ -t 0 || -p /dev/stdin || -f /dev/stdin ]]; then
      printf '%s [y/N] ' "${prompt}" >&2
      read -r answer || answer=""
    fi
    case "${answer}" in
      [yY] | [yY][eE][sS]) ;;
      *)
        out "To sync later, run 'forge sync --apply --yes' from the workspace root."
        if [[ "${source}" == conan ]]; then
          out "After syncing, refresh the Conan lock with 'forge deps lock' from the workspace root."
        fi
        return "${EXIT_OK}"
        ;;
    esac
  fi
  sync_after_manifest_edit || {
    local sync_status=$?
    fail "manifest edit saved; resolve the sync issue and run 'forge sync --apply'"
    return "${sync_status}"
  }
  if [[ "${source}" == conan ]]; then
    add_refresh_conan_lock || {
      local lock_status=$?
      fail "manifest edit and sync saved; run 'forge deps lock' from the workspace root"
      return "${lock_status}"
    }
  fi
}


# Keep lock failures separate from the manifest/sync transaction.
add_refresh_conan_lock() (
  # shellcheck disable=SC2034  # read by forge_cleanup_tmpdirs in the EXIT trap
  FORGE_TMP_DIRS=()
  trap forge_cleanup_tmpdirs EXIT
  manifest_load
  state_load
  if conan_lock_stale; then deps_lock; fi
)

# Select the sole local application/library, or a specifically named local target.
add_select_target() {
  local requested="$1" candidates root
  if [[ -n "${requested}" ]]; then
    [[ "${requested}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "${EXIT_USAGE}" "invalid target name"
    mq -e --arg target "${requested}" '
      ((.bin // []) + (.lib // []) + (.test // [])) | map(select(.name == $target)) | length == 1
    ' >/dev/null || die "${EXIT_USAGE}" "no unique local target named '${requested}'"
    printf '%s\n' "${requested}"
    return
  fi
  root=$(workspace_enclosing_root "${FORGE_ROOT}") || return "${EXIT_CONFLICT}"
  candidates=$(mq --arg root "${root}" --arg module "${FORGE_ROOT}" '
    if $root == $module and ((.bin // []) | length) == 1 then .bin
    else (.bin // []) + (.lib // []) end | .[].name
  ') || return "${EXIT_USAGE}"
  [[ -n "${candidates}" && "${candidates}" != *$'\n'* ]] \
    || die "${EXIT_USAGE}" "use --target NAME to select a local target"
  printf '%s\n' "${candidates}"
}
