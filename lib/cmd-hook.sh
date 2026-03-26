#!/bin/bash
set -euo pipefail

ea_cmd_hook_usage() {
  cat <<EOF
Usage: ea hook <install|uninstall> [--path /path/to/project]

Options:
  --path  Optional project path override (default: auto-detect from current directory)
  -h      Show this help message
EOF
}

ea_cmd_hook_install() {
  local project_override="${1:-}"
  local project_root
  project_root="$(detect_project_root "$project_override")"

  if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "Not a git repository: $project_root"
    return 1
  fi

  local hooks_dir hook_file
  hooks_dir="$project_root/.git/hooks"
  hook_file="$hooks_dir/pre-push"

  if [[ -f "$hook_file" ]]; then
    log_warn "Existing pre-push hook found at $hook_file"
    cp "$hook_file" "${hook_file}.bak"
    log_warn "Backed up existing hook to ${hook_file}.bak"
  fi

  cat > "$hook_file" <<EOF
#!/bin/bash
# managed-by: engineer-agent

set -uo pipefail

EA_ROOT="$EA_ROOT"
REPO_ROOT="\$(git rev-parse --show-toplevel)"

while read -r LOCAL_REF LOCAL_SHA REMOTE_REF REMOTE_SHA; do
  if [[ "\$REMOTE_SHA" == "0000000000000000000000000000000000000000" ]]; then
    DIFF_ARGS="HEAD~1 HEAD"
  else
    DIFF_ARGS="\$REMOTE_SHA \$LOCAL_SHA"
  fi
done

DIFF_ARGS="\${DIFF_ARGS:-HEAD~1 HEAD}"

"\$EA_ROOT/ea" review --path "\$REPO_ROOT" --diff-args "\$DIFF_ARGS" || {
  echo "engineer-agent review failed; push continues."
}

exit 0
EOF

  chmod +x "$hook_file"

  local gitignore_file="$project_root/.gitignore"
  if [[ -f "$gitignore_file" ]]; then
    if ! grep -q '\.code-review/' "$gitignore_file" 2>/dev/null; then
      {
        echo ""
        echo "# engineer-agent artifacts"
        echo ".code-review/"
        echo ".engineer-agent/"
      } >> "$gitignore_file"
      log_ok "Added .code-review/ and .engineer-agent/ to .gitignore"
    fi
  else
    {
      echo "# engineer-agent artifacts"
      echo ".code-review/"
      echo ".engineer-agent/"
    } > "$gitignore_file"
    log_ok "Created .gitignore with engineer-agent artifacts"
  fi

  log_ok "Pre-push hook installed: $hook_file"
}

ea_cmd_hook_uninstall() {
  local project_override="${1:-}"
  local project_root
  project_root="$(detect_project_root "$project_override")"
  local hook_file="$project_root/.git/hooks/pre-push"

  if [[ ! -f "$hook_file" ]]; then
    log_warn "No pre-push hook found at $hook_file"
    return 0
  fi

  if grep -q "managed-by: engineer-agent" "$hook_file" 2>/dev/null; then
    rm -f "$hook_file"
    log_ok "Removed engineer-agent pre-push hook"
  else
    log_warn "pre-push exists but is not managed by engineer-agent; not deleting."
    log_warn "Delete manually if needed: $hook_file"
  fi
}

ea_cmd_hook() {
  local action=""
  local project_override=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      install|uninstall)
        action="$1"
        ;;
      --path)
        project_override="${2:-}"
        shift
        ;;
      -h|--help)
        ea_cmd_hook_usage
        return 0
        ;;
      *)
        log_error "Unknown option for ea hook: $1"
        ea_cmd_hook_usage
        return 1
        ;;
    esac
    shift
  done

  if [[ -z "$action" ]]; then
    log_error "ea hook requires an action: install or uninstall"
    ea_cmd_hook_usage
    return 1
  fi

  if [[ "$action" == "install" ]]; then
    ea_cmd_hook_install "$project_override"
  else
    ea_cmd_hook_uninstall "$project_override"
  fi
}
