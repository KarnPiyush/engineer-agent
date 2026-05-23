#!/bin/bash
# ea index — build / query local structural knowledge graph (Python core)
set -euo pipefail

ea_cmd_index_usage() {
  cat <<EOF
Usage: ea index [--path /path/to/project] [--force] [--quiet]
       ea index status [--path /path/to/project]
       ea index clean [--path /path/to/project]
       ea index search "query" [--path /path/to/project] [--limit N]

Build or update a local structural knowledge graph.

Environment:
  GEMINI_API_KEY or GOOGLE_API_KEY — required for search

Options:
  --path    Project root (default: git root or cwd)
  --force   Full rebuild (re-parse all files)
  --quiet   Less stderr progress
  --limit   Search: max hits (default: 8)
  -h        Help

Examples:
  ea index
  ea index status
  ea index search "where is the router"
EOF
}

ea_cmd_index() {
  local project_override=""
  local force=false
  local quiet=false
  local mode="update" # default to incremental update
  local search_mode=false
  local query=""
  local limit="8"
  local status_mode=false
  local clean_mode=false

  if [[ "${1:-}" == "search" ]]; then
    search_mode=true
    shift
  elif [[ "${1:-}" == "status" ]]; then
    status_mode=true
    shift
  elif [[ "${1:-}" == "clean" ]]; then
    clean_mode=true
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
        mode="build"
        shift
        continue
        ;;
      --quiet)
        quiet=true
        shift
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

  if [[ "$clean_mode" == true ]]; then
    log_step "Purging structural graph at $project_root"
    rm -rf "$project_root/.code-review-graph"
    log_ok "Graph purged."
    return 0
  fi

  if [[ "$status_mode" == true ]]; then
    run_python_tool "$project_root" code-review-graph status --repo "$project_root"
    return 0
  fi

  if [[ "$search_mode" == true ]]; then
    if [[ -z "${query// }" ]]; then
      log_error "Missing search query."
      ea_cmd_index_usage
      return 1
    fi
    run_python_tool "$project_root" code-review-graph search "$query" --repo "$project_root" --limit "$limit" --json
    return 0
  fi

  # Default: indexing
  # If DB doesn't exist, we must build
  if [[ ! -f "$project_root/.code-review-graph/graph.db" ]]; then
    mode="build"
  fi

  if [[ "$mode" == "build" ]]; then
    log_step "Building structural graph at $project_root"
    local build_args=(build --repo "$project_root")
    [[ "$force" == true ]] && build_args+=(--force)
    run_python_tool "$project_root" code-review-graph "${build_args[@]}"
  else
    log_step "Updating structural graph at $project_root (incremental)"
    # We use HEAD as base for general project indexing if not specified
    run_python_tool "$project_root" code-review-graph update --repo "$project_root" --base "HEAD"
  fi
}
