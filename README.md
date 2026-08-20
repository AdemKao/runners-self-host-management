# runners-self-host-management

`runnerctl` is a local CLI for managing multiple GitHub Actions self-hosted runner instances on one macOS/Linux machine.

It is optimized for repository-level runners and multi-account GitHub setups, including environments where different repositories belong to different GitHub accounts or organizations.

## Features

- Install 1..N runner instances for one repository.
- Manage multiple GitHub CLI accounts from `runnerctl`.
- Map `OWNER/REPO` or `OWNER/*` to a specific GitHub account.
- Use a mapped/specified account without globally switching `gh` active account.
- Request short-lived runner registration/remove tokens on demand.
- Never persist GitHub registration tokens or long-lived PATs.
- Install runners through GitHub's official `svc.sh` integration (`launchd` on macOS, `systemd` on Linux).
- Start, stop, restart, inspect, and remove runners from one CLI.
- Tail runner (`Runner_*.log`) and job worker (`Worker_*.log`) diagnostics.

## Requirements

- macOS (Apple Silicon or Intel) or Linux (x64/arm64)
- `bash`
- `curl`
- `tar`
- GitHub CLI: `gh`
- Repository admin permission for each repository where you register a repository-level runner

## Install locally

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

If `~/.local/bin` is not already in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify:

```bash
runnerctl doctor
runnerctl version
```

## Multi-account GitHub auth

Login to each GitHub account once:

```bash
runnerctl auth login
```

Run it again for additional accounts. GitHub CLI stores the credentials in its normal credential store; `runnerctl` does not copy or persist those tokens.

List authenticated accounts:

```bash
runnerctl auth list
```

Show full GitHub CLI auth status:

```bash
runnerctl auth status
```

Explicitly switch the globally active GitHub CLI account:

```bash
runnerctl auth use AdemKao
```

Configure Git over HTTPS to use GitHub CLI as the Git credential helper:

```bash
runnerctl auth setup-git
```

Inspect current auth/Git context:

```bash
runnerctl auth doctor
```

### Repository-to-account mappings

Map an entire owner/organization:

```bash
runnerctl auth map 'Claire-s-English/*' claire-work
runnerctl auth map 'AdemKao/*' AdemKao
```

Or override one repository:

```bash
runnerctl auth map Claire-s-English/billing-platform billing-admin
```

Exact repository mappings take precedence over `OWNER/*` mappings.

List mappings:

```bash
runnerctl auth mappings
```

Resolve which account a repository will use:

```bash
runnerctl auth resolve Claire-s-English/billing-platform
```

Remove a mapping:

```bash
runnerctl auth unmap 'Claire-s-English/*'
```

Mappings are stored locally at:

```text
~/.config/runnerctl/accounts.tsv
```

Only account names are stored there. Tokens are never stored by `runnerctl`.

## Add runners

If a mapping exists, no account option is required:

```bash
runnerctl add Claire-s-English/billing-platform \
  --count 2 \
  --labels local,billing-platform
```

`runnerctl` resolves the account in this order:

1. `--account ACCOUNT`
2. exact `OWNER/REPO` mapping
3. `OWNER/*` mapping
4. current active `gh` account

You can always override it:

```bash
runnerctl add Claire-s-English/billing-platform \
  --account claire-work \
  --count 2 \
  --name-prefix billing-local \
  --labels local,billing
```

The selected account is used only for the GitHub API calls required by that command. `runnerctl add --account ...` does **not** change the globally active `gh` account.

The runner metadata records which account created it so `runnerctl remove` can normally use the same account later.

## Workflow example

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, billing]
    steps:
      - uses: actions/checkout@v4
      - run: pnpm test
```

If two matching runners are idle, two jobs can execute concurrently.

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

## Local layout

Runner data:

```text
~/.local/share/runnerctl/
├── cache/
│   └── actions-runner-osx-arm64-<version>.tar.gz
└── runners/
    ├── billing-local-01/
    │   ├── .runnerctl-meta
    │   ├── _diag/
    │   ├── _work/
    │   ├── config.sh
    │   ├── run.sh
    │   └── svc.sh
    └── billing-local-02/
```

Account mappings:

```text
~/.config/runnerctl/
└── accounts.tsv
```

Override the locations:

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
export RUNNERCTL_CONFIG_HOME="$HOME/.config/runnerctl"
```

## Authentication model

For a mapped or explicit account, `runnerctl` asks GitHub CLI for that account's stored credential and passes it to `gh api` only through the command environment.

```text
gh credential store
       |
       +-- AdemKao
       +-- claire-work
              |
              v
runnerctl resolves repository -> account
              |
              v
gh auth token --user <account>
              |
              v
GH_TOKEN=<ephemeral-in-process> gh api ...
              |
              v
short-lived runner registration token
              |
              v
config.sh
```

The temporary runner registration/remove token is never written to runnerctl configuration.

## Git authentication vs GitHub CLI authentication

`runnerctl auth use ACCOUNT` changes the active **GitHub CLI** account.

For HTTPS Git remotes, you can use:

```bash
runnerctl auth setup-git
```

which delegates to `gh auth setup-git`.

For SSH remotes, account/key selection is controlled by SSH configuration, usually `~/.ssh/config`. Switching the active `gh` account does not switch SSH keys. `runnerctl auth doctor` warns when it detects an SSH remote.

## Logs

Runner connection/service diagnostics:

```bash
runnerctl logs billing-local-01
```

Latest workflow worker diagnostics:

```bash
runnerctl job-logs billing-local-01
```

Add `--no-follow` to print the last 200 lines and exit.

## Concurrency notes

Multiple runner instances on the same host can execute jobs concurrently, but they share CPU, RAM, disk, Docker, and network resources.

For Docker Compose based CI, use a unique project name per workflow run:

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

Avoid binding identical fixed host ports from concurrent jobs unless the test setup allocates unique ports.

## Security

A self-hosted runner executes workflow code directly on the host. Only attach trusted repositories/workflows to machines containing valuable credentials or local data, and be especially careful with untrusted pull requests.

Do not commit GitHub PATs, runner registration tokens, or GitHub CLI credential files to this repository.

## Roadmap

- Organization-level runner pools and runner groups.
- Better SSH alias/account diagnostics for multi-key setups.
- `runnerctl add --repo-url ...` convenience parsing.
- Resource/concurrency limits per local host.
- GitHub-side online/busy health summary.
- Runner package checksum verification.
- Brew formula/release packaging.
