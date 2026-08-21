#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export RUNNERCTL_HOME="$tmp/data"
mkdir -p "$RUNNERCTL_HOME/runners/repo-a-01" "$tmp/targets"
printf 'name=repo-a-01\nrepo=example/a\n' > "$RUNNERCTL_HOME/runners/repo-a-01/.runnerctl-meta"

cat > "$tmp/targets/cleanup.sh" <<'EOF'
#!/usr/bin/env bash
printf 'cleanup\n' >> "${HOOK_TEST_LOG:?}"
EOF
cat > "$tmp/targets/queue.sh" <<'EOF'
#!/usr/bin/env bash
printf 'queue\n' >> "${HOOK_TEST_LOG:?}"
EOF
chmod +x "$tmp/targets/cleanup.sh" "$tmp/targets/queue.sh"

HOOK_TEST_LOG="$tmp/run.log" bash "$ROOT/bin/runnerctl-hooks" register repo-a-01 completed cleanup "$tmp/targets/cleanup.sh" >/dev/null
HOOK_TEST_LOG="$tmp/run.log" bash "$ROOT/bin/runnerctl-hooks" register repo-a-01 completed queue "$tmp/targets/queue.sh" >/dev/null

bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed cleanup
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed queue

dispatcher="$(awk -F= '$1=="ACTIONS_RUNNER_HOOK_JOB_COMPLETED"{sub(/^[^=]*=/,"");print}' "$RUNNERCTL_HOME/runners/repo-a-01/.env")"
[[ -x "$dispatcher" ]]
HOOK_TEST_LOG="$tmp/run.log" "$dispatcher"
grep -q '^cleanup$' "$tmp/run.log"
grep -q '^queue$' "$tmp/run.log"

bash "$ROOT/bin/runnerctl-hooks" unregister repo-a-01 completed cleanup >/dev/null
! bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed cleanup >/dev/null 2>&1
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed queue
[[ -x "$dispatcher" ]]

bash "$ROOT/bin/runnerctl-hooks" unregister repo-a-01 completed queue >/dev/null
! grep -q '^ACTIONS_RUNNER_HOOK_JOB_COMPLETED=' "$RUNNERCTL_HOME/runners/repo-a-01/.env"
[[ ! -e "$dispatcher" ]]

# Existing legacy cleanup hooks are migrated into the dispatcher automatically.
legacy="$RUNNERCTL_HOME/hooks/repo-a-01/job-completed-cleanup.sh"
mkdir -p "$(dirname "$legacy")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$legacy"
chmod +x "$legacy"
printf 'ACTIONS_RUNNER_HOOK_JOB_COMPLETED=%s\n' "$legacy" > "$RUNNERCTL_HOME/runners/repo-a-01/.env"
bash "$ROOT/bin/runnerctl-hooks" register repo-a-01 completed queue "$tmp/targets/queue.sh" >/dev/null
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed cleanup
bash "$ROOT/bin/runnerctl-hooks" has repo-a-01 completed queue

# Unmanaged custom hooks are never silently replaced.
bash "$ROOT/bin/runnerctl-hooks" unregister repo-a-01 completed queue >/dev/null
bash "$ROOT/bin/runnerctl-hooks" unregister repo-a-01 completed cleanup >/dev/null
custom="$tmp/custom.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$custom"; chmod +x "$custom"
printf 'ACTIONS_RUNNER_HOOK_JOB_COMPLETED=%s\n' "$custom" > "$RUNNERCTL_HOME/runners/repo-a-01/.env"
if bash "$ROOT/bin/runnerctl-hooks" register repo-a-01 completed queue "$tmp/targets/queue.sh" >/dev/null 2>&1; then
  echo 'custom hook should have been rejected' >&2
  exit 1
fi

echo 'hook composition tests passed'
