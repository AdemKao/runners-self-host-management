# AI AGENT

This repository is intentionally designed to be worked on by AI coding agents as well as humans.

## First commands

Before changing code, inspect the CLI contract:

```bash
bash runnerctl agent
bash runnerctl agent --json
```

Then run the existing tests:

```bash
bash tests/smoke.sh
```

## Repository rules

- Keep examples generic. Use names such as `example-org/example-repo`, `work-account`, `personal-account`, and `example-runner-01`.
- Do not add real company names, customer names, private repository names, usernames, tokens, machine names, or credentials to documentation, fixtures, or tests.
- Never persist GitHub runner registration/removal tokens. They must remain short-lived and obtained only when needed.
- Preserve support for macOS and Linux.
- Preserve multi-account GitHub CLI behavior; do not assume the globally active `gh` account is always the correct account.
- Prefer non-interactive, deterministic CLI behavior that is safe for automation.
- Add structured output when an agent needs to parse a command reliably.
- Treat commands that remove runners or change global authentication state as higher-risk mutations.
- Do not silently bypass `sudo`, operating-system permissions, or GitHub permission failures.
- Maintain meaningful non-zero exit codes for failed operations.

## Change workflow

For code changes:

1. Read the relevant implementation and tests.
2. Make the smallest coherent change.
3. Update English and Traditional Chinese documentation when user-facing behavior changes.
4. Run:

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

5. Do not publish a release by manually changing tags unless release behavior is part of the requested work.

## CLI safety classification

Read-only / discovery commands may normally be used to understand state:

```text
runnerctl doctor
runnerctl auth list
runnerctl auth status
runnerctl auth doctor
runnerctl auth mappings
runnerctl auth resolve OWNER/REPO
runnerctl list
runnerctl status [RUNNER]
runnerctl logs RUNNER --no-follow
runnerctl job-logs RUNNER --no-follow
runnerctl version
runnerctl agent --json
```

Mutating commands change local configuration, GitHub registration, or service state. Confirm they match the user's request before running them.

The destructive command is:

```text
runnerctl remove RUNNER --yes
```

Only use it when removal is explicitly intended.

## Agent skill

A portable agent skill is provided at:

```text
skills/runnerctl/SKILL.md
```

Agents operating an installed CLI should prefer the live contract from:

```bash
runnerctl agent --json
```

because it describes the behavior of the installed version.
