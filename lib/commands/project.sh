# shellcheck shell=bash
# Shared new/init metadata and scaffolding.

cmd_new() { project_create new "$@"; }
cmd_init() { project_create init "$@"; }

# Prompt for omitted fields, or retain their defaults in argument-only mode.
project_read_field() {
  local label="$1" field="$2" answer=""
  [[ -z "${!field+x}" ]] || return 0
  if (( defaults )); then
    printf -v "${field}" '%s' ""
  else
    printf '%s: ' "${label}" >&2
    IFS= read -r answer || die "${EXIT_USAGE}" "initialization cancelled: expected ${label}"
    printf -v "${field}" '%s' "${answer}"
  fi
}

project_create() {
  local action="$1" kind=bin git_init=0 defaults=0 cpp_namespace="" linkage=""
  local name version description author email
  shift
  while (( $# )); do
    case "$1" in
      --bin) kind=bin ;;
      --lib) kind=lib ;;
      --git) git_init=1 ;;
      --defaults) defaults=1 ;;
      --help|-h) cmd_help "${action}"; return ;;
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
      --name|--version|--description|--author|--email)
        (( $# >= 2 )) || die "${EXIT_USAGE}" "$1 requires a value"
        [[ "$2" != --* ]] || die "${EXIT_USAGE}" "$1 requires a value"
        printf -v "${1#--}" '%s' "$2"
        shift ;;
      -* ) die "${EXIT_USAGE}" "unknown flag for '${action}': $1" ;;
      *)
        [[ "${action}" == new && -z "${name+x}" ]] || die "${EXIT_USAGE}" "unexpected argument for '${action}': $1"
        name="$1" ;;
    esac
    shift
  done

  local dir="${PWD}" default_name="" author_line
  if [[ "${action}" == init ]]; then
    refuse_file "${dir}/Forge.toml"
    default_name=${dir##*/}
    default_name="${default_name//[^A-Za-z0-9_]/_}"
    [[ "${default_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || default_name=project
  elif [[ -n "${name+x}" && ! -t 0 && ! -p /dev/stdin && ! -f /dev/stdin ]]; then
    defaults=1
  fi

  project_read_field "Project name${default_name:+ [${default_name}]}" name
  name="${name:-${default_name}}"
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid project name '${name}' (use letters, digits, underscore)"
  if [[ "${action}" == new ]]; then
    dir+="/${name}"
    refuse_file "${dir}"
  fi

  [[ "${kind}" == lib || -z "${linkage}" ]] \
    || die "${EXIT_USAGE}" "--static and --shared are available for libraries"
  if [[ "${kind}" == lib ]]; then
    cpp_namespace="${cpp_namespace:-${name}}"
    validate_cpp_namespace "${cpp_namespace}"
  elif [[ -n "${cpp_namespace}" ]]; then
    die "${EXIT_USAGE}" "--namespace is available for C++ libraries"
  fi

  project_read_field 'Version [0.1.0]' version
  version="${version:-0.1.0}"
  [[ "${version}" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]] \
    || die "${EXIT_USAGE}" "project version must have one to four dot-separated numbers"
  project_read_field 'Description (optional)' description
  project_read_field 'Author name (optional)' author
  project_read_field 'Author email (optional)' email
  [[ ! "${author}${email}" =~ [[:cntrl:]] ]] \
    || die "${EXIT_USAGE}" "author name and email must contain printable text"
  author_line="${author}"
  [[ -z "${email}" ]] || author_line="${author:+${author} }<${email}>"

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would ${action} ${kind} project '${name}' at ${dir}"
    return
  fi
  scaffold_project "${dir}" "${name}" "${kind}" "${git_init}" "${version}" "${description}" "${author_line}" cpp "${cpp_namespace}" "${linkage}"
  out "Scaffolded ${kind} project '${name}' in ${dir}"
  if [[ "${action}" == new ]]; then
    status "Next: cd ${name} && forge build"
  else
    status "Next: forge build"
  fi
}
