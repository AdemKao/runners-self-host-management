#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.4.3"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/data/runners/example-runner-01"
cp "$ROOT/install.sh" "$tmp/standalone-install.sh"

cat > "$tmp/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail

root="${RUNNERCTL_TEST_SOURCE_ROOT:?}"
out=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="${2:?}"
      shift 2
      ;;
    -* )
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[[ -n "$url" && -n "$out" ]] || exit 2
name="${url##*/}"

source_for() {
  case "$1" in
    runnerctl) printf '%s/runnerctl' "$root" ;;
    runnerctl-base) printf '%s/runnerctl-base' "$root" ;;
    runnerctl-core) printf '%s/bin/runnerctl' "$root" ;;
    runnerctl-cleanup) printf '%s/bin/runnerctl-cleanup' "$root" ;;
    runnerctl-host) printf '%s/bin/runnerctl-host' "$root" ;;
    runnerctl-ci) printf '%s/bin/runnerctl-ci' "$root" ;;
    runnerctl-hooks) printf '%s/bin/runnerctl-hooks' "$root" ;;
    runnerctl-queue) printf '%s/bin/runnerctl-queue' "$root" ;;
    *) return 1 ;;
  esac
}

if [[ "$name" == *.sha256 ]]; then
  artifact="${name%.sha256}"
  source="$(source_for "$artifact")"
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$source" | awk '{print $1}')"
  else
    hash="$(shasum -a 256 "$source" | awk '{print $1}')"
  fi
  printf '%s  %s\n' "$hash" "$artifact" > "$out"
else
  source="$(source_for "$name")"
  cp "$source" "$out"
fi
EOF_CURL
chmod +x "$tmp/bin/curl"

PATH="$tmp/bin:$PATH" \
RUNNERCTL_TEST_SOURCE_ROOT="$ROOT" \
RUNNERCTL_VERSION="$VERSION" \
PREFIX="$tmp/prefix" \
  bash "$tmp/standalone-install.sh" > "$tmp/install.out" 2> "$tmp/install.err"

[[ ! -s "$tmp/install.err" ]]
grep -q "Installed runnerctl to $tmp/prefix/bin/runnerctl" "$tmp/install.out"

cli="$tmp/prefix/bin/runnerctl"
libexec="$tmp/prefix/libexec/runnerctl"
[[ -x "$cli" ]]
[[ -x "$libexec/runnerctl-queue" ]]
[[ -x "$libexec/runnerctl-hooks" ]]
[[ -x "$libexec/bin/runnerctl-host" ]]
[[ -x "$libexec/bin/runnerctl-ci" ]]
[[ -x "$libexec/bin/runnerctl-hooks" ]]
[[ -x "$libexec/bin/runnerctl-queue" ]]
[[ "$("$cli" version)" == "$VERSION" ]]

RUNNERCTL_HOME="$tmp/data" "$cli" capacity --json \
  | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!Number.isInteger(x.cpu) || !Number.isInteger(x.recommended.default_max_concurrency)) process.exit(1)'
RUNNERCTL_HOME="$tmp/data" "$cli" queue status --json \
  | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.enabled!==false || x.max_concurrency<1) process.exit(1)'

cat > "$tmp/data/runners/example-runner-01/.runnerctl-meta" <<'EOF_META'
name=example-runner-01
repo=example-org/example-repo
labels=local,ci
version=2.999.0
account=work-account
created_at=2026-01-01T00:00:00Z
EOF_META

RUNNERCTL_HOME="$tmp/data" RUNNERCTL_SKIP_SERVICE_RESTART=1 \
  "$cli" queue enable --max-concurrency 1 >/dev/null

grep -q '^ACTIONS_RUNNER_HOOK_JOB_STARTED=' "$tmp/data/runners/example-runner-01/.env"
grep -q '^ACTIONS_RUNNER_HOOK_JOB_COMPLETED=' "$tmp/data/runners/example-runner-01/.env"
[[ -x "$tmp/data/hooks/example-runner-01/started.d/queue.sh" ]]
[[ -x "$tmp/data/hooks/example-runner-01/completed.d/queue.sh" ]]

RUNNERCTL_HOME="$tmp/data" RUNNERCTL_SKIP_SERVICE_RESTART=1 \
  "$cli" queue disable >/dev/null

! grep -q '^ACTIONS_RUNNER_HOOK_JOB_STARTED=' "$tmp/data/runners/example-runner-01/.env"
! grep -q '^ACTIONS_RUNNER_HOOK_JOB_COMPLETED=' "$tmp/data/runners/example-runner-01/.env"

echo "installer regression tests passed"
