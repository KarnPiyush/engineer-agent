#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
source "$EA_ROOT/lib/context-gatherer.sh"
# shellcheck disable=SC1091
source "$EA_ROOT/lib/model-router.sh"

ea_cmd_plan_usage() {
  cat <<EOF
Usage: ea plan "requirement text" [--path /path/to/project] [--open] [--cursor] [--model MODEL]
       ea plan --req "requirement text" [--path /path/to/project]

Options:
  --req   Raw requirement text
  --path  Optional project path override (default: auto-detect from current directory)
  --open  Open generated tasks.md in Cursor after completion
  --cursor Alias for --open
  --model Force a specific model: gemini-pro, kilo, qwen-max, etc.
  -h      Show this help message
EOF
}

ea_cmd_plan() {
  local req=""
  local project_override=""
  local open_in_cursor=false
  local model_override=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --req)
        req="${2:-}"
        shift
        ;;
      --path)
        project_override="${2:-}"
        shift
        ;;
      --open|--cursor)
        open_in_cursor=true
        ;;
      --model)
        model_override="${2:-}"
        shift
        ;;
      -h|--help)
        ea_cmd_plan_usage
        return 0
        ;;
      *)
        if [[ -z "$req" ]]; then
          req="$1"
        else
          req="$req $1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$req" ]]; then
    log_error "Missing requirement text."
    ea_cmd_plan_usage
    return 1
  fi

  local project_root
  project_root="$(detect_project_root "$project_override")"
  local prompts_dir="$EA_ROOT/prompts"
  local output_dir
  output_dir="$(make_ea_output_dir "$project_root" "plan")"

  local req_file
  req_file="$(mktemp)"
  trap 'rm -f "${req_file:-}"' EXIT

  log_step "Step 0: Building multi-source project context (README, structure, git, requirement)"
  get_planning_context "$project_root" "$req" > "$req_file"
  log_ok "Context gathered"

  log_step "Step 1: Rephrasing requirement into engineering spec"
  local step1_prompt
  step1_prompt="$(render_prompt "$prompts_dir/rephrase.md" "Raw Requirement" "$req_file")"
  call_model "plan" "$step1_prompt" "$model_override" | parse_and_apply_file_writes "$project_root" > "$output_dir/spec.md"
  log_ok "Spec saved to $output_dir/spec.md"

  log_step "Step 2: Generating Architecture Decision Record"
  local step2_prompt
  step2_prompt="$(render_prompt "$prompts_dir/architect.md" "Engineering Specification" "$output_dir/spec.md")"
  call_model "plan" "$step2_prompt" "$model_override" | parse_and_apply_file_writes "$project_root" > "$output_dir/architecture.md"
  log_ok "Architecture saved to $output_dir/architecture.md"

  log_step "Step 3: Generating implementation plan"
  local step3_prompt
  step3_prompt="$(render_prompt "$prompts_dir/senior-swe.md" \
    "Engineering Specification" "$output_dir/spec.md" \
    "Architecture Decision Record" "$output_dir/architecture.md")"
  call_model "plan" "$step3_prompt" "$model_override" | parse_and_apply_file_writes "$project_root" > "$output_dir/plan.md"
  log_ok "Plan saved to $output_dir/plan.md"

  log_step "Step 4: Generating Cursor-ready task file"
  local step4_prompt
  step4_prompt="$(render_prompt "$prompts_dir/senior-swe.md" "Implementation Plan" "$output_dir/plan.md")"
  call_model "plan" "$step4_prompt" "$model_override" | parse_and_apply_file_writes "$project_root" > "$output_dir/tasks.md"
  log_ok "Tasks saved to $output_dir/tasks.md"

  log_step "Done"
  
  local cursor_prompt_file="$output_dir/cursor-prompt.txt"
  cat > "$cursor_prompt_file" <<EOF
Follow the instructions in $output_dir/tasks.md exactly.

The tasks.md file contains a detailed implementation plan that was generated based on:
- Specification: $output_dir/spec.md
- Architecture: $output_dir/architecture.md
- Implementation Plan: $output_dir/plan.md

Work through each task in order, creating/modifying files as specified.
EOF

  write_latest_pointer "$project_root" "latest-plan" "$output_dir"

  if [[ "$open_in_cursor" == true ]]; then
    open_in_editor "$output_dir/tasks.md" "$project_root"
  fi

  cat <<EOF
Project:       $project_root
Artifacts dir: $output_dir

Generated files:
  - $output_dir/spec.md
  - $output_dir/architecture.md
  - $output_dir/plan.md
  - $output_dir/tasks.md
  - $output_dir/cursor-prompt.txt

Next steps:
  1. Open project in Cursor:
       cursor "$project_root"
  2. In Cursor chat:
       "Follow the instructions in $output_dir/tasks.md exactly."
       Or paste the contents of $cursor_prompt_file
EOF
}
