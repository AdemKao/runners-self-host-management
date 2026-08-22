#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/data/runners/a" "$tmp/data/runners/b" "$tmp/data/runners/c"

cat >"$tmp/data/runners/a/.runnerctl-meta" <<'EOF'
name=runner-a
repo=example-org/repo-a
labels=local,linux,x64
version=2.999.0
account=work
EOF
cat >"$tmp/data/runners/b/.runnerctl-meta" <<'EOF'
name=runner-b
repo=example-org/repo-b
labels=local,linux,x64
version=2.999.0
account=work
EOF
cat >"$tmp/data/runners/c/.runnerctl-meta" <<'EOF'
name=runner-c
repo=example-org/repo-c
labels=local,linux,x64
version=2.999.0
account=work
EOF

printf '11\trunner-a\tonline\tfalse\tlocal\n' >"$tmp/state/runners_example-org_repo-a.tsv"
printf '22\trunner-b\tonline\tfalse\tlocal\n' >"$tmp/state/runners_example-org_repo-b.tsv"
printf '33\trunner-c\tonline\tfalse\tlocal\n' >"$tmp/state/runners_example-org_repo-c.tsv"
printf '101\t2026-08-22T00:00:00Z\n' >"$tmp/state/runs_example-org_repo-a.tsv"
printf '201\t2026-08-22T00:01:00Z\n' >"$tmp/state/runs_example-org_repo-b.tsv"
printf '301\t2026-08-22T00:02:00Z\n' >"$tmp/state/runs_example-org_repo-c.tsv"
printf '1001\tbuild-a\tself-hosted,linux,x64,runnerctl-scheduled\n' >"$tmp/state/jobs_example-org_repo-a_101.tsv"
printf '2001\tbuild-b\tself-hosted,linux,x64,runnerctl-scheduled\n' >"$tmp/state/jobs_example-org_repo-b_201.tsv"
printf '3001\tbuild-c\tself-hosted,linux,x64\n' >"$tmp/state/jobs_example-org_repo-c_301.tsv"

cat >"$tmp/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail
state="${RUNNERCTL_SCHEDULER_TEST_STATE:?}"
[[ "${1:-}" == api ]] || { echo "fake gh supports api only" >&2; exit 2; }
shift
method=GET
endpoint=""
label=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--jq) shift 2 ;;
    --method|-X) method="${2:?}"; shift 2 ;;
    -f|--field|-F) value="${2:?}"; [[ "$value" == labels\[\]=* ]] && label="${value#labels[]=}"; shift 2 ;;
    -*) shift ;;
    *) [[ -z "$endpoint" ]] && endpoint="$1"; shift ;;
  esac
done
[[ -n "$endpoint" ]] || exit 2
base="${endpoint%%\?*}"
repo="${base#repos/}"; repo="${repo%%/actions/*}"
slug="${repo//\//_}"
if [[ "${RUNNERCTL_SCHEDULER_TEST_FAIL_REPO:-}" == "$repo" ]]; then exit 1; fi
case "$method:$base" in
  GET:repos/*/actions/runners)
    cat "$state/runners_${slug}.tsv"
    ;;
  GET:repos/*/actions/runs)
    cat "$state/runs_${slug}.tsv"
    ;;
  GET:repos/*/actions/runs/*/jobs)
    run_id="${base#*actions/runs/}"; run_id="${run_id%%/jobs}"
    cat "$state/jobs_${slug}_${run_id}.tsv"
    ;;
  POST:repos/*/actions/runners/*/labels)
    id="${base#*actions/runners/}"; id="${id%%/labels}"
    file="$state/runners_${slug}.tsv"; out="$file.tmp"
    awk -F'\t' -v OFS='\t' -v id="$id" -v label="$label" '
      $1==id { n=split($5,a,","); found=0; for(i=1;i<=n;i++) if(a[i]==label) found=1; if(!found) $5=($5==""?label:$5 "," label) }
      {print}
    ' "$file" >"$out" && mv "$out" "$file"
    ;;
  DELETE:repos/*/actions/runners/*/labels/*)
    rest="${base#*actions/runners/}"; id="${rest%%/labels/*}"; remove="${rest#*/labels/}"
    file="$state/runners_${slug}.tsv"; out="$file.tmp"
    awk -F'\t' -v OFS='\t' -v id="$id" -v remove="$remove" '
      $1==id { n=split($5,a,","); s=""; for(i=1;i<=n;i++) if(a[i]!="" && a[i]!=remove) s=(s==""?a[i]:s "," a[i]); $5=s }
      {print}
    ' "$file" >"$out" && mv "$out" "$file"
    ;;
  *) echo "unsupported fake gh request: $method $base" >&2; exit 2 ;;
esac
EOF_GH
chmod +x "$tmp/bin/gh"

run_scheduler(){ env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_SCHEDULER_TEST_TOKEN=fake RUNNERCTL_SCHEDULER_TEST_STATE="$tmp/state" RUNNERCTL_SCHEDULER_NO_BACKGROUND=1 bash "$ROOT/bin/runnerctl-scheduler" "$@"; }
has_gate(){ local file="$1"; awk -F'\t' '$5 ~ /(^|,)runnerctl-scheduled(,|$)/ {found=1} END{exit found?0:1}' "$file"; }
set_busy(){
  local file="$1" value="$2" out
  out="$file.tmp"
  awk -F'\t' -v OFS='\t' -v value="$value" '{$4=value;print}' "$file" >"$out" && mv "$out" "$file"
}

# Disabled status is read-only and does not require GitHub API access.
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled!==false)process.exit(1)' < <(run_scheduler status --json)

# max=1: two scheduled repos have queued demand, but only one runner receives the routing label.
run_scheduler enable --max-concurrency 1 --interval 7 >/dev/null
count=0; has_gate "$tmp/state/runners_example-org_repo-a.tsv" && count=$((count+1)); has_gate "$tmp/state/runners_example-org_repo-b.tsv" && count=$((count+1)); [[ "$count" -eq 1 ]]
! has_gate "$tmp/state/runners_example-org_repo-c.tsv"
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(!x.enabled||x.max_concurrency!==1||x.queued_jobs!==2||x.gate_holders!==1)process.exit(1)' < <(run_scheduler status --json)

# Identify holder and prove drain never revokes the routing label from a busy runner.
if has_gate "$tmp/state/runners_example-org_repo-a.tsv"; then holder=a; holder_file="$tmp/state/runners_example-org_repo-a.tsv"; other_file="$tmp/state/runners_example-org_repo-b.tsv"; else holder=b; holder_file="$tmp/state/runners_example-org_repo-b.tsv"; other_file="$tmp/state/runners_example-org_repo-a.tsv"; fi
set_busy "$holder_file" true
run_scheduler drain >/dev/null
has_gate "$holder_file"
! has_gate "$other_file"

# Once the active runner is idle, a drained tick revokes its gate and grants no replacement.
set_busy "$holder_file" false
run_scheduler tick >/dev/null
! has_gate "$holder_file"; ! has_gate "$other_file"

# Resume reassigns exactly one slot; round-robin cursor should prefer the other queued repository.
run_scheduler resume >/dev/null
count=0; has_gate "$tmp/state/runners_example-org_repo-a.tsv" && count=$((count+1)); has_gate "$tmp/state/runners_example-org_repo-b.tsv" && count=$((count+1)); [[ "$count" -eq 1 ]]

# The legacy queue gate cannot be enabled at the same time as the scheduler.
if RUNNERCTL_HOME="$tmp/data" bash "$ROOT/bin/runnerctl-queue" enable --max-concurrency 1 >"$tmp/q.out" 2>"$tmp/q.err"; then echo "legacy queue unexpectedly enabled" >&2; exit 1; fi
grep -qi 'scheduler is enabled' "$tmp/q.err"

# Disable revokes scheduler labels. Then legacy queue config blocks scheduler enable.
run_scheduler disable >/dev/null
! has_gate "$tmp/state/runners_example-org_repo-a.tsv"; ! has_gate "$tmp/state/runners_example-org_repo-b.tsv"
mkdir -p "$tmp/data/queue"; printf 'enabled=true\nmax_concurrency=1\ndrained=false\n' >"$tmp/data/queue/config"
if run_scheduler enable --max-concurrency 1 >"$tmp/e.out" 2>"$tmp/e.err"; then echo "scheduler unexpectedly enabled with legacy queue" >&2; exit 1; fi
grep -qi 'legacy runnerctl queue gate is enabled' "$tmp/e.err"
rm -f "$tmp/data/queue/config"

# API snapshot failures fail closed: enable fails and no routing label is granted.
if RUNNERCTL_SCHEDULER_TEST_FAIL_REPO=example-org/repo-a run_scheduler enable --max-concurrency 1 >"$tmp/f.out" 2>"$tmp/f.err"; then echo "scheduler unexpectedly enabled after API failure" >&2; exit 1; fi
! has_gate "$tmp/state/runners_example-org_repo-a.tsv"; ! has_gate "$tmp/state/runners_example-org_repo-b.tsv"
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled!==false)process.exit(1)' < <(run_scheduler status --json)

# Legacy queue help must clearly distinguish admission gating from GitHub-native queueing.
bash "$ROOT/bin/runnerctl-queue" --help | grep -q 'Legacy host-side admission gate'
bash "$ROOT/bin/runnerctl-scheduler" --help | grep -q 'Jobs stay GitHub "queued"'

echo "scheduler tests passed"
