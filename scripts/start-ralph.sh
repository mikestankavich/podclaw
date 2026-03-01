#!/usr/bin/env bash
set -euo pipefail

# Start a Ralph loop inside a tmux session so it survives SSH disconnects.
# Usage: ./start-ralph.sh [mission-file] [max-iterations]
#
# Examples:
#   ./start-ralph.sh                                    # default mission, 30 iterations
#   ./start-ralph.sh missions/openclaw-podman.md 50     # custom mission, 50 iterations
#
# Reconnect later with: tmux attach -t ralph

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MISSION="${1:-missions/openclaw-podman.md}"
MAX_ITERATIONS="${2:-30}"
MISSION_PATH="$REPO_DIR/$MISSION"

if [[ ! -f "$MISSION_PATH" ]]; then
  echo "Error: mission file not found: $MISSION_PATH" >&2
  exit 1
fi

# Extract completion promise from the mission file (looks for <promise>...</promise>)
PROMISE=$(grep -oP '(?<=<promise>).*(?=</promise>)' "$MISSION_PATH" | head -1)
if [[ -z "$PROMISE" ]]; then
  echo "Warning: no <promise> tag found in mission file. Loop will run until max iterations." >&2
fi

# Kill existing ralph session if any
tmux kill-session -t ralph 2>/dev/null || true

echo "Starting Ralph loop in tmux session 'ralph'"
echo "  Mission: $MISSION"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Completion promise: ${PROMISE:-none}"
echo ""
echo "  Reconnect with: tmux attach -t ralph"
echo ""

# Build the claude command
CLAUDE_CMD="cd $REPO_DIR && claude --dangerously-skip-permissions"

if [[ -n "$PROMISE" ]]; then
  RALPH_CMD="/ralph-loop \"\$(cat $MISSION_PATH)\" --completion-promise '$PROMISE' --max-iterations $MAX_ITERATIONS"
else
  RALPH_CMD="/ralph-loop \"\$(cat $MISSION_PATH)\" --max-iterations $MAX_ITERATIONS"
fi

# Create tmux session and launch claude
tmux new-session -d -s ralph -c "$REPO_DIR" "$CLAUDE_CMD"

echo "Ralph is running. Attach with: tmux attach -t ralph"
echo "Then paste the /ralph-loop command to begin the mission."
echo ""
echo "Command to paste:"
echo "  $RALPH_CMD"
