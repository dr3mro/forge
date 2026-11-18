# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by other modules
# Forge dependency diagnostics and collision detection.
# API: manifest_collisions deps_check_collisions cmd_deps
#      deps_lock deps_pin deps_status
# Inputs: FORGE_MANIFEST_JSON, FORGE_ROOT, conan/fetchcontent helpers.
# Outputs: dependency reports; conan.lock; manifest edits.

DEPS_COLLISION_FILTER='
  [((.dependencies // {}) | to_entries[] | .value.cmake_target)] as $cts
  | [((.dependencies // {}) | to_entries[] | select(.value.source == "conan") | .value.ref)] as $refs
  | [((.bin // []) + (.lib // []) + (.test // []) | .[].name)] as $targets
  | [((.dependencies // {}) | keys[])] as $keys
  | (
      ($cts | group_by(.) | map(select(length > 1) | .[0]) | .[]
        | "duplicate cmake_target: " + .),
      ($refs | group_by(.) | map(select(length > 1) | .[0]) | .[]
        | "duplicate conan ref: " + .),
      ($keys[] as $k | $targets[] as $t | select($k == $t)
        | "name collision with target: " + $k)
    )
'

# Report duplicate Conan references and link targets, and dependency names that collide with project targets.
manifest_collisions() {
  printf '%s' "${FORGE_MANIFEST_JSON}" | jq -r "${DEPS_COLLISION_FILTER}"
}

# Check every manifest in the reachable workspace graph, including duplicate
# CMake target names exported by different members.
deps_check_collisions() {
  local node json line target dup errs="" label
  local -A target_owner=()
  workspace_collect_graph "${FORGE_ROOT}"
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    [[ -f "${node}/Forge.toml" ]] || continue
    json=$(manifest_to_json "${node}/Forge.toml") || continue
    label="${node#"${FORGE_ROOT}"/}"
    [[ -n "${label}" ]] || label="root"
    while IFS= read -r line; do
      [[ -n "${line}" ]] && errs+="${label}: ${line}"$'\n'
    done < <(printf '%s' "${json}" | jq -r "${DEPS_COLLISION_FILTER}")

    while IFS= read -r target; do
      [[ -n "${target}" ]] || continue
      if [[ -n "${target_owner[${target}]+x}" && "${target_owner[${target}]}" != "${node}" ]]; then
        errs+="${label}: target name collision '${target}' also defined in ${target_owner[${target}]#"${FORGE_ROOT}"/}"$'\n'
      fi
      target_owner["${target}"]="${node}"
    done < <(printf '%s' "${json}" | jq -r '
      (((.bin // []) + (.lib // []) + (.test // []) | .[].name),
       (.dependencies // {} | to_entries[] | .value.cmake_target))')
  done

  [[ -z "${errs}" ]] && return 0
  while IFS= read -r line; do
    [[ -n "${line}" ]] && fail "${line}"
  done <<< "${errs}"
  return 1
}

# Refresh the Conan lock for the workspace.
deps_lock() {
  manifest_load
  deps_check_collisions || die "${EXIT_DEP}" "dependency collisions detected"
  if conan_graph_has_deps; then
    conan_lock_create
  else
    out "no Conan dependencies to lock"
  fi
}

# Resolve a Git dependency to a commit and save it in the manifest.
deps_pin() {
  local name="" tag="" branch="" sha=""
  while (( $# > 0 )); do
    case "$1" in
      --tag)     [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; tag="${2:-}"; shift 2 ;;
      --branch)  [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; branch="${2:-}"; shift 2 ;;
      --sha)     [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; sha="${2:-}"; shift 2 ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'deps pin': $1" ;;
      *) [[ -z "${name}" ]] || die "${EXIT_USAGE}" "deps pin accepts one NAME"; name="$1"; shift ;;
    esac
  done
  [[ -n "${name}" ]] || die "${EXIT_USAGE}" "deps pin requires a dependency NAME"
  manifest_load
  local src url current
  src=$(mq --arg n "${name}" '(.dependencies // {})[$n].source // empty')
  [[ -n "${src}" ]] || die "${EXIT_USAGE}" "no dependency named '${name}'"
  [[ "${src}" == "git" ]] || die "${EXIT_USAGE}" "'${name}' is not a git dependency"
  url=$(mq --arg n "${name}" '(.dependencies // {})[$n].url')

  if [[ -n "${sha}" ]]; then
    [[ "${sha}" =~ ^[0-9a-fA-F]{40}$ ]] \
      || die "${EXIT_USAGE}" "--sha must be a full 40-char commit SHA"
  elif [[ -n "${tag}" || -n "${branch}" ]]; then
    [[ "${tag}" != "${branch}" ]] || die "${EXIT_USAGE}" "use either --tag or --branch"
    if (( FORGE_OFFLINE )); then
      die "${EXIT_DEP}" "--offline cannot resolve a tag/branch; supply --sha"
    fi
    current="${tag:-${branch}}"
    sha=$(fetchcontent_resolve_ref "${url}" "${current}")
  else
    die "${EXIT_USAGE}" "deps pin needs --tag, --branch or --sha"
  fi

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would pin '${name}' to ${sha}"
    return "${EXIT_OK}"
  fi
  manifest_set_dep_field "${FORGE_MANIFEST_PATH}" "${name}" rev "${sha}"
  out "pinned ${name} -> ${sha}"
  status "run 'forge sync --diff' then 'forge sync --apply' to update CMake"
}

# Report dependency sources, lock state, and generated-file drift.
deps_status() {
  local format="text"
  while (( $# > 0 )); do
    case "$1" in
      --format) [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; format="${2:-}"; shift 2 ;;
      --format=*) format="${1#*=}"; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'deps status': $1" ;;
      *) die "${EXIT_USAGE}" "deps status accepts no positional arguments" ;;
    esac
  done
  [[ "${format}" == text || "${format}" == json ]] \
    || die "${EXIT_USAGE}" "--format must be text or json"

  manifest_load
  local report rc=0
  report=$(printf '%s' "${FORGE_MANIFEST_JSON}" | jq -r '
    [((.dependencies // {}) | to_entries[] | {
        name: .key,
        source: .value.source,
        cmake_target: .value.cmake_target,
        state: (if .value.source == "git" then
                  (if (.value.rev | test("^[0-9a-fA-F]{40}$")) then "pinned" else "invalid-sha" end)
                elif .value.source == "conan" then "conan"
                elif .value.source == "vcpkg" then "vcpkg"
                else "path" end)
      })]')
  local lock_state="absent" drift="clean"
  [[ -f "${FORGE_ROOT}/conan.lock" ]] && lock_state="present"
  if [[ -f "${FORGE_ROOT}/conan.lock" ]] && conan_lock_stale; then
    lock_state="stale"
  fi
  local rc_sync=0
  sync_detect_drift || rc_sync=$?
  (( rc_sync == 1 )) && drift="drift"
  if ! deps_check_collisions; then drift="collision"; rc="${EXIT_DEP}"; fi

  if [[ "${format}" == "json" ]]; then
    jq -n --argjson deps "${report}" --arg lock "${lock_state}" --arg d "${drift}" \
      '{dependencies: $deps, conan_lock: $lock, manifest_sync: $d}'
  else
    local row
    out "conan.lock: ${lock_state}"
    out "manifest sync: ${drift}"
    while IFS= read -r row; do
      out "${row}"
    done < <(printf '%s' "${report}" | jq -r '.[] | "\(.name)\t\(.source)\t\(.state)\t\(.cmake_target)"')
  fi
  (( rc == 0 )) || return "${rc}"
  return "${EXIT_OK}"
}

# Dispatch the dependency subcommand.
cmd_deps() {
  local sub="${1:-status}"
  (( $# > 0 )) && shift
  case "${sub}" in
    lock)   deps_lock "$@" ;;
    pin)    deps_pin "$@" ;;
    status) deps_status "$@" ;;
    *) die "${EXIT_USAGE}" "unknown deps subcommand: ${sub} (use lock, pin or status)" ;;
  esac
}
