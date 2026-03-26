#!/bin/bash
set -euo pipefail

# Load context-gatherer
# shellcheck disable=SC1091
source "$EA_ROOT/lib/context-gatherer.sh"
# Load model-router
# shellcheck disable=SC1091
source "$EA_ROOT/lib/model-router.sh"

ea_cmd_fix_usage() {
  cat <<EOF
Usage: ea fix [FILE_OR_DESCRIPTION] [--last-error] [--path /path/to/project] [--open] [--cursor] [--model MODEL]

Fix a bug in a file using Kilo Code CLI (Qwen3 Coder, code mode).

Arguments:
  FILE_OR_DESCRIPTION  A file path to fix, or a text description of the problem.
                        If omitted and --last-error is not set, uses staged diff context.

Options:
  --last-error   Use the last captured terminal error (~/.ea/last-error.txt)
  --path         Project path override (default: auto-detect)
  --backend      Force a backend: kilo | gemini (default: auto-route)
  --model        Force a specific model: gemini-pro, kilo, qwen-max, etc.
  --open         Open generated last-fix.md in Cursor after completion
  --cursor       Alias for --open
  -h, --help     Show this help message

Examples:
  ea fix src/auth/login.ts
  ea fix "null pointer in checkout flow"
  ea fix --last-error
  ea fix --last-error --cursor
  ea fix src/auth.ts --model qwen-max
EOF
}

ea_cmd_fix() {
  local target=""
  local use_last_error=false
  local project_override=""
  local force_backend=""
  local model_override=""
  local open_in_cursor=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
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
      --model)
        model_override="${2:-}"
        shift
        ;;
      --open|--cursor)
        open_in_cursor=true
        ;;
      -h|--help)
        ea_cmd_fix_usage
        return 0
        ;;
      *)
        if [[ -z "$target" ]]; then
          target="$1"
        else
          target="$target $1"
        fi
        ;;
    esac
    shift
  done

  local project_root
  project_root="$(detect_project_root "$project_override")"

  # Gather error context
  local error_context=""
  if [[ "$use_last_error" == true ]]; then
    error_context="$(get_last_error)"
    if [[ -z "$error_context" ]]; then
      log_error "No last error found. Run your code first, or pass an error description."
      return 1
    fi
    log_ok "Using last error from ~/.ea/last-error.txt"
  fi

  # Gather file content if target is a file
  local file_content=""
  local target_file=""
  if [[ -n "$target" && -f "$project_root/$target" ]]; then
    target_file="$project_root/$target"
    file_content="$(cat "$target_file")"
    log_ok "Reading file: $target_file"
  elif [[ -n "$target" && -f "$target" ]]; then
    target_file="$target"
    file_content="$(cat "$target_file")"
    log_ok "Reading file: $target_file"
  fi

  # Build the fix prompt
  local fix_prompt=""
  fix_prompt="You are a senior software engineer. Fix the bug described below.

Provide ONLY the corrected code. Be surgical — change the minimum needed to fix the issue.
Explain briefly what was wrong and what you changed.
"

  if [[ -n "$error_context" ]]; then
    fix_prompt="${fix_prompt}
## Error
${error_context}
"
  fi

  if [[ -n "$target" && -z "$file_content" ]]; then
    # Target is a description, not a file
    fix_prompt="${fix_prompt}
## Problem Description
${target}
"
  fi

  if [[ -n "$file_content" ]]; then
    fix_prompt="${fix_prompt}
## File: ${target_file}
\`\`\`
${file_content}
\`\`\`
"
    
    local import_context
    import_context="$(get_import_context "$target_file" "$project_root")"
    if [[ -n "$import_context" ]]; then
      fix_prompt="${fix_prompt}

${import_context}
"
      log_ok "Included import dependencies in context"
    fi
  fi
  
  local git_context
  git_context="$(get_git_context "$project_root" 3)"
  if [[ -n "$git_context" ]]; then
    fix_prompt="${fix_prompt}

${git_context}
"
    log_ok "Included git history in context"
  fi

  # If no target and no last-error, try using git diff for context
  if [[ -z "$target" && "$use_last_error" == false ]]; then
    local diff_content
    diff_content="$(git -C "$project_root" diff 2>/dev/null || true)"
    if [[ -z "$diff_content" ]]; then
      diff_content="$(git -C "$project_root" diff --cached 2>/dev/null || true)"
    fi
    if [[ -z "$diff_content" ]]; then
      log_error "No target file, description, or diff found. Pass a file, description, or --last-error."
      ea_cmd_fix_usage
      return 1
    fi
    fix_prompt="${fix_prompt}
## Current Changes (git diff)
\`\`\`diff
${diff_content}
\`\`\`
"
  fi

  log_step "Generating fix"

  local output_dir
  output_dir="$(make_ea_output_dir "$project_root" "fix")"

  if [[ -n "$force_backend" ]]; then
    if [[ "$force_backend" == "gemini" ]]; then
      call_gemini "$fix_prompt" | parse_and_apply_file_writes "$project_root" | tee "$output_dir/last-fix.md"
    elif [[ "$force_backend" == "kilo" ]]; then
      call_kilo "$fix_prompt" "code" | parse_and_apply_file_writes "$project_root" | tee "$output_dir/last-fix.md"
    else
      route_task "fix" "$fix_prompt" | parse_and_apply_file_writes "$project_root" | tee "$output_dir/last-fix.md"
    fi
  elif [[ -n "$model_override" ]]; then
    call_model "fix" "$fix_prompt" "$model_override" | parse_and_apply_file_writes "$project_root" | tee "$output_dir/last-fix.md"
  else
    route_task "fix" "$fix_prompt" | parse_and_apply_file_writes "$project_root" | tee "$output_dir/last-fix.md"
  fi

  write_latest_pointer "$project_root" "latest-fix" "$output_dir"
  cp "$output_dir/last-fix.md" "$project_root/.engineer-agent/last-fix.md" 2>/dev/null || true

  local fix_output="$output_dir/last-fix.md"
  
  if [[ "$open_in_cursor" == true ]]; then
    open_in_editor "$fix_output" "$project_root"
  fi

  log_step "Fix complete"
  log_ok "Fix output saved to $fix_output"
}
