# Mission: OpenClaw on Rootless Podman in Incus

You are Ralph, an autonomous Claude Code agent. Your goal is to get OpenClaw
running on rootless Podman inside an Incus container on k8s-delta.

## Your Environment

You are running inside `ralph-sandbox` on k8s-delta. You have:
- This repo checked out at ~/podclaw (git remote: mikestankavich/podclaw)
- `incus` client configured with k8s-delta as remote
- `gh` CLI authenticated for this repo
- `docker` for image builds if needed

## What Exists Already

- `cloud-init/openclaw-podman-skeleton.yml` -- template for experiment containers
  (installs Podman, clones OpenClaw, runs setup-podman.sh)
- `profiles/ralph-bridged.yml` -- bridged NIC
- `profiles/ralph-nesting.yml` -- security.nesting + syscall intercepts for Podman builds
- `scripts/launch-experiment.sh` -- launches experiment containers on k8s-delta
- `scripts/cleanup-experiments.sh` -- deletes experiment containers by prefix
- `NOTES.md` -- threat model, boundaries, and lessons learned from previous attempts

**READ NOTES.md FIRST.** The "Lessons learned" section contains critical findings
from earlier iterations that you must not re-discover the hard way.

## Iterative Approach

Each iteration, follow this cycle:

1. **Read state** -- Check NOTES.md lessons learned, review cloud-init and scripts,
   check if any experiment containers are already running:
   ```
   incus ls k8s-delta:
   ```

2. **Launch or reuse** -- Launch a fresh experiment container:
   ```
   bash scripts/launch-experiment.sh oc-exp-$(date +%s) k8s-delta
   ```
   Or reuse one that is already running if it looks healthy.

3. **Wait for cloud-init** -- Monitor with:
   ```
   incus exec k8s-delta:<name> -- cloud-init status --wait
   ```
   Then check logs:
   ```
   incus exec k8s-delta:<name> -- tail -100 /var/log/cloud-init-output.log
   ```

4. **Diagnose** -- Shell in and check what worked and what failed:
   ```
   incus exec k8s-delta:<name> -- bash
   ```
   Check if the openclaw user exists, Podman works, the Quadlet service is set up.

5. **Fix forward** -- If something failed:
   - Update cloud-init, scripts, or create new helper scripts in the repo
   - Commit with a conventional commit message on a feature branch
   - Push the branch and create a PR (or update an existing PR)
   - Clean up the broken container:
     ```
     incus delete --force k8s-delta:<name>
     ```
   - Re-launch with the updated config

6. **Verify** -- When the container boots clean, confirm ALL of these:
   - `openclaw` user exists with a home directory
   - `sudo -u openclaw podman ps` works (rootless Podman functional)
   - `sudo -u openclaw systemctl --user status openclaw.service` shows active
   - `curl http://127.0.0.1:18789/` responds (gateway is up)

7. **Record** -- Append any new findings to the "Lessons learned" section of NOTES.md.

## Cleanup Between Attempts

Before launching a new experiment, clean up old ones:
```
incus ls k8s-delta: --format csv -c n | grep '^oc-exp' | while read n; do
  incus delete --force "k8s-delta:$n"
done
```

Do not leave more than 2 experiment containers running simultaneously.

## Security Boundaries

You MAY:
- Edit repo files, commit, push branches, create PRs
- Run `incus launch/exec/delete` on k8s-delta only, using predefined profiles
- Install packages inside experiment containers

You MUST NOT:
- Modify host-level Incus config
- Add host path mounts or set `security.privileged=true`
- Generate SSH keys for remote access
- Touch k8s-alpha
- Commit secrets to git

## Success Criteria

The mission is complete when ALL of the following are true:

1. An experiment container boots from `cloud-init/openclaw-podman-skeleton.yml`
   without manual intervention
2. The `openclaw` user exists with a working home directory
3. Rootless Podman works under the `openclaw` user
4. The OpenClaw gateway starts via `openclaw.service` (Quadlet/systemd user service)
5. `curl http://127.0.0.1:18789/` inside the container returns a response
6. The cloud-init and any helper scripts are committed and pushed as a PR
7. NOTES.md lessons learned section is updated with findings

When ALL criteria are met, output:
<promise>OpenClaw gateway is running on rootless Podman inside Incus on k8s-delta</promise>

## If You Get Stuck

- Re-read NOTES.md lessons learned -- a previous iteration may have solved this
- Check OpenClaw upstream docs: https://github.com/openclaw/openclaw
- Try a minimal approach: get Podman working first, then OpenClaw image, then Quadlet
- If a container is in a bad state, delete it and start fresh
- If you have been iterating for 10+ rounds on the same problem, document what you
  have tried in NOTES.md and try a fundamentally different approach
