# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by commands
# Forge sync — recursive three-way drift detection and patch application.
# API:
#   sync_prepare          # parse + validate + render every reachable project
#   sync_detect_drift     # 0 clean, 1 drift (messages in FORGE_SYNC_MESSAGES), 2 render error, 6 invalid state
#   sync_print_diff
#   sync_apply            # clean merges written; conflicts -> per-project proposals
# Inputs: workspace graph, each project's state.json and .forge/base/*.
# Outputs: messages on stdout; proposals/backups under each project's .forge/.

FORGE_SYNC_ROOT=""
FORGE_SYNC_TMP=""
declare -A FORGE_SYNC_TMP_BY_NODE=()
FORGE_SYNC_MESSAGES=()

# Read a top-level state field for the given project.
_sync_state_field() {
  jq -r --arg k "$1" '.[$k] // empty' "$2"
}

# Read a managed file's recorded hash for the given project.
_sync_state_file_hash() {
  jq -r --arg f "$1" '.files[$f] // empty' "$2"
}

# Include generated files and tracked dependencies that may need retirement.
_sync_managed_files() {
  local node="$1"
  {
    cmake_managed_files "${FORGE_SYNC_TMP_BY_NODE[${node}]:-}"
    jq -r '.files | keys[] | select(test("^cmake/deps/[A-Za-z_-][A-Za-z0-9_-]*([.]cmake|/CMakeLists[.]txt)$"))' \
      "${node}/.forge/state.json"
  } | awk '!seen[$0]++'
}

# Format a project-relative label for sync diagnostics.
_sync_label() {
  if [[ "$1" == "${FORGE_SYNC_ROOT}" ]]; then
    printf '.'
  else
    printf '%s' "${1#"${FORGE_SYNC_ROOT}"/}"
  fi
}

# Find a legacy root user.cmake that can be moved without overwriting anything.
_sync_legacy_user_cmake() {
  local node="$1"
  if [[ -f "${node}/user.cmake" && ! -L "${node}/user.cmake" \
     && ! -e "${node}/cmake/user.cmake" && ! -L "${node}/cmake/user.cmake" ]]; then
    printf '%s\n' "${node}/user.cmake"
  fi
}

# Render incoming files for every manifest in the workspace.
sync_prepare() {
  manifest_load
  state_load
  FORGE_SYNC_ROOT="${FORGE_ROOT}"
  workspace_collect_graph "${FORGE_ROOT}"
  FORGE_SYNC_TMP_BY_NODE=()

  local node saved_root saved_json saved_manifest saved_state tmp json rc=0
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    saved_root="${FORGE_ROOT}"
    saved_json="${FORGE_MANIFEST_JSON}"
    saved_manifest="${FORGE_MANIFEST_PATH}"
    saved_state="${FORGE_STATE_PATH}"

    FORGE_ROOT="${node}"
    FORGE_MANIFEST_PATH="${node}/Forge.toml"
    FORGE_STATE_PATH="${node}/.forge/state.json"

    if ! json=$(manifest_to_json "${FORGE_MANIFEST_PATH}"); then
      rc=2
    elif ! manifest_validate_json "${json}"; then
      rc=2
    elif [[ ! -f "${FORGE_STATE_PATH}" ]]; then
      fail "missing Forge state: ${FORGE_STATE_PATH}"
      rc=6
    elif ! jq -e 'type == "object" and (.files | type == "object")' "${FORGE_STATE_PATH}" >/dev/null; then
      fail "invalid Forge state: ${FORGE_STATE_PATH}"
      rc=6
    else
      FORGE_MANIFEST_JSON="${json}"
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/forge-sync.XXXXXX") || rc=2
      if (( rc == 0 )); then
        forge_add_tmpdir "${tmp}"
        if [[ "${node}" == "${FORGE_SYNC_ROOT}" && ${#FORGE_GRAPH_NODES[@]} -gt 1 ]]; then
          # The root recipe carries every reachable Conan requirement so a
          # single `conan install` covers the whole workspace.
          conan_prepare_requirements "${FORGE_SYNC_ROOT}"
          FORGE_CONAN_REQUIREMENTS_MODE="graph"
          cmake_render_all "${tmp}" || rc=2
          FORGE_CONAN_REQUIREMENTS_MODE="local"
        else
          cmake_render_all "${tmp}" || rc=2
        fi
        FORGE_SYNC_TMP_BY_NODE["${node}"]="${tmp}"
      fi
    fi

    FORGE_ROOT="${saved_root}"
    FORGE_MANIFEST_JSON="${saved_json}"
    FORGE_MANIFEST_PATH="${saved_manifest}"
    FORGE_STATE_PATH="${saved_state}"
    (( rc != 0 )) && return "${rc}"
  done
  FORGE_SYNC_TMP="${FORGE_SYNC_TMP_BY_NODE[${FORGE_SYNC_ROOT}]:-}"
  return 0
}

# Compare the manifest, current files, and incoming files across the workspace.
sync_detect_drift() {
  FORGE_SYNC_MESSAGES=()
  sync_prepare || return $?

  local node rel cur new recorded state sha recorded_sha label legacy drift=0
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    state="${node}/.forge/state.json"
    label=$(_sync_label "${node}")
    sha=$(sha256_file "${node}/Forge.toml")
    recorded_sha=$(_sync_state_field manifest "${state}")
    if [[ "${sha}" != "${recorded_sha}" ]]; then
      FORGE_SYNC_MESSAGES+=("${label}: manifest changed since last sync")
      drift=1
    fi
    if [[ -n "$(_sync_legacy_user_cmake "${node}")" ]]; then
      FORGE_SYNC_MESSAGES+=("${label}: move user.cmake into cmake/user.cmake")
      drift=1
    fi
    while IFS= read -r rel; do
      [[ -n "${rel}" ]] || continue
      cur="${node}/${rel}"
      new="${FORGE_SYNC_TMP_BY_NODE[${node}]}/${rel}"
      recorded=$(_sync_state_file_hash "${rel}" "${state}")
      if [[ ! -f "${new}" ]]; then
        if [[ -n "${recorded}" ]]; then
          if [[ "${rel}" == conanfile.txt ]]; then
            FORGE_SYNC_MESSAGES+=("${label}: Conan recipe no longer required: ${rel}")
          else
            FORGE_SYNC_MESSAGES+=("${label}: generated dependency no longer required: ${rel}")
          fi
          drift=1
        fi
        continue
      fi
      if [[ ! -f "${cur}" ]]; then
        FORGE_SYNC_MESSAGES+=("${label}: missing file: ${rel}")
        drift=1
        continue
      fi
      [[ "$(sha256_file "${new}")" == "${recorded}" ]] && continue
      if [[ "$(sha256_file "${cur}")" == "${recorded}" ]]; then
        FORGE_SYNC_MESSAGES+=("${label}: template drift: ${rel}")
      else
        FORGE_SYNC_MESSAGES+=("${label}: template + local edits: ${rel} (needs merge)")
      fi
      drift=1
    done < <(_sync_managed_files "${node}")
  done

  (( drift )) && return 1
  return 0
}

# Show pending changes to managed files across the workspace.
sync_print_diff() {
  local m node rel cur new label
  for m in "${FORGE_SYNC_MESSAGES[@]}"; do
    out "pending: ${m}"
  done
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    label=$(_sync_label "${node}")
    while IFS= read -r rel; do
      [[ -n "${rel}" ]] || continue
      cur="${node}/${rel}"
      new="${FORGE_SYNC_TMP_BY_NODE[${node}]}/${rel}"
      if [[ ! -f "${new}" ]]; then
        local recorded
        recorded=$(_sync_state_file_hash "${rel}" "${node}/.forge/state.json")
        if [[ -n "${recorded}" && -f "${cur}" && "$(sha256_file "${cur}")" == "${recorded}" ]]; then
          diff -u -- "${cur}" /dev/null || true
        fi
        continue
      fi
      if [[ -f "${cur}" ]]; then
        diff -u -- "${cur}" "${new}" || true
      else
        out "--- /dev/null"
        out "+++ ${label}/${rel}"
        sed 's/^/+/' "${new}"
      fi
    done < <(_sync_managed_files "${node}")
  done
}

# Merge incoming files into the working tree and update the recorded bases.
sync_apply() {
  progress "Checking workspace sync state"
  local rc=0
  sync_detect_drift || rc=$?
  case "${rc}" in
    0|1) progress_finish ;;
    6) die "${EXIT_CONFLICT}" "workspace state is incomplete" ;;
    *) die "${EXIT_CONFLICT}" "could not render workspace templates" ;;
  esac
  if (( rc == 0 )); then
    out "nothing to sync"
    return 0
  fi

  if (( FORGE_DRY_RUN )); then
    out "dry-run: would apply the following changes:"
    local m
    for m in "${FORGE_SYNC_MESSAGES[@]}"; do out "  ${m}"; done
    return 0
  fi
  confirm_action "Apply Forge sync changes across the workspace?" \
    || die "${EXIT_CONFLICT}" "sync aborted"

  progress "Applying workspace changes"
  local project_path member_path real_root node label legacy
  real_root=$(cd -- "${FORGE_SYNC_ROOT}" && pwd -P) \
    || die "${EXIT_CONFLICT}" "could not resolve the workspace root"
  for project_path in "${FORGE_GRAPH_NODES[@]}"; do
    member_path=$(cd -- "${project_path}" && pwd -P) \
      || die "${EXIT_CONFLICT}" "could not resolve workspace member: ${project_path}"
    [[ "${member_path}" == "${real_root}${project_path#"${FORGE_SYNC_ROOT}"}" ]] \
      || die "${EXIT_CONFLICT}" "workspace member uses an indirect path: ${project_path}"
    sync_check_destinations "${project_path}"
  done

  # Move legacy user files before rendering changes; they are never managed.
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    label=$(_sync_label "${node}")
    legacy=$(_sync_legacy_user_cmake "${node}")
    [[ -n "${legacy}" ]] || continue
    mkdir -p -- "${node}/cmake" || die "${EXIT_OTHER}" "could not create ${label}/cmake"
    mv -- "${legacy}" "${node}/cmake/user.cmake" \
      || die "${EXIT_OTHER}" "could not move ${label}/user.cmake"
    out "moved ${label}/user.cmake to cmake/user.cmake"
  done

  local rel cur base new state recorded cur_hash new_hash merged backup
  local proposal_dir backup_dir conflict=0
  for node in "${FORGE_GRAPH_NODES[@]}"; do
    label=$(_sync_label "${node}")
    state="${node}/.forge/state.json"
    proposal_dir="${node}/.forge/proposals"
    backup_dir="${node}/.forge/backups"
    mkdir -p "${proposal_dir}" "${backup_dir}" \
      || die "${EXIT_OTHER}" "could not create sync directories in ${node}"

    while IFS= read -r rel; do
      [[ -n "${rel}" ]] || continue
      cur="${node}/${rel}"
      base="${node}/.forge/base/${rel}"
      new="${FORGE_SYNC_TMP_BY_NODE[${node}]}/${rel}"
      recorded=$(_sync_state_file_hash "${rel}" "${state}")
      if [[ ! -f "${new}" ]]; then
        [[ -n "${recorded}" ]] || continue
        if [[ -f "${cur}" && "$(sha256_file "${cur}")" == "${recorded}" ]]; then
          backup="${backup_dir}/${rel//\//_}.$(date +%s).$$"
          mv -- "${cur}" "${backup}" || die "${EXIT_OTHER}" "could not retire ${label}/${rel}"
          out "removed unused ${label}/${rel} (backup: ${backup#"${node}"/})"
        elif [[ -e "${cur}" ]]; then
          warn "keeping locally edited ${label}/${rel} as a user-owned file"
        fi
        rm -f -- "${base}" || die "${EXIT_OTHER}" "could not remove the unused base for ${rel}"
        jq --arg f "${rel}" 'del(.files[$f])' "${state}" | atomic_write "${state}" \
          || die "${EXIT_OTHER}" "could not update state for ${label}/${rel}"
        continue
      fi

      new_hash=$(sha256_file "${new}")
      if [[ -z "${recorded}" ]]; then
        if [[ -e "${cur}" ]]; then
          if [[ ! -f "${cur}" || "$(sha256_file "${cur}")" != "${new_hash}" ]]; then
            local owner="user-owned file"
            if [[ "${rel}" == conanfile.txt ]]; then owner="user-owned recipe"; fi
            out "conflict: ${label}/${rel} (${owner})"
            atomic_write "${proposal_dir}/${rel//\//_}.patch" < "${new}" \
              || die "${EXIT_OTHER}" "could not write proposal for ${label}/${rel}"
            conflict=1
            continue
          fi
        else
          mkdir -p -- "${cur%/*}" && (set -o noclobber; cat "${new}" > "${cur}") \
            || die "${EXIT_OTHER}" "could not create ${label}/${rel}"
        fi
        atomic_write "${base}" < "${new}" || die "${EXIT_OTHER}" "could not record base for ${rel}"
        jq --arg f "${rel}" --arg h "${new_hash}" '.files[$f] = $h' "${state}" | atomic_write "${state}" \
          || die "${EXIT_OTHER}" "could not record state for ${label}/${rel}"
        continue
      fi
      if [[ ! -f "${cur}" || ! -f "${base}" ]]; then
        out "conflict: ${label}/${rel} (missing current or base copy)"
        atomic_write "${proposal_dir}/${rel//\//_}.patch" < "${new}" \
          || die "${EXIT_OTHER}" "could not write proposal for ${label}/${rel}"
        conflict=1
        continue
      fi

      [[ "${new_hash}" != "${recorded}" ]] || continue
      cur_hash=$(sha256_file "${cur}")
      if [[ "${cur_hash}" == "${recorded}" ]]; then
        atomic_write "${cur}" < "${new}" \
          || die "${EXIT_OTHER}" "could not write ${label}/${rel}"
      else
        if ! merged=$(git merge-file -p -L current -L base -L incoming \
                "${cur}" "${base}" "${new}" 2>/dev/null); then
          {
            printf '# Forge sync conflict for %s\n' "${label}/${rel}"
            printf '# Resolve by hand, then re-run forge sync --apply.\n\n'
            printf '%s\n' "${merged}"
          } | atomic_write "${proposal_dir}/${rel//\//_}.patch" \
            || die "${EXIT_OTHER}" "could not write proposal for ${label}/${rel}"
          out "conflict: ${label}/${rel} -> .forge/proposals/${rel//\//_}.patch"
          conflict=1
          continue
        fi
        backup="${backup_dir}/${rel//\//_}.$(date +%s)"
        atomic_write "${backup}" < "${cur}" \
          || die "${EXIT_OTHER}" "could not write backup for ${label}/${rel}"
        printf '%s\n' "${merged}" | atomic_write "${cur}" \
          || die "${EXIT_OTHER}" "could not write merge for ${label}/${rel}"
        out "merged: ${label}/${rel} (backup: ${backup#"${node}"/})"
      fi
      atomic_write "${base}" < "${new}" \
        || die "${EXIT_OTHER}" "could not update base for ${label}/${rel}"
      jq --arg f "${rel}" --arg h "${new_hash}" '.files[$f] = $h' "${state}" \
        | atomic_write "${state}" \
        || die "${EXIT_OTHER}" "could not update state for ${label}/${rel}"
    done < <(_sync_managed_files "${node}")

    jq --arg h "$(sha256_file "${node}/Forge.toml")" '.manifest = $h' "${state}" \
      | atomic_write "${state}" \
      || die "${EXIT_OTHER}" "could not update manifest state for ${label}"
  done

  progress_finish "${conflict}"
  (( conflict )) && return "${EXIT_CONFLICT}"
  out "sync applied across $((${#FORGE_GRAPH_NODES[@]})) project(s)"
  return 0
}

# Refuse indirect sync destinations before changing managed files.
sync_check_destinations() {
  local root="$1" rel
  local -a paths=(cmake cmake/user.cmake cmake/deps .forge .forge/state.json .forge/base
    .forge/base/cmake .forge/base/cmake/deps .forge/backups .forge/proposals)
  while IFS= read -r rel; do
    paths+=("${rel}" ".forge/base/${rel}")
    if [[ "${rel}" == cmake/deps/* ]]; then
      paths+=("${rel%/*}" ".forge/base/${rel%/*}")
    fi
  done < <(_sync_managed_files "${root}")
  for rel in "${paths[@]}"; do
    [[ ! -L "${root}/${rel}" ]] \
      || die "${EXIT_CONFLICT}" "refusing to sync a symlinked path: ${root}/${rel}"
  done
}

# Apply generated changes after an explicit manifest edit using the workspace root.
sync_after_manifest_edit() {
  local root
  root=$(workspace_enclosing_root "${FORGE_ROOT}") \
    || die "${EXIT_CONFLICT}" "could not find the enclosing workspace"
  local FORGE_YES=1
  if [[ "${root}" != "${FORGE_ROOT}" ]]; then
    FORGE_MANIFEST_PATH="${root%/}/Forge.toml"
  fi
  sync_apply
}
