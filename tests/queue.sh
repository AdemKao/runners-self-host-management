#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'jobs -p | xargs kill 2>/dev/null || true; rm -rf "$tmp"' EXIT
export RUNNERCTL_HOME="$tmp/data"
export RUNNERCTL_SKIP_SERVICE_RESTART=1
export RUNNERCTL_QUEUE_POLL_SECONDS=0.05
export RUNNERCTL_QUEUE_STALE_GRACE_SECONDS=0
export RUNNERCTL_QUEUE_MAX_WAIT_SECONDS=2
mkdir -p "$RUNNERCTL_HOME/runners/repo-a-01" "$RUNNERCTL_HOME/runners/repo-b-01"
printf 'name=repo-a-01\nrepo=example/repo-a\n' > "$RUNNERCTL_HOME/runners/repo-a-01/.runnerctl-meta"
printf 'name=repo-b-01\nrepo=other/repo-b\n' > "$RUNNERCTL_HOME/runners/repo-b-01/.runnerctl-meta"

queue(){ bash "$ROOT/bin/runnerctl-queue" "$@"; }

capacity="$(RUNNERCTL_QUEUE_CPU_COUNT=2 RUNNERCTL_QUEUE_MEMORY_MIB=1024 RUNNERCTL_QUEUE_SWAP_MIB=0 queue capacity --json)"
printf '%s' "$capacity" | node -e '
const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8"));
if(x.cpu!==2 || x.memory_mib!==1024) process.exit(1);
if(x.recommended.lightweight!==1 || x.recommended.node!==0 || x.recommended.docker!==0 || x.recommended.default_max_concurrency!==1) process.exit(1);
if(x.configured_runners!==2 || x.oversubscribed!==true) process.exit(1);
'

RUNNERCTL_SKIP_SERVICE_RESTART=1 bash "$ROOT/bin/runnerctl-cleanup" enable repo-a-01 >/dev/null
queue enable --max-concurrency 1 >/dev/null 2>"$tmp/enable.err"
grep -q 'legacy admission gate enabled' "$tmp/enable.err"
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed cleanup
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed queue
bash "$ROOT/bin/runnerctl-hooks" has repo-b-01 started queue

status="$(queue status --json)"
printf '%s' "$status" | node -e '
const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8"));
if(!x.enabled || x.drained || x.max_concurrency!==1 || x.active!==0 || x.configured_runners!==2) process.exit(1);
if(x.max_wait_seconds!==2 || x.mode!=="legacy-admission-gate") process.exit(1);
'

start_a="$RUNNERCTL_HOME/hooks/repo-a-01/queue-start.sh"
end_a="$RUNNERCTL_HOME/hooks/repo-a-01/queue-completed.sh"
start_b="$RUNNERCTL_HOME/hooks/repo-b-01/queue-start.sh"
end_b="$RUNNERCTL_HOME/hooks/repo-b-01/queue-completed.sh"
[[ -x "$RUNNERCTL_HOME/hooks/repo-a-01/queue-start.legacy.sh" ]]
[[ -x "$RUNNERCTL_HOME/hooks/repo-b-01/queue-start.legacy.sh" ]]

"$start_a" >/dev/null
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]

# A cancelled GitHub job must terminate the hidden legacy wait and clean state.
"$start_b" >/dev/null 2>"$tmp/cancel.err" &
pid_b=$!
for _ in {1..40}; do
  find "$RUNNERCTL_HOME/queue/waiting" -type f -name 'repo-b-01-*.wait' -print -quit | grep -q . && break
  sleep 0.05
done
kill -0 "$pid_b" 2>/dev/null
kill -TERM "$pid_b"
set +e
wait "$pid_b"
rc=$?
set -e
[[ "$rc" -eq 143 ]]
! find "$RUNNERCTL_HOME/queue/waiting" -type f -name 'repo-b-01-*.wait' -print -quit | grep -q .
[[ ! -f "$RUNNERCTL_HOME/queue/slots/repo-b-01.slot" ]]

# A normal waiter is admitted after the active slot is released.
"$start_b" >/dev/null &
pid_b=$!
for _ in {1..40}; do
  find "$RUNNERCTL_HOME/queue/waiting" -type f -name 'repo-b-01-*.wait' -print -quit | grep -q . && break
  sleep 0.05
done
kill -0 "$pid_b" 2>/dev/null
"$end_a" >/dev/null
wait "$pid_b"
[[ ! -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-b-01.slot" ]]

# Draining blocks new admission without terminating the active job.
queue drain >/dev/null
queue set --max-concurrency 2 >/dev/null
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-b-01.slot" ]]
"$end_b" >/dev/null
"$start_a" >/dev/null &
pid_a=$!
for _ in {1..40}; do
  find "$RUNNERCTL_HOME/queue/waiting" -type f -name 'repo-a-01-*.wait' -print -quit | grep -q . && break
  sleep 0.05
done
kill -0 "$pid_a" 2>/dev/null
[[ ! -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]
queue resume >/dev/null
wait "$pid_a"
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]

# Lowering concurrency does not terminate slots already acquired.
queue set --max-concurrency 2 >/dev/null
"$start_b" >/dev/null
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]
[[ -f "$RUNNERCTL_HOME/queue/slots/repo-b-01.slot" ]]
queue set --max-concurrency 1 >/dev/null
status="$(queue status --json)"
printf '%s' "$status" | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.max_concurrency!==1 || x.active!==2) process.exit(1)'
"$end_a" >/dev/null
"$end_b" >/dev/null

# A hidden Set up runner wait has a hard safety limit and cannot run forever.
queue drain >/dev/null
set +e
"$start_a" >"$tmp/maxwait.out" 2>"$tmp/maxwait.err"
rc=$?
set -e
[[ "$rc" -eq 124 ]]
grep -q 'legacy admission wait exceeded 2s' "$tmp/maxwait.err"
! find "$RUNNERCTL_HOME/queue/waiting" -type f -name 'repo-a-01-*.wait' -print -quit | grep -q .
[[ ! -f "$RUNNERCTL_HOME/queue/slots/repo-a-01.slot" ]]
queue resume >/dev/null

# Stale slots whose worker process no longer exists are repaired on status.
mkdir -p "$RUNNERCTL_HOME/queue/slots"
printf 'runner=stale\nworker_pid=999999\nacquired_at=1\n' > "$RUNNERCTL_HOME/queue/slots/stale.slot"
queue status --json >/dev/null
[[ ! -f "$RUNNERCTL_HOME/queue/slots/stale.slot" ]]

queue disable >/dev/null
status="$(queue status --json)"
printf '%s' "$status" | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.enabled || x.active!==0 || x.waiting!==0) process.exit(1)'
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed cleanup
! bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed queue >/dev/null 2>&1
[[ ! -e "$RUNNERCTL_HOME/hooks/repo-a-01/queue-start.legacy.sh" ]]

echo 'global queue tests passed'
