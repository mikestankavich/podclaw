#!/usr/bin/env bash
set -euo pipefail

# Launch a ralph sandbox container on a target host, push devbox scripts, and run.
# Usage: ./launch-sandbox.sh [name] [host]
#
# Examples:
#   ./launch-sandbox.sh ralph-sandbox k8s-delta.local

NAME="${1:-ralph-sandbox}"
HOST="${2:-k8s-delta.local}"
USER="mike"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_DIR="${SCRIPT_DIR}/../sandbox"
CLOUD_INIT="${SCRIPT_DIR}/../cloud-init/ralph-sandbox.yml"
DEVBOX_LITE="${SANDBOX_DIR}/devbox-lite.sh"
DEVBOX_RALPH="${SANDBOX_DIR}/devbox-ralph.sh"

for f in "$CLOUD_INIT" "$DEVBOX_LITE" "$DEVBOX_RALPH"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: not found: $f" >&2
    exit 1
  fi
done

echo "==> Launching $NAME on $HOST"
ssh "$HOST" "incus launch images:ubuntu/24.04/cloud $NAME \
  -p default -p bridged -p docker \
  --config=cloud-init.user-data=\"\$(cat <<'CLOUDINIT'
$(cat "$CLOUD_INIT")
CLOUDINIT
)\""

echo "==> Waiting for cloud-init to finish..."
ssh "$HOST" "incus exec $NAME -- cloud-init status --wait"

echo "==> Pushing devbox scripts into container"
ssh "$HOST" "incus exec $NAME -- mkdir -p /home/$USER/.local/bin"
for script in "$DEVBOX_LITE" "$DEVBOX_RALPH"; do
  BASENAME="$(basename "$script")"
  ssh "$HOST" "incus file push - $NAME/home/$USER/.local/bin/$BASENAME" < "$script"
done
ssh "$HOST" "incus exec $NAME -- chown -R $USER:$USER /home/$USER/.local"
ssh "$HOST" "incus exec $NAME -- chmod +x /home/$USER/.local/bin/*.sh"

echo "==> Running devbox-ralph.sh as $USER"
ssh "$HOST" "incus exec $NAME -- sudo -iu $USER bash /home/$USER/.local/bin/devbox-ralph.sh"

echo ""
echo "==> Done. Shell into it with:"
echo "    ssh $HOST -t 'incus exec $NAME -- sudo -iu $USER bash'"
echo ""
echo "    Or once avahi is up:"
CONTAINER_SHORT="${NAME%%.*}"
echo "    ssh ${USER}@${CONTAINER_SHORT}.local"
