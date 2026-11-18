#!/usr/bin/env bats
load ../test_helper

@test "version prints forge version" {
  run_forge --no-color version
  [ "$status" -eq 0 ]
  [[ "$output" == forge\ * ]]
}

@test "help lists every implemented command" {
  run_forge --no-color help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Quick start:"*"Commands:"* ]]
  local command
  for command in help version doctor new init build run watch test clean add remove \
    'deps lock' 'deps pin' 'deps status' sync docs fmt metadata generate update uninstall 'workflow init'; do
    grep -Eq "^  ${command}( |$)" <<< "$output"
  done
  [[ "$output" == *"Generate HTML documentation with Doxygen"* ]]
}

@test "unknown command exits 2" {
  run_forge --no-color frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *unknown\ command* ]]
}

@test "unknown global flag exits 2" {
  run_forge --no-color --bogus version
  [ "$status" -eq 2 ]
  [[ "$output" == *unknown\ global\ flag* ]]
}

@test "Bash 3.2 is rejected with guidance" {
  # /bin/bash on macOS is 3.2. On Linux this test is skipped.
  [[ -x /bin/bash ]] || skip
  local ver
  ver=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')
  [[ "$ver" -lt 4 ]] || skip "system bash is 4+"
  run /bin/bash "${FORGE_BIN}" version
  [ "$status" -eq 3 ]
  [[ "$output" == *"Bash 4+ is required"* ]]
}

@test "doctor reports all required tools present" {
  run_forge --no-color doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"All required tools are present"* ]]
}

@test "help uses aligned two columns without dot leaders" {
  run_forge --no-color help
  [ "$status" -eq 0 ]
  [[ "$output" != *"...."* ]]
  local d cols=""
  for d in "Show this help" "Print the Forge version" "Prompt for details and scaffold a directory" "Disable ANSI color"; do
    cols+="$(printf '%s\n' "$output" | grep -F "$d" | awk -v needle="${d}" '{print index($0, needle)}') "
  done
  [ "$(printf '%s' "${cols}" | tr ' ' '\n' | grep -c . | tr -d ' ')" -eq 4 ]
  [ "$(printf '%s' "${cols}" | tr ' ' '\n' | grep . | sort -u | wc -l | tr -d ' ')" -eq 1 ]
}

@test "help is ANSI-free with --no-color and colored with FORCE_COLOR" {
  run_forge --no-color help
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]

  run env -u NO_COLOR FORCE_COLOR=1 "${FORGE_BASH}" "${FORGE_BIN}" --no-color help
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]

  run env -u NO_COLOR FORCE_COLOR=1 "${FORGE_BASH}" "${FORGE_BIN}" help
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]

  run env NO_COLOR=1 FORCE_COLOR=1 "${FORGE_BASH}" "${FORGE_BIN}" help
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "data goes to stdout, diagnostics to stderr" {
  bats_require_minimum_version 1.5.0
  run --separate-stderr "${FORGE_BASH}" "${FORGE_BIN}" --no-color version
  [ "$status" -eq 0 ]
  [ "$output" = "forge 0.1.0" ]
  [ -z "$stderr" ]

  run --separate-stderr "${FORGE_BASH}" "${FORGE_BIN}" --no-color frobnicate
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"unknown command"* ]]
}

@test "command help includes only the selected subcommand options and examples" {
  run_forge deps pin --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"forge deps pin NAME"* && "$output" == *"--sha SHA"* ]]
  [[ "$output" != *"--format FORMAT"* ]]
  run_forge help test
  [ "$status" -eq 0 ]
  [[ "$output" == *"--allow-no-tests"* && "$output" == *"forge test --sanitize address"* ]]
  run_forge help unknown
  [ "$status" -eq 2 ]
}

@test "completion scopes verbs and options and handles values and forwarded arguments" {
  run_forge __complete ''
  [ "$status" -eq 0 ]
  [[ "$output" == *$'deps\n'* && "$output" != *'--tag'* && "$output" != *$'lock\n'* ]]
  run_forge __complete '' --manifest-path 'some dir/Forge.toml' deps
  [ "$status" -eq 0 ]
  [ "$output" = $'lock\npin\nstatus' ]
  run_forge __complete -- deps pin upstream
  [ "$status" -eq 0 ]
  [[ "$output" == *'--tag'* && "$output" == *'--branch'* && "$output" != *'--format'* ]]
  run_forge __complete -- generate bin worker
  [ "$status" -eq 0 ]
  [[ "$output" == *'--cpp'* && "$output" != *'--namespace'* ]]
  run_forge __complete --name generate lib math
  [ "$status" -eq 0 ]
  [ "$output" = '--namespace' ]
  run_forge __complete --format=j deps status
  [ "$output" = '--format=json' ]
  run_forge __complete a test --sanitize
  [ "$output" = $'address\nasan' ]
  run_forge __complete -- run -- --release
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing flag operands return usage without entering an argument loop" {
  run_forge deps pin upstream --tag
  [ "$status" -eq 2 ]
  [[ "$output" == *'--tag requires a value'* ]]
  run_forge deps status --format
  [ "$status" -eq 2 ]
  run_forge metadata --format
  [ "$status" -eq 2 ]
  run_forge test --sanitize
  [ "$status" -eq 2 ]
}

@test "Git dependency completion guides the URL, revision, and CMake target" {
  run_forge __complete '' add fmt_git
  [ "$status" -eq 0 ]
  [[ "$output" == *'--source'* ]]

  run_forge __complete g add fmt_git --source
  [ "$status" -eq 0 ]
  [ "$output" = git ]
  run_forge __complete --source=g add fmt_git
  [ "$status" -eq 0 ]
  [ "$output" = --source=git ]

  run_forge __complete '' add fmt_git --source git
  [ "$status" -eq 0 ]
  [ "$output" = --url ]
  run_forge __complete '' add fmt_git --source = git --url file:///tmp/sample
  [ "$status" -eq 0 ]
  [ "$output" = $'--tag\n--branch\n--sha' ]
  run_forge __complete '' add fmt_git --source=git --url file:///tmp/sample --tag v1
  [ "$status" -eq 0 ]
  [ "$output" = --cmake-target ]
  run_forge __complete -- add fmt_git --source=git --url file:///tmp/sample --branch main
  [ "$status" -eq 0 ]
  [[ "$output" == *'--cmake-target'* && "$output" != *'--tag'* && "$output" != *'--conan'* ]]
  run_forge __complete '' add fmt_git --source=git --url file:///tmp/sample --sha deadbeef --cmake-target fmt::fmt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
