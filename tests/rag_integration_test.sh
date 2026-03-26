#!/usr/bin/env bash
# Smoke test: indexer build, CLI wiring (no API calls required for basic checks).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Node + dist =="
command -v node >/dev/null
[[ -f "$ROOT/lib/indexer/dist/index.js" ]] || {
  echo "Run: cd lib/indexer && npm install && npm run build"
  exit 1
}

echo "== ea index help =="
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
export EA_ROOT="$ROOT"
# shellcheck disable=SC1091
source "$ROOT/lib/cmd-index.sh"
ea_cmd_index --help | head -5

echo "== indexer CLI (no network) =="
node "$ROOT/lib/indexer/dist/index.js" --help >/dev/null

echo "OK: rag integration smoke test passed"
