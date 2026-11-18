# shellcheck shell=bash
# Forge command: generate (Phase 4 workspace members).

# Scaffold a workspace member and register it in the parent manifest.
cmd_generate() {
  local kind="${1:-}" name="${2:-}" subdir dest extension=cpp cpp_namespace="" linkage=""
  if [[ "${kind}" == --help || "${kind}" == -h ]]; then
    cmd_help generate
    return
  fi
  if [[ "${name}" == --help || "${name}" == -h ]]; then
    cmd_help generate "${kind}"
    return
  fi
  (( $# >= 2 )) || die "${EXIT_USAGE}" "usage: forge generate lib|bin NAME [--c|--cpp] [--namespace NAME]"
  shift 2
  while (( $# )); do
    case "$1" in
      --cpp) extension=cpp ;;
      --c) extension=c ;;
      --static|--shared|--dynamic)
        local requested_linkage="${1#--}"
        if [[ "${requested_linkage}" == dynamic ]]; then requested_linkage=shared; fi
        [[ -z "${linkage}" || "${linkage}" == "${requested_linkage}" ]] \
          || die "${EXIT_USAGE}" "choose either --static or --shared"
        linkage="${requested_linkage}" ;;
      --namespace)
        [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "--namespace requires a value"
        cpp_namespace="$2"
        shift ;;
      --help|-h) cmd_help generate "${kind}"; return ;;
      *) die "${EXIT_USAGE}" "unknown generate option: $1" ;;
    esac
    shift
  done
  [[ "${kind}" == lib || "${extension}" == cpp ]] \
    || die "${EXIT_USAGE}" "--c is available for generated libraries"
  case "${kind}" in
    lib | bin) ;;
    *) die "${EXIT_USAGE}" "generate requires KIND 'lib' or 'bin'" ;;
  esac
  [[ -n "${name}" ]] || die "${EXIT_USAGE}" "generate requires a NAME"
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid member name: ${name}"

  [[ "${kind}" == lib || -z "${linkage}" ]] \
    || die "${EXIT_USAGE}" "--static and --shared are available for libraries"
  if [[ "${kind}" == lib && "${extension}" == cpp ]]; then
    cpp_namespace="${cpp_namespace:-${name}}"
    validate_cpp_namespace "${cpp_namespace}"
  elif [[ -n "${cpp_namespace}" ]]; then
    die "${EXIT_USAGE}" "--namespace is available for C++ libraries"
  fi

  require_project
  manifest_load
  if [[ "${kind}" == "lib" ]]; then
    subdir="libs/${name}"
  else
    subdir="bins/${name}"
  fi
  dest="${FORGE_ROOT}/${subdir}"
  [[ ! -e "${dest}" && ! -L "${dest}" ]] \
    || die "${EXIT_CONFLICT}" "refusing to overwrite: ${dest}"

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would generate ${kind} member '${name}' at ${subdir}"
    return "${EXIT_OK}"
  fi

  sync_check_destinations "${FORGE_ROOT}"
  local member_parent="${dest%/*}"
  [[ ! -L "${member_parent}" ]] || die "${EXIT_CONFLICT}" "refusing to use a symlinked member directory: ${member_parent}"
  local saved_root="${FORGE_ROOT}" saved_manifest="${FORGE_MANIFEST_PATH}" author_line
  author_line=$(project_author_line)
  scaffold_project "${dest}" "${name}" "${kind}" 0 "0.1.0" "" "${author_line}" "${extension}" "${cpp_namespace}" "${linkage}" 0
  FORGE_ROOT="${saved_root}"
  FORGE_MANIFEST_PATH="${saved_manifest}"

  manifest_add_workspace_member "${FORGE_MANIFEST_PATH}" "${subdir}"
  if [[ "${kind}" == "lib" ]]; then
    manifest_add_link_to_targets "${FORGE_MANIFEST_PATH}" "${name}"
  fi
  out "generated ${kind} member '${name}' at ${subdir}"
  sync_after_manifest_edit
}
