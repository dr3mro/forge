# Forge autonomous loop — progress

## Operating rules (this session)

0. Team roles (all from `dev/`): **Context Optimizer** targets retrieval before searches; **Architect** produces the dependency-ordered plan and diff review for multi-file changes; **Product Owner** frames the story, acceptance criteria, priority and scope; **Scrum Master** owns the WIP-limited sprint queue, DoD and evidence-based status; **AGENT2** supplies the C++ need; **AGENT1** implements in Bash per `PROJECT.md`; **UI/UX** reviews help, errors and progress against alignment/color/no-color contracts; **DevSecOps** gates untrusted input, paths, injection and exit/JSON contracts; **QA.md** drives testing and bug hunting; **Debugger** does evidence-based root cause on failures; **Memory Manager** keeps `PROJECT.md` and trackers accurate at handoff. Trackers are updated openly each iteration, never silently. Product-changing scope decisions and changes to established help/color conventions are flagged for maintainer approval rather than assumed. Delegation is only claimed when the runtime actually supports it; otherwise the architect adopts each review checklist directly.
1. Each iteration: C++ need (AGENT2) → PO story + acceptance criteria → SM sprint/DoD → implement with Bash (AGENT1, per `PROJECT.md`) → QA test/bug hunt (QA.md) → update `TODO.md`, `BUGS.md`, `PROGRESS.md` → **commit with a message describing what was done in this task** → save state to `PROJECT.md` → loop again.
2. **Test cadence (user instruction, 2026-11-18 07:55):** run tests **at least 60 minutes apart, one test run per window**. Use the interval for planning and implementation. After each window, note which tests failed and add them to the `TODO.md` test-failure backlog for later handling. Do not re-run a suite after every small edit. Cheap `bash -n`/ShellCheck on changed files may still happen per edit.
3. Never claim a test result that was not actually observed. Record blockers and limits honestly.
4. Baseline established 2026-11-18: ShellCheck clean, 191/191 Bats tests green, clean `git status`.
5. Verification commands (for the next window): `shellcheck -x -S warning bin/forge install.sh uninstall.sh lib/*.sh lib/commands/*.sh tests/run.sh tests/fakebin/*` and `bash tests/run.sh` with `/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin` first on PATH.
6. Commit rule from item 1 is **paused** for iteration 1 by user instruction ("Do not commit"); no commit until explicitly requested.
7. **Unattended mode (user instruction, 2026-11-18 07:58):** no interactive confirmations; proceed automatically with planning, implementation and verification. The 60-minute test cadence still applies. Commits remain paused until explicitly requested (AGENTS.md rule).
8. Test schedule: last completed test = two-test defect reproduction (both failed, pre-fix). Next test window opens **2026-11-18 08:55** local; the batched verification is scheduled to start automatically then. No tests to be run before then. Failures are recorded in the `TODO.md` test-failure backlog.

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
- **Verification evidence so far:** baseline 191/191 green before changes; pre-fix reproduction of the two new regression tests returned `not ok 1` (missing sanitizer-aware repair hint) and `not ok 2` (watch dry-run omitted sanitizer). Post-fix behavior is **unverified** and must not be claimed as passing.
