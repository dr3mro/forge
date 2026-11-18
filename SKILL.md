---
name: forge-project-memory
description: Maintain Forge, the Bash-based C++ orchestration CLI in /Users/amr/Repos/projector. Use for changes to its CLI, CMake and dependency integration, scaffolding, installer, tests, or project documentation.
---

# Forge project memory

## 1. What Forge is

Forge is a Cargo-inspired orchestration CLI for conventional C++ projects, written in Bash 4+. `Forge.toml` is intent; CMake is the build authority. Conan 2 resolves Conan packages; Git dependencies are pinned to full SHAs; there is no custom registry or solver. macOS and Linux only.

Core rules: never silently overwrite user work; changes go through `forge sync`; delegate resolution; every dependency states `conan`, `vcpkg`, `git` or `path`; no `eval`; arrays for subprocess args; frozen exit codes/JSON contract.

Implemented commands: `help`, `version`, `doctor`, `new`, `init`, `build`, `run`, `test`, `clean`, `add`, `remove`, `deps lock|pin|status`, `sync --check|--diff|--apply`, `fmt --check`, `docs`, `metadata --format json`, `generate lib|bin`, `workflow init`, `update`, and `uninstall`.

Exit codes: 0 ok · 1 other · 2 usage · 3 missing tool · 4 dependency/lock · 5 build/test · 6 conflict/unsafe write.

## 2. Environment (this machine)

- Default `/bin/bash` is 3.2 — always launch with `/opt/homebrew/bin/bash` (5.3.20) or put `/opt/homebrew/bin` first on PATH. The entry point rejects 3.2 with guidance.
- CMake 4.4.4, Conan 2.33.0, Git 2.54, jq 1.7.1, Python 3.15 (`tomllib`), clang-format (`/opt/homebrew/opt/llvm/bin`), Ninja 1.13, ShellCheck 0.11, Bats 1.14 (brew-installed), `shasum`, no `sha256sum`.
- Cached Conan package used in tests: `fmt/12.1.0` (header-only variant gives CMake target `fmt::fmt-header-only`).
- TOML adapter: python3 stdlib `tomllib` → JSON, queried with `jq`. No yq/dasel/taplo.

## 3. Layout

```
bin/forge                  entry point, Bash 4+ check, globals, EXIT trap
lib/_load.sh               top-level source of all modules (NOT via a function)
lib/ui.sh                  colors, FORCE_COLOR/NO_COLOR, ui_help_row
lib/core.sh                exit codes, out/status/warn/fail/die, atomic_write, paths, hashes
lib/diagnostics.sh         version/doctor, tools.versions reader, version_ge
lib/cli-reference.{sh,tsv} command help, completion protocol and command catalog
lib/cli.sh                 global flag parsing (anywhere before '--'), dispatch
lib/manifest.sh            parser adapter, schema validation, transactional block edits
lib/remove-entry.py        validated removal of dependency tables, member paths and target links
lib/schema.jq              TOML→JSON validation (schema 1 or 2)
lib/workspace.sh           recursive Forge.toml graph traversal
lib/state.sh               .forge/state.json + .forge/base copies
lib/sync.sh                graph-wide three-way merge, proposals, backups
lib/cmake.sh               template rendering, fingerprints, presets, File API
lib/conan.sh               Conan 2 install/lock, graph-wide requirement aggregation
lib/vcpkg.sh              workspace manifest, feature selection, version overrides and CMake integration
lib/fetchcontent.sh        SHA pin resolution, offline source checks
lib/deps.sh                deps lock/pin/status, graph-wide collision checks
lib/project.sh             scaffolding helpers
lib/commands/*.sh          one file per command group
install.sh, uninstall.sh  POSIX shell installer and uninstaller
templates/base/*           scaffold templates, version.cpp.in and Git ref hook
templates/completions/*    Bash and Zsh completion adapters
docs/index.html            self-contained Forge website and command reference
templates/editors/*        Zed and VS Code tasks and LLDB launch configs
templates/workflow/*       GitHub Actions template
tests/{unit,integration,fixtures,fakebin}   Bats suites
docs/*, docs/decisions/*   docs and decision records
tools.versions             single source of tool minimums
```

## 4. Current state

All phases 0–6 of the original plan were implemented. The user requested a new
`progress.md` checklist for the Conan shortcut, vcpkg support, documentation,
and coverage. Keep its stages current alongside `TODO.md`. Use temporary
projects for manual tests.

- Scaffolding writes user-owned Zed and VS Code build, test, and LLDB launch
  configs. Binary projects debug their app and library projects debug their
  test executable. The prelaunch task calls `forge build --debug-target NAME`
  and uses the stable `target/debug-NAME-launch` symlink.
- `sh install.sh` uses its adjacent source directory. `--source DIR` selects
  an unpacked source directory or a live checkout and copies the current CLI
  files. `--repo URL` (or `FORGE_REPOSITORY` for a streamed script) stages the
  Git repository's default branch. No official repository URL is configured.
  The installer tracks owned files in a private Git checkout or snapshot
  under `~/.local/share/forge` and links `~/.local/bin/forge`. `forge update`
  refreshes from the recorded source. Both uninstall entry points preserve
  unmanaged paths and installations with local edits or extra files.
- The installer creates completion links under Bash's per-user completion
  directory and `${ZDOTDIR:-$HOME}/.zfunc`. It registers them in regular
  `.bashrc` and `.zshrc` files and removes its registrations on uninstall.
  Existing completion files and symlinked startup files are preserved.
- `forge new [NAME]` and `forge init` share parsing for `--bin|--lib`,
  `--git`, `--defaults`, `--name`, `--version`, `--description`, `--author`,
  and `--email`. They prompt for omitted metadata in that order unless
  `--defaults` is present. An existing positional name still works for
  noninteractive `new` with no piped input. Scripts can pipe one line per
  omitted field. Supplying `--name` or any other metadata flag skips exactly
  that prompt. The default version is `0.1.0`. Description goes into the
  manifest and README. `package.author` is inherited by generated files.
- New scaffolds include `version.cpp.in` and a deployable
  `forge-reference-transaction` Git hook. When scaffolding a Git root, Forge
  installs it if the default hooks path is in use and the hook is free.
  Git runs it after committing a new numeric tag ref, optionally prefixed
  with `v`. The exact tag is stored in the template and shown by the default
  app's `--version`. CMake reads the numeric portion and configures the
  include. Before tagging it takes the version from `package.version`.
  Existing custom hooks can chain the generated hook. Hook registration is
  local to the Git checkout.
- Use `progress` before user-visible workflow stages. It prints a
  checklist marker on stderr and respects `--quiet`. Keep data and JSON on
  stdout and preserve passthrough for `forge run`.
- Contextual help and Bash/Zsh completion use `lib/cli-reference.tsv`.
  The shell adapters call the internal `__complete` protocol. Keep the same
  commands, options, and examples represented in `docs/index.html` and README.
  The website test checks catalog coverage and navigation links.
- `forge run --debug` and `forge run --release` override the manifest build
  profile. With no `--bin`, run selects the current module’s only declared
  application and can use a workspace-root build. Arguments after `--` go to
  the executable.
- `forge add` edits and reports the nearest enclosing `Forge.toml` by default,
  including from a nested directory of a workspace member. Its path dependency
  paths are relative to that manifest. Use `--manifest-path` to choose a
  different manifest. Both `add` and `generate` automatically apply the
  enclosing workspace’s three-way sync after the manifest edit. A conflict
  leaves the edit and a proposal and returns 6. Refresh the Conan lock
  separately from the workspace root. `remove NAME` drops both the dependency and
  its local links, then applies workspace sync. `remove NAME --lib` detaches
  `libs/NAME` and its parent links while preserving the source directory.
  References from other members must be cleared first.
- `forge add NAME[/VERSION] --conan` uses Conan install JSON to discover
  `cmake_file_name` and `cmake_target_name` under the workspace default profile.
  The discovery install uses a temporary output directory and never builds
  packages. Bare fmt pins `fmt/12.1.0` with `header_only=True` by default.
  Other bare names use a Conan version range and record the exact selected
  version. Offline Conan discovery, locks, and installs disable remotes.
  Explicit `--cmake-package` and `--cmake-target` bypass discovery for an exact
  reference.
- `forge add PORT --vcpkg` requires a bootstrapped checkout in `VCPKG_ROOT`
  at build time. Forge generates a workspace port manifest under the
  fingerprinted build directory. vcpkg is the outer toolchain and can
  chainload Conan. For vcpkg ports, probe CMake's Find module before falling
  back to config mode because Conan's toolchain otherwise prefers config mode.
  Set `features`, `default_features`, and exact `version` on the port's TOML
  dependency table. Exact versions require `build.vcpkg_baseline` from the
  workspace root. Repeated port declarations must agree. The generated
  JSON participates in the build fingerprint. Offline builds reuse a
  configured tree with manifest installation disabled.
- The package-manager shortcuts add the dependency and its selected link in
  one validated edit, then sync. The root's sole application has priority.
  Members use their sole application or library. Use `--target NAME` when
  ambiguous. Persisted `cmake_package` metadata identifies dependencies
  linked explicitly and keeps them out of legacy implicit links.
- `forge generate lib NAME --c` provides a .c source, a C/C++-compatible .h
  header, and a C test. C++ is the default and can be selected with `--cpp`.
  Mixed C and C++ workspaces build and test through their root.
- Library scaffolds persist `[[lib]].type` through `--static` (default)
  or `--shared` (alias `--dynamic`) for both C and C++. Existing manifests
  without a type retain CMake's `BUILD_SHARED_LIBS` behavior. Explicit static
  libraries enable PIC and shared libraries enable Windows symbol export.
- `new` and `init` create a user-owned root CI workflow. `workflow init`
  adds it to older projects and refuses to replace any existing CI files.
  `templates/workflow/ci.py.tpl` normalizes recursive dependencies, installs
  Conan or vcpkg packages, checks out pinned Git sources, and drives CMake,
  CTest and artifact packaging. Linux exports a cached dependency OCI image
  and passes its digest as a named Buildx context to the project build. The
  workflow uploads both images. Windows and macOS use native dependency
  caches and build archives. Both modes run Debug and Release. Regenerate the
  website reference when you change linkage options in the CLI catalog.
- C++ library scaffolds from `generate lib`, `new --lib`, and `init --lib`
  accept `--namespace NAME`, including nested names such as `acme::math`.
  The default is the library project's name. The `<name>_library` class defines
  all three access sections, defaulted construction and assignment, and a
  defaulted virtual destructor. The sample free function stays in the
  library's own namespace to let multiple libraries share a class namespace.
- `forge docs` runs optional Doxygen from the project root and writes
  `target/docs/html/index.html`. Its stdin configuration uses manifest metadata,
  declared bin/lib source files, and the conventional `src/` and `include/`
  trees. It escapes Doxygen environment references in display metadata and
  refuses symlinked output paths.
- In restricted sandboxes, Conan writes timestamps in its cache even for
  dependency resolution. Export `fmt/12.1.0:*` with `conan cache save`, copy the
  default profile to a writable temporary `CONAN_HOME`, and restore the
  archive there. The help tests set or unset `NO_COLOR` explicitly.

- `TODO.md` and `progress.md` track remaining coverage and hosted install
  verification. Scope Bashcov tracing to the launcher via `BASH_ENV` and
  unexport `SHELLOPTS` so Git subprocesses retain their normal shell settings.
  The Bash runtime measurement covers `bin/forge` and `lib/**/*.sh` and
  excludes installed copies, the POSIX lifecycle scripts, jq, Python, and
  branch coverage. The latest run covered 2,171 of 2,586 Bash runtime lines
  (83.95%), up from 82.95%. See `progress.md` for the reproduction steps.

The explicit OCI dependency-image follow-up passed actionlint, six workflow
and website checks, and the local Debug/Release packaging integration test.
Hosted Docker and runner execution remain unverified.

The previous full verification on macOS passed the 123-test Bats suite, a separate
Conan/vcpkg preparation regression, ShellCheck, and actionlint. A generated
project linked static C and shared C++ libraries and packaged Debug and
Release outputs. Local CI also locked, installed, and built against cached
Conan fmt. The Docker build and hosted Windows/macOS jobs still need a
GitHub Actions run. The recorded Bashcov result predates this CI follow-up.

```bash
cd /Users/amr/Repos/projector
shellcheck -x -S warning bin/forge install.sh uninstall.sh lib/*.sh lib/commands/*.sh tests/run.sh tests/fakebin/*
PATH="/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:$PATH" bash tests/run.sh
```

## 5. User preferences (learned the hard way)

- `forge help` must be two aligned columns with dot-free separation: `  <padded label>  <description>`. Descriptions start at a fixed column. Dots were explicitly rejected as ugly. Commands green, flags cyan, headings bold-cyan, dots/dim where applicable; color off for non-TTY, `NO_COLOR`, `--no-color`; on with TTY or `FORCE_COLOR=1`.
- Conan recipe must be **`conanfile.txt`**, not `conanfile.py`. Never reintroduce Python format.
- `generate lib NAME` must auto-link the new library into all targets of the current project's `Forge.toml` (append to `links`), plus register the workspace member. No manual linking step.
- Workspaces must be modular and recursive: every lib keeps its own `Forge.toml` with its own deps; `sync` walks all reachable manifests and updates every project's CMake.
- The user prefers simple, explicit workflows and asks "why" questions before accepting design changes — explain the cause and offer the smallest fix.
- Do not over-engineer or add commands not in the contract. Help must not advertise unimplemented commands.

## 6. Key decisions and gotchas

1. **Modules are sourced at top level** in `_load.sh`. Sourcing through a helper function made `declare -A` local and broke the associative array `FORGE_TOOL_REQ`.
2. **Guard `to_entries` with `// {}`** — TOML tables may be absent; jq errors on null.
3. **Global flags are parsed anywhere before `--`** (`sync --apply --yes` must work), unknown flags before the command are usage errors, after the command they pass through.
4. **File API has two levels**: codemodel references contain `jsonFile` names; load those for `type` and `artifacts[0].path`. An artifact path is absolute or relative to the top-level build directory. Prepending `paths.build` duplicates the subdirectory for workspace targets.
5. **`git merge-file -p -L current -L base -L incoming`** keeps temp paths out of conflict markers; binary files return 255 → treat as conflict.
6. **Lock staleness is keyed to Conan-relevant manifest data across the graph**, not file mtimes, so `add → deps lock → sync` works.
7. **Conan option patterns in `conanfile.txt` use the package name** as in `fmt/*:header_only=True`. Including the version in that pattern selects the wrong fmt target. Forge renders TOML booleans as Conan's capitalized `True` and `False`.
8. **CMake `-B` overrides preset binaryDir**, so fingerprinted dirs work with `cmake --preset`.
9. **Complexity check**: reuse of a configured build requires both `CMakeCache.txt` and `build.ninja`/`Makefile`.
10. **Conan `--build=never` (offline) conflicts with `--build=missing`** — make them exclusive.
11. **CMake reserved target names**: avoid project names like `clean`, `build`, `test`, `all`.
12. **Members only point to descendants** because paths cannot contain `..`, so the workspace graph is a tree.
13. **Conan generators go directly to the output folder** with `conanfile.txt` (no `cmake_layout`); `conan_toolchain_path` discovers via `find`, so no path assumptions.
14. **Line-ending note**: `git merge-file` preserves CRLF; a binary or missing-newline case is handled as a conflict.

## 7. Critical implementation details

- `manifest.sh` block edits: `mapfile` lines into `FORGE_EDIT_LINES`, identify the targeted tables, back up, reparse with `tomllib` + `schema.jq`,
  then atomically replace. `remove-entry.py` handles canonical Forge TOML,
  including multiline link and member arrays, and checks its parsed edit against
  the intended data change before writing. `manifest_add_link_to_targets` appends to every `[[bin]]/[[lib]]/[[test]]` `links` array.
- `sync`: `sync_prepare` collects the graph, then for each node temporarily swaps `FORGE_ROOT`/`FORGE_MANIFEST_JSON`/`FORGE_MANIFEST_PATH`/`FORGE_STATE_PATH`, renders templates to a temp dir, restores globals. `sync_detect_drift` returns 0/1/2 and fills `FORGE_SYNC_MESSAGES` with `label: message`. `sync_apply` merges per project with per-project proposals/backups.
- Root `conanfile.txt` aggregates every reachable Conan requirement; members keep their own declarations. Conflicting options for the same package or duplicate CMake target names are rejected.
- `compute_fingerprint` includes compiler, generator, arch, profile, Conan profiles, sanitizer, toolchain file. Build dir: `target/<profile>-<fingerprint>/`.
- `compile_commands.json` is symlinked into the root only when absent, or with `build --link-compile-commands`.
- UI: `ui_help_row LABEL DESCRIPTION LABEL_WIDTH [green|cyan|bold]`; label column padded, descriptions start at a fixed column, no dots.

## 8. How to continue

**Maintenance rule:** after finishing any task in this repository, update this
`SKILL.md` before reporting completion — record the new state, decisions,
user preferences, gotchas and verification results so the next session resumes
with accurate context. Do this even for small fixes.

1. Read `TODO.md` for the current backlog.
2. Before editing, run the verification commands in §4 to establish a baseline.
3. For help/completion changes edit `lib/cli-reference.tsv` and `lib/cli-reference.sh`; for dependency changes edit `lib/conan.sh`, `lib/cmake.sh`, `lib/schema.jq`; for workspace behavior edit `lib/workspace.sh`, `lib/sync.sh`, `lib/commands/generate.sh`.
4. Always write tests for new code and behavior, including bug fixes.
   Verify observable results through the normal entry points. Keep existing
   tests strong and fix the code when they expose a defect.
5. Keep docs in `docs/` aligned with `--help`.
6. Do not recreate `progress.md` or the original plan unless the user asks.
