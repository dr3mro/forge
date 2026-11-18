---
name: forge-project-memory
description: Maintain Forge, the Bash-based C++ orchestration CLI in /Users/amr/Repos/projector. Use for changes to its CLI, CMake and dependency integration, scaffolding, installer, tests, or project documentation.
---

# Forge project memory

## 1. What Forge is

Forge is a Cargo-inspired orchestration CLI for conventional C++ projects, written in Bash 4+. `Forge.toml` is intent; CMake is the build authority. Conan 2 resolves Conan packages; Git dependencies are pinned to full SHAs; there is no custom registry or solver. macOS and Linux only.

Core rules: never silently overwrite user work; changes go through `forge sync`; delegate resolution; every dependency states `conan`, `vcpkg`, `git` or `path`; no `eval`; arrays for subprocess args; frozen exit codes/JSON contract.

Implemented commands: `help`, `version`, `doctor`, `new`, `init`, `build`, `run`, `watch`, `test`, `clean`, `add`, `remove`, `deps lock|pin|status`, `sync --check|--diff|--apply`, `fmt --check`, `docs`, `metadata --format json`, `generate lib|bin`, `workflow init`, `update`, and `uninstall`.

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
- With no arguments, `sh install.sh` and the streamed installer clone the
  default branch of `https://github.com/dr3mro/forge.git`. The published
  script URL is `https://raw.githubusercontent.com/dr3mro/forge/refs/heads/main/install.sh`.
  `--source DIR_OR_REPO` copies an existing directory or clones a Git
  repository. Local snapshots include the MIT license when present. The
  `--repo` flag and a positional Git source remain accepted. `forge update`
  uses the original source. Both uninstall entry points preserve unmanaged
  paths and installations with local edits or extra files.
- Keep the primary curl command, launcher PATH setup, and `forge doctor`
  example aligned across README, `docs/getting-started.md`, and
  `docs/index.html`. Show local source installation as an alternate option.
- Register PATH with an exact, guarded startup line in Bash interactive and
  login profiles and in Zsh's `.zshrc`. Check the entire PATH component
  before prepending. Uninstall removes the matching Forge-owned line.
- The installer creates completion links under Bash's per-user completion
  directory and `${ZDOTDIR:-$HOME}/.zfunc`. It registers them in regular
  `.bashrc` and `.zshrc` files and removes its registrations on uninstall.
  Existing completion files and symlinked startup files are preserved.
- `forge new [NAME]` and `forge init` share parsing for `--bin|--lib`,
  `--git`, `--defaults`, `--name`, `--version`, `--description`, `--author`,
  and `--email`. They prompt for omitted metadata in that order unless
  `--defaults` is present. A named noninteractive `new` uses defaults on
  empty stdin, including an empty pipe. It cancels if a response stream
  starts and then ends early. Scripts can pipe one line per omitted field. Supplying `--name` or any other metadata flag skips exactly
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
- Pair `progress "step"` with `progress_finish` after successful work.
  A failed step uses `progress_finish STATUS` or is closed by `die`.
  Diagnostics show one result line per step, with a green check or red cross
  when color is enabled. Keep results on stderr and respect `--quiet`.
- Contextual help and Bash/Zsh completion use `lib/cli-reference.tsv`.
  The shell adapters call the internal `__complete` protocol. Keep the same
  commands, options, and examples represented in `docs/index.html` and README.
  The website test checks catalog coverage and navigation links.
- Git dependency completion guides `forge add NAME --source git` through
  `--url`, one of `--tag`, `--branch` or `--sha`, and `--cmake-target`.
  It runs locally and accepts Bash's split `--source=git` input. Keep the
  FetchContent example in the CLI catalog, README, and website command
  reference aligned. All 42 focused CLI, dependency, installer, and website
  tests passed, along with ShellCheck.
- `forge run --build` uses the normal build pipeline for the requested
  profile and workspace application, then launches the freshly built
  executable. Build diagnostics go to stderr so the app owns stdout.
  Arguments after `--` and the app's exit status pass through.
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
- Conan adds sync first, then refresh a missing or stale workspace-root lock.
  If locking fails, the manifest and sync edits remain saved and the previous
  lock is preserved. Repeating an unchanged shortcut skips a current lock.
  Use `forge deps lock` for explicit refreshes after manual manifest edits.
- `forge add NAME[/VERSION] --conan` uses Conan install JSON to discover
  `cmake_file_name` and `cmake_target_name` under the workspace default profile.
  The discovery install uses a temporary output directory and never builds
  packages. Bare fmt pins `fmt/12.1.0` with `header_only=True` by default.
  Other bare names use a Conan version range and record the exact selected
  version. Offline Conan discovery, locks, and installs disable remotes.
  Explicit `--cmake-package` and `--cmake-target` bypass discovery for an exact
  reference. When a ref cannot be resolved, `_conan_metadata_failure` queries
  `conan list NAME/* -r '*' --format=json` and fails with every version the
  remotes offer (version-sorted), instead of the misleading explicit-names hint;
  offline mode keeps the generic message.
- `forge add PORT --vcpkg` requires a bootstrapped checkout in `VCPKG_ROOT`
  at build time. Forge generates a workspace port manifest under the
  stable profile build directory. vcpkg is the outer toolchain and can
  chainload Conan. For vcpkg ports, probe CMake's Find module before falling
  back to config mode because Conan's toolchain otherwise prefers config mode.
  SQLite's vcpkg defaults are package `unofficial-sqlite3` and target
  `unofficial::sqlite3::sqlite3`. Reject vcpkg imports naming a local project
  target. Conan installs disable root user-preset generation. Before builds,
  Forge prunes old fingerprinted includes from Conan-marked
  `CMakeUserPresets.json` files and preserves unrelated includes.
  Set `features`, `default_features`, and exact `version` on the port's TOML
  dependency table. Exact versions require `build.vcpkg_baseline` from the
  workspace root. Repeated port declarations must agree. The generated
  JSON participates in the build fingerprint. Offline builds reuse a
  configured tree with manifest installation disabled.
- `forge add PORT/VERSION --vcpkg` and `PORT/VERSION#PORT_VERSION` write
  exact overrides. If the workspace has no baseline, the first versioned add
  pins the current Git commit of `VCPKG_ROOT`. Existing baselines are reused,
  and adding from a member records the baseline at the workspace root. Older
  ports may need Git history missing from shallow checkouts. When
  `$VCPKG_ROOT/versions/<letter>-/<port>.json` exists,
  `vcpkg_validate_version` matches `version#port-version` against it before
  editing the manifest and fails with the full version list on a miss; absent
  registry files (fixtures, partial checkouts) skip the check. The 163-test
  Bats suite and ShellCheck passed. A real fmt 12.2.1 vcpkg build passed
  CTest and ran.
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
  libraries enable PIC. New shared libraries use the generated
  `<name>_export.h` API macro for Windows import/export and default symbol
  visibility on GCC/Clang. Older shared libraries retain auto-export.
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
  Workspace members use the root application project's name, even when
  generated from a nested member. Standalone libraries use their own project
  name. The class name matches the library name exactly. The header declares
  the public constructors, assignment operators, and
  virtual destructor. The source defaults each operation in the same
  namespace. The generated C++ class has no sample methods or free helpers.
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

The sanitizer lock fix reads the workspace state directly during Conan lock
validation. Neither sanitizer tests nor `deps status` needs to initialize
sync state first. A real Conan/fmt AddressSanitizer regression verifies
fresh-lock acceptance and genuine stale-lock rejection. The reported `sql`
workspace passed the read-only status and dry-run checks.

The automatic-lock follow-up passed 31 focused Bats tests and ShellCheck.
Real Conan builds cover automatic root and workspace-member locking. Fixtures
cover dry-run, offline locking, current-lock reuse, and preservation of a
previous lock when Conan fails after sync.

The stable-build and preset repair passed all 140 Bats tests and ShellCheck.
Tests verify in-place toolchain refresh, profile locking, editor links,
sanitizer isolation, and a real Conan build combined with a vcpkg SQLite
fixture after reproducing the duplicate preset error. Existing fingerprinted
build trees stay untouched until explicit cleanup.

The build-and-run and library export follow-up passed all 136 Bats tests and
ShellCheck. Tests cover Debug/Release selection, nested workspaces, dry-run,
argument and status forwarding, and shared C and C++ linking and packaging.
Clang cross-compilation for the Windows MSVC target independently confirmed
the generated C++ DLL export and import annotations.

Forge's repository CI installs Conan 2.33.0 in a runner-local virtual
environment and seeds the Debug fmt 12.1.0 fixture. Keep Bats' failure output
enabled in CI so setup failures show the originating Forge diagnostic. The
empty-pipe test reproduces the Ubuntu scaffold failure independently of how a
runner exposes stdin. All 133 local Bats tests, ShellCheck for the changed
shell files, and actionlint passed. Hosted CI still needs a run.

The compilation-database follow-up verified legacy-link migration,
Debug/Release switching, user-owned root database preservation, and clangd's
resolution of fmt after adding the real Conan package to an existing build.

The namespace, installer PATH, and progress follow-up passed all 131 Bats
tests, POSIX installer syntax validation, and ShellCheck. Tests exercise
nested library namespaces, Bash and Zsh startup and uninstall, ANSI-colored
scaffold and installer results, and failed workspace sync.

The installer URL follow-up passed POSIX syntax, ShellCheck, and nine focused
installer and website tests. Tests redirect the official remote to a temporary
Git fixture and cover no-argument direct and streamed installs and both
`--source` modes. The public raw URL returned HTTP 200. The updated script
must be published before the raw URL serves the new behavior.

`install.sh --update` checks `git ls-remote --tags --refs` for a Git source
before staging. It strips a leading `v`, selects the highest numeric tag with
`sort -V`, and compares it with `FORGE_VERSION` read from the installed
`bin/forge`. On a match it prints "Forge is already up to date (vX.Y.Z)." and
exits 0 without touching the checkout; an interactive "Reinstall anyway?
[y/N]" can force it. When a Git source has no numeric tags (as with the public
repository), it compares the installed HEAD with `git ls-remote "$source" HEAD`
instead and reports the installed version. For directory sources it compares
the installable files in the source tree with the installed copy, so an
unchanged local source is reported current while changed files still update.
The staged install records its version in `.git/forge-version`.

The explicit OCI dependency-image follow-up passed actionlint, six workflow
and website checks, and the local Debug/Release packaging integration test.
Hosted Docker and runner execution remain unverified.

The previous full verification on macOS passed the 123-test Bats suite, a separate
Conan/vcpkg preparation regression, ShellCheck, and actionlint. A generated
project linked static C and shared C++ libraries and packaged Debug and
Release outputs. Local CI also locked, installed, and built against cached
Conan fmt. The Docker build and hosted Windows/macOS jobs still need a
GitHub Actions run. The recorded Bashcov result predates this CI follow-up.

- `forge add NAME` with no source prompts interactively (TTY or piped stdin) to
  choose Conan, vcpkg, or GitHub; `--github` runs a wizard for repository URL,
  tag/branch/SHA, and upstream CMake target. All options and examples live in
  `lib/cli-reference.tsv`, so `forge add --help` and Bash/Zsh completion advertise
  them. Non-interactive use must pass `--conan`, `--vcpkg`, `--github`, or
  `--source` (usage error 2 otherwise).
- After a successful add, `add_sync_dependency()` in `lib/commands/add.sh` asks
  `[y/N]` before syncing and, for Conan, refreshing the lock. A decline keeps the
  manifest edit and prints `forge sync --apply --yes` plus `forge deps lock` for
  later; `--yes` skips the prompt. `sync_after_manifest_edit` forces a local
  `FORGE_YES=1` so there is no second confirmation.
- `forge watch` (`cmd_watch` in `lib/commands/run.sh`) builds and runs the
  selected app, then supervises restarts. `lib/watch.py` polls the workspace
  every 250 ms over source, header and build-input files (skipping `.git`,
  `.forge`, `target`), terminates the previous process group on change (SIGKILL
  after 3 s), and returns 130 on Ctrl-C. It re-invokes `forge run --build` with
  the original global flags and forwarded `--` arguments. Dry-run only prints
  the plan; `python3` becomes a runtime requirement.
- Projects scaffold a user-owned `cmake/user.cmake`, included after
  `ProjectOptions.cmake` and `cmake/ProjectOptionsUser.cmake` and before
  diagnostics, version source, CTest, dependencies, workspace, and targets.
  Sync never records, rewrites, or removes it, and `sync_apply` moves a legacy
  root `user.cmake` into it (regular files only, never overwriting a target).
  CMake defaults set in `[cmake.variables]` in `Forge.toml` (ident keys;
  string/number/boolean values) render as literal bracket-quoted `set(...)`
  into the managed `cmake/ProjectOptionsUser.cmake`. For overrides that need
  targets to exist, use `cmake_language(DEFER CALL ...)` in `cmake/user.cmake`;
  toolchain options that must precede `project()` belong in a preset or
  `forge build --toolchain`. See README "Generated CMake layout",
  `docs/ownership.md`, and `docs/index.html`.
- Cargo-style Clang diagnostics live in the managed `cmake/Diagnostics.cmake`
  as `forge_clang_diagnostics()`, called from the root after `cmake/user.cmake`.
  `FORGE_CLANG_DIAGNOSTICS` (default ON via `option()` inside the function, so a
  normal variable from `user.cmake` still wins) guards color, warning names,
  include stacks, template trees, `-Wall -Wextra -Wpedantic`, and
  `-ferror-limit=3`. Root `add_compile_options` is inherited by workspace
  members added later; non-Clang compilers are untouched.
- New projects seed `[cmake.variables]` with `FORGE_CODESIGN_IDENTITY = "adhoc"`,
  `FORGE_CODESIGN_ENTITLEMENTS = "entitlements.plist"`, and `-O0 -g` for both
  C and C++ debug flags. The managed `cmake/CodeSign.cmake` defines
  `forge_codesign_target()`: on macOS it maps `adhoc` to `-`, finds `codesign`,
  and adds a POST_BUILD `codesign --force --sign … --entitlements …` for every
  `[[bin]]` and `SHARED` `[[lib]]` (never tests or static libs). `--force`
  replaces the linker's ad-hoc signature; the root `entitlements.plist` is
  scaffolded once (user-owned, untracked by sync) with
  `com.apple.security.get-task-allow`, which makes `leaks`/LLDB able to attach.
  Empty identity disables signing; a keychain identity can be substituted in
  Forge.toml or `cmake/user.cmake`. Dylibs get signed but macOS does not embed
  entitlements in them.

```bash
cd /Users/amr/Repos/forge
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
6. **Lock staleness is keyed to Conan-relevant manifest data across the graph**. After sync, Conan adds refresh stale locks automatically. Manual Conan edits still support an explicit `forge deps lock`.
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
- `sync`: `sync_prepare` collects the graph, then for each node temporarily swaps `FORGE_ROOT`/`FORGE_MANIFEST_JSON`/`FORGE_MANIFEST_PATH`/`FORGE_STATE_PATH`, renders templates to a temp dir, restores globals. `sync_detect_drift` returns 0 for clean, 1 for drift, 2 for rendering errors, or 6 for missing or invalid state, and fills `FORGE_SYNC_MESSAGES` with `label: message`. `sync_apply` merges per project with per-project proposals/backups.
- Generated root `CMakeLists.txt` orchestrates version resolution, source
  configuration, project options, dependency and workspace loading, target
  declaration, and CTest registration. Each module under `cmake/` defines one
  function. Dependencies are flat modules `cmake/deps/<name>.cmake`, each
  defining `forge_load_dependency()` and included by `cmake/Dependencies.cmake`;
  sync retires legacy `cmake/deps/<name>/CMakeLists.txt` files recorded in state.
  `cmake/ProjectOptionsUser.cmake` is included after `ProjectOptions.cmake` and
  carries bracket-literal `set(...)` lines from `[cmake.variables]`.
  `include(cmake/user.cmake OPTIONAL)` follows it, then `cmake/CodeSign.cmake`
  and `cmake/Diagnostics.cmake`; sync never records `cmake/user.cmake` or
  `entitlements.plist`. Package lookups
  use `GLOBAL` to make imported targets visible to consumers. Workspace targets
  stay in their original build directories. Uppercase dependency aliases use
  hyphen escapes in generated file names so aliases that differ only by case
  also work on macOS.
- Sync inventories per-dependency files using incoming render output and
  recorded state. This lets existing projects migrate via three-way sync.
  New files respect user-owned paths. Removed dependencies back up unmodified
  files and release locally edited files from management. Check dependency
  directory and base paths for symlinks before applying changes.
- Render the Conan recipe from `templates/base/conanfile.txt.tpl` only when the module declares Conan dependencies or the workspace root has reachable Conan requirements. Root recipes aggregate the graph. Sync creates the recipe on first use and retires unused managed recipes, backing up unmodified files and preserving edited ones. A different user-owned recipe triggers a proposal on first use. Conflicting options for the same package or duplicate CMake target names are rejected.
- `compute_fingerprint` includes compiler, generator, arch, profile, Conan profiles, sanitizer, toolchain file. Store the fingerprint in `target/<profile>/.forge-config` and refresh CMake in the stable profile directory when it changes.
- CMake exports the per-build database; successful builds atomically refresh
  `target/compile_commands.json` from normal builds and expose it through the root link for
  clangd. Migrate old Forge-owned direct links automatically. Preserve a
  user-owned root database unless `build --link-compile-commands` is set.
- UI: `ui_help_row LABEL DESCRIPTION LABEL_WIDTH [green|cyan|bold]`; label column padded, descriptions start at a fixed column, no dots.

Optional Conan recipe verification on macOS: all 146 Bats tests passed with a
writable Conan fixture cache, and ShellCheck passed. Regressions cover recipe
creation in a workspace, vcpkg-only projects, and preservation of local edits.

The audit of commit `4739852` covered every public command and subcommand
on macOS. The full 146-test Bats suite passed. That audit found seven
manual findings, including cleanup path validation and sync status errors.
All seven findings now have CLI regression tests. Cleanup verifies the exact
physical path and reports refusal as exit 6. Use disposable projects and
sibling marker files for cleanup tests. Missing or invalid workspace state
fails status commands with exit 6 before they emit a success report.
Conflicting sync modes and competing Git selectors return usage error 2.
Git resolves the exact requested branch or tag and peels annotated tags.
Formatting previews distinguish write mode from check mode and preserve source
files. All 160 Bats tests passed without skips, alongside ShellCheck.
A real Conan fmt and vcpkg zlib build passed CTest and rebuilt offline.
A real vcpkg SQLite verification remains an open blocker.

## 8. How to continue

**Maintenance rule:** after finishing any task in this repository, update this
`SKILL.md` before reporting completion — record the new state, decisions,
user preferences, gotchas and verification results so the next session resumes
with accurate context. Do this even for small fixes.

1. Review recent `git log` entries and the test suites for prior CLI audits,
   reproducible failures, and likely causes.
2. Before editing, run the verification commands in §4 to establish a baseline.
3. For help/completion changes edit `lib/cli-reference.tsv` and `lib/cli-reference.sh`; for dependency changes edit `lib/conan.sh`, `lib/cmake.sh`, `lib/schema.jq`; for workspace behavior edit `lib/workspace.sh`, `lib/sync.sh`, `lib/commands/generate.sh`.
4. Always write tests for new code and behavior, including bug fixes.
   Verify observable results through the normal entry points. Keep existing
   tests strong and fix the code when they expose a defect.
5. Keep docs in `docs/` aligned with `--help`.
6. Do not recreate `progress.md` or the original plan unless the user asks.
