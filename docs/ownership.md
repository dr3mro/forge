# Ownership and sync

| Artifact | Ownership | Update policy |
| --- | --- | --- |
| `Forge.toml` | User intent | `add`/`remove` edit it transactionally; ambiguous edits are refused |
| `CMakeLists.txt`, `cmake/*.cmake` | User-owned after creation | Created once; `sync` proposes changes |
| `CMakePresets.json`, `CMakeUserPresets.json` | User-owned | Same sync policy; Conan may write its own user presets |
| `conanfile.txt` | User-owned recipe | Created once; `sync` proposes patches |
| `conan.lock` | Conan's | Written by `forge deps lock`; committed |
| `.forge/state.json` | Tool-owned, committed | Template ID, hashes of generated base files, manifest hash |
| `.forge/base/` | Tool-owned | Base copies used for three-way merges |
| `.forge/proposals/` | Tool-written, git-ignored | Conflict patches from `sync` |
| `.forge/backups/` | Tool-written, git-ignored | Backups before applying a merge |
| `target/` | Generated, git-ignored | Safe to delete via `forge clean` |

## Sync algorithm

`sync` walks the **entire workspace graph**: it finds every reachable
`Forge.toml` (root → members → their members), renders each project's templates
from its own manifest, and checks each against that project's own
`.forge/state.json`. Messages are prefixed with the project path (`.` for the
root). Applying changes updates every project, with proposals and backups kept
inside each project's `.forge/`.

For each managed path, compare the recorded base, the current file and the
freshly rendered template:

- `--check`: reports pending template or manifest drift; exit 6 on drift.
- `--diff`: prints a unified diff of current vs. rendered.
- `--apply`: files without local edits are replaced directly; locally edited
  files are three-way merged with `git merge-file`. Clean merges are backed up
  and written atomically; conflicts write
  `.forge/proposals/<path>.patch`, exit 6 and leave the original untouched.
  Non-interactive use requires `--yes`, which never overrides a conflict.

`forge build` never regenerates CMake. If the manifest and CMake disagree, it
fails with exit 6 and recommends `forge sync --diff`.

## Fingerprint inputs

Build directories are `target/<profile>-<fingerprint>/`. The fingerprint hashes
compiler identity, generator, architecture, profile, Conan host/build profile
settings, sanitizer flags and any explicit toolchain file. `compile_commands.json`
is exported in the build tree and linked into the project root only when no
file exists there (or with `build --link-compile-commands` consent).
