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
bash runnerctl upgrade --help
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
- Treat `runnerctl upgrade --check` as read-only and `runnerctl upgrade` / `runnerctl self-update` as installation mutations.
- Do not silently bypass `sudo`, operating-system permissions, GitHub permission failures, or interactive privilege prompts.
- Maintain meaningful non-zero exit codes for failed operations.
- When public CLI behavior changes, update both `README.md` and `README.zh-TW.md`.

## Public frontend and internal core

```text
runnerctl             public frontend: help, agent contract, JSON, completion, upgrade
bin/runnerctl         internal runner/service implementation core
```

Distribution code must install both files. Do not change a packaging path in a way that installs only the core or only the frontend.

For Homebrew wrappers, use the documented Pathname form:

```ruby
(bin/"runnerctl").write_env_script(...)
```

Do not call `bin.write_env_script(...)`; that treats the `bin` directory itself as the script path.

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

5. Check that `package.json`, Homebrew tests, and public `runnerctl version` remain consistent.
6. Do not manually create or move release tags unless release behavior is explicitly part of the requested work.

## Safe discovery commands

Prefer structured output:

```text
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve OWNER/REPO --json
runnerctl list --json
runnerctl status RUNNER --json
runnerctl upgrade --check --json
runnerctl agent --json
```

Logs are read-only but follow indefinitely by default. Agents must use:

```text
runnerctl logs RUNNER --no-follow
runnerctl job-logs RUNNER --no-follow
```

## Upgrade behavior

Before upgrading, prefer:

```bash
runnerctl upgrade --check --json
```

If an update is available and the user wants it installed:

```bash
runnerctl upgrade
```

`runnerctl self-update` is an alias. The CLI detects Homebrew, npm, pnpm, or shell installation and uses the matching update path.

A broken pre-v0.3.1 Homebrew installation cannot self-update because the old wrapper may not execute; repair it once with Homebrew, then use `runnerctl upgrade` for later versions.

## Mutation classes

Mutating commands change local configuration, GitHub registration, host service state, or the runnerctl installation. Confirm they match the user's request before running them.

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
