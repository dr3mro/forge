# shellcheck shell=bash
# shellcheck disable=SC2034  # graph globals consumed by cmake/sync/conan
# Forge workspace graph — recursive traversal of Forge.toml members.
# API: workspace_collect_graph; FORGE_GRAPH_NODES (absolute project dirs, root first).
# Inputs: [workspace].members in each reachable Forge.toml.
# Outputs: FORGE_GRAPH_NODES. Side effects: none (read-only).
# Cycles are rejected with exit 6; diamonds are visited once.

declare -A FORGE_WS_VISITED=()
declare -A FORGE_WS_PATH=()
FORGE_GRAPH_NODES=()

# Clear the collected workspace graph.
workspace_reset_graph() {
  FORGE_WS_VISITED=()
  FORGE_WS_PATH=()
  FORGE_GRAPH_NODES=()
}

# Visit a project and its descendants in manifest order.
workspace_walk() {
  local dir="$1" manifest json member child
  if [[ -n "${FORGE_WS_PATH[${dir}]+x}" ]]; then
    die "${EXIT_CONFLICT}" "workspace cycle detected at ${dir#"${FORGE_ROOT}"/}"
  fi
  [[ -n "${FORGE_WS_VISITED[${dir}]+x}" ]] && return 0
  FORGE_WS_PATH["${dir}"]=1
  FORGE_WS_VISITED["${dir}"]=1
  FORGE_GRAPH_NODES+=("${dir}")

  manifest="${dir}/Forge.toml"
  if [[ -f "${manifest}" ]]; then
    json=$(manifest_to_json "${manifest}") \
      || die "${EXIT_USAGE}" "could not parse ${manifest}"
    while IFS= read -r member; do
      [[ -n "${member}" ]] || continue
      path_is_safe_relative "${member}" \
        || die "${EXIT_USAGE}" "unsafe workspace member path: ${member}"
      child="${dir}/${member}"
      [[ -f "${child}/Forge.toml" ]] \
        || die "${EXIT_DEP}" "workspace member has no Forge.toml: ${child}"
      workspace_walk "${child}"
    done < <(printf '%s' "${json}" | jq -r '(.workspace.members // [])[]')
  fi
  unset 'FORGE_WS_PATH[$dir]'
}

# Populate the reachable workspace graph from a root project.
workspace_collect_graph() {
  local root="${1:-${FORGE_ROOT}}"
  workspace_reset_graph
  workspace_walk "${root}"
}

# Find the outermost ancestor that registers this project through workspace members.
workspace_enclosing_root() {
  local root="$1" ancestor relative json
  ancestor=$(dirname -- "${root}")
  while [[ "${ancestor}" != "${root}" ]]; do
    if [[ -f "${ancestor}/Forge.toml" ]]; then
      relative="${root#"${ancestor%/}"/}"
      json=$(manifest_to_json "${ancestor}/Forge.toml") || return 1
      if jq -e --arg member "${relative}" '(.workspace.members // []) | index($member) != null' \
          <<< "${json}" >/dev/null; then
        root="${ancestor}"
      fi
    fi
    [[ "${ancestor}" != / ]] || break
    ancestor=$(dirname -- "${ancestor}")
  done
  printf '%s\n' "${root}"
}
