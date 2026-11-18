#!/usr/bin/env bats
load ../test_helper

setup() {
  load_forge_libs
}

@test "version_ge compares dotted versions" {
  run version_ge 3.25.0 3.25
  [ "$status" -eq 0 ]
  run version_ge 3.24 3.25
  [ "$status" -eq 1 ]
  run version_ge 10.0 9.9
  [ "$status" -eq 0 ]
  run version_ge 2.33.0 2
  [ "$status" -eq 0 ]
}

@test "path_is_safe_relative accepts normal paths" {
  run path_is_safe_relative "src/main.cpp"
  [ "$status" -eq 0 ]
  run path_is_safe_relative "libs/logger"
  [ "$status" -eq 0 ]
}

@test "path_is_safe_relative rejects traversal and absolute paths" {
  run path_is_safe_relative "../etc/passwd"
  [ "$status" -eq 1 ]
  run path_is_safe_relative "/etc/passwd"
  [ "$status" -eq 1 ]
  run path_is_safe_relative "a/../b"
  [ "$status" -eq 1 ]
  run path_is_safe_relative 'C:\evil'
  [ "$status" -eq 1 ]
}

@test "atomic_write creates nested files with exact content" {
  local dir="${BATS_TMPDIR}/forge-atomic-$$"
  local target="${dir}/a/b/file.txt"
  printf 'hello\nworld\n' | atomic_write "$target"
  [ -f "$target" ]
  [ "$(cat "$target")" = "$(printf 'hello\nworld')" ]
  [ -z "$(find "$dir" -name '.forge-tmp.*' -print -quit)" ]
  rm -rf "$dir"
}

@test "atomic_write preserves existing mode" {
  local dir="${BATS_TMPDIR}/forge-atomic-mode-$$"
  mkdir -p "$dir"
  local target="${dir}/script.sh"
  printf '#!/bin/sh\n' > "$target"
  chmod 0755 "$target"
  printf '#!/bin/sh\necho hi\n' | atomic_write "$target"
  [ "$(stat_mode "$target")" = "755" ]
  rm -rf "$dir"
}

@test "sha256 helpers agree" {
  local f="${BATS_TMPDIR}/forge-sha-$$"
  printf 'abc' > "$f"
  [ "$(sha256_file "$f")" = "$(sha256_str 'abc')" ]
  rm -f "$f"
}

@test "discover_project walks up to Forge.toml" {
  local dir="${BATS_TMPDIR}/forge-discover-$$"
  mkdir -p "$dir/a/b"
  printf 'schema = 1\n' > "$dir/Forge.toml"
  local oldpwd="$PWD" rc
  cd "$dir/a/b"
  FORGE_MANIFEST_PATH=""
  discover_project
  rc=$?
  cd "$oldpwd"
  [ "$rc" -eq 0 ]
  [ "$FORGE_ROOT" = "$dir" ]
  rm -rf "$dir"
}

@test "verbose command logging redacts secret-looking arguments" {
  load_forge_libs
  local FORGE_DRY_RUN=1 FORGE_VERBOSE=1
  run run_cmd printf 'API_TOKEN=example' plain
  [ "$status" -eq 0 ]
  [[ "$output" == *"<redacted>"*plain* ]]
  [[ "$output" != *example* ]]
}
