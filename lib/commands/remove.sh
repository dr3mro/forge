# shellcheck shell=bash
# Remove a dependency or detach a generated library, then apply workspace sync.

cmd_remove() {
  local name="" library=0 member="" links
  while (( $# > 0 )); do
    case "$1" in
      --lib) library=1 ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'remove': $1" ;;
      *) [[ -z "${name}" ]] || die "${EXIT_USAGE}" "remove accepts one NAME"; name="$1" ;;
    esac
    shift
  done
  [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "remove requires a valid NAME"
  manifest_load
  sync_check_destinations "${FORGE_ROOT}"

  if (( library )); then
    member="libs/${name}"
    mq -e --arg member "${member}" '(.workspace.members // []) | index($member) != null' >/dev/null \
      || die "${EXIT_USAGE}" "no workspace library '${member}'"
    links=$(jq -cn --arg name "${name}" '[$name]')
  else
    links=$(mq_json --arg name "${name}" '.dependencies[$name] | select(.) | [$name, .cmake_target]')
    [[ -n "${links}" ]] || die "${EXIT_USAGE}" "no dependency named '${name}'"
  fi

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would remove '${name}' and sync"
    return "${EXIT_OK}"
  fi

  if (( library )); then remove_check_member_links "${member}" "${name}"; fi
  progress "Updating Forge.toml"
  manifest_remove_entry "${FORGE_MANIFEST_PATH}" "${name}" "${member}" "${links}"
  if (( library )); then
    out "detached workspace library '${member}' (sources preserved)"
  else
    out "removed dependency '${name}'"
  fi
  sync_after_manifest_edit || {
    local sync_status=$?
    fail "manifest edit saved; resolve the sync issue and run 'forge sync --apply'"
    return "${sync_status}"
  }
}


# A generated member is auto-linked in its parent. Other modules can link it
# explicitly and should remove those links before detaching the member.
remove_check_member_links() {
  local member="$1" name="$2" root node json
  root=$(workspace_enclosing_root "${FORGE_ROOT}") \
    || die "${EXIT_CONFLICT}" "could not find the enclosing workspace"
  workspace_collect_graph "${root}"
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    case "${node}" in
      "${FORGE_ROOT}"|"${FORGE_ROOT}/${member}"|"${FORGE_ROOT}/${member}/"*) continue ;;
    esac
    json=$(manifest_to_json "${node}/Forge.toml") \
      || die "${EXIT_USAGE}" "could not read ${node}/Forge.toml"
    if jq -e --arg name "${name}" '
      any(((.bin // []) + (.lib // []) + (.test // []))[];
        (.links // []) | index($name) != null)
    ' <<< "${json}" >/dev/null; then
      die "${EXIT_CONFLICT}" "remove links to '${name}' from ${node}/Forge.toml before detaching it"
    fi
  done
}
