# 0004 — Three-way merge behavior

Status: **resolved** (Phase 0 spike)

## Decision
`forge sync --apply` uses `git merge-file -p -L current -L base -L incoming
<current> <base> <incoming>` (Git is already a dependency). Exit 0 = clean
merge written atomically; non-zero = conflict.

## Spike results
| Case | Behavior | Forge handling |
| --- | --- | --- |
| Clean non-overlapping edits | merged text, rc 0 | write atomically after backup + confirmation |
| Overlapping edits | conflict markers, rc 1 | write `.forge/proposals/<path>.patch`, leave original untouched, exit 6 |
| Missing final newline | merge still works; markers inserted | treated as ordinary conflict/clean result |
| CRLF files | markers use file's CRLF | Forge preserves bytes; warns if base is LF but current is CRLF |
| Binary input | `error: Cannot merge binary files`, rc 255 | classified as conflict; proposal written; original untouched |

`-L` labels keep absolute temp paths out of conflict markers (`<<<<<<< current`,
`=======`, `>>>>>>> incoming`). `--yes` confirms clean writes but **never**
overrides a conflict.

## Conflict fallback
The full `git merge-file` output (including markers) is written to
`.forge/proposals/<relative-path>.patch` for manual resolution. The managed file
is never modified on conflict.
