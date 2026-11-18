# shellcheck shell=bash
# Forge command: sync.

# Check, preview, or apply workspace-wide generated changes.
cmd_sync() {
  local mode="" requested
  while (( $# > 0 )); do
    case "$1" in
      --check | --diff | --apply)
        requested="${1#--}"
        [[ -z "${mode}" || "${mode}" == "${requested}" ]] \
          || die "${EXIT_USAGE}" "choose one sync mode: --check, --diff or --apply"
        mode="${requested}"
        shift
        ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'sync': $1" ;;
      *) die "${EXIT_USAGE}" "sync accepts no positional arguments" ;;
    esac
  done

  case "${mode:-check}" in
    check)
      local rc=0
      sync_detect_drift || rc=$?
      if (( rc > 1 )); then
        die "${EXIT_CONFLICT}" "could not check Forge sync state"
      elif (( rc == 1 )); then
        local m
        for m in "${FORGE_SYNC_MESSAGES[@]}"; do out "pending: ${m}"; done
        die "${EXIT_CONFLICT}" "drift detected (exit 6)"
      fi
      out "in sync"
      ;;
    diff)
      local rc=0
      sync_detect_drift || rc=$?
      (( rc > 1 )) && die "${EXIT_CONFLICT}" "could not render templates"
      if (( rc == 0 )); then
        out "in sync"
      else
        sync_print_diff
      fi
      ;;
    apply)
      sync_apply || exit $?
      ;;
  esac
}
