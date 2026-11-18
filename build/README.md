# hello

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
