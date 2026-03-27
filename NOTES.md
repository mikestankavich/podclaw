# Podclaw Notes & Threat Model

This document tracks security assumptions, boundaries, and design decisions for Podclaw.

## Host roles

Podclaw assumes a **two-host model**:

- **Production host** -- your real homelab or workstation. Out of scope for Podclaw
  experiments. OpenClaw containers should never touch this host.
- **Sacrificial host** -- a dedicated machine running Ubuntu 24.04 LTS with Incus.
  Acceptable assumption: this machine can be rooted or reinstalled without serious loss.

## High-level threat model

- We assume:
  - OpenClaw and any agents it controls may be **malicious or compromised**.
  - AI coding agents may make mistakes, generate unsafe commands, or mis-handle secrets.
  - The Incus daemon on the sacrificial host is trusted but exposed only locally.

- We want to prevent:
  - Lateral movement from the sacrificial host into production hosts or other important infrastructure.
  - Access to SSH keys, API tokens, or sensitive data outside this lab.
  - Host-level persistence that survives a full wipe/reinstall of the sacrificial host.

## Allowed vs disallowed on the sacrificial host

**Allowed**

- Creating/modifying Incus containers using profiles defined in `profiles/`.
- Running rootless Podman / Docker **inside** Incus containers.
- Installing and running OpenClaw and supporting tooling in those containers.
- Pulling container images from public registries (GHCR, Docker Hub).
- Storing non-sensitive logs and build artifacts.

**Not allowed**

- Adding Incus `disk` devices that mount host paths outside container rootfs.
- Setting `security.privileged=true` on containers, unless explicitly documented and justified.
- Adding new network devices that reach other VLANs / management networks.
- Copying SSH private keys, API tokens, or secrets from other machines into the lab host.
- Configuring the lab host as a router or gateway for the rest of the network.

## OpenClaw networking and exposure

- Default stance:
  - OpenClaw gateways bind to **127.0.0.1** inside their Incus container.
  - Access from outside the container is via the container's LAN IP (bridged profile)
    or SSH port forwarding.
- LAN exposure:
  - Only recommended through an explicit reverse proxy or load balancer that:
    - Terminates TLS.
    - Enforces authentication.
    - Is documented with config and diagrams.
- No OpenClaw instance from this lab should be exposed directly to the public internet.

## Resource and blast-radius limits

- Incus profiles should:
  - Set sensible CPU and RAM limits for containers where practical.
  - Use a dedicated storage pool if possible, so lab cleanup is just a pool wipe.
- If the lab becomes unstable or confusing:
  - Preferred remediation is to:
    - Stop and delete all Incus containers on the sacrificial host.
    - Optionally wipe the Incus storage pool.
    - Rebuild from a clean Ubuntu 24.04 install using Podclaw configs.

## Lessons learned: rootless Podman in Incus

These are gotchas discovered while building the cloud-init automation. They apply to
anyone running rootless Podman inside unprivileged Incus system containers on Ubuntu 24.04.

### AppArmor blocks unprivileged user namespaces

Ubuntu 24.04 sets `kernel.apparmor_restrict_unprivileged_userns=1`, which blocks rootless
Podman (and any unprivileged user namespace creation) inside Incus containers. You must
install AppArmor profiles granting `userns` permission to: `podman`, `conmon`, `crun`,
`slirp4netns`, and `pasta`.

Example profile:
```
abi <abi/4.0>,
include <tunables/global>
profile podman /usr/bin/podman flags=(unconfined) {
  userns,
}
```

Load with `apparmor_parser -r`. Must be done **before** running OpenClaw's setup script.

### fuse-overlayfs is critical for performance

Rootless Podman with `--userns keep-id` triggers `storage-chown-by-maps`, which recursively
chowns the entire image overlay. For large images (3+ GB) this takes 10+ minutes and causes
systemd timeouts. Fix: use `fuse-overlayfs` as the storage driver.

```ini
# ~/.config/containers/storage.conf
[storage]
driver = "overlay"
[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

This handles UID mapping in FUSE and skips the chown entirely.

### Incus profile requirements

Rootless `podman build` inside Incus fails without `security.nesting=true`. The Incus
profile must also set `security.syscalls.intercept.mknod=true` and
`security.syscalls.intercept.setxattr=true`.

### Cloud-init ordering matters

The `runcmd` order must be:
1. Install `fuse-overlayfs` and `apparmor-utils` (via packages)
2. Create and load AppArmor userns profiles
3. Create the service user and configure `storage.conf`
4. Run OpenClaw's `setup-podman.sh` / `scripts/podman/setup.sh`

All rootless Podman prerequisites must be in place before the setup script runs.

### Service user creation

Pre-creating the `openclaw` user with `useradd -m -s /usr/sbin/nologin` in cloud-init
runcmd works -- the setup script detects the existing user and skips creation. However,
using cloud-init's `users:` directive with `system: true` inhibits home directory creation
and causes conflicts.

### Other gotchas

- OpenClaw's `scripts/podman/setup.sh` refuses to run as root. Run it as the service user.
- `sudo -iu` fails for users with `/usr/sbin/nologin` shell; use `sudo -u` instead.
- Cloning repos as root then running scripts as another user causes permission mismatches --
  `chown` the clone before running setup.
- The Quadlet service name is `openclaw.service`, not `openclaw-gateway.service`.
- Quadlet-generated units are transient -- `systemctl enable` fails with "Unit is transient
  or generated". This is expected; the unit starts via the systemd generator.
- The Quadlet uses `--bind lan` (0.0.0.0). This requires either
  `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true` (lab only) or an
  explicit `gateway.controlUi.allowedOrigins` list in `openclaw.json`. Pre-create the
  config before the setup script runs (it skips creation if the file exists).

## Version pinning strategy

OpenClaw ships daily releases (e.g. `v2026.3.24`). The cloud-init template clones `main`
at container launch time with no pinned commit or tag. This means every fresh container
gets whatever is current on `main` at boot.

**Trade-offs:**
- *Pro:* No version drift -- each fresh container is up-to-date automatically.
- *Con:* A breaking change on `main` can silently break new container launches.
- *Current decision:* Accept the risk for lab use. OpenClaw's daily releases are generally
  backward-compatible and `scripts/podman/setup.sh` handles most wiring.
- *If stability becomes a problem:* Pin to a release tag by changing the clone step to
  `git clone --branch v2026.X.Y --depth 1 https://github.com/openclaw/openclaw /opt/openclaw`.

As of March 2026, the root-level `setup-podman.sh` still exists but `scripts/podman/setup.sh`
is the newer maintained path (includes Quadlet template support via `openclaw.container.in`).

## Open questions / TODOs

- [ ] Decide whether to pin container CPU cores for more deterministic performance.
- [ ] Add automated checks (scripts or CI) that lint cloud-init and profiles for disallowed patterns.
- [ ] Add example OpenClaw reverse-proxy + TLS configuration.
- [ ] Replace `dangerouslyAllowHostHeaderOriginFallback` with explicit `gateway.controlUi.allowedOrigins` before any non-lab deployment.
