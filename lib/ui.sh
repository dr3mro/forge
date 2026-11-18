# shellcheck shell=bash
# Forge UI module — restrained color, TTY detection, precedence handling.
# API: ui_init; ui_red ui_green ui_yellow ui_blue ui_magenta ui_cyan
#      ui_bold ui_dim; ui_help_row; ui_strip_ansi.
# Inputs: FORGE_NO_COLOR, FORGE_FORCE_COLOR, NO_COLOR, stdout TTY state.
# Outputs: sets FORGE_COLOR (0/1). No other side effects.
#
# Precedence (highest first): --no-color > NO_COLOR > FORCE_COLOR > TTY.
# Progress symbols remain visible when ANSI styling is disabled.

FORGE_COLOR=0

# Choose whether to emit color using flags, environment, and TTY state.
ui_init() {
  if [[ "${FORGE_NO_COLOR:-0}" == "1" ]]; then
    FORGE_COLOR=0
  elif [[ -n "${NO_COLOR+x}" ]]; then
    FORGE_COLOR=0
  elif [[ "${FORGE_FORCE_COLOR:-0}" == "1" || "${FORCE_COLOR:-0}" == "1" ]]; then
    FORGE_COLOR=1
  elif [[ -t 1 ]]; then
    FORGE_COLOR=1
  else
    FORGE_COLOR=0
  fi
}

# Apply an ANSI style when color is enabled.
_ui_color() {
  local code="$1"
  shift
  if (( FORGE_COLOR )); then
    printf '\033[%sm%s\033[0m' "${code}" "$*"
  else
    printf '%s' "$*"
  fi
}

# Convenience wrappers for severity colors and text emphasis.
ui_red()     { _ui_color 31 "$@"; }
ui_green()   { _ui_color 32 "$@"; }
ui_yellow()  { _ui_color 33 "$@"; }
ui_blue()    { _ui_color 34 "$@"; }
ui_magenta() { _ui_color 35 "$@"; }
ui_cyan()    { _ui_color 36 "$@"; }
ui_bold()    { _ui_color 1 "$@"; }
ui_dim()     { _ui_color 2 "$@"; }

# Two-column help row with aligned columns:
#   ui_help_row LABEL DESCRIPTION LABEL_WIDTH [green|cyan|bold]
# The description starts immediately after the padded label column.
ui_help_row() {
  local label="$1" description="$2" label_width="$3" style="${4:-green}"
  local padded colored
  printf -v padded '%-*s' "${label_width}" "${label}"
  case "${style}" in
    green) colored=$(ui_green "${padded}") ;;
    cyan)  colored=$(ui_cyan "${padded}") ;;
    bold)  colored=$(ui_bold "${padded}") ;;
    *)     colored="${padded}" ;;
  esac
  printf '  %s  %s\n' "${colored}" "${description}"
}

# Remove ANSI SGR sequences from a stream of text (used to keep JSON clean).
ui_strip_ansi() {
  sed $'s/\033\[[0-9;]*m//g'
}
