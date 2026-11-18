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

@test "clean refuses unsafe symlink targets" {
  mkdir -p "${DIR}/outside"
  ln -s "${DIR}/outside" target/escape
  run_forge --no-color clean --all --yes
  [[ "$output" == *"refusing unsafe path"* ]]
  [ -d "${DIR}/outside" ]
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
