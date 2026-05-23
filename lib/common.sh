#!/bin/bash
# Shared helpers for engineer-agent command modules.

set -euo pipefail

# ---------------------------------------------------------------------------
# Global state directories
# ---------------------------------------------------------------------------
EA_GLOBAL_DIR="${HOME}/.ea"
EA_CONFIG_FILE="${EA_GLOBAL_DIR}/config.json"
EA_QUOTA_FILE="${EA_GLOBAL_DIR}/quota.json"
EA_CACHE_DIR="${EA_GLOBAL_DIR}/cache"
EA_PROJECT_CONFIG=".ea-config.json"

init_ea_global() {
  mkdir -p "$EA_GLOBAL_DIR"
  mkdir -p "$EA_CACHE_DIR"
  chmod 700 "$EA_GLOBAL_DIR"
  
  if [[ ! -f "$EA_CONFIG_FILE" ]]; then
    cat > "$EA_CONFIG_FILE" <<'EOF'
{
  "version": "1.0",
  "model_preferences": {
    "default": "auto",
    "plan": "gemini-pro",
    "fix": "kilo",
    "debug": "kilo",
    "review": "auto",
    "commit": "kilo"
  },
  "routing_rules": [],
  "verbose": false,
  "dry_run": false
}
EOF
  fi
  
  if [[ ! -f "$EA_QUOTA_FILE" ]]; then
    cat > "$EA_QUOTA_FILE" <<'EOF'
{
  "total_input_tokens": 0,
  "total_output_tokens": 0,
  "total_calls": 0,
  "last_updated": ""
}
EOF
  fi
}

init_ea_global

# ---------------------------------------------------------------------------
# Config management
# ---------------------------------------------------------------------------
read_ea_config() {
  if [[ -f "$EA_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$EA_CONFIG_FILE" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

write_ea_config() {
  local key="$1"
  local value="$2"
  if command -v jq >/dev/null 2>&1 && [[ -f "$EA_CONFIG_FILE" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    jq --argjson val "$value" "$key = \$val" "$EA_CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$EA_CONFIG_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Verbose and dry-run mode
# ---------------------------------------------------------------------------
EA_VERBOSE="${EA_VERBOSE:-false}"
EA_DRY_RUN="${EA_DRY_RUN:-false}"

is_verbose() {
  [[ "$EA_VERBOSE" == "true" ]]
}

is_dry_run() {
  [[ "$EA_DRY_RUN" == "true" ]]
}

# ---------------------------------------------------------------------------
# Terminal colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  GREEN="\033[0;32m"
  CYAN="\033[0;36m"
  YELLOW="\033[0;33m"
  RED="\033[0;31m"
  RESET="\033[0m"
else
  BOLD="" GREEN="" CYAN="" YELLOW="" RED="" RESET=""
fi

log_step()  { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n\n" "$1"; }
log_ok()    { printf "${GREEN}✓ %s${RESET}\n" "$1"; }
log_warn()  { printf "${YELLOW}⚠ %s${RESET}\n" "$1"; }
log_error() { printf "${RED}✗ %s${RESET}\n" "$1" >&2; }

# fail MSG [EXIT_CODE] — descriptive error and exit (default 1)
fail() {
  local msg="${1:-Unknown error}"
  local code="${2:-1}"
  log_error "$msg"
  exit "$code"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Python venv management (structural indexing)
# ---------------------------------------------------------------------------

_ensure_python_venv() {
  local project_root="$1"
  local venv_dir="$project_root/.engineer-agent/.ea_venv"
  local python_cmd="python3"

  if ! command -v "$python_cmd" >/dev/null 2>&1; then
    fail "Python 3 is required but not found. Please install Python 3.10+."
  fi

  # Check version >= 3.10
  if ! "$python_cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >/dev/null 2>&1; then
    local version
    version=$($python_cmd --version 2>&1)
    fail "Python 3.10+ is required. Found: $version"
  fi

  if [[ ! -d "$venv_dir" ]]; then
    log_step "Creating Python virtual environment at $venv_dir..."
    "$python_cmd" -m venv "$venv_dir" || fail "Failed to create virtual environment."
  fi

  local python_venv="$venv_dir/bin/python"
  local pip_cmd="$venv_dir/bin/pip"
  
  # Check if code-review-graph is installed by trying to import it
  if ! "$python_venv" -c "import code_review_graph" >/dev/null 2>&1; then
    log_step "Installing code-review-graph and dependencies..."
    if [[ ! -d "$EA_ROOT/code-review-graph" ]]; then
      fail "code-review-graph source not found at $EA_ROOT/code-review-graph"
    fi
    # Use --quiet to keep output clean, but show errors if they happen
    "$pip_cmd" install --quiet -e "$EA_ROOT/code-review-graph[google-embeddings]" || fail "Failed to install code-review-graph."
    log_ok "Python environment ready."
  fi
}

# run_python_tool PROJECT_ROOT TOOL_NAME ARGS...
run_python_tool() {
  local project_root="$1"
  shift
  local tool_name="$1"
  shift
  local venv_dir="$project_root/.engineer-agent/.ea_venv"
  _ensure_python_venv "$project_root"
  "$venv_dir/bin/$tool_name" "$@"
}

# ---------------------------------------------------------------------------
# Tool availability checks
# ---------------------------------------------------------------------------

has_gemini() { command -v gemini >/dev/null 2>&1; }
# Kilo CLI: official package is @kilocode/cli (binary "kilo"); accept "kilo-code" for backwards compatibility
has_kilo()   { command -v kilo >/dev/null 2>&1 || command -v kilo-code >/dev/null 2>&1; }
_get_kilo_cmd() { command -v kilo >/dev/null 2>&1 && echo kilo || echo kilo-code; }

# ---------------------------------------------------------------------------
# Prompt rendering
# ---------------------------------------------------------------------------

# render_prompt TEMPLATE_FILE [LABEL CONTENT_FILE] ...
render_prompt() {
  local template_file="$1"
  shift
  cat "$template_file"
  while [[ $# -ge 2 ]]; do
    printf "\n\n--- %s ---\n\n" "$1"
    cat "$2"
    shift 2
  done
}

# ---------------------------------------------------------------------------
# Prompt helper — backend-native tools (no hardcoded tool names)
# schema/tools.json documents typical Gemini CLI tools for humans; prompts do not
# list specific tool names so Gemini and Kilo each use their CLI's real tools.
# ---------------------------------------------------------------------------
# get_tools_prompt_section — returns text to inject before the user prompt.
get_tools_prompt_section() {
  cat <<'EOS'

--- Tool usage (backend-native) ---
Use the tools your environment exposes to read files, search the codebase, list directories, run shell commands, and edit files as needed. Use only tool names that your CLI actually provides (do not invent names from generic examples).

--- File output for engineer-agent ---
To create or modify a file in your response so engineer-agent can apply it, output a fenced block:

```FILE_WRITE:path/to/file
contents here
```

EOS
}

# ---------------------------------------------------------------------------
# Noise suppression (keytar.node / module resolution on stderr)
# Only filters known benign lines; auth/critical errors pass through.
# ---------------------------------------------------------------------------
_filter_cli_stderr() {
  grep -v -E '(keytar\.node|Cannot find module.*keytar|ENOENT.*node_modules)' 2>/dev/null || cat
}

# ---------------------------------------------------------------------------
# Gemini Pro CLI executor
# ---------------------------------------------------------------------------

# call_gemini PROMPT_TEXT
# Prepends backend-native + FILE_WRITE guidance; filters stderr noise.
call_gemini() {
  local prompt_text="$1"
  require_cmd gemini
  local full_prompt
  full_prompt="$(get_tools_prompt_section)
---
$prompt_text"
  
  if is_verbose; then
    log_step "=== GEMINI PROMPT ==="
    echo "$full_prompt"
    log_step "=== END PROMPT ==="
  fi
  
  local input_tokens
  input_tokens="$(estimate_tokens "$full_prompt")"
  
  local response
  response="$(echo "$full_prompt" | gemini -p "Follow the instructions in the text provided on stdin." 2> >(_filter_cli_stderr >&2))"
  
  local output_tokens
  output_tokens="$(estimate_tokens "$response")"
  
  update_quota "$input_tokens" "$output_tokens"
  
  if is_verbose; then
    log_step "=== GEMINI RESPONSE ==="
    echo "$response"
    log_step "=== END RESPONSE ==="
    log_ok "Tokens: $input_tokens in, $output_tokens out"
  fi
  
  echo "$response"
}

# ---------------------------------------------------------------------------
# Kilo Code CLI executors
# ---------------------------------------------------------------------------

# call_kilo PROMPT_TEXT [MODE]
#   MODE defaults to "code". Other useful values: "debug", "architect"
#   Uses Kilo CLI in non-interactive autonomous mode (kilo run --auto).
call_kilo() {
  local prompt_text="$1"
  local mode="${2:-code}"
  if ! has_kilo; then
    log_error "Kilo CLI not found (required for --backend kilo)."
    log_error "Install: npm install -g @kilocode/cli"
    log_error "Or use Gemini instead: ea fix ... --backend gemini"
    exit 1
  fi

  local kilo_cmd
  kilo_cmd="$(_get_kilo_cmd)"
  local full_prompt
  full_prompt="$(get_tools_prompt_section)
---
$prompt_text"
  
  if is_verbose; then
    log_step "=== KILO PROMPT (mode: $mode) ==="
    echo "$full_prompt"
    log_step "=== END PROMPT ==="
  fi
  
  local input_tokens
  input_tokens="$(estimate_tokens "$full_prompt")"
  
  local response
  response="$("$kilo_cmd" run --auto --agent "$mode" "$full_prompt" 2> >(_filter_cli_stderr >&2))"
  
  local output_tokens
  output_tokens="$(estimate_tokens "$response")"
  
  update_quota "$input_tokens" "$output_tokens"
  
  if is_verbose; then
    log_step "=== KILO RESPONSE ==="
    echo "$response"
    log_step "=== END RESPONSE ==="
    log_ok "Tokens: $input_tokens in, $output_tokens out"
  fi
  
  echo "$response"
}

# call_kilo_debug PROMPT_TEXT
#   Shorthand for invoking Kilo in debug mode (uses DeepSeek R1 free model).
call_kilo_debug() {
  local prompt_text="$1"
  call_kilo "$prompt_text" "debug"
}

# ---------------------------------------------------------------------------
# Task router: picks the best backend for a given task type
# ---------------------------------------------------------------------------

# route_task TASK_TYPE PROMPT_TEXT [DIFF_LINES]
#   TASK_TYPE: plan | review | fix | debug | ship | commit | parallel
#   DIFF_LINES: optional, number of lines in the diff (used for review routing)
#
#   Routing logic:
#     plan/architect   → Gemini Pro  (large context, planning)
#     review <500 loc  → Kilo        (DeepSeek R1, free)
#     review >=500 loc → Gemini Pro  (large context)
#     fix              → Kilo        (Qwen3 Coder, code mode)
#     debug            → Kilo        (DeepSeek R1, debug mode)
#     ship (plan)      → Gemini Pro
#     ship (execute)   → Kilo        (Qwen3 Coder, code mode)
#     commit           → Kilo        (Kimi K2, fast)
#     parallel         → Kilo        (Qwen3 Coder, code mode)
#
#   Fallback: if the preferred tool is missing, the other is tried.
route_task() {
  local task_type="$1"
  local prompt_text="$2"
  local diff_lines="${3:-0}"

  case "$task_type" in
    plan|architect)
      if has_gemini; then
        log_ok "[router] $task_type → gemini pro"
        call_gemini "$prompt_text"
      elif has_kilo; then
        log_warn "[router] gemini unavailable, falling back to kilo for $task_type"
        call_kilo "$prompt_text" "architect"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    review)
      if [[ "$diff_lines" -ge 500 ]] && has_gemini; then
        log_ok "[router] review ($diff_lines lines) → gemini pro (large diff)"
        call_gemini "$prompt_text"
      elif has_kilo; then
        log_ok "[router] review ($diff_lines lines) → kilo (DeepSeek R1, code mode)"
        call_kilo "$prompt_text" "code"
      elif has_gemini; then
        log_ok "[router] review → gemini pro (kilo unavailable)"
        call_gemini "$prompt_text"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    fix)
      if has_kilo; then
        log_ok "[router] fix → kilo (Qwen3 Coder, code mode)"
        call_kilo "$prompt_text" "code"
      elif has_gemini; then
        log_warn "[router] kilo unavailable, falling back to gemini for fix"
        call_gemini "$prompt_text"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    debug)
      if has_kilo; then
        log_ok "[router] debug → kilo (DeepSeek R1, debug mode)"
        call_kilo_debug "$prompt_text"
      elif has_gemini; then
        log_warn "[router] kilo unavailable, falling back to gemini for debug"
        call_gemini "$prompt_text"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    commit)
      if has_kilo; then
        log_ok "[router] commit → kilo (Kimi K2, code mode)"
        call_kilo "$prompt_text" "code"
      elif has_gemini; then
        log_warn "[router] kilo unavailable, falling back to gemini for commit"
        call_gemini "$prompt_text"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    ship-plan)
      # Planning phase of ea ship — uses Gemini
      if has_gemini; then
        log_ok "[router] ship (plan) → gemini pro"
        call_gemini "$prompt_text"
      elif has_kilo; then
        log_warn "[router] gemini unavailable, falling back to kilo for ship planning"
        call_kilo "$prompt_text" "architect"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    ship-execute)
      # Execution phase of ea ship — uses Kilo
      if has_kilo; then
        log_ok "[router] ship (execute) → kilo (Qwen3 Coder, code mode)"
        call_kilo "$prompt_text" "code"
      elif has_gemini; then
        log_warn "[router] kilo unavailable, falling back to gemini for ship execution"
        call_gemini "$prompt_text"
      else
        log_error "No AI backend available. Install gemini or Kilo CLI (npm install -g @kilocode/cli)."
        return 1
      fi
      ;;

    *)
      log_error "[router] Unknown task type: $task_type"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# FILE_WRITE artifact capture — parse LLM stdout for FILE_WRITE blocks and write files
# Format: ```FILE_WRITE:path/to/file
#         contents...
#         ```
# parse_and_apply_file_writes PROJECT_ROOT — reads stdin, writes FILE_WRITE blocks under PROJECT_ROOT, echoes rest to stdout
parse_and_apply_file_writes() {
  local project_root="${1:?Missing project_root}"
  local inblock=0
  local outpath=""
  local line

  local fence='```'
  while IFS= read -r line; do
    # Match opening fence: ```FILE_WRITE:path/to/file
    if [[ "$line" == "${fence}FILE_WRITE:"* ]]; then
      local relpath="${line#"${fence}FILE_WRITE:"}"
      relpath="${relpath#"${relpath%%[![:space:]]*}"}"
      relpath="${relpath%"${relpath##*[![:space:]]}"}"
      if [[ -z "$relpath" ]]; then
        inblock=0
        printf '%s\n' "$line"
        continue
      fi
      inblock=1
      outpath="${project_root}/${relpath}"
      outpath="${outpath#./}"
      mkdir -p "$(dirname "$outpath")" 2>/dev/null || true
      : > "$outpath"
      continue
    fi
    if [[ "$inblock" -eq 1 ]]; then
      if [[ "$line" == "$fence" ]]; then
        inblock=0
        log_ok "Wrote: $outpath"
        continue
      fi
      printf '%s\n' "$line" >> "$outpath"
      continue
    fi
    printf '%s\n' "$line"
  done
}

# ---------------------------------------------------------------------------
# Project path detection
# ---------------------------------------------------------------------------

# detect_project_root [override_path]
detect_project_root() {
  local override_path="${1:-}"
  if [[ -n "$override_path" ]]; then
    if [[ ! -d "$override_path" ]]; then
      log_error "Project path does not exist: $override_path"
      exit 1
    fi
    (cd "$override_path" && pwd)
    return
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

# make_ea_output_dir PROJECT_ROOT KEYWORD
# Creates .engineer-agent/YYYYMMDD_HHMMSS_KEYWORD and echoes the path.
# Use for timestamped per-run history (plan, ship-plan, fix, debug).
make_ea_output_dir() {
  local project_root="$1"
  local keyword="$2"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local dir="$project_root/.engineer-agent/${ts}_${keyword}"
  mkdir -p "$dir"
  echo "$dir"
}

# write_latest_pointer PROJECT_ROOT POINTER_NAME OUTPUT_DIR_PATH
# Writes .engineer-agent/POINTER_NAME.txt with one line: OUTPUT_DIR_PATH (for backwards compatibility).
write_latest_pointer() {
  local project_root="$1"
  local pointer_name="$2"
  local output_dir_path="$3"
  local base="$project_root/.engineer-agent"
  mkdir -p "$base"
  printf '%s\n' "$output_dir_path" > "$base/${pointer_name}.txt"
}

# ---------------------------------------------------------------------------
# Last-error helpers (shared by fix and debug commands)
# ---------------------------------------------------------------------------

EA_ERROR_FILE="${HOME}/.ea/last-error.txt"

save_last_error() {
  local error_text="$1"
  mkdir -p "$(dirname "$EA_ERROR_FILE")"
  echo "$error_text" > "$EA_ERROR_FILE"
}

get_last_error() {
  if [[ -f "$EA_ERROR_FILE" ]]; then
    cat "$EA_ERROR_FILE"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Token tracking
# ---------------------------------------------------------------------------
estimate_tokens() {
  local text="$1"
  echo -n "$text" | wc -c | awk '{printf "%.0f", $1 / 4}'
}

update_quota() {
  local input_tokens="$1"
  local output_tokens="$2"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  
  if command -v jq >/dev/null 2>&1 && [[ -f "$EA_QUOTA_FILE" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    jq --arg ts "$timestamp" \
       --argjson in_tok "$input_tokens" \
       --argjson out_tok "$output_tokens" \
       '.total_input_tokens += $in_tok | .total_output_tokens += $out_tok | .total_calls += 1 | .last_updated = $ts' \
       "$EA_QUOTA_FILE" > "$tmp_file" && mv "$tmp_file" "$EA_QUOTA_FILE"
  fi
}

get_quota_summary() {
  if [[ -f "$EA_QUOTA_FILE" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '"\(.total_input_tokens) input tokens, \(.total_output_tokens) output tokens, \(.total_calls) calls"' "$EA_QUOTA_FILE"
  else
    echo "No quota data available"
  fi
}

# ---------------------------------------------------------------------------
# Secret scrubbing
# ---------------------------------------------------------------------------
scrub_context() {
  local text="$1"
  echo "$text" | sed -E \
    -e 's/(sk-|api_?key|token|secret|password)["\s:=]+[a-zA-Z0-9_\-]{16,}/$1=REDACTED/g' \
    -e 's/AIza[0-9A-Za-z\-]{35}/AIzaREDACTED/g' \
    -e 's/(ghp|gho|ghu|ghs|ghr)_[0-9a-zA-Z]{36}/ghp_REDACTED/g' \
    -e 's/(xox[pborsa]-[0-9]{10,13})-([0-9a-zA-Z]{5,})/xoxb-REDACTED/g' \
    -e 's/(-----BEGIN [A-Z]+ PRIVATE KEY-----)/-----BEGIN PRIVATE KEY-----/g'
}

# ---------------------------------------------------------------------------
# IDE Integration
# ---------------------------------------------------------------------------
open_in_editor() {
  local file="$1"
  local project_root="${2:-.}"
  
  if command -v cursor >/dev/null 2>&1; then
    log_ok "Opening in Cursor..."
    cursor "$project_root" 2>/dev/null || open "$file"
  elif command -v code >/dev/null 2>&1; then
    log_ok "Opening in VS Code..."
    code "$file"
  else
    log_ok "Opening with default application..."
    open "$file"
  fi
}
