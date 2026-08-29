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

export RUNNERCTL_TELEGRAM_BOT_TOKEN='tg-super-secret'
export RUNNERCTL_TELEGRAM_CHAT_ID='123456'
export RUNNERCTL_LINE_CHANNEL_ACCESS_TOKEN='line-super-secret'
export RUNNERCTL_LINE_TO='U123456789'
export RUNNERCTL_WEBHOOK_URL='https://example.invalid/runnerctl'
export RUNNERCTL_WEBHOOK_AUTH_HEADER='Authorization: Bearer webhook-super-secret'
providers_json="$(bash "$ROOT/bin/runnerctl-notify" providers --json)"
printf '%s' "$providers_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.length<3||!x.find(p=>p.name==="telegram"&&p.configured)||!x.find(p=>p.name==="line"&&p.configured)||!x.find(p=>p.name==="webhook"&&p.configured))process.exit(1)'
! printf '%s' "$providers_json" | grep -q 'super-secret'

: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=telegram bash "$ROOT/bin/runnerctl-notify" test --provider telegram >"$tmp/tg.out" 2>"$tmp/tg.err"
grep -q 'api.telegram.org/bottg-super-secret/sendMessage' "$tmp/curl-config.log"
grep -q 'chat_id=123456' "$tmp/curl-args.log"
grep -q 'runnerctl notification test' "$tmp/curl-args.log"
! cat "$tmp/tg.out" "$tmp/tg.err" | grep -q 'tg-super-secret'

: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=line bash "$ROOT/bin/runnerctl-notify" test --provider line >"$tmp/line.out" 2>"$tmp/line.err"
grep -q 'https://api.line.me/v2/bot/message/push' "$tmp/curl-config.log"
grep -q 'Authorization: Bearer line-super-secret' "$tmp/curl-config.log"
grep -q 'U123456789' "$tmp/curl-args.log"
! cat "$tmp/line.out" "$tmp/line.err" | grep -q 'line-super-secret'

: >"$tmp/curl-config.log"; : >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=webhook bash "$ROOT/bin/runnerctl-notify" emit scheduler.drained --message 'maintenance window' >"$tmp/webhook.out" 2>"$tmp/webhook.err"
grep -q 'https://example.invalid/runnerctl' "$tmp/curl-config.log"
grep -q 'Authorization: Bearer webhook-super-secret' "$tmp/curl-config.log"
grep -q 'scheduler.drained' "$tmp/curl-args.log"
grep -q 'maintenance window' "$tmp/curl-args.log"
! cat "$tmp/webhook.out" "$tmp/webhook.err" | grep -q 'webhook-super-secret'

# Executable plugins still work for explicit/manual delivery.
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

RUNNERCTL_HOOKS_HELPER="$tmp/bin/hooks" RUNNERCTL_SKIP_SERVICE_RESTART=1 \
  bash "$ROOT/bin/runnerctl-notify" enable test-runner --events job.started,job.completed >/dev/null
grep -q '^register test-runner started notify ' "$tmp/hooks.log"
grep -q '^register test-runner completed notify ' "$tmp/hooks.log"
[[ -x "$tmp/data/notify/hooks/test-runner-started.sh" ]]
[[ -x "$tmp/data/notify/hooks/test-runner-completed.sh" ]]

# Started notifications are actionable and explicitly describe runner-setup semantics.
export RUNNERCTL_NOTIFY_PROVIDERS=telegram
export GITHUB_REPOSITORY=example-org/example-repo
export GITHUB_RUN_ID=98765
export GITHUB_RUN_ATTEMPT=2
export GITHUB_JOB=build_and_test
export GITHUB_WORKFLOW='CI Pipeline'
export GITHUB_HEAD_REF='feature/observable-notify'
export GITHUB_REF='refs/pull/123/merge'
export GITHUB_REF_NAME='123/merge'
export GITHUB_REF_TYPE=branch
export GITHUB_SHA='0123456789abcdef0123456789abcdef01234567'
export GITHUB_EVENT_NAME=pull_request
export GITHUB_SERVER_URL=https://github.com
: >"$tmp/curl-args.log"
"$tmp/data/notify/hooks/test-runner-started.sh"
grep -q 'runner assigned / setup started' "$tmp/curl-args.log"
grep -q 'branch: feature/observable-notify' "$tmp/curl-args.log"
grep -q 'job: build_and_test' "$tmp/curl-args.log"
grep -q 'sha: 0123456789ab' "$tmp/curl-args.log"
grep -q 'url: https://github.com/example-org/example-repo/actions/runs/98765' "$tmp/curl-args.log"
grep -q 'workflow steps have not started yet' "$tmp/curl-args.log"

# Webhook event JSON contains the same navigation context without extra GitHub API calls.
: >"$tmp/curl-args.log"
RUNNERCTL_NOTIFY_PROVIDERS=webhook bash "$ROOT/bin/runnerctl-notify" emit job.started --runner test-runner >/dev/null
payload_arg="$(grep -- '--data-binary' "$tmp/curl-args.log" | tail -n1)"
printf '%s' "$payload_arg" | grep -q 'feature/observable-notify'
printf '%s' "$payload_arg" | grep -q 'https://github.com/example-org/example-repo/actions/runs/98765'
printf '%s' "$payload_arg" | grep -q 'runner-assigned-before-steps'

# Custom plugins are NOT allowed to block synchronous GitHub runner hooks by default.
rm -f "$tmp/plugin.json" "$tmp/plugin.env"
RUNNERCTL_NOTIFY_PROVIDERS=custom RUNNERCTL_PLUGIN_EVENT_FILE="$tmp/plugin.json" RUNNERCTL_PLUGIN_ENV_FILE="$tmp/plugin.env" \
  RUNNERCTL_NOTIFY_HOOK=1 bash "$ROOT/bin/runnerctl-notify" hook test-runner started >"$tmp/custom-hook.out" 2>"$tmp/custom-hook.err"
[[ ! -e "$tmp/plugin.json" ]]
grep -q 'custom provider custom skipped in synchronous runner hook' "$tmp/custom-hook.err"

# Provider outage is fail-open when invoked from runner hooks.
export RUNNERCTL_NOTIFY_PROVIDERS=telegram
export RUNNERCTL_FAKE_CURL_FAIL=1
"$tmp/data/notify/hooks/test-runner-completed.sh"
[[ $? -eq 0 ]]
grep -q 'provider=telegram event=job.completed delivery=failed' "$tmp/data/notify/notify.log"

if bash "$ROOT/bin/runnerctl-notify" test --provider telegram >"$tmp/fail.out" 2>"$tmp/fail.err"; then
  echo 'notify test unexpectedly succeeded while fake provider failed' >&2
  exit 1
fi
! cat "$tmp/fail.out" "$tmp/fail.err" | grep -q 'tg-super-secret'
unset RUNNERCTL_FAKE_CURL_FAIL

# Doctor exposes hook composition / queue hazards without secrets.
mkdir -p "$tmp/data/hooks/test-runner/started.d" "$tmp/data/hooks/test-runner/completed.d" "$tmp/data/queue" "$tmp/data/scheduler"
printf '#!/bin/sh\n' >"$tmp/data/hooks/test-runner/started.d/notify.sh"
printf '#!/bin/sh\n' >"$tmp/data/hooks/test-runner/started.d/queue.sh"
printf '#!/bin/sh\n' >"$tmp/data/hooks/test-runner/completed.d/notify.sh"
printf 'ACTIONS_RUNNER_HOOK_JOB_STARTED=%s\nACTIONS_RUNNER_HOOK_JOB_COMPLETED=%s\n' "$tmp/data/hooks/test-runner/job-started-dispatch.sh" "$tmp/data/hooks/test-runner/job-completed-dispatch.sh" >"$tmp/data/runners/test-runner/.env"
printf 'enabled=true\ndrained=false\nmax_concurrency=1\n' >"$tmp/data/queue/config"
printf 'max_wait_seconds=300\n' >"$tmp/data/queue/safety"
printf 'enabled=false\n' >"$tmp/data/scheduler/config"
doctor_json="$(bash "$ROOT/bin/runnerctl-notify" doctor test-runner --json)"
printf '%s' "$doctor_json" | node -e '
const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));
if(!x.notification_enabled||!x.legacy_queue.enabled||x.legacy_queue.max_wait_seconds!==300)process.exit(1);
if(!x.started_handlers.includes("notify")||!x.started_handlers.includes("queue"))process.exit(1);
if(!x.warning.includes("legacy queue is enabled"))process.exit(1);
'
! printf '%s' "$doctor_json" | grep -q 'super-secret'

status_json="$(bash "$ROOT/bin/runnerctl-notify" status --json)"
printf '%s' "$status_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled_runners!==1||!x.runners.find(r=>r.runner==="test-runner"&&r.enabled))process.exit(1)'
! printf '%s' "$status_json" | grep -q 'super-secret'

RUNNERCTL_HOOKS_HELPER="$tmp/bin/hooks" RUNNERCTL_SKIP_SERVICE_RESTART=1 bash "$ROOT/bin/runnerctl-notify" disable test-runner >/dev/null
grep -q '^unregister test-runner started notify$' "$tmp/hooks.log"
grep -q '^unregister test-runner completed notify$' "$tmp/hooks.log"

echo 'notification integration tests passed'
