# shellcheck shell=bash
# Forge command: clean.

# Require the build directory to resolve to its exact location under target.
_clean_safe_dir() {
  local d="$1" real treal
  [[ -L "${FORGE_ROOT}/target" || -L "${d}" ]] && return 1
  path_is_safe_relative "${d#"${FORGE_ROOT}/target/"}" || return 1
  real=$(cd "${d}" 2>/dev/null && pwd -P) || return 1
  treal=$(cd "${FORGE_ROOT}/target" 2>/dev/null && pwd -P) || return 1
  [[ "${real}" == "${treal}/${d#"${FORGE_ROOT}/target/"}" ]]
}

# Remove selected build directories after validating their paths.
cmd_clean() {
  local profile="" all=0 rc=0
  while (( $# > 0 )); do
    case "$1" in
      --profile) profile="${2:-}"; [[ -n "${profile}" ]] || die "${EXIT_USAGE}" "--profile requires a value"; shift 2 ;;
      --profile=*) profile="${1#*=}"; [[ -n "${profile}" ]] || die "${EXIT_USAGE}" "--profile requires a value"; shift ;;
      --all) all=1; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'clean': $1" ;;
      *) die "${EXIT_USAGE}" "clean accepts no positional arguments" ;;
    esac
  done
  [[ -z "${profile}" || "${profile}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] \
    || die "${EXIT_USAGE}" "invalid profile name: ${profile}"

  require_project
  manifest_load
  local target_dir="${FORGE_ROOT}/target"
  [[ ! -L "${target_dir}" ]] || die "${EXIT_CONFLICT}" "refusing unsafe path: ${target_dir}"
  [[ -d "${target_dir}" ]] || { out "nothing to clean"; return "${EXIT_OK}"; }

  local -a dirs=() d
  if (( all )); then
    for d in "${target_dir}"/*; do
      [[ -d "${d}" ]] && dirs+=("${d}")
    done
    (( ${#dirs[@]} )) || { out "nothing to clean"; return "${EXIT_OK}"; }
    confirm_action "Delete all build directories under target/?" \
      || die "${EXIT_CONFLICT}" "clean aborted"
  elif [[ -n "${profile}" ]]; then
    for d in "${target_dir}/${profile}" "${target_dir}/${profile}-"* "${target_dir}/sanitizers/"*/"${profile}"; do
      [[ -d "${d}" ]] && dirs+=("${d}")
    done
  else
    d=$(resolve_build_dir "${profile}")
    [[ -d "${d}" ]] && dirs+=("${d}")
  fi

  (( ${#dirs[@]} )) || { out "nothing to clean"; return "${EXIT_OK}"; }

  for d in "${dirs[@]}"; do
    if ! _clean_safe_dir "${d}"; then
      fail "refusing unsafe path: ${d}"
      rc="${EXIT_CONFLICT}"
      continue
    fi
    local lock
    lock=$(build_lock_path "${d}")
    if [[ -d "${lock}" ]] ||
      { [[ "${d}" == "${target_dir}/sanitizers" ]] &&
        [[ -n "$(find "${d}" -name '.*.forge-lock' -type d -print -quit)" ]]; }; then
      fail "refusing to clean an active build: ${d}"
      rc="${EXIT_CONFLICT}"
      continue
    fi
    if (( FORGE_DRY_RUN )); then
      status "dry-run: would delete ${d#"${FORGE_ROOT}"/}"
    else
      progress "Removing ${d}"
      rm -rf -- "${d}" || die "${EXIT_OTHER}" "could not delete ${d}"
      progress_finish
      out "deleted ${d#"${FORGE_ROOT}"/}"
    fi
  done
  return "${rc}"
}
