# shellcheck shell=bash
# Forge command: add (dependency).

# Validate a dependency, edit its module manifest, and apply workspace sync.
cmd_add() {
  local name="" source="" ref="" url="" rev="" tag="" branch="" path=""
  local cmake_target="" cmake_package="" shortcut="" target="" port="" conan_name=""
  local -a options=() fields=()
  while (( $# > 0 )); do
    case "$1" in
      --conan | --vcpkg)
        [[ -z "${shortcut}" || "${shortcut}" == "${1#--}" ]] \
          || die "${EXIT_USAGE}" "--conan and --vcpkg cannot be combined"
        shortcut="${1#--}"
        shift
        ;;
      --source | --ref | --url | --rev | --sha | --tag | --branch | --path | --cmake-target | --cmake-package | --target | --option)
        [[ -n "${2:-}" && "$2" != --* ]] || die "${EXIT_USAGE}" "$1 requires a value"
        case "$1" in
          --source) source="$2" ;;
          --ref) ref="$2" ;;
          --url) url="$2" ;;
          --rev | --sha) rev="$2" ;;
          --tag) tag="$2" ;;
          --branch) branch="$2" ;;
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
    die "${EXIT_USAGE}" "--target requires --conan or --vcpkg"
  fi
  if [[ "${source}" == conan || "${source}" == vcpkg ]]; then
    [[ -z "${url}${rev}${tag}${branch}${path}" ]] \
      || die "${EXIT_USAGE}" "Git and path flags conflict with ${source}"
  elif [[ -n "${cmake_package}" ]]; then
    die "${EXIT_USAGE}" "--cmake-package requires Conan or vcpkg"
  fi
  if [[ "${shortcut}" == conan ]]; then
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
    [[ "${name}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "${EXIT_USAGE}" "invalid vcpkg port: ${name}"
    [[ -z "${ref}" && ${#options[@]} -eq 0 ]] \
      || die "${EXIT_USAGE}" "vcpkg ports use the installed registry revision"
    port="${name}"
    name="${name//-/_}"
    [[ "${name}" != [0-9]* ]] || name="vcpkg_${name}"
    cmake_package="${cmake_package:-${port}}"
    if [[ "${port}" == fmt ]]; then cmake_target="${cmake_target:-fmt::fmt}"; fi
  fi
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid dependency name: ${name}"
  [[ "${shortcut}" == conan || -n "${cmake_target}" ]] || die "${EXIT_USAGE}" "add requires --cmake-target"

  manifest_load
  deps_check_collisions || die "${EXIT_DEP}" "dependency collisions detected"
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
    status "dry-run: would add '${ref:-${port:-${name}}}' (${source}) to ${FORGE_MANIFEST_PATH} and link '${target}'"
    return "${EXIT_OK}"
  fi
  if [[ -n "${target}" ]] && mq -e --arg name "${name}" '.dependencies[$name] != null' >/dev/null; then
    local requested_options
    requested_options=$(printf '%s\n' "${options[@]}" | jq -Rn '[inputs | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$")] | from_entries')
    mq -e --arg name "${name}" --arg source "${source}" --arg ref "${ref}" --arg port "${port}" \
      --arg imported "${cmake_target}" --arg package "${cmake_package}" --argjson options "${requested_options}" '
        .dependencies[$name] as $d
        | $d.source == $source and (($d.ref // "") == $ref) and (($d.port // "") == $port)
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
    sync_after_manifest_edit
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

  if [[ "${source}" == "git" && -z "${rev}" && ( -n "${tag}" || -n "${branch}" ) ]]; then
    (( FORGE_OFFLINE )) \
      && die "${EXIT_DEP}" "--offline cannot resolve a tag/branch; use 'forge deps pin' with --sha"
    url="${url:-$(mq --arg n "${name}" '(.dependencies // {})[$n].url // empty')}"
    [[ -n "${url}" ]] || die "${EXIT_USAGE}" "git dependency needs --url"
    require_tool git
    rev=$(fetchcontent_resolve_ref "${url}" "${tag:-${branch}}")
    status "resolved ${tag:-${branch}} -> ${rev}"
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

  sync_check_destinations "${FORGE_ROOT}"
  progress "Updating Forge.toml"
  manifest_add_dependency "${FORGE_MANIFEST_PATH}" "${name}" "${source}" "${fields[@]}"

  out "added dependency '${name}' to ${FORGE_MANIFEST_PATH}"
  sync_after_manifest_edit || {
    local sync_status=$?
    fail "manifest edit saved; resolve the sync issue and run 'forge sync --apply'"
    return "${sync_status}"
  }
  if [[ "${source}" == conan ]]; then
    status "Run 'forge deps lock' from ${FORGE_ROOT} before building."
  fi
}


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
