# Forge autonomous loop — progress

## Operating rules (this session)

0. Team roles (all from `dev/`): **Context Optimizer** targets retrieval before searches; **Architect** produces the dependency-ordered plan and diff review for multi-file changes; **Product Owner** frames the story, acceptance criteria, priority and scope; **Scrum Master** owns the WIP-limited sprint queue, DoD and evidence-based status; **AGENT2** supplies the C++ need; **AGENT1** implements in Bash per `PROJECT.md`; **UI/UX** reviews help, errors and progress against alignment/color/no-color contracts; **DevSecOps** gates untrusted input, paths, injection and exit/JSON contracts; **QA.md** drives testing and bug hunting; **Debugger** does evidence-based root cause on failures; **Memory Manager** keeps `PROJECT.md` and trackers accurate at handoff. Trackers are updated openly each iteration, never silently. Product-changing scope decisions and changes to established help/color conventions are flagged for maintainer approval rather than assumed. Delegation is only claimed when the runtime actually supports it; otherwise the architect adopts each review checklist directly.
1. Each iteration: C++ need (AGENT2) → PO story + acceptance criteria → SM sprint/DoD → implement with Bash (AGENT1, per `PROJECT.md`) → QA test/bug hunt (QA.md) → update `TODO.md`, `BUGS.md`, `PROGRESS.md` → **commit with a message describing what was done in this task** → save state to `PROJECT.md` → loop again.
2. **Test cadence (user instruction, 2026-11-18 08:00):** operate in **autopilot with no prompts**, looping continuously. Do several batches of bug finding, improvements, fixes and new features between test runs — run tests **every few batches**, not after every edit. Record which tests failed in the `TODO.md` test-failure backlog for later handling. Cheap `bash -n`/ShellCheck on changed files may still happen per edit. (This supersedes the earlier 60-minute cadence; the 08:55 timer was cancelled.)
3. Never claim a test result that was not actually observed. Record blockers and limits honestly.
4. Baseline established 2026-11-18: ShellCheck clean, 191/191 Bats tests green, clean `git status`.
5. Verification commands (for the next window): `shellcheck -x -S warning bin/forge install.sh uninstall.sh lib/*.sh lib/commands/*.sh tests/run.sh tests/fakebin/*` and `bash tests/run.sh` with `/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin` first on PATH.
6. **Commit rule restored (user instruction, 2026-11-18 07:59):** commit with a descriptive message after each task/batch, then push; the earlier pause is lifted.
7. **Autopilot (user instruction, 2026-11-18 08:00):** no interactive confirmations; continue the loop (find bugs → improve → fix → new features → batch tests → commit → repeat) without asking.
8. Verification ledger (2026-11-18): baseline 191/191 green; commit `a9f36d2` pushed. Final batched verification after batches 2–4 and BUG-004: `shellcheck_exit=0`, `1..201`, `bats_exit=0` — **201/201 green, locally verified**. One intermediate failure (website catalog test 149, missing `--cppstd` example in `docs/index.html`) was fixed; focused website tests then passed and the full suite was re-run clean. Hosted CI and Linux remain unverified.

## Iteration log

### Iteration 0 — baseline (complete)
- Read all four role files and the full `PROJECT.md`; inspected `README.md`, command catalog, and command implementations.
- Baseline verification: ShellCheck clean; `bash tests/run.sh` → 191/191 pass.
- No code changes.

### Iteration 1 — sanitized build and run for C++ debugging (in progress)
- **C++ need (AGENT2):** Sanitizer instrumentation is reachable only through `forge test --sanitize`. A debugger working on a memory bug cannot get an ASan-instrumented *application* from Forge.
- **PO story (priority: High; impact high, risk low, effort small):** *As a C++ application developer chasing a memory bug, I want to build and run my application under a sanitizer, so that I can reproduce the failure under LLDB without running the test suite.* In scope: `build`, `run`, `watch` accept `--sanitize NAME`; isolated tree preserved; docs/catalog aligned. Out of scope: new sanitizer types, changing manifest schema, C-flag instrumentation (backlog idea).
- **PO acceptance criteria:**
  1. `forge build --sanitize NAME` configures/compiles into `target/sanitizers/<canonical>/<profile>` and leaves `target/<profile>` untouched.
  2. `forge run --sanitize NAME` launches the instrumented executable; `run --build --sanitize NAME` compiles then launches; arguments after `--` still pass through.
  3. Aliases normalize to canonical names; unknown/empty values exit 2 with a clear message; `test --sanitize` behavior is unchanged.
  4. Missing sanitized build reports a repair hint that names the sanitizer; `watch --sanitize` dry-run states the sanitizer.
  5. Help, CLI catalog, website, README and `docs/commands.md` advertise the new flags; Bats and ShellCheck pass.
- **SM sprint queue (WIP 1):** (a) shared sanitizer helper + `build`/`run`/`watch` flags → (b) catalog/docs → (c) regression tests → (d) QA probe + fix findings → (e) full verification → (f) commit → (g) memory update. DoD = all acceptance criteria observed through the CLI, full suite green, ShellCheck clean, commit present, trackers current.
- **UI/UX review:** new flags are catalog-only additions, so the two-column grid and color contract are untouched. Two message defects were flagged by QA and reviewed: the missing-build hint named a command that builds the *wrong* tree, and the `watch --sanitize` dry-run plan omitted the sanitizer. Both are objective, low-severity UX defects (clear recovery command / accurate preview); minimal text-only fixes approved by the role's "smallest coherent improvement" rule, no new prompts or styling changes.
- **DevSecOps gate:** no new trust boundary. `forge_enable_sanitizer` accepts only the fixed allowlist (address/asan, undefined/ubsan, leak/lsan, thread/tsan), so the value used in the `target/sanitizers/NAME/<profile>` path and in `-DCMAKE_*_FLAGS` is never attacker-controlled text; empty/flag-like/unknown values exit 2. No `eval`, no new secrets, no change to JSON/exit contracts, no writes outside the validated build tree. ShellCheck + adversarial CLI tests are the evidence gates.
- **Status (updated 07:55):** (a)–(d) complete — helper, flags, docs, regression tests, QA reproduction of both UX defects and their minimal fixes are implemented. (e) verification is **deferred to the 08:55 test window** under the new cadence rule; no post-fix test has been run yet. (f) commit paused by user instruction. (g) memory update pending handoff.
- **Verification evidence so far:** baseline 191/191 green before changes; pre-fix reproduction returned `not ok 1`/`not ok 2` for BUG-001/002. Final verification: `shellcheck_exit=0`, `1..201`, `bats_exit=0` (201/201). BUG-004 (infinite loop on `--sanitize` without a value) was found when the suite hung at test 98, fixed in `build.sh` and `run.sh`, and guarded with a `timeout 10` assertion. Website test 149 failed once because the new `--cppstd` example was absent from `docs/index.html`; fixed and re-verified.

### Batches 2–4 — follow-up work (complete, verified)

- **Batch 2:** `forge_enable_sanitizer` now also sets `CMAKE_C_FLAGS` and `CMAKE_SHARED_LINKER_FLAGS`; mixed C/C++ workspaces get full instrumentation. Regression tests cover helper flags and a real C-source sanitizer build.
- **Batch 3:** `new`/`init` accept `--cppstd 17|20|23` (default 20), written to `Forge.toml`; catalog, website, README and `docs/commands.md` aligned.
- **Batch 4:** BUG-003 fixed — missing sanitized executable error names the sanitizer and gives a valid repair command.
- **BUG-004:** missing `--sanitize` operand no longer hangs `build`/`run`/`watch`; exits 2.
- **Config:** `opencode.json` now auto-allows all actions (including `.env` reads) and all eight agents have `shell: allow`; verified with `opencode debug config` and `opencode debug agents`. Specialist `edit: deny` is preserved.
- **Commit/push:** `47a6144` pushed before the next task started.

### Next task — generated members inherit root C++ standard (complete, verified)

- Confirmed BUG-005 with a disposable probe: root `cppstd=17` produced `libs/widget/Forge.toml` with `cppstd=20`.
- Added `workspace_application_cppstd()` in `lib/commands/generate.sh`, mirroring the namespace helper, with a safe default of 20 for older manifests.
- Added regression test in `tests/unit/04_project.bats` and a note in `docs/commands.md`.
- Verification: `shellcheck_exit=0`, `1..202`, `bats_exit=0` — 202/202 green locally. Committed and pushed as `8fec0ef`.

### Next task — per-member `--cppstd` override for generate (complete, verified)

- Added `--cppstd 17|20|23` to `generate lib|bin`; explicit value overrides the inherited root standard. `generate class` rejects it. Invalid values exit 2 before any files are written.
- Catalog, website and `docs/commands.md` aligned; regression test added in `tests/unit/04_project.bats`.
- QA reliability probe: 52 missing-operand CLI invocations across all flags, zero hangs (BUG-004 pattern confirmed isolated).
- Verification: `shellcheck_exit=0`, `1..203`, `bats_exit=0` — 203/203 green locally. Committed and pushed as `53b9ab5`.

### Next task — cross-standard workspace regression guard (complete, verified)

- Hypothesis: a member's `forge_project_options()` (`PARENT_SCOPE`) might override the root C++ standard for root targets. Disproved empirically: root 17 / member 23 produced `-std=c++17` for root sources and `-std=c++23` for member sources. The workspace helper's function scope confines the parent-scope write.
- Added an integration test in `tests/integration/01_build.bats` asserting both standards in `compile_commands.json`, so the new per-member override cannot silently regress.
- Verification: `shellcheck_exit=0`, `1..204`, `bats_exit=0` — 204/204 green locally. Committed and pushed as `d1c7d3a`.

### Next task — getting-started discoverability (complete, docs-only)

- Added `--cppstd` to the create section, sanitizer build/run/test examples to the build section, and member standard inheritance/override to the workspace paragraph in `docs/getting-started.md`.
- Verified the website/install consistency tests (2/2) since they check `docs/getting-started.md` alongside README and the website. No code changes.

### Next task — `forge test --list` (complete, verified)

- Added `--list` to `cmd_test`: runs `ctest -N` against the resolved profile/sanitizer build directory, honors `FILTER`, and does not execute tests. Dry-run reports the listing plan. Existing "not built" error behavior is unchanged.
- Catalog, website, `docs/commands.md` and `docs/getting-started.md` aligned; unit and integration regression tests added.
- Verification: `shellcheck_exit=0`, `1..205`, `bats_exit=0` — 205/205 green locally. Committed and pushed as `9322a27`.

### Next task — watch --sanitize integration guard (complete, verified)

- QA probe confirmed `forge watch --sanitize address` rebuilds and restarts inside `target/sanitizers/address/debug` after a source edit, and exits 130 on Ctrl-C.
- Added an integration regression test in `tests/integration/01_build.bats` covering first run, source-triggered restart, sanitizer build path and interrupt status. No product code change needed.
- Verification: `shellcheck_exit=0`, `1..206`, `bats_exit=0` — 206/206 green locally. Committed and pushed as `7ec5446`.

### Next task — clean leaves dangling compilation database links (complete, verified)

- QA probe found `target/compile_commands.json` and the root link dangling after `clean --all`, while an unrelated `target/user-notes.txt` was correctly preserved.
- Added `prune_compile_commands_links()` in `lib/cmake.sh` and called it after successful deletions in `cmd_clean`. It only removes Forge-patterned symlinks resolving under `target/` that no longer exist.
- Extended the profile-clean test and added a `clean --all` test asserting both links are gone and user files survive (BUG-006).
- Verification: `shellcheck_exit=0`, `1..207`, `bats_exit=0` — 207/207 green locally. Committed and pushed as `cebcfec`.

### Next task — profile-aware test repair hint (complete, verified)

- BUG-007: `forge test --release` before a release build suggested `forge build` (debug). It now suggests `forge build --release`; regression test added in `tests/unit/07_devtools.bats`.
- Verification: `shellcheck_exit=0`, `1..208`, `bats_exit=0` — 208/208 green locally. Commit/push pending.
