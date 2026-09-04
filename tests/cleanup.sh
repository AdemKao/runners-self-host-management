#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

data="$tmp/data with [spaces]"
runner="$data/runners/example-runner-01"
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
  env HOME="$tmp/home" RUNNERCTL_HOME="$data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/runnerctl" "$@"
}

run cleanup --help | grep -q 'Host disk hygiene'
run add --help | grep -q -- '--cleanup'
run completion bash | grep -q 'cleanup add'
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.commands["cleanup status"] || !x.commands["cleanup run"]) process.exit(1)' \
  < <(run agent --json)

run cleanup enable example-runner-01 >/dev/null
hook="$data/hooks/example-runner-01/job-completed-cleanup.sh"
dispatcher="$data/hooks/example-runner-01/job-completed-dispatch.sh"
handler="$data/hooks/example-runner-01/completed.d/cleanup.sh"
[[ -x "$hook" ]]
[[ -x "$dispatcher" ]]
[[ -x "$handler" ]]
grep -Fq "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$dispatcher" "$runner/.env"

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.enabled || x.name!=="example-runner-01" || x.workspace_kb<=0) process.exit(1)' \
  < <(run cleanup status example-runner-01 --json)

HOME="$tmp/home" GITHUB_WORKSPACE="$workspace" bash "$dispatcher" >/dev/null
[[ -d "$workspace" ]]
[[ -z "$(find "$workspace" -mindepth 1 -maxdepth 1 -print -quit)" ]]
[[ -f "$cache/content" ]]

printf 'again\n' > "$workspace/file.txt"
run cleanup run example-runner-01 --dry-run | grep -Fq "$workspace"
run cleanup run example-runner-01 >/dev/null
[[ ! -e "$workspace/file.txt" ]]

# A workspace symlink is never followed by either manual cleanup or the
# completion hook. The target may be outside the runner work root.
external="$tmp/external-target"
mkdir -p "$external"
printf 'keep-me\n' >"$external/sentinel"
rmdir "$workspace"
ln -s "$external" "$workspace"
set +e
run cleanup run example-runner-01 >/dev/null 2>"$tmp/symlink.err"
rc=$?
set -e
[[ "$rc" -eq 7 ]]
[[ -f "$external/sentinel" ]]
HOME="$tmp/home" GITHUB_WORKSPACE="$workspace" bash "$dispatcher" >/dev/null 2>"$tmp/hook-symlink.err"
[[ -f "$external/sentinel" ]]
grep -q 'completion handler failed' "$tmp/hook-symlink.err"
rm "$workspace"
mkdir -p "$workspace"

# Lexically-in-root paths containing .. are canonicalized before deletion.
outside="$runner/outside"
mkdir -p "$outside"
printf 'keep-me-too\n' >"$outside/sentinel"
escape="$runner/_work/../outside"
HOME="$tmp/home" GITHUB_WORKSPACE="$escape" bash "$dispatcher" >/dev/null 2>"$tmp/hook-traversal.err"
[[ -f "$outside/sentinel" ]]
grep -q 'completion handler failed' "$tmp/hook-traversal.err"

run cleanup disable example-runner-01 >/dev/null
! grep -q '^ACTIONS_RUNNER_HOOK_JOB_COMPLETED=' "$runner/.env"
[[ ! -e "$hook" ]]
[[ ! -e "$handler" ]]
[[ ! -e "$dispatcher" ]]

echo "cleanup tests passed"
