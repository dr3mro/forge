#!/usr/bin/env bats
load ../test_helper

setup() {
  ORIG_PWD="$PWD"
  WORK="${BATS_TMPDIR}/forge-deps-$$-${RANDOM}"
  GITREPO="${WORK}/gitdep"
  mkdir -p "${WORK}" "${GITREPO}/include"
  cat > "${GITREPO}/CMakeLists.txt" <<'EOF'
add_library(gdep INTERFACE)
add_library(gdep::gdep ALIAS gdep)
EOF
  printf '#pragma once\n' > "${GITREPO}/include/gdep.hpp"
  (
    cd "${GITREPO}"
    git init -q
    git add .
    git -c user.email=a@b -c user.name=t commit -qm init
    git tag v1.0.0
  )
  SHA=$(cd "${GITREPO}" && git rev-parse HEAD)
  load_forge_libs
  cd "${WORK}"
  run_forge --no-color new proj >/dev/null
  cd proj
  mock_conan_lock
}

teardown() {
  cd "${ORIG_PWD}"
  rm -rf "${WORK}"
}

@test "add appends a conan dependency and creates a backup" {
  local before
  before=$(sha256_file CMakeLists.txt)
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 --cmake-target fmt::fmt
  [ "$status" -eq 0 ]
  grep -q '\[dependencies.fmt\]' Forge.toml
  grep -q 'ref = "fmt/12.1.0"' Forge.toml
  [ "$(sha256_file CMakeLists.txt)" = "${before}" ]
  [ -n "$(find .forge/backups -type f -print -quit)" ]
  load_forge_libs
  local json
  json=$(manifest_to_json Forge.toml)
  [ "$(printf '%s' "${json}" | jq -r '.dependencies.fmt.source')" = "conan" ]
}

@test "add refuses duplicate dependency names" {
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 --cmake-target fmt::fmt >/dev/null
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.1 --cmake-target fmt::fmt
  [ "$status" -eq 2 ]
  [[ "$output" == *already\ exists* ]]
}

@test "add --dry-run leaves the manifest untouched" {
  local before
  before=$(sha256_file Forge.toml)
  run_forge --no-color add --yes --dry-run fmt --source conan --ref fmt/12.1.0 --cmake-target fmt::fmt
  [ "$status" -eq 0 ]
  [ "$(sha256_file Forge.toml)" = "${before}" ]
}

@test "remove deletes exactly one dependency block" {
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 --cmake-target fmt::fmt >/dev/null
  run_forge --no-color add --yes logger --source path --path libs --cmake-target logger >/dev/null
  run_forge --no-color remove fmt
  [ "$status" -eq 0 ]
  [ "$(grep -c '\[dependencies\.' Forge.toml)" -eq 1 ]
  grep -q '\[dependencies.logger\]' Forge.toml
}

@test "deps pin resolves a tag to a full SHA" {
  run_forge --no-color add --yes gdep --source git --url "file://${GITREPO}" --sha "$SHA" --cmake-target gdep::gdep >/dev/null
  sed -i '' "s/${SHA}/0000000000000000000000000000000000000000/" Forge.toml 2>/dev/null \
    || sed -i "s/${SHA}/0000000000000000000000000000000000000000/" Forge.toml
  run_forge --no-color deps pin gdep --tag v1.0.0
  [ "$status" -eq 0 ]
  grep -q "rev = \"${SHA}\"" Forge.toml
}

@test "deps pin refuses tag resolution in offline mode" {
  run_forge --no-color add --yes gdep --source git --url "file://${GITREPO}" --sha "$SHA" --cmake-target gdep::gdep >/dev/null
  run_forge --no-color --offline deps pin gdep --tag v1.0.0
  [ "$status" -eq 4 ]
}

@test "deps status --format json is ANSI-free" {
  run_forge --no-color deps status --format json
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
  run jq -e '.dependencies | type == "array"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "Conan 1 is rejected by the adapter" {
  load_forge_libs
  local oldpath="$PATH"
  export PATH="${FORGE_PROJECT_DIR}/tests/fakebin:${PATH}"
  run conan_check
  export PATH="${oldpath}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Conan 2 is required"* ]]
}

@test "fake git resolves a tag to a fixed full SHA" {
  load_forge_libs
  local oldpath="$PATH" sha
  export PATH="${FORGE_PROJECT_DIR}/tests/fakebin:${PATH}"
  sha=$(fetchcontent_resolve_ref "https://example.invalid/repo.git" --tag v1.0.0)
  export PATH="${oldpath}"
  [ "${sha}" = "1111111111111111111111111111111111111111" ]
}

@test "duplicate cmake_target is diagnosed" {
  run_forge --no-color add --yes fmt --source conan --ref fmt/12.1.0 --cmake-target dup::target >/dev/null
  run_forge --no-color add --yes spdlog --source conan --ref spdlog/1.14.1 --cmake-target dup::target >/dev/null
  run_forge --no-color deps status
  [ "$status" -eq 4 ]
  [[ "$output" == *"duplicate cmake_target"* ]]
}

@test "add diagnoses an option missing its value" {
  run_forge --no-color add --yes logger --source path --path
  [ "$status" -eq 2 ]
  [[ "$output" == *"--path requires a value"* ]]
}

@test "remove strips explicit multiline links and syncs the Conan recipe" {
  run_forge add --yes fmt --conan --ref fmt/12.1.0 --cmake-package fmt --cmake-target fmt::fmt
  [ "$status" -eq 0 ]
  python3 - <<'PY'
from pathlib import Path
p = Path("Forge.toml")
p.write_text(p.read_text().replace('links = ["fmt"]', "links = [\n  'fmt', # imported shortcut\n]\n"))
PY
  run_forge remove fmt --dry-run
  [ "$status" -eq 0 ]
  grep -Fq "[dependencies.fmt]" Forge.toml
  run_forge remove fmt
  [ "$status" -eq 0 ]
  [[ "$output" == *"sync applied"* ]]
  [ ! -e conanfile.txt ]
  [ ! -e .forge/base/conanfile.txt ]
  jq -e '.files | has("conanfile.txt") | not' .forge/state.json
  ! grep -Fq 'fmt' cmake/Dependencies.cmake cmake/Targets.cmake
  run_forge sync --check
  [ "$status" -eq 0 ]
}

@test "remove --lib detaches a workspace member and preserves its source" {
  run_forge generate lib widget
  [ "$status" -eq 0 ]
  run_forge remove widget --lib
  [ "$status" -eq 0 ]
  [ -f libs/widget/src/widget.cpp ]
  ! grep -Fq widget Forge.toml cmake/Dependencies.cmake cmake/Targets.cmake
  run_forge sync --check
  [ "$status" -eq 0 ]
  run_forge remove widget --lib
  [ "$status" -eq 2 ]
}

@test "dependency status text, empty lock, and dry-run Git pin are available" {
  run_forge deps status
  [ "$status" -eq 0 ]
  run_forge deps lock
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Conan dependencies to lock"* ]]
  run_forge add --yes gdep --source git --url "file://${GITREPO}" --tag v1.0.0 --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  run_forge deps pin gdep --sha invalid
  [ "$status" -eq 2 ]
  run_forge deps pin gdep
  [ "$status" -eq 2 ]
  run_forge --dry-run deps pin gdep --sha "$SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would pin"* ]]
}

@test "retiring a Conan recipe preserves local edits and stops tracking it" {
  run_forge add --yes fmt --conan --cmake-package fmt --cmake-target fmt::fmt-header-only
  [ "$status" -eq 0 ]
  printf '\n# Keep this local change\n' >> conanfile.txt
  cp conanfile.txt edited.txt
  run_forge remove fmt
  [ "$status" -eq 0 ]
  [[ "$output" == *'keeping locally edited'* ]]
  cmp edited.txt conanfile.txt
  jq -e '.files | has("conanfile.txt") | not' .forge/state.json
  run_forge sync --check
  [ "$status" -eq 0 ]
}

@test "deps pin rejects competing selectors before changing the manifest" {
  git -C "$GITREPO" branch audit-branch
  run_forge add --yes gdep --source git --url "file://${GITREPO}" \
    --sha 0000000000000000000000000000000000000000 --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  cp Forge.toml manifest.before

  run_forge deps pin gdep --tag v1.0.0 --branch audit-branch
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires exactly one"* ]]
  run_forge deps pin gdep --sha "$SHA" --tag v1.0.0
  [ "$status" -eq 2 ]
  run_forge deps pin gdep --branch audit-branch --sha "$SHA"
  [ "$status" -eq 2 ]
  cmp manifest.before Forge.toml
}

@test "Git selectors distinguish a branch from an annotated tag with the same name" {
  git -C "$GITREPO" -c user.name=t -c user.email=a@b tag -am release shared "$SHA"
  git -C "$GITREPO" -c user.name=t -c user.email=a@b commit --allow-empty -qm next
  git -C "$GITREPO" branch shared
  local branch_sha
  branch_sha=$(git -C "$GITREPO" rev-parse refs/heads/shared)

  run_forge add --yes gdep --source git --url "file://${GITREPO}" --tag shared --branch shared --cmake-target gdep::gdep
  [ "$status" -eq 2 ]
  ! grep -Fq '[dependencies.gdep]' Forge.toml
  run_forge add --yes gdep --source=git --url "file://${GITREPO}" --tag shared --cmake-target gdep::gdep
  [ "$status" -eq 0 ]
  grep -Fxq "rev = \"$SHA\"" Forge.toml
  run_forge deps pin gdep --branch shared
  [ "$status" -eq 0 ]
  grep -Fxq "rev = \"$branch_sha\"" Forge.toml
}
