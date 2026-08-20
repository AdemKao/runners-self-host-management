#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/install.sh"

[[ "$(bash "$ROOT/bin/runnerctl" version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
bash "$ROOT/bin/runnerctl" --help | grep -q 'runnerctl add OWNER/REPO'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
RUNNERCTL_HOME="$tmp" bash "$ROOT/bin/runnerctl" list | grep -q 'REPOSITORY'

echo "smoke tests passed"
