#!/usr/bin/env bash
set -euo pipefail

# Minimal dev sandbox bootstrap: Node (fnm), gh CLI, Claude Code, Docker.
# Runs as the target user (not root). Uses sudo for system packages.
# Anything else can be installed later by asking Claude.

export DEBIAN_FRONTEND=noninteractive
sudo apt update -y
sudo apt upgrade -y

sudo apt install -y \
  avahi-daemon openssh-server curl tree unzip wget jq git \
  ca-certificates gnupg nano tmux

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi

# --- FNM + Node LTS ---
if ! command -v fnm >/dev/null 2>&1; then
  curl -fsSL https://fnm.vercel.app/install | bash
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env)"
  fnm install --lts
  fnm default lts-latest
  fnm use default

  mkdir -p ~/.npm-global
  npm config set prefix ~/.npm-global

  npm install -g pnpm @anthropic-ai/claude-code
fi

# --- GitHub CLI ---
if ! command -v gh >/dev/null 2>&1; then
  curl -fsSL https://gist.github.com/mikestankavich/4728909ba36b5142bd59d722210c6f43/raw/install-gh-cli.sh | sudo bash
fi

# --- .bashrc patch ---
if ! grep -q "# fnm path setup" ~/.bashrc 2>/dev/null; then
tee -a ~/.bashrc > /dev/null <<'EOF'

# fnm path setup
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"

# npm global bin
export PATH="$PATH:$HOME/.npm-global/bin"

EOF
fi

echo ""
echo "devbox-lite bootstrap complete for $USER."
echo "Log out and back in (or source ~/.bashrc) to pick up PATH changes."
