#!/bin/bash
# Error capture and terminal history utilities for engineer-agent

set -euo pipefail

# ---------------------------------------------------------------------------
# Shell Integration
# ---------------------------------------------------------------------------

# generate_shell_snippet [shell]
# Outputs shell snippet for error capture
generate_shell_snippet() {
  local shell="${1:-bash}"
  
  local snippet=""
  
  case "$shell" in
    zsh)
      snippet='
# Engineer Agent error capture
autoload -Uz add-zsh-hook

_ea_capture_last_error() {
  if [[ -n "$TMUX" ]]; then
    tmux capture-pane -p -S -50 > /tmp/tmux-capture-$$.txt 2>/dev/null || true
  fi
  if [[ -n "$LAST_EXIT_CODE" ]] && [[ "$LAST_EXIT_CODE" -ne 0 ]]; then
    print -s "exit $LAST_EXIT_CODE" 2>/dev/null || true
  fi
}

add-zsh-hook precmd _ea_capture_last_error
'
      ;;
    bash)
      snippet='
# Engineer Agent error capture
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;} _ea_capture_last_error"

_ea_capture_last_error() {
  local exit_code=$?
  if [[ -n "$TMUX" ]]; then
    tmux capture-pane -p -S -50 > /tmp/tmux-capture-$$.txt 2>/dev/null || true
  fi
  if [[ $exit_code -ne 0 ]]; then
    echo "exit $exit_code" >> ~/.bash_history 2>/dev/null || true
  fi
}
'
      ;;
  esac
  
  echo "$snippet"
}

# ---------------------------------------------------------------------------
# ea capture command
# ---------------------------------------------------------------------------

ea_cmd_capture_usage() {
  cat <<EOF
Usage: ea capture [--lines N] [--output FILE]

Capture terminal history for context.

Options:
  --lines N     Number of lines to capture (default: 50)
  --output FILE Save to file instead of stdout
  --tmux        Capture tmux pane (if in tmux)
  -h            Show this help message

Examples:
  ea capture
  ea capture --lines 100
  ea capture --tmux
EOF
}

ea_cmd_capture() {
  local lines=50
  local output_file=""
  local use_tmux=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --lines)
        lines="${2:-50}"
        shift
        ;;
      --output)
        output_file="${2:-}"
        shift
        ;;
      --tmux)
        use_tmux=true
        ;;
      -h|--help)
        ea_cmd_capture_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        ea_cmd_capture_usage
        return 1
        ;;
    esac
    shift
  done

  local capture_output=""
  
  if [[ "$use_tmux" == true ]] && [[ -n "$TMUX" ]]; then
    capture_output="$(tmux capture-pane -p -S "-$lines" 2>/dev/null || echo "")"
  elif [[ -n "$TMUX" ]]; then
    log_warn "Not in tmux, falling back to last-error file"
    capture_output="$(get_last_error)"
  else
    capture_output="$(get_last_error)"
  fi
  
  if [[ -z "$capture_output" ]]; then
    log_warn "No captured output found"
    
    if [[ -f "/tmp/tmux-capture-$$.txt" ]]; then
      capture_output="$(cat /tmp/tmux-capture-$$.txt)"
    fi
  fi
  
  if [[ -n "$output_file" ]]; then
    echo "$capture_output" > "$output_file"
    log_ok "Captured output saved to: $output_file"
  else
    echo "$capture_output"
  fi
}

# ---------------------------------------------------------------------------
# Shell setup installer
# ---------------------------------------------------------------------------

install_shell_integration() {
  local shell="${1:-auto}"
  
  if [[ "$shell" == "auto" ]]; then
    if [[ -n "$ZSH_VERSION" ]]; then
      shell="zsh"
    else
      shell="bash"
    fi
  fi
  
  local snippet
  snippet="$(generate_shell_snippet "$shell")"
  
  local rc_file=""
  case "$shell" in
    zsh)
      rc_file="$HOME/.zshrc"
      ;;
    bash)
      rc_file="$HOME/.bashrc"
      ;;
  esac
  
  if grep -q "ea_capture" "$rc_file" 2>/dev/null; then
    log_ok "Shell integration already installed in $rc_file"
    return 0
  fi
  
  echo "$snippet" >> "$rc_file"
  log_ok "Shell integration added to $rc_file"
  log_warn "Restart your shell or run: source $rc_file"
}
