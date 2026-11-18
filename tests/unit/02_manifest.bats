#!/usr/bin/env bats
load ../test_helper

setup() {
  load_forge_libs
}

@test "valid full TOML parses and validates" {
  local json
  json=$(manifest_to_json "$(fixture valid_full.toml)")
  [ -n "$json" ]
  run manifest_validate_json "$json"
  [ "$status" -eq 0 ]
}

@test "unknown keys are rejected" {
  local json
  json=$(manifest_to_json "$(fixture invalid_unknown_key.toml)")
  run manifest_validate_json "$json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key 'bogus'"* ]]
}

@test "unsafe names and paths are rejected" {
  local json
  json=$(manifest_to_json "$(fixture invalid_unsafe.toml)")
  run manifest_validate_json "$json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid name"* ]]
  [[ "$output" == *"unsafe path"* ]]
}

@test "non-SHA git rev is rejected" {
  local json
  json=$(manifest_to_json "$(fixture invalid_git_rev.toml)")
  run manifest_validate_json "$json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"40-char SHA"* ]]
}

@test "shell metacharacters in paths are rejected and never executed" {
  local f="${BATS_TMPDIR}/forge-malicious-$$.toml"
  cat > "$f" <<'EOF'
schema = 1
[package]
name = "hello"
version = "0.1.0"
cppstd = "20"
[[bin]]
name = "hello"
path = "src/$(touch /tmp/forge-pwned-bats).cpp"
EOF
  local json
  json=$(manifest_to_json "$f")
  run manifest_validate_json "$json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe path"* ]]
  [ ! -e /tmp/forge-pwned-bats ]
  rm -f "$f"
}

@test "malformed TOML fails cleanly" {
  local f="${BATS_TMPDIR}/forge-malformed-$$.toml"
  printf 'schema = 1\n[package\nname = ' > "$f"
  run manifest_to_json "$f"
  [ "$status" -ne 0 ]
  rm -f "$f"
}

@test "unsupported schema is rejected" {
  local f="${BATS_TMPDIR}/forge-schema-$$.toml"
  printf 'schema = 3\n[package]\nname="x"\nversion="1"\ncppstd="20"\n' > "$f"
  local json
  json=$(manifest_to_json "$f")
  run manifest_validate_json "$json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema' must be 1 or 2"* ]]
  rm -f "$f"
}

@test "schema 2 is accepted without workspace" {
  local f="${BATS_TMPDIR}/forge-schema2-$$.toml"
  printf 'schema = 2\n[package]\nname="x"\nversion="1"\ncppstd="20"\n' > "$f"
  local json
  json=$(manifest_to_json "$f")
  run manifest_validate_json "$json"
  [ "$status" -eq 0 ]
  rm -f "$f"
}
