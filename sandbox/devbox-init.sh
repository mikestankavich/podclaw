#!/usr/bin/env bash
set -euo pipefail

# --- Configurable defaults ---
GO_VER="go1.25.1.linux-amd64"

# --- Ensure packages are installed ---
export DEBIAN_FRONTEND=noninteractive
sudo apt update -y
sudo apt upgrade -y

sudo apt install -y \
  avahi-daemon openssh-server curl tree unzip wget rsync jq git build-essential \
  software-properties-common ca-certificates gnupg lsb-release nano direnv \
  python3 python3-pip python3-venv

# --- Install FNM ---
if ! command -v fnm >/dev/null 2>&1; then
  curl -fsSL https://fnm.vercel.app/install | bash
  export PATH=$PATH:~/.local/share/fnm
  eval $(fnm env)
  fnm install --lts
  fnm default lts-latest
  fnm use default

  # --- NPM global directory setup ---
  mkdir -p ~/.npm-global
  npm config set prefix ~/.npm-global

  # --- Global install pnpm and claude-code ---
  npm install -g pnpm @anthropic-ai/claude-code
fi

# --- GitHub CLI install (runs as root, standard script installs system-wide) ---
if ! command -v gh >/dev/null 2>&1; then
  curl -fsSL https://gist.github.com/mikestankavich/4728909ba36b5142bd59d722210c6f43/raw/install-gh-cli.sh | sudo bash
fi

# --- Just command runner ---
if ! command -v just >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin
fi

# --- uv (Python), as user to get ~/.cargo/bin available ---
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- Go install ---
if ! [ -x /usr/local/go/bin/go ] || [[ "$(/usr/local/go/bin/go version 2>/dev/null)" != *"${GO_VER%%.*}"* ]]; then
  curl -fsSL "https://go.dev/dl/${GO_VER}.tar.gz" | sudo tar -C /usr/local -xz
fi

# --- .bashrc patch: only if not already present ---
if ! grep -q "# direnv hook to auto set env vars" ~/.bashrc 2>/dev/null; then
tee -a ~/.bashrc > /dev/null <<'EOF'

# direnv hook to auto set env vars on change directory when the destination directory has a .envrc file
eval "$(direnv hook bash)"

# Add user-global NPM path
export PATH=$PATH:~/.npm-global/bin

# Add golang bin path
export PATH=$PATH:/usr/local/go/bin

# Add uv path
export PATH=$PATH:~/.cargo/bin

EOF
fi

echo ""
echo "Bootstrap complete for user $USER."
