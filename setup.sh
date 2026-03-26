#!/bin/bash
# One-time setup script for global `ea` command.

set -euo pipefail

EA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EA_BIN="$EA_ROOT/ea"

if [[ ! -x "$EA_BIN" ]]; then
  chmod +x "$EA_BIN"
fi

TARGET_DIR="$HOME/.local/bin"
TARGET_LINK="$TARGET_DIR/ea"

mkdir -p "$TARGET_DIR"
ln -sf "$EA_BIN" "$TARGET_LINK"

echo "Installed: $TARGET_LINK -> $EA_BIN"

if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
  echo ""
  echo "Add this to your shell profile (~/.zshrc):"
  echo "  export PATH=\"$TARGET_DIR:\$PATH\""
  echo ""
  echo "Then reload your shell:"
  echo "  source ~/.zshrc"
else
  echo ""
  echo "PATH already contains $TARGET_DIR"
fi

echo ""
echo "Setting up shell integration for error capture..."
# ZSH_VERSION is only set when running inside zsh; under bash it is unset and set -u would error.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  shell="zsh"
else
  shell="bash"
fi

snippet='
# Engineer Agent error capture
if [[ -n "$TMUX" ]]; then
  trap '"'"'tmux capture-pane -p -S -50 > ~/.ea/tmux-capture.txt 2>/dev/null || true'"'"' DEBUG
fi
'

if [[ "$shell" == "zsh" ]]; then
  rc_file="$HOME/.zshrc"
else
  rc_file="$HOME/.bashrc"
fi

if ! grep -q "ea.*error capture" "$rc_file" 2>/dev/null; then
  echo "$snippet" >> "$rc_file"
  echo "Added error capture to $rc_file"
else
  echo "Shell integration already present in $rc_file"
fi

mkdir -p "$HOME/.ea"

echo ""
echo "Try it:"
echo "  ea help"
