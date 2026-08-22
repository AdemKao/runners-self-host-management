#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$ROOT/tests/.smoke-v050.$$"
cleanup(){ rm -f "$tmp"; }
trap cleanup EXIT
sed \
  -e 's/VERSION="0\.4\.3"/VERSION="0.5.0"/' \
  -e 's/NEXT_VERSION="0\.4\.4"/NEXT_VERSION="0.5.1"/' \
  -e "s/'host-wide execution gate'/'Legacy host-side admission gate'/g" \
  -e 's/capacity queue upgrade/capacity queue scheduler upgrade/g' \
  "$ROOT/tests/smoke-legacy.sh" >"$tmp"
bash "$tmp"
bash "$ROOT/runnerctl" --help | grep -q 'GitHub-native scheduling'
bash "$ROOT/runnerctl" scheduler --help | grep -q 'runnerctl-scheduled'
bash "$ROOT/runnerctl" queue --help | grep -q 'Legacy host-side admission gate'
bash "$ROOT/runnerctl" agent --json | grep -q '"scheduler status"'
echo "v0.5 smoke wrapper passed"
