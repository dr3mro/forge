# shellcheck shell=bash
# vcpkg workspace manifest and CMake integration.

# An imported vcpkg target cannot also be defined by the consuming project.
vcpkg_target_is_local() {
  jq -e --arg name "$1" 'any(((.bin // []) + (.lib // []) + (.test // []))[]; .name == $name)' \
    <<< "$2" >/dev/null
}

# Pin the current Git checkout when the workspace has no registry baseline yet.
vcpkg_registry_baseline() {
  local root="${VCPKG_ROOT:-}" baseline
  [[ -n "${root}" ]] || die "${EXIT_TOOL}" "set VCPKG_ROOT to a Git checkout of vcpkg to record a baseline"
  require_tool git
  baseline=$(git -C "${root}" rev-parse --verify HEAD 2>/dev/null) \
    && [[ "${baseline}" =~ ^[0-9a-fA-F]{40}$ ]] \
    && git -C "${root}" cat-file -e "${baseline}:versions/baseline.json" 2>/dev/null \
    || die "${EXIT_DEP}" "could not read the registry baseline from VCPKG_ROOT"
  printf '%s' "${baseline}"
}

# Build a deterministic vcpkg manifest for the workspace root.
vcpkg_workspace_manifest() {
  local node json records baseline imported root
  workspace_collect_graph "${FORGE_ROOT}" || return 1
  records=$(
    for node in "${FORGE_GRAPH_NODES[@]}"; do
      json=$(manifest_to_json "${node}/Forge.toml") || exit 1
      while IFS= read -r imported; do
        if vcpkg_target_is_local "${imported}" "${json}"; then
          fail "${node}/Forge.toml: vcpkg cmake_target '${imported}' names a project target"
          exit 1
        fi
      done < <(jq -r '(.dependencies // {})[] | select(.source == "vcpkg") | .cmake_target' <<< "${json}")
      jq -c '(.dependencies // {})[] | select(.source == "vcpkg")
        | {port, version, features: ((.features // []) | unique), default_features: (.default_features != false)}' \
        <<< "${json}" || exit 1
    done
  ) || return 1
  [[ -n "${records}" ]] || return 0
  baseline=$(mq '.build.vcpkg_baseline // ""') || return 1
  if [[ -z "${baseline}" ]] && jq -es 'any(.[]; .version != null)' <<< "${records}" >/dev/null; then
    root=$(workspace_enclosing_root "${FORGE_ROOT}") || return 1
    if [[ "${root}" != "${FORGE_ROOT}" ]]; then
      json=$(manifest_to_json "${root}/Forge.toml") || return 1
      baseline=$(jq -r '.build.vcpkg_baseline // ""' <<< "${json}") || return 1
    fi
  fi
  jq -cs --arg baseline "${baseline}" '
    group_by(.port) | map(unique) |
    if any(length > 1) then error("conflicting vcpkg settings for a workspace port") else map(.[0]) end |
    (map(select(.version != null) | {name: .port, version})) as $versions |
    if ($versions | length > 0) and $baseline == "" then error("vcpkg versions require build.vcpkg_baseline at the workspace root") else
      {dependencies: map(
        if (.features | length) == 0 and .default_features then .port
        else {name: .port, features, "default-features": .default_features} end
      )} + (if $baseline == "" then {} else {"builtin-baseline": $baseline} end)
        + (if ($versions | length) == 0 then {} else {overrides: $versions} end)
    end
  ' <<< "${records}"
}

# Reject a version the local registry does not offer, listing every one it does.
vcpkg_validate_version() {
  local port="$1" version="$2" root="${VCPKG_ROOT:-}" file listed base port_revision
  [[ -n "${root}" ]] || return 0
  [[ "${version}" =~ ^([^#]+)(#([0-9]+))?$ ]] || return 0
  base="${BASH_REMATCH[1]}"
  port_revision="${BASH_REMATCH[3]:-0}"
  file="${root}/versions/${port:0:1}-/${port}.json"
  [[ -f "${file}" ]] || return 0
  listed=$(jq -r '.versions[]?
    | (.["version-string"] // .version // .["version-semver"] // .["version-date"]) as $v
    | (."port-version" // 0) as $p
    | "\($v)#\($p)"' "${file}" 2>/dev/null) || return 0
  [[ -n "${listed}" ]] || return 0
  grep -Fxq "${base}#${port_revision}" <<< "${listed}" && return 0
  local display
  display=$(jq -r '[.versions[]?
    | (.["version-string"] // .version // .["version-semver"] // .["version-date"]) as $v
    | (."port-version" // 0) as $p
    | if $p == 0 then $v else "\($v)#\($p)" end] | join(", ")' "${file}" 2>/dev/null)
  die "${EXIT_DEP}" "${port}/${version} is not available in VCPKG_ROOT. Available versions: ${display}"
}

# Set up manifest mode in the build directory and pass its options to CMake.
vcpkg_prepare_configure() {
  local build_dir="$1" previous_toolchain="$2" manifest="$3"
  local root="${VCPKG_ROOT:-}" manifest_dir="${build_dir}/.forge-vcpkg"
  [[ -n "${root}" ]] || die "${EXIT_TOOL}" "set VCPKG_ROOT to your bootstrapped vcpkg checkout"
  local toolchain
  toolchain="$(abspath "${root}")/scripts/buildsystems/vcpkg.cmake"
  [[ -f "${toolchain}" && -x "${root}/vcpkg" ]] \
    || die "${EXIT_TOOL}" "VCPKG_ROOT must contain vcpkg and its CMake toolchain"
  local install=ON
  if (( FORGE_OFFLINE )); then
    [[ -f "${build_dir}/CMakeCache.txt" ]] \
      || die "${EXIT_DEP}" "offline vcpkg requires an already configured build (run a connected build first)"
    install=OFF
  fi
  [[ ! -L "${FORGE_ROOT}/target" && ! -L "${build_dir}" && ! -L "${manifest_dir}" && ! -L "${manifest_dir}/vcpkg.json" ]] \
    || die "${EXIT_CONFLICT}" "refusing to write a symlinked vcpkg manifest"
  printf '%s\n' "${manifest}" \
    | atomic_write "${manifest_dir}/vcpkg.json" \
    || die "${EXIT_OTHER}" "could not write the generated vcpkg manifest"
  FORGE_EXTRA_CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=${toolchain}" "-DVCPKG_MANIFEST_DIR=${manifest_dir}"
    "-DVCPKG_MANIFEST_INSTALL:BOOL=${install}")
  if [[ -n "${previous_toolchain}" ]]; then
    FORGE_EXTRA_CMAKE_ARGS+=("-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$(abspath "${previous_toolchain}")")
  fi
}
