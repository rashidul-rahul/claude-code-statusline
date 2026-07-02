#!/usr/bin/env bash
# Install statusline.sh into one of the standard Claude Code config dirs and
# wire it up in that dir's settings.json. Pass the target dir as the first
# argument, or set CLAUDE_CONFIG_DIR. Defaults to ~/.claude.
#
# Usage:
#   ./install.sh                       # installs into ~/.claude
#   ./install.sh ~/.claude-work        # installs into ~/.claude-work
#   CLAUDE_CONFIG_DIR=~/.claude-personal ./install.sh
set -euo pipefail

target="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
script_src="$(cd "$(dirname "$0")" && pwd)/statusline.sh"

if [ ! -f "$script_src" ]; then
  echo "error: $script_src not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

mkdir -p "$target/hooks"
install -m 0755 "$script_src" "$target/hooks/statusline.sh"
echo "installed: $target/hooks/statusline.sh"

settings="$target/settings.json"
if [ ! -f "$settings" ]; then
  echo '{}' > "$settings"
fi

cmd="bash \"$target/hooks/statusline.sh\""
tmp=$(mktemp)
jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd, refreshInterval: 2}' "$settings" > "$tmp"
mv "$tmp" "$settings"
echo "updated: $settings (statusLine -> $cmd)"

echo
echo "Done. Restart Claude Code or trigger any action to see the new status line."
