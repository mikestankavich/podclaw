#!/usr/bin/env bash
set -euo pipefail

# Delete all experiment containers matching a prefix on a given remote
# Usage: ./cleanup-experiments.sh [prefix] [remote]
#
# Examples:
#   ./cleanup-experiments.sh                     # delete all oc-exp-* locally
#   ./cleanup-experiments.sh oc-exp k8s-delta    # delete oc-exp-* on k8s-delta

PREFIX="${1:-oc-exp}"
REMOTE="${2:-}"

if [[ -n "$REMOTE" ]]; then
  CONTAINERS=$(incus ls "${REMOTE}:" --format csv -c n | grep "^${PREFIX}" || true)
else
  CONTAINERS=$(incus ls --format csv -c n | grep "^${PREFIX}" || true)
fi

if [[ -z "$CONTAINERS" ]]; then
  echo "No containers matching prefix '${PREFIX}' found."
  exit 0
fi

echo "Containers to delete:"
echo "$CONTAINERS" | sed 's/^/  /'
echo ""
read -p "Delete all? [y/N] " -r
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

while IFS= read -r name; do
  TARGET="$name"
  if [[ -n "$REMOTE" ]]; then
    TARGET="${REMOTE}:${name}"
  fi
  echo "Deleting $TARGET..."
  incus delete --force "$TARGET"
done <<< "$CONTAINERS"

echo "Done."
