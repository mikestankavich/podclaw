#!/usr/bin/env bash
# setup-traefik.sh -- Set up Traefik TLS for OpenClaw
#
# Requires: PODCLAW_DOMAIN, PODCLAW_CF_API_TOKEN, PODCLAW_ACME_EMAIL
# Run as root after setup-openclaw.sh has completed.
set -euo pipefail

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
TRAEFIK_CONFIG="${OPENCLAW_HOME}/.config/traefik"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

log() { echo "==> $*"; }

# Validate required variables
for var in PODCLAW_DOMAIN PODCLAW_CF_API_TOKEN PODCLAW_ACME_EMAIL; do
  if [ -z "${!var:-}" ]; then
    echo "Error: ${var} is not set." >&2
    exit 1
  fi
done

# --- Allow unprivileged ports 80/443 ---
# Rootless Podman can't bind to privileged ports by default.
log "Enabling unprivileged port binding"
sysctl -w net.ipv4.ip_unprivileged_port_start=0 > /dev/null
if ! grep -q "ip_unprivileged_port_start" /etc/sysctl.d/99-podclaw.conf 2>/dev/null; then
  echo "net.ipv4.ip_unprivileged_port_start=0" > /etc/sysctl.d/99-podclaw.conf
fi

# --- Install Traefik config ---
log "Installing Traefik config to ${TRAEFIK_CONFIG}"
mkdir -p "${TRAEFIK_CONFIG}/dynamic"

# Static config (substitute ACME email)
sed "s#\${PODCLAW_ACME_EMAIL}#${PODCLAW_ACME_EMAIL}#g" \
  "${REPO_ROOT}/traefik/traefik.yml" > "${TRAEFIK_CONFIG}/traefik.yml"

# Dynamic route config (substitute domain)
sed "s#\${PODCLAW_DOMAIN}#${PODCLAW_DOMAIN}#g" \
  "${REPO_ROOT}/traefik/dynamic/openclaw.yml" > "${TRAEFIK_CONFIG}/dynamic/openclaw.yml"

chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${TRAEFIK_CONFIG}"

# --- Install Quadlet unit ---
log "Installing Traefik Quadlet"
QUADLET_DIR="${OPENCLAW_HOME}/.config/containers/systemd"
mkdir -p "${QUADLET_DIR}"

sed "s#\${PODCLAW_CF_API_TOKEN}#${PODCLAW_CF_API_TOKEN}#g" \
  "${REPO_ROOT}/traefik/traefik.container" > "${QUADLET_DIR}/traefik.container"

chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${QUADLET_DIR}"

# --- Create DNS A record ---
log "Creating DNS A record: ${PODCLAW_DOMAIN}"
GUEST_IP=$(hostname -I | awk '{print $1}')

# Get zone ID from domain
ZONE_NAME=$(echo "${PODCLAW_DOMAIN}" | awk -F. '{print $(NF-1)"."$NF}')
ZONE_ID=$(curl -sf -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
  -H "Authorization: Bearer ${PODCLAW_CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "${ZONE_ID}" ] || [ "${ZONE_ID}" = "null" ]; then
  echo "WARNING: Could not find Cloudflare zone for ${ZONE_NAME}. Create the DNS record manually." >&2
else
  # Upsert: delete existing, create new
  EXISTING=$(curl -sf -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${PODCLAW_DOMAIN}" \
    -H "Authorization: Bearer ${PODCLAW_CF_API_TOKEN}" | jq -r '.result[0].id // empty')

  if [ -n "${EXISTING}" ]; then
    curl -sf -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${EXISTING}" \
      -H "Authorization: Bearer ${PODCLAW_CF_API_TOKEN}" > /dev/null
  fi

  curl -sf -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${PODCLAW_CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${PODCLAW_DOMAIN}\",\"content\":\"${GUEST_IP}\",\"ttl\":120,\"proxied\":false}" > /dev/null

  log "DNS A record created: ${PODCLAW_DOMAIN} -> ${GUEST_IP}"
fi

# --- Patch OpenClaw config with HTTPS origin ---
OPENCLAW_CONFIG="${OPENCLAW_HOME}/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
  log "Adding https://${PODCLAW_DOMAIN} to allowedOrigins"
  jq --arg origin "https://${PODCLAW_DOMAIN}" \
    '.gateway.controlUi.allowedOrigins = (.gateway.controlUi.allowedOrigins // []) + [$origin] | .gateway.controlUi.allowedOrigins |= unique' \
    "$OPENCLAW_CONFIG" > "${OPENCLAW_CONFIG}.tmp" && mv "${OPENCLAW_CONFIG}.tmp" "$OPENCLAW_CONFIG"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$OPENCLAW_CONFIG"
  # Restart OpenClaw to pick up the new origin
  systemctl --machine "${OPENCLAW_USER}@" --user restart openclaw.service || true
  sleep 3
fi

# --- Start Traefik ---
log "Starting Traefik service"
systemctl --machine "${OPENCLAW_USER}@" --user daemon-reload || true
systemctl --machine "${OPENCLAW_USER}@" --user start traefik.service || true

log "Traefik setup complete"
log "OpenClaw available at: https://${PODCLAW_DOMAIN}/"
