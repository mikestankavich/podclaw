#!/usr/bin/env bash
set -euo pipefail

# Launch an OpenClaw experiment container on k8s-delta (or localhost)
# Usage: ./launch-experiment.sh [name] [remote]
#
# Examples:
#   ./launch-experiment.sh                    # oc-exp-<timestamp>, local
#   ./launch-experiment.sh my-test            # my-test, local
#   ./launch-experiment.sh my-test k8s-delta  # k8s-delta:my-test

NAME="${1:-oc-exp-$(date +%Y%m%d-%H%M%S)}"
REMOTE="${2:-}"
CLOUD_INIT="$(dirname "$0")/../cloud-init/openclaw-podman-skeleton.yml"

if [[ ! -f "$CLOUD_INIT" ]]; then
  echo "Error: cloud-init file not found: $CLOUD_INIT" >&2
  exit 1
fi

TARGET="${NAME}"
if [[ -n "$REMOTE" ]]; then
  TARGET="${REMOTE}:${NAME}"
fi

echo "Launching experiment container: $TARGET"
echo "  Profiles: default, bridged, docker"
echo "  Cloud-init: $CLOUD_INIT"
echo ""

incus launch images:ubuntu/24.04/cloud "$TARGET" \
  -p default -p bridged -p docker \
  --config=cloud-init.user-data="$(cat "$CLOUD_INIT")"

echo ""
echo "Container launched. Monitor cloud-init with:"
echo "  incus exec ${TARGET} -- tail -f /var/log/cloud-init-output.log"
echo ""
echo "Shell into it with:"
echo "  incus exec ${TARGET} -- sudo -iu mike bash"
