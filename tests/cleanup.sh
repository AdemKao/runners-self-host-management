#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

runner="$tmp/data/runners/example-runner-01"
workspace="$runner/_work/example-repo/example-repo"
cache="$tmp/home/.npm/_cacache"
mkdir -p "$workspace/node_modules/pkg" "$workspace/dist" "$cache"

cat > "$runner/.runnerctl-meta" <<'EOF_META'
name=example-runner-01
repo=example-org/example-repo
labels=local,ci
version=2.999.0
account=work-account
created_at=2026-01-01T00:00:00Z
EOF_META

printf 'dependency\n' > "$workspace/node_modules/pkg/index.js"
printf 'build\n' > "$workspace/dist/app.js"
printf 'cached package\n' > "$cache/content"

run() {
  env HOME="$tmp/home" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/runnerctl" "$@"
}

run cleanup --help | grep -q 'post-job hook'
run add --help | grep -q -- '--cleanup'
run cleanup enable example-runner-01 >/dev/null

hook="$tmp/data/hooks/example-runner-01/job-completed-cleanup.sh"
[[ -x "$hook" ]]
grep -Fq "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$hook" "$runner/.env"

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.enabled || x.name!=="example-runner-01" || x.workspace_kb<=0) process.exit(1)' \
  < <(run cleanup status example-runner-01 --json)

HOME="$tmp/home" GITHUB_WORKSPACE="$workspace" bash "$hook" >/dev/null
[[ -d "$workspace" ]]
[[ -z "$(find "$workspace" -mindepth 1 -maxdepth 1 -print -quit)" ]]
[[ -f "$cache/content" ]]

printf 'again\n' > "$workspace/file.txt"
run cleanup run example-runner-01 --dry-run | grep -q "$workspace"
run cleanup run example-runner-01 >/dev/null
[[ ! -e "$workspace/file.txt" ]]

run cleanup disable example-runner-01 >/dev/null
! grep -q '^ACTIONS_RUNNER_HOOK_JOB_COMPLETED=' "$runner/.env"
[[ ! -e "$hook" ]]

echo "cleanup tests passed"
