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
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 \
    --cmake-target fmt::fmt-header-only --option header_only=True
  [ "$status" -eq 0 ]
  python3 - <<'PYTHON'
from pathlib import Path
manifest = Path("Forge.toml")
manifest.write_text(manifest.read_text().replace('header_only = "True"', 'header_only = true'))
PYTHON
  run_forge --no-color add --yes gdep --source git --url "file://${GITREPO}" \
    --rev "${SHA}" --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  run_forge --no-color add --yes logger --source path --path libs-logger --cmake-target logger
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
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 \
    --cmake-target fmt::fmt-header-only --option header_only=True >/dev/null
  cd ../..
  run_forge --no-color sync --apply --yes
  [ "$status" -eq 0 ]
  grep -q 'fmt/12.1.0' conanfile.txt
  grep -q 'find_package(fmt 12.1.0 CONFIG REQUIRED GLOBAL)' libs/lib1/cmake/deps/fmt.cmake
  run_forge --no-color deps lock
  [ "$status" -eq 0 ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
}

@test "offline build fails clearly without populated Git sources" {
  run_forge --no-color add --yes gdep --source git --url "file://${GITREPO}" \
    --rev "${SHA}" --cmake-target gdep::gdep >/dev/null
  run_forge --no-color sync --apply --yes >/dev/null
  run_forge --no-color --offline build
  [ "$status" -eq 4 ]
  [[ "$output" == *"offline build requires populated Git sources"* ]]
}

@test "Conan shortcut links only the root application and builds with real Conan" {
  run_forge --no-color build
  [ "$status" -eq 0 ]
  ! grep -q 'fmt' compile_commands.json
  run_forge --no-color --offline add --yes fmt --conan
  [ "$status" -eq 0 ]
  grep -Fq 'cmake_target = "fmt::fmt-header-only"' Forge.toml
  grep -Fq 'target_link_libraries(mixed PRIVATE fmt::fmt-header-only)' cmake/Targets.cmake
  ! grep -Fq 'target_link_libraries(mixed_tests PRIVATE fmt::fmt-header-only)' cmake/Targets.cmake

  cp Forge.toml before.toml
  run_forge --no-color add --yes fmt/12.1.0 --conan
  [ "$status" -eq 0 ]
  cmp before.toml Forge.toml
  run_forge --no-color add --yes fmt/12.2.0 --conan
  [ "$status" -eq 6 ]
  cmp before.toml Forge.toml
  [ -f conan.lock ]
  cat > src/main.cpp <<'CPP'
#include <fmt/format.h>
int main() { return fmt::format("{}", 42) == "42" ? 0 : 1; }
CPP
  run_forge --no-color build
  [ "$status" -eq 0 ]
  jq -e 'any(.[]; (.file | endswith("/src/main.cpp")) and (.command | contains("/include")) and (.command | contains(".conan") or contains("/p/")))' compile_commands.json
  if command -v clangd >/dev/null 2>&1; then
    run clangd --check=src/main.cpp
    [ "$status" -eq 0 ]
  fi
  run_forge --no-color run
  [ "$status" -eq 0 ]
}

@test "exact Conan shortcut from member source links the member only and syncs root" {
  run_forge --no-color generate lib mathlib
  [ "$status" -eq 0 ]
  [ ! -e conanfile.txt ]
  [ ! -e libs/mathlib/conanfile.txt ]
  cd libs/mathlib/src
  run_forge --no-color --offline add --yes fmt/12.1.0 --conan
  [ "$status" -eq 0 ]
  grep -Fq 'target_link_libraries(mathlib PRIVATE fmt::fmt-header-only)' ../cmake/Targets.cmake
  ! grep -Fq 'fmt::fmt-header-only' ../../../cmake/Targets.cmake
  grep -Fxq 'fmt/12.1.0' ../../../conanfile.txt
  grep -Fxq 'fmt/12.1.0' ../conanfile.txt
  cat >> mathlib.cpp <<'CPP'
#include <fmt/format.h>
static_assert(FMT_VERSION > 0);
CPP
  cd ../../..
  [ -f conan.lock ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
  run_forge --no-color test
  [ "$status" -eq 0 ]
}

@test "mixed Conan and SQLite builds discard old duplicate presets and preserve custom presets" {
  run_forge add --yes fmt --conan --offline
  [ "$status" -eq 0 ]
  [ -f conan.lock ]
  run_forge build
  [ "$status" -eq 0 ]
  [ ! -e CMakeUserPresets.json ]

  local old
  old=$(find target -name CMakePresets.json -print -quit)
  [ -f "$old" ]
  mkdir -p target/debug-000000000000
  cp "$old" target/debug-000000000000/CMakePresets.json
  printf '{"version":4,"configurePresets":[{"name":"custom","hidden":true}]}\n' > custom-presets.json
  jq -n --arg old "$old" '{
    version: 4, vendor: {conan: {}, "test.example": {}},
    include: [$old, "target/debug-000000000000/CMakePresets.json", "custom-presets.json"]
  }' > CMakeUserPresets.json
  run cmake --list-presets
  [ "$status" -ne 0 ]
  [[ "$output" == *'Duplicate preset'*'conan-debug'* ]]

  export VCPKG_ROOT="$BATS_TEST_TMPDIR/vcpkg fixture"
  mkdir -p "$VCPKG_ROOT/scripts/buildsystems" "$VCPKG_ROOT/packages/unofficial-sqlite3"
  printf '#!/bin/sh\nexit 0\n' > "$VCPKG_ROOT/vcpkg"
  chmod +x "$VCPKG_ROOT/vcpkg"
  cat > "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" <<'CMAKE'
if(VCPKG_CHAINLOAD_TOOLCHAIN_FILE)
  include("${VCPKG_CHAINLOAD_TOOLCHAIN_FILE}")
endif()
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_LIST_DIR}/../../packages")
CMAKE
  cat > "$VCPKG_ROOT/packages/unofficial-sqlite3/unofficial-sqlite3-config.cmake" <<'CMAKE'
if(NOT TARGET unofficial::sqlite3::sqlite3)
  add_library(unofficial::sqlite3::sqlite3 INTERFACE IMPORTED)
  set_property(TARGET unofficial::sqlite3::sqlite3 PROPERTY INTERFACE_COMPILE_DEFINITIONS SQLITE_VCPKG_FIXTURE)
endif()
CMAKE
  run_forge add --yes sqlite3 --vcpkg
  [ "$status" -eq 0 ]
  cat > src/main.cpp <<'CPP'
#include <fmt/format.h>
#ifndef SQLITE_VCPKG_FIXTURE
#error "SQLite must come from the vcpkg package"
#endif
int main() { return fmt::format("{}", 42) == "42" ? 0 : 1; }
CPP

  run_forge build --release
  [ "$status" -eq 0 ]
  jq -e '.include == ["custom-presets.json"] and (.vendor | has("test.example"))' CMakeUserPresets.json
  run_forge build
  [ "$status" -eq 0 ]
  jq -e '.include == ["custom-presets.json"]' CMakeUserPresets.json
  run_forge run --release
  [ "$status" -eq 0 ]
}

@test "sanitizer builds and deps status read a valid Conan lock without prior sync" {
  run_forge --offline add --yes fmt --conan --target mixed_tests
  [ "$status" -eq 0 ]
  run_forge --offline deps lock
  [ "$status" -eq 0 ]
  run_forge deps status --format json
  [ "$status" -eq 0 ]
  jq -e '.conan_lock == "present"' <<< "$output"

  cat > tests/main.cpp <<'CPP'
#include <fmt/format.h>
int main() { return fmt::format("{}", 42) == "42" ? 0 : 1; }
CPP
  run_forge --offline test --sanitize address
  [ "$status" -eq 0 ]
  [[ "$output" == *'tests ok'* ]]
  [ -f target/sanitizers/address/debug/.forge-conan/conan_toolchain.cmake ]

  python3 - <<'PY'
from pathlib import Path
path = Path("Forge.toml")
path.write_text(path.read_text().replace('header_only = "True"', 'header_only = "False"'))
PY
  run_forge --offline test --sanitize address
  [ "$status" -eq 4 ]
  [[ "$output" == *'conan.lock is stale'* ]]
}


@test "Git dependency added after a Conan shortcut still links the application" {
  run_forge --no-color add --yes fmt --conan
  [ "$status" -eq 0 ]
  run_forge --no-color add --yes gdep --source git --url "file://${GITREPO}" \
    --rev "${SHA}" --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  grep -Fq 'gdep' <<<"$(grep -A3 '^\[\[bin\]\]' Forge.toml)"
  grep -Fq 'target_link_libraries(mixed PRIVATE gdep::gdep' cmake/Targets.cmake

  cat > src/main.cpp <<'CPP'
#include <fmt/core.h>
#include "gdep.hpp"
int main() { return fmt::format("{}", gdep_value()).size() > 0 ? 0 : 1; }
CPP
  run_forge --no-color build
  [ "$status" -eq 0 ]
}
