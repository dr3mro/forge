# shellcheck shell=bash
# Forge command: docs.

# Generate a Doxygen configuration from the manifest and C++ source layout.
doxygen_config() {
  local path
  # Doxygen expands dollar-parenthesis expressions even inside quoted values.
  mq '
    def cfg: gsub("[[:cntrl:]]"; " ") | split("$") | join("&#36;") | @json;
    "PROJECT_NAME = " + (.package.name | cfg),
    "PROJECT_NUMBER = " + (.package.version | cfg),
    "PROJECT_BRIEF = " + ((.package.description // "") | cfg)
  ' || return
  cat <<'CONFIG'
OUTPUT_DIRECTORY = target/docs
GENERATE_HTML = YES
GENERATE_LATEX = NO
RECURSIVE = YES
EXCLUDE = target .forge
EXTRACT_ALL = YES
HAVE_DOT = NO
QUIET = YES
CONFIG
  for path in src include; do
    if [[ -d "${path}" ]]; then printf 'INPUT += %s\n' "${path}"; fi
  done
  mq '((.bin // []) + (.lib // [])) | .[].path | "INPUT += " + @json'
}

# Run Doxygen at the project root with generated HTML under target/docs.
cmd_docs() {
  case "${1:-}" in
    --help | -h) cmd_help; return "${EXIT_OK}" ;;
  esac
  (( $# == 0 )) || die "${EXIT_USAGE}" "usage: forge docs"

  manifest_load
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would generate Doxygen HTML in target/docs"
    return "${EXIT_OK}"
  fi
  require_tool doxygen

  local path
  for path in target target/docs; do
    [[ ! -L "${FORGE_ROOT}/${path}" ]] \
      || die "${EXIT_CONFLICT}" "refusing to write through a symlink: ${path}"
  done
  if [[ -d "${FORGE_ROOT}/target/docs" ]]; then
    path=$(find "${FORGE_ROOT}/target/docs" -type l -print -quit) \
      || die "${EXIT_CONFLICT}" "could not inspect target/docs"
    [[ -z "${path}" ]] || die "${EXIT_CONFLICT}" "refusing to write documentation through symlinks: ${path}"
  fi
  mkdir -p "${FORGE_ROOT}/target/docs" || die "${EXIT_OTHER}" "could not create target/docs"

  progress "Generating Doxygen documentation"
  (cd "${FORGE_ROOT}" && doxygen_config | run_cmd doxygen -) \
    || die "${EXIT_BUILD}" "Doxygen generation failed"
  [[ -f "${FORGE_ROOT}/target/docs/html/index.html" ]] \
    || die "${EXIT_BUILD}" "Doxygen did not generate an HTML index"
  out "docs ok: target/docs/html/index.html"
}
