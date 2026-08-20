# runners-self-host-management

`runnerctl` is a small local CLI for managing multiple GitHub Actions self-hosted runner instances on one macOS/Linux machine.

The first release is optimized for repository-level runners, which is useful when you have admin permission on individual repositories but do not have organization-level runner permission.

## Features

- Install 1..N runner instances for one repository.
- Use GitHub CLI (`gh`) to request short-lived registration/remove tokens on demand.
- Never persist GitHub registration tokens.
- Install each runner using GitHub's official `svc.sh` service integration (`launchd` on macOS, `systemd` on Linux).
- Start, stop, restart, and inspect runners from one CLI.
- Tail runner (`Runner_*.log`) and job worker (`Worker_*.log`) diagnostics.
- Keep runner binaries, work directories, metadata, and download cache under one local data directory.

## Requirements

- macOS (Apple Silicon or Intel) or Linux (x64/arm64)
- `bash`
- `curl`
- `tar`
- GitHub CLI: `gh`
- Repository admin permission for every repository where you register a repository-level runner

Authenticate GitHub CLI first:

```bash
gh auth login
gh auth status
```

For a fine-grained PAT, GitHub's repository runner registration/remove-token endpoints require repository **Administration: write** permission. You may also provide authentication temporarily through `GH_TOKEN`; `runnerctl` does not save it.

## Install locally

```bash
git clone --branch feat/runnerctl-initial https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash install.sh
```

If `~/.local/bin` is not already in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then verify:

```bash
runnerctl doctor
```

## Add runners

Two concurrent runners for one repository:

```bash
runnerctl add Claire-s-English/billing-platform \
  --count 2 \
  --labels local,billing-platform
```

The default runner names look like:

```text
claire-s-english-billing-platform-my-mac-01
claire-s-english-billing-platform-my-mac-02
```

You can override the prefix:

```bash
runnerctl add Claire-s-English/billing-platform \
  --count 2 \
  --name-prefix billing-local \
  --labels local,billing
```

Then a workflow can target this pool:

```yaml
jobs:
  test:
    runs-on: [self-hosted, local, billing]
    steps:
      - uses: actions/checkout@v4
      - run: pnpm test
```

If both runners are idle, two matching jobs can run concurrently.

## Commands

```text
runnerctl doctor
runnerctl add OWNER/REPO [--count N] [--labels a,b] [--name-prefix PREFIX]
runnerctl list
runnerctl status [RUNNER]
runnerctl start RUNNER
runnerctl stop RUNNER
runnerctl restart RUNNER
runnerctl start-all
runnerctl stop-all
runnerctl logs RUNNER [--no-follow]
runnerctl job-logs RUNNER [--no-follow]
runnerctl remove RUNNER [--yes]
runnerctl version
```

Examples:

```bash
runnerctl list
runnerctl status billing-local-01
runnerctl logs billing-local-01
runnerctl job-logs billing-local-01
runnerctl restart billing-local-01
runnerctl remove billing-local-02
```

## Local layout

By default:

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

Change it with:

```bash
export RUNNERCTL_HOME="$HOME/github-runners"
```

## Authentication and tokens

`runnerctl` intentionally does **not** ask you to copy the temporary registration token from GitHub Settings.

Instead, when you run `runnerctl add`, it calls through your existing `gh` authentication to request a short-lived registration token and immediately passes it to `config.sh`. GitHub registration/remove tokens expire after one hour.

Authentication precedence is the normal GitHub CLI behavior. This means you can use either:

```bash
gh auth switch
runnerctl add OWNER/REPO --count 2
```

or a temporary token for a command:

```bash
GH_TOKEN="..." runnerctl add OWNER/REPO --count 2
```

Do not put long-lived PATs into this repository or runner metadata.

## Logs

Runner connection/service diagnostics:

```bash
runnerctl logs billing-local-01
```

Latest workflow worker diagnostics:

```bash
runnerctl job-logs billing-local-01
```

Both commands show the latest matching file in the runner's `_diag/` directory and follow it by default. Add `--no-follow` to print the last 200 lines and exit.

## Concurrency notes

Multiple runner instances on the same host can execute jobs concurrently, but they still share CPU, RAM, disk, Docker, and network resources.

For Docker Compose based CI, avoid fixed global resources. Prefer a unique Compose project name per workflow run, for example:

```bash
docker compose -p "ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" up -d
```

Also avoid binding the same fixed host ports from two concurrent jobs unless your test setup explicitly allocates unique ports.

## Security

A self-hosted runner executes repository workflow code directly on your machine. Only attach trusted repositories/workflows to a machine containing valuable credentials or local data. Be especially careful with workflows triggered by untrusted pull requests.

## Roadmap

- Organization-level runner pools and runner groups.
- Named GitHub authentication profiles for multi-account setups.
- `runnerctl add --repo-url ...` convenience parsing.
- Resource/concurrency limits per local host.
- Health summary including GitHub-side online/busy state.
- Brew formula/release packaging.
