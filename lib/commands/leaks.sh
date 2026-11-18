# shellcheck shell=bash
# Forge command: leaks — platform-appropriate leak checking for built targets.

FORGE_LEAKS_BUILD_DIR=""

# Build once for all leak checks in this invocation. macOS uses the normal
# entitled debug tree; Linux uses the isolated LeakSanitizer tree so the
# regular debug build stays untouched.
forge_leaks_prepare() {
  local os="$1" workspace
  workspace=$(workspace_enclosing_root "${FORGE_ROOT}") \
    || die "${EXIT_CONFLICT}" "could not find the enclosing workspace"
  if [[ "${workspace}" != "${FORGE_ROOT}" ]]; then
    # shellcheck disable=SC2034 # consumed by manifest_load
    FORGE_MANIFEST_PATH="${workspace%/}/Forge.toml"
    manifest_load
  fi
  if [[ "${os}" == Linux ]]; then
    forge_enable_sanitizer leak
  fi
  build_project debug "" || return $?
  FORGE_LEAKS_BUILD_DIR=$(resolve_build_dir debug) || return $?
}

# Check one built executable. Any leak report or checker failure is fatal so
# callers (including `forge test`) fail with the standard build/test code.
forge_leaks_check_target() {
  local build_dir="$1" name="$2" os="$3" rc=0 exe=""
  shift 3
  if exe=$(cmake_executable_path "${name}" "${build_dir}" 2>/dev/null); then
    :
  else
    exe=$(find_executable "${name}" "${build_dir}")
  fi
  [[ -n "${exe}" && -f "${exe}" && -x "${exe}" ]] \
    || die "${EXIT_BUILD}" "no built executable for '${name}' in ${build_dir#"${FORGE_ROOT}"/}"

  local -a cmd=()
  if [[ "${os}" == Darwin ]]; then
    cmd=(leaks -quiet -atExit -- "${exe}" "$@")
  else
    cmd=("${exe}" "$@")
  fi

  progress "Checking ${name} for leaks"
  run_cmd "${cmd[@]}" || rc=$?
  if (( rc == 0 )); then
    progress_finish
    out "no leaks detected in ${name}"
    return "${EXIT_OK}"
  fi

  progress_finish 1
  if [[ "${os}" == Darwin && "${rc}" -eq 1 ]]; then
    die "${EXIT_BUILD}" "leaks detected in '${name}' (run 'leaks -quiet -atExit -- ${exe}' for details)"
  fi
  die "${EXIT_BUILD}" "leak check failed for '${name}' (exit ${rc}; ${os} backend)"
}

# Check every declared application and test executable in the current module.
forge_leaks_check_all() {
  local os
  os=$(uname -s)
  case "${os}" in
    Darwin) require_tool leaks ;;
    Linux) : ;;
    *) return "${EXIT_OK}" ;;
  esac
  local -a names=()
  mapfile -t names < <(mq '((.bin // []) + (.test // []))[] | .name')
  (( ${#names[@]} )) || return "${EXIT_OK}"
  forge_leaks_prepare "${os}" || return $?
  local name
  for name in "${names[@]}"; do
    forge_leaks_check_target "${FORGE_LEAKS_BUILD_DIR}" "${name}" "${os}"
  done
}

cmd_leaks() {
  local bin="" test_name="" all=0 forward_seen=0 rc=0 os="" build_dir="" exe=""
  local -a forward=() candidates=() cmd=()
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
      --test)
        test_name="${2:-}"
        [[ -n "${test_name}" && "${test_name}" != -* ]] || die "${EXIT_USAGE}" "--test requires a value"
        shift 2
        ;;
      --test=*)
        test_name="${1#*=}"
        [[ -n "${test_name}" ]] || die "${EXIT_USAGE}" "--test requires a value"
        shift
        ;;
      --all) all=1; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'leaks': $1" ;;
      *) die "${EXIT_USAGE}" "use '--' to forward arguments to the program" ;;
    esac
  done
  [[ -z "${bin}" || "${bin}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid executable name: ${bin}"
  [[ -z "${test_name}" || "${test_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid test target name: ${test_name}"
  if (( all )) && { [[ -n "${bin}" ]] || [[ -n "${test_name}" ]]; }; then
    die "${EXIT_USAGE}" "--all cannot be combined with --bin or --test"
  fi

  manifest_load
  if [[ -n "${test_name}" ]]; then
    mq -e --arg name "${test_name}" 'any((.test // [])[]; .name == $name)' >/dev/null \
      || die "${EXIT_USAGE}" "no such test target: ${test_name}"
  elif [[ -z "${bin}" && "${all}" == 0 ]]; then
    mapfile -t candidates < <(mq '(.bin // [])[] | .name')
    case "${#candidates[@]}" in
      0) die "${EXIT_BUILD}" "no executable targets declared in this module (use --bin NAME)" ;;
      1) bin="${candidates[0]}" ;;
      *) die "${EXIT_USAGE}" "multiple executables found: ${candidates[*]} (use --bin NAME)" ;;
    esac
  fi

  os=$(uname -s)
  case "${os}" in
    Darwin) require_tool leaks ;;
    Linux) : ;;
    *) die "${EXIT_TOOL}" "'forge leaks' supports macOS and Linux only (found ${os})" ;;
  esac

  if (( FORGE_DRY_RUN )); then
    local backend="LeakSanitizer" what="${bin:-${test_name:-all declared targets}}"
    [[ "${os}" != Darwin ]] || backend="leaks"
    status "dry-run: would build debug and check ${what} for leaks (${backend})"
    return "${EXIT_OK}"
  fi

  if (( all )); then
    forge_leaks_check_all
    return $?
  fi
  forge_leaks_prepare "${os}" || return $?
  forge_leaks_check_target "${FORGE_LEAKS_BUILD_DIR}" "${bin:-${test_name}}" "${os}" "${forward[@]}"
}
