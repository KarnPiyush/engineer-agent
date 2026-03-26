#!/bin/bash
set -euo pipefail

# Load context-gatherer
# shellcheck disable=SC1091
source "$EA_ROOT/lib/context-gatherer.sh"

ea_cmd_debug_usage() {
  cat <<EOF
Usage: ea debug [ERROR_DESCRIPTION] [--file LOG_FILE] [--last-error] [--path /path/to/project] [--open] [--cursor]

Analyze a bug using Kilo Code CLI (DeepSeek R1, debug mode) and generate a
Cursor-ready debug brief at .engineer-agent/debug-brief.md.

Arguments:
  ERROR_DESCRIPTION    Error message or description of the bug

Options:
  --file         Read error from a log file
  --last-error   Use the last captured terminal error (~/.ea/last-error.txt)
  --path         Project path override (default: auto-detect)
  --backend      Force a backend: kilo | gemini (default: auto-route)
  --open         Open generated debug-brief.md in Cursor after completion
  --cursor       Alias for --open
  -h, --help     Show this help message

Workflow:
  1. ea debug "TypeError: Cannot read property 'id' of undefined"
  2. Open Cursor → Agent Mode
  3. Paste: "Follow the debug brief in .engineer-agent/debug-brief.md to fix this bug."

Examples:
  ea debug "TypeError: Cannot read property 'id' of undefined"
  ea debug --file /tmp/error.log
  ea debug --last-error
  ea debug --last-error --cursor
EOF
}

ea_cmd_debug() {
  local error_desc=""
  local error_file=""
  local use_last_error=false
  local project_override=""
  local force_backend=""
  local open_in_cursor=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --file)
        error_file="${2:-}"
        shift
        ;;
      --last-error)
        use_last_error=true
        ;;
      --path)
        project_override="${2:-}"
        shift
        ;;
      --backend)
        force_backend="${2:-}"
        shift
        ;;
      --open|--cursor)
        open_in_cursor=true
        ;;
      -h|--help)
        ea_cmd_debug_usage
        return 0
        ;;
      *)
        if [[ -z "$error_desc" ]]; then
          error_desc="$1"
        else
          error_desc="$error_desc $1"
        fi
        ;;
    esac
    shift
  done

  local project_root
  project_root="$(detect_project_root "$project_override")"

  # Gather error context from the various sources
  local error_context=""

  if [[ -n "$error_file" ]]; then
    if [[ ! -f "$error_file" ]]; then
      log_error "Error file not found: $error_file"
      return 1
    fi
    error_context="$(cat "$error_file")"
    log_ok "Reading error from file: $error_file"
  elif [[ "$use_last_error" == true ]]; then
    error_context="$(get_last_error)"
    if [[ -z "$error_context" ]]; then
      log_error "No last error found at ~/.ea/last-error.txt"
      return 1
    fi
    log_ok "Using last error from ~/.ea/last-error.txt"
  elif [[ -n "$error_desc" ]]; then
    error_context="$error_desc"
  else
    log_error "No error description, file, or --last-error provided."
    ea_cmd_debug_usage
    return 1
  fi

  # Gather git context using context-gatherer
  local git_context
  git_context="$(get_git_context "$project_root" 3)"
  
  local git_diff=""
  git_diff="$(git -C "$project_root" diff HEAD~1 HEAD 2>/dev/null || true)"
  if [[ -z "$git_diff" ]]; then
    git_diff="$(git -C "$project_root" diff 2>/dev/null || true)"
  fi

  local changed_files=""
  changed_files="$(git -C "$project_root" diff --name-only HEAD~1 HEAD 2>/dev/null || true)"

  # Gather relevant file contents (files mentioned in the error)
  local relevant_files_content=""
  # Try to extract file paths from the error message (patterns like path/file.ts:LINE)
  local mentioned_files
  mentioned_files="$(echo "$error_context" | grep -oE '[a-zA-Z0-9_./-]+\.(ts|js|py|go|rs|java|tsx|jsx):[0-9]+' | cut -d: -f1 | sort -u || true)"

  for mf in $mentioned_files; do
    local full_path=""
    if [[ -f "$project_root/$mf" ]]; then
      full_path="$project_root/$mf"
    elif [[ -f "$mf" ]]; then
      full_path="$mf"
    fi
    if [[ -n "$full_path" ]]; then
      relevant_files_content="${relevant_files_content}

### File: ${mf}
\`\`\`
$(cat "$full_path")
\`\`\`
"
    fi
  done

  # Build the debug prompt using the debug-brief template
  local prompts_dir="$EA_ROOT/prompts"
  local debug_prompt
  debug_prompt="$(cat "$prompts_dir/debug-brief.md")"

  debug_prompt="${debug_prompt}

---

## Error Information

${error_context}
"

  if [[ -n "$relevant_files_content" ]]; then
    debug_prompt="${debug_prompt}
## Relevant Source Files
${relevant_files_content}
"
  fi
  
  local symbol_context
  symbol_context="$(get_symbol_context "$project_root" "$error_context")"
  if [[ -n "$symbol_context" ]]; then
    debug_prompt="${debug_prompt}

${symbol_context}
"
    log_ok "Included symbol search results in context"
  fi

  if [[ -n "$git_context" ]]; then
    debug_prompt="${debug_prompt}
${git_context}
"
  elif [[ -n "$git_diff" ]]; then
    debug_prompt="${debug_prompt}
## Recent Changes (git diff)
\`\`\`diff
${git_diff}
\`\`\`
"
  fi

  if [[ -n "$changed_files" ]]; then
    debug_prompt="${debug_prompt}
## Recently Changed Files
${changed_files}
"
  fi

  log_step "Analyzing error with AI (debug mode)"

  local output_dir
  output_dir="$(make_ea_output_dir "$project_root" "debug")"
  local brief_file="$output_dir/debug-brief.md"

  if [[ "$force_backend" == "gemini" ]]; then
    call_gemini "$debug_prompt" > "$brief_file"
  elif [[ "$force_backend" == "kilo" ]]; then
    call_kilo_debug "$debug_prompt" > "$brief_file"
  else
    route_task "debug" "$debug_prompt" > "$brief_file"
  fi

  write_latest_pointer "$project_root" "latest-debug" "$output_dir"
  cp "$brief_file" "$project_root/.engineer-agent/debug-brief.md" 2>/dev/null || true

  log_step "Debug brief generated"
  
  local cursor_prompt_file="$output_dir/cursor-prompt.txt"
  cat > "$cursor_prompt_file" <<EOF
Follow the debug brief in $brief_file to fix this bug.

The debug brief contains:
- Error analysis and root cause
- Relevant files with line numbers
- Suggested fix with exact changes needed

After fixing, verify there are no TypeScript/lint errors in the changed files.
EOF

  if [[ "$open_in_cursor" == true ]]; then
    open_in_editor "$brief_file" "$project_root"
  fi

  cat <<EOF

Debug brief saved to: ${brief_file}
Cursor prompt saved to: ${cursor_prompt_file}

${BOLD}${CYAN}Next steps — Cursor Debug Workflow:${RESET}

  1. Open your project in Cursor:
       ${GREEN}cursor "${project_root}"${RESET}

  2. Open Cursor's Agent Mode (Cmd+L or Ctrl+L)

  3. Paste this prompt:
       ${YELLOW}Follow the debug brief in .engineer-agent/debug-brief.md to fix this bug.${RESET}
       (Latest run: $output_dir)

  4. Cursor will read the brief, navigate to the files, and apply the fix
     using its full editor context (LSP, types, open files).

To view the brief:
  cat "${brief_file}"

EOF
}
