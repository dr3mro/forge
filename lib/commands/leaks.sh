# shellcheck shell=bash
# Forge command: leaks — platform-appropriate leak checking for a debug app.

# Select the application to check, then build and inspect it. On macOS this
# uses the native `leaks` tool against the normal entitled debug build; on
# Linux it uses Forge's LeakSanitizer build. Arguments after `--` are forwarded
# unchanged to both the application and, on macOS, to `leaks` via `--`.
cmd_leaks() {
  local bin="" forward_seen=0 rc=0 os="" build_dir="" exe="" workspace=""
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
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'leaks': $1" ;;
      *) die "${EXIT_USAGE}" "use '--' to forward arguments to the program" ;;
    esac
  done
  [[ -z "${bin}" || "${bin}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid executable name: ${bin}"

  manifest_load
  if [[ -z "${bin}" ]]; then
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
    local backend="LeakSanitizer"
    [[ "${os}" != Darwin ]] || backend="leaks"
    status "dry-run: would build debug and check ${bin} for leaks (${backend})"
    return "${EXIT_OK}"
  fi

  workspace=$(workspace_enclosing_root "${FORGE_ROOT}") \
    || die "${EXIT_CONFLICT}" "could not find the enclosing workspace"
  if [[ "${workspace}" != "${FORGE_ROOT}" ]]; then
    # shellcheck disable=SC2034 # consumed by manifest_load
    FORGE_MANIFEST_PATH="${workspace%/}/Forge.toml"
    manifest_load
  fi

  # Linux has no native `leaks`; LSan needs an instrumented build. Keep it in
  # the standard isolated sanitizer tree so the normal debug build is intact.
  if [[ "${os}" == Linux ]]; then
    forge_enable_sanitizer leak
  fi
  build_project debug "" || return $?
  build_dir=$(resolve_build_dir debug) || return $?

  if exe=$(cmake_executable_path "${bin}" "${build_dir}" 2>/dev/null); then
    :
  else
    exe=$(find_executable "${bin}" "${build_dir}")
  fi
  [[ -n "${exe}" && -f "${exe}" && -x "${exe}" ]] \
    || die "${EXIT_BUILD}" "no built executable for '${bin}' in ${build_dir#"${FORGE_ROOT}"/}"

  if [[ "${os}" == Darwin ]]; then
    cmd=(leaks -quiet -atExit -- "${exe}" "${forward[@]}")
  else
    cmd=("${exe}" "${forward[@]}")
  fi

  progress "Checking ${bin} for leaks"
  run_cmd "${cmd[@]}" || rc=$?
  if (( rc == 0 )); then
    progress_finish
    out "no leaks detected"
    return "${EXIT_OK}"
  fi

  progress_finish 1
  if [[ "${os}" == Darwin && "${rc}" -eq 1 ]]; then
    die "${EXIT_BUILD}" "leaks detected in '${bin}' (run 'leaks -quiet -atExit -- ${exe}' for details)"
  fi
  die "${EXIT_BUILD}" "leak check failed for '${bin}' (exit ${rc}; ${os} backend)"
}
