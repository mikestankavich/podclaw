# Podclaw — OpenClaw on rootless Podman in Incus
#
# Configuration is loaded from .env.local (see .env.local.example).

set dotenv-load := true
set dotenv-filename := ".env.local"

name := env("PODCLAW_CONTAINER_NAME", "podclaw")
remote := env("PODCLAW_REMOTE", "")
target := if remote != "" { remote + ":" + name } else { name }
admin_user := env("PODCLAW_ADMIN_USER", "")

# Show container info and resource usage
info:
    @echo "Container:  {{target}}"
    @incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman ps --format "Image:      \{{{{.Image}}}}\nStatus:     \{{{{.Status}}}}\nPorts:      \{{{{.Ports}}}}"
    @echo ""
    @GUEST_IP=$(incus exec {{target}} -- hostname -I 2>/dev/null | awk '{print $$1}'); \
      echo "Gateway:    http://127.0.0.1:18789/  (inside container)"; \
      echo "LAN:        http://$GUEST_IP:18789/"
    @echo ""
    @incus info {{target}} | grep -E "^  (CPU|Memory|Disk)" || true

# Open a shell in the container
shell:
    incus exec {{target}} -- sudo -iu {{admin_user}} bash

# Show cloud-init and gateway logs (-f to follow)
logs *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ARGS}}" == *"-f"* ]]; then
      incus exec {{target}} -- sudo -u openclaw journalctl --user -u openclaw.service -f
    else
      incus exec {{target}} -- sudo -u openclaw journalctl --user -u openclaw.service --no-pager -n 50
    fi

# Manage the openclaw systemd service (status, start, stop, restart)
service verb="status":
    incus exec {{target}} -- sudo -u openclaw systemctl --user {{verb}} openclaw.service

# Show rootless Podman containers
podman *ARGS:
    incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman {{ARGS}}

# Launch a new OpenClaw container
launch:
    ./scripts/podclaw-quickstart.sh

# Delete the container
destroy:
    incus delete --force {{target}}
