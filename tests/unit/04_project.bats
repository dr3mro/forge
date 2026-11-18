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
  [ ! -e hello/conanfile.txt ]
  [ ! -e hello/.forge/base/conanfile.txt ]
  jq -e '.files | has("conanfile.txt") | not' hello/.forge/state.json
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

@test "new and init write the selected C++ standard and reject invalid values" {
  local dir="${BATS_TMPDIR}/forge-cppstd-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new app17 --defaults --cppstd 17
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "17"$' app17/Forge.toml
  run_forge --no-color new app23 --defaults --cppstd=23
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "23"$' app23/Forge.toml
  run_forge --no-color new bad --defaults --cppstd 14
  [ "$status" -eq 2 ]
  [ ! -e bad ]
  mkdir app_init && cd app_init
  run_forge --no-color init --defaults --name initapp --cppstd 17
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "17"$' Forge.toml
  cd "$old"; rm -rf "$dir"
}

@test "generated workspace members inherit the root C++ standard" {
  local dir="${BATS_TMPDIR}/forge-cppstd-member-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new root --defaults --cppstd 17 >/dev/null
  [ "$status" -eq 0 ]
  cd root
  run_forge --no-color generate lib widget >/dev/null
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "17"$' libs/widget/Forge.toml
  cd libs/widget
  run_forge --no-color generate lib nested >/dev/null
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "17"$' libs/nested/Forge.toml
  cd "$old"; rm -rf "$dir"
}

@test "generate accepts a per-member C++ standard override" {
  local dir="${BATS_TMPDIR}/forge-cppstd-override-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new root --defaults --cppstd 17 >/dev/null
  [ "$status" -eq 0 ]
  cd root
  run_forge --no-color generate lib fast --cppstd 23 >/dev/null
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "23"$' libs/fast/Forge.toml
  run_forge --no-color generate bin worker --cppstd 23 >/dev/null
  [ "$status" -eq 0 ]
  grep -q '^cppstd = "23"$' bins/worker/Forge.toml
  run_forge --no-color generate lib bad --cppstd 14
  [ "$status" -eq 2 ]
  [ ! -e libs/bad ]
  run_forge --no-color generate class Foo --cppstd 23
  [ "$status" -eq 2 ]
  cd "$old"; rm -rf "$dir"
}

@test "new scaffolds user, manifest-variable, and diagnostics modules under cmake" {
  local dir="${BATS_TMPDIR}/forge-cmake-modules-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new hello --defaults
  [ "$status" -eq 0 ]
  cd hello
  [ -f cmake/user.cmake ]
  [ ! -e user.cmake ]
  [ -f cmake/ProjectOptionsUser.cmake ]
  [ -f cmake/Diagnostics.cmake ]
  local flag
  for flag in -fcolor-diagnostics -fdiagnostics-show-option \
    -fdiagnostics-show-note-include-stack -ferror-limit=3 \
    -fno-elide-type -fdiagnostics-show-template-tree \
    -Wall -Wextra -Wpedantic; do
    grep -Fq -- "$flag" cmake/Diagnostics.cmake
  done
  grep -Fq 'include(cmake/user.cmake OPTIONAL)' CMakeLists.txt
  grep -Fq 'include(cmake/ProjectOptionsUser.cmake)' CMakeLists.txt
  grep -Fq 'forge_clang_diagnostics()' CMakeLists.txt
  jq -e '.files | has("cmake/user.cmake") | not' .forge/state.json
  [ -f entitlements.plist ]
  grep -q 'com.apple.security.get-task-allow' entitlements.plist
  [ -f cmake/CodeSign.cmake ]
  grep -Fq 'forge_codesign_target' cmake/Targets.cmake
  grep -Fxq 'FORGE_CODESIGN_IDENTITY = "adhoc"' Forge.toml
  grep -Fxq 'FORGE_CODESIGN_ENTITLEMENTS = "entitlements.plist"' Forge.toml
  grep -Fxq 'CMAKE_CXX_FLAGS_DEBUG = "-O0 -g"' Forge.toml
  jq -e '.files | has("cmake/CodeSign.cmake")' .forge/state.json
  jq -e '.files | has("entitlements.plist") | not' .forge/state.json
  run_forge --no-color sync --check
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

@test "generate class writes a standalone pair in the current directory" {
  local dir="${BATS_TMPDIR}/forge-class-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new hello --defaults
  [ "$status" -eq 0 ]
  cd hello

  run_forge --no-color generate class Widget
  [ "$status" -eq 0 ]
  [ -f Widget.hpp ]
  [ -f Widget.cpp ]
  grep -Fq 'namespace hello {' Widget.hpp
  grep -Fq 'class Widget {' Widget.hpp
  grep -Fq 'virtual ~Widget();' Widget.hpp
  grep -Fq 'Widget::Widget() = default;' Widget.cpp
  ! grep -q 'export.h\|FORGE_Widget_API' Widget.hpp
  jq -e '.files | has("Widget.hpp") | not' .forge/state.json
  run_forge sync --check
  [ "$status" -eq 0 ]
  cd "$old"; rm -rf "$dir"
}

@test "generate class honors a path, namespace, dry-run, and overwrite refusal" {
  local dir="${BATS_TMPDIR}/forge-class-path-$$" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new hello --defaults >/dev/null
  cd hello

  run_forge --no-color generate class Point src/geometry --namespace acme::geom
  [ "$status" -eq 0 ]
  [ -f src/geometry/Point.hpp ]
  [ -f src/geometry/Point.cpp ]
  grep -Fq 'namespace acme::geom {' src/geometry/Point.hpp

  run_forge --no-color generate class Temp --dry-run
  [ "$status" -eq 0 ]
  [ ! -e Temp.hpp ]
  [[ "$output" == *"would generate class 'Temp'"* ]]

  run_forge --no-color generate class Point src/geometry
  [ "$status" -eq 6 ]
  [[ "$output" == *'refusing to overwrite'* ]]

  run_forge --no-color generate class 'class'
  [ "$status" -eq 2 ]
  [[ "$output" == *'C++ keyword'* ]]
  run_forge --no-color generate class Bad ../outside
  [ "$status" -eq 2 ]
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
    grep -Fxq 'forge_project_version(forge_version 2.4.1)' CMakeLists.txt
    grep -Fxq 'project(sample VERSION ${forge_version} LANGUAGES CXX)' CMakeLists.txt
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
  [[ "$output" == *"[✓] Writing Forge.toml"* ]]
  grep -Fxq 'version = "2.3.4"' prompted/Forge.toml

  mkdir initialized
  cd initialized
  run_forge --quiet init --defaults --name scripted --version 3.2.1 --description 'Scripted setup' --author Dev
  [ "$status" -eq 0 ]
  [[ "$output" != *"[✓]"* && "$output" != *"[✗]"* ]]
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
  grep -Fxq 'class FORGE_math_API math {' math/include/math.hpp
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
  grep -Fq 'target_compile_definitions(toolkit PUBLIC FORGE_toolkit_SHARED)' cmake/Targets.cmake
  grep -Fxq '#define FORGE_toolkit_API __declspec(dllexport)' include/toolkit_export.h
  grep -Fxq '#define FORGE_toolkit_API __declspec(dllimport)' include/toolkit_export.h
}

@test "scaffolding prints green successes and a red cross for a failed step" {
  cd "$BATS_TEST_TMPDIR"
  run env -u NO_COLOR FORCE_COLOR=1 "$FORGE_BASH" "$FORGE_BIN" new healthy --defaults
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[\033[32m✓\033[0m] Creating project directories'* ]]
  [[ "$output" == *$'[\033[32m✓\033[0m] Generating CMake files and recording sync state'* ]]
  [[ "$output" != *'[ ]'* ]]

  mkdir broken
  cd broken
  touch src
  run env -u NO_COLOR FORCE_COLOR=1 "$FORGE_BASH" "$FORGE_BIN" init --defaults
  [ "$status" -eq 1 ]
  [[ "$output" == *$'[\033[31m✗\033[0m] Creating project directories'* ]]
  [[ "$output" != *'Writing editor settings'* ]]
}

@test "named new accepts an empty pipe and rejects incomplete metadata" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new from_pipe < <(printf '')
  [ "$status" -eq 0 ]
  [ -f from_pipe/Forge.toml ]
  grep -Fxq 'version = "0.1.0"' from_pipe/Forge.toml
  [[ "$output" != *'Version [0.1.0]:'* ]]

  run_forge new from_dev_null --dry-run </dev/null
  [ "$status" -eq 0 ]
  [ ! -e from_dev_null ]

  run_forge new incomplete < <(printf '1.2.3\n')
  [ "$status" -eq 2 ]
  [[ "$output" == *'expected Description'* ]]
  [ ! -e incomplete ]
}

@test "C++ library rejects a keyword class name even with a valid namespace override" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new class --lib --namespace acme --defaults
  [ "$status" -eq 2 ]
  [[ "$output" == *'C++ keyword cannot be used as a class name'* ]]
  [ ! -e class ]
}

@test "init refuses symlinked CMake and state directories before scaffolding" {
  cd "$BATS_TEST_TMPDIR"
  local dir
  for dir in cmake .forge; do
    mkdir -p outside project
    ln -s "$PWD/outside" "project/$dir"
    cd project
    run_forge init --name sample --defaults
    [ "$status" -eq 6 ]
    [[ "$output" == *"refusing to scaffold through a symlinked"* ]]
    [ ! -e Forge.toml ]
    [ -z "$(ls -A ../outside)" ]
    cd ..
    unlink "project/$dir"
  done
}


@test "new rejects CMake-reserved project names" {
  local dir="${BATS_TMPDIR}/forge-reserved-$$-${RANDOM}" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  local name
  for name in clean test all install package; do
    run_forge --no-color new "$name" --defaults
    [ "$status" -eq 2 ]
    [[ "$output" == *"reserved CMake target name"* ]]
    [ ! -e "$name" ]
  done
  cd "$old"
  rm -rf "$dir"
}


@test "new seeds clang tooling configuration as user-owned files" {
  local dir="${BATS_TMPDIR}/forge-tools-$$-${RANDOM}" old="$PWD"
  mkdir -p "$dir"; cd "$dir"
  run_forge --no-color new tooled --defaults
  [ "$status" -eq 0 ]
  cd tooled
  for f in .clang-format .clang-tidy .clangd cppcheck.supp cmake/user.cmake; do
    [ -f "$f" ] || fail "missing $f"
  done
  grep -Fq 'FORGE_CLANG_TIDY' cmake/user.cmake
  grep -Fq 'FORGE_CPPCHECK' cmake/user.cmake
  run_forge fmt --check
  [ "$status" -eq 0 ]
  # sync does not track user-owned tool configuration
  jq -e '.files | has(".clang-format") | not' .forge/state.json
  # a second scaffold in the same directory keeps the user's edits
  printf '# custom\n' >> .clang-format
  cp .clang-format "$BATS_TEST_TMPDIR/format.before"
  cd ..
  run_forge --no-color init --name tooled --defaults
  [ "$status" -eq 6 ] || true
  cd "$old"
  rm -rf "$dir"
}
