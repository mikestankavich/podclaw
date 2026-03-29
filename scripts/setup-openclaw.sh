#!/usr/bin/env bash
# setup-openclaw.sh -- Set up OpenClaw on rootless Podman (Ubuntu 24.04)
#
# Run as root on a fresh Ubuntu 24.04 system. Installs its own
# dependencies if missing. Called by cloud-init or run standalone.
#
# Usage: sudo ./setup-openclaw.sh
#   Or:  curl -fsSL https://raw.githubusercontent.com/mikestankavich/podclaw/main/scripts/setup-openclaw.sh | sudo bash
set -euo pipefail

OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:main-slim}"
OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"

log() { echo "==> $*"; }

# --- Install dependencies if missing ---
DEPS="podman fuse-overlayfs apparmor-utils systemd-container git curl jq"
MISSING=""
for pkg in $DEPS; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    MISSING="$MISSING $pkg"
  fi
done
if [ -n "$MISSING" ]; then
  log "Installing dependencies:$MISSING"
  apt-get update -qq
  apt-get install -y -qq $MISSING
fi

# --- AppArmor userns profiles ---
# Ubuntu 24.04 blocks unprivileged user namespaces. Grant userns to
# podman, conmon, crun, slirp4netns, and pasta.
log "Installing AppArmor userns profiles"
for bin in podman conmon crun slirp4netns pasta; do
  cat > "/etc/apparmor.d/${bin}-userns" <<APPARMOR
abi <abi/4.0>,
include <tunables/global>

profile ${bin} /usr/bin/${bin} flags=(unconfined) {
  userns,
}
APPARMOR
  apparmor_parser -r "/etc/apparmor.d/${bin}-userns"
done

# --- Create openclaw user ---
log "Creating ${OPENCLAW_USER} user"
if ! id "${OPENCLAW_USER}" &>/dev/null; then
  useradd -m -s /usr/sbin/nologin "${OPENCLAW_USER}"
fi
loginctl enable-linger "${OPENCLAW_USER}"
OPENCLAW_UID=$(id -u "${OPENCLAW_USER}")
systemctl start "user@${OPENCLAW_UID}.service" || true

# --- Configure fuse-overlayfs storage ---
log "Configuring fuse-overlayfs storage driver"
mkdir -p "${OPENCLAW_HOME}/.config/containers"
cat > "${OPENCLAW_HOME}/.config/containers/storage.conf" <<STORAGE
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
STORAGE
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}/.config"

# --- subuid/subgid ---
if ! grep -q "^${OPENCLAW_USER}:" /etc/subuid 2>/dev/null; then
  echo "${OPENCLAW_USER}:100000:65536" >> /etc/subuid
  echo "${OPENCLAW_USER}:100000:65536" >> /etc/subgid
fi

# --- OpenClaw config ---
log "Pre-creating OpenClaw config"
mkdir -p "${OPENCLAW_HOME}/.openclaw/workspace"
chmod 700 "${OPENCLAW_HOME}/.openclaw" "${OPENCLAW_HOME}/.openclaw/workspace"

cat > "${OPENCLAW_HOME}/.openclaw/openclaw.json" <<CONFIG
{
  "gateway": {
    "mode": "local",
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
CONFIG
chmod 600 "${OPENCLAW_HOME}/.openclaw/openclaw.json"

# --- Gateway auth token ---
log "Generating gateway auth token"
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}" > "${OPENCLAW_HOME}/.openclaw/.env"
chmod 600 "${OPENCLAW_HOME}/.openclaw/.env"

chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}/.openclaw"

# --- Clone and run OpenClaw setup ---
log "Cloning OpenClaw repo"
git clone https://github.com/openclaw/openclaw /opt/openclaw 2>/dev/null || true
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" /opt/openclaw

log "Running OpenClaw setup (pull image + install Quadlet)"
sudo -u "${OPENCLAW_USER}" bash -c "cd /opt/openclaw && OPENCLAW_IMAGE=${OPENCLAW_IMAGE} OPENCLAW_PODMAN_QUADLET=1 OPENCLAW_PODMAN_PUBLISH_HOST=0.0.0.0 ./scripts/podman/setup.sh"

# --- Patch Quadlet for LAN access ---
QUADLET="${OPENCLAW_HOME}/.config/containers/systemd/openclaw.container"
if [ -f "$QUADLET" ]; then
  log "Patching Quadlet for LAN port binding"
  sed -i 's|PublishPort=127.0.0.1:|PublishPort=0.0.0.0:|g' "$QUADLET"
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$QUADLET"
fi

# --- Start service ---
log "Starting OpenClaw service"
systemctl --machine "${OPENCLAW_USER}@" --user daemon-reload || true
systemctl --machine "${OPENCLAW_USER}@" --user restart openclaw.service || true

# --- Post-setup validation ---
log "Running post-setup validation"
sudo -u "${OPENCLAW_USER}" podman exec openclaw openclaw doctor --fix 2>&1 || true
sudo -u "${OPENCLAW_USER}" podman exec openclaw openclaw security audit 2>&1 || true

# --- Fix ownership ---
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}" || true

log "OpenClaw setup complete"
