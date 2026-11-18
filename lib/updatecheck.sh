# shellcheck shell=bash
# Periodic update check (at most once per interval) for installed Forge.
# API: update_check_periodic.
# Inputs: FORGE_HOME, FORGE_QUIET, FORGE_OFFLINE, FORGE_DRY_RUN,
#         FORCE_UPDATE_CHECK (test hook), XDG_CACHE_HOME/HOME.
# Outputs: an optional notice on stderr. No manifest or project side effects.

# Check the installation's Git source for a newer release, at most once per
# day. Runs only for interactive terminals so machine-readable output stays
# clean. FORCE_UPDATE_CHECK=1 bypasses the TTY gate for tests.
update_check_periodic() {
  (( FORGE_QUIET || FORGE_OFFLINE || FORGE_DRY_RUN )) && return 0
  [[ -t 1 || "${FORCE_UPDATE_CHECK:-0}" == 1 ]] || return 0
  [[ "${FORGE_NO_UPDATE_CHECK:-0}" != 1 ]] || return 0

  local cache_dir="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/forge"
  local stamp="${cache_dir}/last-update-check"
  local interval="${FORGE_UPDATE_INTERVAL:-86400}"
  local now last source installed latest
  now=$(date +%s) || return 0
  if [[ -f "${stamp}" ]]; then
    IFS= read -r last < "${stamp}" || last=0
    [[ "${last}" =~ ^[0-9]+$ ]] || last=0
    (( now - last < interval )) && return 0
  fi
  mkdir -p "${cache_dir}" 2>/dev/null || return 0
  printf '%s\n' "${now}" > "${stamp}" 2>/dev/null || return 0

  [[ -f "${FORGE_HOME}/.git/forge-source" ]] || return 0
  IFS= read -r source < "${FORGE_HOME}/.git/forge-source" || return 0
  [[ "${source}" == http* || "${source}" == git@* ]] || return 0
  IFS= read -r installed < "${FORGE_HOME}/.git/forge-version" || installed=''

  latest=$(timeout 6 git ls-remote --tags --refs "${source}" 2>/dev/null \
    | awk -F/ '{t=$NF; sub(/^v/, "", t); if (t ~ /^[0-9]/) print t}' \
    | sort -V | tail -1)
  [[ -n "${latest}" && "${latest}" != "${installed}" ]] || return 0
  status "forge ${latest} is available (installed ${installed:-unknown}); run 'forge update'"
}
