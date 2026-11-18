# shellcheck shell=bash
# vcpkg workspace manifest and CMake integration.

# Build a deterministic vcpkg manifest for the workspace root.
vcpkg_workspace_manifest() {
  local node json records baseline
  workspace_collect_graph "${FORGE_ROOT}" || return 1
  records=$(
    for node in "${FORGE_GRAPH_NODES[@]}"; do
      json=$(manifest_to_json "${node}/Forge.toml") || exit 1
      jq -c '(.dependencies // {})[] | select(.source == "vcpkg")
        | {port, version, features: ((.features // []) | unique), default_features: (.default_features != false)}' \
        <<< "${json}" || exit 1
    done
  ) || return 1
  [[ -n "${records}" ]] || return 0
  baseline=$(mq '.build.vcpkg_baseline // ""') || return 1
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
