# Podclaw

Run **OpenClaw** in a rootless Podman container inside an **Incus** guest -- fully automated via cloud-init. One command gives you an isolated, disposable OpenClaw instance with no impact on your host.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Incus host                                 │
│                                             │
│  ┌────────────────────────────────────────┐ │
│  │  Incus guest  (Ubuntu 24.04)           │ │
│  │  Profiles: bridged + nesting           │ │
│  │                                        │ │
│  │  ┌──────────────────────────────────┐  │ │
│  │  │  Rootless Podman  (user: openclaw) │ │
│  │  │  ┌────────────────────────────┐  │  │ │
│  │  │  │  OpenClaw gateway          │  │  │ │
│  │  │  │  :18789 (loopback / LAN)   │  │  │ │
│  │  │  └────────────────────────────┘  │  │ │
│  │  │  Managed by Quadlet / systemd    │  │ │
│  │  │  --user service                  │  │ │
│  │  └──────────────────────────────────┘  │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

The OpenClaw gateway runs as a single Node.js process inside a rootless Podman container, managed by a systemd user service via Quadlet. The Incus guest provides the outer isolation boundary -- no host path mounts, no privileged mode.

## Quick start

### Prerequisites

- **Incus host** with the following profiles available:

  | Profile | Purpose | How to create |
  |---------|---------|---------------|
  | `default` | Root disk + managed network | Ships with Incus (`incus admin init`) |
  | `bridged` | Bridged NIC on a host bridge (e.g. `br0`) | `incus profile create bridged` then add a `nic` device with `nictype: bridged` and `parent: br0` |
  | `docker` | `security.nesting=true` + syscall intercepts for rootless Podman | `incus profile create docker` then set `security.nesting=true`, `security.syscalls.intercept.mknod=true`, `security.syscalls.intercept.setxattr=true` |

  Reference configs are in [`profiles/`](profiles/). The launch script defaults to profile names `bridged` and `docker` -- override with `PODCLAW_PROFILE_BRIDGED` and `PODCLAW_PROFILE_NESTING` env vars to match your environment.

- **Ubuntu 24.04 LTS** recommended for the Incus guest image
- `git`, `curl`, and `incus` CLI on the machine you're launching from
- OpenClaw LLM API keys (Anthropic, OpenAI, etc.) -- configured post-launch via the Control UI

### One-command launch

```bash
git clone https://github.com/mikestankavich/podclaw.git
cd podclaw

# Configure your admin user (or put these in .env.local)
export PODCLAW_ADMIN_USER="yourname"
export PODCLAW_SSH_KEY="ssh-ed25519 AAAA..."

# Local Incus host:
./scripts/podclaw-quickstart.sh my-openclaw

# Or target a remote Incus host:
./scripts/podclaw-quickstart.sh my-openclaw your-remote
```

This will:
1. Launch an Ubuntu 24.04 Incus guest with the right profiles
2. Run cloud-init to install Podman, configure AppArmor for rootless userns, and pull the OpenClaw container image
3. Start the OpenClaw gateway as a Quadlet systemd user service
4. Wait for everything to come up and print access URLs

Full boot takes ~1-2 minutes (pulls a pre-built image from GHCR, no local build).

### Manual step-by-step

If you prefer to control each step:

```bash
# 0. Set required variables (or source .env.local)
export PODCLAW_ADMIN_USER="yourname"
export PODCLAW_SSH_KEY="ssh-ed25519 AAAA..."

# 1. Launch the Incus guest
incus launch images:ubuntu/24.04/cloud my-openclaw \
  -p default -p bridged -p docker \
  --config=cloud-init.user-data="$(envsubst '${PODCLAW_ADMIN_USER} ${PODCLAW_SSH_KEY}' < cloud-init/openclaw-podman-skeleton.yml)"

# 2. Wait for cloud-init
incus exec my-openclaw -- cloud-init status --wait

# 3. Verify the gateway
incus exec my-openclaw -- curl -s http://127.0.0.1:18789/

# 4. Check the service
incus exec my-openclaw -- sudo -u openclaw systemctl --user status openclaw.service
incus exec my-openclaw -- sudo -u openclaw podman ps
```

### Accessing the gateway

The gateway listens on port 18789 inside the Incus guest. If your guest has a LAN IP (bridged profile), you can reach the Control UI directly:

```
http://<guest-ip>:18789/
```

From there, configure your LLM API keys and start using agents.

### Tear down

```bash
incus delete --force my-openclaw
```

That's it. No cleanup, no leftover state on the host.

## Who this is for

- **Homelab / Incus users** who want a clean, containerized OpenClaw setup
- **Infra engineers** exploring rootless Podman inside system containers
- **AI agent experimenters** who want isolated OpenClaw instances they can spin up and tear down

### Non-goals

- This is not a one-click VPS deployment. For that, see the [official OpenClaw install docs](https://docs.openclaw.ai/install/).
- This is not a production-hardened setup. The `dangerouslyAllowHostHeaderOriginFallback` config flag and open gateway binding are lab-only choices.

## Repository layout

| Path | Purpose |
|------|---------|
| `cloud-init/openclaw-podman-skeleton.yml` | Cloud-init template for OpenClaw containers |
| `profiles/openclaw-bridged.yml` | Reference Incus profile: bridged NIC (no host mounts) |
| `profiles/openclaw-nesting.yml` | Reference Incus profile: nesting for rootless Podman |
| `scripts/podclaw-quickstart.sh` | One-command launch, wait, and verify |
| `NOTES.md` | Threat model, security boundaries, lessons learned |

## Design principles

- **Container isolation** -- OpenClaw runs inside an Incus guest with no host path mounts or privileged mode
- **Rootless by default** -- OpenClaw runs under a non-privileged user in rootless Podman
- **Reproducible** -- cloud-init, profiles, and scripts are small, idempotent, and version-controlled
- **Disposable** -- delete the container and start fresh; no cleanup needed on the host

## Key implementation details

Things we learned the hard way (full details in [NOTES.md](NOTES.md)):

- **AppArmor userns profiles** are required on Ubuntu 24.04 -- the kernel blocks unprivileged user namespaces by default. We install profiles for `podman`, `conmon`, `crun`, `slirp4netns`, and `pasta`.
- **fuse-overlayfs** is critical -- without it, rootless Podman with `--userns keep-id` triggers a 10+ minute recursive chown on large container images.
- **Cloud-init ordering matters** -- AppArmor profiles and storage config must be in place before the OpenClaw setup script runs.
- **Quadlet units are transient** -- `systemctl enable` fails on them (expected). They start via the systemd generator.

## Security

See [NOTES.md](NOTES.md) for details.

- No `security.privileged=true` on any container
- No host path mounts from Incus guests
- Gateway auth token generated automatically at boot
- OpenClaw gateways bind to loopback by default; LAN binding requires explicit config
