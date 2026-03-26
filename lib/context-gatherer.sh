#!/bin/bash
# Context gathering utilities for engineer-agent
# Provides git history and import parsing for enhanced AI context

set -euo pipefail

# ---------------------------------------------------------------------------
# Git Context - Get recent commits and changes
# ---------------------------------------------------------------------------

# get_git_context PROJECT_ROOT [NUM_COMMITS]
# Returns formatted git context: commit messages and diffs
get_git_context() {
  local project_root="${1:-.}"
  local num_commits="${2:-3}"
  
  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  
  local commits
  commits="$(git -C "$project_root" log --oneline -n "$num_commits" 2>/dev/null || true)"
  
  if [[ -z "$commits" ]]; then
    return 0
  fi
  
  echo "## Recent Commits (last $num_commits)"
  echo ""
  echo "$commits"
  echo ""
  
  local diff_content
  diff_content="$(git -C "$project_root" diff HEAD~"$num_commits" HEAD --stat 2>/dev/null || true)"
  
  if [[ -n "$diff_content" ]]; then
    echo "## Recent Changes Summary"
    echo ""
    echo "$diff_content"
    echo ""
  fi
}

# get_changed_files PROJECT_ROOT [NUM_COMMITS]
# Returns list of recently changed files
get_changed_files() {
  local project_root="${1:-.}"
  local num_commits="${2:-3}"
  
  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo ""
    return
  fi
  
  git -C "$project_root" diff --name-only HEAD~"$num_commits" HEAD 2>/dev/null | head -20 || true
}

# ---------------------------------------------------------------------------
# Import Parsing - Find local imports in source files
# ---------------------------------------------------------------------------

# MAX_DEPTH controls how deep we follow imports
MAX_DEPTH="${MAX_DEPTH:-2}"
# MAX_FILES limits total files to avoid token explosion
MAX_FILES="${MAX_FILES:-10}"

# parse_imports FILE_PATH PROJECT_ROOT [CURRENT_DEPTH]
# Parses import/require statements from a file and returns local file contents
parse_imports() {
  local file_path="$1"
  local project_root="$2"
  local current_depth="${3:-0}"
  
  if [[ ! -f "$file_path" ]]; then
    return 0
  fi
  
  if [[ "$current_depth" -ge "$MAX_DEPTH" ]]; then
    return 0
  fi
  
  local file_dir
  file_dir="$(dirname "$file_path")"
  local absolute_project_root
  absolute_project_root="$(cd "$project_root" && pwd)"
  
  local import_patterns=()
  local file_ext="${file_path##*.}"
  
  case "$file_ext" in
    ts|tsx|js|jsx)
      import_patterns=(
        "import .* from ['\"]\.\.?/([^'\"]+)['\"]"
        "require\(['\"]\.\.?/([^'\"]+)['\"]"
      )
      ;;
    py)
      import_patterns=(
        "from \.?\.?([a-zA-Z_][a-zA-Z0-9_]*) import"
        "import \.?\.?([a-zA-Z_][a-zA-Z0-9_]*)"
      )
      ;;
    go)
      import_patterns=(
        "import .*\"([^\"]+)\""
      )
      ;;
    rs)
      import_patterns=(
        "use (crate|self|super)::([a-zA-Z_][a-zA-Z0-9_]*)"
      )
      ;;
  esac
  
  local imported_files=()
  
  for pattern in "${import_patterns[@]}"; do
    local matches
    matches="$(grep -oE "$pattern" "$file_path" 2>/dev/null | sed -E "s/$pattern/\1/g" | sort -u || true)"
    
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      
      local resolved_path=""
      
      case "$file_ext" in
        ts|tsx|js|jsx)
          for ext in "" ".ts" ".tsx" ".js" ".jsx" "/index.ts" "/index.js"; do
            local try_path="$file_dir/$match$ext"
            if [[ -f "$try_path" ]]; then
              resolved_path="$try_path"
              break
            fi
          done
          ;;
        py)
          local py_path="$file_dir/${match//./\/}.py"
          if [[ -f "$py_path" ]]; then
            resolved_path="$py_path"
          fi
          ;;
      esac
      
      if [[ -n "$resolved_path" ]] && [[ -f "$resolved_path" ]]; then
        local canonical_path
        canonical_path="$(realpath --relative-to="$absolute_project_root" "$resolved_path" 2>/dev/null || echo "$resolved_path")"
        
        if [[ ! " ${imported_files[*]} " =~ " ${canonical_path} " ]]; then
          imported_files+=("$canonical_path")
        fi
      fi
    done <<< "$matches"
  done
  
  local result=""
  local count=0
  
  for imp_file in "${imported_files[@]}"; do
    if [[ "$count" -ge "$MAX_FILES" ]]; then
      break
    fi
    
    local full_path="$absolute_project_root/$imp_file"
    if [[ -f "$full_path" ]]; then
      result="${result}

### Imported File: ${imp_file}
\`\`\`
$(cat "$full_path")
\`\`\`
"
      count=$((count + 1))
      
      if [[ "$current_depth" -lt $((MAX_DEPTH - 1)) ]]; then
        local nested_imports
        nested_imports="$(parse_imports "$full_path" "$project_root" $((current_depth + 1)) || true)"
        if [[ -n "$nested_imports" ]]; then
          result="${result}${nested_imports}"
        fi
      fi
    fi
  done
  
  echo "$result"
}

# get_import_context FILE_PATH PROJECT_ROOT
# Main function to get import context for a file
get_import_context() {
  local file_path="$1"
  local project_root="$2"
  
  local absolute_file_path
  absolute_file_path="$(cd "$project_root" && realpath "$file_path" 2>/dev/null || echo "$file_path")"
  
  local context
  context="$(parse_imports "$absolute_file_path" "$project_root" 0)"
  
  if [[ -n "$context" ]]; then
    echo "## Import Dependencies"
    echo "$context"
  fi
}

# ---------------------------------------------------------------------------
# LSP-lite: Symbol Search for debug context
# ---------------------------------------------------------------------------

# MAX_SYMBOL_RESULTS limits results for common symbols
MAX_SYMBOL_RESULTS="${MAX_SYMBOL_RESULTS:-20}"

# search_symbols PROJECT_ROOT SYMBOLS...
# Search for symbols in the codebase
search_symbols() {
  local project_root="$1"
  shift
  local symbols=("$@")
  
  if [[ ${#symbols[@]} -eq 0 ]]; then
    return 0
  fi
  
  local search_cmd
  if command -v rg >/dev/null 2>&1; then
    search_cmd="rg"
  elif command -v grep >/dev/null 2>&1; then
    search_cmd="grep -r"
  else
    return 0
  fi
  
  local common_symbols=("init" "main" "test" "Error" "null" "undefined" "true" "false" "return")
  local is_common=false
  for sym in "${symbols[@]}"; do
    for common in "${common_symbols[@]}"; do
      if [[ "$sym" == "$common" ]]; then
        is_common=true
        break
      fi
    done
  done
  
  if [[ "$is_common" == true ]]; then
    return 0
  fi
  
  local result=""
  local total_matches=0
  
  for symbol in "${symbols[@]}"; do
    local matches=""
    if [[ "$search_cmd" == "rg" ]]; then
      matches="$(rg -l -n --max-count "$MAX_SYMBOL_RESULTS" \
        --glob '!node_modules/*' \
        --glob '!*.min.js' \
        --glob '!dist/*' \
        --glob '!build/*' \
        -g '*.{ts,js,py,go,rs,java,tsx,jsx}' \
        "\\b${symbol}\\b" "$project_root" 2>/dev/null | head -10 || true)"
    else
      matches="$(grep -rl -n --include='*.ts' --include='*.js' --include='*.py' --include='*.go' --include='*.rs' \
        --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build \
        -e "\\b${symbol}\\b" "$project_root" 2>/dev/null | head -10 || true)"
    fi
    
    if [[ -n "$matches" ]]; then
      local match_count
      match_count="$(echo "$matches" | wc -l | tr -d ' ')"
      total_matches=$((total_matches + match_count))
      
      result="${result}

### Symbol: ${symbol} (${match_count} occurrences)
\`\`\`
${matches}
\`\`\`
"
    fi
  done
  
  if [[ -n "$result" ]]; then
    echo "## Symbol Search Results"
    echo "Found $total_matches total matches"
    echo "$result"
  fi
}

# extract_symbols_from_error ERROR_TEXT
# Extract potential symbols from an error message
extract_symbols_from_error() {
  local error_text="$1"
  
  echo "$error_text" | grep -oE '\b[A-Z][a-zA-Z0-9_]*\b' | sort -u | head -10
}

# get_symbol_context PROJECT_ROOT ERROR_TEXT
# Main function to get symbol context from error text
get_symbol_context() {
  local project_root="$1"
  local error_text="$2"
  
  local symbols
  symbols="$(extract_symbols_from_error "$error_text")"
  
  if [[ -n "$symbols" ]]; then
    search_symbols "$project_root" $symbols
  fi
}

# ---------------------------------------------------------------------------
# Planning context - multi-source project snapshot for ea plan / ea ship
# ---------------------------------------------------------------------------

README_MAX_LINES="${README_MAX_LINES:-200}"
STRUCTURE_MAX_LINES="${STRUCTURE_MAX_LINES:-80}"
ENTRYPOINT_MAX_LINES="${ENTRYPOINT_MAX_LINES:-20}"

# append_semantic_planning_context PROJECT_ROOT QUERY
# If .engineer-agent/index.db exists and GEMINI_API_KEY is set, runs local indexer search.
append_semantic_planning_context() {
  local root="${1:?}"
  local query="$2"
  [[ "${EA_SKIP_SEMANTIC:-}" == "1" ]] && return 0
  local db="$root/.engineer-agent/index.db"
  local idx="${EA_ROOT:-}/lib/indexer/dist/index.js"
  [[ -f "$db" && -f "$idx" ]] || return 0
  command -v node >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [[ -n "${GEMINI_API_KEY:-}${GOOGLE_API_KEY:-}" ]] || return 0

  local json
  json="$(node "$idx" search --root "$root" --limit "${EA_SEMANTIC_LIMIT:-5}" "$query" 2>/dev/null)" || return 0
  [[ -n "$json" ]] || return 0

  local n
  n="$(echo "$json" | jq -r '.hits | length' 2>/dev/null || echo 0)"
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -eq 0 ]]; then
    return 0
  fi

  echo "## Relevant Code Context (semantic retrieval)"
  echo ""
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.hits[] | "### \(.path) (lines \(.startLine)-\(.endLine), score \(.score))\n\n\(.content)\n"'
  else
    echo "$json"
  fi
  echo ""
  echo "---"
  echo ""
}

# get_planning_context PROJECT_ROOT REQUIREMENT_TEXT
# Outputs a single markdown blob: README (capped), repo structure, language/entrypoints,
# recent git context, then ## New Requirement. Token-conscious; skips heavy dirs.
get_planning_context() {
  local project_root="${1:?}"
  local requirement_text="$2"
  local root_abs
  root_abs="$(cd "$project_root" && pwd)"

  # --- 1. README (if present, capped) ---
  local readme_file="$root_abs/README.md"
  if [[ -f "$readme_file" ]]; then
    echo "## Project Context (README)"
    echo ""
    head -n "$README_MAX_LINES" "$readme_file"
    echo ""
    echo "---"
    echo ""
  fi

  append_semantic_planning_context "$root_abs" "$requirement_text"

  # --- 2. Repo structure (top-level + one level down, exclude heavy dirs) ---
  echo "## Repo Structure"
  echo ""
  local skip_dirs="node_modules|dist|build|.git|__pycache__|.next|.nuxt|.cache|vendor|target|out"
  (cd "$root_abs" && find . -maxdepth 2 -not -path '*/.*' 2>/dev/null | \
    grep -vE "/(${skip_dirs})(/|$)" | \
    sort | head -n "$STRUCTURE_MAX_LINES") || true
  echo ""
  echo "---"
  echo ""

  # --- 3. Language and entrypoint hints ---
  echo "## Language and Entrypoint Hints"
  echo ""
  local ext_counts
  ext_counts="$(cd "$root_abs" && find . -type f -not -path '*/.*' 2>/dev/null | \
    grep -vE "/(${skip_dirs})(/|$)" | \
    sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10)" || true
  if [[ -n "$ext_counts" ]]; then
    echo "File extensions (top):"
    echo "$ext_counts" | head -5
    echo ""
  fi

  local entrypoints_line
  entrypoints_line="$(cd "$root_abs" && find . -maxdepth 4 -type f \( \
    -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' -o \
    -name 'index.tsx' -o -name 'index.ts' -o -name 'index.js' -o -name 'index.jsx' -o \
    -name 'main.go' -o -name 'main.rs' -o -name 'manage.py' \) 2>/dev/null | \
    grep -vE "/(${skip_dirs})(/|$)" | sort -u | head -n "$ENTRYPOINT_MAX_LINES")" || true
  if [[ -n "$entrypoints_line" ]]; then
    echo "Likely entrypoints / manifests:"
    echo "$entrypoints_line"
  fi
  echo ""
  echo "---"
  echo ""

  # --- 4. Recent changes (git) ---
  if git -C "$root_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    get_git_context "$root_abs" 5 || true
    echo "---"
    echo ""
  fi

  # --- 5. New requirement ---
  echo "## New Requirement"
  echo ""
  echo "$requirement_text"
}
