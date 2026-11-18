# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by other modules
# Forge state — tool-owned .forge/state.json and base-file copies.
# API:
#   state_init               # create dirs + state.json once
#   state_load               # set FORGE_STATE_PATH, validate presence
#   state_read KEY           # top-level string value
#   state_set KEY VALUE
#   state_file_hash REL      # recorded hash for a managed file (empty if none)
#   state_set_file_hash REL HASH
#   state_manifest_sha / state_set_manifest_sha HASH
#   state_record_generated   # snapshot manifest + all managed base files
# Inputs: FORGE_ROOT. Outputs: files under .forge/.
# Side effects: writes .forge/state.json and .forge/base/*.

FORGE_STATE_PATH=""

# Create Forge's state directories and initial state document.
state_init() {
  local root="${FORGE_ROOT:-${PWD}}" d
  for d in base proposals backups; do
    mkdir -p "${root}/.forge/${d}"
  done
  mkdir -p "${root}/target"
  FORGE_STATE_PATH="${root}/.forge/state.json"
  if [[ ! -f "${FORGE_STATE_PATH}" ]]; then
    jq -n '{version: 1, template_id: "base", template_version: "1.0.0", manifest: "", files: {}}' \
      | atomic_write "${FORGE_STATE_PATH}"
  fi
}

# Locate the current project's state and require that it exists.
state_load() {
  FORGE_STATE_PATH="${FORGE_ROOT}/.forge/state.json"
  [[ -f "${FORGE_STATE_PATH}" ]] \
    || die "${EXIT_CONFLICT}" "Forge state is missing: ${FORGE_STATE_PATH} (run 'forge sync --apply')"
}

# Read a top-level value from the state document.
state_read() {
  jq -r --arg k "$1" '.[$k] // empty' "${FORGE_STATE_PATH}"
}

# Atomically update a top-level value in the state document.
state_set() {
  local key="$1" value="$2"
  jq --arg k "${key}" --arg v "${value}" '.[$k] = $v' "${FORGE_STATE_PATH}" \
    | atomic_write "${FORGE_STATE_PATH}"
}

# Read the recorded hash for a managed path.
state_file_hash() {
  jq -r --arg f "$1" '.files[$f] // empty' "${FORGE_STATE_PATH}"
}

# Atomically record a hash for a managed path.
state_set_file_hash() {
  local rel="$1" hash="$2"
  jq --arg f "${rel}" --arg h "${hash}" '.files[$f] = $h' "${FORGE_STATE_PATH}" \
    | atomic_write "${FORGE_STATE_PATH}"
}

# Read the hash of the last synced manifest.
state_manifest_sha() {
  state_read manifest
}

# Record the hash of the synced manifest.
state_set_manifest_sha() {
  state_set manifest "$1"
}

# Snapshot the freshly generated files as the new base, and record their hashes.
state_record_generated() {
  local root="${FORGE_ROOT}" rel
  state_set_manifest_sha "$(sha256_file "${root}/Forge.toml")"
  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    mkdir -p "${root}/.forge/base/$(dirname -- "${rel}")"
    cp "${root}/${rel}" "${root}/.forge/base/${rel}"
    state_set_file_hash "${rel}" "$(sha256_file "${root}/${rel}")"
  done < <(cmake_managed_files)
}
