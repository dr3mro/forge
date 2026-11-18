#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  WORK="${BATS_TMPDIR}/forge-wf-$$-${RANDOM}"
  mkdir -p "$WORK"; cd "$WORK"
  run_forge --no-color new app >/dev/null
  cd app
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "new generates a root workflow and workflow init preserves user edits" {
  [ -f .github/workflows/forge.yml ]
  [ -f .github/forge/ci.py ]
  [ -f .github/forge/Dockerfile ]
  printf '# custom configuration\n' >> .github/workflows/forge.yml
  run_forge --no-color workflow init
  [ "$status" -eq 6 ]
  grep -Fxq '# custom configuration' .github/workflows/forge.yml
}

@test "workflow init adds the full CI template to an existing project and supports dry-run" {
  mv .github example-ci
  run_forge --no-color workflow init --dry-run
  [ "$status" -eq 0 ]
  [ ! -e .github ]
  run_forge --no-color workflow init
  [ "$status" -eq 0 ]
  diff -r example-ci .github
  if command -v actionlint >/dev/null 2>&1; then
    actionlint .github/workflows/forge.yml
  fi
}

@test "CI dependency inputs remain stable for source changes and track Git pins" {
  local dependency="$BATS_TEST_TMPDIR/upstream" first second
  git init -q "$dependency"
  printf 'add_library(upstream INTERFACE)\n' > "$dependency/CMakeLists.txt"
  git -C "$dependency" add CMakeLists.txt
  git -C "$dependency" -c user.name=Tests -c user.email=ci@example.test commit -qm initial
  first=$(git -C "$dependency" rev-parse HEAD)
  run_forge add --yes upstream --source git --url "file://$dependency" --rev "$first" --cmake-target upstream
  [ "$status" -eq 0 ]
  run python3 .github/forge/ci.py prepare
  [ "$status" -eq 0 ]
  cp target/forge-ci-inputs/plan.json initial.json
  printf '\n// source-only edit\n' >> src/main.cpp
  python3 .github/forge/ci.py prepare
  cmp initial.json target/forge-ci-inputs/plan.json
  python3 .github/forge/ci.py deps
  [ "$(git -C target/forge-ci-deps/git/UPSTREAM rev-parse HEAD)" = "$first" ]
  python3 .github/forge/ci.py build
  [ -f target/forge-ci-artifacts/project-Debug.tar.gz ]

  git -C "$dependency" -c user.name=Tests -c user.email=ci@example.test commit -qm update --allow-empty
  second=$(git -C "$dependency" rev-parse HEAD)
  run_forge deps pin upstream --sha "$second"
  [ "$status" -eq 0 ]
  python3 .github/forge/ci.py prepare
  ! cmp -s initial.json target/forge-ci-inputs/plan.json
  python3 .github/forge/ci.py deps
  [ "$(git -C target/forge-ci-deps/git/UPSTREAM rev-parse HEAD)" = "$second" ]
}

@test "CI requires a synced Conan recipe and prepares vcpkg version inputs" {
  cat >> Forge.toml <<'TOML'

[dependencies.fmt]
source = "conan"
ref = "fmt/12.1.0"
cmake_target = "fmt::fmt-header-only"

[dependencies.fmt.conan_options]
header_only = true

[dependencies.zlib]
source = "vcpkg"
port = "zlib"
cmake_package = "ZLIB"
cmake_target = "ZLIB::ZLIB"
default_features = false
version = "1.3.1"
TOML
  local baseline=1234567890abcdef1234567890abcdef12345678
  python3 - "$baseline" <<'PY'
from pathlib import Path
import sys
manifest = Path("Forge.toml")
manifest.write_text(manifest.read_text().replace("[build]\n", f'[build]\nvcpkg_baseline = "{sys.argv[1]}"\n'))
PY
  printf '{}\n' > conan.lock
  run python3 .github/forge/ci.py prepare
  [ "$status" -ne 0 ]
  [[ "$output" == *'missing conanfile.txt'* ]]
  printf '[requires]\nfmt/0.0.1\n' > conanfile.txt
  run python3 .github/forge/ci.py prepare
  [ "$status" -ne 0 ]
  [[ "$output" == *'conanfile.txt is out of sync'* ]]
  rm conanfile.txt
  run_forge sync --apply --yes
  [ "$status" -eq 0 ]
  run python3 .github/forge/ci.py prepare
  [ "$status" -eq 0 ]
  cmp conan.lock target/forge-ci-inputs/conan.lock
  grep -Fxq 'fmt/*:header_only=True' target/forge-ci-inputs/conanfile.txt
  jq -e --arg sha "$baseline" '
    .["builtin-baseline"] == $sha and .overrides == [{name:"zlib", version:"1.3.1"}]
    and .dependencies == [{name:"zlib", features:[], "default-features":false}]
  ' target/forge-ci-inputs/vcpkg.json
}

@test "generated Linux CI hands the dependency image to the project build by digest" {
  python3 - <<'PY'
from pathlib import Path

workflow = Path(".github/workflows/forge.yml").read_text()
dockerfile = Path(".github/forge/Dockerfile").read_text()
linux, native = workflow.split("\n  native:", 1)
dependencies, project = linux.split("- name: Build project image and run tests", 1)
assert "target: deps" in dependencies
assert "outputs: type=oci,dest=${{ runner.temp }}/deps-image.tar" in dependencies
assert "target: project" in project
assert "DEPENDENCY_IMAGE=ci-dependency-image" in project
assert "ci-dependency-image=oci-layout://" in project
assert "@${{ steps.deps-image.outputs.digest }}" in project
assert "Linux-deps-image-${{ matrix.config }}" in project
assert "Linux-image-${{ matrix.config }}" in project
assert "config: [Debug, Release]" in linux and "config: [Debug, Release]" in native
assert "os: [windows-2022, macos-15]" in native
dependencies, project = dockerfile.split("FROM ${DEPENDENCY_IMAGE} AS project", 1)
assert "COPY target/forge-ci-inputs/" in dependencies
assert "COPY . ." not in dependencies
assert "COPY . ." in project
assert 'ARG CONFIG=Debug' in project
PY
}
