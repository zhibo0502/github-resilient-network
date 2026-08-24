---
name: github-resilient-network
description: Operate GitHub repositories from this Windows host when HTTPS is intermittent or proxy routing is ambiguous. Use for GitHub connection resets or timeouts, proxy bypass, resilient fetch/push, connector-based Git publication, branch synchronization, or safe branch deletion. Do not use for ordinary healthy local-only Git work.
---

# GitHub Resilient Network

Reproduce this host's reliable GitHub workflow without changing global proxy, remote, credential, or SSH configuration.

## Workflow

1. Read applicable `AGENTS.md`, then inspect `git status --short`, current branch, `git worktree list`, remotes, and local/tracking SHAs. Preserve dirty work and unrelated branches.
2. Measure the current path; do not assume the last incident is still active:
   - inspect Git proxy config, proxy environment variable presence, and `netsh winhttp show proxy` without exposing credential-bearing values;
   - resolve `github.com` and test IPv4 HTTPS with `curl.exe -4 -I --noproxy "*" --connect-timeout 8 https://github.com`;
   - run read-only Git through a child PowerShell process, normally `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/git-direct.ps1 ls-remote --heads origin`.
3. Select the first proven route:
   - **Direct Git:** use `scripts/git-direct.ps1` for fetch, push, and explicitly authorized ref deletion. It clears proxy variables and Git proxy config for that child process only.
   - **GitHub connector:** when local HTTPS is unavailable, use connector branch/commit/file readback. Publish only a committed and tested local Git state. Build every blob from that commit object (`git cat-file blob <commit>:<path>`), obtain its mode from `git ls-tree <commit> -- <path>`, and preserve that mode in the connector tree; never publish filesystem bytes from an `autocrlf` checkout or mix staged and unstaged state. Base the tree on authoritative remote main, create a commit with that main as parent, confirm main has not advanced, then update the ref without force. Read back the main SHA, every changed blob, and every changed mode. Discover current connector tools first; if delete-ref is unavailable, leave deletion pending or use Direct Git after recovery.
   - **SSH:** use only when `ssh -o BatchMode=yes -T git@github.com` output explicitly says the account successfully authenticated. GitHub may return exit code `1` even on successful authentication. `Permission denied (publickey)` is not a usable route. Never upload, replace, or register keys implicitly.
4. Before any write, resolve the exact repository, remote, base SHA, branch, changed files, and authorization. A request to publish does not authorize force push, global config edits, credential changes, or unrelated branch deletion.
5. Treat the same operation failing three consecutive times as a stop condition. Do not increase concurrency or timeouts to force success. A changed transport or later user-resumed attempt starts a fresh audit.
6. After a write, require authoritative readback:
   - fetch/`ls-remote` or connector comparison proves the expected main/ref SHA;
   - file publication proves every remote blob and file mode matches the tested Git object;
   - branch deletion proves the exact remote branch is absent;
   - local `main` is fast-forwarded in the worktree that owns it, and local/tracking/main SHAs are reported separately.

## Branch safety

- Do not merge a diverged historical branch wholesale when main already contains cherry-picked, squashed, or strengthened equivalents. Identify its genuinely unique commits, review them, integrate them onto current main, and test that combined tree.
- Delete a branch only after main contains equivalent or stronger content and the exact local/remote target is confirmed. With multiple worktrees, update main in its owning worktree, detach the feature worktree at current `origin/main`, then delete only the named local branch.
- Keep production deployment, database writes, cron changes, PR creation, and release actions outside this workflow unless separately authorized.

## Host-specific interpretation

This host has shown intermittent direct GitHub 443 timeouts while IPv4 HTTPS later recovered without a configuration change. WinHTTP has normally been direct, and SSH has been reachable while existing keys were not authorized. These are diagnostic clues only; live checks decide every run.
