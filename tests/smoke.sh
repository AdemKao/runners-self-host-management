#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/install.sh"

[[ "$($ROOT/bin/runnerctl version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
"$ROOT/bin/runnerctl" --help | grep -q 'runnerctl add OWNER/REPO'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
RUNNERCTL_HOME="$tmp" "$ROOT/bin/runnerctl" list | grep -q 'REPOSITORY'

echo "smoke tests passed"
