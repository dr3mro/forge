# 0005 — Tool minimums

Status: **resolved** (Phase 0)

## Decision
All minimums/pins live in `tools.versions` at the repository root and are the
single machine-checked source for `forge doctor` and CI:

| Tool | Minimum |
| --- | --- |
| Bash | 4.0 (3.2 rejected at startup with Homebrew guidance) |
| CMake | 3.25 |
| Conan | 2.x (major) |
| Git | 2.0 |
| jq | 1.6 |
| Python (tomllib) | 3.11 |
| ShellCheck | 0.8 |
| Ninja | 1.10 |
| Bats | 1.5 |

Observed local versions (macOS, Phase 0): Bash 5.3 (Homebrew), CMake 4.4.4,
Conan 2.33, Git 2.54, jq 1.7.1, Python 3.15, ShellCheck 0.11, Ninja 1.13,
Bats 1.14. All pass `forge doctor`.
