# Dependencies

Forge supports three sources, each stated explicitly in `Forge.toml`:

| Source | Fields | Resolution |
| --- | --- | --- |
| `conan` | `ref`, optional `conan_options` | Conan 2 resolves the graph; Forge never mirrors it |
| `vcpkg` | `port`, `cmake_package`, `cmake_target` | vcpkg manifest mode |
| `git` | `url`, `rev` (full SHA) | `FetchContent_Declare(... GIT_TAG <sha>)`; tags/branches resolved by `deps pin` |
| `path` | `path` | `add_subdirectory` of an in-tree CMake project |

Conan packages are found with `find_package(<pkg> <version> CONFIG REQUIRED)`
using CMakeDeps. Git sources are consumed through their upstream CMake targets.
Forge never silently prefers a system package, and duplicate logical packages
are diagnosed across the **whole workspace graph**, not just the root.

Each member declares its own dependencies in its own `Forge.toml`. When the root
is built, all reachable Conan requirements are aggregated into the root
`conanfile.txt` and `conan.lock`, so a single `conan install` supplies every
member. Git/path dependencies stay in the member that declares them; their
`FetchContent_Declare` / `add_subdirectory` lines are rendered into that
member's `cmake/Dependencies.cmake`. Conflicting options for the same Conan
package, or two projects exporting the same CMake target name, are refused.

## Add a dependency to a workspace member

Run `forge add` from a member directory or any of its subdirectories. Forge
uses the nearest enclosing `Forge.toml` and prints the manifest it edited.
A `--path` value is relative to that manifest's directory. Use the global
`--manifest-path PATH` flag to edit a specific manifest from elsewhere.

```bash
cd libs/widgets/src
forge add fmt --source conan --ref fmt/12.1.0 \
  --cmake-target fmt::fmt-header-only --option header_only=True
```

Forge syncs the enclosing workspace after the edit. Return to its root to
refresh the shared Conan lock before building.

## Package manager shortcuts

`forge add fmt --conan` uses `fmt/12.1.0` and `header_only=True` by default.
Pass `fmt/VERSION` for an exact version. For other bare package names, Conan
resolves a version and Forge records the exact result. Forge uses the workspace’s default
build profile and the requested options to read Conan’s package and target
metadata. Discovery requires an available binary. Supply both
`--cmake-package` and `--cmake-target` to enter the CMake names explicitly
when Conan cannot provide metadata. `--offline` limits discovery to the
local Conan cache.

`forge add fmt --vcpkg` uses the installed vcpkg registry checkout. For example,
use `forge add zlib --vcpkg --cmake-package ZLIB --cmake-target ZLIB::ZLIB`
for a port whose CMake package name differs from the port name. Set
`VCPKG_ROOT` to a bootstrapped checkout before building. Forge aggregates
ports into a generated manifest under the build directory and uses vcpkg’s
CMake toolchain. An offline vcpkg build needs a previously configured build
directory for the same dependency set and disables manifest installation.
[Microsoft vcpkg documentation](https://learn.microsoft.com/vcpkg/users/buildsystems/cmake-integration)

Both shortcuts link the sole application or library in the current module
and apply workspace sync. At the workspace root, the sole application takes
precedence. Use `--target NAME` to select a specific local
target, including a test target. `--dry-run` previews the selection without
resolving or editing dependencies.

## Mixed workflow

```bash
forge add fmt --source conan --ref fmt/12.1.0 \
  --cmake-target fmt::fmt-header-only --option header_only=True
forge add catch2 --source git --url https://github.com/catchorg/Catch2.git \
  --rev <full-sha> --cmake-target Catch2::Catch2WithMain
forge add logger --source path --path libs/logger --cmake-target logger

forge deps lock                  # Conan lockfile
forge build                      # Conan install, then CMake configure + FetchContent
```

`add` edits the selected manifest and applies a three-way sync. On a merge
conflict, Forge leaves a proposal and exits with code 6. After adding a Conan
dependency, refresh the lock with `forge deps lock` before rebuilding.

## Conan integration

Forge checks for Conan 2, renders a reviewable `conanfile.txt` (CMakeDeps +
CMakeToolchain + `cmake_layout`) and runs `conan install` with explicit build
type and output folder before configuring. The lockfile is created from a
freshly rendered recipe so the documented `add → deps lock → sync` order works.
Locks are keyed to the Conan-relevant manifest data, not to `conanfile.txt`
mtimes. Because build directories are fingerprinted, Forge configures via its
own preset and passes Conan's discovered `conan_toolchain.cmake` with
`-DCMAKE_TOOLCHAIN_FILE` (see `docs/decisions/0003-conan-presets.md`).

## Offline

`--offline` is accepted where it can truly fail instead of fetching:

- `deps pin --tag/--branch` refuses to resolve a tag offline.
- Conan installs and locks use `--no-remote --build=never`. Missing cached packages fail clearly.
- `build` requires populated Git sources; otherwise it exits 4 with a clear
  message. When sources are present it sets
  `FETCHCONTENT_FULLY_DISCONNECTED=ON`.

## Security

URL schemes are validated; names and paths reject shell metacharacters. No user
input is interpolated into shell strings (all subprocess arguments are Bash
arrays) or unquoted CMake strings. Manifest parsing never executes project
scripts. Conan recipes and CMake dependencies can run third-party code — a
warning is shown when the first dependency is added. Secrets are redacted in
`--verbose` logs.

## Editing package settings

Change a Conan dependency's `ref` to select a different version and set
options under `[dependencies.NAME.conan_options]`. Use the new version's CMake
package and imported target if they changed. Run `forge sync --apply --yes`
and refresh the workspace lock with `forge deps lock`.

A vcpkg dependency can select `features`, set `default_features = false`, or
set an exact `version` override. Overrides require `vcpkg_baseline` in the
workspace root's `[build]` table. Use a full vcpkg registry commit SHA and
matching settings for each port shared across members. Forge translates these
settings to the generated vcpkg manifest and uses them in the build fingerprint.

`forge remove NAME` removes the dependency and its local target links.
`forge remove NAME --lib` detaches a generated library and preserves its files.
Both commands apply workspace sync. Remove links from other members before
detaching a library.
