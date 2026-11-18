#!/usr/bin/env bats
load ../test_helper

setup() {
  load_forge_libs
  WORK="${BATS_TMPDIR}/forge-offer-$$-${RANDOM}"
  mkdir -p "$WORK"
}

teardown() {
  rm -rf "$WORK"
}

@test "offer_fix runs the suggested command with --yes" {
  export FORGE_YES=1
  run offer_fix "Repair?" printf 'repair ran\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"repair ran"* ]]
}

@test "offer_fix declines without forcing and without a terminal" {
  export FORGE_YES=0
  run offer_fix "Repair?" printf 'should not run\n'
  [ "$status" -eq 1 ]
  [[ "$output" != *"should not run"* ]]
}
