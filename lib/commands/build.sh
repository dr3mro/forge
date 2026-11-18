# shellcheck shell=bash
# shellcheck disable=SC2034  # global flags consumed by cmake.sh
# Forge command: build.

# Shared configure+compile routine (also used by sanitizer test builds).
forge_perform_build() {
  local build_dir="$1" profile="$2" gen="$3" toolchain="${4:-}" target="${5:-}"
  local vcpkg_manifest fingerprint cached="" fresh=0 stamp="${build_dir}/.forge-config"
  vcpkg_manifest=$(vcpkg_workspace_manifest) || die "${EXIT_DEP}" "could not resolve vcpkg manifest"
  fingerprint=$(compute_fingerprint "${profile}" "${toolchain}" "${vcpkg_manifest}") \
    || die "${EXIT_DEP}" "could not compute build fingerprint"
  if [[ -n "${vcpkg_manifest}" ]]; then fingerprint+=":offline=${FORGE_OFFLINE}"; fi
  if (( ! FORGE_DRY_RUN )); then
    conan_prune_user_presets \
      || die "${EXIT_CONFLICT}" "could not refresh Conan's generated preset includes"
  fi
  [[ ! -f "${stamp}" ]] || IFS= read -r cached < "${stamp}"
  if [[ "${cached}" != "${fingerprint}" ]] || ! cmake_is_configured "${build_dir}" "${gen}"; then
    if [[ -f "${build_dir}/CMakeCache.txt" && "${cached}" != "${fingerprint}" ]]; then fresh=1; fi
    if (( ! FORGE_DRY_RUN )); then
      progress "Configuring CMake (${profile})"
      rm -f -- "${stamp}" || die "${EXIT_CONFLICT}" "could not invalidate build fingerprint"
    fi
    cmake_configure "${build_dir}" "${profile}" "${toolchain}" "${vcpkg_manifest}" "${fresh}"
    if (( ! FORGE_DRY_RUN )); then
      printf '%s\n' "${fingerprint}" | atomic_write "${stamp}" \
        || die "${EXIT_OTHER}" "could not record build fingerprint"
      progress_finish
    fi
  else
    status "reusing configured build: ${build_dir#"${FORGE_ROOT}"/}"
  fi
  local -a bargs=(--build "${build_dir}" --config "${profile}" --parallel "$(forge_jobs)")
  [[ -n "${target}" ]] && bargs+=(--target "${target}")
  [[ "${FORGE_CLEAN_FIRST:-0}" != 1 ]] || bargs+=(--clean-first)
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would run cmake ${bargs[*]}"
    return 0
  fi
  progress "Compiling ${target:-project}"
  run_cmd cmake "${bargs[@]}" || die "${EXIT_BUILD}" "build failed"
  progress_finish
  if [[ -z "${FORGE_SANITIZER}" ]]; then link_compile_commands "${build_dir}"; fi
}

# Validate project state and build the selected profile or target.
cmd_build() {
  local release=0 target="" toolchain="" debug_target="" sanitize=""
  while (( $# > 0 )); do
    case "$1" in
      --debug-target) debug_target="${2:-}"; [[ -n "${debug_target}" ]] || die "${EXIT_USAGE}" "--debug-target requires a name"; shift 2 ;;
      --release) release=1; shift ;;
      --clean-first) FORGE_CLEAN_FIRST=1; shift ;;
      --sanitize) sanitize="${2:-}"; [[ -n "${sanitize}" ]] || die "${EXIT_USAGE}" "--sanitize requires a value"; shift 2 ;;
      --sanitize=*) sanitize="${1#*=}"; shift ;;
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

  if [[ -n "${sanitize}" ]]; then
    forge_enable_sanitizer "${sanitize}"
  fi

  manifest_load

  local profile
  if (( release )); then
    profile="release"
  elif [[ -n "${debug_target}" ]]; then
    profile="debug"
  else
    profile=$(mq '.build.default_profile // "debug"')
  fi
  build_project "${profile}" "${target}" "${toolchain}" "${debug_target}"
}

# Validate, configure, and build the loaded project for the selected profile.
build_project() {
  local profile="$1" target="$2" toolchain="${3:-}" debug_target="${4:-}"
  # Build never regenerates CMake: drift is a hard failure with a repair hint.
  local rc=0
  progress "Checking Forge sync state"
  sync_detect_drift || rc=$?
  if (( rc == 1 )); then
    fail "manifest/CMake drift detected:"
    local m
    for m in "${FORGE_SYNC_MESSAGES[@]}"; do fail "  ${m}"; done
    if offer_fix "Sync generated files and retry the build?" sync_apply; then
      progress_finish
      rc=0
    else
      die "${EXIT_CONFLICT}" "run 'forge sync --diff', then 'forge sync --apply --yes'"
    fi
  fi
  (( rc == 0 )) || die "${EXIT_CONFLICT}" "could not check Forge sync state"
  progress_finish

  local gen build_dir
  gen=$(normalize_generator "$(mq '.build.generator // "Ninja"')")

  [[ -z "${toolchain}" || -f "${toolchain}" ]] \
    || die "${EXIT_USAGE}" "toolchain file not found: ${toolchain}"
  [[ -z "${target}" || "${target}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "${EXIT_USAGE}" "invalid target name: ${target}"

  jq -e --arg p "${profile}" '.configurePresets[] | select(.name == $p)' \
    "${FORGE_ROOT}/CMakePresets.json" >/dev/null 2>&1 \
    || die "${EXIT_USAGE}" "no CMake preset for profile '${profile}' (expected debug or release)"

  build_dir=$(resolve_build_dir "${profile}") || die "${EXIT_USAGE}" "invalid build profile: ${profile}"
  cmake_check_build_path "${build_dir}"
  build_lock_acquire "${build_dir}"

  # Mixed policy: Conan installs first, then CMake configures and FetchContent runs.
  local effective_toolchain="${toolchain}"
  if conan_graph_has_deps; then
    conan_prepare_requirements "${FORGE_ROOT}"
    FORGE_CONAN_REQUIREMENTS_MODE="graph"
    cmake_check_build_path "${build_dir}/.forge-conan"
    conan_install "${build_dir}/.forge-conan" "${profile}"
    FORGE_CONAN_REQUIREMENTS_MODE="local"
    local ctc
    ctc=$(conan_toolchain_path "${build_dir}/.forge-conan")
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
  build_lock_release
  out "build ok: ${build_dir#"${FORGE_ROOT}"/}"
}

# Keep the stable LLDB launch link when migrating from an older build tree.
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
    if not prior.parts or not re.fullmatch(r"debug(?:-[0-9a-f]{12})?", prior.parts[0]) or ".." in prior.parts:
        sys.exit(f"refusing to overwrite {link}")
elif link.exists():
    sys.exit(f"refusing to overwrite {link}")

with TemporaryDirectory(dir=target_dir) as staging:
    staged_link = Path(staging) / "executable"
    staged_link.symlink_to(destination)
    os.replace(staged_link, link)
PYTHON
}
