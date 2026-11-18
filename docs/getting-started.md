# Getting started

## 1. Install the toolchain

Forge needs Bash 4+, CMake 3.25+, Ninja, Git, jq 1.6+ and Python 3.11+
(for the TOML parser). Conan 2 is needed only when you declare Conan
dependencies; clang-format is needed only for `forge fmt`.

macOS (Homebrew):

```bash
brew install bash cmake ninja git jq shellcheck bats-core
python3 -m pip install --upgrade 'conan>=2'
# macOS ships Bash 3.2; put Homebrew Bash first on PATH:
export PATH="/opt/homebrew/bin:$PATH"
```

Ubuntu:

```bash
sudo apt-get install -y cmake ninja-build git jq shellcheck bats python3 python3-pip
python3 -m pip install --upgrade 'conan>=2'
```

Verify everything: `forge doctor`. It reports each tool, the required minimum
and an actionable install hint, exiting 3 if anything is missing.

## 2. Create a project

```bash
forge new hello          # binary project in ./hello
forge new --lib mylib --defaults  # library project with default metadata
forge init               # prompt and scaffold a binary in the current directory
forge init --lib --defaults --name widgets --version 1.0.0
```

`new` and `init` refuse to overwrite anything. Add `--git` to run `git init`.
Forge prompts for the project name, version, description, author name, and
author email. Press Enter to use the directory name and version `0.1.0`, or
supply a version with one to four dot-separated numbers. The last three
fields are optional. Forge writes the description to the manifest and README
and adds the supplied author information to generated C++ sources, headers,
and tests. Scripts can pipe five newline-terminated responses in the same order.

Both commands create Zed and VS Code tasks for building and testing with Forge,
plus a **Forge: Debug** launch configuration. VS Code requires the CodeLLDB
extension (`vadimcn.vscode-lldb`).

## 3. Build, run, test

```bash
cd hello
forge build              # configure via preset, compile
forge run                # use the manifest's default profile
forge run --debug --bin hello  # choose a profile and executable
forge run -- arg1 arg2   # arguments after -- are forwarded exactly
forge test               # CTest with --output-on-failure
```

Build directories are `target/<profile>-<fingerprint>/`. The fingerprint covers
the compiler, generator, architecture, profile, Conan profiles, sanitizer flags
and toolchain file, so incompatible caches are never reused. Debug and release
are always separate (`forge build --release`).

After building, `forge run --debug` or `forge run --release` selects the current
module’s sole application. A module can use artifacts built at the workspace
root. Use `--bin NAME` to select a specific executable.

Generate a workspace library with `forge generate lib math --c` or
`forge generate lib math_cpp --cpp`. Generated sources and headers inherit the
project’s author information and have a blank `Purpose:` line. Forge registers
the library and syncs the workspace automatically.

## 4. Change the project

`Forge.toml` is intent; CMake is the build authority. After editing the manifest:

```bash
forge sync --check       # exit 6 if drift
forge sync --diff        # unified diff of proposed changes
forge sync --apply --yes # three-way merge, backups, conflict proposals
```

`forge build` refuses to proceed on drift and prints the exact repair command.
User edits to CMake files survive merges.

## 5. Clean

```bash
forge clean              # current profile's build dir
forge clean --profile debug
forge clean --all --yes  # all validated build dirs under target/
```

`clean` refuses symlinks and any path that escapes `target/`.


## Generate API documentation

Install Doxygen and run `forge docs` from your project. Forge passes the project
metadata and source paths from `Forge.toml` to Doxygen, which also scans
`src/` and `include/` when present. Open `target/docs/html/index.html`.
