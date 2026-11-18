# Forge

A Cargo-inspired orchestration CLI for conventional C++ projects. Forge scaffolds
projects and gives stable commands to configure, build, run, test and maintain
them. It does **not** replace CMake, Conan, Git or a package registry: CMake stays
the build authority, Conan and vcpkg resolve their packages, and Git dependencies are
pinned to full commit SHAs in `Forge.toml`.

Supported: macOS and Linux · Bash 4+ · CMake 3.25+ · C++17/20/23 · Ninja (recommended)
and Make · Conan 2 · Git.

## Quick start

```bash
# Requirements: Bash 4+, CMake, Ninja, Conan 2 (if using Conan deps), Git, jq, Python 3.11+
forge doctor

forge new hello
cd hello
forge build
forge run --bin hello
forge test
```

To initialize the current directory with project metadata and generate API
documentation, run:

```sh
forge init --defaults --name hello --version 0.1.0
forge docs
```

Install Doxygen to use `forge docs`, then open `target/docs/html/index.html`.

Add a Conan dependency from the project root or inside a workspace member.

```bash
forge add fmt --conan
# Or choose an exact version with: forge add fmt/12.2.0 --conan
forge deps lock
forge build
```

Forge discovers the CMake package and exported target from Conan, links the
current module’s sole application or library, and applies workspace sync.
At the workspace root, Forge prioritizes the sole application.
Use `--target NAME` when the module has multiple targets. Run `forge deps lock`
from the workspace root. Bare `fmt` uses the tested `fmt/12.1.0` default.
For other bare names, Forge asks Conan to resolve a version and records the
exact result.

For vcpkg, set `VCPKG_ROOT` to a bootstrapped checkout and run:

```bash
forge add fmt --vcpkg
forge build
```

Forge gives vcpkg a generated workspace manifest inside the build directory.
Other ports require `--cmake-target` and can override the CMake package name
with `--cmake-package`. See the [dependency guide](docs/dependencies.md).

### Change a dependency in Forge.toml

Change a Conan `ref` to upgrade it and edit its options in the same manifest.
Update `cmake_target` and `cmake_package` if the selected version or options
export different CMake names.

```toml
[dependencies.fmt]
source = "conan"
ref = "fmt/12.1.0"
cmake_package = "fmt"
cmake_target = "fmt::fmt-header-only"

[dependencies.fmt.conan_options]
header_only = true
```

vcpkg declarations accept `features = ["feature-name"]` and
`default_features = false`. To pin an exact port release, set
`version = "11.0.0#1"` in its dependency table and set `build.vcpkg_baseline`
in the workspace root to the full registry commit SHA. Use matching settings
where a port is shared across members. Use `forge deps pin NAME --tag TAG`
to upgrade a Git dependency by tag.

```sh
forge sync --apply --yes
forge deps lock   # If the workspace still has Conan dependencies
forge build
forge remove fmt
forge remove widget --lib   # Detaches libs/widget and keeps its source files
```

Both forms of `remove` apply workspace sync. Before detaching a library, remove
links to it from other members. Refresh the Conan lock after a removal if Conan
dependencies remain.

## Project metadata and release versions

Both `new` and `init` prompt for omitted project metadata. Use `--defaults`
for a noninteractive run and override any defaults with `--name`,
`--version`, `--description`, `--author`, and `--email`.

```sh
forge new hello --git --defaults --version 1.2.3 --description "Example app"
cd hello
forge build
forge run -- --version   # 1.2.3
git add .
git commit -m "Initial project"
git tag v1.2.4
forge build
forge run -- --version   # v1.2.4
```

Forge installs a Git `reference-transaction` hook when you use `--git` or
initialize in an existing repository root with the default hooks directory.
After a new numeric tag succeeds, the hook writes its exact text into
`version.cpp.in`. CMake reads its numeric portion for `PROJECT_VERSION` and
generates the C++ include at configure time. Before tagging, CMake uses
`package.version` from Forge.toml. Tag updates change the working tree.
For custom hook setups, call the generated `forge-reference-transaction`
script with the hook arguments and ref updates on stdin. Clones need their
own hook registration.

## Install

Install from a local source directory, including an unpacked source archive.
The installer requires Git to track the files it owns.

```sh
sh install.sh                  # Use the script's source directory
sh install.sh --source /path/to/forge
export PATH="$HOME/.local/bin:$PATH"
```

When the repository URL is available, replace the placeholders to install from
its default branch through the streamed installer.

```sh
curl -fsSL https://raw.githubusercontent.com/OWNER/REPOSITORY/DEFAULT_BRANCH/install.sh |
  sh -s -- --repo https://github.com/OWNER/REPOSITORY.git
```

Forge installs into `~/.local/share/forge` and creates `~/.local/bin/forge`.
`forge update` refreshes it from the original directory or Git repository.
`forge uninstall` and `sh uninstall.sh` remove the installation and its
Bash and Zsh completion files. Start a new interactive shell to load
completions. Bash login shells can load `~/.bashrc` from `~/.bash_profile`.
Existing completion files and symlinked startup files are preserved.

## Command reference

Open the [Forge website](docs/index.html) for the searchable command reference and
workflow examples. Use `forge COMMAND --help` for options and examples in the
terminal, or `forge help deps pin` to open a specific subcommand.

| Command | Example | Purpose |
| --- | --- | --- |
| `help` | `forge help deps pin` | Show this help |
| `version` | `forge version` | Print the Forge version |
| `doctor` | `forge doctor` | Check the local toolchain |
| `new` | `forge new --name hello --git` | Prompt for details and scaffold a directory |
| `init` | `forge init --name widget --lib --defaults` | Prompt for project details in the current directory |
| `build` | `forge build --debug-target hello` | Configure and compile a project or target |
| `run` | `forge run --release --bin hello -- --version` | Run a built executable and forward arguments |
| `test` | `forge test smoke --repeat 3` | Run CTest with a filter, repeat count, or sanitizer |
| `clean` | `forge clean --profile release --dry-run` | Remove Forge-owned build directories |
| `add` | `forge add fmt/12.1.0 --conan --target hello` | Declare a dependency and sync the workspace |
| `remove` | `forge remove widget --lib` | Remove a dependency or detach a library, then sync |
| `deps` | `forge deps status --format json` | Manage dependency locks and pins |
| `deps lock` | `forge deps lock` | Create or refresh the workspace Conan lock |
| `deps pin` | `forge deps pin vendor --tag v1.2.3` | Resolve and save a full Git SHA |
| `deps status` | `forge deps status --format json` | Report dependencies, lock state, and drift |
| `sync` | `forge sync --diff` | Check, preview, or reconcile generated files |
| `docs` | `forge docs` | Generate HTML documentation with Doxygen |
| `fmt` | `forge fmt --check` | Format C and C++ sources with clang-format |
| `metadata` | `forge metadata --format json` | Emit stable project metadata as JSON |
| `generate` | `forge generate lib widget --c` | Scaffold a workspace member and sync |
| `generate lib` | `forge generate lib widget --c` | Create a C or C++ library member |
| `generate bin` | `forge generate bin worker` | Create a C++ application member |
| `workflow` | `forge workflow init` | Manage the generated CI workflow |
| `workflow init` | `forge workflow init --dry-run` | Create a GitHub Actions template |
| `update` | `forge update` | Refresh Forge from its installation source |
| `uninstall` | `forge uninstall` | Remove the installation and shell completions |

Bash and Zsh completion list commands at `forge`, subcommands at `forge deps`
or `forge generate`, and relevant options after you type `--`. Start a new
interactive shell after installing or updating Forge to load the completion.

For libraries, `--namespace acme::numeric` works with `generate lib`,
`new --lib`, and `init --lib`. The namespace defaults to the library's project
name. The header declares a `<name>_library` class with public, protected, and
private sections, defaulted construction and assignment, and a virtual
destructor. The sample free function remains in the library's original
project namespace. C libraries use their existing C interface.

```bash
forge generate lib math --namespace acme::numeric
forge new geometry --lib --namespace acme::geometry --defaults
```

## Static and shared libraries

Generated libraries are static by default. Use `--shared` (or `--dynamic`)
for a shared library. These options work with `new --lib`, `init --lib`,
and `generate lib`, including generated C libraries.

```sh
forge generate lib codec --c --static
forge generate lib plugin --shared --namespace acme::plugins
```

Change `type = "static"` or `type = "shared"` under `[[lib]]` in
`Forge.toml`, then run `forge sync --apply --yes`. Older manifests with no
`type` retain CMake's `BUILD_SHARED_LIBS` behavior.

## GitHub Actions

`new` and `init` scaffold a root workflow and CI support files under
`.github/`. For an older project, run `forge workflow init`. The files
are user-owned and Forge preserves existing CI files. Generated workspace
members use their parent's workflow.

| Runner | Debug and Release output |
| --- | --- |
| Linux | CTest results, a build archive, a dependency OCI image, and a Docker project image |
| Windows | Native MSVC build archive and CTest results |
| macOS | Native CMake build archive and CTest results |

On Linux, the workflow builds and uploads a dependency OCI image for each
configuration. It installs locked Conan packages, builds vcpkg ports, and
fetches pinned Git sources. The project image builds and tests source files on
top of that exact dependency image. Changing dependency inputs refreshes the
dependency layer, while source-only changes can reuse it. Windows and macOS
use native dependency caches keyed by dependency inputs, runner, and
configuration. Git and local source dependencies compile with the project.

Commit updated manifests, generated CMake files, and any refreshed Conan
lock so CI sees dependency changes. Build archives contain project outputs
and headers. Projects with external shared libraries may need additional
runtime packaging. Download the Linux dependency and project images from
the workflow artifacts. The project image includes the build environment.

## Editor tasks and debugging

`forge new` and `forge init` create build, test, and debug build tasks for
Zed and VS Code. Open the project root and make sure the editor can find
`forge` on its PATH. In VS Code, install the CodeLLDB extension
(`vadimcn.vscode-lldb`). Select **Forge: Debug** to build and launch under
LLDB. See the [Zed debugger documentation](https://zed.dev/docs/debugger) and
[VS Code launch configuration reference](https://code.visualstudio.com/docs/debugtest/debugging-configuration).
Binary projects launch their application, and library projects launch
their test executable. Forge creates these editor files during scaffolding
and leaves subsequent edits to them in your project.

## Documentation

- [Getting started](docs/getting-started.md)
- [Manifest reference](docs/manifest.md)
- [Command reference](docs/commands.md)
- [Ownership & sync](docs/ownership.md)
- [Dependencies](docs/dependencies.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Design decisions](docs/decisions/)

## Development

```bash
shellcheck -x -S warning bin/forge install.sh uninstall.sh lib/*.sh lib/commands/*.sh tests/run.sh tests/fakebin/*
bash tests/run.sh
```

Forge's own CI runs ShellCheck, `doctor`, Bats unit tests and real-tool
integration tests on both macOS and Ubuntu (`.github/workflows/ci.yml`).
