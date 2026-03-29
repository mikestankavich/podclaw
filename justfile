# Podclaw — OpenClaw on rootless Podman in Incus
#
# Configuration is loaded from .env.local (see .env.local.example).

set dotenv-load := true
set dotenv-filename := ".env.local"

name := env("PODCLAW_CONTAINER_NAME", "podclaw")
remote := env("PODCLAW_REMOTE", "")
target := if remote != "" { remote + ":" + name } else { name }
admin_user := env("PODCLAW_ADMIN_USER", "")
quiet := env("PODCLAW_QUIET", "")

# Show container info and resource usage
info:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Container:  {{target}}"
    echo ""
    GUEST_IP=$(incus exec {{target}} -- hostname -I 2>/dev/null | awk '{print $1}') || true
    echo "Gateway:    http://127.0.0.1:18789/  (inside container)"
    if [[ -n "$GUEST_IP" ]]; then
      echo "LAN:        http://${GUEST_IP}:18789/"
    fi
    echo ""
    incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman ps 2>/dev/null || true
    echo ""
    incus info {{target}} 2>/dev/null | grep -A1 -E "Resources:" || true

# Open a shell in the container
shell:
    incus exec {{target}} -- sudo -iu {{admin_user}} bash

# Show gateway logs (-f to follow)
logs *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ARGS}}" == *"-f"* ]]; then
      incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman logs -f openclaw
    else
      incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman logs --tail 50 openclaw
    fi

# Manage the openclaw systemd service (status, start, stop, restart)
service verb="status":
    incus exec {{target}} -- systemctl --machine openclaw@ --user {{verb}} openclaw.service

# Show rootless Podman containers
podman *ARGS:
    incus exec {{target}} --cwd /home/openclaw -- sudo -u openclaw podman {{ARGS}}

# Launch a new OpenClaw container (verbose by default, PODCLAW_QUIET=1 to suppress log tailing)
launch:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{quiet}}" ]]; then
      export PODCLAW_VERBOSE=1
    fi
    ./scripts/podclaw-quickstart.sh

# Delete the container
destroy:
    incus delete --force {{target}}
