#!/bin/bash
# Model routing and configuration for engineer-agent
# Handles --model flag and .ea-config.json routing rules

set -euo pipefail

# ---------------------------------------------------------------------------
# Config file detection
# ---------------------------------------------------------------------------

EA_PROJECT_CONFIG="${EA_PROJECT_CONFIG:-.ea-config.json}"

get_project_config() {
  local project_root="${1:-.}"
  local config_file="$project_root/$EA_PROJECT_CONFIG"
  
  if [[ -f "$config_file" ]]; then
    echo "$config_file"
  elif [[ -f "$project_root/.ea.json" ]]; then
    echo "$project_root/.ea.json"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Model resolution
# ---------------------------------------------------------------------------

# resolve_model TASK_TYPE [USER_MODEL_OVERRIDE]
# Returns the model to use for a given task
# Priority: user override > project config > global config > default
resolve_model() {
  local task_type="$1"
  local user_override="${2:-}"
  
  if [[ -n "$user_override" ]]; then
    echo "$user_override"
    return
  fi
  
  local project_config
  project_config="$(get_project_config "$(pwd)")"
  
  if [[ -n "$project_config" ]] && command -v jq >/dev/null 2>&1; then
    local project_model
    project_model="$(jq -r ".model_preferences.\"$task_type\" // empty" "$project_config" 2>/dev/null || true)"
    if [[ -n "$project_model" && "$project_model" != "null" ]]; then
      echo "$project_model"
      return
    fi
    
    local project_default
    project_default="$(jq -r ".model_preferences.default // empty" "$project_config" 2>/dev/null || true)"
    if [[ -n "$project_default" && "$project_default" != "null" ]]; then
      echo "$project_default"
      return
    fi
  fi
  
  local global_model
  global_model="$(read_ea_config ".model_preferences.\"$task_type\"")"
  if [[ -n "$global_model" ]]; then
    echo "$global_model"
    return
  fi
  
  echo "auto"
}

# ---------------------------------------------------------------------------
# Routing rules
# ---------------------------------------------------------------------------

# apply_routing_rules TASK_TYPE PROMPT
# Applies routing rules from config to decide between Gemini and Kilo
apply_routing_rules() {
  local task_type="$1"
  local prompt="$2"
  
  local project_config
  project_config="$(get_project_config "$(pwd)")"
  
  if [[ -z "$project_config" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  
  local rules
  rules="$(jq -r '.routing_rules // []' "$project_config" 2>/dev/null || echo "[]")"
  
  local rule_count
  rule_count="$(echo "$rules" | jq 'length' 2>/dev/null || echo "0")"
  
  for i in $(seq 0 $((rule_count - 1))); do
    local rule
    rule="$(echo "$rules" | jq -r ".[$i]" 2>/dev/null || continue)"
    
    local condition
    condition="$(echo "$rule" | jq -r '.condition // empty' 2>/dev/null)"
    local backend
    backend="$(echo "$rule" | jq -r '.backend // empty' 2>/dev/null)"
    
    case "$condition" in
      "file_size_gt")
        local threshold
        threshold="$(echo "$rule" | jq -r '.value // 0' 2>/dev/null)"
        local file_path
        file_path="$(echo "$rule" | jq -r '.file // empty' 2>/dev/null)"
        
        if [[ -n "$file_path" && -f "$file_path" ]]; then
          local file_size
          file_size="$(wc -c < "$file_path" 2>/dev/null || echo "0")"
          if [[ "$file_size" -gt "$threshold" ]]; then
            echo "$backend"
            return
          fi
        fi
        ;;
      *)
        ;;
    esac
  done
  
  return 1
}

# ---------------------------------------------------------------------------
# Model to backend mapping
# ---------------------------------------------------------------------------

# map_model_to_backend MODEL
# Maps a model name to a backend (gemini or kilo)
map_model_to_backend() {
  local model="$1"
  
  case "$model" in
    gemini|gemini-pro|gemini-pro-1.5)
      echo "gemini"
      ;;
    kilo|kilo-code|qwen|deepseek|kimi|qwen3-coder|deepseek-r1)
      echo "kilo"
      ;;
    auto|"")
      echo "auto"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# call_model TASK_TYPE PROMPT [USER_MODEL_OVERRIDE]
# Main entry point for model routing with override support
call_model() {
  local task_type="$1"
  local prompt="$2"
  local user_model="${3:-auto}"
  
  local resolved_model
  resolved_model="$(resolve_model "$task_type" "$user_model")"
  
  if is_verbose; then
    log_ok "[router] Resolved model: $resolved_model for task: $task_type"
  fi
  
  local backend
  backend="$(map_model_to_backend "$resolved_model")"
  
  case "$backend" in
    gemini)
      if is_verbose; then
        log_ok "[router] Using Gemini Pro"
      fi
      call_gemini "$prompt"
      ;;
    kilo)
      if is_verbose; then
        log_ok "[router] Using Kilo"
      fi
      call_kilo "$prompt" "$task_type"
      ;;
    auto)
      route_task "$task_type" "$prompt"
      ;;
    *)
      log_error "Unknown model: $resolved_model"
      return 1
      ;;
  esac
}
