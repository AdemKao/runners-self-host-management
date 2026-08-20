---
name: runnerctl
description: Safely manage GitHub Actions self-hosted runners with runnerctl on macOS and Linux.
---

# runnerctl AI AGENT skill

Use this skill when a user asks you to inspect, register, start, stop, troubleshoot, or remove GitHub Actions self-hosted runners managed by `runnerctl`.

## Discover the installed contract first

Run:

```bash
runnerctl agent --json
```

Then inspect state with machine-readable commands:

```bash
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
```

For a target repository, resolve the account before mutating anything:

```bash
runnerctl auth resolve example-org/example-repo --json
```

Before a mutation, inspect focused command help:

```bash
runnerctl add --help
runnerctl remove --help
```

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

A typical non-interactive registration is:

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci \
  --account work-account
```

Never invent the repository, account, count, or labels when they materially affect the user's setup.

## Logs

Agents must use finite log reads:

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

Do not use the default follow mode in unattended automation because it can block indefinitely.

## Mutations

Starting, stopping, restarting, registering runners, changing mappings, configuring Git credentials, or changing the active account are mutations. Ensure the action matches user intent.

For bulk service operations, inspect `runnerctl list --json` first because all managed runners are affected.

## Destructive operations

Removing a runner is destructive:

```bash
runnerctl remove example-runner-01 --yes
```

Only use `--yes` when the user explicitly intends to remove that exact runner. Inspect `runnerctl status example-runner-01 --json` first when practical.

## Credentials and host security

- Never print, save, or commit GitHub registration/removal tokens.
- Do not expose GitHub CLI credentials.
- Do not bypass `sudo` or OS privilege prompts.
- Self-hosted runners execute workflow code on the host; attaching an untrusted repository can expose host resources.
- Treat any non-zero CLI exit code as failure and report it instead of assuming success.

## Structured output

Prefer `--json` for automation when supported. Current discovery interfaces include:

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
```

Do not scrape the human-readable tables when a JSON interface exists.
