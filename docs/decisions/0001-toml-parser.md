# 0001 — TOML → JSON adapter

Status: **resolved** (Phase 0 spike)

## Decision
Use **Python 3 `tomllib`** (standard library since 3.11) as the TOML 1.0 → JSON
adapter, and **`jq` 1.6+** for all queries. No third-party parser is installed.

## Alternatives considered
| Candidate | License | macOS/Linux install | TOML 1.0 | Pinning |
| --- | --- | --- | --- | --- |
| `tomlq` (yq) | MIT | brew/apt | partial | yes |
| `dasel` | MIT | Go binary | partial | yes |
| `taplo` | MIT | Rust binary | good | yes |
| `python3 -m tomllib` | PSF | python3 (already required by Conan 2) | full | via `tools.versions` |

## Rationale
- `tomllib` is a conformant TOML 1.0 parser with zero extra install steps;
  Conan 2 already requires Python 3.
- It parses to a Python dict which `json.dump` serializes losslessly for the
  subset Forge validates. No custom TOML semantics.
- The adapter interface (`manifest_to_json`) isolates the choice: a future
  `taplo`/`dasel` adapter is a one-file change.
- Pin via `PYTHON_MIN=3.11` and `TOML_ADAPTER=python3-tomllib` in
  `tools.versions`. `forge doctor` verifies both version and `import tomllib`.

## Safety
Parsing never executes project scripts. A conformance fixture set lives in
`tests/fixtures/` (valid full, unknown key, unsafe path/name, non-SHA rev,
malformed TOML, shell-metacharacter path). Shell metacharacters are rejected by
the schema and are never interpolated into shell strings (all subprocess
arguments use Bash arrays).
