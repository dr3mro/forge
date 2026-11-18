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
  grep -Fq 'find_package(ZLIB MODULE QUIET)' cmake/Dependencies.cmake
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
