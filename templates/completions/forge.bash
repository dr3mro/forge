# Bash completion for Forge (compatible with Bash 3.2).
_forge_complete() {
  local reply prefix="${COMP_WORDS[COMP_CWORD]}" count=$((COMP_CWORD - 1)) assignment=""
  COMPREPLY=()
  # Readline can split an option assignment into a flag, '=', and a value.
  if (( COMP_CWORD >= 3 )) && [[ "${COMP_WORDS[COMP_CWORD-1]}" == '=' ]]; then
    assignment="${COMP_WORDS[COMP_CWORD-2]}="
    prefix="${assignment}${prefix}"
    count=$((count - 2))
  fi
  while IFS= read -r reply; do
    COMPREPLY+=("${reply#"${assignment}"}")
  done < <(command forge __complete "${prefix}" "${COMP_WORDS[@]:1:count}")
}
complete -F _forge_complete forge
