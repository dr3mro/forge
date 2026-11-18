# shellcheck shell=bash
# shellcheck disable=SC2034  # global flags consumed by cmake.sh
# Forge command: test (including isolated sanitizer profiles).

# Build and run the selected CTest tests.
cmd_test() {
  local filter="" repeat=1 allow_no_tests=0 release=0 sanitize="" list=0 positional=0
  while (( $# > 0 )); do
    case "$1" in
      --repeat) repeat="${2:-}"; [[ "${repeat}" =~ ^[0-9]+$ ]] || die "${EXIT_USAGE}" "--repeat requires a positive integer"; shift 2 ;;
      --repeat=*) repeat="${1#*=}"; [[ "${repeat}" =~ ^[0-9]+$ ]] || die "${EXIT_USAGE}" "--repeat requires a positive integer"; shift ;;
      --allow-no-tests) allow_no_tests=1; shift ;;
      --list) list=1; shift ;;
      --release) release=1; shift ;;
      --sanitize) [[ -n "${2:-}" && "$2" != -* ]] || die "${EXIT_USAGE}" "$1 requires a value"; sanitize="$2"; shift 2 ;;
      --sanitize=*) sanitize="${1#*=}"; shift ;;
      --help | -h) cmd_help; return "${EXIT_OK}" ;;
      -*) die "${EXIT_USAGE}" "unknown flag for 'test': $1" ;;
      *)
        (( positional == 0 )) || die "${EXIT_USAGE}" "test accepts one optional FILTER"
        filter="$1"; positional=1; shift
        ;;
    esac
  done
  (( repeat >= 1 )) || die "${EXIT_USAGE}" "--repeat must be at least 1"

  manifest_load
  local profile gen build_dir toolchain=""
  if (( release )); then profile="release"; else profile=$(mq '.build.default_profile // "debug"'); fi

  if [[ -n "${sanitize}" ]]; then
    forge_enable_sanitizer "${sanitize}"
    sanitize="${FORGE_SANITIZER}"
    gen=$(normalize_generator "$(mq '.build.generator // "Ninja"')")
    build_dir=$(resolve_build_dir "${profile}") || die "${EXIT_USAGE}" "invalid build profile: ${profile}"
    cmake_check_build_path "${build_dir}"
    build_lock_acquire "${build_dir}"
    if conan_graph_has_deps; then
      conan_prepare_requirements "${FORGE_ROOT}"
      FORGE_CONAN_REQUIREMENTS_MODE="graph"
      cmake_check_build_path "${build_dir}/.forge-conan"
      conan_install "${build_dir}/.forge-conan" "${profile}"
      FORGE_CONAN_REQUIREMENTS_MODE="local"
      toolchain=$(conan_toolchain_path "${build_dir}/.forge-conan")
    fi
    if (( FORGE_DRY_RUN )); then
      status "dry-run: would build and test ${build_dir#"${FORGE_ROOT}"/} with ${sanitize}"
      return "${EXIT_OK}"
    fi
    forge_perform_build "${build_dir}" "${profile}" "${gen}" "${toolchain}"
    status "sanitizer build: ${build_dir#"${FORGE_ROOT}"/}"
  else
    build_dir=$(resolve_build_dir "${profile}") || die "${EXIT_USAGE}" "invalid build profile: ${profile}"
  fi

  if [[ ! -d "${build_dir}" ]]; then
    local build_hint="forge build"
    [[ "${profile}" == release ]] && build_hint="forge build --release"
    die "${EXIT_BUILD}" "project is not built for '${profile}' (run '${build_hint}')"
  fi

  if (( FORGE_DRY_RUN )); then
    if (( list )); then
      status "dry-run: would list ctest tests in ${build_dir} (filter: ${filter:-all})"
    else
      status "dry-run: would run ctest in ${build_dir} (filter: ${filter:-all})"
    fi
    return "${EXIT_OK}"
  fi

  local -a cargs=(--test-dir "${build_dir}")
  if (( list )); then
    cargs+=(-N)
  else
    cargs+=(--output-on-failure)
    (( repeat > 1 )) && cargs+=(--repeat "until-fail:${repeat}")
  fi
  [[ -n "${filter}" ]] && cargs+=(-R "${filter}")

  local output rc=0
  if (( list )); then progress "Listing CTest tests"; else progress "Running CTest"; fi
  output=$(ctest "${cargs[@]}" 2>&1) || rc=$?
  printf '%s\n' "${output}"

  if [[ "${output}" == *"No tests were found"* ]]; then
    if (( allow_no_tests )); then
      progress_finish
      status "no tests found (allowed by --allow-no-tests)"
      return "${EXIT_OK}"
    fi
    die "${EXIT_BUILD}" "no tests found (use '[[test]]' targets or --allow-no-tests)"
  fi
  (( rc == 0 )) || die "${EXIT_BUILD}" "tests failed"
  progress_finish
  if (( list )); then return "${EXIT_OK}"; fi
  out "tests ok"
}
