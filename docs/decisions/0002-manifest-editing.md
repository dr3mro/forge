# 0002 — Manifest editing strategy

Status: **resolved** (Phase 0 spike, implemented in Phase 2)

## Decision
Edit `Forge.toml` with **block-level append/delete** on the raw text, never a
general TOML writer:

- Dependencies are keyed tables (`[dependencies.NAME]`) — one contiguous block.
  `add` appends a block at EOF; `remove` deletes exactly that block.
- Targets are array tables (`[[bin]]`, `[[lib]]`, `[[test]]`). `add` appends;
  `remove` locates the single block whose `name` matches and deletes it.

Every edit follows the same transaction:

1. Refuse if the target block/name already exists or cannot be placed
   unambiguously.
2. Write a backup (`.forge/backups/Forge.toml.<n>`).
3. Apply the edit to an in-memory line array.
4. **Reparse and revalidate** the result with `tomllib` + `schema.jq`.
5. Atomically rename the validated temp file into place.

Comments and formatting outside the touched block are preserved byte-for-byte.

## Verification
Fixtures cover trailing blocks, comments, unicode/spaces in paths and
metacharacters. Anything the block locator cannot resolve is refused with a
message rather than guessed. No regex rewriting of arbitrary TOML is performed.
