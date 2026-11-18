#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  WORK="${BATS_TMPDIR}/forge-upcheck-$$-${RANDOM}"
  mkdir -p "${WORK}/home/.git" "${WORK}/bin" "${WORK}/cache"
  printf 'https://example.invalid/forge.git\n' > "${WORK}/home/.git/forge-source"
  printf '0.1.0\n' > "${WORK}/home/.git/forge-version"
  cat > "${WORK}/bin/git" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FORGE_TEST_GIT_LOG"
if [ "$1" = ls-remote ]; then
  printf '%s\t%s\n' deadbeef refs/tags/v9.9.9
  printf '%s\t%s\n' beefdead refs/tags/v0.1.0
fi
SH
  chmod +x "${WORK}/bin/git"
  export FORGE_TEST_GIT_LOG="${WORK}/git.log"
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "periodic update check notices a newer release once per interval" {
  # Invoke the launcher indirectly via BATS_RUN_COMMAND so FORGE_HOME points
  # at the fake installation; use the library function directly for isolation.
  load_forge_libs
  export FORGE_HOME="${WORK}/home"
  export XDG_CACHE_HOME="${WORK}/cache"
  export FORCE_UPDATE_CHECK=1
  export FORGE_QUIET=0 FORGE_OFFLINE=0 FORGE_DRY_RUN=0
  export PATH="${WORK}/bin:${PATH}"

  run update_check_periodic
  [ "$status" -eq 0 ]
  [[ "$output" == *"forge 9.9.9 is available"* ]]
  [ -f "${WORK}/cache/forge/last-update-check" ]
  local calls
  calls=$(wc -l < "${FORGE_TEST_GIT_LOG}" | tr -d ' ')
  [ "$calls" -eq 1 ]

  # A second call within the interval does not hit the network again.
  run update_check_periodic
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  calls=$(wc -l < "${FORGE_TEST_GIT_LOG}" | tr -d ' ')
  [ "$calls" -eq 1 ]
}

@test "periodic update check is skipped offline, quiet, and without a source" {
  load_forge_libs
  export FORGE_HOME="${WORK}/home"
  export XDG_CACHE_HOME="${WORK}/cache"
  export FORCE_UPDATE_CHECK=1
  export PATH="${WORK}/bin:${PATH}"

  FORGE_OFFLINE=1 FORGE_QUIET=0 run update_check_periodic
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  FORGE_OFFLINE=0 FORGE_QUIET=1 run update_check_periodic
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  rm -f "${WORK}/home/.git/forge-source"
  FORGE_OFFLINE=0 FORGE_QUIET=0 run update_check_periodic
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
