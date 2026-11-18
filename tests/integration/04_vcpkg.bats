#!/usr/bin/env bats
load ../test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color new sample
  [ "$status" -eq 0 ]
  cd sample
}

@test "vcpkg workspace ports reach CMake manifest mode and link a real build" {
  export VCPKG_ROOT="$BATS_TEST_TMPDIR/vcpkg fixture"
  mkdir -p "$VCPKG_ROOT/scripts/buildsystems" "$VCPKG_ROOT/packages/fmt"
  printf '#!/bin/sh\nexit 0\n' > "$VCPKG_ROOT/vcpkg"
  chmod +x "$VCPKG_ROOT/vcpkg"
  cat > "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" <<'CMAKE'
get_property(in_try_compile GLOBAL PROPERTY IN_TRY_COMPILE)
if(in_try_compile)
  return()
endif()
file(READ "${VCPKG_MANIFEST_DIR}/vcpkg.json" manifest)
string(JSON port GET "${manifest}" dependencies 0)
if(NOT port STREQUAL "fmt")
  message(FATAL_ERROR "expected the fmt port")
endif()
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_LIST_DIR}/../../packages")
CMAKE
  cat > "$VCPKG_ROOT/packages/fmt/fmt-config.cmake" <<'CMAKE'
if(NOT TARGET fmt::fmt)
  add_library(fmt::fmt INTERFACE IMPORTED)
  set_property(TARGET fmt::fmt PROPERTY INTERFACE_COMPILE_DEFINITIONS FORGE_VCPKG_TEST)
endif()
CMAKE
  run_forge --no-color generate lib member
  [ "$status" -eq 0 ]
  cd libs/member/src
  run_forge --no-color add fmt --vcpkg
  [ "$status" -eq 0 ]
  grep -Fq 'target_link_libraries(member PRIVATE fmt::fmt)' ../cmake/Targets.cmake
  cat >> member.cpp <<'CPP'
#ifndef FORGE_VCPKG_TEST
#error "the member must link to the vcpkg package"
#endif
CPP
  cd ../../..
  [ ! -e conanfile.txt ]
  [ ! -e libs/member/conanfile.txt ]
  run_forge --no-color build
  [ "$status" -eq 0 ]
  local manifest
  manifest=$(find target -name vcpkg.json -print -quit)
  jq -e '.dependencies == ["fmt"]' "$manifest"
  run_forge --no-color --offline build
  [ "$status" -eq 0 ]
  grep -Fxq 'VCPKG_MANIFEST_INSTALL:BOOL=OFF' "${manifest%/.forge-vcpkg/vcpkg.json}/CMakeCache.txt"
}

@test "vcpkg add validates port metadata and build requires a toolchain" {
  unset VCPKG_ROOT
  run_forge --no-color add zlib --vcpkg
  [ "$status" -eq 2 ]
  run_forge --no-color add zlib --vcpkg --cmake-package ZLIB --cmake-target ZLIB::ZLIB
  [ "$status" -eq 0 ]
  grep -Fq 'find_package(ZLIB MODULE QUIET GLOBAL)' cmake/deps/zlib/CMakeLists.txt
  run_forge --no-color build
  [ "$status" -eq 3 ]
  [[ "$output" == *"set VCPKG_ROOT"* ]]
}

@test "vcpkg settings generate feature selection and exact version overrides" {
  run_forge add fmt --vcpkg
  [ "$status" -eq 0 ]
  local baseline=1234567890abcdef1234567890abcdef12345678
  python3 - "$baseline" <<'PY'
from pathlib import Path
import sys
p = Path("Forge.toml")
text = p.read_text().replace("[build]\n", f'[build]\nvcpkg_baseline = "{sys.argv[1]}"\n')
p.write_text(text + 'features = ["feature-b", "feature-a"]\ndefault_features = false\nversion = "11.0.0#1"\n')
PY
  run "$FORGE_BASH" -c '
    FORGE_HOME=$1
    FORGE_LIB=$FORGE_HOME/lib
    source "$FORGE_LIB/_load.sh"
    FORGE_ROOT=$PWD
    FORGE_MANIFEST_PATH=$PWD/Forge.toml
    manifest_load
    vcpkg_workspace_manifest
  ' _ "$FORGE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  jq -e --arg baseline "$baseline" '
    ."builtin-baseline" == $baseline and
    .dependencies == [{name:"fmt",features:["feature-a","feature-b"],"default-features":false}] and
    .overrides == [{name:"fmt",version:"11.0.0#1"}]
  ' <<< "$output"
}

@test "sqlite3 shortcut uses the imported vcpkg target and rejects app targets" {
  local app
  app=$(sed -n 's/^name = "\([^"]*\)"$/\1/p' Forge.toml | head -1)
  cp Forge.toml before.toml
  run_forge add sqlite3 --vcpkg --cmake-target "$app"
  [ "$status" -eq 2 ]
  [[ "$output" == *'names a project target'* ]]
  cmp before.toml Forge.toml

  run_forge add sqlite3 --vcpkg
  [ "$status" -eq 0 ]
  grep -Fxq 'cmake_package = "unofficial-sqlite3"' Forge.toml
  grep -Fxq 'cmake_target = "unofficial::sqlite3::sqlite3"' Forge.toml
  grep -Fq "target_link_libraries($app PRIVATE unofficial::sqlite3::sqlite3)" cmake/Targets.cmake
  python3 - "$app" <<'PY'
from pathlib import Path
import sys
p = Path("Forge.toml")
p.write_text(p.read_text().replace("unofficial::sqlite3::sqlite3", sys.argv[1]))
PY
  run_forge sync --apply --yes
  [ "$status" -eq 0 ]
  run_forge build
  [ "$status" -eq 4 ]
  [[ "$output" == *"vcpkg cmake_target '$app' names a project target"* ]]
}

make_registry() {
  export VCPKG_ROOT="$BATS_TEST_TMPDIR/registry"
  mkdir -p "$VCPKG_ROOT/versions"
  printf '{"default":{"fmt":{"baseline":"12.0.0","port-version":0}}}\n' > "$VCPKG_ROOT/versions/baseline.json"
  git -C "$VCPKG_ROOT" init -q
  git -C "$VCPKG_ROOT" add versions
  git -C "$VCPKG_ROOT" -c user.name=Forge -c user.email=forge@example.test commit -qm baseline
}

@test "vcpkg version shortcut pins the workspace baseline and avoids re-adding the same port" {
  make_registry
  local baseline
  baseline=$(git -C "$VCPKG_ROOT" rev-parse HEAD)
  run_forge add 'fmt/12.0.0#1' --vcpkg
  [ "$status" -eq 0 ]
  grep -Fxq "vcpkg_baseline = \"$baseline\"" Forge.toml
  grep -Fxq 'version = "12.0.0#1"' Forge.toml
  cp Forge.toml before
  unset VCPKG_ROOT
  run_forge add 'fmt/12.0.0#1' --vcpkg
  [ "$status" -eq 0 ]
  [[ "$output" == *'already linked'* ]]
  run_forge add fmt/12.2.0 --vcpkg
  [ "$status" -eq 6 ]
  cmp before Forge.toml
  run_forge add sqlite3/3.54.1 --vcpkg
  [ "$status" -eq 0 ]
  grep -Fxq "vcpkg_baseline = \"$baseline\"" Forge.toml
  grep -Fxq 'version = "3.54.1"' Forge.toml
  run_forge sync --check
  [ "$status" -eq 0 ]
}

@test "versioned vcpkg add in a member pins only the workspace root" {
  make_registry
  local baseline
  baseline=$(git -C "$VCPKG_ROOT" rev-parse HEAD)
  run_forge generate lib member
  [ "$status" -eq 0 ]
  cd libs/member
  run_forge add fmt/12.0.0 --vcpkg
  [ "$status" -eq 0 ]
  grep -Fxq "vcpkg_baseline = \"$baseline\"" ../../Forge.toml
  ! grep -Fq vcpkg_baseline Forge.toml
  grep -Fxq 'version = "12.0.0"' Forge.toml
  cd ../..
  run_forge sync --check
  [ "$status" -eq 0 ]
  local directory
  for directory in . libs/member; do
    (
      cd "$directory"
      run "$FORGE_BASH" -c '
        FORGE_HOME=$1
        FORGE_LIB=$FORGE_HOME/lib
        source "$FORGE_LIB/_load.sh"
        FORGE_ROOT=$PWD
        FORGE_MANIFEST_PATH=$PWD/Forge.toml
        manifest_load
        vcpkg_workspace_manifest
      ' _ "$FORGE_PROJECT_DIR"
      [ "$status" -eq 0 ]
      jq -e --arg sha "$baseline" '."builtin-baseline" == $sha and .overrides == [{"name":"fmt","version":"12.0.0"}]' <<< "$output"
    )
  done
}

@test "versioned vcpkg dry run needs no registry and a failed baseline lookup keeps the manifest" {
  unset VCPKG_ROOT
  cp Forge.toml before
  run_forge add fmt/12.0.0 --vcpkg --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would add 'fmt/12.0.0'"* ]]
  run_forge add fmt/12.0.0 --vcpkg
  [ "$status" -eq 3 ]
  [[ "$output" == *'set VCPKG_ROOT'* ]]
  run_forge add fmt/ --vcpkg
  [ "$status" -eq 2 ]
  cmp before Forge.toml
}
