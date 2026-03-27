# CLAUDE.md

This file provides guidance to Claude Code when working in the podclaw repository.

## Project Overview

Podclaw is a recipe for running OpenClaw (AI agent gateway) on rootless Podman inside
Incus containers. The repo contains cloud-init templates, Incus profiles, and helper
scripts -- not application code.

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

### You MAY:
- Edit files in this repo, commit, push branches, create PRs
- Run `incus launch`, `incus exec`, `incus delete` targeting configured remotes
- Use the predefined profiles in `profiles/` when launching containers
- Install packages inside Incus containers you create
- Run rootless Podman or Docker inside experiment containers

### You MUST NOT:
- Modify host-level Incus configuration outside the repo profiles
- Add host path mounts (`disk` devices) to any container
- Set `security.privileged=true` without explicit human approval
- Generate or install SSH keys for remote access to other hosts
- Commit secrets, tokens, or keys to git (check .gitignore)
- Print tokens or secrets in output

## Key File Locations

| Path | Purpose |
|------|---------|
| `cloud-init/openclaw-podman-skeleton.yml` | Cloud-init template for OpenClaw containers |
| `profiles/openclaw-bridged.yml` | Reference: bridged NIC profile |
| `profiles/openclaw-nesting.yml` | Reference: security.nesting for rootless Podman |
| `scripts/podclaw-quickstart.sh` | One-command launch, wait, and verify |
| `NOTES.md` | Threat model, boundaries, lessons learned |

## Environment

- Secrets in `.env.local` (gitignored) -- loaded via direnv
- Container naming convention: `oc-exp-<timestamp>` for experiments
- OpenClaw gateway default port: 18789 (loopback only)
