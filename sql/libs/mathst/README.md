# mathst

A C++ project managed by Forge.

## Quick start

```
forge build
forge test
```

In Zed or VS Code, use **Forge: Debug** to build and launch under LLDB.
VS Code requires the CodeLLDB extension (`vadimcn.vscode-lldb`).

Edit `Forge.toml` to declare dependencies and targets, then run
`forge sync --diff` and `forge sync --apply` to update the user-owned CMake
files. `forge doctor` checks your local toolchain.

## Version

`forge run -- --version` prints the version for an application scaffold.
CMake starts with the version in `Forge.toml`. If the Forge Git hook is
installed, a new release tag such as `v1.2.3` updates `version.cpp.in` and
the next build picks it up. To enable the hook in a clone using the default Git
hooks directory, install `forge-reference-transaction` as the executable
`reference-transaction` hook or chain it from an existing hook.
