# runnerctl

[繁體中文](README.zh-TW.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` is an open-source CLI for managing multiple GitHub Actions self-hosted runner instances on a single macOS or Linux host.

It automates runner download, registration, background service management, logs, and multi-account GitHub authentication. Starting with v0.3, the CLI also exposes a first-class contract for AI coding agents and automation tools.

## Highlights

- Register one or many self-hosted runners for a repository.
- Run multiple runner instances concurrently on the same host.
- Use `launchd` on macOS and `systemd` on Linux.
- Work with multiple GitHub CLI accounts without storing runner registration tokens.
- Map repository owners or individual repositories to GitHub accounts.
- Start, stop, restart, inspect, and remove runners from one CLI.
- Read runner and workflow worker diagnostic logs.
- Stripe-style command discovery with `COMMAND --help` and `help COMMAND`.
- AI-agent contract with `runnerctl agent` and `runnerctl agent --json`.
- Machine-readable JSON for read-only discovery commands.
- Bash, Zsh, and Fish completion generation.
- Install through shell, npm/pnpm, or Homebrew/Linuxbrew without manually cloning the repository.
- GitHub Releases include SHA-256 checksums.

## Requirements

- macOS (Apple Silicon or Intel) or Linux (x64/arm64)
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- repository admin permission for repositories where runners are registered

Node.js is only required when installing from npm/pnpm. Linux service operations may require `sudo` because the official GitHub runner service script uses systemd.

## Installation

### macOS / Linux shell installer

Install the current `main` version:

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

The default destination is:

```text
~/.local/bin/runnerctl
~/.local/libexec/runnerctl/runnerctl-core
```

Use a custom prefix when needed:

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | PREFIX="$HOME/.local" bash
```

Install a tagged release with checksum verification:

```bash
VERSION="X.Y.Z"
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | RUNNERCTL_VERSION="$VERSION" bash
```

### npm / pnpm

Install directly from GitHub:

```bash
npm install -g github:AdemKao/runners-self-host-management
```

or:

```bash
pnpm add -g github:AdemKao/runners-self-host-management
```

The repository is prepared for the npm package `@ademkao/runnerctl`. Once published to the npm registry:

```bash
npm install -g @ademkao/runnerctl
# or
pnpm add -g @ademkao/runnerctl
```

### Homebrew / Linuxbrew

Install the HEAD formula from this repository:

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

### Development checkout

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

## Quick start

Check the host first:

```bash
runnerctl doctor
```

Authenticate GitHub CLI if needed:

```bash
runnerctl auth login
runnerctl auth list
```

For multiple GitHub accounts, map repositories to accounts:

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map 'example-user/*' personal-account
```

Register two runners:

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci
```

Inspect them:

```bash
runnerctl list
```

A workflow can target the labels:

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

One configured runner process can execute one job at a time. Two idle runner instances allow two matching jobs to run concurrently.

## Discoverable help

The root help is grouped by purpose:

```bash
runnerctl --help
```

Every important command exposes focused help:

```bash
runnerctl add --help
runnerctl auth --help
runnerctl auth map --help
runnerctl remove --help
runnerctl help add
```

Mutation help includes a `Side effects` section and an `AI AGENT` note so both humans and agents can understand the risk before running a command.

## AI agents and automation

`runnerctl` is designed to be discoverable by coding agents such as Codex, Claude Code, OpenCode, Cursor, and other automation systems.

Human-readable agent guidance:

```bash
runnerctl agent
```

Machine-readable contract:

```bash
runnerctl agent --json
```

The contract classifies commands as read-only, mutating, or destructive, documents exit codes, and recommends a discovery sequence before mutations.

A typical agent-safe preflight is:

```bash
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
runnerctl auth resolve example-org/example-repo --json
runnerctl add --help
```

Agents should use finite log reads:

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

Do not use `remove --yes` unless removal of that exact runner is explicitly intended.

Repository-level agent instructions are available in [AGENTS.md](AGENTS.md). A portable skill is available at [skills/runnerctl/SKILL.md](skills/runnerctl/SKILL.md). `CLAUDE.md` points Claude Code to the same canonical instructions.

## JSON output

Read-only discovery commands provide stable JSON intended for agents and scripts:

```bash
runnerctl doctor --json
runnerctl list --json
runnerctl status example-runner-01 --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve example-org/example-repo --json
```

Example:

```json
{
  "runners": [
    {
      "name": "example-runner-01",
      "repository": "example-org/example-repo",
      "account": "work-account",
      "status": "running",
      "labels": ["local", "ci"]
    }
  ]
}
```

Human-readable output remains the default.

## Multi-account GitHub authentication

`runnerctl` uses accounts already authenticated by GitHub CLI and does not store GitHub access tokens itself.

```bash
runnerctl auth list
runnerctl auth status
```

Create mappings:

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map example-user/example-repo personal-account
```

Resolve the effective account:

```bash
runnerctl auth resolve example-org/example-repo
```

Account resolution order is:

1. Explicit `--account ACCOUNT` when the command supports it.
2. Exact `OWNER/REPO` mapping.
3. `OWNER/*` mapping.
4. Active GitHub CLI account.

Changing the active account is still available:

```bash
runnerctl auth use work-account
```

This changes global `gh` state, so mappings or an explicit `--account` are preferred for automation.

### Git authentication is separate

For HTTPS Git remotes:

```bash
runnerctl auth setup-git
```

For SSH remotes, key selection is controlled by `~/.ssh/config`. `runnerctl auth use` does not switch SSH keys.

Inspect the current context with:

```bash
runnerctl auth doctor
```

## Runner lifecycle

```bash
runnerctl list
runnerctl status example-runner-01
runnerctl start example-runner-01
runnerctl stop example-runner-01
runnerctl restart example-runner-01
runnerctl start-all
runnerctl stop-all
```

Remove a runner interactively:

```bash
runnerctl remove example-runner-01
```

Skip confirmation only when the removal is intentional:

```bash
runnerctl remove example-runner-01 --yes
```

## Logs

Follow the runner connection/service log:

```bash
runnerctl logs example-runner-01
```

Follow the latest workflow worker log:

```bash
runnerctl job-logs example-runner-01
```

For automation, always prefer `--no-follow`.

## Shell completion

Generate completion scripts:

```bash
runnerctl completion bash
runnerctl completion zsh
runnerctl completion fish
```

For example, with Zsh:

```bash
runnerctl completion zsh > ~/.zfunc/_runnerctl
```

Add the generated script using the normal completion setup for your shell.

## Data layout

Default runner data:

```text
~/.local/share/runnerctl/
├── cache/
└── runners/
    └── example-runner-01/
        ├── .runnerctl-meta
        ├── _diag/
        ├── _work/
        └── svc.sh
```

Account mappings:

```text
~/.config/runnerctl/accounts.tsv
```

Override locations with:

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
export RUNNERCTL_CONFIG_HOME="$HOME/.config/runnerctl"
```

## Parallel jobs and isolation

Runner instances on the same host share CPU, RAM, disk, Docker, and network resources.

For Docker Compose jobs, use a unique project name:

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

Avoid fixed host ports and globally named resources when jobs may execute concurrently.

## Security

Self-hosted runners execute workflow code directly on the host. Only attach trusted repositories and workflows to machines containing valuable credentials or data.

`runnerctl` requests short-lived GitHub runner registration/removal tokens only when needed. Those tokens are not written into runnerctl mappings or metadata.

See [SECURITY.md](SECURITY.md) for the security policy.

## Release and distribution

A new public CLI/package version merged to `main` can trigger the release workflow. The workflow validates the public CLI version against `package.json`, runs tests, and creates artifacts such as:

```text
runnerctl
runnerctl.sha256
runnerctl-core
runnerctl-core.sha256
runnerctl-X.Y.Z.tar.gz
runnerctl-X.Y.Z.tar.gz.sha256
```

If `NPM_TOKEN` is configured, the same release also publishes the npm package. Otherwise the GitHub Release still completes and npm publishing is skipped.

## Development

Before submitting changes:

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).

## Roadmap

- Organization-level runner pools and runner groups.
- GitHub-side online/busy health reporting.
- Host-level concurrency and resource limits.
- Stable versioned Homebrew formula generation from releases.
- Debian (`.deb`) and RPM packages.
- Richer completion for runner/account names.

## License

MIT. See [LICENSE](LICENSE).
