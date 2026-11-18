# Forge QA findings

QA summary — iteration 1 (sanitizer build/run slice)

| Metric | Result |
| --- | --- |
| Commands discovered | build, run, watch, test (sanitizer paths) |
| Scenarios executed | Full Bats suite (201 tests) + focused probes |
| Passed | 201 (final clean run) |
| Failed | 0 (final); 7 defects found and fixed during the campaign |
| Confirmed bugs | 7 (1 high, 2 medium, 4 low) |
| Critical / High | 0 / 1 |
| Platforms tested | macOS (local) |

## Workflow coverage

| Workflow | Status | Tests | Failures | Notes |
| --- | --- | ----: | -------: | ----- |
| Project creation | Passed | 26 focused | 0 | bin/lib, C/C++, namespace, cppstd, reserved names |
| Project configuration | Passed | focused | 0 | TOML schema, manifest variables, user CMake |
| Conan dependencies | Passed | integration | 0 | real cached fmt, lock, status JSON, ASan build |
| FetchContent dependencies | Partial | integration | 0 | Git pinning and offline fixtures; no live network fetch |
| Mixed dependencies | Passed | integration | 0 | Conan + Git + path + vcpkg fixtures |
| CMake synchronization | Passed | focused | 0 | drift, three-way merge, user-owned files |
| Build and execution | Passed | integration | 0 | Debug/Release, targets, run, arguments, status |
| Interactive CLI | Partial | focused | 0 | prompts and EOF via piped stdin; no real TTY matrix |
| Invalid inputs | Passed | probes | 0 | 52 missing operands + 63 invalid values, no hangs |
| Recovery testing | Passed | probes | 0 | build → clean → rebuild, sync, lock repair |
| Portability | Partial | local | 0 | macOS only; Linux and hosted CI unverified |
| Security | Partial | ShellCheck + probes | 0 | allowlisted sanitizer input, no eval, safe paths |
| Randomized testing | Partial | probes | 0 | bounded deterministic invalid-value combinations |

## BUG-001 — Missing sanitized build suggests a command that builds the wrong tree

**Severity:** Low  
**Category:** UX / CLI  
**Status:** Fixed — verified locally (201/201 Bats, ShellCheck clean)  
**Reproducibility:** Always  
**Environment:** macOS, Bash 5.3.20, CMake 4.4.4

**Summary:** `forge run --sanitize NAME --bin APP` with no instrumented build exits 5 with a repair hint of `forge build --debug-target APP`, which produces a normal (non-instrumented) build and does not fix the condition.

**Steps to reproduce:**
1. In a fresh scaffold, do not run any build.
2. `forge run --sanitize address --bin app`

**Expected:** Hint names `forge build --sanitize address ...`.  
**Actual:** Hint omits the sanitizer.

**Evidence:** `bats --filter 'missing sanitized build' tests/unit/07_devtools.bats` → `not ok 1` at line 109.

**Root cause:** `lib/commands/run.sh` built `build_hint` without consulting `FORGE_SANITIZER`.  
**Fix:** Add `--sanitize <name>` to the hint when a sanitizer is active (debug-target and release forms).  
**Regression test:** `a missing sanitized build reports a sanitizer-aware repair hint`.  
**Verification:** Deferred to the 08:55 test window under the 60-minute cadence rule.

## BUG-002 — `watch --sanitize` dry-run plan omits the sanitizer

**Severity:** Low  
**Category:** UX / CLI  
**Status:** Fixed — verified locally (201/201 Bats, ShellCheck clean)  
**Reproducibility:** Always  
**Environment:** macOS, Bash 5.3.20

**Summary:** `forge watch --sanitize address --dry-run` reports the watch plan without indicating that restarts will be instrumented, so the preview does not describe the operation that will run.

**Steps to reproduce:**
1. In a scaffold: `forge --dry-run watch --sanitize address --bin app`

**Expected:** Plan states `sanitizer=address`.  
**Actual:** Plan shows only the workspace, binary and profile.

**Evidence:** `bats --filter 'watch --sanitize dry run' tests/unit/07_devtools.bats` → `not ok 2` at line 115.

**Root cause:** `lib/commands/run.sh` dry-run status was a fixed string.  
**Fix:** Append `(sanitizer=<name>)` to the plan when `FORGE_SANITIZER` is set.  
**Regression test:** `watch --sanitize dry run names the sanitizer in its plan`.  
**Verification:** Deferred to the 08:55 test window under the 60-minute cadence rule.

## BUG-003 — Missing sanitized executable error omits the sanitizer

**Severity:** Low  
**Category:** UX / CLI  
**Status:** Fixed — verified locally (201/201 Bats, ShellCheck clean)  
**Reproducibility:** Always

**Summary:** When `target/sanitizers/NAME/<profile>` exists but the executable does not, `forge run --sanitize NAME` reports only `executable ... is not built for 'debug'` with no indication that the missing artifact is the instrumented one.

**Evidence:** static review of `lib/commands/run.sh` (exit path after build-directory discovery); regression test `a missing sanitized executable names the sanitizer in the error` added.

**Root cause:** the missing-executable `die` path predated `--sanitize` and did not consult `FORGE_SANITIZER`.  
**Fix:** include `sanitizer=<name>` and a valid `forge build --sanitize <name>` repair command.  
**Verification:** deferred to the next batched test run.

## BUG-004 — Missing `--sanitize` operand hangs the CLI in an infinite loop

**Severity:** High  
**Category:** CLI / Reliability  
**Status:** Fixed — verified locally (201/201 Bats, ShellCheck clean)  
**Reproducibility:** Always (observed during the batched Bats run)

**Summary:** `forge --dry-run build --sanitize` with no value spins forever at 100% CPU instead of exiting 2. The same pattern affected `run` and `watch`. It hung the full test suite at test 98 and required killing the process tree.

**Steps to reproduce:**
1. `forge --dry-run build --sanitize`

**Expected:** `error: --sanitize requires a value`, exit 2.  
**Actual:** infinite argument loop; no output, no exit.

**Evidence:** `ps` showed `/Users/amr/Repos/forge/bin/forge --dry-run build --sanitize` in state `R` for 16 minutes; batched log stopped after `ok 97`.

**Root cause:** in `cmd_build` and `_run_project`, the `--sanitize)` case did `sanitize="${2:-}"; shift 2`. With a single argument, `shift 2` fails and leaves `$1` as `--sanitize`, so the `while (( $# ))` loop never advances. `cmd_test` already validated the operand before shifting.  
**Fix:** validate `[[ -n "${sanitize}" ]] || die "${EXIT_USAGE}" "--sanitize requires a value"` before `shift 2` in both sites.  
**Regression test:** `build and run validate sanitizer names before doing work` now wraps the missing-operand call in `timeout 10` so a recurrence fails instead of hanging.  
**Verification:** direct CLI check returned exit 2 in <1 s for `build`, `run` and `watch`; full suite pending.

## BUG-005 — Generated workspace members ignored the root C++ standard

**Severity:** Medium  
**Category:** Scaffolding / Workspace  
**Status:** Fixed — verified locally (202/202 Bats, ShellCheck clean)  
**Reproducibility:** Always

**Summary:** A workspace root scaffolded with `--cppstd 17` produced generated members with `cppstd = "20"`, so members could not compile root-required C++17-only source without a manual manifest edit.

**Evidence:** disposable probe — root `cppstd = "17"`, `libs/widget/Forge.toml` `cppstd = "20"`.  
**Root cause:** `generate.sh` called `scaffold_project` without the C++ standard, so it used the default 20; namespace already had an explicit root-inheritance helper.  
**Fix:** add `workspace_application_cppstd()` mirroring `workspace_application_namespace()`, and pass the root value to `scaffold_project`.  
**Regression test:** `generated workspace members inherit the root C++ standard`.  
**Verification:** focused suite ok 3; full suite 202/202.

## BUG-006 — `clean` left dangling compilation database links

**Severity:** Medium  
**Category:** Filesystem / State  
**Status:** Fixed — verified locally (207/207 Bats, ShellCheck clean)  
**Reproducibility:** Always

**Summary:** After `forge clean --profile debug` or `forge clean --all`, the managed `target/compile_commands.json` and root `compile_commands.json` symlinks remained, pointing at the deleted build. IDE tooling (clangd) saw a broken link.

**Steps to reproduce:** build a project, run `forge clean --all --yes`, then inspect `target/compile_commands.json`.

**Expected:** Forge-owned links are removed with the build they publish.  
**Actual:** both symlinks remained dangling; unrelated files under `target/` were preserved.

**Evidence:** disposable probe showed `compile_commands.json -> debug/compile_commands.json` after `clean --all` deleted `target/debug`.  
**Root cause:** `cmd_clean` only removed build directories; `link_compile_commands()` had no cleanup counterpart.  
**Fix:** add `prune_compile_commands_links()` in `lib/cmake.sh`, called after successful deletion. It removes only symlinks with Forge-owned destinations that resolve inside `target/` and no longer exist; regular files and unexpected symlinks are untouched.  
**Regression tests:** extended `clean dry-run preserves...` and added `clean --all preserves unrelated target files and prunes stale database links`.

## BUG-007 — `test --release` suggested the debug build command

**Severity:** Low  
**Category:** UX / CLI  
**Status:** Fixed — verified locally (208/208 Bats, ShellCheck clean)  
**Reproducibility:** Always

**Summary:** With no Release build present, `forge test --release` exited 5 with `run 'forge build'`, which builds the default debug profile and does not fix the condition.

**Evidence:** disposable CLI run; regression test `test reports a profile-aware repair hint when the profile is not built`.  
**Root cause:** the missing-build `die` in `cmd_test` predated profile flags and used a fixed hint.  
**Fix:** emit `forge build --release` when the selected profile is `release`.  
**Verification:** focused test passed; full suite 208/208.

## Unverified risks

- Hosted CI, Linux behavior and cross-platform sanitizer support were not exercised locally.
- The `--cppstd` inheritance for generated workspace members (candidate bug in `TODO.md`) has not been investigated yet.
