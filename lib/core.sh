# shellcheck shell=bash
# shellcheck disable=SC2034  # exit-code constants & state are used by other modules
# Forge core — exit codes, diagnostics output, path/atomic-write/hash helpers.
# API:
#   out status warn fail die verbose
#   require_tool abspath path_is_safe_relative
#   atomic_write stat_mode sha256_str sha256_file
#   discover_project require_project
#   foreach_line (helper for safe line iteration)
# Inputs: globals from bin/forge; ui_* for colored prefixes.
# Outputs: messages to stdout (data) / stderr (diagnostics).
# Side effects: filesystem only in atomic_write/discover helpers.

# Exit codes (frozen after v0.1).
EXIT_OK=0
EXIT_OTHER=1
EXIT_USAGE=2
EXIT_TOOL=3
EXIT_DEP=4
EXIT_BUILD=5
EXIT_CONFLICT=6

# --- Output ---------------------------------------------------------------
# Data goes to stdout; diagnostics/progress go to stderr.
out()     { printf '%s\n' "$*"; }
status()  { (( FORGE_QUIET )) || printf '%s\n' "$*" >&2; }
progress() { status "[ ] $*"; }
warn()    { printf '%s: %s\n' "$(ui_yellow warning)" "$*" >&2; }
fail()    { printf '%s: %s\n' "$(ui_red error)" "$*" >&2; }

# Report an error and exit with the supplied Forge exit code.
die() {
  local code="$1"
  shift
  fail "$*"
  exit "${code}"
}

# Write diagnostic details when verbose output is enabled.
verbose() {
  if (( FORGE_VERBOSE )); then
    printf '%s\n' "$*" >&2
  fi
  return 0
}

# Run a subprocess from an argument array (never a command string / eval).
# Honors --dry-run and redacts obvious secret-looking values in verbose logs.
run_cmd() {
  if (( FORGE_VERBOSE )); then
    local shown="" a
    for a in "$@"; do
      case "${a}" in
        *TOKEN* | *PASSWORD* | *SECRET* | *KEY=*) a='<redacted>' ;;
      esac
      shown+=" ${a}"
    done
    verbose "run:${shown}"
  fi
  (( FORGE_DRY_RUN )) && return 0
  "$@"
}

# Ask for confirmation or honor the global yes flag.
confirm_action() {
  local prompt="${1:-Proceed?}" answer
  (( FORGE_YES )) && return 0
  if [[ -t 0 ]]; then
    printf '%s [y/N] ' "${prompt}" >&2
    read -r answer || return 1
    [[ "${answer}" == [yY] || "${answer}" == [yY][eE][sS] ]] || return 1
    return 0
  fi
  die "${EXIT_CONFLICT}" "non-interactive operation requires --yes"
}

# Number of parallel build jobs.
forge_jobs() {
  local n
  if n=$(sysctl -n hw.ncpu 2>/dev/null); then
    printf '%s' "${n}"
  elif n=$(nproc 2>/dev/null); then
    printf '%s' "${n}"
  else
    printf '2'
  fi
}

FORGE_TMP_DIRS=()

# Register a temporary directory for the exit trap.
forge_add_tmpdir() {
  FORGE_TMP_DIRS+=("$1")
}

# Remove temporary directories registered during this invocation.
forge_cleanup_tmpdirs() {
  local d
  for d in "${FORGE_TMP_DIRS[@]}"; do
    [[ -n "${d}" && -d "${d}" ]] && rm -rf -- "${d}"
  done
}

# --- Tools & paths ---------------------------------------------------------
# Exit with a tool error when a required command is missing.
require_tool() {
  local tool="$1"
  command -v "${tool}" >/dev/null 2>&1 \
    || die "${EXIT_TOOL}" "required tool '${tool}' not found (run 'forge doctor')"
}

# Absolute path without readlink -f (portable macOS/Linux).
abspath() {
  local p="$1"
  if [[ "${p}" == /* ]]; then
    printf '%s' "${p}"
  else
    printf '%s/%s' "${PWD}" "${p}"
  fi
}

# A relative path is safe if non-empty, not absolute, has no backslash,
# no '~' prefix and no '..' component.
path_is_safe_relative() {
  local p="$1" part
  [[ -n "${p}" ]] || return 1
  [[ "${p}" != /* ]] || return 1
  [[ "${p}" != *\\* ]] || return 1
  [[ "${p}" != '~' && "${p}" != '~'/* ]] || return 1
  local IFS=/
  local -a parts=()
  read -r -a parts <<< "${p}"
  for part in "${parts[@]}"; do
    [[ "${part}" == ".." ]] && return 1
  done
  return 0
}

# --- Filesystem ------------------------------------------------------------
# Read a file's mode using GNU or BSD stat.
stat_mode() {
  local f="$1"
  if stat -c %a "${f}" >/dev/null 2>&1; then
    stat -c %a "${f}"
  else
    stat -f %Lp "${f}"
  fi
}

# Write stdin to a file atomically (same-directory temp file + mv).
# Creates parent directories. Preserves mode of an existing target.
atomic_write() {
  local target="$1" tmp dir mode
  dir=$(dirname -- "${target}")
  mkdir -p -- "${dir}" || return 1
  tmp=$(mktemp "${dir}/.forge-tmp.XXXXXX") || return 1
  if ! cat > "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if [[ -e "${target}" ]]; then
    mode=$(stat_mode "${target}") && chmod "${mode}" "${tmp}" 2>/dev/null || true
  fi
  if ! mv -f -- "${tmp}" "${target}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  return 0
}

# Print the SHA-256 digest of a string.
sha256_str() {
  local data="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "${data}" | sha256sum | awk '{print $1}'
  else
    printf '%s' "${data}" | shasum -a 256 | awk '{print $1}'
  fi
}

# Print the SHA-256 digest of a file.
sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${f}" | awk '{print $1}'
  else
    shasum -a 256 "${f}" | awk '{print $1}'
  fi
}

# --- Project discovery -----------------------------------------------------
# Resolve an explicit manifest or find one in a parent directory.
discover_project() {
  local start="${FORGE_MANIFEST_PATH:-}" dir
  if [[ -n "${start}" ]]; then
    [[ -f "${start}" ]] || return 1
    FORGE_MANIFEST_PATH=$(abspath "${start}")
    FORGE_ROOT=$(dirname -- "${FORGE_MANIFEST_PATH}")
    return 0
  fi
  dir="${PWD}"
  while :; do
    if [[ -f "${dir}/Forge.toml" ]]; then
      FORGE_ROOT="${dir}"
      FORGE_MANIFEST_PATH="${dir}/Forge.toml"
      return 0
    fi
    [[ "${dir}" == "/" ]] && break
    dir=$(dirname -- "${dir}")
  done
  return 1
}

# Require a discoverable Forge project before continuing.
require_project() {
  discover_project \
    || die "${EXIT_USAGE}" "no Forge.toml found (run 'forge new NAME' or 'forge init')"
}
