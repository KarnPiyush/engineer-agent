#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
source "$EA_ROOT/lib/context-gatherer.sh"

# execute_with_stepping PROMPT PROJECT_ROOT
# Execute Kilo with step-by-step confirmation
execute_with_stepping() {
  local prompt="$1"
  local project_root="$2"
  
  local current_step=1
  local in_block=0
  local pending_writes=()
  
  log_warn "Step mode enabled - you will be prompted before each file write"
  
  route_task "ship-execute" "$prompt" | while IFS= read -r line; do
    echo "$line"
    
    if [[ "$line" == \`\`\`FILE_WRITE:* ]]; then
      in_block=1
      pending_writes+=("$line")
      continue
    fi
    
    if [[ "$in_block" -eq 1 ]]; then
      pending_writes+=("$line")
      if [[ "$line" == \`\`\` ]]; then
        in_block=0
        
        if [[ ! -t 0 ]]; then
          printf '%s\n' "${pending_writes[@]}" | parse_and_apply_file_writes "$project_root" || true
        else
          echo ""
          printf "${YELLOW}Step %d:${RESET}\n" "$current_step"
          printf "${BOLD}Execute these changes? [y/n/s (skip)]: ${RESET}"
          read -r confirm
          
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            printf '%s\n' "${pending_writes[@]}" | parse_and_apply_file_writes "$project_root" || true
            current_step=$((current_step + 1))
          elif [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            log_warn "Skipped step $current_step"
            current_step=$((current_step + 1))
          else
            log_warn "Aborted by user"
            return 1
          fi
        fi
        pending_writes=()
      fi
    fi
  done
}

ea_cmd_ship_usage() {
  cat <<EOF
Usage: ea ship "feature description" [--breakdown] [--step] [--path /path/to/project]

Plan a feature with Gemini Pro, then execute with Kilo Code CLI agents.

Arguments:
  FEATURE_DESCRIPTION  What to build

Options:
  --breakdown    Show plan only, do not execute
  --step         Pause before each Kilo execution step for confirmation
  --path         Project path override (default: auto-detect)
  -h, --help     Show this help message

Workflow:
  1. Gemini Pro generates a feature plan (spec + architecture + tasks)
  2. Plan is shown for review
  3. If confirmed, Kilo Code CLI executes the plan step-by-step

Examples:
  ea ship "add rate limiting to API endpoints"
  ea ship "implement dark mode" --breakdown
  ea ship "add payment integration" --step
EOF
}

ea_cmd_ship() {
  local feature=""
  local breakdown_only=false
  local step_mode=false
  local project_override=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --breakdown)
        breakdown_only=true
        ;;
      --step)
        step_mode=true
        ;;
      --path)
        project_override="${2:-}"
        shift
        ;;
      -h|--help)
        ea_cmd_ship_usage
        return 0
        ;;
      *)
        if [[ -z "$feature" ]]; then
          feature="$1"
        else
          feature="$feature $1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$feature" ]]; then
    log_error "Missing feature description."
    ea_cmd_ship_usage
    return 1
  fi

  local project_root
  project_root="$(detect_project_root "$project_override")"
  local prompts_dir="$EA_ROOT/prompts"
  local output_dir
  output_dir="$(make_ea_output_dir "$project_root" "ship-plan")"

  # --- Phase 1: Plan (Gemini Pro) ---
  log_step "Phase 1: Generating feature plan (Gemini Pro)"

  # Gather project context (README, structure, git, requirement)
  local req_file
  req_file="$(mktemp)"
  trap 'rm -f "${req_file:-}"' EXIT

  get_planning_context "$project_root" "$feature" > "$req_file"

  # Step 1: Spec
  log_step "Step 1/3: Generating engineering spec"
  local step1_prompt
  step1_prompt="$(render_prompt "$prompts_dir/rephrase.md" "Raw Requirement" "$req_file")"
  route_task "ship-plan" "$step1_prompt" > "$output_dir/spec.md"
  log_ok "Spec saved to $output_dir/spec.md"

  # Step 2: Architecture
  log_step "Step 2/3: Generating architecture"
  local step2_prompt
  step2_prompt="$(render_prompt "$prompts_dir/architect.md" "Engineering Specification" "$output_dir/spec.md")"
  route_task "ship-plan" "$step2_prompt" > "$output_dir/architecture.md"
  log_ok "Architecture saved to $output_dir/architecture.md"

  # Step 3: Implementation plan
  log_step "Step 3/3: Generating implementation plan"
  local step3_prompt
  step3_prompt="$(render_prompt "$prompts_dir/senior-swe.md" \
    "Engineering Specification" "$output_dir/spec.md" \
    "Architecture Decision Record" "$output_dir/architecture.md")"
  route_task "ship-plan" "$step3_prompt" > "$output_dir/plan.md"
  log_ok "Plan saved to $output_dir/plan.md"
  write_latest_pointer "$project_root" "latest-ship-plan" "$output_dir"

  # Show the plan
  log_step "Feature Plan"
  cat "$output_dir/plan.md"

  if [[ "$breakdown_only" == true ]]; then
    log_step "Breakdown complete (--breakdown flag set, not executing)"
    cat <<EOF

Artifacts generated:
  - $output_dir/spec.md
  - $output_dir/architecture.md
  - $output_dir/plan.md

To execute this plan with Kilo agents, run:
  ea ship "$feature"
EOF
    return 0
  fi

  # --- Phase 2: Execute (Kilo Code CLI) ---
  echo ""
  
  if [[ "$EA_DRY_RUN" == "true" ]]; then
    log_warn "Dry run mode - not executing"
    return 0
  fi
  
  if [[ ! -t 0 ]]; then
    log_warn "Non-interactive mode - proceeding with implementation"
  else
    printf "${BOLD}Proceed with implementation? [y/n]: ${RESET}"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      log_warn "Aborted. Plan saved at $output_dir/plan.md"
      return 0
    fi
  fi

  log_step "Phase 2: Executing plan with Kilo Code CLI"

  local execute_prompt="You are a senior software engineer. Execute the implementation plan below.

Work through each task in order. For each task:
1. Create or modify the specified files
2. Follow the patterns and conventions described
3. Handle the edge cases listed
4. Keep changes minimal and focused

Implementation Plan:
$(cat "$output_dir/plan.md")

Engineering Specification:
$(cat "$output_dir/spec.md")

Architecture:
$(cat "$output_dir/architecture.md")

Execute each task now. Create/modify files as specified in the plan. Use FILE_WRITE blocks when creating or modifying files."

  if [[ "$step_mode" == true ]]; then
    execute_with_stepping "$execute_prompt" "$project_root"
  else
    route_task "ship-execute" "$execute_prompt" | parse_and_apply_file_writes "$project_root"
  fi

  log_step "Ship complete"
  cat <<EOF

Feature shipped: $feature

Artifacts:
  - $output_dir/spec.md
  - $output_dir/architecture.md
  - $output_dir/plan.md

Next steps:
  1. Review changes: ea review
  2. Commit: ea commit
  3. Push: git push
EOF
}
