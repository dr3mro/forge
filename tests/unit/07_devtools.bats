#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  WORK="${BATS_TMPDIR}/forge-devtools-$$-${RANDOM}"
  mkdir -p "$WORK"; cd "$WORK"
  run_forge --no-color new app >/dev/null
  cd app
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "metadata --format json emits ANSI-free stable JSON" {
  run_forge --no-color metadata --format json
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
  run jq -e '.schema == 1 and .package.name == "app" and (.targets | length == 1)' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "metadata rejects non-json formats" {
  run_forge --no-color metadata --format yaml
  [ "$status" -eq 2 ]
}

@test "fmt --check never modifies files" {
  command -v clang-format >/dev/null || skip "clang-format not installed"
  load_forge_libs
  local before after
  printf 'int main( ){return 0;}\n' > src/main.cpp
  before=$(sha256_file src/main.cpp)
  run_forge --no-color fmt --check
  [ "$status" -eq 5 ]
  [[ "$output" == *"format check failed"* ]]
  after=$(sha256_file src/main.cpp)
  [ "$before" = "$after" ]
}

@test "fmt writes formatted source and check then passes" {
  command -v clang-format >/dev/null || skip "clang-format not installed"
  run_forge --no-color fmt
  [ "$status" -eq 0 ]
  run_forge --no-color fmt --check
  [ "$status" -eq 0 ]
}

@test "sanitizer build uses an isolated directory" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color test --sanitize address >/dev/null
  [ "$status" -eq 0 ]
  [ -f target/sanitizers/address/debug/CMakeCache.txt ]
  [ ! -e target/debug ]
  run_forge --no-color build >/dev/null
  [ "$status" -eq 0 ]
  [ -f target/debug/CMakeCache.txt ]
  [ -f target/sanitizers/address/debug/CMakeCache.txt ]
  [ "$(readlink target/compile_commands.json)" = debug/compile_commands.json ]
}

@test "build and run validate sanitizer names before doing work" {
  for command in build run watch; do
    run_forge --dry-run "$command" --sanitize=invalid
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown sanitizer 'invalid'"* ]]
  done
  run_forge --dry-run build --sanitize
  [ "$status" -eq 2 ]
  [[ "$output" == *"--sanitize requires a value"* ]]
}

@test "build --sanitize uses the isolated sanitizer tree and leaves normal build alone" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color build --sanitize address >/dev/null
  [ "$status" -eq 0 ]
  [ -f target/sanitizers/address/debug/CMakeCache.txt ]
  [ ! -e target/debug ]
  [ ! -e target/compile_commands.json ]
  run_forge --no-color build >/dev/null
  [ "$status" -eq 0 ]
  [ -f target/debug/CMakeCache.txt ]
  [ -f target/sanitizers/address/debug/CMakeCache.txt ]
  [ "$(readlink target/compile_commands.json)" = debug/compile_commands.json ]
}

@test "run --sanitize finds the instrumented executable and forwards arguments" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color build --sanitize address >/dev/null
  [ "$status" -eq 0 ]
  run_forge --no-color run --sanitize address --bin app -- --flag
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from app!"* ]]
  [ ! -e target/debug/app ]
}

@test "run --build --sanitize normalizes aliases and builds the instrumented target" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color run --build --sanitize asan --bin app
  [ "$status" -eq 0 ]
  [ -f target/sanitizers/address/debug/CMakeCache.txt ]
  [ ! -e target/debug ]
}

@test "a missing sanitized build reports a sanitizer-aware repair hint" {
  run_forge --no-color run --sanitize address --bin app
  [ "$status" -eq 5 ]
  [[ "$output" == *"forge build --sanitize address"* ]]
}

@test "watch --sanitize dry run names the sanitizer in its plan" {
  run_forge --no-color --dry-run watch --sanitize address --bin app
  [ "$status" -eq 0 ]
  [[ "$output" == *"sanitizer=address"* ]]
}

@test "development commands report help and reject malformed options" {
  local command
  for command in build run test fmt metadata update uninstall; do
    run_forge "$command" --help
    [ "$status" -eq 0 ]
    run_forge "$command" --invalid
    [ "$status" -eq 2 ]
  done
  run_forge update
  [ "$status" -eq 6 ]
  run_forge uninstall
  [ "$status" -eq 6 ]
}

@test "build dry run accepts both target and toolchain flag spellings" {
  printf '# sample toolchain\n' > toolchain.cmake
  run_forge --dry-run build --target "$(basename "$PWD")" --toolchain toolchain.cmake --link-compile-commands
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would run cmake"* ]]
  run_forge --dry-run build --target=sample --toolchain=toolchain.cmake
  [ "$status" -eq 0 ]
  run_forge build --debug-target sample --release
  [ "$status" -eq 2 ]
  run_forge build --toolchain=missing
  [ "$status" -eq 2 ]
  run_forge build --target=invalid-target
  [ "$status" -eq 2 ]
}

@test "test validates sanitizer and repeat settings before building" {
  local sanitizer
  for sanitizer in asan ubsan lsan tsan; do
    run_forge --dry-run test --sanitize="$sanitizer" --repeat=2
    [ "$status" -eq 0 ]
    [[ "$output" == *"would build and test"* ]]
  done
  run_forge test --sanitize=invalid
  [ "$status" -eq 2 ]
  run_forge test --repeat invalid
  [ "$status" -eq 2 ]
  run_forge test --repeat=invalid
  [ "$status" -eq 2 ]
}

@test "fmt dry runs describe their mode and preserve source files" {
  command -v clang-format >/dev/null || skip "clang-format not installed"
  printf 'int main( ){return 0;}\n' > src/main.cpp
  cp src/main.cpp source.before
  run_forge fmt --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would format "* ]]
  cmp source.before src/main.cpp
  run_forge fmt --check --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would check format for "* ]]
  cmp source.before src/main.cpp
}


@test "fresh scaffold and generated class pass fmt --check" {
  run_forge fmt --check
  [ "$status" -eq 0 ]
  run_forge generate class Point src/geo --namespace ns
  [ "$status" -eq 0 ]
  run_forge fmt --check
  [ "$status" -eq 0 ]
}
