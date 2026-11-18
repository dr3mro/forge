# shellcheck shell=bash
# shellcheck disable=SC2034  # global flags consumed by cmake.sh
# Forge command: build.

# Shared configure+compile routine (also used by sanitizer test builds).
forge_perform_build() {
  local build_dir="$1" profile="$2" gen="$3" toolchain="${4:-}" target="${5:-}"
  local vcpkg_manifest install=ON
  vcpkg_manifest=$(vcpkg_workspace_manifest) || die "${EXIT_DEP}" "could not resolve vcpkg manifest"
  (( ! FORGE_OFFLINE )) || install=OFF
  if ! cmake_is_configured "${build_dir}" "${gen}" ||
    { [[ -n "${vcpkg_manifest}" ]] && ! grep -Fxq "VCPKG_MANIFEST_INSTALL:BOOL=${install}" "${build_dir}/CMakeCache.txt"; }; then
    progress "Configuring CMake (${profile})"
    cmake_configure "${build_dir}" "${profile}" "${gen}" "${toolchain}"
  else
    status "reusing configured build: ${build_dir#"${FORGE_ROOT}"/}"
  fi
  local -a bargs=(--build "${build_dir}" --config "${profile}" --parallel "$(forge_jobs)")
  [[ -n "${target}" ]] && bargs+=(--target "${target}")
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would run cmake ${bargs[*]}"
    return 0
  fi
  progress "Compiling ${target:-project}"
  run_cmd cmake "${bargs[@]}" || die "${EXIT_BUILD}" "build failed"
  link_compile_commands "${build_dir}"
}

# Validate project state and build the selected profile or target.
cmd_build() {
  local release=0 target="" toolchain="" debug_target=""
  while (( $# > 0 )); do
    case "$1" in
      --debug-target) debug_target="${2:-}"; [[ -n "${debug_target}" ]] || die "${EXIT_USAGE}" "--debug-target requires a name"; shift 2 ;;
      --release) release=1; shift ;;
      --target)  target="${2:-}"; [[ -n "${target}" ]] || die "${EXIT_USAGE}" "--target requires a value"; shift 2 ;;
      --target=*) target="${1#*=}"; shift ;;
      --toolchain) toolchain="${2:-}"; [[ -n "${toolchain}" ]] || die "${EXIT_USAGE}" "--toolchain requires a value"; shift 2 ;;
      --toolchain=*) toolchain="${1#*=}"; shift ;;
      --link-compile-commands) FORGE_LINK_COMPILE_COMMANDS=1; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'build': $1" ;;
      *) die "${EXIT_USAGE}" "build accepts no positional arguments" ;;
    esac
  done

  if [[ -n "${debug_target}" ]]; then
    [[ -z "${target}" && "${release}" == 0 ]] \
      || die "${EXIT_USAGE}" "--debug-target cannot be combined with --target or --release"
    target="${debug_target}"
  fi

  manifest_load

  # Build never regenerates CMake: drift is a hard failure with a repair hint.
  local rc=0
  progress "Checking Forge sync state"
  sync_detect_drift || rc=$?
  if (( rc == 1 )); then
    fail "manifest/CMake drift detected:"
    local m
    for m in "${FORGE_SYNC_MESSAGES[@]}"; do fail "  ${m}"; done
    die "${EXIT_CONFLICT}" "run 'forge sync --diff', then 'forge sync --apply --yes'"
  fi
  (( rc == 2 )) && die "${EXIT_CONFLICT}" "could not check Forge sync state"

  local profile gen fp build_dir
  if (( release )); then
    profile="release"
  elif [[ -n "${debug_target}" ]]; then
    profile="debug"
  else
    profile=$(mq '.build.default_profile // "debug"')
  fi
  gen=$(normalize_generator "$(mq '.build.generator // "Ninja"')")

  [[ -z "${toolchain}" || -f "${toolchain}" ]] \
    || die "${EXIT_USAGE}" "toolchain file not found: ${toolchain}"
  [[ -z "${target}" || "${target}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid target name: ${target}"

  jq -e --arg p "${profile}" '.configurePresets[] | select(.name == $p)' \
    "${FORGE_ROOT}/CMakePresets.json" >/dev/null 2>&1 \
    || die "${EXIT_USAGE}" "no CMake preset for profile '${profile}' (expected debug or release)"

  fp=$(compute_fingerprint "${profile}" "${toolchain}") || die "${EXIT_DEP}" "could not compute build fingerprint"
  build_dir="${FORGE_ROOT}/target/${profile}-${fp}"

  # Mixed policy: Conan installs first, then CMake configures and FetchContent runs.
  local effective_toolchain="${toolchain}"
  if conan_graph_has_deps; then
    conan_prepare_requirements "${FORGE_ROOT}"
    FORGE_CONAN_REQUIREMENTS_MODE="graph"
    conan_install "${build_dir}" "${profile}"
    FORGE_CONAN_REQUIREMENTS_MODE="local"
    local ctc
    ctc=$(conan_toolchain_path "${build_dir}")
    [[ -n "${ctc}" ]] && effective_toolchain="${ctc}"
  fi

  if (( FORGE_OFFLINE )) && fetchcontent_has_deps; then
    fetchcontent_sources_populated "${build_dir}" \
      || die "${EXIT_DEP}" "offline build requires populated Git sources (run a connected build first)"
    FORGE_EXTRA_CMAKE_ARGS+=("-DFETCHCONTENT_FULLY_DISCONNECTED=ON")
  fi

  forge_perform_build "${build_dir}" "${profile}" "${gen}" "${effective_toolchain}" "${target}"
  if [[ -n "${debug_target}" ]] && (( ! FORGE_DRY_RUN )); then
    link_debug_executable "${debug_target}" "${build_dir}"
  fi
  out "build ok: ${build_dir#"${FORGE_ROOT}"/}"
}

# Give LLDB a stable executable path while keeping Forge's fingerprinted builds.
link_debug_executable() {
  local target="$1" build_dir="$2" executable
  executable=$(cmake_executable_path "${target}" "${build_dir}") \
    && [[ -f "${executable}" && -x "${executable}" ]] \
    || die "${EXIT_BUILD}" "no built executable for '${target}'"
  python3 - "${FORGE_ROOT}/target" "${target}" "${executable}" <<'PYTHON' \
    || die "${EXIT_CONFLICT}" "could not link the debug executable"
import os
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

target_dir, name, executable = map(Path, sys.argv[1:])
link = target_dir / ("debug-" + name.name + "-launch")
destination = os.path.relpath(executable, target_dir)
if link.is_symlink():
    prior = link.readlink()
    if not prior.parts or not re.fullmatch(r"debug-[0-9a-f]+", prior.parts[0]) or ".." in prior.parts:
        sys.exit(f"refusing to overwrite {link}")
elif link.exists():
    sys.exit(f"refusing to overwrite {link}")

with TemporaryDirectory(dir=target_dir) as staging:
    staged_link = Path(staging) / "executable"
    staged_link.symlink_to(destination)
    os.replace(staged_link, link)
PYTHON
}
