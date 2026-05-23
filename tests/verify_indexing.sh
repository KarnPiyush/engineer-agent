#!/bin/bash
set -euo pipefail

# Test structural indexing integration
# This script verifies Task 1, 3, 4, 5

EA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export EA_ROOT
# shellcheck disable=SC1091
source "$EA_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$EA_ROOT/lib/cmd-index.sh"

PROJECT_DIR="$(mktemp -d)"
trap 'rm -rf "$PROJECT_DIR"' EXIT

cd "$PROJECT_DIR"
git init -q
cat > test.py <<EOF
def hello():
    print("world")

def caller():
    hello()
EOF

git add test.py
git commit -m "initial commit" -q

log_step "Testing ea index (initial build)"
ea_cmd_index --path "$PROJECT_DIR"

log_step "Testing ea index status"
ea_cmd_index status --path "$PROJECT_DIR"

log_step "Testing ea index search"
ea_cmd_index search "hello" --path "$PROJECT_DIR"

log_step "Testing incremental update"
cat >> test.py <<EOF

def another_caller():
    hello()
EOF
ea_cmd_index --path "$PROJECT_DIR"
ea_cmd_index status --path "$PROJECT_DIR"

log_ok "All indexing tests passed!"
