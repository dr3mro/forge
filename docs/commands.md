# Command reference

This table matches `forge help`. Global flags may appear before or after the
command (before `--`): `--manifest-path PATH`, `--quiet/-q`, `--verbose/-v`,
`--no-color`, `--force-color`, `--dry-run`, `--offline`, `--yes/-y`, `--help/-h`, `--version/-V`.

| Command | Contract |
| --- | --- |
| `help` | Show overview or a specific command (for example, `forge help deps pin`) |
| `version` | Print Forge version |
| `doctor` | Actionable checks for Bash, CMake, Conan 2, Git, jq, parser, compiler, Ninja, ShellCheck |
| `new [NAME] [--bin\|--lib] [--git]` | Prompt for metadata and scaffold a project directory |
| `init [--bin\|--lib] [--git]` | Prompt for project and author details, then scaffold in the current directory |
| `build [--release] [--clean-first] [--target T] [--toolchain F] [--sanitize NAME] [--link-compile-commands]` | Validate drift, install Conan graph if needed, configure via preset, compile |
| `build --debug-target T` | Build an executable with the debug preset and link it to `target/debug-T-launch` for LLDB |
| `run [--build] [--debug\|--release] [--bin N] [--sanitize NAME] [-- ARGS]` | Run the current module’s sole application by default. Use `--build` to compile first and `--bin` to select an executable explicitly |
| `watch [--bin NAME] [--debug|--release] [--sanitize NAME] [-- ARGS]` | Rebuild and run when workspace inputs change |
| `test [FILTER] [--repeat N] [--sanitize NAME] [--list]` | CTest; `--sanitize` uses an isolated build dir, `--list` enumerates tests without running them |
| `leaks [--bin NAME] [-- ARGS]` | Build debug and check the selected executable for leaks |
| `clean [--profile N] [--all]` | Delete only validated Forge-owned dirs under `target/`; `--all` confirms |
| `add NAME[/VERSION] --conan [--target T]` | Discover Conan CMake metadata, link a local target, and sync |
| `add PORT --vcpkg [--target T]` | Add a vcpkg port, link a local target, and sync |
| `add NAME --source S ...` | Add a dependency to the nearest enclosing manifest and sync its workspace |
| `remove NAME [--lib]` | Remove a dependency or detach a generated workspace library, then sync |
| `deps lock` | Create/refresh `conan.lock` from a freshly rendered recipe |
| `deps pin NAME --tag T\|--branch B\|--sha SHA` | Resolve and write a full Git SHA |
| `deps status [--format json]` | Source/state report, lock state, drift and collisions |
| `sync --check\|--diff\|--apply [--yes]` | Recursively checks/updates every project in the workspace graph (three-way merge with per-project proposals) |
| `docs` | Generate Doxygen HTML at `target/docs/html/index.html` |
| `fmt [--check]` | clang-format; `--check` never modifies files |
| `metadata --format json` | Stable ANSI-free project metadata |
| `generate lib\|bin NAME [--c\|--cpp]` | Create and sync a member. Libraries default to C++ and link into the parent targets |
| `update` | Refresh Forge from its original directory or Git source |
| `uninstall` | Remove the per-user installation, launcher and shell completions |
| `workflow init` | Add the user-owned GitHub Actions workflow and CI support files to an existing project |

`add` source-specific flags: `--ref R` (conan), `--url U --rev SHA` (git),
`--path P` (path), plus `--cmake-target T` and optional repeated
`--option K=V` (conan).

`new` and `init` accept `--name`, `--version`, `--description`, `--author`,
`--email`, and `--cppstd 17|20|23` (default 20). C++ library scaffolds also
accept `--namespace NAME`. Pass `--defaults` to skip prompts for omitted fields.

Use `forge generate lib math --namespace acme::numeric` to put the generated
`math` class in a custom namespace. It defaults to the root
application project's name. Generated members also inherit the root project's
`cppstd`; pass `--cppstd 17|20|23` to override it for one member. C++ libraries
from `new --lib` and `init --lib` use the same template. Pass `--static` (default), `--shared`, or its alias `--dynamic`
to choose library linkage. New root projects automatically receive GitHub
Actions for Debug and Release on Windows, Linux, and macOS.

`forge leaks` always uses a Debug build. On macOS it runs `leaks -quiet
-atExit --` against the normal, entitled debug executable; on Linux it builds
with LeakSanitizer in `target/sanitizers/leak/debug` and runs that executable.
Pass `--bin NAME` to select an executable and put program arguments after `--`.
Exit 0 means no leaks, exit 5 means leaks were detected (or the instrumented
program failed), and exit 3 means a required tool is unavailable.

Use `--clean-first` to ask CMake to clean build outputs before compiling,
without changing the build directory or deleting user-owned files.

`--sanitize NAME` is accepted by `build`, `run`, `watch`, and `test`. Names are
`address` (`asan`), `undefined` (`ubsan`), `leak` (`lsan`), or `thread`
(`tsan`). Instrumented builds use an isolated `target/sanitizers/NAME/<profile>`
tree, so they never disturb a normal build. `forge build --sanitize address`
compiles an app under ASan and `forge run --sanitize address` launches that
instrumented executable; adding `--build` builds it first. `watch` forwards the
sanitizer to each rebuild. C and C++ sources and shared-library links are all
instrumented, so mixed workspaces are covered. The root `compile_commands.json`
link is not changed by an instrumented build.

## Exit codes

`0` success · `1` other · `2` usage/validation · `3` missing tool ·
`4` dependency/lock error · `5` build/test failure · `6` conflict or unsafe
write. Data goes to stdout; diagnostics and progress go to stderr. JSON output
contains no ANSI or progress text.
