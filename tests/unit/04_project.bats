#!/usr/bin/env bats
load ../test_helper

@test "new scaffolds a complete bin project" {
  local dir="${BATS_TMPDIR}/forge-new-bin-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new hello
  [ "$status" -eq 0 ]
  [ -f hello/Forge.toml ]
  [ -f hello/CMakeLists.txt ]
  [ -f hello/CMakePresets.json ]
  [ -f hello/conanfile.txt ]
  [ -f hello/cmake/Targets.cmake ]
  [ -f hello/.forge/state.json ]
  [ -f hello/.forge/base/CMakeLists.txt ]
  [ -f hello/src/main.cpp ]
  run jq -e '
    .version == 1 and (.manifest | test("^[0-9a-f]{64}$"))
    and (.files["CMakeLists.txt"] | test("^[0-9a-f]{64}$"))
  ' hello/.forge/state.json
  [ "$status" -eq 0 ]
  cd "$old"; rm -rf "$dir"
}

@test "new --lib scaffolds a library with header and linked test" {
  local dir="${BATS_TMPDIR}/forge-new-lib-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new --lib mylib
  [ "$status" -eq 0 ]
  [ -f mylib/include/mylib.hpp ]
  [ -f mylib/src/mylib.cpp ]
  run grep -q 'target_link_libraries(mylib_tests PRIVATE mylib)' mylib/cmake/Targets.cmake
  [ "$status" -eq 0 ]
  cd "$old"; rm -rf "$dir"
}

@test "new refuses to overwrite an existing directory" {
  local dir="${BATS_TMPDIR}/forge-new-over-$$" old="$PWD"
  mkdir -p "$dir/hello"; cd "$dir"
  run_forge --no-color new hello
  [ "$status" -eq 6 ]
  [[ "$output" == *refusing\ to\ overwrite* ]]
  cd "$old"; rm -rf "$dir"
}

@test "new --dry-run creates nothing" {
  local dir="${BATS_TMPDIR}/forge-new-dry-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new --dry-run hello
  [ "$status" -eq 0 ]
  [ ! -e hello ]
  cd "$old"; rm -rf "$dir"
}

@test "init scaffolds into the current directory and refuses a second run" {
  local dir="${BATS_TMPDIR}/forge-init-$$" old="$PWD"
  mkdir -p "$dir/proj"; cd "$dir/proj"
  run_forge --no-color init <<< $'\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q '^name = "proj"$' Forge.toml
  grep -q '^version = "0.1.0"$' Forge.toml
  [ -f Forge.toml ]
  run_forge --no-color init
  [ "$status" -eq 6 ]
  cd "$old"; rm -rf "$dir"
}

@test "init preserves an existing editor configuration and exits before scaffolding" {
  cd "$BATS_TEST_TMPDIR"
  mkdir .vscode
  printf '{"tasks":[]}\n' > .vscode/tasks.json

  run_forge --no-color init <<< $'\n\n\n\n'
  [ "$status" -eq 6 ]
  [ "$(cat .vscode/tasks.json)" = '{"tasks":[]}' ]
  [ ! -e Forge.toml ]
  [ ! -e .zed ]
}

@test "init prompts for metadata and puts the author on every generated C++ file" {
  local kind input description='API with "quotes", & and \paths'
  printf -v input '%s\n' sample 2.4.1 "$description" 'A. Developer' 'dev@example.test'
  for kind in bin lib; do
    mkdir "${BATS_TEST_TMPDIR}/$kind"
    cd "${BATS_TEST_TMPDIR}/$kind"
    run_forge --no-color init "--$kind" <<< "$input"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project name"*Version*Description*"Author name"*"Author email"* ]]
    grep -Fq 'project(sample VERSION 2.4.1 LANGUAGES CXX)' CMakeLists.txt
    grep -Fq -- "$description" README.md
    run python3 -c 'import sys, tomllib; p = tomllib.load(open("Forge.toml", "rb"))["package"]; assert p["description"] == sys.argv[1]' "$description"
    [ "$status" -eq 0 ]
    local -a cpp_files=(tests/main.cpp)
    if [[ "$kind" == lib ]]; then
      cpp_files+=(include/sample.hpp src/sample.cpp)
    else
      cpp_files+=(src/main.cpp)
    fi
    local file
    for file in "${cpp_files[@]}"; do
      [ "$(head -n 1 "$file")" = '// Author: A. Developer <dev@example.test>' ]
    done
  done
}

@test "init rejects a version CMake cannot use before writing any files" {
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color init <<< $'sample\n1.2.3-beta\nExample project'
  [ "$status" -eq 2 ]
  [[ "$output" == *"one to four dot-separated numbers"* ]]
  [ ! -e Forge.toml ]
  [ ! -e CMakeLists.txt ]
}

@test "init stops on incomplete input and rejects positional metadata" {
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color init <<< sample
  [ "$status" -eq 2 ]
  [[ "$output" == *"initialization cancelled"* ]]
  run_forge --no-color init sample 1.2.3
  [ "$status" -eq 2 ]
  [ ! -e Forge.toml ]
}

@test "new prompts for omitted fields and displays progress unless quiet" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new <<< $'prompted\n2.3.4\nDescription\nAuthor\nmail@example.test'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project name"*Version*Description*"Author name"*"Author email"* ]]
  [[ "$output" == *"[ ] Writing Forge.toml"* ]]
  grep -Fxq 'version = "2.3.4"' prompted/Forge.toml

  mkdir initialized
  cd initialized
  run_forge --quiet init --defaults --name scripted --version 3.2.1 --description 'Scripted setup' --author Dev
  [ "$status" -eq 0 ]
  [[ "$output" != *"[ ]"* ]]
  grep -Fxq 'name = "scripted"' Forge.toml
  grep -Fxq 'author = "Dev"' Forge.toml
}

@test "init keeps an existing Git hook and rejects an option without a value" {
  cd "$BATS_TEST_TMPDIR"
  run_forge init --version
  [ "$status" -eq 2 ]
  [ ! -e Forge.toml ]
  git init -q
  printf '# existing hook\n' > .git/hooks/reference-transaction
  run_forge init --defaults --name app
  [ "$status" -eq 0 ]
  [[ "$output" == *"existing reference-transaction hook"* ]]
  grep -Fxq '# existing hook' .git/hooks/reference-transaction
}

@test "new and init accept a library namespace and validate it before writing" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new --lib math --namespace acme::numeric --defaults
  [ "$status" -eq 0 ]
  grep -Fxq 'namespace acme::numeric {' math/include/math.hpp
  grep -Fxq 'class math_library {' math/include/math.hpp
  mkdir initialized
  cd initialized
  run_forge init --lib --name geometry --namespace acme::geometry --defaults
  [ "$status" -eq 0 ]
  grep -Fxq 'namespace acme::geometry {' include/geometry.hpp

  cd ..
  run_forge new --lib invalid --namespace 'acme::class' --defaults
  [ "$status" -eq 2 ]
  [[ "$output" == *'C++ keyword'* ]]
  [ ! -e invalid ]
  run_forge new invalid --namespace acme --defaults
  [ "$status" -eq 2 ]
  [ ! -e invalid ]
}

@test "new and init prompt only for metadata omitted after --name" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new --name helloworld --author Alice <<< $'1.2.3\nExample\nalice@example.test'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Version [0.1.0]'*'Description (optional)'*'Author email (optional)'* ]]
  [[ "$output" != *'Project name'* && "$output" != *'Author name (optional)'* ]]
  grep -Fxq 'author = "Alice <alice@example.test>"' helloworld/Forge.toml
  mkdir existing
  cd existing
  run_forge init --name helloworld --version 2.3.4 <<< $'Example\nAlice\nalice@example.test'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Description (optional)'*'Author name (optional)'*'Author email (optional)'* ]]
  [[ "$output" != *'Project name'* && "$output" != *'Version [0.1.0]'* ]]
  grep -Fxq 'name = "helloworld"' Forge.toml
}

@test "library linkage flags are validated before scaffolding" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new mixed --lib --static --shared --defaults
  [ "$status" -eq 2 ]
  [ ! -e mixed ]
  run_forge new app --shared --defaults
  [ "$status" -eq 2 ]
  [ ! -e app ]
  run_forge init --lib --name toolkit --shared --defaults
  [ "$status" -eq 0 ]
  grep -Fxq 'type = "shared"' Forge.toml
  grep -Fq 'add_library(toolkit SHARED src/toolkit.cpp)' cmake/Targets.cmake
  grep -Fq 'WINDOWS_EXPORT_ALL_SYMBOLS ON' cmake/Targets.cmake
}
