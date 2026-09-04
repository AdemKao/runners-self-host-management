#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
data="$tmp/data"
config="$tmp/config"
rootfs="$tmp/rootfs"
docker_root="$tmp/docker-root"
fakebin="$tmp/bin"
ps_file="$tmp/ps.txt"
df_file="$tmp/df.tsv"
docker_log="$tmp/docker.log"
mkdir -p "$home" "$data/runners/example-runner-01/_work/example-repo/example-repo" "$config" "$rootfs" "$docker_root" "$fakebin"
printf 'name=example-runner-01\nrepo=example-org/example-repo\naccount=work-account\n' >"$data/runners/example-runner-01/.runnerctl-meta"
printf 'workspace-data\n' >"$data/runners/example-runner-01/_work/example-repo/example-repo/file.txt"
: >"$ps_file"; : >"$docker_log"

write_df() {
  local docker_avail="$1" docker_used="$2"
  cat >"$df_file" <<EOF_DF
$rootfs	52428800	5242880	90
$data	104857600	94371840	10
$docker_root	52428800	$docker_avail	$docker_used
EOF_DF
}
write_df 5242880 90

cat >"$fakebin/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
set -euo pipefail
log="${FAKE_DOCKER_LOG:?}"
root="${FAKE_DOCKER_ROOT:?}"
printf '%s\n' "$*" >>"$log"
if [[ "${FAKE_DOCKER_DOWN:-0}" == 1 ]]; then exit 1; fi
case "${1:-} ${2:-}" in
  "info --format") printf '%s\n' "$root" ;;
  "ps -q") [[ -n "${FAKE_RUNNING_CONTAINERS:-}" ]] && printf '%s\n' "$FAKE_RUNNING_CONTAINERS" ;;
  "image ls") printf 'img-a\nimg-b\nimg-c\n' ;;
  "system df")
    if [[ "${FAKE_DOCKER_MALFORMED:-0}" == 1 ]]; then printf 'not-tab-separated\n'; else printf 'Images\t28.67GB\nBuild Cache\t16.78GB\n'; fi
    ;;
  "image prune") ;;
  "builder prune")
    if [[ -n "${FAKE_AFTER_AVAILABLE_KB:-}" && -n "${RUNNERCTL_CLEANUP_DF_FILE:-}" ]]; then
      tmpf="${RUNNERCTL_CLEANUP_DF_FILE}.tmp"
      awk -F'\t' -v OFS='\t' -v p="$root" -v a="$FAKE_AFTER_AVAILABLE_KB" '$1==p {$3=a; $4=(a>=10485760?80:88)} {print}' "$RUNNERCTL_CLEANUP_DF_FILE" >"$tmpf"
      mv "$tmpf" "$RUNNERCTL_CLEANUP_DF_FILE"
    fi
    ;;
  *) exit 2 ;;
esac
EOF_DOCKER
chmod +x "$fakebin/docker"

run_helper() {
  env \
    HOME="$home" RUNNERCTL_HOME="$data" RUNNERCTL_CONFIG_HOME="$config" \
    RUNNERCTL_CLEANUP_ROOT_PATH="$rootfs" RUNNERCTL_CLEANUP_DF_FILE="$df_file" \
    RUNNERCTL_CLEANUP_PS_FILE="$ps_file" FAKE_DOCKER_LOG="$docker_log" FAKE_DOCKER_ROOT="$docker_root" \
    PATH="$fakebin:$PATH" \
    "$@" bash "$ROOT/bin/runnerctl-cleanup" host
}

status_json="$(run_helper env status --json)"
printf '%s' "$status_json" | node -e '
const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8"));
if(x.policy.enabled!==false || x.policy.min_free_gb!==10) process.exit(1);
if(x.storage.root.available_kb!==5242880 || x.storage.docker_root.available_kb!==5242880) process.exit(1);
if(x.storage.runner_workspaces_kb<=0) process.exit(1);
if(x.docker.image_count!==3 || x.docker.build_cache_bytes!==16780000000) process.exit(1);
if(x.decision.cleanup_needed!==true || x.decision.blocked!==false) process.exit(1);
if(!x.warnings.some(w=>w.includes("below the 10 GiB"))) process.exit(1);
'

: >"$docker_log"
dry_json="$(run_helper env run --dry-run --json)"
printf '%s' "$dry_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.result!=="dry-run"||x.volumes_pruned!==false)process.exit(1)'
! grep -q '^image prune' "$docker_log"
! grep -q '^builder prune' "$docker_log"

run_helper env configure --enable --min-free-gb 10 --image-retention-hours 168 --build-cache-retention-hours 72 >/dev/null
policy_json="$(run_helper env policy --json)"
printf '%s' "$policy_json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(!x.enabled||x.image_retention_hours!==168||x.build_cache_retention_hours!==72)process.exit(1)'
[[ "$(stat -c %a "$data/cleanup/host-policy" 2>/dev/null || stat -f %Lp "$data/cleanup/host-policy")" == 600 ]]

# Active GitHub runner work must defer cleanup.
printf '123 /opt/actions-runner/bin/Runner.Worker spawnclient 456\n' >"$ps_file"
set +e
run_helper env run --json >"$tmp/active-runner.json"
rc=$?
set -e
[[ "$rc" -eq 4 ]]
printf '%s' "$(cat "$tmp/active-runner.json")" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.reason!=="runner_job_active")process.exit(1)'
: >"$ps_file"

# An independent Docker build also defers cleanup.
printf '222 docker buildx build .\n' >"$ps_file"
set +e
run_helper env run --json >"$tmp/active-build.json"
rc=$?
set -e
[[ "$rc" -eq 4 ]]
: >"$ps_file"

# Running containers defer cleanup. Existing stopped containers are left to
# Docker image-prune reference protection and are never removed by runnerctl.
set +e
run_helper env FAKE_RUNNING_CONTAINERS=container-1 run --json >"$tmp/active-container.json"
rc=$?
set -e
[[ "$rc" -eq 4 ]]
printf '%s' "$(cat "$tmp/active-container.json")" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.reason!=="running_containers")process.exit(1)'

# Lock contention fails fast; a stale dead-PID lock is recovered.
mkdir -p "$data/cleanup/host.lock"
printf '%s\n' "$$" >"$data/cleanup/host.lock/pid"
set +e
run_helper env run --dry-run --json >"$tmp/lock.json"
rc=$?
set -e
[[ "$rc" -eq 6 ]]
rm -f "$data/cleanup/host.lock/pid"; printf '99999999\n' >"$data/cleanup/host.lock/pid"
run_helper env run --dry-run --json >/dev/null
[[ ! -d "$data/cleanup/host.lock" ]]

# Malformed Docker accounting is visible in status and fails closed for mutation.
malformed="$(run_helper env FAKE_DOCKER_MALFORMED=1 status --json)"
printf '%s' "$malformed" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.docker.accounting_ok!==false||!x.docker.error.includes("malformed"))process.exit(1)'
set +e
run_helper env FAKE_DOCKER_MALFORMED=1 run --json >/dev/null
rc=$?
set -e
[[ "$rc" -eq 7 ]]

# Unreachable daemon is explicit and non-mutating.
down="$(run_helper env FAKE_DOCKER_DOWN=1 status --json)"
printf '%s' "$down" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.docker.cli!==true||x.docker.daemon!==false)process.exit(1)'
set +e
run_helper env FAKE_DOCKER_DOWN=1 run --json >/dev/null
rc=$?
set -e
[[ "$rc" -eq 5 ]]

# A healthy filesystem skips pruning even when host cleanup is enabled.
write_df 15728640 70
: >"$docker_log"
skip="$(run_helper env run --json)"
printf '%s' "$skip" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.result!=="skipped"||x.reason!=="free_space_target_met")process.exit(1)'
! grep -q '^image prune' "$docker_log"

# Low disk runs only the two age-filtered prune operations and never volumes.
write_df 5242880 90
: >"$docker_log"
cleaned="$(run_helper env FAKE_AFTER_AVAILABLE_KB=12582912 run --json)"
printf '%s' "$cleaned" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.result!=="cleaned"||x.reason!=="free_space_target_met"||x.reclaimed_kb<=0||x.volumes_pruned!==false)process.exit(1)'
grep -q '^image prune -a --force --filter until=168h$' "$docker_log"
grep -q '^builder prune --force --filter until=72h$' "$docker_log"
! grep -E 'system prune|volume|--volumes' "$docker_log"

# Safe retention cleanup does not silently escalate if the target is still unmet.
write_df 5242880 90
set +e
run_helper env FAKE_AFTER_AVAILABLE_KB=6291456 run --json >"$tmp/unmet.json"
rc=$?
set -e
[[ "$rc" -eq 3 ]]
printf '%s' "$(cat "$tmp/unmet.json")" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.reason!=="target_still_unmet")process.exit(1)'

# Simulate missing Docker with a restricted PATH containing all commands used by
# the helper except docker. This keeps the test independent from hosted images.
nodocker="$tmp/nodocker"; mkdir -p "$nodocker"
for cmd in awk bash cat chmod date dirname du find grep hostname mkdir mktemp mv ps pwd rm rmdir sort stat tr uname wc; do
  src="$(command -v "$cmd" || true)"; [[ -n "$src" ]] && ln -sf "$src" "$nodocker/$cmd"
done
missing="$(env HOME="$home" RUNNERCTL_HOME="$data" RUNNERCTL_CLEANUP_ROOT_PATH="$rootfs" RUNNERCTL_CLEANUP_DF_FILE="$df_file" RUNNERCTL_CLEANUP_PS_FILE="$ps_file" PATH="$nodocker" /bin/bash "$ROOT/bin/runnerctl-cleanup" host status --json)"
printf '%s' "$missing" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.docker.cli!==false||x.docker.daemon!==false)process.exit(1)'
set +e
env HOME="$home" RUNNERCTL_HOME="$data" RUNNERCTL_CLEANUP_ROOT_PATH="$rootfs" RUNNERCTL_CLEANUP_DF_FILE="$df_file" RUNNERCTL_CLEANUP_PS_FILE="$ps_file" PATH="$nodocker" /bin/bash "$ROOT/bin/runnerctl-cleanup" host run --json >/dev/null
rc=$?
set -e
[[ "$rc" -eq 5 ]]

echo 'host cleanup tests passed'
