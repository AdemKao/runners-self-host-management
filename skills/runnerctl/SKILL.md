---
name: runnerctl
description: Safely manage GitHub Actions self-hosted runners with runnerctl on macOS and Linux.
---

# runnerctl AI AGENT skill

Use this skill when a user asks you to inspect, register, start, stop, troubleshoot, or remove GitHub Actions self-hosted runners managed by `runnerctl`.

## Always discover first

Run the installed CLI contract first when available:

```bash
runnerctl agent --json
```

Then inspect state with read-only commands:

```bash
runnerctl doctor
runnerctl auth list
runnerctl auth mappings
runnerctl list
```

For a target repository, resolve the account before mutating anything:

```bash
runnerctl auth resolve example-org/example-repo
```

## Multi-account behavior

Do not assume the active GitHub CLI account is correct.

Prefer one of these approaches:

```bash
runnerctl add example-org/example-repo --account work-account
```

or an existing mapping:

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

Never invent the repository, account, count, or labels when they materially affect the user's setup. Discover existing state or use values supplied by the user.

## Logs

Agents should use finite log reads:

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

Do not use the default follow mode in unattended automation because it can block indefinitely.

## Mutations

Starting, stopping, restarting, registering runners, changing mappings, configuring Git credentials, or changing the active account are mutations. Ensure the requested action matches user intent.

## Destructive operations

Removing a runner is destructive:

```bash
runnerctl remove example-runner-01 --yes
```

Only use `--yes` when the user explicitly intends to remove that runner. Before removal, inspect `runnerctl list` or `runnerctl status RUNNER` to ensure the target is correct.

## Credentials and security

- Never print, save, or commit GitHub registration/removal tokens.
- Do not expose GitHub CLI credentials.
- Do not bypass `sudo` or OS privilege prompts.
- Remember that self-hosted runners execute workflow code on the host; attaching untrusted repositories can expose host resources.
- Treat a non-zero CLI exit code as failure and report it instead of assuming success.
