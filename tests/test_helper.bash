# Bats shared setup for Forge tests.
# Ensures a Bash 4+ interpreter is used to launch Forge on macOS.

FORGE_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_PROJECT_DIR="$(cd "${FORGE_TEST_DIR}/.." && pwd)"
FORGE_BIN="${FORGE_PROJECT_DIR}/bin/forge"

# Pick a Bash 4+ interpreter explicitly (macOS default is 3.2).
if (( BASH_VERSINFO[0] >= 4 )); then
  FORGE_BASH="bash"
elif [[ -x /opt/homebrew/bin/bash ]]; then
  FORGE_BASH="/opt/homebrew/bin/bash"
elif [[ -x /usr/local/bin/bash ]]; then
  FORGE_BASH="/usr/local/bin/bash"
else
  FORGE_BASH="bash"
fi

# Capture a Forge invocation with Bats using the selected Bash interpreter.
run_forge() {
  run "${FORGE_BASH}" "${FORGE_BIN}" "$@"
}

# Print the path to a test fixture.
fixture() {
  printf '%s\n' "${FORGE_TEST_DIR}/fixtures/$1"
}

# Source Forge libraries directly into the test shell (no side effects).
load_forge_libs() {
  export FORGE_HOME="${FORGE_PROJECT_DIR}"
  export FORGE_VERSION="0.1.0-test"
  # shellcheck disable=SC1091
  source "${FORGE_PROJECT_DIR}/lib/_load.sh"
}

# Mock lock resolution without network or a populated Conan cache.
mock_conan_lock() {
  local dir="${BATS_TEST_TMPDIR}/lock-bin"
  export FORGE_TEST_CONAN_DELEGATE
  FORGE_TEST_CONAN_DELEGATE=$(command -v conan || true)
  export FORGE_TEST_CONAN_LOCK_LOG="${BATS_TEST_TMPDIR}/lock-invocations"
  mkdir -p "$dir"
  cat > "$dir/conan" <<'SH'
#!/bin/sh
case $1 in
  --version) printf 'Conan version 2.33.0\n' ;;
  lock)
    shift
    [ "$1" = create ] || exit 98
    printf '%s\n' "$*" >> "$FORGE_TEST_CONAN_LOCK_LOG"
    for arg do
      case $arg in
        --lockfile-out=*) printf '{"requires":[]}\n' > "${arg#*=}" ;;
      esac
    done
    [ "${FORGE_TEST_FAIL_LOCK:-0}" = 0 ] ;;
  *) [ -n "$FORGE_TEST_CONAN_DELEGATE" ] && exec "$FORGE_TEST_CONAN_DELEGATE" "$@" ;;
esac
SH
  chmod +x "$dir/conan"
  export PATH="$dir:$PATH"
}
