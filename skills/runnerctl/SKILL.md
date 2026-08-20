---
name: runnerctl
description: Safely manage GitHub Actions self-hosted runners with runnerctl on macOS and Linux.
---

# runnerctl AI AGENT skill

Use this skill when a user asks you to inspect, register, start, stop, troubleshoot, upgrade, or remove GitHub Actions self-hosted runners managed by `runnerctl`.

## Discover the installed contract first

```bash
runnerctl agent --json
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
runnerctl upgrade --check --json
```

For a target repository, resolve the account before mutation:

```bash
runnerctl auth resolve example-org/example-repo --json
```

Read focused help before mutating state:

```bash
runnerctl add --help
runnerctl upgrade --help
runnerctl remove --help
```

## Upgrade behavior

`runnerctl upgrade --check --json` is read-only apart from network access and is preferred before upgrading.

If an update is available and installation is intended:

```bash
runnerctl upgrade
```

`runnerctl self-update` is an alias. The CLI detects Homebrew, npm, pnpm, or shell installation and selects the matching update path.

Do not invent a package-manager command when `runnerctl upgrade` can determine it. If installation detection returns `unknown`, report that result instead of guessing.

A broken pre-v0.3.1 Homebrew wrapper may not be able to execute `runnerctl upgrade`; that installation requires a one-time Homebrew repair before future self-upgrades can work.

## Multi-account behavior

Do not assume the active GitHub CLI account is correct.

Prefer an explicit account:

```bash
runnerctl add example-org/example-repo --account work-account
```

or a repository mapping:

```bash
runnerctl auth map 'example-org/*' work-account
```

Avoid `runnerctl auth use ACCOUNT` unless the user actually wants to change the global active `gh` account.

## Runner creation

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci \
  --account work-account
```

Never invent the repository, account, count, or labels when they materially affect the setup.

## Logs

Agents must use finite log reads:

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

Do not use follow mode in unattended automation.

## Mutation classes

Mutations include runner registration, service state changes, account mappings, Git credential setup, global `gh` account changes, and installing runnerctl updates.

For bulk service operations, inspect `runnerctl list --json` first.

## Destructive operations

Removing a runner is destructive:

```bash
runnerctl remove example-runner-01 --yes
```

Only use `--yes` when removal of that exact runner is explicitly intended. Inspect `runnerctl status example-runner-01 --json` first when practical.

## Credentials and host security

- Never print, save, or commit GitHub registration/removal tokens.
- Do not expose GitHub CLI credentials.
- Do not bypass `sudo` or OS privilege prompts.
- Self-hosted runners execute workflow code on the host; attaching an untrusted repository can expose host resources.
- Treat any non-zero CLI exit code as failure.

## Structured output

Prefer JSON when available:

```text
runnerctl agent --json
runnerctl doctor --json
runnerctl list --json
runnerctl status RUNNER --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve OWNER/REPO --json
runnerctl upgrade --check --json
```

Do not scrape human-readable tables when a JSON interface exists.
