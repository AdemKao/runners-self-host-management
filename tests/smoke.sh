#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$ROOT/tests/.smoke-v080.$$"
cleanup(){ rm -f "$tmp" "$tmp.help" "$tmp.scheduler" "$tmp.queue" "$tmp.notify" "$tmp.bot" "$tmp.cleanup"; }
trap cleanup EXIT
sed \
  -e 's/VERSION="0\.4\.3"/VERSION="0.8.0"/' \
  -e 's/NEXT_VERSION="0\.4\.4"/NEXT_VERSION="0.8.1"/' \
  -e "s/'host-wide execution gate'/'Legacy host-side admission gate'/g" \
  -e 's/capacity queue upgrade/capacity queue bot notify scheduler upgrade/g' \
  "$ROOT/tests/smoke-legacy.sh" >"$tmp"
bash "$tmp"
[[ "$(bash "$ROOT/runnerctl" version)" == "0.8.0" ]]
bash "$ROOT/runnerctl" --help >"$tmp.help"
grep -q 'GitHub-native scheduling' "$tmp.help"
grep -q 'Notifications and integrations' "$tmp.help"
grep -q 'Read-only Bot/API controller' "$tmp.help"
bash "$ROOT/runnerctl" cleanup --help >"$tmp.cleanup"
grep -q 'Host disk hygiene' "$tmp.cleanup"
grep -q 'never prunes Docker volumes' "$tmp.cleanup"
bash "$ROOT/runnerctl" cleanup host policy --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled!==false||x.min_free_gb!==10||!x.valid)process.exit(1)'
bash "$ROOT/runnerctl" scheduler --help >"$tmp.scheduler"
grep -q 'runnerctl-scheduled' "$tmp.scheduler"
bash "$ROOT/runnerctl" queue --help >"$tmp.queue"
grep -q 'Legacy host-side admission gate' "$tmp.queue"
grep -q 'default 300 seconds' "$tmp.queue"
bash "$ROOT/runnerctl" notify --help >"$tmp.notify"
grep -q 'Notification integrations and provider plugins' "$tmp.notify"
grep -q 'notify doctor RUNNER' "$tmp.notify"
bash "$ROOT/runnerctl" notify providers --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.length<3)process.exit(1)'
if command -v python3 >/dev/null 2>&1; then
  bash "$ROOT/runnerctl" bot --help >"$tmp.bot"
  grep -q 'Read-only Telegram, LINE, and HTTP API controller' "$tmp.bot"
  bash "$ROOT/runnerctl" bot doctor --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["version"]=="0.7.0" and x["read_only"] is True'
fi
bash "$ROOT/runnerctl" agent --json | grep -q '"scheduler status"'
bash "$ROOT/runnerctl" agent --json | grep -q '"notify status"'
bash "$ROOT/runnerctl" agent --json | grep -q '"bot query"'
bash "$ROOT/runnerctl" completion bash | grep -q 'bot'
echo "v0.8.0 smoke wrapper passed"
