# Podclaw Notes & Threat Model

This document tracks security assumptions, boundaries, and design decisions for the Podclaw lab.

## Hosts and roles

- **k8s-alpha**
  - Minisforum HX370, 96 GB RAM, 2 TB NVMe.
  - "Real" homelab box for useful workloads, Incus sandboxes, dev tools, local models.
  - **Out of scope** for Podclaw experiments; Ralph and OpenClaw should not touch this host.

- **k8s-delta**
  - GMKtec M6, 64 GB RAM, 2 TB NVMe, Ubuntu 24.04 LTS.
  - Designated **sacrificial Podclaw lab host**.
  - Acceptable assumption: this machine can be rooted or reinstalled without serious loss.

## High-level threat model

- We assume:
  - OpenClaw and any agents it controls may be **malicious or compromised**.
  - Claude + Ralph skills may make mistakes, generate unsafe commands, or mis-handle secrets.
  - The Incus daemon on k8s-delta is trusted but exposed only locally.

- We want to prevent:
  - Lateral movement from k8s-delta into k8s-alpha or other important hosts.
  - Access to SSH keys, API tokens, or sensitive data outside this lab.
  - Host-level persistence that survives a full wipe/reinstall of k8s-delta.

## Allowed vs disallowed on k8s-delta

**Allowed**

- Creating/modifying Incus containers using profiles defined in `profiles/`.
- Running rootless Podman / Docker **inside** Incus containers.
- Installing and running OpenClaw and supporting tooling in those containers.
- Building and pulling container images in the context of this host only.
- Storing non-sensitive logs and build artifacts on k8s-delta.

**Not allowed**

- Adding Incus `disk` devices that mount host paths outside container rootfs.
- Setting `security.privileged=true` on containers, unless explicitly documented and justified.
- Adding new network devices that reach other VLANs / management networks.
- Copying SSH private keys, API tokens, or secrets from other machines into k8s-delta.
- Configuring this host as a router or gateway for the rest of the homelab.

## Ralph / Claude Code boundaries

- Ralph runs inside a `ralph-sandbox` container on k8s-delta as a **non-root, non-sudo user**.
- Ralph may:
  - Edit files in this repo and push to the dedicated GitHub repository.
  - Call `incus launch/exec/delete` **on k8s-delta only**, using the predefined profiles.
  - Install packages inside Incus containers it creates.
- Ralph may **not**:
  - Modify host-level Incus configuration outside those profiles.
  - Add host path mounts or privileged containers without explicit human approval.
  - Generate or install SSH keys for remote access to other hosts.

## GitHub and secrets

- Podclaw uses a **fine-grained GitHub token**:
  - Scoped to a single private repo: `mikestankavich/podclaw`.
  - Permissions: repository contents read/write, optional PR permissions; everything else disabled.
- The token is stored on k8s-delta in:
  - `/home/ralph/.config/ralph/github.env`
  - Permissions: `600`, owned by `ralph`.
- The token must **never** be:
  - Committed to Git.
  - Printed in logs or terminal transcripts.
  - Reused for other repos or hosts.

## OpenClaw networking and exposure

- Default stance:
  - OpenClaw gateways created by Podclaw experiments bind to **127.0.0.1** inside their container.
  - Access is via SSH port forwarding or local curl from the host.
- LAN exposure:
  - Only allowed through an explicit reverse proxy or load balancer that:
    - Terminates TLS.
    - Enforces authentication.
    - Is documented in this repo with config and diagrams.
- No OpenClaw instance from this lab should be exposed directly to the public internet.

## Resource and blast-radius limits

- Incus profiles used by Podclaw experiments should:
  - Set sensible CPU and RAM limits for experimental containers where practical.
  - Use a dedicated storage pool if possible, so lab cleanup is just a pool wipe.
- If the lab becomes unstable or confusing:
  - Preferred remediation is to:
    - Stop and delete all Incus containers on k8s-delta.
    - Optionally wipe the Incus storage pool.
    - Rebuild from a clean Ubuntu 24.04 install using Podclaw configs.

## Lessons learned from initial OpenClaw setup

- `setup-podman.sh` assumes it creates the `openclaw` user itself; pre-creating it via cloud-init causes conflicts.
- `system: true` in cloud-init inhibits home directory creation.
- Rootless `podman build` inside Incus fails without `security.nesting=true` (the `docker` profile).
- The Quadlet service name is `openclaw.service`, not `openclaw-gateway.service`.
- `sudo -iu` fails for users with `/usr/sbin/nologin` shell; use `sudo -u` instead.
- Cloning repos as root then running scripts as another user causes permission mismatches.

## Open questions / TODOs

- [ ] Decide whether to pin container CPU cores for more deterministic performance.
- [ ] Decide if any experiments require `security.privileged=true`; document them explicitly.
- [ ] Add automated checks (scripts or CI) that lint cloud-init and profiles for disallowed patterns.
- [ ] Add example OpenClaw reverse-proxy + TLS configuration once the basic Podman path is stable.
- [ ] Evaluate whether to build OpenClaw images inside Incus or pull prebuilt from a registry.
