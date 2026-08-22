#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/data/runners/test-runner" "$tmp/data/plugins/notify"

cat >"$tmp/data/runners/test-runner/.runnerctl-meta" <<'EOF'
name=test-runner
repo=example-org/example-repo
labels=linux,x64
version=2.999.0
account=work
EOF

cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config="$(cat)"
printf '%s\n' "$config" >>"${RUNNERCTL_FAKE_CURL_CONFIG_LOG:?}"
printf '%s\n' "$*" >>"${RUNNERCTL_FAKE_CURL_ARGS_LOG:?}"
[[ "${RUNNERCTL_FAKE_CURL_FAIL:-0}" == 1 ]] && exit 22
exit 0
EOF
chmod +x "$tmp/bin/curl"

cat >"$tmp/bin/hooks" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${RUNNERCTL_FAKE_HOOKS_LOG:?}"
exit 0
EOF
chmod +x "$tmp/bin/hooks"

export RUNNERCTL_HOME="$tmp/data"
export RUNNERCTL_CURL_BIN="$tmp/bin/curl"
export RUNNERCTL_FAKE_CURL_CONFIG_LOG="$tmp/curl-config.log"
export RUNNERCTL_FAKE_CURL_ARGS_LOG="$tmp/curl-args.log"
export RUNNERCTL_FAKE_HOOKS_LOG="$tmp/hooks.log"

# Provider status reports configuration booleans but never credential values.
export RUNNERCTL_TELEGRAM_BOT_TOKEN='tg-super-secret'
export RUNNERCTL_TELEGRAM_CHAT_ID='123456'
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='line-super-secret'
export RUNNERCTL_LINE_TO='U123456789'
export RUNNERCTL_WEBHOOK_URL='https://example.invalid/runnerctl'
export RUNNERCTL_WEBHOOK_AUTH_HEADER='Authorization: Bearer webhook-super-secret'
providers_json="$(bash "$ROOT/bin/runnerctl-notify" providers --json)"
printf '%s' "$providers_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.length<3||!x.find(p=>p.name==="telegram"&&p.configured)||!x.find(p=>p.name==="line"&&p.configured)||!x.find(p=>p.name==="webhook"&&p.configured))process.exit(1)'
! printf '%s' "$providers_json" | grep -q 'super-secret'

# Telegram uses sendMessage; token travels through curl config stdin, not status/log output.
: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=telegram bash "$ROOT/bin/runnerctl-notify" test --provider telegram >"$tmp/tg.out" 2>"$tmp/tg.err"
grep -q 'api.telegram.org/bottg-super-secret/sendMessage' "$tmp/curl-config.log"
grep -q 'chat_id=123456' "$tmp/curl-args.log"
grep -q 'runnerctl notification test' "$tmp/curl-args.log"
! cat "$tmp/tg.out" "$tmp/tg.err" | grep -q 'tg-super-secret'

# LINE uses the official push endpoint and Bearer token through curl config stdin.
: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=line bash "$ROOT/bin/runnerctl-notify" test --provider line >"$tmp/line.out" 2>"$tmp/line.err"
grep -q 'https://api.line.me/v2/bot/message/push' "$tmp/curl-config.log"
grep -q 'Authorization: Bearer line-super-secret' "$tmp/curl-config.log"
grep -q 'U123456789' "$tmp/curl-args.log"
! cat "$tmp/line.out" "$tmp/line.err" | grep -q 'line-super-secret'

# Generic webhook receives the stable runnerctl event JSON and optional auth header.
: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=webhook bash "$ROOT/bin/runnerctl-notify" emit scheduler.drained --message 'maintenance window' >"$tmp/webhook.out" 2>"$tmp/webhook.err"
grep -q 'https://example.invalid/runnerctl' "$tmp/curl-config.log"
grep -q 'Authorization: Bearer webhook-super-secret' "$tmp/curl-config.log"
grep -q 'scheduler.drained' "$tmp/curl-args.log"
grep -q 'maintenance window' "$tmp/curl-args.log"
! cat "$tmp/webhook.out" "$tmp/webhook.err" | grep -q 'webhook-super-secret'

# Executable plugin contract: stdin is JSON and event/message are environment variables.
cat >"$tmp/data/plugins/notify/custom" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >"${RUNNERCTL_PLUGIN_EVENT_FILE:?}"
printf '%s|%s\n' "${RUNNERCTL_NOTIFY_EVENT:-}" "${RUNNERCTL_NOTIFY_MESSAGE:-}" >"${RUNNERCTL_PLUGIN_ENV_FILE:?}"
EOF
chmod +x "$tmp/data/plugins/notify/custom"
RUNNERCTL_NOTIFY_PROVIDERS=custom RUNNERCTL_PLUGIN_EVENT_FILE="$tmp/plugin.json" RUNNERCTL_PLUGIN_ENV_FILE="$tmp/plugin.env" \
  bash "$ROOT/bin/runnerctl-notify" emit custom.event --message 'plugin payload'
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(x.schema_version!==1||x.event!=="custom.event"||x.message!=="plugin payload")process.exit(1)' "$tmp/plugin.json"
grep -q '^custom.event|plugin payload$' "$tmp/plugin.env"

# Enable composes notification hooks without starting a real runner service.
RUNNERCTL_HOOKS_HELPER="$tmp/bin/hooks" RUNNERCTL_SKIP_SERVICE_RESTART=1 \
  bash "$ROOT/bin/runnerctl-notify" enable test-runner --events job.started,job.completed >/dev/null
grep -q '^register test-runner started notify ' "$tmp/hooks.log"
grep -q '^register test-runner completed notify ' "$tmp/hooks.log"
[[ -x "$tmp/data/notify/hooks/test-runner-started.sh" ]]
[[ -x "$tmp/data/notify/hooks/test-runner-completed.sh" ]]

# Provider outage is fail-open when invoked from runner hooks.
export RUNNERCTL_NOTIFY_PROVIDERS=telegram
export RUNNERCTL_FAKE_CURL_FAIL=1
export GITHUB_REPOSITORY=example-org/example-repo
export GITHUB_RUN_ID=98765
export GITHUB_JOB=build
export GITHUB_WORKFLOW=CI
"$tmp/data/notify/hooks/test-runner-completed.sh"
[[ $? -eq 0 ]]
grep -q 'provider=telegram event=job.completed delivery=failed' "$tmp/data/notify/notify.log"

# Manual test is fail-closed so an operator can diagnose provider problems.
if bash "$ROOT/bin/runnerctl-notify" test --provider telegram >"$tmp/fail.out" 2>"$tmp/fail.err"; then
  echo 'notify test unexpectedly succeeded while fake provider failed' >&2
  exit 1
fi
! cat "$tmp/fail.out" "$tmp/fail.err" | grep -q 'tg-super-secret'
unset RUNNERCTL_FAKE_CURL_FAIL

status_json="$(bash "$ROOT/bin/runnerctl-notify" status --json)"
printf '%s' "$status_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled_runners!==1||!x.runners.find(r=>r.runner==="test-runner"&&r.enabled))process.exit(1)'
! printf '%s' "$status_json" | grep -q 'super-secret'

RUNNERCTL_HOOKS_HELPER="$tmp/bin/hooks" RUNNERCTL_SKIP_SERVICE_RESTART=1 bash "$ROOT/bin/runnerctl-notify" disable test-runner >/dev/null
grep -q '^unregister test-runner started notify$' "$tmp/hooks.log"
grep -q '^unregister test-runner completed notify$' "$tmp/hooks.log"

echo 'notification integration tests passed'
