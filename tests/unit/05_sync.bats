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
  printf '\n# LOCAL OPTIONS\n' >> cmake/ProjectOptions.cmake
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  grep -q 'MY LOCAL EDIT' CMakeLists.txt
  grep -q 'LOCAL OPTIONS' cmake/ProjectOptions.cmake
  grep -q 'CMAKE_CXX_STANDARD 17' cmake/ProjectOptions.cmake
  run_forge --no-color sync --check
  [ "$status" -eq 0 ]
}

@test "sync writes a proposal and leaves the file untouched on conflict" {
  sed -i '' 's/cppstd = "20"/cppstd = "17"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "20"/cppstd = "17"/' Forge.toml
  run_forge --no-color sync --apply --yes >/dev/null
  # Now make a divergent local edit, then drift the template to a different value.
  sed -i '' 's/CMAKE_CXX_STANDARD 17/CMAKE_CXX_STANDARD 14/' cmake/ProjectOptions.cmake 2>/dev/null \
    || sed -i 's/CMAKE_CXX_STANDARD 17/CMAKE_CXX_STANDARD 14/' cmake/ProjectOptions.cmake
  sed -i '' 's/cppstd = "17"/cppstd = "20"/' Forge.toml 2>/dev/null \
    || sed -i 's/cppstd = "17"/cppstd = "20"/' Forge.toml
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 6 ]
  [ -f .forge/proposals/cmake_ProjectOptions.cmake.patch ]
  grep -q 'CMAKE_CXX_STANDARD 14' cmake/ProjectOptions.cmake
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

@test "missing or invalid member state fails every sync status consumer" {
  bats_require_minimum_version 1.5.0
  run_forge generate bin worker
  [ "$status" -eq 0 ]
  rm bins/worker/.forge/state.json
  local issue command
  for issue in 'missing Forge state' 'invalid Forge state'; do
    for command in 'sync --check' 'sync --diff' 'metadata --format json' 'deps status --format json'; do
      local -a args
      read -r -a args <<< "$command"
      run --separate-stderr "$FORGE_BASH" "$FORGE_BIN" --no-color "${args[@]}"
      [ "$status" -eq 6 ]
      [[ "$stderr" == *"$issue"*'bins/worker/.forge/state.json'* ]]
      [ -z "$output" ]
    done
    printf '[]\n' > bins/worker/.forge/state.json
  done
}

@test "conflicting sync modes fail before writing generated files" {
  cp cmake/ProjectOptions.cmake options.before
  cp .forge/state.json state.before
  sed 's/cppstd = "20"/cppstd = "17"/' Forge.toml > manifest.next
  mv manifest.next Forge.toml

  run_forge sync --check --apply --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"choose one sync mode"* ]]
  run_forge sync --apply --diff --yes
  [ "$status" -eq 2 ]
  cmp options.before cmake/ProjectOptions.cmake
  cmp state.before .forge/state.json
}

@test "sync retires removed dependency files and preserves local edits" {
  run_forge add alpha --source path --path vendor/alpha --cmake-target alpha
  [ "$status" -eq 0 ]
  run_forge add beta --source path --path vendor/beta --cmake-target beta
  [ "$status" -eq 0 ]

  printf '# local dependency edit\n' >> cmake/deps/beta/CMakeLists.txt
  cp cmake/deps/beta/CMakeLists.txt beta.before
  run_forge remove alpha
  [ "$status" -eq 0 ]
  [ ! -e cmake/deps/alpha/CMakeLists.txt ]
  [ ! -e .forge/base/cmake/deps/alpha/CMakeLists.txt ]
  [ -n "$(find .forge/backups -name 'cmake_deps_alpha_CMakeLists.txt.*' -print -quit)" ]
  grep -Fq 'add_subdirectory(cmake/deps/beta)' cmake/Dependencies.cmake
  cmp beta.before cmake/deps/beta/CMakeLists.txt

  run_forge remove beta
  [ "$status" -eq 0 ]
  cmp beta.before cmake/deps/beta/CMakeLists.txt
  ! grep -Fq 'add_subdirectory(cmake/deps/' cmake/Dependencies.cmake
  jq -e '.files | keys | all(startswith("cmake/deps/") | not)' .forge/state.json
  run_forge sync --check
  [ "$status" -eq 0 ]

  run_forge add beta --source path --path vendor/beta --cmake-target beta
  [ "$status" -eq 6 ]
  cmp beta.before cmake/deps/beta/CMakeLists.txt
  [ -f .forge/proposals/cmake_deps_beta_CMakeLists.txt.patch ]
}

@test "sync refuses a symlinked dependency directory before writing files" {
  mkdir -p outside cmake/deps
  ln -s "$PWD/outside" cmake/deps/logger
  cp cmake/Dependencies.cmake deps.before

  run_forge add logger --source path --path vendor/logger --cmake-target logger
  [ "$status" -eq 6 ]
  [[ "$output" == *'refusing to sync a symlinked path:'*'cmake/deps/logger'* ]]
  [ ! -e outside/CMakeLists.txt ]
  cmp deps.before cmake/Dependencies.cmake
}

@test "per-dependency directories distinguish aliases that differ only by case" {
  run_forge add helper --source path --path vendor/lower --cmake-target lower_helper
  [ "$status" -eq 0 ]
  run_forge add Helper --source path --path vendor/upper --cmake-target upper_helper
  [ "$status" -eq 0 ]
  grep -Fq 'vendor/lower' cmake/deps/helper/CMakeLists.txt
  grep -Fq 'vendor/upper' cmake/deps/-helper/CMakeLists.txt
  grep -Fq 'add_subdirectory(cmake/deps/helper)' cmake/Dependencies.cmake
  grep -Fq 'add_subdirectory(cmake/deps/-helper)' cmake/Dependencies.cmake

  run_forge remove Helper
  [ "$status" -eq 0 ]
  [ ! -e cmake/deps/-helper/CMakeLists.txt ]
  grep -Fq 'vendor/lower' cmake/deps/helper/CMakeLists.txt
  run_forge sync --check
  [ "$status" -eq 0 ]
}
