#!/usr/bin/env bats
load ../test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  run_forge --no-color new demo
  [ "$status" -eq 0 ]
  cd demo
}

@test "shortcut rejects malformed references and conflicting sources before changing manifest" {
  cp Forge.toml before.toml
  run_forge add fmt/ --conan
  [ "$status" -eq 2 ]
  run_forge add fmt/12.2.0 --conan --ref fmt/12.1.0
  [ "$status" -eq 2 ]
  run_forge add fmt --conan --vcpkg
  [ "$status" -eq 2 ]
  run_forge add fmt --conan --source git
  [ "$status" -eq 2 ]
  cmp before.toml Forge.toml
}

@test "target selection is local and dry-run needs no Conan metadata" {
  cat >> Forge.toml <<'TOML'

[[bin]]
name = "also"
path = "src/main.cpp"
links = []
TOML
  cp Forge.toml before.toml
  run_forge add fmt/12.2.0 --conan
  [ "$status" -eq 2 ]
  [[ "$output" == *"use --target NAME"* ]]
  run_forge add fmt/12.2.0 --conan --target missing
  [ "$status" -eq 2 ]
  run_forge --dry-run add fmt/12.2.0 --conan --target also
  [ "$status" -eq 0 ]
  [[ "$output" == *"fmt/12.2.0"*"link 'also'"* ]]
  cmp before.toml Forge.toml
}

@test "Conan metadata reports ambiguous components and accepts a target override" {
  mkdir fakebin
  cat > fakebin/conan <<'SH'
#!/bin/sh
if [ "$1" = --version ]; then
  printf 'Conan version 2.33.0\n'
else
  cat <<'JSON'
{"graph":{"nodes":{"1":{"name":"example","context":"host","cpp_info":{
  "root":{"properties":{"cmake_file_name":"Example"}},
  "widget":{"properties":{"cmake_target_name":"Example::Widget"}},
  "tool":{"properties":{}}
}}}}}
JSON
fi
SH
  chmod +x fakebin/conan
  export PATH="$PWD/fakebin:$PATH"
  run_forge --no-color add example/1.0 --conan
  [ "$status" -eq 2 ]
  [[ "$output" == *"Example::Widget"*"example::tool"* ]]
  ! grep -Fq '[dependencies.example]' Forge.toml

  mock_conan_lock
  run_forge --no-color add example/1.0 --conan --cmake-target Example::Widget
  [ "$status" -eq 0 ]
  grep -Fq 'find_package(Example 1.0 CONFIG REQUIRED)' cmake/Dependencies.cmake
  grep -Fq 'target_link_libraries(demo PRIVATE Example::Widget)' cmake/Targets.cmake
}

@test "sync conflict retains both dependency and target link in the saved manifest" {
  printf '# user deps\n' > cmake/Dependencies.cmake
  run_forge --no-color add fmt/12.2.0 --conan --cmake-package fmt --cmake-target fmt::fmt
  [ "$status" -eq 6 ]
  [[ "$output" == *"manifest edit saved"* ]]
  grep -Fxq 'ref = "fmt/12.2.0"' Forge.toml
  grep -Fxq 'links = ["fmt"]' Forge.toml
  grep -Fxq '# user deps' cmake/Dependencies.cmake
  [ -f .forge/proposals/cmake_Dependencies.cmake.patch ]
}

@test "the root shortcut prioritizes the sole application and supports adding a second link" {
  cat >> Forge.toml <<'TOML'

[[lib]]
name = "sibling"
path = "src/main.cpp"
links = [
  # Preserved when linking the dependency explicitly.
]
TOML
  mock_conan_lock
  run_forge --no-color add fmt/12.2.0 --conan --cmake-package fmt --cmake-target fmt::fmt
  [ "$status" -eq 0 ]
  grep -Fq 'target_link_libraries(demo PRIVATE fmt::fmt)' cmake/Targets.cmake
  ! grep -Fq 'target_link_libraries(sibling PRIVATE fmt::fmt)' cmake/Targets.cmake

  run_forge --no-color add fmt/12.2.0 --conan --target sibling
  [ "$status" -eq 0 ]
  grep -Fq '# Preserved when linking' Forge.toml
  [ "$(grep -Fc '[dependencies.fmt]' Forge.toml)" -eq 1 ]
  grep -Fq 'target_link_libraries(sibling PRIVATE fmt::fmt)' cmake/Targets.cmake
}

@test "failed Conan metadata discovery leaves the module manifest untouched" {
  mkdir fakebin
  printf '#!/bin/sh\nif [ "$1" = --version ]; then echo "Conan version 2.33.0"; else exit 1; fi\n' > fakebin/conan
  chmod +x fakebin/conan
  export PATH="$PWD/fakebin:$PATH"
  cp Forge.toml before.toml
  run_forge --no-color --offline add fmt --conan
  [ "$status" -eq 4 ]
  [[ "$output" == *"could not inspect fmt/12.1.0"* ]]
  cmp before.toml Forge.toml
}

@test "bare Conan package records the exact version selected by Conan" {
  mkdir fakebin
  cat > fakebin/conan <<'SH'
#!/bin/sh
if [ "$1" = --version ]; then
  echo "Conan version 2.33.0"
else
  [ "$2" = '--requires=library-x/[*]' ] || exit 1
  echo '{"graph":{"nodes":{"1":{"name":"library-x","version":"2.4.1","context":"host","cpp_info":{"root":{"properties":{}}}}}}}'
fi
SH
  chmod +x fakebin/conan
  export PATH="$PWD/fakebin:$PATH"
  mock_conan_lock
  run_forge --no-color add library-x --conan
  [ "$status" -eq 0 ]
  grep -Fxq '[dependencies.library_x]' Forge.toml
  grep -Fxq 'ref = "library-x/2.4.1"' Forge.toml
  grep -Fq 'target_link_libraries(demo PRIVATE library-x::library-x)' cmake/Targets.cmake
  run_forge --no-color add library-x --conan
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
}

@test "Conan add locks the workspace after sync and skips an unchanged lock" {
  mock_conan_lock
  run_forge generate lib widget
  [ "$status" -eq 0 ]
  cd libs/widget
  run_forge --offline add fmt --conan --cmake-package fmt --cmake-target fmt::fmt-header-only
  [ "$status" -eq 0 ]
  [[ "$output" == *'sync applied'*'wrote conan.lock'* ]]
  [ -f ../../conan.lock ]
  [ ! -e conan.lock ]
  grep -Fq -- '--no-remote' "$FORGE_TEST_CONAN_LOCK_LOG"
  local first
  first=$(cat "$FORGE_TEST_CONAN_LOCK_LOG")

  run_forge add fmt --conan --cmake-package fmt --cmake-target fmt::fmt-header-only
  [ "$status" -eq 0 ]
  [ "$(cat "$FORGE_TEST_CONAN_LOCK_LOG")" = "$first" ]
  run_forge --dry-run add zlib/1.3.1 --conan --cmake-package ZLIB --cmake-target ZLIB::ZLIB
  [ "$status" -eq 0 ]
  [ "$(cat "$FORGE_TEST_CONAN_LOCK_LOG")" = "$first" ]
  ! grep -Fq '[dependencies.zlib]' Forge.toml
}

@test "failed automatic lock keeps the prior lock and permits retry after sync" {
  mock_conan_lock
  run_forge add fmt --conan --cmake-package fmt --cmake-target fmt::fmt-header-only
  [ "$status" -eq 0 ]
  cp conan.lock previous.lock
  export FORGE_TEST_FAIL_LOCK=1
  run_forge add zlib/1.3.1 --conan --cmake-package ZLIB --cmake-target ZLIB::ZLIB
  [ "$status" -eq 4 ]
  [[ "$output" == *'manifest edit and sync saved'* ]]
  grep -Fxq 'zlib/1.3.1' conanfile.txt
  cmp conan.lock previous.lock
  unset FORGE_TEST_FAIL_LOCK
  run_forge add zlib/1.3.1 --conan --cmake-package ZLIB --cmake-target ZLIB::ZLIB
  [ "$status" -eq 0 ]
  [[ "$output" == *'already linked'*'wrote conan.lock'* ]]
}
