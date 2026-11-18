#!/usr/bin/env bash
# Run all Forge Bats suites. Portable: works on macOS (Homebrew) and Ubuntu.
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if ! command -v bats >/dev/null 2>&1; then
  printf 'error: bats-core is required (apt install bats / brew install bats-core)\n' >&2
  exit 3
fi

exec bats "$@" "${ROOT}/tests/unit" "${ROOT}/tests/integration"
