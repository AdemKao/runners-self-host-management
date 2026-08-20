# Contributing to runnerctl

Thanks for helping improve `runnerctl`.

## Development setup

Requirements:

- macOS or Linux
- Bash
- Git
- GitHub CLI (`gh`)
- Node.js only when validating npm packaging

Clone the repository and run the smoke suite:

```bash
git clone https://github.com/AdemKao/runners-self-host-management.git
cd runners-self-host-management
bash tests/smoke.sh
```

## Pull requests

Keep pull requests focused and include:

- the problem being solved;
- the behavior before and after the change;
- tests for behavior changes when practical;
- documentation updates for user-facing changes.

Please avoid committing credentials, GitHub runner registration tokens, private repository names, internal hostnames, or other environment-specific secrets.

## Shell style

- Use `set -euo pipefail` for executable Bash scripts.
- Quote variable expansions unless intentional word splitting is required.
- Prefer portable commands available on both macOS and Linux.
- Keep authentication tokens in process memory only; do not persist them in runner metadata.

## Testing

Run:

```bash
bash tests/smoke.sh
npm pack --dry-run
ruby -c Formula/runnerctl.rb
```

CI runs on both Ubuntu and macOS.

## Releases

Release tags use semantic versioning, for example `v0.3.0`. The tag version must match both `bin/runnerctl` and `package.json`.
