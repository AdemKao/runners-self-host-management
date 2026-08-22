# runnerctl

[繁體中文](README.zh-TW.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` is an open-source CLI for managing multiple GitHub Actions self-hosted runners on a single macOS or Linux host.

It automates runner registration, background services, logs, multi-account GitHub authentication, upgrades, scheduling, notifications, and agent-friendly discovery.

## Highlights

- Register one or many self-hosted runners for a repository.
- Run multiple runner instances concurrently on one host.
- Manage services with `launchd` on macOS and `systemd` on Linux.
- Support multiple GitHub CLI accounts and repository-to-account mappings.
- Start, stop, restart, inspect, and remove runners.
- Read runner and workflow worker logs.
- GitHub-native queued-job scheduling with host-wide concurrency limits.
- Outbound Telegram, LINE, webhook, and executable-plugin notifications.
- Optional read-only Telegram / LINE / HTTP API controller for remote status queries.
- Stripe-style `COMMAND --help` discovery.
- AI-agent contract via `runnerctl agent` and `runnerctl agent --json`.
- Stable JSON for read-only discovery commands.
- Bash, Zsh, and Fish completion.
- Self-upgrade support for Homebrew, npm/pnpm, and shell installs.
- GitHub Release artifacts with SHA-256 checksums.

## Requirements

- macOS (Apple Silicon or Intel) or Linux (x64/arm64)
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- repository admin permission where a runner is registered

Node.js is only required for npm/pnpm installation. Linux service operations may require `sudo`.

**Python 3.8+ is optional and is required only for `runnerctl bot ...` Telegram/LINE/HTTP controller commands.** Other runnerctl features do not require Python.

## Installation

### Homebrew / Linuxbrew

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

### macOS / Linux shell installer

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

Default layout:

```text
~/.local/bin/runnerctl
~/.local/libexec/runnerctl/runnerctl-core
```

Install a tagged release with checksum verification:

```bash
VERSION="X.Y.Z"
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | RUNNERCTL_VERSION="$VERSION" bash
```

### npm / pnpm

```bash
npm install -g github:AdemKao/runners-self-host-management
# or
pnpm add -g github:AdemKao/runners-self-host-management
```

When the npm registry package is published:

```bash
npm install -g @ademkao/runnerctl
# or
pnpm add -g @ademkao/runnerctl
```

## Upgrade

Check for an update without changing anything:

```bash
runnerctl upgrade --check
```

Machine-readable check for agents and scripts:

```bash
runnerctl upgrade --check --json
```

Upgrade using the detected installation method:

```bash
runnerctl upgrade
```

`self-update` is an alias:

```bash
runnerctl self-update
```

The CLI detects the installation method and uses the appropriate path:

- Homebrew HEAD: `brew update` + `brew upgrade --fetch-HEAD runnerctl`
- Homebrew stable: `brew update` + `brew upgrade runnerctl`
- npm/pnpm: installs the latest tagged GitHub release globally
- shell installer: downloads the latest release and verifies SHA-256 before replacing the frontend/core

### Recovering from v0.3.0 Homebrew installation

`v0.3.0` used the Homebrew `write_env_script` API incorrectly, which can leave `/opt/homebrew/Cellar/runnerctl/.../bin` as an invalid wrapper path and cause `ENOTDIR` during completion generation.

Because the installed `runnerctl` itself may be broken, repair it once after `v0.3.1` is available:

```bash
brew update
brew reinstall --HEAD runnerctl
runnerctl version
```

After that, future upgrades can use:

```bash
runnerctl upgrade
```

## Quick start

```bash
runnerctl doctor
runnerctl auth login
runnerctl auth list
```

For multiple GitHub accounts, use generic repository mappings:

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

Workflow example:

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

One runner process executes one job at a time. Two idle runner instances can run two matching jobs concurrently.

## Scheduling, notifications, and remote read-only queries

These are separate layers:

```text
runnerctl scheduler
  GitHub-native queued-job admission and host concurrency

runnerctl notify
  runnerctl -> Telegram / LINE / webhook / custom provider

runnerctl bot
  Telegram / LINE / authenticated HTTP client -> read-only runnerctl query
```

Scheduler details: [docs/scheduler.md](docs/scheduler.md)

Notification/provider setup: [docs/notifications.md](docs/notifications.md)

Read-only Bot/API setup and security: [docs/bot-controller.md](docs/bot-controller.md)

### Read-only Bot/API examples

Inspect local controller readiness without printing secrets:

```bash
runnerctl bot doctor --json
```

Run a fixed local query:

```bash
runnerctl bot query status --json
```

Telegram uses long polling and does not need a public listener:

```bash
export RUNNERCTL_TELEGRAM_BOT_TOKEN='...'
export RUNNERCTL_TELEGRAM_ALLOWED_CHAT_IDS='123456789'
runnerctl bot telegram run
```

Supported Telegram/LINE commands are read-only:

```text
/status
/runners
/queue
/scheduler
/health
/help
```

Start the authenticated local HTTP API / LINE webhook listener:

```bash
export RUNNERCTL_BOT_API_TOKEN='use-a-long-random-value'
runnerctl bot serve --bind 127.0.0.1 --port 8765
```

HTTP `/v1/*` queries require a bearer token. LINE additionally requires `RUNNERCTL_LINE_CHANNEL_SECRET` signature verification and an allowed LINE user ID. The controller binds to loopback by default, does not provide TLS termination, and intentionally exposes **no remote mutating commands** in v0.7.0.

## Discoverable help

```bash
runnerctl --help
runnerctl add --help
runnerctl auth --help
runnerctl notify --help
runnerctl bot --help
runnerctl upgrade --help
runnerctl remove --help
runnerctl help add
```

Mutation help includes `Side effects` and `AI AGENT` guidance.

## AI agents and automation

Human-readable contract:

```bash
runnerctl agent
```

Machine-readable contract:

```bash
runnerctl agent --json
```

Recommended agent preflight:

```bash
runnerctl doctor --json
runnerctl auth list --json
runnerctl auth mappings --json
runnerctl list --json
runnerctl bot doctor --json
runnerctl upgrade --check --json
runnerctl auth resolve example-org/example-repo --json
runnerctl add --help
```

Agents should use finite log reads:

```bash
runnerctl logs example-runner-01 --no-follow
runnerctl job-logs example-runner-01 --no-follow
```

Do not use `remove --yes` unless removal of that exact runner is explicitly intended.

Repository-level instructions are in [AGENTS.md](AGENTS.md). A portable skill is available at [skills/runnerctl/SKILL.md](skills/runnerctl/SKILL.md).

## JSON output

```bash
runnerctl doctor --json
runnerctl list --json
runnerctl status example-runner-01 --json
runnerctl auth list --json
runnerctl auth status --json
runnerctl auth doctor --json
runnerctl auth mappings --json
runnerctl auth resolve example-org/example-repo --json
runnerctl notify status --json
runnerctl bot doctor --json
runnerctl bot query status --json
runnerctl upgrade --check --json
```

Human-readable output remains the default.

## Multi-account GitHub authentication

`runnerctl` uses accounts already authenticated by GitHub CLI and does not store GitHub access tokens.

```bash
runnerctl auth list
runnerctl auth status
runnerctl auth map 'example-org/*' work-account
runnerctl auth resolve example-org/example-repo
```

Resolution order:

1. Explicit `--account ACCOUNT` when supported.
2. Exact `OWNER/REPO` mapping.
3. `OWNER/*` mapping.
4. Active GitHub CLI account.

Changing the global active account is available but less automation-friendly:

```bash
runnerctl auth use work-account
```

For HTTPS Git remotes:

```bash
runnerctl auth setup-git
```

SSH key selection remains controlled by `~/.ssh/config`.

## Runner lifecycle

```bash
runnerctl list
runnerctl status example-runner-01
runnerctl start example-runner-01
runnerctl stop example-runner-01
runnerctl restart example-runner-01
runnerctl start-all
runnerctl stop-all
runnerctl remove example-runner-01
```

Skip removal confirmation only when intentional:

```bash
runnerctl remove example-runner-01 --yes
```

## Logs

```bash
runnerctl logs example-runner-01
runnerctl job-logs example-runner-01
```

For automation, use `--no-follow`.

## Shell completion

```bash
runnerctl completion bash
runnerctl completion zsh
runnerctl completion fish
```

Homebrew installs generated Bash, Zsh, and Fish completions automatically.

## Data layout

```text
~/.local/share/runnerctl/
├── bot/
│   └── telegram.offset
├── cache/
├── notify/
├── plugins/
│   └── notify/
└── runners/
    └── example-runner-01/
        ├── .runnerctl-meta
        ├── _diag/
        ├── _work/
        └── svc.sh

~/.config/runnerctl/accounts.tsv
```

## Parallel jobs and isolation

Runners on one host share CPU, RAM, disk, Docker, and networking.

For Docker Compose jobs, use a unique project name:

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

Avoid fixed host ports and globally named resources when jobs can run concurrently.

## Security

Self-hosted runners execute workflow code directly on the host. Attach only trusted repositories and workflows to machines containing valuable credentials or data.

Registration/removal tokens are requested only when needed and are not persisted in runnerctl mappings or metadata.

Bot/API credentials are environment-based and remote query commands are read-only in v0.7.0. Keep the HTTP controller on loopback/private networking unless you intentionally put it behind trusted HTTPS and authentication.

See [SECURITY.md](SECURITY.md) and [docs/bot-controller.md](docs/bot-controller.md).

## Release and distribution

A new CLI/package version merged to `main` triggers the release workflow when no release for that version exists. It validates CLI/package version consistency, runs tests, and creates standalone artifacts plus SHA-256 manifests and a source-compatible tarball.

If `NPM_TOKEN` is configured, the npm package is published too. npm publication failure does not prevent the GitHub Release from being created.

Release history: [CHANGELOG.md](CHANGELOG.md)

## Development

```bash
bash tests/smoke.sh
bash tests/scheduler.sh
bash tests/notify.sh
python3 tests/test_bot_controller.py
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).

## Roadmap

- Organization-level runner pools and runner groups.
- GitHub-side online/busy health reporting.
- Persistent service helpers for scheduler/bot controllers.
- Audited permission model for future remote operator actions.
- Stable versioned Homebrew formula generated from releases.
- Debian (`.deb`) and RPM packages.
- Richer completion for runner/account names.

## License

MIT. See [LICENSE](LICENSE).
