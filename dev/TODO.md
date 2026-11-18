# Forge loop — ideas backlog

Ideas discovered while working the loop. Promoted into an iteration when they become a concrete user story.

## Test-failure backlog (populated after each 60-minute test window)

- _2026-11-18: resolved. One failure was observed mid-campaign (website catalog test 149: missing `--cppstd 23` example in `docs/index.html`); fixed and full suite re-run at 201/201 with ShellCheck clean. No open test failures._
- ~~**Candidate bug:** generated workspace members ignored root `cppstd`.~~ Confirmed by probe, fixed with `workspace_application_cppstd()` and regression test (BUG-005).
- ~~**Per-member `--cppstd` override**~~ Implemented for `generate lib|bin`; members inherit root by default and accept an explicit override.

## Candidate ideas (not yet scheduled)

- ~~**Sanitizer flags for C sources.**~~ Implemented in batch 2: `forge_enable_sanitizer` now also sets `CMAKE_C_FLAGS` and `CMAKE_SHARED_LINKER_FLAGS`; regression tests added. Awaiting batch test run.
- **Forward test-binary arguments from `forge test`.** CTest's `-R` filter covers test names, but C++ devs also need gtest/Catch2-specific flags (e.g. `--gtest_repeat`, Catch2 tags) passed to the test executable. Needs a manifest or CLI contract decision before implementing.
- **`--cppstd 17|20|23` on `new`/`init`.** `package.cppstd` is required but can only be set after scaffolding by editing `Forge.toml`. A scaffold-time flag would align with the existing metadata flags.
- **Hosted CI run.** Multiple `PROJECT.md` entries note that hosted GitHub Actions (Docker/Windows/macOS jobs) still need a real run. Not fixable locally; track as an environment blocker, not a code task.
