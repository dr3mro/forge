#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  WORK="${BATS_TMPDIR}/forge-ws-$$-${RANDOM}"
  mkdir -p "$WORK"; cd "$WORK"
  run_forge --no-color new app2 >/dev/null
  cd app2
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "generate lib registers a member and bumps schema to 2" {
  run_forge --no-color generate lib foo
  [ "$status" -eq 0 ]
  grep -q '^schema = 2$' Forge.toml
  grep -q 'members = \["libs/foo"\]' Forge.toml
  grep -q 'links = \["foo"\]' Forge.toml
  [ -f libs/foo/CMakeLists.txt ]
  [ -f libs/foo/include/foo.hpp ]
}

@test "generate bin member produces a second executable" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color generate bin tool >/dev/null
  run_forge --no-color sync --apply --yes >/dev/null
  run_forge --no-color build
  [ "$status" -eq 0 ]
  [ -x target/debug/ws_bins_tool/tool ]
}

@test "member edits automatically sync the enclosing workspace" {
  run_forge --no-color generate lib lib1 >/dev/null
  cd libs/lib1
  mkdir -p deps/logger
  printf 'add_library(logger INTERFACE)\n' > deps/logger/CMakeLists.txt
  mkdir -p src/nested
  cd src/nested
  run_forge --no-color add logger --source path --path deps/logger --cmake-target logger --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"/libs/lib1/Forge.toml"* ]]
  run_forge --no-color add logger --source path --path deps/logger --cmake-target logger
  [ "$status" -eq 0 ]
  [[ "$output" == *"/libs/lib1/Forge.toml"* ]]
  grep -Fq '[dependencies.logger]' ../../Forge.toml
  ! grep -Fq '[dependencies.logger]' ../../../../Forge.toml
  cd ../..
  run_forge --no-color generate lib lib2 >/dev/null
  cd ../..

  grep -q 'deps/logger' libs/lib1/cmake/Dependencies.cmake
  grep -q 'libs/lib2' libs/lib1/cmake/Dependencies.cmake

  run_forge --no-color sync --check
  [ "$status" -eq 0 ]
}

@test "two workspace libraries build and link per target" {
  command -v cmake >/dev/null || skip "cmake not installed"
  run_forge --no-color generate lib foo >/dev/null
  run_forge --no-color generate lib bar >/dev/null
  grep -q 'links = \["foo", "bar"\]' Forge.toml
  run_forge --no-color sync --apply --yes >/dev/null
  run_forge --no-color build
  [ "$status" -eq 0 ]
  grep -q 'target_link_libraries(app2 PRIVATE foo bar)' cmake/Targets.cmake
  run_forge --no-color test
  [ "$status" -eq 0 ]
}

@test "generate dry-run preserves the parent manifest and creates no member" {
  cp Forge.toml manifest.before
  run_forge --no-color generate lib preview --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would generate lib member 'preview'"* ]]
  cmp manifest.before Forge.toml
  [ ! -e libs/preview ]
}

@test "generate recovers attribution from an older initialized project" {
  printf '// Author: Legacy User <legacy@example.test>\n\n' > source.header
  cat source.header src/main.cpp > source.next
  mv source.next src/main.cpp
  run_forge --no-color generate lib inherited
  [ "$status" -eq 0 ]
  [ "$(head -n 1 libs/inherited/include/inherited.hpp)" = '// Author: Legacy User <legacy@example.test>' ]
}

@test "removing a library refuses when another module links to it" {
  run_forge generate lib shared
  [ "$status" -eq 0 ]
  run_forge generate lib client
  [ "$status" -eq 0 ]
  python3 - <<'PY'
from pathlib import Path
p = Path("libs/client/Forge.toml")
p.write_text(p.read_text().replace("links = []", 'links = ["shared"]'))
PY
  run_forge remove shared --lib
  [ "$status" -eq 6 ]
  [[ "$output" == *"remove links to 'shared'"* ]]
  grep -Fq '"libs/shared"' Forge.toml
}

@test "generate validates namespace and language options before editing the workspace" {
  cp Forge.toml before.toml
  run_forge generate lib invalid --namespace 'acme::'
  [ "$status" -eq 2 ]
  run_forge generate lib invalid --namespace
  [ "$status" -eq 2 ]
  run_forge generate lib invalid --c --namespace acme
  [ "$status" -eq 2 ]
  run_forge generate bin invalid --namespace acme
  [ "$status" -eq 2 ]
  cmp before.toml Forge.toml
  [ ! -e libs/invalid ]
  [ ! -e bins/invalid ]

  run_forge generate lib --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'--namespace NAME'* ]]
}

@test "nested C++ members use the root application namespace in header and source" {
  run_forge generate lib parent
  [ "$status" -eq 0 ]
  cd libs/parent
  run_forge generate lib child
  [ "$status" -eq 0 ]
  local header=libs/child/include/child.hpp source=libs/child/src/child.cpp
  grep -Fxq 'namespace app2 {' "$header"
  grep -Fxq 'namespace app2 {' "$source"
  grep -Fxq '  virtual ~child();' "$header"
  grep -Fxq 'child::~child() = default;' "$source"
  ! grep -E '\badd\(' "$header" "$source"
}
