# shellcheck shell=bash
# Shared CLI reference for help and completion.

reference_heading() { out "$(ui_bold "$(ui_cyan "$1")")"; }

reference_options() {
  local scope="$1" kind path label description values
  while IFS=$'\t' read -r kind path label description values; do
    [[ "${kind}" == option && "${path}" == "${scope}" ]] || continue
    ui_help_row "${label}" "${description}" 24 cyan
  done < "${FORGE_LIB}/cli-reference.tsv"
  return 0
}

cmd_help() {
  local scope="$*" kind path label description values synopsis="" summary=""
  local -a rows=() examples=()
  local width=0
  while IFS=$'\t' read -r kind path label description values; do
    if [[ "${kind}" == command ]]; then
      if [[ "${path}" == "${scope}" ]]; then
        synopsis="${label}" summary="${description}"
      elif [[ -z "${scope}" || "${path}" == "${scope} "* ]]; then
        rows+=("${label}"$'\t'"${description}")
        if (( ${#label} > width )); then width=${#label}; fi
      fi
    elif [[ "${kind}" == example && "${path}" == "${scope}" ]]; then
      examples+=("${label}")
    fi
  done < "${FORGE_LIB}/cli-reference.tsv"

  if [[ -z "${scope}" ]]; then
    reference_heading 'Forge · C++ project orchestration'
    out 'Usage: forge [GLOBAL OPTIONS] COMMAND [ARGS]'
    out ""
    reference_heading 'Quick start:'
    out '  forge doctor'
    out '  forge new hello --defaults'
    out '  cd hello && forge build'
    out '  forge run -- --version'
    out '  forge test'
    out ""
    reference_heading 'Commands:'
  else
    [[ -n "${synopsis}" ]] || die "${EXIT_USAGE}" "unknown help topic: ${scope}"
    reference_heading "forge ${synopsis}"
    out "${summary}"
    if (( ${#rows[@]} )); then
      out ""
      reference_heading 'Subcommands:'
    fi
  fi
  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r label description <<< "${row}"
    ui_help_row "${label}" "${description}" "${width}" green
  done

  out ""
  if [[ -n "${scope}" ]]; then
    reference_options "${scope}"
    out ""
    reference_heading 'Examples'
    for row in "${examples[@]}"; do out "  ${row}"; done
    out '  See forge help for global options.'
    return
  fi

  reference_heading 'Global options:'
  # Keep the overview columns aligned with the command table.
  while IFS=$'\t' read -r kind path label description values; do
    if [[ "${kind}" == option && "${path}" == global ]]; then
      ui_help_row "${label}" "${description}" "${width}" cyan
    fi
  done < "${FORGE_LIB}/cli-reference.tsv"
  out '  Short forms: -h help, -V version, -q quiet, -v verbose, -y yes.'
  out ""
  reference_heading 'Common workflows'
  out '  forge new --name hello --git             # Prompt for remaining metadata'
  out '  forge generate lib widget --c            # Add and link a C library'
  out '  forge add fmt --conan                     # Add, sync, and lock a Conan package'
  out '  forge sync --diff && forge sync --apply --yes'
  out '  forge test --sanitize address'
  out '  forge help deps pin                      # Show options and an example'
  out ""
  out 'Run forge COMMAND --help for command-specific options.'
  out 'Exit codes: 0 success, 1 other error, 2 usage, 3 missing tool,'
  out '            4 dependency/lock, 5 build/test, 6 conflict or unsafe write.'
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
        if [[ "${scope}" == add ]]; then used["${word}"]=1; fi
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
      matches=(--source --conan --vcpkg)
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
