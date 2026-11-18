# Forge OpenCode working rules

- Start with `git status --short`; preserve existing user changes.
- Source of truth is current repository code and tests, not stale project memory.
- Forge is Bash 4+ on macOS/Linux; CMake owns builds; Forge.toml declares intent; Conan 2, vcpkg and pinned Git/path dependencies are explicit.
- Never use `eval` for untrusted input. Use Bash arrays for command arguments. Do not silently overwrite user-owned files.
- Keep exit codes 0/1/2/3/4/5/6 and machine-readable stdout contracts stable.
- `lib/cli-reference.tsv` drives help/completion; preserve aligned two-column help, semantic colors, NO_COLOR and non-TTY behavior.
- `conanfile.txt`, not conanfile.py.
- Search relevant symbols and inspect bounded ranges before loading whole files.
- Use focused tests first; run broader Bats/ShellCheck for cross-cutting changes. On macOS use Bash 4+ (Homebrew), not /bin/bash 3.2.
- Test destructive behavior only in disposable projects. Never run git reset/clean or commit without explicit instruction.
- At handoff report changed files, exact executed verification, unverified gaps and next action. Update trackers only when requested or part of approved task.
- Skills in `.opencode/skills/` are specialist instructions, not automatic subagent invocation.
