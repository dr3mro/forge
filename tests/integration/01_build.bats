#!/usr/bin/env bats
# Real-tool integration: requires cmake, ninja, c++ and a Bash 4+ interpreter.
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  command -v cmake >/dev/null || skip "cmake not installed"
  command -v ninja >/dev/null || skip "ninja not installed"
  DIR="${BATS_TMPDIR}/forge-it-$$-${RANDOM}"
  mkdir -p "$DIR"
  cd "$DIR"
  run_forge --no-color new hello >/dev/null
  cd hello
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${BATS_TMPDIR}"/forge-it-$$-*
}

@test "bin project configures, builds, tests and runs with real CMake" {
  run_forge --no-color build
  [ "$status" -eq 0 ]
  [[ "$output" == *"build ok"* ]]
  [ -f compile_commands.json ]

  run_forge --dry-run test --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"would list ctest tests"* ]]

  run_forge --no-color test --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total Tests"* ]]
  [[ "$output" != *"tests ok"* ]]

  run_forge --no-color test
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests ok"* ]]

  run_forge --no-color run --debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from hello"* ]]
}

@test "lib project configures, builds and tests" {
  cd "${DIR}"
  rm -rf mylib
  run_forge --no-color new --lib mylib >/dev/null
  cd mylib
  run_forge --no-color build
  [ "$status" -eq 0 ]
  run_forge --no-color test
  [ "$status" -eq 0 ]
}

@test "run selects debug or release independently of the default and forwards arguments" {
  sed 's/default_profile = "debug"/default_profile = "release"/' Forge.toml > Forge.new
  mv Forge.new Forge.toml
  cat > src/main.cpp <<'CPP'
#include <iostream>
int main(int argc, char** argv) {
#ifdef NDEBUG
  std::cout << "release";
#else
  std::cout << "debug";
#endif
  if (argc > 1) std::cout << " " << argv[1];
  std::cout << '\n';
}
CPP
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  run_forge --no-color build --debug-target hello
  [ "$status" -eq 0 ]
  run_forge --no-color build --release
  [ "$status" -eq 0 ]

  run_forge --no-color run --debug --bin hello -- --release
  [ "$status" -eq 0 ]
  [ "$output" = "debug --release" ]
  run_forge --no-color run --release
  [ "$status" -eq 0 ]
  [ "$output" = "release" ]
  run_forge --no-color run --bin hello
  [ "$status" -eq 0 ]
  [ "$output" = "release" ]
  run_forge --no-color run --debug --release --bin hello
  [ "$status" -eq 2 ]
}

@test "run requires --bin when multiple executables exist" {
  cat >> Forge.toml <<'EOF'

[[bin]]
name = "hello2"
path = "src/main.cpp"
links = []
EOF
  run_forge --no-color sync --apply --yes >/dev/null
  run_forge --no-color build >/dev/null
  run_forge --no-color run
  [ "$status" -eq 2 ]
  [[ "$output" == *"multiple executables"* ]]
  run_forge --no-color run --bin hello2
  [ "$status" -eq 0 ]
}

@test "user CMake edits survive repeated builds" {
  run_forge --no-color build >/dev/null
  printf '\n# USER EDIT PRESENT\n' >> CMakeLists.txt
  run_forge --no-color build
  [ "$status" -eq 0 ]
  grep -q 'USER EDIT PRESENT' CMakeLists.txt
}

@test "clean refuses a symlinked profile and preserves its destination" {
  mkdir -p "${DIR}/outside"
  printf 'keep me\n' > "${DIR}/outside/marker"
  ln -s "${DIR}/outside" target/debug
  run_forge --no-color clean --profile debug
  [ "$status" -eq 6 ]
  [[ "$output" == *"refusing unsafe path"* ]]
  grep -Fxq 'keep me' "${DIR}/outside/marker"
  [ -L target/debug ]
}

@test "clean refuses a symlinked target directory before following it" {
  rmdir target
  mkdir -p "${DIR}/outside/debug"
  printf 'keep me\n' > "${DIR}/outside/debug/marker"
  ln -s "${DIR}/outside" target
  run_forge clean --profile debug
  [ "$status" -eq 6 ]
  [[ "$output" == *"refusing unsafe path"* ]]
  grep -Fxq 'keep me' "${DIR}/outside/debug/marker"
  [ -L target ]
}

@test "clean refuses an empty profile and leaves the default build alone" {
  run_forge build
  [ "$status" -eq 0 ]
  run_forge clean --profile= --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--profile requires a value"* ]]
  run_forge clean --profile=
  [ "$status" -eq 2 ]
  [ -f target/debug/CMakeCache.txt ]
}

@test "clean reports an active build as a conflict" {
  mkdir -p target/debug target/.debug.forge-lock
  touch target/debug/marker
  run_forge clean --profile debug
  [ "$status" -eq 6 ]
  [[ "$output" == *"refusing to clean an active build"* ]]
  [ -f target/debug/marker ]
  [ -d target/.debug.forge-lock ]
}

@test "clean refuses indirect sanitizer profiles inside the target directory" {
  mkdir -p target/sanitizers target/other/debug
  touch target/other/debug/marker
  ln -s ../other target/sanitizers/address
  run_forge clean --profile debug
  [ "$status" -eq 6 ]
  [[ "$output" == *"refusing unsafe path"* ]]
  [ -f target/other/debug/marker ]
}

@test "editor debug tasks build executable artifacts for binary and library projects" {
  for project in hello sample_lib; do
    local executable="$project"
    if [[ "$project" == sample_lib ]]; then
      cd "$DIR"
      run_forge --no-color new --lib "$project"
      [ "$status" -eq 0 ]
      cd "$project"
      executable="${project}_tests"
    fi

    local zed_build vscode_build
    zed_build=$(jq -er '.[0].build' .zed/debug.json)
    vscode_build=$(jq -er '.configurations[0].preLaunchTask' .vscode/launch.json)
    jq -e --arg name "$zed_build" --arg target "$executable" \
      'any(.[]; .label == $name and .command == "forge" and .args == ["build", "--debug-target", $target])' \
      .zed/tasks.json
    jq -e --arg name "$vscode_build" --arg target "$executable" \
      'any(.tasks[]; .label == $name and .command == "forge" and .args == ["build", "--debug-target", $target])' \
      .vscode/tasks.json
    local artifact="target/debug-${executable}-launch"
    jq -e --arg path "\$ZED_WORKTREE_ROOT/$artifact" '.[0].adapter == "CodeLLDB" and .[0].program == $path' .zed/debug.json
    jq -e --arg path "\${workspaceFolder}/$artifact" '.configurations[0] | .type == "lldb" and .program == $path' .vscode/launch.json

    run_forge --no-color build --debug-target "$executable"
    [ "$status" -eq 0 ]
    [ -L "$artifact" ]
    run "./$artifact"
    [ "$status" -eq 0 ]
  done
}

@test "debug build resolves a workspace member artifact from the top-level build directory" {
  run_forge --no-color generate bin worker
  [ "$status" -eq 0 ]
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  run_forge --no-color build --debug-target worker
  [ "$status" -eq 0 ]
  run ./target/debug-worker-launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from worker"* ]]
  cd bins/worker/src
  run_forge --no-color run --debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from worker"* ]]
}

@test "CTest empty filters require an explicit allow-no-tests flag" {
  run_forge --no-color build
  [ "$status" -eq 0 ]

  run_forge --no-color test '^no_such_target$'
  [ "$status" -eq 5 ]
  [[ "$output" == *"no tests found"* ]]
  run_forge --no-color test --allow-no-tests '^no_such_target$'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tests found (allowed by --allow-no-tests)"* ]]
}

@test "clean dry-run preserves a real build and clean removes the selected profile" {
  run_forge --no-color build
  [ "$status" -eq 0 ]
  local built
  built=target/debug
  [ -f "$built/CMakeCache.txt" ]

  run_forge --no-color clean --profile debug --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would delete $built"* ]]
  [ -f "$built/CMakeCache.txt" ]
  run_forge --no-color clean --profile debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted $built"* ]]
  [ ! -e "$built" ]
  [ ! -e target/compile_commands.json ]
  [ ! -e compile_commands.json ]
}

@test "clean --all preserves unrelated target files and prunes stale database links" {
  run_forge --no-color build >/dev/null
  [ "$status" -eq 0 ]
  [ -L target/compile_commands.json ]
  echo 'keep me' > target/user-notes.txt
  run_forge --no-color clean --all --yes >/dev/null
  [ "$status" -eq 0 ]
  [ ! -e target/debug ]
  [ ! -e target/compile_commands.json ]
  [ ! -e compile_commands.json ]
  [ "$(cat target/user-notes.txt)" = "keep me" ]
}

@test "generated C and C++ libraries inherit attribution and build in the same workspace" {
  cd "$DIR"
  mkdir authored
  cd authored
  run_forge --no-color init <<< $'app\n\n\nA. Developer\ndev@example.test'
  [ "$status" -eq 0 ]

  run_forge --no-color generate lib c_math --c
  [ "$status" -eq 0 ]
  run_forge --no-color generate lib cpp_math --cpp
  [ "$status" -eq 0 ]

  local file
  for file in libs/c_math/{include/c_math.h,src/c_math.c,tests/main.c} \
              libs/cpp_math/{include/cpp_math.hpp,src/cpp_math.cpp,tests/main.cpp}; do
    [ "$(head -n 1 "$file")" = '// Author: A. Developer <dev@example.test>' ]
    [ "$(sed -n '3p' "$file")" = '// Purpose:' ]
  done
  grep -q 'LANGUAGES C)' libs/c_math/CMakeLists.txt
  grep -q 'LANGUAGES CXX)' libs/cpp_math/CMakeLists.txt
  cat > src/main.cpp <<'CPP'
#include "c_math.h"
#include "cpp_math.hpp"
int main() { app::cpp_math math; return c_math_add(2, 3) == 5 ? 0 : 1; }
CPP
  run_forge --no-color sync --check
  [ "$status" -eq 0 ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
  run_forge --no-color test
  [ "$status" -eq 0 ]
  [[ "$output" == *c_math_tests*cpp_math_tests* ]]
  run_forge --no-color run --debug
  [ "$status" -eq 0 ]
}

@test "local release tag updates the generated executable and CMake project version" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new app --git --defaults --version 1.2.3
  [ "$status" -eq 0 ]
  cd app
  git -c user.name=Test -c user.email=test@example.test commit -qm initial --allow-empty
  run_forge build
  [ "$status" -eq 0 ]
  run_forge run -- --version
  [ "$output" = 1.2.3 ]
  git tag checkpoint
  grep -Fq '@PROJECT_VERSION@' version.cpp.in
  git -c user.name=Test -c user.email=test@example.test tag -am release v2.3.4
  grep -Fxq 'inline constexpr char forge_version[] = "v2.3.4";' version.cpp.in
  run_forge build
  [ "$status" -eq 0 ]
  run_forge run -- --version
  [ "$output" = v2.3.4 ]
  find target -name CMakeCache.txt -exec grep -Fx 'CMAKE_PROJECT_VERSION:STATIC=2.3.4' {} + | grep -q .
  git tag -d v2.3.4
  grep -Fq '"v2.3.4"' version.cpp.in
}

@test "C++ library classes share a custom namespace and support defaulted operations" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new consumer --defaults
  [ "$status" -eq 0 ]
  cd consumer
  run_forge generate lib math --cpp --namespace acme::numeric
  [ "$status" -eq 0 ]
  run_forge generate lib geometry --namespace acme::numeric
  [ "$status" -eq 0 ]
  run_forge generate lib standalone
  [ "$status" -eq 0 ]
  grep -Fxq 'namespace consumer {' libs/standalone/include/standalone.hpp

  cat > src/main.cpp <<'CPP'
#include <memory>
#include <utility>

#include "geometry.hpp"
#include "math.hpp"
#include "standalone.hpp"

class Derived : public acme::numeric::math {
 public:
  explicit Derived(bool& destroyed) : destroyed_(destroyed) {}
  ~Derived() override { destroyed_ = true; }

 private:
  bool& destroyed_;
};

int main() {
  bool destroyed = false;
  {
    std::unique_ptr<acme::numeric::math> library =
        std::make_unique<Derived>(destroyed);
    auto copy = *library;
    auto moved = std::move(copy);
    copy = *library;
    moved = std::move(copy);
  }
  acme::numeric::geometry geometry;
  consumer::standalone standalone;
  return destroyed ? 0 : 1;
}
CPP
  run_forge build
  [ "$status" -eq 0 ]
  run_forge test
  [ "$status" -eq 0 ]
  run_forge run
  [ "$status" -eq 0 ]
}

@test "generated CI builds and packages static and shared libraries in both configurations" {
  cd "$BATS_TEST_TMPDIR"
  run_forge new package_app --defaults
  [ "$status" -eq 0 ]
  cd package_app
  run_forge generate lib archive --static --c
  [ "$status" -eq 0 ]
  run_forge generate lib plugin --dynamic
  [ "$status" -eq 0 ]
  run_forge generate lib support --c --shared
  [ "$status" -eq 0 ]
  [ ! -e libs/plugin/.github ]
  grep -Fxq 'type = "static"' libs/archive/Forge.toml
  grep -Fxq 'type = "shared"' libs/plugin/Forge.toml
  cat > src/main.cpp <<'CPP'
#include "archive.h"
#include "plugin.hpp"
#include "support.h"
int main() {
  package_app::plugin plugin;
  return archive_add(1, 2) == support_add(1, 2) ? 0 : 1;
}
CPP
  python3 .github/forge/ci.py prepare
  local config
  for config in Debug Release; do
    run python3 .github/forge/ci.py deps --config "$config"
    [ "$status" -eq 0 ]
    run python3 .github/forge/ci.py build --config "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"100% tests passed"* ]]
    run tar -tzf "target/forge-ci-artifacts/project-$config.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" == *'bin/package_app'* && "$output" == *'lib/libarchive.a'* ]]
    [[ "$output" =~ lib/libplugin\.(dylib|so) ]]
    [[ "$output" =~ lib/libsupport\.(dylib|so) ]]
    [[ "$output" == *plugin_export.h* && "$output" == *support_export.h* ]]
  done
}

@test "editor compilation database follows Debug and Release and preserves user files" {
  run_forge build
  [ "$status" -eq 0 ]
  [ "$(readlink compile_commands.json)" = "target/compile_commands.json" ]
  local debug
  debug=$(readlink target/compile_commands.json)
  [ "$debug" = debug/compile_commands.json ]

  # Simulate an existing project linked directly to its original build.
  rm compile_commands.json
  ln -s "target/debug-000000000000/compile_commands.json" compile_commands.json
  run_forge build --release
  [ "$status" -eq 0 ]
  [ "$(readlink compile_commands.json)" = "target/compile_commands.json" ]
  [ "$(readlink target/compile_commands.json)" = release/compile_commands.json ]
  jq -e 'any(.[]; .file | endswith("/src/main.cpp"))' compile_commands.json

  rm compile_commands.json
  printf 'custom database\n' > compile_commands.json
  run_forge build
  [ "$status" -eq 0 ]
  [ ! -L compile_commands.json ]
  [ "$(cat compile_commands.json)" = "custom database" ]
  [[ "$output" == *"leaving user-owned"* ]]
  run_forge build --link-compile-commands
  [ "$status" -eq 0 ]
  [ "$(readlink compile_commands.json)" = "target/compile_commands.json" ]
  [ "$(readlink target/compile_commands.json)" = "$debug" ]
}

@test "run --build builds the requested profile and preserves executable arguments and status" {
  bats_require_minimum_version 1.5.0
  cat > src/main.cpp <<'CPP'
#include <iostream>
int main(int argc, char** argv) {
#ifdef NDEBUG
  std::cout << "release";
#else
  std::cout << "debug";
#endif
  for (int i = 1; i < argc; ++i) std::cout << "|" << argv[i];
  return 7;
}
CPP
  run --separate-stderr "$FORGE_BASH" "$FORGE_BIN" run --build --release -- --build 'two words'
  [ "$status" -eq 7 ]
  [ "$output" = 'release|--build|two words' ]
  [[ "$stderr" == *'build ok: target/release'* ]]
  run --separate-stderr "$FORGE_BASH" "$FORGE_BIN" run --build --debug
  [ "$status" -eq 7 ]
  [ "$output" = 'debug' ]

  printf 'this will not compile\n' > src/main.cpp
  run --separate-stderr "$FORGE_BASH" "$FORGE_BIN" run --build --release
  [ "$status" -eq 5 ]
  [ -z "$output" ]
  [[ "$stderr" == *'build failed'* ]]
}

@test "run --build uses the workspace build tree and dry-run leaves it untouched" {
  run_forge generate bin worker
  [ "$status" -eq 0 ]
  run_forge run --build --bin clean
  [ "$status" -eq 2 ]
  cd bins/worker
  run_forge run --build --dry-run -- --example
  [ "$status" -eq 0 ]
  [[ "$output" == *'dry-run: would run worker --example'* ]]
  [ -z "$(find ../../target -mindepth 1 -print -quit)" ]
  run_forge run --build
  [ "$status" -eq 0 ]
  [[ "$output" == *'Hello from worker!'* ]]
  [ "$(readlink ../../target/compile_commands.json)" = debug/compile_commands.json ]
}

@test "a changed toolchain refreshes CMake in place without creating fingerprinted build directories" {
  printf 'set(FORGE_TOOLCHAIN_TEST first CACHE STRING "")\n' > toolchain.cmake
  run_forge build --toolchain toolchain.cmake
  [ "$status" -eq 0 ]
  grep -Fxq 'FORGE_TOOLCHAIN_TEST:STRING=first' target/debug/CMakeCache.txt

  printf 'set(FORGE_TOOLCHAIN_TEST second CACHE STRING "")\n' > toolchain.cmake
  run_forge build --toolchain toolchain.cmake
  [ "$status" -eq 0 ]
  grep -Fxq 'FORGE_TOOLCHAIN_TEST:STRING=second' target/debug/CMakeCache.txt
  run_forge build --release --toolchain toolchain.cmake
  [ "$status" -eq 0 ]
  [ -f target/release/CMakeCache.txt ]
  [ "$(find target -mindepth 1 -maxdepth 1 -type d | sort)" = $'target/debug\ntarget/release' ]
}

@test "a second build cannot write to an active profile directory" {
  mkdir target/.debug.forge-lock
  run_forge build
  [ "$status" -eq 6 ]
  [[ "$output" == *'another build is active'* ]]
  [ -d target/.debug.forge-lock ]
  [ ! -e target/debug/CMakeCache.txt ]
  rmdir target/.debug.forge-lock
  run_forge build
  [ "$status" -eq 0 ]
  [ -f target/debug/CMakeCache.txt ]
  [ ! -e target/.debug.forge-lock ]
}

@test "sync upgrades a legacy CMake project and builds with its migrated dependency" {
  run_forge add --yes helper --source path --path vendor/helper --cmake-target helper
  [ "$status" -eq 0 ]
  mkdir -p vendor/helper
  cat > vendor/helper/CMakeLists.txt <<'CMAKE'
add_library(helper INTERFACE)
target_compile_definitions(helper INTERFACE FORGE_HELPER_AVAILABLE)
CMAKE
  cat >> src/main.cpp <<'CPP'
#ifndef FORGE_HELPER_AVAILABLE
#error "path dependency must be linked"
#endif
CPP

  # Simulate the previous layout and recorded bases, including a local root edit.
  cat > CMakeLists.txt <<'CMAKE'
# Generated by Forge. Managed by `forge sync`.
# Edit freely; run `forge sync --diff` after changing Forge.toml.
cmake_minimum_required(VERSION 3.25)
project(hello VERSION 0.1.0 LANGUAGES CXX)
configure_file(version.cpp.in forge-version.cpp @ONLY)
set(CMAKE_CXX_STANDARD 20)
include(CTest)
include(cmake/Dependencies.cmake)
include(cmake/Targets.cmake)
if(BUILD_TESTING)
  include(cmake/Testing.cmake)
endif()
CMAKE
  cat > cmake/Dependencies.cmake <<'CMAKE'
# Generated by Forge. Managed by `forge sync`.
# Conan packages are provided by CMakeDeps via the generated toolchain.

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/vendor/helper"
                 "${CMAKE_CURRENT_BINARY_DIR}/helper")
CMAKE
  load_forge_libs
  local file
  for file in CMakeLists.txt cmake/Dependencies.cmake; do
    cp "$file" ".forge/base/$file"
    jq --arg file "$file" --arg hash "$(sha256_file "$file")" '.files[$file] = $hash' \
      .forge/state.json > state.next
    mv state.next .forge/state.json
  done
  printf '\n# keep this root comment\n' >> CMakeLists.txt
  local -a additions=(cmake/Version.cmake cmake/VersionSource.cmake cmake/ProjectOptions.cmake
    cmake/Workspace.cmake cmake/deps/helper.cmake)
  for file in "${additions[@]}"; do
    rm "$file" ".forge/base/$file"
    jq --arg file "$file" 'del(.files[$file])' .forge/state.json > state.next
    mv state.next .forge/state.json
  done
  run_forge sync --diff
  [ "$status" -eq 0 ]
  [[ "$output" == *'cmake/deps/helper.cmake'* ]]
  [ ! -e cmake/deps/helper.cmake ]
  run_forge sync --apply --yes
  [ "$status" -eq 0 ]
  grep -Fxq '# keep this root comment' CMakeLists.txt
  ! grep -Eq 'set\(CMAKE_CXX_STANDARD|configure_file\(|add_(library|executable|test)\(' CMakeLists.txt
  for file in cmake/*.cmake cmake/deps/helper.cmake; do
    # ProjectOptionsUser.cmake and user.cmake are plain setting files, not
    # function modules: sync renders bracket-quoted set(...) lines into them.
    case "$file" in
      cmake/ProjectOptionsUser.cmake | cmake/user.cmake) continue ;;
    esac
    [ "$(grep -c '^function(' "$file")" -eq 1 ]
  done
  grep -Fq 'include(cmake/deps/helper.cmake)' cmake/Dependencies.cmake
  cmp cmake/deps/helper.cmake .forge/base/cmake/deps/helper.cmake
  run_forge sync --check
  [ "$status" -eq 0 ]
  run_forge build
  [ "$status" -eq 0 ]
  run_forge test
  [ "$status" -eq 0 ]
}

@test "CMake manifest variables are literal defaults and user.cmake takes precedence" {
  # New scaffolds already seed [cmake.variables] (codesign/debug defaults),
  # so insert the keys into that existing table instead of redeclaring it.
  python3 - <<'PY'
from pathlib import Path
p = Path('Forge.toml')
s = p.read_text()
needle = '[cmake.variables]\n'
addition = ("CMAKE_CXX_STANDARD = 23\n"
            "BUILD_TESTING = false\n"
            "FORGE_LITERAL = 'text ]=] ${UNCHANGED}'\n")
assert needle in s
p.write_text(s.replace(needle, needle + addition, 1))
PY
  cat > cmake/user.cmake <<'CMAKE'
if(NOT FORGE_LITERAL STREQUAL [==[text ]=] ${UNCHANGED}]==])
  message(FATAL_ERROR "Manifest string was altered")
endif()
if(BUILD_TESTING)
  message(FATAL_ERROR "Expected the manifest default to be OFF")
endif()
set(CMAKE_CXX_STANDARD 17)
set(BUILD_TESTING ON)
cmake_language(DEFER CALL target_compile_definitions hello PRIVATE USER_CMAKE_RAN)
CMAKE
  cp cmake/user.cmake "$DIR/user.before"
  cat >> src/main.cpp <<'CPP'
#if __cplusplus != 201703L || !defined(USER_CMAKE_RAN)
#error "expected user.cmake settings to take precedence"
#endif
CPP
  run_forge sync --apply --yes
  [ "$status" -eq 0 ]
  cmp "$DIR/user.before" cmake/user.cmake
  jq -e '.files | has("cmake/user.cmake") | not' .forge/state.json
  grep -Fq 'set(CMAKE_CXX_STANDARD [=[' cmake/ProjectOptionsUser.cmake
  grep -Fxq '23]=])' cmake/ProjectOptionsUser.cmake
  grep -Fq 'set(BUILD_TESTING [=[' cmake/ProjectOptionsUser.cmake
  grep -Fxq 'OFF]=])' cmake/ProjectOptionsUser.cmake
  grep -Fq 'set(FORGE_LITERAL [==[' cmake/ProjectOptionsUser.cmake
  grep -Fq -- '-fdiagnostics-show-template-tree' cmake/Diagnostics.cmake
  run_forge build
  [ "$status" -eq 0 ]
  run_forge test
  [ "$status" -eq 0 ]
}

@test "macOS debug binaries are codesigned with the debugging entitlement" {
  [[ "$(uname -s)" == Darwin ]] || skip "macOS only"
  run_forge --no-color build
  [ "$status" -eq 0 ]

  run codesign -dv target/debug/hello
  [ "$status" -eq 0 ]
  run codesign -d --entitlements - target/debug/hello
  [ "$status" -eq 0 ]
  [[ "$output" == *'com.apple.security.get-task-allow'* ]]

  # Debug flags come from the seeded [cmake.variables].
  grep -q -- '-O0' compile_commands.json

  # leaks can attach to the signed process.
  run leaks -quiet -atExit -- target/debug/hello
  [ "$status" -eq 0 ]
  [[ "$output" != *'not debuggable'* ]]
}

@test "Clang diagnostics are active in a real build and user.cmake can opt out" {
  CC=clang CXX=clang++ run_forge --no-color build
  [ "$status" -eq 0 ]
  [ -f compile_commands.json ]
  grep -q -- '-fdiagnostics-show-template-tree' compile_commands.json

  printf 'set(FORGE_CLANG_DIAGNOSTICS OFF)\n' > cmake/user.cmake
  CC=clang CXX=clang++ run_forge --no-color build
  [ "$status" -eq 0 ]
  ! grep -q -- '-fdiagnostics-show-template-tree' compile_commands.json
}

@test "watch rebuilds after a source edit and stops the previous application" {
  run_forge watch --dry-run --bin hello -- example
  [ "$status" -eq 0 ]
  [[ "$output" == *"would watch"* ]]

  run python3 - "$FORGE_BASH" "$FORGE_BIN" "$DIR/watch.log" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

bash, forge, output = sys.argv[1:]
log = Path(output)
source = Path("src/main.cpp")

def write_source(message):
    source.write_text(
        '#include <iostream>\n#include <unistd.h>\n'
        f'int main(int argc, char** argv) {{ std::cout << "{message} " << '
        'getpid() << " " << (argc > 1 ? argv[1] : "") << std::endl; for (;;) pause(); }\n'
    )

def wait_for(message):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        for line in log.read_text().splitlines():
            if line.startswith(message + " "):
                _, pid, arg = line.split()
                assert arg == "example", line
                return int(pid)
        time.sleep(0.1)
    raise AssertionError(log.read_text())

write_source("first")
with log.open("w") as stream:
    watcher = subprocess.Popen(
        [bash, forge, "watch", "--bin", "hello", "--", "example"],
        stdout=stream, stderr=subprocess.STDOUT,
    )
    try:
        first = wait_for("first")
        write_source("second")
        second = wait_for("second")
        assert first != second
        try:
            os.kill(first, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError("first application was still running")
    finally:
        watcher.send_signal(signal.SIGINT)
        watcher.wait(timeout=10)
    assert watcher.returncode == 130, log.read_text()
PY
  [ "$status" -eq 0 ]
}

@test "workspace members keep a different C++ standard than the root" {
  cd "${DIR}"
  run_forge --no-color new root --defaults --cppstd 17 >/dev/null
  [ "$status" -eq 0 ]
  cd root
  run_forge --no-color generate lib fast --cppstd 23 >/dev/null
  [ "$status" -eq 0 ]
  run_forge --no-color build >/dev/null
  [ "$status" -eq 0 ]
  run jq -e '
    ([.[] | select(.file | endswith("root/src/main.cpp")) | .command | contains("-std=c++17")] | any)
    and ([.[] | select(.file | endswith("libs/fast/src/fast.cpp")) | .command | contains("-std=c++23")] | any)
  ' target/debug/compile_commands.json
  [ "$status" -eq 0 ]
}

@test "watch --sanitize rebuilds and restarts in the sanitizer tree" {
  run_forge --no-color build --sanitize address >/dev/null
  [ "$status" -eq 0 ]

  run python3 - "$FORGE_BASH" "$FORGE_BIN" "$DIR/watch-sanitize.log" <<'PY'
from pathlib import Path
import signal
import subprocess
import sys
import time

bash, forge, output = sys.argv[1:]
log = Path(output)
source = Path("src/main.cpp")

def wait_for(predicate, message):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(message + "\n" + log.read_text())

with log.open("w") as stream:
    watcher = subprocess.Popen(
        [bash, forge, "watch", "--sanitize", "address", "--bin", "hello"],
        stdout=stream, stderr=subprocess.STDOUT,
    )
    try:
        wait_for(lambda: "Hello from hello" in log.read_text(), "first run")
        source.write_text(source.read_text() + "\n// touched\n")
        wait_for(lambda: log.read_text().count("Hello from hello") >= 2, "restart")
    finally:
        watcher.send_signal(signal.SIGINT)
        watcher.wait(timeout=10)
    assert watcher.returncode == 130, log.read_text()
assert "sanitizers/address/debug" in log.read_text(), log.read_text()
PY
  [ "$status" -eq 0 ]
}
