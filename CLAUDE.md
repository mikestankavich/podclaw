# CLAUDE.md

This file provides guidance to Claude Code when working in the podclaw repository.

## Project Overview

Podclaw is a homelab harness for running OpenClaw (AI agent gateway) on rootless Podman
inside Incus containers on a sacrificial host (k8s-delta). The repo contains cloud-init
templates, Incus profiles, helper scripts, and mission prompts -- not application code.

See NOTES.md for the full threat model and lessons learned.

## Git Workflow

- NEVER push directly to main -- always use feature branches and PRs
- Branch naming: `feature/descriptive-name`, `fix/descriptive-name`, `docs/descriptive-name`
- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- Merge strategy: always `--merge` (never squash, never rebase)
- Prefer incremental commits over amending

## Code Style

- Shell scripts: [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- YAML: 2-space indentation
- Markdown: clear headings, concise language
- No file should exceed 500 lines -- split if needed

## Security Boundaries

These rules apply to ALL sessions -- human-driven or autonomous (Ralph).

### You MAY:
- Edit files in this repo, commit, push branches, create PRs
- Run `incus launch`, `incus exec`, `incus delete` targeting k8s-delta ONLY
- Use the predefined profiles in `profiles/` when launching containers
- Install packages inside Incus containers you create
- Run rootless Podman or Docker inside experiment containers

### You MUST NOT:
- Modify host-level Incus configuration outside the repo profiles
- Add host path mounts (`disk` devices) to any container
- Set `security.privileged=true` without explicit human approval
- Generate or install SSH keys for remote access to other hosts
- Touch k8s-alpha or any host other than k8s-delta
- Commit secrets, tokens, or keys to git (check .gitignore)
- Print tokens or secrets in output

## Available Tooling

Inside ralph-sandbox on k8s-delta:
- `incus` -- configured with k8s-delta as remote
- `docker` -- available for image builds
- `gh` -- GitHub CLI, authenticated with fine-grained PAT (scoped to mikestankavich/podclaw)
- `podman` -- available inside experiment containers (not in sandbox itself)

## Key File Locations

| Path | Purpose |
|------|---------|
| `cloud-init/openclaw-podman-skeleton.yml` | Template for experiment containers |
| `cloud-init/ralph-sandbox.yml` | Sandbox container cloud-init |
| `profiles/ralph-bridged.yml` | Bridged NIC profile |
| `profiles/ralph-nesting.yml` | security.nesting for Podman builds |
| `scripts/launch-experiment.sh` | Launch experiment containers |
| `scripts/cleanup-experiments.sh` | Delete experiment containers by prefix |
| `scripts/launch-sandbox.sh` | Launch and bootstrap ralph-sandbox |
| `missions/` | Ralph-loop mission prompts |
| `NOTES.md` | Threat model, boundaries, lessons learned |

## Environment

- Secrets in `.env.local` (gitignored) -- loaded via direnv
- Container naming convention: `oc-exp-<timestamp>` for experiments
- OpenClaw gateway default port: 18789 (loopback only)
