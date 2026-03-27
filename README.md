# Podclaw

Run **OpenClaw** in a rootless Podman container inside an **Incus** guest -- fully automated via cloud-init, with blast-radius isolation and easy teardown. Built for homelab users who want disposable AI agent sandboxes without risking real infrastructure.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Incus host  (k8s-delta, sacrificial)       │
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

  Reference configs are in [`profiles/`](profiles/) (named `ralph-bridged.yml` and `ralph-nesting.yml`). The launch scripts expect the profile names `bridged` and `docker` on your Incus host.

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

./scripts/podclaw-quickstart.sh my-openclaw k8s-delta
```

This will:
1. Launch an Ubuntu 24.04 Incus guest with the right profiles
2. Run cloud-init to install Podman, configure AppArmor for rootless userns, and build the OpenClaw container image
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

- **Homelab / Incus users** who want isolated, disposable OpenClaw sandboxes
- **Infra engineers** exploring rootless Podman inside system containers
- **AI agent experimenters** who want blast-radius isolation for agent workloads

### Non-goals

- This is not a one-click VPS deployment. For that, see the [official OpenClaw install docs](https://docs.openclaw.ai/install/).
- This is not a production-hardened setup. The `dangerouslyAllowHostHeaderOriginFallback` config flag and open gateway binding are lab-only choices.

## Repository layout

### OpenClaw deployment (the main event)

| Path | Purpose |
|------|---------|
| `cloud-init/openclaw-podman-skeleton.yml` | Cloud-init template for OpenClaw experiment containers |
| `profiles/ralph-bridged.yml` | Reference Incus profile: bridged NIC (no host mounts) |
| `profiles/ralph-nesting.yml` | Reference Incus profile: nesting for rootless Podman |
| `scripts/podclaw-quickstart.sh` | One-command launch, wait, and verify |
| `scripts/launch-experiment.sh` | Launch an experiment container (no wait/verify) |
| `scripts/cleanup-experiments.sh` | Delete experiment containers by prefix |
| `NOTES.md` | Threat model, security boundaries, lessons learned |

### Ralph autonomous agent (how this was built)

This repo was built by [Ralph](https://github.com/mikestankavich/ralph-sandbox) -- an autonomous Claude Code agent iterating on the deployment inside a sandboxed Incus container. The Ralph tooling lives in a separate repo.

## Design principles

- **Sacrificial host only** -- all experiments run on a dedicated box with no important data
- **Rootless by default** -- OpenClaw runs under a non-privileged user in rootless Podman, with Incus as the outer boundary
- **Agent-friendly, human-auditable** -- cloud-init, profiles, and scripts are small, idempotent, and version-controlled
- **Easy nuke-and-rebuild** -- delete the container and start fresh; rebuild the host if needed

## Key implementation details

Things we learned the hard way (full details in [NOTES.md](NOTES.md)):

- **AppArmor userns profiles** are required on Ubuntu 24.04 -- the kernel blocks unprivileged user namespaces by default. We install profiles for `podman`, `conmon`, `crun`, `slirp4netns`, and `pasta`.
- **fuse-overlayfs** is critical -- without it, rootless Podman with `--userns keep-id` triggers a 10+ minute recursive chown on the 3GB OpenClaw image.
- **Cloud-init ordering matters** -- AppArmor profiles and storage config must be in place before `setup-podman.sh` runs.
- **Quadlet units are transient** -- `systemctl enable` fails on them (expected). They start via the systemd generator.

## Security

See [NOTES.md](NOTES.md) for the full threat model. Key points:

- No `security.privileged=true` on any container
- No host path mounts from Incus guests
- Gateway auth token generated automatically at boot
- OpenClaw gateways bind to loopback by default; LAN binding requires explicit config
- The sacrificial host (k8s-delta) is assumed to be expendable

## Hardware

- **k8s-delta** (sacrificial lab host): GMKtec M6, 64 GB RAM, 2 TB NVMe, Ubuntu 24.04 LTS
- **k8s-alpha** (real homelab, out of scope): Minisforum HX370, 96 GB RAM, 2 TB NVMe
