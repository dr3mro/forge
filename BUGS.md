# Forge CLI audit

Tested commit `4739852` on macOS arm64 with Bash 5.3, real CMake/Ninja, Conan 2 with cached fmt, a local Git repository, and disposable Forge projects. The issue steps assume `forge` resolves to the audited checkout. Run them in temporary projects, especially the `clean` cases.

## 1. High · `clean` can delete files outside the project

In a fresh project, make `target/` a symlink to a sibling directory containing a `debug/` directory and a marker file. Run `forge clean --profile debug`.

**Observed.** Forge exits 0 and removes the sibling's `debug/` directory and its marker. It should refuse a symlinked `target/` and preserve the external files.

**Cause.** [`_clean_safe_dir`](lib/commands/clean.sh#L5) checks whether the final profile directory is a symlink. It then resolves both the profile directory and `target/`, so a symlinked parent makes the external directory the trusted deletion root.

## 2. Medium · `clean` exits 0 after refusing a path

In a fresh project with a real `target/`, make `target/debug` a symlink to a sibling directory. Run `forge clean --profile debug`.

**Observed.** Forge prints `error: refusing unsafe path` and preserves the directory, but exits 0. A script sees cleanup as successful.

**Cause.** [The cleanup loop](lib/commands/clean.sh#L55) logs a refusal and continues without recording an error status. The active-build refusal uses the same pattern.

## 3. Medium · An empty cleanup profile selects the default

Build the default Debug profile, then run `forge clean --profile= --dry-run`.

**Observed.** Forge accepts the command instead of returning usage error 2. It previews deletion of the default build. With no `--dry-run`, that default is eligible for deletion. The space-separated form with a missing value rejects the input.

**Cause.** [The equals-form parser](lib/commands/clean.sh#L21) accepts an empty string. The selection logic treats an empty profile as though the option was omitted.

## 4. Medium · Four commands mishandle a missing workspace member's sync state

Run `forge new probe --defaults`, enter the project, and run `forge generate bin worker`. Move `bins/worker/.forge/state.json` aside temporarily. Run `forge sync --check`, `forge sync --diff`, `forge metadata`, and `forge deps status --format json`.

**Observed.** All four exit 0 after a missing-state diagnostic. `sync --check` prints `in sync`, `sync --diff` prints an empty preview, and both JSON commands emit `"manifest_sync": "clean"`. Automation should be able to distinguish an unverifiable workspace from a clean one.

**Cause.** [`sync_prepare`](lib/sync.sh#L63) returns 6 for a member with missing state. [The check and diff handlers](lib/commands/sync.sh#L20) recognize render error 2 and miss 6. [Metadata](lib/commands/format.sh#L89) and [dependency status](lib/deps.sh#L150) default to clean and only update that field for drift status 1.

## 5. Medium · `deps pin` silently ignores competing selectors

Add a dependency from a local Git repository with a tag named `v1` and a branch named `audit-branch`. Run `forge deps pin git_dep --tag v1 --branch audit-branch --dry-run`.

**Observed.** Forge exits 0 and selects the tag. The documented syntax calls for one selector. Without `--dry-run`, the selected SHA is written to the manifest.

**Cause.** [The selector check](lib/deps.sh#L93) compares the tag and branch strings for inequality. Two different names pass that check, and the subsequent expansion prefers the tag. The SHA branch also runs before tag or branch validation.

## 6. Low · `fmt --dry-run` describes the wrong mode

Run `forge fmt --dry-run` in a fresh application. Compare with `forge fmt --check --dry-run`.

**Observed.** Both say `would check format`. The first command previews the mode that rewrites source files.

**Cause.** [The preview](lib/commands/format.sh#L45) uses `${check:+check }`. Both `0` and `1` are nonempty strings in Bash.

## 7. Medium · Conflicting sync modes can turn a check into an apply

Run `forge sync --check --apply --yes` in a temporary project. Forge accepts both modes and enters the apply path. The command should reject conflicting modes with usage error 2 so an appended argument cannot silently change a check into a write.

**Cause.** [The sync parser](lib/commands/sync.sh#L5) overwrites the mode with each flag. The last flag wins.

## Coverage and limits

- Checked contextual help for all 25 catalog entries. Exercised version, doctor, application and standalone-library scaffolding, C and C++ library generation, child binary generation, explicit Debug and Release builds, root and member runs, CTest filters and repeats, AddressSanitizer, formatting, metadata, Doxygen, and cleanup.
- Added, built, ran, and tested a project with Conan fmt, a local Git dependency, and a local path dependency together. Exercised Conan locking, Git tag pinning, sync check/diff/apply, dependency status, removal of all four dependency types, and detachment of a workspace library.
- A real build linked Conan fmt and vcpkg zlib together, passed CTest, and rebuilt offline. The vcpkg SQLite shortcut succeeded. The real vcpkg build reached the port installer, where the SQLite source download failed in this environment. The vcpkg fixture in the integration suite exercises the toolchain and manifest path without that download.
- All 146 existing Bats tests passed with no skips, and ShellCheck passed. The suite also exercises workflow generation and local CI helpers, installation, update, uninstall, and Bash/Zsh completion using temporary installations. Hosted CI, Windows/Linux execution, and a network install from GitHub were outside this local run.

## Why the suite passed

| Findings | What existing tests covered | Regression to add |
| --- | --- | --- |
| 1–2 · Cleanup symlinks | The integration test put a symlink below a real `target/` and checked the warning and survival of its destination. | Test a symlinked `target/` separately. For both cases, assert a nonzero exit and verify that an external marker survives. |
| 3 · Empty profile | Cleanup tests used valid profile names. | Pass `--profile=` with an existing default build. Assert exit 2 and verify that the build survives. |
| 4 · Missing member state | Sync tests covered a clean project and ordinary manifest drift. | Remove a member's state file and assert failure for check, diff, metadata, and dependency status. Verify that each avoids reporting a clean workspace. |
| 5 and 7 · Competing selectors | Tests covered individual Git selectors and sync modes. | Pass conflicting selectors and modes. Assert exit 2 and verify that neither the manifest nor generated files change. |
| 6 · Format preview | Format tests checked that `--check` preserves source files and that write mode formats them. | Compare both dry-run messages and verify that neither invocation changes the source. |

The seven findings were reproduced manually while all 146 existing tests passed.
All seven audit findings are fixed and have Bats regression coverage. The
regressions assert exit codes, output, and file preservation where applicable.
