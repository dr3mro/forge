#!/usr/bin/env bats
# Real mixed Conan 2 + FetchContent + path integration.
# Skips if fmt is not available in the local Conan cache (CI installs it).
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  command -v conan >/dev/null || skip "conan not installed"
  if ! conan list 'fmt/*' 2>/dev/null | grep -q 'fmt/'; then
    skip "fmt recipe not in local Conan cache"
  fi
  WORK="${BATS_TMPDIR}/forge-mixed-$$-${RANDOM}"
  GITREPO="${WORK}/gitdep"
  mkdir -p "${WORK}" "${GITREPO}/include"
  cat > "${GITREPO}/CMakeLists.txt" <<'EOF'
add_library(gdep INTERFACE)
add_library(gdep::gdep ALIAS gdep)
target_include_directories(gdep INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
EOF
  cat > "${GITREPO}/include/gdep.hpp" <<'EOF'
#pragma once
constexpr int gdep_value() { return 42; }
EOF
  (
    cd "${GITREPO}"
    git init -q
    git add .
    git -c user.email=a@b -c user.name=t commit -qm init
  )
  SHA=$(cd "${GITREPO}" && git rev-parse HEAD)
  mkdir -p "${WORK}/logger/include"
  cat > "${WORK}/logger/CMakeLists.txt" <<'EOF'
add_library(logger INTERFACE)
target_include_directories(logger INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
EOF
  cat > "${WORK}/logger/include/logger.hpp" <<'EOF'
#pragma once
constexpr int logger_value() { return 7; }
EOF
  cd "${WORK}"
  run_forge --no-color new mixed >/dev/null
  cd mixed
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "one target builds with Conan, Git and path dependencies" {
  cp -R "${WORK}/logger" libs-logger
  run_forge --no-color add fmt --source conan --ref fmt/12.1.0 \
    --cmake-target fmt::fmt-header-only
  [ "$status" -eq 0 ]
  printf '\n[dependencies.fmt.conan_options]\nheader_only = true\n' >> Forge.toml
  run_forge --no-color add gdep --source git --url "file://${GITREPO}" \
    --rev "${SHA}" --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  run_forge --no-color add logger --source path --path libs-logger --cmake-target logger
  [ "$status" -eq 0 ]

  run_forge --no-color deps lock
  [ "$status" -eq 0 ]
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]

  cat > src/main.cpp <<'EOF'
#include <fmt/format.h>
#include "gdep.hpp"
#include "logger.hpp"
int main() {
  return fmt::format("{} {}", gdep_value(), logger_value()).size() > 0 ? 0 : 1;
}
EOF
  cat > tests/main.cpp <<'EOF'
#include <cassert>
#include "gdep.hpp"
#include "logger.hpp"
int main() { assert(gdep_value() == 42); assert(logger_value() == 7); }
EOF

  run_forge --no-color build
  [ "$status" -eq 0 ]
  [[ "$output" == *"build ok"* ]]
  run_forge --no-color test
  [ "$status" -eq 0 ]
  run_forge --no-color run --bin mixed
  [ "$status" -eq 0 ]
}

@test "root conanfile aggregates Conan deps declared in members" {
  run_forge --no-color generate lib lib1 >/dev/null
  cd libs/lib1
  run_forge --no-color add fmt --source conan --ref fmt/12.1.0 \
    --cmake-target fmt::fmt-header-only --option header_only=True >/dev/null
  cd ../..
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  grep -q 'fmt/12.1.0' conanfile.txt
  grep -q 'find_package(fmt 12.1.0' libs/lib1/cmake/Dependencies.cmake
  run_forge --no-color deps lock
  [ "$status" -eq 0 ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
}

@test "offline build fails clearly without populated Git sources" {
  run_forge --no-color add gdep --source git --url "file://${GITREPO}" \
    --rev "${SHA}" --cmake-target gdep::gdep >/dev/null
  run_forge --no-color sync --apply --yes >/dev/null
  run_forge --no-color --offline build
  [ "$status" -eq 4 ]
  [[ "$output" == *"offline build requires populated Git sources"* ]]
}

@test "Conan shortcut links only the root application and builds with real Conan" {
  run_forge --no-color --offline add fmt --conan
  [ "$status" -eq 0 ]
  grep -Fq 'cmake_target = "fmt::fmt-header-only"' Forge.toml
  grep -Fq 'target_link_libraries(mixed PRIVATE fmt::fmt-header-only)' cmake/Targets.cmake
  ! grep -Fq 'target_link_libraries(mixed_tests PRIVATE fmt::fmt-header-only)' cmake/Targets.cmake

  cp Forge.toml before.toml
  run_forge --no-color add fmt/12.1.0 --conan
  [ "$status" -eq 0 ]
  cmp before.toml Forge.toml
  run_forge --no-color add fmt/12.2.0 --conan
  [ "$status" -eq 6 ]
  cmp before.toml Forge.toml
  run_forge --no-color deps lock
  [ "$status" -eq 0 ]
  cat > src/main.cpp <<'CPP'
#include <fmt/format.h>
int main() { return fmt::format("{}", 42) == "42" ? 0 : 1; }
CPP
  run_forge --no-color build
  [ "$status" -eq 0 ]
  run_forge --no-color run
  [ "$status" -eq 0 ]
}

@test "exact Conan shortcut from member source links the member only and syncs root" {
  run_forge --no-color generate lib mathlib
  [ "$status" -eq 0 ]
  cd libs/mathlib/src
  run_forge --no-color --offline add fmt/12.1.0 --conan
  [ "$status" -eq 0 ]
  grep -Fq 'target_link_libraries(mathlib PRIVATE fmt::fmt-header-only)' ../cmake/Targets.cmake
  ! grep -Fq 'fmt::fmt-header-only' ../../../cmake/Targets.cmake
  grep -Fxq 'fmt/12.1.0' ../../../conanfile.txt
  cat > mathlib.cpp <<'CPP'
#include "mathlib.hpp"
#include <fmt/format.h>
namespace mathlib {
int add(int a, int b) { return fmt::format("{}", a + b).empty() ? 0 : a + b; }
}
CPP
  cd ../../..
  run_forge --no-color deps lock
  [ "$status" -eq 0 ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
  run_forge --no-color test
  [ "$status" -eq 0 ]
}
