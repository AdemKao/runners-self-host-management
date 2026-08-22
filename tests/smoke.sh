#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$ROOT/tests/.smoke-v060.$$"
cleanup(){ rm -f "$tmp"; }
trap cleanup EXIT
sed \
  -e 's/VERSION="0\.4\.3"/VERSION="0.6.0"/' \
  -e 's/NEXT_VERSION="0\.4\.4"/NEXT_VERSION="0.6.1"/' \
  -e "s/'host-wide execution gate'/'Legacy host-side admission gate'/g" \
  -e 's/capacity queue upgrade/capacity queue notify scheduler upgrade/g' \
  "$ROOT/tests/smoke-legacy.sh" >"$tmp"
bash "$tmp"
[[ "$(bash "$ROOT/runnerctl" version)" == "0.6.0" ]]
bash "$ROOT/runnerctl" --help >"$tmp.help"
grep -q 'GitHub-native scheduling' "$tmp.help"
grep -q 'Notifications and integrations' "$tmp.help"
bash "$ROOT/runnerctl" scheduler --help >"$tmp.scheduler"
grep -q 'runnerctl-scheduled' "$tmp.scheduler"
bash "$ROOT/runnerctl" queue --help >"$tmp.queue"
grep -q 'Legacy host-side admission gate' "$tmp.queue"
bash "$ROOT/runnerctl" notify --help >"$tmp.notify"
grep -q 'Notification integrations and provider plugins' "$tmp.notify"
bash "$ROOT/runnerctl" notify providers --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.length<3)process.exit(1)'
bash "$ROOT/runnerctl" agent --json | grep -q '"scheduler status"'
bash "$ROOT/runnerctl" agent --json | grep -q '"notify status"'
bash "$ROOT/runnerctl" completion bash | grep -q 'notify'
echo "v0.6 smoke wrapper passed"