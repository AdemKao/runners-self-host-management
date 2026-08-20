# runnerctl

[繁體中文](README.zh-TW.md)

![CI](https://github.com/AdemKao/runners-self-host-management/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

`runnerctl` is a small open-source CLI for managing multiple GitHub Actions self-hosted runner instances on a single macOS or Linux host.

It is designed for developers and small teams that want local or dedicated CI capacity without manually repeating GitHub's runner setup commands for every repository and runner instance.

## Features

- Register one or many self-hosted runners for a repository.
- Run multiple runner instances concurrently on the same host.
- Manage runners as background services with `launchd` on macOS and `systemd` on Linux.
- Manage multiple GitHub CLI accounts without storing long-lived credentials.
- Map repository owners or individual repositories to specific GitHub accounts.
- Start, stop, restart, inspect, and remove runners from one CLI.
- Tail runner and workflow worker diagnostic logs.
- Install from shell, npm/pnpm, or Homebrew HEAD without manually cloning the repository.
- Build tagged GitHub Releases with SHA-256 checksums.

## Requirements

Runtime requirements:

- macOS (Apple Silicon or Intel) or Linux (x64/arm64)
- Bash
- `curl`
- `tar`
- GitHub CLI (`gh`)
- repository admin permission for repositories where runners are registered

`npm` or `pnpm` is only required when installing through the Node package ecosystem.

## Installation

### macOS / Linux installer

Install the current `main` version:

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | bash
```

The default destination is `~/.local/bin/runnerctl`. Override it with `PREFIX`:

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh | PREFIX="$HOME/.local" bash
```

Tagged releases can be installed by setting `RUNNERCTL_VERSION`. The release installer verifies the published SHA-256 checksum before installation:

```bash
curl -fsSL https://raw.githubusercontent.com/AdemKao/runners-self-host-management/main/install.sh \
  | RUNNERCTL_VERSION=<version> bash
```

### npm / pnpm

Install directly from GitHub without cloning:

```bash
npm install -g github:AdemKao/runners-self-host-management
```

or:

```bash
pnpm add -g github:AdemKao/runners-self-host-management
```

The repository is also prepared for publishing as `@ademkao/runnerctl` on npm. Once a package release is published, the standard registry commands are:

```bash
npm install -g @ademkao/runnerctl
# or
pnpm add -g @ademkao/runnerctl
```

### Homebrew / Linuxbrew

The repository contains a HEAD formula. Add the repository as a custom tap and install the current source version:

```bash
brew tap ademkao/runnerctl https://github.com/AdemKao/runners-self-host-management
brew install --HEAD ademkao/runnerctl/runnerctl
```

This works with Homebrew on macOS and Linuxbrew on Linux.

### Development checkout

For contributors:

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

## Quick start

Check your environment:

```bash
runnerctl doctor
```

Authenticate GitHub CLI if needed:

```bash
runnerctl auth login
runnerctl auth list
```

Optionally map repositories to different GitHub accounts:

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map 'example-user/*' personal-account
```

Create two concurrent runners for a repository:

```bash
runnerctl add example-org/example-repo \
  --count 2 \
  --labels local,ci
```

Inspect them:

```bash
runnerctl list
```

A workflow can target the pool with matching labels:

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, ci]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/test.sh
```

If both matching runners are idle, two jobs can execute concurrently.

## Commands

```text
runnerctl doctor

runnerctl auth list
runnerctl auth status
runnerctl auth use ACCOUNT
runnerctl auth login [GH_AUTH_LOGIN_OPTIONS...]
runnerctl auth setup-git
runnerctl auth doctor
runnerctl auth map OWNER/REPO|OWNER/* ACCOUNT
runnerctl auth unmap OWNER/REPO|OWNER/*
runnerctl auth mappings
runnerctl auth resolve OWNER/REPO

runnerctl add OWNER/REPO [--count N] [--labels a,b] [--name-prefix PREFIX] [--account ACCOUNT]
runnerctl list
runnerctl status [RUNNER]
runnerctl start RUNNER
runnerctl stop RUNNER
runnerctl restart RUNNER
runnerctl start-all
runnerctl stop-all
runnerctl logs RUNNER [--no-follow]
runnerctl job-logs RUNNER [--no-follow]
runnerctl remove RUNNER [--yes] [--account ACCOUNT]
runnerctl version
```

## Multiple GitHub accounts

GitHub CLI can keep more than one account authenticated for the same host. `runnerctl` uses those existing credentials and does not persist the tokens itself.

List accounts:

```bash
runnerctl auth list
```

Change the active `gh` account explicitly:

```bash
runnerctl auth use work-account
```

For runner operations, it is usually better to map repositories instead of repeatedly changing the global active account:

```bash
runnerctl auth map 'example-org/*' work-account
runnerctl auth map example-user/example-repo personal-account
```

Resolution order is:

1. `--account ACCOUNT` passed to the command;
2. exact `OWNER/REPO` mapping;
3. `OWNER/*` mapping;
4. active GitHub CLI account.

Check which account will be used:

```bash
runnerctl auth resolve example-org/example-repo
```

Mappings contain account names only. Credentials remain managed by GitHub CLI.

### Git authentication versus GitHub CLI authentication

`gh` authentication and Git SSH authentication are separate concerns.

For HTTPS remotes, you can configure Git to use GitHub CLI credentials:

```bash
runnerctl auth setup-git
```

For SSH remotes, the SSH key is selected by your SSH configuration. `runnerctl auth use` does not change `~/.ssh/config` or SSH keys.

Use:

```bash
runnerctl auth doctor
```

to inspect the active GitHub account, Git protocol, current repository remote, and resolved runner account.

## Runner storage

By default runner data lives under:

```text
~/.local/share/runnerctl/
├── cache/
└── runners/
    ├── example-runner-01/
    │   ├── .runnerctl-meta
    │   ├── _diag/
    │   ├── _work/
    │   └── svc.sh
    └── example-runner-02/
```

Account mappings live separately under:

```text
~/.config/runnerctl/accounts.tsv
```

Change these locations with:

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
export RUNNERCTL_CONFIG_HOME="$HOME/.config/runnerctl"
```

## Logs

Runner connection and service diagnostics:

```bash
runnerctl logs example-runner-01
```

Latest workflow worker diagnostics:

```bash
runnerctl job-logs example-runner-01
```

Add `--no-follow` to print the latest 200 lines and exit.

## Concurrency and isolation

Multiple runner instances on one machine can execute jobs concurrently, but they still share CPU, RAM, disk, Docker, and network resources.

For Docker Compose based CI, use a unique project name per workflow run:

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

Avoid fixed host ports or globally named resources when multiple jobs may run at the same time.

## Security

A self-hosted runner executes workflow code directly on its host machine. Only attach trusted repositories and workflows to machines containing valuable credentials or local data.

`runnerctl` intentionally does not persist GitHub registration or removal tokens. It requests short-lived tokens through the selected GitHub CLI account when required.

See [SECURITY.md](SECURITY.md) for the security policy and reporting guidance.

## Releases and distribution

Tags matching `v*` trigger the release workflow. A release validates that the Git tag, CLI version, and npm package version match, then creates:

```text
runnerctl
runnerctl.sha256
runnerctl-<version>.tar.gz
runnerctl-<version>.tar.gz.sha256
```

If the repository has an `NPM_TOKEN` secret configured, the same tagged workflow also publishes the npm package. Without that secret, the GitHub Release still succeeds and npm publishing is skipped.

## Development

Run the smoke test suite:

```bash
bash tests/smoke.sh
```

Validate npm packaging:

```bash
npm pack --dry-run
```

Validate the Homebrew formula:

```bash
ruby -c Formula/runnerctl.rb
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Roadmap

- Organization-level runner pools and runner groups.
- GitHub-side online/busy health reporting.
- Host-level concurrency and resource limits.
- Stable Homebrew tap formula generated from releases.
- Debian (`.deb`) and RPM packages.

## License

MIT. See [LICENSE](LICENSE).
