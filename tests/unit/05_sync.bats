#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  local dir="${BATS_TMPDIR}/forge-sync-$$-${RANDOM}"
  mkdir -p "$dir"
  cd "$dir"
  run_forge --no-color new hello >/dev/null
  cd hello
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${BATS_TMPDIR}"/forge-sync-$$-*
}

@test "sync --check is clean right after scaffolding" {
  run_forge --no-color sync --check
  [ "$status" -eq 0 ]
  [ "$output" = "in sync" ]
}

@test "sync detects manifest drift with exit 6" {
  sed -i '' 's/cppstd = "20"/cppstd = "17"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "20"/cppstd = "17"/' Forge.toml
  run_forge --no-color sync --check
  [ "$status" -eq 6 ]
  [[ "$output" == *"manifest changed"* ]]
}

@test "sync --apply merges template changes and preserves local edits" {
  sed -i '' 's/cppstd = "20"/cppstd = "17"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "20"/cppstd = "17"/' Forge.toml
  printf '\n# MY LOCAL EDIT\n' >> CMakeLists.txt
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  grep -q 'MY LOCAL EDIT' CMakeLists.txt
  grep -q 'CMAKE_CXX_STANDARD 17' CMakeLists.txt
  run_forge --no-color sync --check
  [ "$status" -eq 0 ]
}

@test "sync writes a proposal and leaves the file untouched on conflict" {
  sed -i '' 's/cppstd = "20"/cppstd = "17"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "20"/cppstd = "17"/' Forge.toml
  run_forge --no-color sync --apply --yes >/dev/null
  # Now make a divergent local edit, then drift the template to a different value.
  sed -i '' 's/CMAKE_CXX_STANDARD 17/CMAKE_CXX_STANDARD 14/' CMakeLists.txt 2>/dev/null \
    || sed -i 's/CMAKE_CXX_STANDARD 17/CMAKE_CXX_STANDARD 14/' CMakeLists.txt
  sed -i '' 's/cppstd = "17"/cppstd = "20"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "17"/cppstd = "20"/' Forge.toml
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 6 ]
  [ -f .forge/proposals/CMakeLists.txt.patch ]
  grep -q 'CMAKE_CXX_STANDARD 14' CMakeLists.txt
}

@test "build refuses to run when drift is present" {
  sed -i '' 's/cppstd = "20"/cppstd = "17"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "20"/cppstd = "17"/' Forge.toml
  run_forge --no-color build
  [ "$status" -eq 6 ]
  [[ "$output" == *"drift detected"* ]]
}

@test "sync apply is a no-op when clean and dry-run preserves pending state" {
  bats_require_minimum_version 1.5.0
  run --separate-stderr "${FORGE_BASH}" "${FORGE_BIN}" --no-color sync --apply
  [ "$status" -eq 0 ]
  [ "$output" = "nothing to sync" ]
  [[ "$stderr" == *"[✓] Checking workspace sync state"* ]]

  cp CMakeLists.txt cmake.before
  cp .forge/state.json state.before
  sed 's/cppstd = "20"/cppstd = "17"/' Forge.toml > manifest.next
  mv manifest.next Forge.toml
  run_forge --no-color sync --apply --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would apply the following changes"* ]]
  cmp cmake.before CMakeLists.txt
  cmp state.before .forge/state.json
}

@test "auto-sync preserves a conflicting local edit and reports the saved manifest" {
  printf '# local project dependencies\n' > cmake/Dependencies.cmake
  cp cmake/Dependencies.cmake local.before
  run_forge --no-color add logger --source path --path vendor/logger --cmake-target logger
  [ "$status" -eq 6 ]
  [[ "$output" == *"added dependency 'logger'"*conflict* ]]
  [[ "$output" == *"[✓] Checking workspace sync state"*"[✗] Applying workspace changes"* ]]
  [ -f .forge/proposals/cmake_Dependencies.cmake.patch ]
  grep -Fq '[dependencies.logger]' Forge.toml
  cmp local.before cmake/Dependencies.cmake
}

@test "sync reports a proposal when an unchanged managed file is missing" {
  rm cmake/Testing.cmake
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 6 ]
  [[ "$output" == *"missing current or base copy"* ]]
  [ -f .forge/proposals/cmake_Testing.cmake.patch ]
  [ ! -e cmake/Testing.cmake ]
}

@test "sync retires an unmodified empty legacy Conan recipe" {
  sed '/^{{.*}}$/d' "$FORGE_PROJECT_DIR/templates/base/conanfile.txt.tpl" > conanfile.txt
  cp conanfile.txt .forge/base/conanfile.txt
  local digest
  digest=$(python3 -c 'from hashlib import sha256; print(sha256(open("conanfile.txt", "rb").read()).hexdigest())')
  jq --arg digest "$digest" '.files["conanfile.txt"] = $digest' .forge/state.json > state.next
  mv state.next .forge/state.json

  run_forge sync --diff
  [ "$status" -eq 0 ]
  [[ "$output" == *'Conan recipe no longer required'* ]]
  [ -f conanfile.txt ]
  run_forge sync --apply --yes
  [ "$status" -eq 0 ]
  [ ! -e conanfile.txt ]
  [ ! -e .forge/base/conanfile.txt ]
  [ -f "$(find .forge/backups -name 'conanfile.txt.*' -print -quit)" ]
  run_forge sync --check
  [ "$status" -eq 0 ]
}

@test "an existing user Conan recipe survives init and conflicts with generated content" {
  mkdir "$BATS_TEST_TMPDIR/existing"
  cd "$BATS_TEST_TMPDIR/existing"
  printf '[requires]\nlocal-package/1.0\n' > conanfile.txt
  cp conanfile.txt original.txt
  run_forge init --defaults --name existing
  [ "$status" -eq 0 ]
  cmp original.txt conanfile.txt
  jq -e '.files | has("conanfile.txt") | not' .forge/state.json
  run_forge add fmt --conan --cmake-package fmt --cmake-target fmt::fmt-header-only
  [ "$status" -eq 6 ]
  [[ "$output" == *"user-owned recipe"* ]]
  cmp original.txt conanfile.txt
  grep -Fxq 'fmt/12.1.0' .forge/proposals/conanfile.txt.patch
  [ ! -e conan.lock ]
}
