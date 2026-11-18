# Forge QA findings

QA summary — iteration 1 (sanitizer build/run slice)

| Metric | Result |
| --- | --- |
| Commands discovered | build, run, watch, test (sanitizer paths) |
| Scenarios executed | 2 regression tests + smoke builds (pre-fix) |
| Passed | 0 (both regression tests failed as intended before the fix) |
| Failed | 2 |
| Confirmed bugs | 2 (low severity, UX) |
| Critical / High | 0 / 0 |
| Platforms tested | macOS (local) |

## BUG-001 — Missing sanitized build suggests a command that builds the wrong tree

**Severity:** Low  
**Category:** UX / CLI  
**Status:** Fixed — verification pending  
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
**Status:** Fixed — verification pending  
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

## Unverified risks

- No post-fix test run has completed; both fixes are implemented but unconfirmed.
- Hosted CI, Linux behavior and cross-platform sanitizer support were not exercised locally.
