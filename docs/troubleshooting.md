# Troubleshooting

| Symptom | Cause | Repair |
| --- | --- | --- |
| `Bash 4+ is required (found 3.2...)` | macOS default Bash is 3.2 | `brew install bash` and put `/opt/homebrew/bin` first on PATH |
| `forge doctor` reports a missing tool | Tool not installed or wrong version | Follow the printed install hint, then re-run `doctor` |
| `no Forge.toml found` | Command run outside a project | `cd` into the project or pass `--manifest-path PATH` |
| `manifest/CMake drift detected` | `Forge.toml` changed without sync | `forge sync --diff`, then `forge sync --apply --yes` |
| `sync --apply` exits 6 with a conflict | Local and template edits overlap | Inspect `.forge/proposals/<path>.patch`, resolve by hand, then re-run `sync --apply` |
| `non-interactive operation requires --yes` | `sync --apply` / `clean --all` without confirmation | Add `--yes` |
| `conan.lock is missing` / `is stale` | Lock not created or manifest Conan data changed | `forge deps lock` |
| `conan install failed` | Remote/profile issue or incompatible binary | Check `conan profile show`, remotes and the Conan warning in output |
| `fmt::fmt not found` | Wrong target name for a Conan package | Use the verified upstream target (e.g. `fmt::fmt-header-only` for `fmt/12.1.0` header-only) |
| `offline build requires populated Git sources` | `--offline` on a fresh checkout | Run a connected `forge build` once, then retry offline |
| `run` asks for `--bin` | Multiple executables (e.g. test binary) | `forge run --bin <name>` |
| `no tests found` | No `[[test]]` targets, or filter matched nothing | Add a test target, adjust the filter, or pass `--allow-no-tests` |
| `refusing to overwrite` | Scaffold/workflow target already exists | Remove or rename the existing file; Forge never overwrites user work |
| `refusing unsafe path` | `clean` saw a symlink or traversal outside `target/` | Remove the symlink; Forge only deletes validated directories under `target/` |
| JSON contains color codes | Color forced with `FORCE_COLOR` | Use `--no-color`; `--format json` output is ANSI-free by contract |
