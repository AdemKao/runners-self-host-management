#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
mkdir -p "$home/runners/runner-a" "$home/runners/runner-b" "$tmp/bin"
cat >"$home/runners/runner-a/.runnerctl-meta" <<'EOF'
name=runner-a
repo=example-org/repo-a
account=work-account
EOF
cat >"$home/runners/runner-b/.runnerctl-meta" <<'EOF'
name=runner-b
repo=example-org/repo-b
account=personal-account
EOF
printf 'baseline\n' >"$tmp/mode"
: >"$tmp/gh.log"
: >"$tmp/notify.log"

cat >"$tmp/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail
mode="$(cat "${RUNNERCTL_TEST_MODE_FILE:?}")"
log="${RUNNERCTL_TEST_GH_LOG:?}"
printf '%s\n' "$*" >>"$log"
if [[ "${1:-}" == auth && "${2:-}" == status ]]; then printf 'active-account\n'; exit 0; fi
if [[ "${1:-}" == auth && "${2:-}" == token ]]; then printf 'fake-token\n'; exit 0; fi
[[ "${1:-}" == api ]] || exit 2
endpoint=""
for arg in "$@"; do case "$arg" in repos/*) endpoint="$arg"; break ;; esac; done
[[ -n "$endpoint" ]] || exit 2
case "$endpoint" in
  'repos/example-org/repo-a/actions/runs?status=completed&per_page=20')
    case "$mode" in
      baseline) printf '101\t1\tCI\tmain\taaaa\n' ;;
      new|repeat) printf '102\t1\tCI\tmain\tbbbb\n101\t1\tCI\tmain\taaaa\n' ;;
      partial) printf '103\t1\tCI\tmain\tcccc\n102\t1\tCI\tmain\tbbbb\n' ;;
      recover) printf '103\t1\tCI\tmain\tcccc\n102\t1\tCI\tmain\tbbbb\n' ;;
    esac
    ;;
  'repos/example-org/repo-a/actions/runs/101/jobs?filter=latest&per_page=100')
    printf '1001\t101\ttest\tsuccess\t2026-08-23T01:00:00Z\t2026-08-23T01:01:00Z\t11\trunner-a\thttps://github.com/example-org/repo-a/actions/runs/101/job/1001\n'
    printf '1002\t101\thosted\tsuccess\t2026-08-23T01:00:00Z\t2026-08-23T01:01:00Z\t0\tGitHub Actions 42\thttps://example.invalid/1002\n'
    ;;
  'repos/example-org/repo-a/actions/runs/102/jobs?filter=latest&per_page=100')
    printf '1003\t102\tbuild\tfailure\t2026-08-23T02:00:00Z\t2026-08-23T02:02:00Z\t11\trunner-a\thttps://github.com/example-org/repo-a/actions/runs/102/job/1003\n'
    ;;
  'repos/example-org/repo-a/actions/runs/103/jobs?filter=latest&per_page=100')
    printf '1004\t103\trelease\ttimed_out\t2026-08-23T03:00:00Z\t2026-08-23T03:20:00Z\t11\trunner-a\thttps://github.com/example-org/repo-a/actions/runs/103/job/1004\n'
    ;;
  'repos/example-org/repo-b/actions/runs?status=completed&per_page=20')
    [[ "$mode" == partial ]] && exit 1
    case "$mode" in
      baseline) printf '201\t1\tTests\tmain\tdddd\n' ;;
      new|repeat) printf '202\t1\tTests\tmain\teeee\n201\t1\tTests\tmain\tdddd\n' ;;
      recover) printf '203\t1\tTests\tmain\tffff\n202\t1\tTests\tmain\teeee\n' ;;
    esac
    ;;
  'repos/example-org/repo-b/actions/runs/201/jobs?filter=latest&per_page=100')
    printf '2001\t201\ttest\tsuccess\t2026-08-23T01:00:00Z\t2026-08-23T01:03:00Z\t22\trunner-b\thttps://github.com/example-org/repo-b/actions/runs/201/job/2001\n'
    ;;
  'repos/example-org/repo-b/actions/runs/202/jobs?filter=latest&per_page=100')
    printf '2002\t202\tdeploy\tcancelled\t2026-08-23T02:00:00Z\t2026-08-23T02:01:00Z\t22\trunner-b\thttps://github.com/example-org/repo-b/actions/runs/202/job/2002\n'
    ;;
  'repos/example-org/repo-b/actions/runs/203/jobs?filter=latest&per_page=100')
    printf '2003\t203\tverify\tsuccess\t2026-08-23T04:00:00Z\t2026-08-23T04:01:00Z\t22\trunner-b\thttps://github.com/example-org/repo-b/actions/runs/203/job/2003\n'
    ;;
  *) echo "unexpected fake gh endpoint: $endpoint mode=$mode" >&2; exit 2 ;;
esac
EOF_GH
chmod +x "$tmp/bin/gh"

cat >"$tmp/notify" <<'EOF_NOTIFY'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == emit ]] || exit 2
printf '%s\t%s\n' "${2:-}" "$*" >>"${RUNNERCTL_TEST_NOTIFY_LOG:?}"
EOF_NOTIFY
chmod +x "$tmp/notify"

export PATH="$tmp/bin:$PATH"
export RUNNERCTL_HOME="$home"
export RUNNERCTL_MONITOR_TEST_TOKEN=fake-token
export RUNNERCTL_TEST_MODE_FILE="$tmp/mode"
export RUNNERCTL_TEST_GH_LOG="$tmp/gh.log"
export RUNNERCTL_TEST_NOTIFY_LOG="$tmp/notify.log"
export RUNNERCTL_NOTIFY_HELPER="$tmp/notify"
export RUNNERCTL_MONITOR_NO_BACKGROUND=1
monitor="$ROOT/bin/runnerctl-monitor"

bash "$monitor" status --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["enabled"] is False and x["history_count"] == 0'
bash "$monitor" enable --interval 60 --retention 3 >/dev/null
baseline="$(bash "$monitor" once --json)"
printf '%s' "$baseline" | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["baseline"] is True and x["new_outcomes"] == 2 and x["errors"] == 0'
[[ ! -s "$tmp/notify.log" ]]
bash "$monitor" jobs --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert len(x)==2; assert {r["runner_name"] for r in x}=={"runner-a","runner-b"}; assert all(r["runner_name"]!="GitHub Actions 42" for r in x)'

printf 'new\n' >"$tmp/mode"
second="$(bash "$monitor" once --json)"
printf '%s' "$second" | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["baseline"] is False and x["new_outcomes"] == 2 and x["errors"] == 0'
grep -q '^job.failed' "$tmp/notify.log"
grep -q '^job.cancelled' "$tmp/notify.log"
[[ "$(wc -l <"$tmp/notify.log" | tr -d ' ')" == 2 ]]
bash "$monitor" jobs --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert len(x)==3; assert x[0]["conclusion"]=="cancelled"; assert {r["conclusion"] for r in x}>={"failure","cancelled"}'
bash "$monitor" failures --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert {r["conclusion"] for r in x}=={"failure","cancelled"}'

jobs102_before="$(grep -c 'runs/102/jobs' "$tmp/gh.log" || true)"
jobs202_before="$(grep -c 'runs/202/jobs' "$tmp/gh.log" || true)"
printf 'repeat\n' >"$tmp/mode"
repeat="$(bash "$monitor" once --json)"
printf '%s' "$repeat" | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["new_outcomes"] == 0'
[[ "$(wc -l <"$tmp/notify.log" | tr -d ' ')" == 2 ]]
[[ "$(grep -c 'runs/102/jobs' "$tmp/gh.log" || true)" == "$jobs102_before" ]]
[[ "$(grep -c 'runs/202/jobs' "$tmp/gh.log" || true)" == "$jobs202_before" ]]

printf 'partial\n' >"$tmp/mode"
if bash "$monitor" once --json >"$tmp/partial.json" 2>"$tmp/partial.err"; then echo 'expected partial poll to return non-zero' >&2; exit 1; fi
python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["result"]=="partial" and x["errors"]==1 and x["new_outcomes"]==1' "$tmp/partial.json"
grep -q '^job.timed_out' "$tmp/notify.log"
bash "$monitor" status --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["last_result"]=="partial" and x["last_errors"]==1 and x["history_count"]==3'

printf 'recover\n' >"$tmp/mode"
recover="$(bash "$monitor" once --json)"
printf '%s' "$recover" | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["result"]=="success" and x["new_outcomes"]==1'
[[ "$(wc -l <"$tmp/notify.log" | tr -d ' ')" == 4 ]]
bash "$monitor" jobs --limit 100 --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert len(x)==3; assert x[0]["job"]=="verify"; assert any(r["conclusion"]=="timed_out" for r in x)'

# Manual once must not race a live background controller.
sleep 30 & fake_pid=$!
printf '%s\n' "$fake_pid" >"$home/monitor/monitor.pid"
if bash "$monitor" once --json >/dev/null 2>"$tmp/race.err"; then kill "$fake_pid" 2>/dev/null || true; echo 'expected manual once to reject live controller' >&2; exit 1; fi
grep -q 'background monitor is running' "$tmp/race.err"
kill "$fake_pid" 2>/dev/null || true
rm -f "$home/monitor/monitor.pid"

bash "$monitor" disable >/dev/null
bash "$monitor" status --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["enabled"] is False and x["history_count"]==3'

echo 'monitor tests passed'
