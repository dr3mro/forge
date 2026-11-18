# shellcheck shell=bash
# Forge diagnostics — version_ge, tool version probes, help/version/doctor.
# API: version_ge; cmd_help cmd_version cmd_doctor.
# Inputs: tools.versions, FORGE_VERSION, ui_* helpers.
# Outputs: help/doctor to stdout; exit 3 when a required tool is missing.
# Side effects: none (read-only environment probes).

declare -A FORGE_TOOL_REQ=()

# Compare two dotted version strings numerically.
version_ge() {
  # Compare dotted numeric versions: returns 0 when "$1" >= "$2".
  local a="$1" b="$2" IFS=.
  local -a av=() bv=()
  read -r -a av <<< "${a}"
  read -r -a bv <<< "${b}"
  local i n=${#av[@]} m=${#bv[@]}
  (( n > m )) && n=${m}
  local x y
  for (( i = 0; i < n; i++ )); do
    x="${av[i]:-0}" y="${bv[i]:-0}"
    [[ "${x}" =~ ^[0-9]+$ ]] || x=0
    [[ "${y}" =~ ^[0-9]+$ ]] || y=0
    if (( x > y )); then return 0; fi
    if (( x < y )); then return 1; fi
  done
  return 0
}

# Load the minimum tool versions from tools.versions.
load_tools_versions() {
  local f="${FORGE_HOME}/tools.versions" key value
  [[ -f "${f}" ]] || return 1
  FORGE_TOOL_REQ=()
  while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    [[ -n "${key}" ]] && FORGE_TOOL_REQ["${key}"]="${value}"
  done < "${f}"
  return 0
}

# --- Version probes --------------------------------------------------------
# Extract the version string from each tool's version output.
probe_cmake()      { cmake --version 2>/dev/null | head -1 | awk '{print $3}'; }
probe_conan()      { conan --version 2>/dev/null | awk '{print $NF}'; }
probe_git()        { git --version 2>/dev/null | sed -E 's/^git version ([0-9.]+).*/\1/'; }
probe_jq()         { jq --version 2>/dev/null | sed -E 's/^jq-([0-9.]+).*/\1/'; }
probe_python()     { python3 --version 2>/dev/null | awk '{print $2}'; }
probe_shellcheck() { shellcheck --version 2>/dev/null | sed -n 's/^version: //p'; }
probe_ninja()      { ninja --version 2>/dev/null | head -1; }
probe_compiler()   { c++ --version 2>/dev/null | head -1; }

DOCTOR_FAILURES=0

# Print one tool check and count failures.
doctor_check() {
  # doctor_check LABEL FOUND REQUIRED  (empty REQUIRED = any version ok)
  local label="$1" found="${2:-}" required="${3:-}" ok=1
  if [[ -z "${found}" ]]; then
    ok=0
  elif [[ -n "${required}" ]] && ! version_ge "${found}" "${required}"; then
    ok=0
  fi
  if (( ok )); then
    out "  $(ui_green '[ok]')   ${label} ${found} (need >= ${required:-any})"
  else
    out "  $(ui_red '[MISS]') ${label} ${found:-not found} (need >= ${required:-any})"
    DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
  fi
}

# --- Commands --------------------------------------------------------------
# Print the version of this Forge launcher.
cmd_version() {
  out "forge ${FORGE_VERSION}"
}

# Probe the local toolchain against Forge's minimum requirements.
cmd_doctor() {
  load_tools_versions || die "${EXIT_OTHER}" "tools.versions is missing or unreadable"

  out "Forge doctor (v${FORGE_VERSION})"
  out "  host: $(uname -s) $(uname -m)"
  out "  bash: ${BASH_VERSION}"
  out ""

  DOCTOR_FAILURES=0
  doctor_check "bash"       "${BASH_VERSION}"                 "${FORGE_TOOL_REQ[BASH_MIN]}"
  doctor_check "cmake"      "$(probe_cmake)"                  "${FORGE_TOOL_REQ[CMAKE_MIN]}"
  doctor_check "conan"      "$(probe_conan)"                  "${FORGE_TOOL_REQ[CONAN_MAJOR]}"
  doctor_check "git"        "$(probe_git)"                    "${FORGE_TOOL_REQ[GIT_MIN]}"
  doctor_check "jq"         "$(probe_jq)"                     "${FORGE_TOOL_REQ[JQ_MIN]}"
  doctor_check "compiler"   "$(probe_compiler)"               ""
  doctor_check "ninja"      "$(probe_ninja)"                  "${FORGE_TOOL_REQ[NINJA_MIN]}"
  doctor_check "shellcheck" "$(probe_shellcheck)"             "${FORGE_TOOL_REQ[SHELLCHECK_MIN]}"

  # Parser adapter needs both a recent Python and importable tomllib.
  local pv python_parser_ok=1
  pv=$(probe_python)
  version_ge "${pv:-0}" "${FORGE_TOOL_REQ[PYTHON_MIN]:-3.11}" || python_parser_ok=0
  python3 -c 'import tomllib' >/dev/null 2>&1 || python_parser_ok=0
  if (( python_parser_ok )); then
    doctor_check "toml-parser(py3+tomllib)" "${pv}" "${FORGE_TOOL_REQ[PYTHON_MIN]}"
  else
    doctor_check "toml-parser(py3+tomllib)" "" "${FORGE_TOOL_REQ[PYTHON_MIN]}"
  fi

  out ""
  if (( DOCTOR_FAILURES == 0 )); then
    out "$(ui_green 'All required tools are present.')"
    return "${EXIT_OK}"
  fi
  out "$(ui_red "${DOCTOR_FAILURES} required tool(s) missing or too old.")"
  cat >&2 <<'EOF'
hint (macOS/Homebrew):
  brew install bash cmake ninja jq shellcheck pipx
  pipx install 'conan>=2,<3'
  pipx ensurepath
Ensure /opt/homebrew/bin (or /usr/local/bin) precedes /bin on PATH.
EOF
  return "${EXIT_TOOL}"
}
