# Host bootstrap

`runnerctl host` prepares the basic command-line prerequisites used by GitHub Actions self-hosted runners without silently changing unrelated host configuration.

## Inspect first

```bash
runnerctl host inspect
runnerctl host inspect --json
```

The inspection reports the operating-system family, package manager, required commands (`git`, `gh`, `curl`, `tar`), missing dependencies, and whether bootstrap is available.

## Preview changes

Always preview package changes before applying them:

```bash
runnerctl host bootstrap --dry-run
runnerctl host bootstrap --dry-run --json
```

The dry-run is read-only.

## Apply prerequisite packages

```bash
runnerctl host bootstrap
```

The command may use `sudo` on Linux. It only manages the CLI prerequisites required by runnerctl. It does **not** configure swap, firewall rules, Docker, GitHub credentials, or register a runner.

## Oracle VM / AlmaLinux 8 example

For an Oracle VM running AlmaLinux 8.10:

```bash
cat /etc/os-release
runnerctl host inspect
runnerctl host bootstrap --dry-run
runnerctl host bootstrap
runnerctl doctor
```

A machine missing `git` and `gh` should produce a plan similar to:

```text
sudo dnf install -y git
sudo dnf install -y 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install -y gh
```

The GitHub CLI repository setup follows the official DNF4 installation path used by RHEL-compatible systems. DNF5 is detected separately and uses its corresponding `config-manager addrepo --from-repofile=...` form.

After bootstrap, authenticate explicitly:

```bash
runnerctl auth login
runnerctl auth status
```

Then register the repository runner:

```bash
runnerctl add OWNER/REPO --labels local,linux
```

## Low-memory hosts

Host bootstrap does not add swap automatically. If `runnerctl doctor` reports very low memory or no swap, resolve that host-capacity problem separately before running Node/Docker-heavy CI workloads.

This separation is intentional: package bootstrap is safe to automate, while memory, firewall, Docker, and security policy changes require an explicit host-administration decision.
