# Forge implementation progress

## Scaffolding, package options, and installer

- [x] Share interactive metadata and scriptable flags across `new` and `init`.
- [x] Wire the generated Git tag hook to the application and CMake version.
- [x] Add progress markers and sync after dependency or library removal.
- [x] Expose vcpkg port features and version overrides in Forge.toml.
- [x] Install from a source directory and support a supplied URL for piped setup.
- [x] Register and remove Bash and Zsh completions.
- [x] Reconcile help, examples, the dependency guide, and the project skill.
- [x] Pass ShellCheck, shell syntax checks, and all 111 Bats tests. Verify
  real Conan and vcpkg package configuration and offline builds.
- [x] Refactor shared scaffold and CMake target rendering logic and remeasure
  Bash line coverage. The scoped Bashcov run covered 2,068 of 2,493 lines
  (82.95%) across 29 runtime files, up from 80.36%.
- [ ] Verify the hosted installer after the repository URL is supplied.


## Reproduce Bash coverage

Run Bashcov from a temporary source copy with the normal test dependencies
and a writable Conan cache. The runtime metric counts executable lines from
`bin/forge` and Bash modules under `lib/`. It excludes installed copies,
POSIX lifecycle and hook scripts, jq, Python, and branch coverage.

```sh
cat > coverage-env.sh <<'SH'
case "$0" in
  */bin/forge) set -x ;;
esac
SH
cat > coverage-entry.sh <<'SH'
#!/usr/bin/env bash
export -n SHELLOPTS
export BASH_ENV="$PWD/coverage-env.sh"
exec bash tests/run.sh
SH
bashcov --bash-path "$(command -v bash)" -- coverage-entry.sh
```

Bashcov writes its report under `coverage/`. Filter the report to the runtime
files above for comparison with the most recent measurement. Reaching 100% remains
open, including unmet command failure paths and separate instrumentation for
the installer, hook, and manifest adapters.


## CLI reference, website, and C++ library templates

- [x] Verify partial metadata prompts for both scaffold commands.
- [x] Share a command catalog across scoped CLI help and shell completions.
- [x] Add a standalone HTML reference and verify desktop and mobile layouts.
- [x] Scaffold configurable C++ library namespaces and test defaulted
  copy and move operations and virtual destruction in a real build.
- [x] Pass ShellCheck, shell syntax checks, and all 120 Bats tests.
- [x] Measure Bash line coverage at 2,171 of 2,586 lines (83.95%) across
  30 Bash runtime files. The previous result was 82.95%.
- [ ] Reach 100% runtime test coverage.


## Library linkage and generated CI

- [x] Scaffold explicit static and shared targets and preserve legacy manifests.
- [x] Generate root CI for Debug and Release on Linux, Windows, and macOS.
- [x] Reuse dependency inputs across source-only changes and refresh them on
  dependency changes. Export build archives and Linux project images.
- [x] Verify the 123-test Bats suite and separate Conan/vcpkg preparation test.
  ShellCheck and actionlint passed. Local test builds packaged both library
  types and configurations, and a Conan smoke build passed.
- [ ] Verify Docker and native jobs on hosted GitHub Actions runners.

## Explicit dependency images

- [x] Export a Linux dependency OCI image in Debug and Release and pass its
  digest into the project image build. Upload both images and extract the
  tested binary archive from the project image.
- [x] Verify workflow syntax with actionlint, run the six focused unit checks,
  and build and package both configurations through the local CI helper.
- [ ] Exercise OCI export, image loading, and the platform matrix on GitHub Actions.
