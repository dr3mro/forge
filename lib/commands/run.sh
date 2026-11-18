# shellcheck shell=bash
# Forge command: run.

# Locate and launch the selected built executable.
cmd_run() {
  local bin="" profile="" forward_seen=0
  local -a forward=()
  while (( $# > 0 )); do
    if (( forward_seen )); then
      forward+=("$1"); shift
      continue
    fi
    case "$1" in
      --) forward_seen=1; shift ;;
      --bin)
        bin="${2:-}"
        [[ -n "${bin}" && "${bin}" != -* ]] || die "${EXIT_USAGE}" "--bin requires a value"
        shift 2
        ;;
      --bin=*)
        bin="${1#*=}"
        [[ -n "${bin}" ]] || die "${EXIT_USAGE}" "--bin requires a value"
        shift
        ;;
      --release | --debug)
        [[ -z "${profile}" || "${profile}" == "${1#--}" ]] \
          || die "${EXIT_USAGE}" "--release and --debug cannot be combined"
        profile="${1#--}"
        shift
        ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'run': $1" ;;
      *) die "${EXIT_USAGE}" "use '--' to forward arguments to the program" ;;
    esac
  done

  [[ -z "${bin}" || "${bin}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid executable name: ${bin}"
  manifest_load
  [[ -n "${profile}" ]] || profile=$(mq '.build.default_profile // "debug"')
  local workspace build_dir exe="" found_build=0 known_target=0
  local -a build_dirs=() candidates=()
  build_dirs+=("$(resolve_build_dir "${profile}")")
  workspace=$(workspace_enclosing_root "${FORGE_ROOT}") \
    || die "${EXIT_CONFLICT}" "could not find the enclosing workspace"
  if [[ "${workspace}" != "${FORGE_ROOT}" ]]; then
    local workspace_build
    workspace_build=$(
      # shellcheck disable=SC2034 # consumed by manifest_load
      FORGE_MANIFEST_PATH="${workspace%/}/Forge.toml"
      manifest_load
      resolve_build_dir "${profile}"
    ) || return $?
    build_dirs+=("${workspace_build}")
  fi

  if [[ -z "${bin}" ]]; then
    mapfile -t candidates < <(mq '(.bin // [])[] | .name')
    case "${#candidates[@]}" in
      0) die "${EXIT_BUILD}" "no executable targets declared in this module" ;;
      1) bin="${candidates[0]}" ;;
      *) die "${EXIT_USAGE}" "multiple executables found: ${candidates[*]} (use --bin NAME)" ;;
    esac
    known_target=1
  elif mq -e --arg bin "${bin}" 'any((.bin // [])[]; .name == $bin)' >/dev/null; then
    known_target=1
  fi

  for build_dir in "${build_dirs[@]}"; do
    [[ -d "${build_dir}" ]] || continue
    found_build=1
    if exe=$(cmake_executable_path "${bin}" "${build_dir}" 2>/dev/null); then
      known_target=1
    elif (( known_target )); then
      exe=$(find_executable "${bin}" "${build_dir}")
    fi
    [[ -n "${exe}" && -f "${exe}" && -x "${exe}" ]] && break
    exe=""
  done
  if (( ! found_build )); then
    local build_hint="forge build --debug-target ${bin}"
    [[ "${profile}" != release ]] || build_hint="forge build --release"
    die "${EXIT_BUILD}" "project is not built for '${profile}' (run '${build_hint}')"
  fi
  (( known_target )) || die "${EXIT_USAGE}" "no such executable: ${bin}"
  [[ -n "${exe}" ]] || die "${EXIT_BUILD}" "executable '${bin}' is not built for '${profile}'"

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would run ${exe} ${forward[*]:-}"
    return "${EXIT_OK}"
  fi
  exec "${exe}" "${forward[@]}"
}
