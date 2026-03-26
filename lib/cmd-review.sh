#!/bin/bash
set -euo pipefail

# Load cache-manager
# shellcheck disable=SC1091
source "$EA_ROOT/lib/cache-manager.sh"

ea_cmd_review_usage() {
  cat <<EOF
Usage: ea review [--diff-args "REF1 REF2"] [--path /path/to/project] [--backend kilo|gemini] [--no-cache]

Run AI code review on git diffs.

Routing:
  - Diffs <500 lines  → Kilo Code CLI (DeepSeek R1, free)
  - Diffs >=500 lines → Gemini Pro (large context)
  - Override with --backend flag

Options:
  --diff-args  Arguments for git diff (default: "HEAD~1 HEAD")
  --path       Optional project path override (default: auto-detect from current directory)
  --backend    Force a backend: kilo | gemini (default: auto-route based on diff size)
  --no-cache   Disable caching, always run fresh review
  -h           Show this help message

Examples:
  ea review
  ea review --diff-args "main..feature-branch"
  ea review --backend gemini
EOF
}

ea_cmd_review() {
  local project_override=""
  local diff_args="HEAD~1 HEAD"
  local force_backend=""
  local use_cache=true

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --path)
        project_override="${2:-}"
        shift
        ;;
      --diff-args)
        diff_args="${2:-}"
        shift
        ;;
      --backend)
        force_backend="${2:-}"
        shift
        ;;
      --no-cache)
        use_cache=false
        ;;
      -h|--help)
        ea_cmd_review_usage
        return 0
        ;;
      *)
        log_error "Unknown option for ea review: $1"
        ea_cmd_review_usage
        return 1
        ;;
    esac
    shift
  done

  local project_root
  project_root="$(detect_project_root "$project_override")"

  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "Not a git repository: $project_root"
    return 1
  fi

  log_step "Computing git diff ($diff_args)"
  local diff_file
  diff_file="$(mktemp)"
  # shellcheck disable=SC2086
  git -C "$project_root" diff $diff_args > "$diff_file" 2>/dev/null || true

  if [[ ! -s "$diff_file" ]]; then
    log_warn "No diff found for: git diff $diff_args"
    log_warn "Trying staged changes (git diff --cached) instead..."
    git -C "$project_root" diff --cached > "$diff_file" 2>/dev/null || true
  fi

  if [[ ! -s "$diff_file" ]]; then
    log_warn "No changes to review. Diff is empty."
    rm -f "$diff_file"
    return 0
  fi

  local diff_lines
  diff_lines="$(wc -l < "$diff_file" | tr -d ' ')"
  log_ok "Diff captured: $diff_lines lines"

  local prompts_dir="$EA_ROOT/prompts"
  local review_prompt
  review_prompt="$(render_prompt "$prompts_dir/review.md" "Git Diff" "$diff_file")"

  log_step "Running code review"

  local review_dir="$project_root/.code-review"
  mkdir -p "$review_dir"

  local timestamp review_file
  timestamp="$(date +%Y%m%d_%H%M%S)"
  review_file="$review_dir/${timestamp}_review.md"

  local review_result=""
  local cache_hit=false
  
  if [[ "$use_cache" == true ]]; then
    local diff_content
    diff_content="$(cat "$diff_file")"
    if review_result="$(get_cached_or_run_review "$diff_content" "v1" "$review_prompt")"; then
      if [[ -s "$review_file" ]] 2>/dev/null || grep -q "." <<< "$review_result"; then
        cache_hit=true
      fi
    fi
  fi
  
  if [[ "$cache_hit" == false ]]; then
    if [[ "$force_backend" == "gemini" ]]; then
      log_ok "[review] Using Gemini Pro (forced via --backend)"
      review_result="$(call_gemini "$review_prompt")"
    elif [[ "$force_backend" == "kilo" ]]; then
      log_ok "[review] Using Kilo Code CLI (forced via --backend)"
      review_result="$(call_kilo "$review_prompt" "code")"
    else
      review_result="$(route_task "review" "$review_prompt" "$diff_lines")"
    fi
    
    if [[ "$use_cache" == true ]]; then
      local cache_key
      cache_key="$(get_cache_key "$(cat "$diff_file")" "v1")"
      save_review "$cache_key" "$review_result"
    fi
  else
    log_ok "[review] Using cached review result"
  fi
  
  echo "$review_result" > "$review_file"

  rm -f "$diff_file"

  log_step "Review complete"
  
  if [[ "$cache_hit" == true ]]; then
    log_ok "Retrieved from cache (use --no-cache to run fresh review)"
  fi
  
  cat <<EOF
Review saved to: $review_file
To read the review:
  cat "$review_file"
EOF
}
