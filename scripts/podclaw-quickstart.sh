#!/usr/bin/env bash
set -euo pipefail

# podclaw-quickstart.sh -- Launch a fully working OpenClaw instance in one shot.
#
# Launches an Incus container with rootless Podman, waits for cloud-init to
# finish, and verifies the OpenClaw gateway is responding.
#
# Assumptions:
#   - Running on an Incus host (or a machine with `incus` configured for a remote)
#   - Incus has a bridged NIC profile and a nesting profile available
#     (see profiles/ in the repo for reference configs)
#   - OpenClaw API keys are configured post-launch via the Control UI
#
# Required environment variables (set in shell or .env.local):
#   PODCLAW_ADMIN_USER       -- admin username for SSH/troubleshooting
#   PODCLAW_SSH_KEY          -- SSH public key for that user
#
# Optional environment variables:
#   PODCLAW_PROFILE_BRIDGED  -- Incus bridged NIC profile name (default: bridged)
#   PODCLAW_PROFILE_NESTING  -- Incus nesting profile name (default: docker)
#
# Usage:
#   ./podclaw-quickstart.sh [name] [remote]
#
# Examples:
#   export PODCLAW_ADMIN_USER=yourname PODCLAW_SSH_KEY="ssh-ed25519 AAAA..."
#   ./podclaw-quickstart.sh my-openclaw
#   ./podclaw-quickstart.sh my-openclaw your-remote
#
#   # Or use .env.local in the repo root:
#   echo 'PODCLAW_ADMIN_USER=yourname' >> .env.local
#   echo 'PODCLAW_SSH_KEY="ssh-ed25519 AAAA..."' >> .env.local
#   ./podclaw-quickstart.sh my-openclaw

NAME="${1:-oc-exp-$(date +%Y%m%d-%H%M%S)}"
REMOTE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
CLOUD_INIT="${REPO_ROOT}/cloud-init/openclaw-podman-skeleton.yml"

# Gateway may take a few seconds after cloud-init reports done.
GATEWAY_RETRIES=12
GATEWAY_RETRY_INTERVAL=5
GATEWAY_PORT=18789

if [[ ! -f "$CLOUD_INIT" ]]; then
  echo "Error: cloud-init file not found: ${CLOUD_INIT}" >&2
  exit 1
fi

# Load .env.local from repo root if it exists.
if [[ -f "${REPO_ROOT}/.env.local" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "${REPO_ROOT}/.env.local"
  set +a
fi

# Validate required variables.
if [[ -z "${PODCLAW_ADMIN_USER:-}" ]]; then
  echo "Error: PODCLAW_ADMIN_USER is not set." >&2
  echo "Set it in your shell or in .env.local" >&2
  exit 1
fi
if [[ -z "${PODCLAW_SSH_KEY:-}" ]]; then
  echo "Error: PODCLAW_SSH_KEY is not set." >&2
  echo "Set it in your shell or in .env.local" >&2
  exit 1
fi

export PODCLAW_ADMIN_USER PODCLAW_SSH_KEY

PROFILE_BRIDGED="${PODCLAW_PROFILE_BRIDGED:-bridged}"
PROFILE_NESTING="${PODCLAW_PROFILE_NESTING:-docker}"

TARGET="${NAME}"
EXEC_TARGET="${NAME}"
if [[ -n "$REMOTE" ]]; then
  TARGET="${REMOTE}:${NAME}"
  EXEC_TARGET="${TARGET}"
fi

# --- Step 1: Launch ---

echo "==> Launching Incus container: ${TARGET}"
echo "    Profiles: default, ${PROFILE_BRIDGED}, ${PROFILE_NESTING}"
echo "    Cloud-init: ${CLOUD_INIT}"
echo ""

incus launch images:ubuntu/24.04/cloud "${TARGET}" \
  -p default -p "${PROFILE_BRIDGED}" -p "${PROFILE_NESTING}" \
  --config=cloud-init.user-data="$(envsubst '${PODCLAW_ADMIN_USER} ${PODCLAW_SSH_KEY}' < "${CLOUD_INIT}")"

echo ""

# --- Step 2: Wait for cloud-init ---

echo "==> Waiting for cloud-init to finish (timeout: ${CLOUD_INIT_TIMEOUT}s)..."
echo "    You can tail logs in another terminal with:"
echo "    incus exec ${EXEC_TARGET} -- tail -f /var/log/cloud-init-output.log"
echo ""

if ! incus exec "${EXEC_TARGET}" -- cloud-init status --wait --long \
    2>&1 | tail -3; then
  echo ""
  echo "WARNING: cloud-init may have finished with errors." >&2
  echo "Check: incus exec ${EXEC_TARGET} -- tail -50 /var/log/cloud-init-output.log" >&2
fi

echo ""

# --- Step 3: Verify gateway ---

echo "==> Checking OpenClaw gateway on port ${GATEWAY_PORT}..."

GATEWAY_UP=false
for i in $(seq 1 "${GATEWAY_RETRIES}"); do
  if incus exec "${EXEC_TARGET}" -- \
      curl -sf -o /dev/null "http://127.0.0.1:${GATEWAY_PORT}/" 2>/dev/null; then
    GATEWAY_UP=true
    break
  fi
  echo "    Attempt ${i}/${GATEWAY_RETRIES} -- not ready yet, waiting ${GATEWAY_RETRY_INTERVAL}s..."
  sleep "${GATEWAY_RETRY_INTERVAL}"
done

echo ""

if "${GATEWAY_UP}"; then
  echo "==> OpenClaw gateway is running!"
else
  echo "==> WARNING: Gateway did not respond after ${GATEWAY_RETRIES} attempts." >&2
  echo "    Debug with:" >&2
  echo "    incus exec ${EXEC_TARGET} -- sudo -u openclaw podman ps" >&2
  echo "    incus exec ${EXEC_TARGET} -- sudo -u openclaw systemctl --user status openclaw.service" >&2
  echo ""
fi

# --- Step 4: Print access info ---

CONTAINER_IP=$(incus exec "${EXEC_TARGET}" -- hostname -I 2>/dev/null | awk '{print $1}') || true

echo "============================================================"
echo "  Container:  ${TARGET}"
echo "  Gateway:    http://127.0.0.1:${GATEWAY_PORT}/  (inside container)"
if [[ -n "${CONTAINER_IP:-}" ]]; then
  echo "  LAN:        http://${CONTAINER_IP}:${GATEWAY_PORT}/"
fi
echo ""
echo "  Shell:      incus exec ${EXEC_TARGET} -- sudo -iu ${PODCLAW_ADMIN_USER} bash"
echo "  Logs:       incus exec ${EXEC_TARGET} -- tail -50 /var/log/cloud-init-output.log"
echo "  Podman:     incus exec ${EXEC_TARGET} -- sudo -u openclaw podman ps"
echo "  Service:    incus exec ${EXEC_TARGET} -- sudo -u openclaw systemctl --user status openclaw.service"
echo ""
echo "  Next steps:"
echo "    1. Open the Control UI at the LAN URL above"
echo "    2. Configure your LLM API keys (Anthropic, OpenAI, etc.)"
echo "    3. Start chatting with an agent"
echo ""
echo "  Tear down:  incus delete --force ${TARGET}"
echo "============================================================"
