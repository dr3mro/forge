# shellcheck shell=bash
# shellcheck disable=SC2034  # global flags consumed by cmake.sh
# Forge command: test (including isolated sanitizer profiles).

# Translate a sanitizer name into compiler flags.
_sanitizer_flags() {
  case "$1" in
    address | asan)   printf '%s' "-fsanitize=address -fno-omit-frame-pointer" ;;
    undefined | ubsan) printf '%s' "-fsanitize=undefined -fno-omit-frame-pointer" ;;
    leak | lsan)      printf '%s' "-fsanitize=leak -fno-omit-frame-pointer" ;;
    thread | tsan)    printf '%s' "-fsanitize=thread -fno-omit-frame-pointer" ;;
    *) return 1 ;;
  esac
}

# Build and run the selected CTest tests.
cmd_test() {
  local filter="" repeat=1 allow_no_tests=0 release=0 sanitize="" positional=0
  while (( $# > 0 )); do
    case "$1" in
      --repeat) repeat="${2:-}"; [[ "${repeat}" =~ ^[0-9]+$ ]] || die "${EXIT_USAGE}" "--repeat requires a positive integer"; shift 2 ;;
      --repeat=*) repeat="${1#*=}"; [[ "${repeat}" =~ ^[0-9]+$ ]] || die "${EXIT_USAGE}" "--repeat requires a positive integer"; shift ;;
      --allow-no-tests) allow_no_tests=1; shift ;;
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
  local profile gen build_dir flags toolchain=""
  if (( release )); then profile="release"; else profile=$(mq '.build.default_profile // "debug"'); fi

  if [[ -n "${sanitize}" ]]; then
    flags=$(_sanitizer_flags "${sanitize}") \
      || die "${EXIT_USAGE}" "unknown sanitizer '${sanitize}' (address, undefined, leak, thread)"
    case "${sanitize}" in
      asan) sanitize="address" ;;
      ubsan) sanitize="undefined" ;;
      lsan) sanitize="leak" ;;
      tsan) sanitize="thread" ;;
    esac
    FORGE_SANITIZER="${sanitize}"
    gen=$(normalize_generator "$(mq '.build.generator // "Ninja"')")
    build_dir=$(resolve_build_dir "${profile}")
    FORGE_EXTRA_CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=${flags}" "-DCMAKE_EXE_LINKER_FLAGS=${flags}")
    if conan_graph_has_deps; then
      conan_prepare_requirements "${FORGE_ROOT}"
      FORGE_CONAN_REQUIREMENTS_MODE="graph"
      conan_install "${build_dir}" "${profile}"
      FORGE_CONAN_REQUIREMENTS_MODE="local"
      toolchain=$(conan_toolchain_path "${build_dir}")
    fi
    if (( FORGE_DRY_RUN )); then
      status "dry-run: would build and test ${build_dir#"${FORGE_ROOT}"/} with ${sanitize}"
      return "${EXIT_OK}"
    fi
    forge_perform_build "${build_dir}" "${profile}" "${gen}" "${toolchain}"
    status "sanitizer build: ${build_dir#"${FORGE_ROOT}"/}"
  else
    build_dir=$(resolve_build_dir "${profile}")
  fi

  [[ -d "${build_dir}" ]] \
    || die "${EXIT_BUILD}" "project is not built for '${profile}' (run 'forge build')"

  if (( FORGE_DRY_RUN )); then
    status "dry-run: would run ctest in ${build_dir} (filter: ${filter:-all})"
    return "${EXIT_OK}"
  fi

  local -a cargs=(--test-dir "${build_dir}" --output-on-failure)
  [[ -n "${filter}" ]] && cargs+=(-R "${filter}")
  (( repeat > 1 )) && cargs+=(--repeat "until-fail:${repeat}")

  local output rc=0
  progress "Running CTest"
  output=$(ctest "${cargs[@]}" 2>&1) || rc=$?
  printf '%s\n' "${output}"

  if [[ "${output}" == *"No tests were found"* ]]; then
    if (( allow_no_tests )); then
      status "no tests found (allowed by --allow-no-tests)"
      return "${EXIT_OK}"
    fi
    die "${EXIT_BUILD}" "no tests found (use '[[test]]' targets or --allow-no-tests)"
  fi
  (( rc == 0 )) || die "${EXIT_BUILD}" "tests failed"
  out "tests ok"
}
