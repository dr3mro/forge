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
| `build [--release] [--target T] [--toolchain F] [--link-compile-commands]` | Validate drift, install Conan graph if needed, configure via preset, compile |
| `build --debug-target T` | Build an executable with the debug preset and link it to `target/debug-T-launch` for LLDB |
| `run [--debug\|--release] [--bin N] [-- ARGS]` | Run the current module’s sole application by default. Use `--bin` to select an executable explicitly |
| `test [FILTER] [--repeat N] [--sanitize NAME]` | CTest; `--sanitize` uses an isolated build dir |
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
and `--email`. C++ library scaffolds also accept `--namespace NAME`. Pass `--defaults` to skip prompts for omitted fields.

Use `forge generate lib math --namespace acme::numeric` to put the generated
`math_library` class in a custom namespace. It defaults to the member's
project name. C++ libraries from `new --lib` and `init --lib` use the same
template. Pass `--static` (default), `--shared`, or its alias `--dynamic`
to choose library linkage. New root projects automatically receive GitHub
Actions for Debug and Release on Windows, Linux, and macOS.

## Exit codes

`0` success · `1` other · `2` usage/validation · `3` missing tool ·
`4` dependency/lock error · `5` build/test failure · `6` conflict or unsafe
write. Data goes to stdout; diagnostics and progress go to stderr. JSON output
contains no ANSI or progress text.
