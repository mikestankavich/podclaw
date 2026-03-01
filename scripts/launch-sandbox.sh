#!/usr/bin/env bash
set -euo pipefail

# Launch a ralph sandbox container on a target host, push devbox-lite, and run it.
# Usage: ./launch-sandbox.sh [name] [host]
#
# Examples:
#   ./launch-sandbox.sh ralph-sandbox k8s-delta.local

NAME="${1:-ralph-sandbox}"
HOST="${2:-k8s-delta.local}"
USER="mike"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLOUD_INIT="${SCRIPT_DIR}/../cloud-init/ralph-sandbox.yml"
DEVBOX_LITE="${SCRIPT_DIR}/../sandbox/devbox-lite.sh"

if [[ ! -f "$CLOUD_INIT" ]]; then
  echo "Error: cloud-init not found: $CLOUD_INIT" >&2
  exit 1
fi
if [[ ! -f "$DEVBOX_LITE" ]]; then
  echo "Error: devbox-lite.sh not found: $DEVBOX_LITE" >&2
  exit 1
fi

echo "==> Launching $NAME on $HOST"
ssh "$HOST" "incus launch images:ubuntu/24.04/cloud $NAME \
  -p default -p bridged -p docker \
  --config=cloud-init.user-data=\"\$(cat <<'CLOUDINIT'
$(cat "$CLOUD_INIT")
CLOUDINIT
)\""

echo "==> Waiting for cloud-init to finish..."
ssh "$HOST" "incus exec $NAME -- cloud-init status --wait"

echo "==> Pushing devbox-lite.sh into container"
ssh "$HOST" "incus file push - $NAME/home/$USER/devbox-lite.sh" < "$DEVBOX_LITE"
ssh "$HOST" "incus exec $NAME -- chown $USER:$USER /home/$USER/devbox-lite.sh"
ssh "$HOST" "incus exec $NAME -- chmod +x /home/$USER/devbox-lite.sh"

echo "==> Running devbox-lite.sh as $USER"
ssh "$HOST" "incus exec $NAME -- sudo -iu $USER bash /home/$USER/devbox-lite.sh"

echo ""
echo "==> Done. Shell into it with:"
echo "    ssh $HOST -t 'incus exec $NAME -- sudo -iu $USER bash'"
echo ""
echo "    Or once avahi is up:"
CONTAINER_SHORT="${NAME%%.*}"
echo "    ssh ${USER}@${CONTAINER_SHORT}.local"
