# 0006 — Post-Phase-2 Bash checkpoint

Status: **recorded** (Phase 2 checkpoint)

## Module size (lines)
Largest modules after Phase 2:

| Module | Lines | Role |
| --- | --- | --- |
| `lib/cmake.sh` | 389 | template rendering, fingerprints, configure, File API |
| `lib/manifest.sh` | 242 | parser adapter, schema, transactional block edits |
| `lib/core.sh` | 203 | exit codes, IO, atomic writes, paths, hashing |
| `lib/sync.sh` | 159 | three-way merge / patch proposals |
| `lib/deps.sh` | 149 | deps lock/pin/status, collisions |

Total implementation ≈ 2,500 lines including 47 Bats tests and templates.

## Defect review
Bugs found during Phase 0–2 and fixed with regression tests:

1. Associative array scope lost when modules were sourced inside a helper
   function → modules now source at top level.
2. `to_entries` on null tables → `// {}` guards everywhere.
3. Global flags after the command (`sync --apply --yes`) were rejected → CLI
   parses globals anywhere before `--`.
4. CMake File API `targets` are references into per-target JSON files → fixed
   two-level codemodel lookup.
5. `git merge-file` labels contained absolute temp paths → `-L` labels added.
6. Conan `--build=never` conflicted with `--build=missing` → exclusive policy.
7. Lock staleness keyed on conanfile mtime broke the documented
   `add → lock → sync` workflow → keyed on Conan-relevant manifest hash, and
   locks are now created from a freshly rendered recipe.
8. `cmd_remove` used an undiscovered manifest path → calls `manifest_load`.
9. JSON `true` is not a Python literal → explicit JSON→Python conversion.
10. Reuse check trusted `CMakeCache.txt` alone → also requires build.ninja/Makefile.

## Decision
Bash remains a workable fit through v0.1. The frozen JSON/exit-code contract and
the adapter boundary keep a future rewrite viable if `manifest.sh`/`sync.sh`
keep growing. Continue to Phase 3.
