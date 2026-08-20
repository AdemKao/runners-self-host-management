# Security Policy

`runnerctl` manages software that executes GitHub Actions workflow code directly on a host machine. Treat runner hosts as privileged infrastructure.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose credentials, execute unintended code, or compromise runner hosts.

Use GitHub's private vulnerability reporting feature for this repository when available. Include:

- affected version or commit;
- operating system;
- reproduction steps;
- expected and observed behavior;
- potential impact.

## Security principles

`runnerctl` is designed to:

- avoid persisting GitHub registration and removal tokens;
- use existing GitHub CLI authentication instead of storing long-lived tokens;
- keep account mappings separate from credentials;
- use GitHub's official runner service integration;
- verify checksums for tagged release artifacts installed through the release installer.

## Self-hosted runner warning

Only attach trusted repositories and workflows to machines that contain valuable credentials or local data. Workflows from untrusted pull requests can execute commands on a self-hosted runner.
