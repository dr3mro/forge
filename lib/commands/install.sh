# shellcheck shell=bash
# Forge commands for a per-user installation created by install.sh.

# Refresh the per-user checkout through the installer.
cmd_update() {
  manage_installation update "$@"
}

# Remove the per-user checkout through the uninstaller.
cmd_uninstall() {
  manage_installation uninstall "$@"
}

# Validate installation commands and delegate to the lifecycle scripts.
manage_installation() {
  local action="$1"
  shift
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cmd_help
    return
  fi
  (( $# == 0 )) || die "${EXIT_USAGE}" "usage: forge ${action}"
  [[ -f "${FORGE_HOME}/.git/forge-install" ]] \
    || die "${EXIT_CONFLICT}" "forge ${action} requires an installation made by install.sh"
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would ${action} Forge at ${FORGE_HOME}"
    return
  fi
  if [[ "${action}" == update ]]; then
    [[ -f "${FORGE_HOME}/.git/forge-source" ]] || (( ! FORGE_OFFLINE )) || die "${EXIT_DEP}" "forge update requires a connection to its Git source"
    exec sh "${FORGE_HOME}/install.sh" --update
  fi
  exec sh "${FORGE_HOME}/uninstall.sh"
}
