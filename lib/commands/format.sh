# shellcheck shell=bash
# Forge command: fmt / metadata (Phase 3).

# Run clang-format in write or check mode on project sources.
cmd_fmt() {
  local check=0
  while (( $# > 0 )); do
    case "$1" in
      --check) check=1; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'fmt': $1" ;;
      *) die "${EXIT_USAGE}" "fmt accepts no positional arguments" ;;
    esac
  done

  manifest_load
  require_tool clang-format

  local -a files=() unique=() f d
  local -A seen=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && files+=("${f}")
  done < <(mq '((.bin // []) + (.lib // []) + (.test // []) | .[].path)')
  while IFS= read -r d; do
    [[ -n "${d}" ]] || continue
    while IFS= read -r f; do
      files+=("${f#"${FORGE_ROOT}"/}")
    done < <(find "${FORGE_ROOT}/${d}" -type f \
      \( -name '*.c' -o -name '*.cpp' -o -name '*.hpp' -o -name '*.cc' -o -name '*.h' -o -name '*.cxx' \) 2>/dev/null | sort)
  done < <(
    {
      printf '%s\n' src include tests
      mq '((.dependencies // {}) | to_entries[] | select(.value.source == "path") | .value.path)'
    }
  )

  for f in "${files[@]}"; do
    [[ -n "${seen[${f}]+x}" ]] && continue
    seen["${f}"]=1
    unique+=("${f}")
  done
  (( ${#unique[@]} )) || { out "no source files to format"; return "${EXIT_OK}"; }

  if (( FORGE_DRY_RUN )); then
    local action=format
    if (( check )); then action="check format for"; fi
    status "dry-run: would ${action} ${#unique[@]} file(s)"
    return "${EXIT_OK}"
  fi
  local -a style_args=()
  [[ -f "${FORGE_ROOT}/.clang-format" ]] && style_args=(--style=file)

  progress "Running clang-format"
  if (( check )); then
    (cd "${FORGE_ROOT}" && clang-format "${style_args[@]}" --dry-run --Werror "${unique[@]}") \
      || die "${EXIT_BUILD}" "format check failed"
    progress_finish
    out "format check ok (${#unique[@]} files)"
  else
    (cd "${FORGE_ROOT}" && clang-format "${style_args[@]}" -i "${unique[@]}") \
      || die "${EXIT_OTHER}" "clang-format failed"
    progress_finish
    out "formatted ${#unique[@]} file(s)"
  fi
}

# Emit machine-readable project metadata.
cmd_metadata() {
  local format="json"
  while (( $# > 0 )); do
    case "$1" in
      --format) [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; format="${2:-}"; shift 2 ;;
      --format=*) format="${1#*=}"; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'metadata': $1" ;;
      *) die "${EXIT_USAGE}" "metadata accepts no positional arguments" ;;
    esac
  done
  [[ "${format}" == "json" ]] \
    || die "${EXIT_USAGE}" "metadata only supports --format json"

  manifest_load
  local pkg targets deps profile build_dir lock_state rc=0
  pkg=$(mq_json '{name: .package.name, version: .package.version, cppstd: .package.cppstd}')
  targets=$(mq_json '
    [((.bin // []) | map({kind: "bin", name: .name, path: .path, links: (.links // [])}))
     + ((.lib // []) | map({kind: "lib", name: .name, path: .path, links: (.links // [])}))
     + ((.test // []) | map({kind: "test", name: .name, path: .path, links: (.links // [])}))]')
  deps=$(mq_json '
    [((.dependencies // {}) | to_entries[] |
      {name: .key, source: .value.source, cmake_target: .value.cmake_target})]')
  profile=$(mq '.build.default_profile // "debug"')
  build_dir=$(resolve_build_dir "${profile}")
  lock_state="absent"
  [[ -f "${FORGE_ROOT}/conan.lock" ]] && lock_state="present"
  sync_detect_drift || rc=$?
  (( rc <= 1 )) || die "${EXIT_CONFLICT}" "could not check Forge sync state"
  local sync_state="clean"
  (( rc == 1 )) && sync_state="drift"

  jq -n \
    --arg version "${FORGE_VERSION}" \
    --argjson pkg "${pkg}" \
    --argjson targets "${targets}" \
    --argjson deps "${deps}" \
    --arg profile "${profile}" \
    --arg build_dir "${build_dir#"${FORGE_ROOT}"/}" \
    --arg lock "${lock_state}" \
    --arg sync "${sync_state}" \
    '{
      schema: 1,
      forge_version: $version,
      package: $pkg,
      build: {profile: $profile, build_dir: $build_dir, conan_lock: $lock, manifest_sync: $sync},
      targets: $targets,
      dependencies: $deps
    }'
}
