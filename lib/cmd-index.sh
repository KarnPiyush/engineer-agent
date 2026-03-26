#!/bin/bash
# ea index — build / query local semantic index (Node helper)
set -euo pipefail

ea_cmd_index_usage() {
  cat <<EOF
Usage: ea index [--path /path/to/project] [--force] [--quiet] [--exclude GLOB ...]
       ea index search "query" [--path /path/to/project] [--limit N]

Build or update a local semantic index (SQLite + Gemini embeddings).

Environment:
  GEMINI_API_KEY or GOOGLE_API_KEY — required for indexing and search

Options:
  --path    Project root (default: git root or cwd)
  --force   Re-index every file
  --quiet   Less stderr progress
  --exclude Additional fast-glob ignore (repeatable); merged with built-in + .gitignore
  --limit   Search: max hits (default: 8)
  -h        Help

Examples:
  ea index
  ea index search "where is the router"
EOF
}

_ensure_indexer_built() {
  local idx="$EA_ROOT/lib/indexer"
  if [[ ! -d "$idx" ]]; then
    log_error "Indexer not found at $idx"
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js is required for ea index. Install Node 18+."
    return 1
  fi
  if [[ ! -d "$idx/node_modules" ]]; then
    log_step "Installing indexer dependencies (npm install)..."
    (cd "$idx" && npm install)
  fi
  if [[ ! -f "$idx/dist/index.js" ]]; then
    log_step "Building indexer (npm run build)..."
    (cd "$idx" && npm run build)
  fi
}

ea_cmd_index() {
  local project_override=""
  local force=false
  local quiet=false
  local search_mode=false
  local query=""
  local limit="8"
  local exclude_args=()

  if [[ "${1:-}" == "search" ]]; then
    search_mode=true
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        project_override="${2:-}"
        shift 2
        continue
        ;;
      --force)
        force=true
        shift
        continue
        ;;
      --quiet)
        quiet=true
        shift
        continue
        ;;
      --exclude)
        exclude_args+=(--exclude "${2:-}")
        shift 2
        continue
        ;;
      --limit)
        limit="${2:-8}"
        shift 2
        continue
        ;;
      -h|--help)
        ea_cmd_index_usage
        return 0
        ;;
      *)
        if [[ "$search_mode" == true ]]; then
          query="$query${query:+ }$1"
        fi
        shift
        continue
        ;;
    esac
  done

  local project_root
  project_root="$(detect_project_root "$project_override")"
  _ensure_indexer_built || return 1

  local indexer="$EA_ROOT/lib/indexer/dist/index.js"
  if [[ "$search_mode" == true ]]; then
    if [[ -z "${query// }" ]]; then
      log_error "Missing search query."
      ea_cmd_index_usage
      return 1
    fi
    node "$indexer" search --root "$project_root" --limit "$limit" "$query"
    return 0
  fi

  local args=(index --root "$project_root")
  [[ "$force" == true ]] && args+=(--force)
  [[ "$quiet" == true ]] && args+=(--quiet)
  if [[ ${#exclude_args[@]} -gt 0 ]]; then
    args+=("${exclude_args[@]}")
  fi
  log_step "Indexing project at $project_root (Gemini embeddings)"
  if [[ "$quiet" != true ]]; then
    log_warn "First run can take many minutes. Progress: lines starting with [ea-index] (stderr)."
  fi
  node "$indexer" "${args[@]}"
}
