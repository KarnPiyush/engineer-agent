#!/bin/bash
set -euo pipefail

ea_cmd_commit_usage() {
  cat <<EOF
Usage: ea commit [--conventional] [--verbose] [--path /path/to/project]

Generate a commit message from staged changes using Kilo Code CLI (Kimi K2).

Options:
  --conventional   Enforce Conventional Commits format (default: true)
  --verbose        Include body paragraph explaining WHY
  --path           Project path override (default: auto-detect)
  --backend        Force a backend: kilo | gemini (default: auto-route)
  -h, --help       Show this help message

Examples:
  git add . && ea commit
  ea commit --verbose
  ea commit --backend gemini
EOF
}

ea_cmd_commit() {
  local conventional=true
  local verbose=false
  local project_override=""
  local force_backend=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --conventional)
        conventional=true
        ;;
      --verbose)
        verbose=true
        ;;
      --path)
        project_override="${2:-}"
        shift
        ;;
      --backend)
        force_backend="${2:-}"
        shift
        ;;
      -h|--help)
        ea_cmd_commit_usage
        return 0
        ;;
      *)
        log_error "Unknown option for ea commit: $1"
        ea_cmd_commit_usage
        return 1
        ;;
    esac
    shift
  done

  local project_root
  project_root="$(detect_project_root "$project_override")"

  # Get staged diff
  local diff_content
  diff_content="$(git -C "$project_root" diff --cached 2>/dev/null || true)"

  if [[ -z "$diff_content" ]]; then
    log_warn "No staged changes found. Stage files first: git add <files>"
    log_warn "Trying unstaged diff instead..."
    diff_content="$(git -C "$project_root" diff 2>/dev/null || true)"
  fi

  if [[ -z "$diff_content" ]]; then
    log_error "No changes to commit. Stage or modify files first."
    return 1
  fi

  local diff_lines
  diff_lines="$(echo "$diff_content" | wc -l | tr -d ' ')"
  log_ok "Diff captured: $diff_lines lines"

  # Build the commit message prompt
  local commit_prompt="Generate a commit message for the following staged diff.

Rules:
- Format: <type>(<scope>): <subject>
- Types: feat, fix, refactor, test, docs, chore, perf, ci
- Subject: imperative mood, max 72 chars, no period at end
- Scope: the module or component affected (e.g., auth, api, db, ui)"

  if [[ "$verbose" == true ]]; then
    commit_prompt="${commit_prompt}
- Include a body paragraph explaining WHY the change was made (not what — the diff shows what)
- If there are breaking changes, add a BREAKING CHANGE: footer"
  fi

  commit_prompt="${commit_prompt}

Examples of good commit messages:
  fix(auth): handle expired JWT refresh race condition
  feat(payments): add Stripe webhook idempotency keys
  refactor(db): extract query builder to separate service

Diff:
\`\`\`diff
${diff_content}
\`\`\`

Respond with ONLY the commit message — no explanation, no backticks, no markdown formatting."

  log_step "Generating commit message"

  local commit_msg=""
  if [[ "$force_backend" == "gemini" ]]; then
    commit_msg="$(call_gemini "$commit_prompt")"
  elif [[ "$force_backend" == "kilo" ]]; then
    commit_msg="$(call_kilo "$commit_prompt" "code")"
  else
    commit_msg="$(route_task "commit" "$commit_prompt")"
  fi

  # Clean up the message (strip leading/trailing whitespace and backticks)
  commit_msg="$(echo "$commit_msg" | sed 's/^```//;s/```$//' | sed '/^$/d' | head -20)"

  echo ""
  printf "${BOLD}${CYAN}Generated commit message:${RESET}\n"
  echo "────────────────────────────────"
  echo "$commit_msg"
  echo "────────────────────────────────"
  echo ""

  printf "${BOLD}Use this message? [y/n/e(dit)]: ${RESET}"
  read -r choice

  case "$choice" in
    y|Y)
      git -C "$project_root" commit -m "$commit_msg"
      log_ok "Committed successfully"
      ;;
    e|E)
      # Write to temp file and open in editor
      local tmpfile
      tmpfile="$(mktemp)"
      echo "$commit_msg" > "$tmpfile"
      "${EDITOR:-vi}" "$tmpfile"
      local edited_msg
      edited_msg="$(cat "$tmpfile")"
      rm -f "$tmpfile"
      if [[ -n "$edited_msg" ]]; then
        git -C "$project_root" commit -m "$edited_msg"
        log_ok "Committed with edited message"
      else
        log_warn "Empty message — commit aborted"
      fi
      ;;
    *)
      log_warn "Commit aborted"
      ;;
  esac
}
