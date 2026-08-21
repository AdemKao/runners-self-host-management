# CI compatibility scanner

`runnerctl ci check` inspects GitHub Actions workflows before moving jobs from GitHub-hosted runners to self-hosted runners.

## Check a repository

```bash
runnerctl ci check OWNER/REPO
```

Compare the requirements with the current host:

```bash
runnerctl ci check OWNER/REPO --current-host
```

Machine-readable output:

```bash
runnerctl ci check OWNER/REPO --current-host --json
```

## What it detects

The scanner reports obvious host requirements from workflow files and referenced actions, including:

- Docker container actions (`runs.using: docker`)
- `docker://` steps
- workflow service containers
- job-level containers
- common Linux-only commands such as `apt-get`
- common macOS-only commands such as Homebrew

For third-party actions, runnerctl reads `action.yml` / `action.yaml` metadata instead of relying only on the action name.

## Migration example

A workflow containing:

```yaml
steps:
  - uses: anothrNick/github-tag-action@1.67.0
```

is detected as requiring Linux + Docker because that action is a Docker container action.

A macOS self-hosted runner can have Docker Desktop installed and still be incompatible with GitHub Docker container actions. The scanner therefore recommends a Linux self-hosted runner with Docker for that workflow.

Typical migration flow:

```bash
runnerctl doctor
runnerctl host inspect
runnerctl ci check OWNER/REPO --current-host
```

Only after the compatibility result is acceptable should the workflow's `runs-on` labels be changed to target the self-hosted runner.

## Scope and limitations

This command is intentionally read-only. It does not rewrite workflow files or guarantee that arbitrary shell scripts are portable. It surfaces known platform requirements and actionable compatibility warnings before migration.
