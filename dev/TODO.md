# Forge loop — ideas backlog

Ideas discovered while working the loop. Promoted into an iteration when they become a concrete user story.

## Test-failure backlog (populated after each 60-minute test window)

- _No test run has completed under the new cadence rule yet. Next window: 2026-11-18 08:55 local._

## Candidate ideas (not yet scheduled)

- **Sanitizer flags for C sources.** `_sanitizer_flags` is only applied through `CMAKE_CXX_FLAGS`/`CMAKE_EXE_LINKER_FLAGS`. Mixed C/C++ workspaces therefore build C objects without instrumentation, so ASan can miss bugs in C libraries. Add `CMAKE_C_FLAGS` (and consider shared-library linker flags) when a sanitizer is enabled. Found during iteration 1 discovery.
- **Forward test-binary arguments from `forge test`.** CTest's `-R` filter covers test names, but C++ devs also need gtest/Catch2-specific flags (e.g. `--gtest_repeat`, Catch2 tags) passed to the test executable. Needs a manifest or CLI contract decision before implementing.
- **`--cppstd 17|20|23` on `new`/`init`.** `package.cppstd` is required but can only be set after scaffolding by editing `Forge.toml`. A scaffold-time flag would align with the existing metadata flags.
- **Hosted CI run.** Multiple `PROJECT.md` entries note that hosted GitHub Actions (Docker/Windows/macOS jobs) still need a real run. Not fixable locally; track as an environment blocker, not a code task.
