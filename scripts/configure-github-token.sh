#!/usr/bin/env bash
set -euo pipefail

# Configure a fine-grained GitHub PAT for the podclaw repo.
# Stores the token securely in ~/.config/podclaw/github.env
#
# Token requirements (create at https://github.com/settings/personal-access-tokens):
#   - Fine-grained PAT
#   - Scoped to: mikestankavich/podclaw (single repo)
#   - Permissions:
#     - Repository contents: Read and write
#     - Pull requests: Read and write (optional)
#     - Everything else: No access

CONFIG_DIR="${HOME}/.config/podclaw"
ENV_FILE="${CONFIG_DIR}/github.env"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

if [[ -f "$ENV_FILE" ]]; then
  echo "Existing token found at $ENV_FILE"
  read -p "Overwrite? [y/N] " -r
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Keeping existing token."
    exit 0
  fi
fi

echo ""
echo "Enter your fine-grained GitHub PAT for mikestankavich/podclaw:"
read -s -p "Token: " TOKEN
echo ""

if [[ -z "$TOKEN" ]]; then
  echo "Error: empty token" >&2
  exit 1
fi

cat > "$ENV_FILE" <<EOF
export PODCLAW_GH_TOKEN="${TOKEN}"
export PODCLAW_GH_REPO="https://github.com/mikestankavich/podclaw.git"
EOF

chmod 600 "$ENV_FILE"
echo "Token saved to $ENV_FILE (mode 600)"
echo ""
echo "To use: source $ENV_FILE"
echo "To clone: git clone https://\${PODCLAW_GH_TOKEN}@github.com/mikestankavich/podclaw.git"
