#!/usr/bin/env bats
# Verify the documentation command with the real Doxygen executable.
load ../test_helper

@test "docs builds API pages from a legacy manifest without a description" {
  command -v doxygen >/dev/null || skip "doxygen not installed"
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color new --lib legacy
  [ "$status" -eq 0 ]
  cd legacy/src
  run_forge --no-color docs
  [ "$status" -eq 0 ]
  [[ "$output" == *target/docs/html/index.html* ]]
  [ -f ../target/docs/html/index.html ]
  [ -n "$(find ../target/docs/html -name '*legacy*' -print -quit)" ]
}

@test "docs uses the project description and version without expanding environment variables" {
  command -v doxygen >/dev/null || skip "doxygen not installed"
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color init --lib <<< $'sample\n2.4.1\nLibrary with $(HOME) in the description\n\n'
  [ "$status" -eq 0 ]
  run_forge --no-color docs --dry-run
  [ "$status" -eq 0 ]
  [ ! -e target/docs ]

  run_forge --no-color docs
  [ "$status" -eq 0 ]
  grep -Fq '2.4.1' target/docs/html/index.html
  grep -Fq 'Library with &#36;(HOME) in the description' target/docs/html/index.html
}

@test "docs reports a failed generator without a success message" {
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color new sample
  [ "$status" -eq 0 ]
  mkdir fakebin
  printf '#!/bin/sh\nexit 1\n' > fakebin/doxygen
  chmod +x fakebin/doxygen
  export PATH="$PWD/fakebin:$PATH"
  cd sample

  run_forge --no-color docs
  [ "$status" -eq 5 ]
  [[ "$output" == *"Doxygen generation failed"* ]]
  [[ "$output" != *"docs ok"* ]]
}
