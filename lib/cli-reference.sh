# shellcheck shell=bash
# Shared CLI reference for help and completion.
#
# lib/cli-reference.tsv is the single source of truth for commands, options
# and examples. This module renders that catalog into a task-oriented,
# discoverable help screen; completion (reference_complete) reads the same
# catalog so help and Tab completion can never drift apart.
#
# Layout contract (kept stable for the test suite and for humans):
#   - The overview keeps the literal "Quick start:" before "Commands:".
#   - Every command row is exactly "  <synopsis><padding>  <description>"
#     so descriptions share one column across commands AND global options.
#   - No dot leaders; color is supplied exclusively by the ui_* helpers.

# --- presentation primitives ------------------------------------------------
reference_heading() { out "$(ui_bold "$(ui_cyan "$1")")"; }

reference_banner() {
  local title="$1"
  out "$(ui_dim '════════════════════════════════════════════════════════════════════')"
  out "  $(ui_bold "$(ui_cyan '⚒')")  $(ui_bold "$(ui_cyan "${title}")")"
  out "$(ui_dim '════════════════════════════════════════════════════════════════════')"
}

reference_group()  { out ""; out "  $(ui_bold "$(ui_magenta "$1")")"; }
reference_note()   { out "  $(ui_yellow 'ℹ')  $1"; }
reference_tip()    { out "  $(ui_yellow '💡') $1"; }
reference_more()   { out "  $(ui_cyan '📘') $(ui_dim "$1")"; }

# Task grouping for the overview. Keys are TSV command paths; the fallback
# "other" group guarantees every catalog command stays visible.
declare -A FORGE_HELP_GROUP=(
  ["help"]="start"        ["version"]="start"   ["doctor"]="start"
  ["new"]="start"         ["init"]="start"
  ["build"]="buildrun"    ["run"]="buildrun"   ["watch"]="buildrun"
  ["test"]="buildrun"     ["clean"]="buildrun"
  ["add"]="deps"          ["remove"]="deps"    ["deps"]="deps"
  ["deps lock"]="deps"    ["deps pin"]="deps"  ["deps status"]="deps"
  ["sync"]="deps"
  ["generate"]="struct"   ["generate lib"]="struct"
  ["generate bin"]="struct" ["generate class"]="struct"
  ["docs"]="quality"      ["fmt"]="quality"    ["metadata"]="quality"
  ["workflow"]="maint"    ["workflow init"]="maint"
  ["update"]="maint"      ["uninstall"]="maint"
)

FORGE_HELP_GROUPS=(
  'start|🚀  Get started'
  'buildrun|🛠   Build, run & test'
  'deps|📦  Dependencies & sync'
  'struct|🧱  Project structure'
  'quality|✨  Quality & docs'
  'maint|⚙️   Maintenance'
  'other|🔧  Other commands'
)

# Print the options for one scope, aligned and colored.
reference_options() {
  local scope="$1" kind path label description _ width=24 row opt_label opt_desc
  local -a opts=()
  while IFS=$'\t' read -r kind path label description _; do
    [[ "${kind}" == option && "${path}" == "${scope}" ]] || continue
    opts+=("${label}"$'\t'"${description}")
    if (( ${#label} > width )); then width=${#label}; fi
  done < "${FORGE_LIB}/cli-reference.tsv"
  (( ${#opts[@]} )) || return 0
  out ""
  out "  $(ui_bold "$(ui_blue 'Options:')")"
  for row in "${opts[@]}"; do
    IFS=$'\t' read -r opt_label opt_desc <<< "${row}"
    ui_help_row "${opt_label}" "${opt_desc}" "${width}" cyan
  done
}

cmd_help() {
  local scope="$*" kind path label description _ synopsis="" summary=""
  local width=0 row rlabel rdesc rpath gdef gkey gtitle
  local -a rows=() examples=() global_opts=() group_rows=()

  while IFS=$'\t' read -r kind path label description _; do
    if [[ "${kind}" == command ]]; then
      if [[ "${path}" == "${scope}" ]]; then
        synopsis="${label}" summary="${description}"
      elif [[ -z "${scope}" || "${path}" == "${scope} "* ]]; then
        rows+=("${label}"$'\t'"${description}"$'\t'"${path}")
        if (( ${#label} > width )); then width=${#label}; fi
      fi
    elif [[ "${kind}" == example && "${path}" == "${scope}" ]]; then
      examples+=("${label}")
    elif [[ "${kind}" == option && "${path}" == global ]]; then
      global_opts+=("${label}"$'\t'"${description}")
    fi
  done < "${FORGE_LIB}/cli-reference.tsv"

  if [[ -z "${scope}" ]]; then
    reference_banner 'Forge · C++ project orchestration'
    out ""
    out "  $(ui_bold 'Usage:') $(ui_green 'forge [GLOBAL OPTIONS] COMMAND [ARGS]')  $(ui_dim 'forge <cmd> --help for details')"

    reference_group '🚀 Quick start:'
    out "  $(ui_green 'forge doctor')                 $(ui_dim '# check your toolchain')"
    out "  $(ui_green 'forge new hello --defaults')    $(ui_dim '# scaffold an app')"
    out "  $(ui_green 'cd hello && forge build')       $(ui_dim '# configure & compile')"
    out "  $(ui_green 'forge run -- --version')        $(ui_dim '# run it')"
    out "  $(ui_green 'forge test')                    $(ui_dim '# run CTest')"

    out ""
    out "  $(ui_bold "$(ui_cyan '📋 Commands:')") $(ui_dim '— organized by what you want to do')"
    for gdef in "${FORGE_HELP_GROUPS[@]}"; do
      gkey="${gdef%%|*}"; gtitle="${gdef#*|}"
      group_rows=()
      for row in "${rows[@]}"; do
        IFS=$'\t' read -r rlabel rdesc rpath <<< "${row}"
        [[ "${FORGE_HELP_GROUP[${rpath}]:-other}" == "${gkey}" ]] || continue
        group_rows+=("${rlabel}"$'\t'"${rdesc}")
      done
      (( ${#group_rows[@]} )) || continue
      out "  $(ui_bold "$(ui_blue "${gtitle}")")"
      for row in "${group_rows[@]}"; do
        IFS=$'\t' read -r rlabel rdesc <<< "${row}"
        ui_help_row "${rlabel}" "${rdesc}" "${width}" green
      done
    done

    out ""
    out "  $(ui_bold "$(ui_cyan '🌐 Global options:')")"
    for row in "${global_opts[@]}"; do
      IFS=$'\t' read -r rlabel rdesc <<< "${row}"
      ui_help_row "${rlabel}" "${rdesc}" "${width}" cyan
    done
    out "  Short forms: -h help, -V version, -q quiet, -v verbose, -y yes."

    reference_group '🧭 Common workflows'
    out "  $(ui_green 'forge new --name hello --git')             $(ui_dim '# prompt for remaining metadata')"
    out "  $(ui_green 'forge generate lib widget --c')            $(ui_dim '# add and link a C library')"
    out "  $(ui_green 'forge add fmt --conan --yes')               $(ui_dim '# add, sync and lock a Conan package')"
    out "  $(ui_green 'forge sync --diff && forge sync --apply --yes')"
    out "  $(ui_green 'forge test --sanitize address')"
    out "  $(ui_green 'forge help deps pin')                      $(ui_dim '# options & example for one verb')"

    out ""
    out "$(ui_dim '────────────────────────────────────────────────────────────────────')"
    reference_tip "Run $(ui_green 'forge <command> --help') for every option and example of a verb."
    reference_more "https://dr3mro.github.io/forge/ · docs/commands.md"
    out "  $(ui_dim 'Exit codes:') 0 ok · 1 error · 2 usage · 3 missing tool"
    out "              $(ui_dim '4 dependency/lock · 5 build/test · 6 conflict')"
    return
  fi

  [[ -n "${synopsis}" ]] || die "${EXIT_USAGE}" "unknown help topic: ${scope}"
  reference_banner "forge ${synopsis}"
  out ""
  out "  ${summary}"
  out ""
  out "  $(ui_bold 'Usage:')   $(ui_green "forge ${synopsis}")"

  if [[ "${scope}" == add ]]; then
    out ""
    reference_note "Omit the source to choose Conan, vcpkg, or GitHub interactively."
    reference_note "GitHub prompts for the URL, tag/branch/SHA, and upstream CMake target."
    reference_note "Answer y to sync (and lock Conan), or pass $(ui_green '--yes') for scripts."
    reference_note "Later: $(ui_green 'forge sync --apply'), then $(ui_green 'forge deps lock') for Conan."
  fi

  if (( ${#rows[@]} )); then
    out ""
    out "  $(ui_bold "$(ui_blue 'Subcommands:')")"
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r rlabel rdesc rpath <<< "${row}"
      ui_help_row "${rlabel}" "${rdesc}" "${width}" green
    done
  fi

  reference_options "${scope}"

  out ""
  out "  $(ui_bold "$(ui_blue 'Examples:')")"
  if (( ${#examples[@]} )); then
    for row in "${examples[@]}"; do
      out "  $(ui_cyan '▸')  $(ui_green "${row}")"
    done
  else
    out "  $(ui_cyan '▸')  $(ui_green "forge ${synopsis}")"
  fi

  out ""
  out "$(ui_dim '────────────────────────────────────────────────────────────────────')"
  reference_tip "Add $(ui_green '--yes') for non-interactive use where supported."
  reference_more "forge help · forge <command> --help · https://dr3mro.github.io/forge/"
}

# Resolve the deepest known command scope from positionals before --help.
reference_help_for() {
  local scope="$1" child="${2:-}" kind path _
  while IFS=$'\t' read -r kind path _; do
    if [[ "${kind}" == command && "${path}" == "${scope} ${child}" ]]; then
      cmd_help "${scope}" "${child}"
      return
    fi
  done < "${FORGE_LIB}/cli-reference.tsv"
  cmd_help "${scope}"
}

# Internal completion protocol. Arguments are the prefix and completed words.
# Keep this independent of manifest contents and subprocess availability.
reference_complete() {
  local prefix="${1:-}" kind path label description values flag key word scope="" awaiting="" candidate add_source="" git_revision=0
  (( $# )) || return 0
  shift
  local -A commands=() options=() choices=() used=()
  local -a paths=() flags=() matches=()
  while IFS=$'\t' read -r kind path label description values; do
    case "${kind}" in
      command) commands["${path}"]=1; paths+=("${path}") ;;
      option)
        flag="${label%% *}"
        key="${path} ${flag}"
        flags+=("${key}")
        options["${key}"]=0
        if [[ "${label}" != "${flag}" ]]; then options["${key}"]=1; fi
        choices["${key}"]="${values}"
        ;;
    esac
  done < "${FORGE_LIB}/cli-reference.tsv"

  for word in "$@"; do
    if [[ -n "${awaiting}" ]]; then
      if [[ "${awaiting}" == 'add --source' ]]; then
        # Bash can pass the equals sign as a separate completed word.
        [[ "${word}" != '=' ]] || continue
        add_source="${word}"
      fi
      awaiting=""
      continue
    fi
    case "${word}" in
      --) return 0 ;;
      --source=*)
        if [[ "${scope}" == add ]]; then add_source="${word#*=}"; fi
        continue
        ;;
      -*=*) continue ;;
      -*)
        if [[ "${scope}" == add ]]; then
          used["${word}"]=1
          if [[ "${word}" == --github ]]; then add_source=git; fi
        fi
        for key in "${scope} ${word}" "global ${word}"; do
          if [[ "${options[${key}]:-0}" == 1 ]]; then awaiting="${key}"; break; fi
        done ;;
      *)
        candidate="${scope:+${scope} }${word}"
        if [[ "${scope}" == help || "${scope}" == 'help '* ]]; then
          candidate="${candidate#help }"
          if [[ -n "${commands[${candidate}]:-}" ]]; then scope="help ${candidate}"; fi
        elif [[ -n "${commands[${candidate}]:-}" ]]; then
          scope="${candidate}"
        elif [[ -z "${scope}" ]]; then
          return 0
        fi ;;
    esac
  done

  if [[ -n "${used[--tag]:-}${used[--branch]:-}${used[--sha]:-}${used[--rev]:-}" ]]; then
    git_revision=1
  fi

  if [[ -n "${awaiting}" ]]; then
    read -r -a matches <<< "${choices[${awaiting}]}"
  elif [[ "${prefix}" == --*=* ]]; then
    flag="${prefix%%=*}"
    for key in "${scope} ${flag}" "global ${flag}"; do
      if [[ -n "${choices[${key}]:-}" ]]; then
        read -r -a matches <<< "${choices[${key}]}"
        matches=("${matches[@]/#/${flag}=}")
        break
      fi
    done
  elif [[ "${prefix}" == -* ]]; then
    for key in "${flags[@]}"; do
      path="${key% *}" flag="${key##* }"
      if [[ "${path}" == "${scope}" ]]; then
        if [[ "${scope}" == add && "${add_source}" == git ]]; then
          case "${flag}" in
            --url | --cmake-target) [[ -z "${used[${flag}]:-}" ]] || continue ;;
            --tag | --branch | --rev | --sha) (( ! git_revision )) || continue ;;
            *) continue ;;
          esac
        fi
        matches+=("${flag}")
      elif [[ "${path}" == global && ( "${flag}" != --version || -z "${scope}" ) ]]; then
        matches+=("${flag}")
      fi
    done
  elif [[ -z "${prefix}" && "${scope}" == add ]]; then
    if [[ "${add_source}" == git ]]; then
      if [[ -z "${used[--url]:-}" ]]; then
        matches=(--url)
      elif (( ! git_revision )); then
        matches=(--tag --branch --sha)
      elif [[ -z "${used[--cmake-target]:-}" ]]; then
        matches=(--cmake-target)
      fi
    elif [[ -z "${add_source}${used[--conan]:-}${used[--vcpkg]:-}" ]]; then
      matches=(--source --conan --vcpkg --github)
    fi
  else
    case "${scope}" in
      help) scope="" ;;
      'help '*) scope="${scope#help }" ;;
    esac
    for path in "${paths[@]}"; do
      candidate="${path}"
      if [[ -n "${scope}" ]]; then
        [[ "${path}" == "${scope} "* ]] || continue
        candidate="${path#"${scope} "}"
      fi
      if [[ "${candidate}" != *' '* ]]; then matches+=("${candidate}"); fi
    done
  fi
  for candidate in "${matches[@]}"; do
    if [[ "${candidate}" == "${prefix}"* ]]; then out "${candidate}"; fi
  done
  return 0
}
