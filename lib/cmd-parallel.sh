#!/bin/bash
set -euo pipefail

ea_cmd_parallel_usage() {
  cat <<EOF
Usage: ea parallel "task1" "task2" ["task3" ...] [--path /path/to/project]

Spawn multiple Kilo Code CLI parallel agents, each working on a separate git branch.

Arguments:
  TASKS    One or more task descriptions (each in quotes)

Options:
  --path         Project path override (default: auto-detect)
  -h, --help     Show this help message

Each task will:
  1. Create a new git branch: ea/parallel/<sanitized-task-name>
  2. Run a Kilo Code CLI agent in autonomous mode
  3. Commit changes to its branch
  4. Report completion

Examples:
  ea parallel "fix CSS layout on desktop" "add color picker to notes"
  ea parallel "write unit tests for auth" "refactor database queries" "update API docs"
EOF
}

# Sanitize a task description into a valid git branch name
_sanitize_branch_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//' | head -c 50
}

# Run a single parallel agent (called as background job)
_run_parallel_agent() {
  local task="$1"
  local project_root="$2"
  local branch_name="$3"
  local agent_id="$4"

  local log_file="$project_root/.engineer-agent/parallel-${agent_id}.log"

  {
    echo "=== EA Parallel Agent #${agent_id} ==="
    echo "Task:   $task"
    echo "Branch: $branch_name"
    echo "Start:  $(date)"
    echo "---"
    echo ""

    # Create and checkout branch
    if ! git -C "$project_root" checkout -b "$branch_name" 2>&1; then
      echo "ERROR: Failed to create branch $branch_name"
      return 1
    fi

    # Run Kilo Code CLI in autonomous mode
    if has_kilo; then
      echo "Running Kilo Code CLI agent..."
      local agent_prompt="You are a senior software engineer. Complete this task in the current project:

Task: ${task}

Instructions:
- Make the necessary file changes to complete the task
- Keep changes focused and minimal
- Follow existing code patterns and conventions
- When done, summarize what you changed"

      local kilo_cmd
      kilo_cmd="$(_get_kilo_cmd)"
      "$kilo_cmd" run --auto --agent code "$agent_prompt" 2>&1 || true
    else
      echo "ERROR: Kilo CLI not found (install: npm install -g @kilocode/cli)"
      return 1
    fi

    # Stage and commit changes
    local changes
    changes="$(git -C "$project_root" status --porcelain 2>/dev/null || true)"
    if [[ -n "$changes" ]]; then
      git -C "$project_root" add -A 2>&1
      git -C "$project_root" commit -m "feat(parallel): ${task}" 2>&1 || true
      echo ""
      echo "Changes committed to branch: $branch_name"
    else
      echo ""
      echo "No file changes detected for this task."
    fi

    echo ""
    echo "=== Agent #${agent_id} complete: $(date) ==="

  } > "$log_file" 2>&1

  return 0
}

ea_cmd_parallel() {
  local tasks=()
  local project_override=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --path)
        project_override="${2:-}"
        shift
        ;;
      -h|--help)
        ea_cmd_parallel_usage
        return 0
        ;;
      *)
        tasks+=("$1")
        ;;
    esac
    shift
  done

  if [[ ${#tasks[@]} -eq 0 ]]; then
    log_error "No tasks provided."
    ea_cmd_parallel_usage
    return 1
  fi

  if ! has_kilo; then
    log_error "Kilo CLI not found. Install: npm install -g @kilocode/cli"
    return 1
  fi

  local project_root
  project_root="$(detect_project_root "$project_override")"

  # Ensure we're in a git repo
  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "Not a git repository: $project_root"
    return 1
  fi

  # Save current branch to return to later
  local original_branch
  original_branch="$(git -C "$project_root" branch --show-current 2>/dev/null || echo "main")"

  local output_dir="$project_root/.engineer-agent"
  mkdir -p "$output_dir"

  log_step "Spawning ${#tasks[@]} parallel agents"

  local pids=()
  local branches=()
  local agent_id=1

  for task in "${tasks[@]}"; do
    local sanitized
    sanitized="$(_sanitize_branch_name "$task")"
    local branch_name="ea/parallel/${sanitized}"
    branches+=("$branch_name")

    printf "  ${CYAN}Agent #%d:${RESET} %s → ${YELLOW}%s${RESET}\n" "$agent_id" "$task" "$branch_name"

    # Each agent needs to run from the original branch as a base
    # We launch each as a background process
    (
      cd "$project_root"
      _run_parallel_agent "$task" "$project_root" "$branch_name" "$agent_id"
    ) &

    pids+=($!)
    agent_id=$((agent_id + 1))
  done

  echo ""
  log_ok "All agents launched. Waiting for completion..."
  echo ""

  # Wait for all agents to complete
  local failed=0
  agent_id=1
  for pid in "${pids[@]}"; do
    if wait "$pid"; then
      log_ok "Agent #${agent_id} completed (branch: ${branches[$((agent_id-1))]})"
    else
      log_error "Agent #${agent_id} failed (check .engineer-agent/parallel-${agent_id}.log)"
      failed=$((failed + 1))
    fi
    agent_id=$((agent_id + 1))
  done

  # Return to original branch
  git -C "$project_root" checkout "$original_branch" 2>/dev/null || true

  log_step "Parallel execution complete"

  echo "Branches created:"
  for branch in "${branches[@]}"; do
    printf "  ${GREEN}%s${RESET}\n" "$branch"
  done

  echo ""
  echo "To review a branch:"
  echo "  git diff ${original_branch}..ea/parallel/<branch-name>"
  echo ""
  echo "To merge a branch:"
  echo "  git merge ea/parallel/<branch-name>"
  echo ""
  echo "Agent logs: $output_dir/parallel-*.log"

  if [[ $failed -gt 0 ]]; then
    log_warn "$failed agent(s) failed. Check logs for details."
    return 1
  fi
}
