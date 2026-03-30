# Podclaw — OpenClaw on rootless Podman in Incus
#
# Configuration is loaded from .env.local (see .env.local.example).
# Run `just` or `just --list` to see available commands.

set dotenv-load := true
set dotenv-filename := ".env.local"

name := env("PODCLAW_CONTAINER_NAME", "podclaw")
remote := env("PODCLAW_REMOTE", "")
target := if remote != "" { remote + ":" + name } else { name }
admin_user := env("PODCLAW_ADMIN_USER", "")
quiet := env("PODCLAW_QUIET", "")
domain := env("PODCLAW_DOMAIN", "")

# Helper: run a command as the openclaw user inside the Incus guest
_oc := "incus exec " + target + " --cwd /tmp -- sudo -u openclaw"

# List available commands
default:
    @just --list

# Print a one-time pairing URL for the Control UI
pair:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    OUTPUT=$({{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw dashboard --no-open 2>&1) || {
      echo "Error: could not get dashboard URL. Is the container running?" >&2
      echo "$OUTPUT" >&2
      exit 1
    }
    URL=$(echo "$OUTPUT" | grep -o 'http://[^ ]*' || true)
    if [[ -z "$URL" ]]; then
      echo "Error: no URL found in output:" >&2
      echo "$OUTPUT" >&2
      exit 1
    fi
    if [[ -n "{{domain}}" ]]; then
      URL=$(echo "$URL" | sed "s#http://127.0.0.1:18789#https://{{domain}}#")
    fi
    echo "$URL"

# List pending device pairing requests
devices:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    {{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw devices list

# Approve a device pairing request
approve request_id:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    {{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw devices approve "{{request_id}}"

# Approve the most recent pending device pairing request
approve-latest:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    {{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw devices approve --latest

# Approve all pending device pairing requests
approve-all:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    PENDING=$({{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw devices list 2>&1 | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' || true)
    if [[ -z "$PENDING" ]]; then
      echo "No pending requests."
      exit 0
    fi
    for REQ in $PENDING; do
      echo "Approving $REQ..."
      {{_oc}} podman exec -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
        openclaw openclaw devices approve "$REQ" 2>&1 || true
    done

# Print the gateway auth token
token:
    @incus exec {{target}} -- cat /home/openclaw/.openclaw/.env 2>/dev/null | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2

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
    {{_oc}} podman ps 2>/dev/null || true
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
      {{_oc}} podman logs -f openclaw
    else
      {{_oc}} podman logs --tail 50 openclaw
    fi

# Manage the openclaw systemd service (status, start, stop, restart)
service verb="status":
    incus exec {{target}} -- systemctl --machine openclaw@ --user {{verb}} openclaw.service

# Run openclaw CLI commands (e.g. just openclaw onboard, just openclaw --help)
openclaw *ARGS:
    #!/usr/bin/env bash
    set -eo pipefail
    TOKEN=$(incus exec {{target}} -- cat /home/openclaw/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN | cut -d= -f2)
    incus exec {{target}} --cwd /tmp -t -- sudo -u openclaw podman exec -it \
      -e OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
      openclaw openclaw {{ARGS}}

# Show rootless Podman containers
podman *ARGS:
    {{_oc}} podman {{ARGS}}

# Push and run setup script on an existing container (no cloud-init)
setup:
    incus file push scripts/setup-openclaw.sh {{target}}/root/setup-openclaw.sh
    incus exec {{target}} -- chmod +x /root/setup-openclaw.sh
    incus exec {{target}} -- /root/setup-openclaw.sh

# Traefik reverse proxy status
traefik verb="status":
    incus exec {{target}} -- systemctl --machine openclaw@ --user {{verb}} traefik.service

# Show Traefik logs (-f to follow)
traefik-logs *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ARGS}}" == *"-f"* ]]; then
      {{_oc}} podman logs -f traefik
    else
      {{_oc}} podman logs --tail 50 traefik
    fi

# Pull latest OpenClaw image and restart the service (in-place upgrade)
upgrade:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Pulling latest image..."
    {{_oc}} podman pull ghcr.io/openclaw/openclaw:main-slim
    echo "Restarting OpenClaw service..."
    incus exec {{target}} -- systemctl --machine openclaw@ --user restart openclaw.service
    sleep 10
    echo "Verifying..."
    {{_oc}} podman exec openclaw openclaw gateway status 2>/dev/null || echo "(status check unavailable)"
    echo "Upgrade complete."

# Launch a new OpenClaw container (verbose by default, PODCLAW_QUIET=1 to suppress log tailing)
launch:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{quiet}}" ]]; then
      export PODCLAW_VERBOSE=1
    fi
    ./scripts/podclaw-quickstart.sh

# Delete the container (requires confirmation)
destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "This will permanently delete: {{target}}"
    read -rp "Are you sure? [y/N] " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
      incus delete --force {{target}}
      echo "Deleted."
    else
      echo "Cancelled."
    fi
