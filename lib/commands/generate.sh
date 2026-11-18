# shellcheck shell=bash
# Forge command: generate (Phase 4 workspace members).

# Use the root package name even when generating inside a nested member.
workspace_application_namespace() {
  local root json
  root=$(workspace_enclosing_root "${FORGE_ROOT}") || return 1
  if [[ "${root}" == "${FORGE_ROOT}" ]]; then
    mq '.package.name'
  else
    json=$(manifest_to_json "${root}/Forge.toml") || return 1
    jq -er '.package.name' <<< "${json}"
  fi
}

# Use the root C++ standard even when generating inside a nested member.
workspace_application_cppstd() {
  local root json value
  root=$(workspace_enclosing_root "${FORGE_ROOT}") || return 1
  if [[ "${root}" == "${FORGE_ROOT}" ]]; then
    value=$(mq '.package.cppstd // "20"')
  else
    json=$(manifest_to_json "${root}/Forge.toml") || return 1
    value=$(jq -er '.package.cppstd // "20"' <<< "${json}") || return 1
  fi
  [[ "${value}" =~ ^(17|20|23)$ ]] || value=20
  printf '%s' "${value}"
}

# Write a standalone C++ class pair without creating a library or manifest edits.
generate_class() {
  local name="$1" path="${2:-.}" cpp_namespace="$3" dest header source author_line
  local tpl="${FORGE_HOME}/templates/base"
  if [[ "${path}" == /* ]]; then
    dest="${path}"
  else
    path_is_safe_relative "${path}" || die "${EXIT_USAGE}" "unsafe class path: ${path}"
    dest="${PWD}/${path}"
  fi
  [[ ! -L "${dest}" ]] || die "${EXIT_CONFLICT}" "refusing to use a symlinked class directory: ${dest}"
  mkdir -p -- "${dest}" || die "${EXIT_OTHER}" "could not create ${dest}"
  header="${dest}/${name}.hpp"
  source="${dest}/${name}.cpp"
  [[ ! -e "${header}" && ! -L "${header}" ]] || die "${EXIT_CONFLICT}" "refusing to overwrite: ${header}"
  [[ ! -e "${source}" && ! -L "${source}" ]] || die "${EXIT_CONFLICT}" "refusing to overwrite: ${source}"
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would generate class '${name}' in ${dest}"
    return "${EXIT_OK}"
  fi
  author_line=$(project_author_line)
  scaffold_source_file "${tpl}/class.hpp.tpl" "${header}" "${name}" "${author_line}" "${cpp_namespace}"
  scaffold_source_file "${tpl}/class.cpp.tpl" "${source}" "${name}" "${author_line}" "${cpp_namespace}"
  out "generated class '${name}' in ${dest}"
}

# Scaffold a workspace member and register it in the parent manifest.
cmd_generate() {
  local kind="${1:-}" name="${2:-}" subdir dest extension=cpp cpp_namespace="" linkage="" cppstd=""
  local -a class_path=()
  if [[ "${kind}" == --help || "${kind}" == -h ]]; then
    cmd_help generate
    return
  fi
  if [[ "${name}" == --help || "${name}" == -h ]]; then
    cmd_help generate "${kind}"
    return
  fi
  (( $# >= 2 )) || die "${EXIT_USAGE}" "usage: forge generate lib|bin NAME [--c|--cpp] [--namespace NAME] [--cppstd 17|20|23]"
  shift 2
  while (( $# )); do
    case "$1" in
      --cpp) extension=cpp ;;
      --c) extension=c ;;
      --cppstd)
        [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "--cppstd requires a value"
        [[ "$2" =~ ^(17|20|23)$ ]] || die "${EXIT_USAGE}" "--cppstd must be 17, 20 or 23"
        cppstd="$2"; shift ;;
      --cppstd=*)
        cppstd="${1#*=}"
        [[ "${cppstd}" =~ ^(17|20|23)$ ]] || die "${EXIT_USAGE}" "--cppstd must be 17, 20 or 23"
        shift ;;
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
      *)
        if [[ "${kind}" == class && ${#class_path[@]} -eq 0 && "$1" != -* ]]; then
          class_path+=("$1")
        else
          die "${EXIT_USAGE}" "unknown generate option: $1"
        fi ;;
    esac
    shift
  done
  if [[ "${kind}" == class ]]; then
    [[ "${extension}" == cpp && -z "${linkage}" && -z "${cppstd}" ]] \
      || die "${EXIT_USAGE}" "class generation accepts only --namespace and an optional PATH"
  else
    [[ "${kind}" == lib || "${extension}" == cpp ]] \
      || die "${EXIT_USAGE}" "--c is available for generated libraries"
  fi
  case "${kind}" in
    lib | bin | class) ;;
    *) die "${EXIT_USAGE}" "generate requires KIND 'lib', 'bin' or 'class'" ;;
  esac
  [[ -n "${name}" ]] || die "${EXIT_USAGE}" "generate requires a NAME"
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid member name: ${name}"

  [[ "${kind}" == lib || -z "${linkage}" ]] \
    || die "${EXIT_USAGE}" "--static and --shared are available for libraries"
  if [[ -n "${cpp_namespace}" ]] \
    && { [[ "${kind}" == lib && "${extension}" == cpp ]] || [[ "${kind}" == class ]]; }; then
    : # accepted for C++ libraries and classes
  elif [[ -n "${cpp_namespace}" ]]; then
    die "${EXIT_USAGE}" "--namespace is available for C++ libraries and classes"
  fi

  manifest_load
  if [[ "${kind}" == class ]]; then
    validate_cpp_identifier "${name}" "class name"
    if [[ -z "${cpp_namespace}" ]]; then
      cpp_namespace=$(workspace_application_namespace) \
        || die "${EXIT_USAGE}" "could not read the workspace project name"
    fi
    validate_cpp_namespace "${cpp_namespace}"
    generate_class "${name}" "${class_path[0]:-}" "${cpp_namespace}"
    return $?
  fi
  if [[ "${kind}" == lib && "${extension}" == cpp ]]; then
    validate_cpp_identifier "${name}" "class name"
    if [[ -z "${cpp_namespace}" ]]; then
      cpp_namespace=$(workspace_application_namespace) || die "${EXIT_USAGE}" "could not read the workspace project name"
    fi
    validate_cpp_namespace "${cpp_namespace}"
  fi
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
  local saved_root="${FORGE_ROOT}" saved_manifest="${FORGE_MANIFEST_PATH}" author_line cppstd
  author_line=$(project_author_line)
  if [[ -z "${cppstd}" ]]; then
    cppstd=$(workspace_application_cppstd) \
      || die "${EXIT_USAGE}" "could not read the workspace C++ standard"
  fi
  scaffold_project "${dest}" "${name}" "${kind}" 0 "0.1.0" "" "${author_line}" "${extension}" "${cpp_namespace}" "${linkage}" 0 "${cppstd}"
  FORGE_ROOT="${saved_root}"
  FORGE_MANIFEST_PATH="${saved_manifest}"

  manifest_add_workspace_member "${FORGE_MANIFEST_PATH}" "${subdir}"
  if [[ "${kind}" == "lib" ]]; then
    manifest_add_link_to_targets "${FORGE_MANIFEST_PATH}" "${name}"
  fi
  out "generated ${kind} member '${name}' at ${subdir}"
  sync_after_manifest_edit
}
