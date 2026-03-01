#!/usr/bin/env bash
set -euo pipefail

# Ralph sandbox bootstrap: devbox-lite + ralph-wiggum Claude Code plugin.
# Usage: bash devbox-ralph.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Base tooling (Node, Docker, gh, Claude Code) ---
bash "$SCRIPT_DIR/devbox-lite.sh"

# --- Ralph Wiggum plugin (Claude Code stop-hook loop) ---
RALPH_PLUGIN_DIR="$HOME/.claude/plugins/ralph-wiggum"
if [[ ! -d "$RALPH_PLUGIN_DIR" ]]; then
  RALPH_REPO="anthropics/claude-code"
  RALPH_PATH="plugins/ralph-wiggum"
  mkdir -p "$RALPH_PLUGIN_DIR"/{.claude-plugin,commands,hooks,scripts}
  for f in .claude-plugin/plugin.json commands/cancel-ralph.md commands/help.md \
           commands/ralph-loop.md hooks/hooks.json hooks/stop-hook.sh \
           scripts/setup-ralph-loop.sh; do
    curl -fsSL "https://raw.githubusercontent.com/$RALPH_REPO/main/$RALPH_PATH/$f" \
      -o "$RALPH_PLUGIN_DIR/$f"
  done
  chmod +x "$RALPH_PLUGIN_DIR/hooks/stop-hook.sh" "$RALPH_PLUGIN_DIR/scripts/setup-ralph-loop.sh"
fi

echo ""
echo "devbox-ralph bootstrap complete. Ralph Wiggum plugin installed."
echo "Commands available in Claude Code: /ralph-loop, /cancel-ralph, /help"
