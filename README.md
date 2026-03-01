# Podclaw

Podclaw is a homelab-friendly playground for running **OpenClaw** on **rootless Podman** inside **Incus** containers.

The goal is to give AI agents (Claude + "Ralph") a safe, disposable environment to iterate on OpenClaw deployments without putting real infrastructure or data at risk.

## Design goals

- **Sacrificial host only**
  All experiments run on a dedicated box (k8s-delta) with no important data and no shared host path mounts.

- **Rootless by default**
  OpenClaw runs under a non-privileged user in rootless Podman, using Incus containers as the outer boundary.

- **Agent-friendly, human-auditable**
  Cloud-init, Incus profiles, and scripts are small, idempotent, and stored in this repo so both humans and AI agents can reason about them.

- **Easy nuke-and-rebuild**
  If (when) things go sideways, you can delete experiment containers or rebuild the entire host from scratch with minimal ceremony.

## Components

- `profiles/`
  Incus profile definitions for the sacrificial host:
  - `ralph-bridged.yml` -- bridged NIC, no host mounts.
  - `ralph-nesting.yml` -- enables nested Podman/Docker where needed.

- `cloud-init/`
  Cloud-init configs for:
  - `ralph-sandbox.yml` -- Claude Code + tools sandbox on the victim host.
  - `openclaw-podman-skeleton.yml` -- base for OpenClaw + rootless Podman experiment containers.

- `scripts/`
  Helper scripts for:
  - Configuring a fine-grained GitHub token for this repo only.
  - Launching and cleaning up experiment containers.
  - (Later) starting OpenClaw via Podman or systemd user services.

- `NOTES.md`
  Threat model, safety assumptions, and "what I'm willing to lose" written down explicitly.

## High-level workflow

1. **Prepare the victim host**
   - Choose a sacrificial machine (k8s-delta) running Ubuntu 24.04 LTS.
   - Remove old Incus containers and any host path mounts.
   - Create minimal Incus profiles from `profiles/`.

2. **Create the Ralph sandbox**
   - Launch `ralph-sandbox` on the victim with `cloud-init/ralph-sandbox.yml`.
   - Install Claude Code CLI and the "Ralph" skills in that container.
   - Configure a fine-grained GitHub token that can only access this repo.

3. **Iterate on OpenClaw experiments**
   - Ralph/Claude edits `cloud-init/openclaw-podman-skeleton.yml` and helper scripts in this repo.
   - From `ralph-sandbox`, launch experiment containers with Incus using that cloud-init.
   - Inside those containers, run OpenClaw under rootless Podman and refine until it's boring and reliable.

4. **Reset when necessary**
   - Delete experiment containers or rebuild the entire victim host when the lab gets messy.
   - Keep k8s-alpha and any real workloads out of this blast radius.

## Security notes (non-exhaustive)

- Podclaw assumes:
  - The sacrificial host has **no important secrets or data**.
  - There are **no host path mounts** from Incus containers into sensitive directories.
  - The Ralph sandbox user has **no SSH keys** to other machines.
  - OpenClaw gateways created here are initially **bound to loopback**; any LAN exposure is deliberate and proxied.

For more detailed security assumptions and boundaries, see `NOTES.md`.

## Status

This repo starts as a **lab notebook and harness**, not a polished product. Expect rough edges, breaking changes, and plenty of "Ralph Wiggum" experiments as we converge on a clean, repeatable pattern for OpenClaw on rootless Podman in Incus.

## Hardware

- **k8s-delta** (sacrificial lab host): GMKtec M6, 64 GB RAM, 2 TB NVMe, Ubuntu 24.04 LTS
- **k8s-alpha** (real homelab, out of scope): Minisforum HX370, 96 GB RAM, 2 TB NVMe
