# AI AGENT

This repository is intentionally designed to be worked on by AI coding agents as well as humans.

## Start with the CLI contract

Before changing code or runner state, inspect the public CLI contract:

```bash
bash runnerctl agent
bash runnerctl agent --json
bash runnerctl --help
```

For any command that may mutate state, read its focused help first:

```bash
bash runnerctl add --help
bash runnerctl auth --help
bash runnerctl remove --help
```

Then run the existing tests before and after user-facing changes:

```bash
bash tests/smoke.sh
```

## Repository rules

- Keep examples generic. Use names such as `example-org/example-repo`, `work-account`, `personal-account`, and `example-runner-01`.
- Do not add real company names, customer names, private repository names, usernames, tokens, machine names, or credentials to documentation, fixtures, or tests.
- Never persist GitHub runner registration/removal tokens. They must remain short-lived and obtained only when needed.
- Preserve support for macOS and Linux.
- Preserve shell, npm/pnpm, and Homebrew/Linuxbrew distribution paths.
- Preserve multi-account GitHub CLI behavior; do not assume the globally active `gh` account is always correct.
- Prefer non-interactive, deterministic CLI behavior that is safe for automation.
- Prefer stable `--json` output when an agent or script needs to parse a command reliably.
- Keep human-readable output as the default unless the command is explicitly machine-oriented.
- Treat commands that remove runners or change global authentication state as higher-risk mutations.
- Do not silently bypass `sudo`, operating-system permissions, GitHub permission failures, or interactive privilege prompts.
- Maintain meaningful non-zero exit codes for failed operations.
- When public CLI behavior changes, update both `README.md` and `README.zh-TW.md`.

## Public frontend and internal core

The installed public command is:

```text
runnerctl
```

The source tree contains:

```text
runnerctl             public frontend: help, agent contract, JSON, completion
bin/runnerctl         internal runner/service implementation core
```

Distribution code must install both files. Do not change a packaging path in a way that installs only the core or only the frontend.

## Change workflow

1. Read the relevant implementation, tests, and command help.
2. Make the smallest coherent change.
3. Update English and Traditional Chinese docs for user-facing behavior.
4. Run:

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

5. Check that `package.json` and the public `runnerctl version` remain consistent for releases.
6. Do not manually create or move release tags unless release behavior is explicitly part of the requested work.

## Safe discovery commands

Prefer structured output for agent automation:

```text
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve OWNER/REPO --json
runnerctl list --json
runnerctl status RUNNER --json
runnerctl agent --json
```

Logs are read-only but follow indefinitely by default. Agents must use:

```text
runnerctl logs RUNNER --no-follow
runnerctl job-logs RUNNER --no-follow
```

## Mutation classes

Mutating commands change local configuration, GitHub registration, or host service state. Confirm they match the user's request before running them.

Changing the global GitHub CLI account is a global mutation:

```text
runnerctl auth use ACCOUNT
```

Prefer repository mappings or explicit `--account` when global switching is unnecessary.

The destructive command is:

```text
runnerctl remove RUNNER --yes
```

Only use `--yes` when removal of that exact runner is explicitly intended.

## Agent skill

A portable agent skill is provided at:

```text
skills/runnerctl/SKILL.md
```

Agents operating an installed CLI should prefer the live contract:

```bash
runnerctl agent --json
```

because it describes the behavior of the installed version.
