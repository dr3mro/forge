# shellcheck shell=bash
# shellcheck disable=SC2034  # runtime globals are consumed by command modules
# Forge CLI — global flag parsing and command dispatch.
# API: forge_main.
# Inputs: process arguments; globals from bin/forge.
# Outputs: dispatches to cmd_* functions; exits with frozen codes.
# Side effects: none beyond dispatched command.

# Parse global flags and dispatch the requested command.
forge_main() {
  if [[ "${1:-}" == __complete ]]; then
    shift
    reference_complete "$@"
    return
  fi
  ui_init
  local -a args=("$@") cmd_args=()
  local manifest_path="" seen_cmd=0 a

  # Global flags may appear before or after the command (matching the command
  # contracts, e.g. `sync --apply --yes`). Parsing stops at '--', which belongs
  # to the command (used by `run` to forward arguments exactly).
  while (( ${#args[@]} > 0 )); do
    a="${args[0]}"
    case "${a}" in
      --)
        cmd_args+=("${args[@]}")
        break
        ;;
      --manifest-path)
        manifest_path="${args[1]:-}"
        [[ -n "${manifest_path}" ]] || die "${EXIT_USAGE}" "--manifest-path requires a value"
        args=("${args[@]:2}")
        ;;
      --manifest-path=*)
        manifest_path="${a#*=}"
        [[ -n "${manifest_path}" ]] || die "${EXIT_USAGE}" "--manifest-path requires a value"
        args=("${args[@]:1}")
        ;;
      --quiet | -q)      FORGE_QUIET=1;    args=("${args[@]:1}") ;;
      --verbose | -v)    FORGE_VERBOSE=1;  args=("${args[@]:1}") ;;
      --no-color)        FORGE_NO_COLOR=1; ui_init; args=("${args[@]:1}") ;;
      --force-color)     FORGE_FORCE_COLOR=1; ui_init; args=("${args[@]:1}") ;;
      --dry-run)         FORGE_DRY_RUN=1;  args=("${args[@]:1}") ;;
      --offline)         FORGE_OFFLINE=1;  args=("${args[@]:1}") ;;
      --yes | -y)        FORGE_YES=1;      args=("${args[@]:1}") ;;
      --help | -h)
        if (( seen_cmd )); then
          reference_help_for "${cmd_args[0]}" "${cmd_args[1]:-}"
          return
        else
          cmd_help; return "${EXIT_OK}"
        fi
        ;;
      --version | -V)
        if (( seen_cmd )); then
          cmd_args+=("${a}"); args=("${args[@]:1}"); seen_cmd=1
        else
          cmd_version; return "${EXIT_OK}"
        fi
        ;;
      -*)
        if (( seen_cmd )); then
          cmd_args+=("${a}"); args=("${args[@]:1}")
        else
          die "${EXIT_USAGE}" "unknown global flag: ${a} (see 'forge help')"
        fi
        ;;
      *)
        cmd_args+=("${a}"); args=("${args[@]:1}"); seen_cmd=1
        ;;
    esac
  done

  [[ -n "${manifest_path}" ]] && FORGE_MANIFEST_PATH="${manifest_path}"

  local cmd="${cmd_args[0]:-help}"
  local -a rest=("${cmd_args[@]:1}")
  local fn="cmd_${cmd}"

  declare -F "${fn}" >/dev/null 2>&1 \
    || die "${EXIT_USAGE}" "unknown command: ${cmd} (see 'forge help')"
  "${fn}" "${rest[@]}"
}
