#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures/ci"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/uname" <<'EOF_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${FAKE_OS:-Darwin}" ;;
  -m) printf '%s\n' "${FAKE_ARCH:-arm64}" ;;
  *) printf '%s\n' "${FAKE_OS:-Darwin}" ;;
esac
EOF_UNAME
chmod +x "$tmp/bin/uname"

cat > "$tmp/bin/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${FAKE_DOCKER_DOWN:-0}" == "1" ]] && exit 1
  exit 0
fi
exit 0
EOF_DOCKER
chmod +x "$tmp/bin/docker"

run_check() {
  env \
    PATH="$tmp/bin:/usr/bin:/bin" \
    RUNNERCTL_CI_WORKFLOW_DIR="$FIXTURES/workflows" \
    RUNNERCTL_CI_ACTION_METADATA_DIR="$FIXTURES/actions" \
    "$@" bash "$ROOT/bin/runnerctl-ci" check example/repo --current-host --json
}

mac_json="$(run_check env FAKE_OS=Darwin FAKE_ARCH=arm64)"
printf '%s' "$mac_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.repository !== "example/repo") process.exit(1);
if (!x.requirements.linux || !x.requirements.docker) process.exit(1);
if (x.requirements.macos) process.exit(1);
if (!x.findings.some(f => f.subject === "anothrNick/github-tag-action@1.67.0" && f.kind === "docker-action")) process.exit(1);
if (!x.findings.some(f => f.kind === "service-containers")) process.exit(1);
if (!x.findings.some(f => f.kind === "linux-command")) process.exit(1);
if (x.current_host.os !== "Darwin" || x.current_host.compatible !== false) process.exit(1);
if (!x.recommendation.includes("Linux self-hosted runner with Docker")) process.exit(1);
'

linux_json="$(run_check env FAKE_OS=Linux FAKE_ARCH=x86_64)"
printf '%s' "$linux_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.current_host.os !== "Linux") process.exit(1);
if (x.current_host.docker_daemon !== true) process.exit(1);
if (x.current_host.compatible !== true) process.exit(1);
'

linux_no_docker_json="$(run_check env FAKE_OS=Linux FAKE_DOCKER_DOWN=1)"
printf '%s' "$linux_no_docker_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.current_host.docker_daemon !== false || x.current_host.compatible !== false) process.exit(1);
'

text_output="$(env PATH="$tmp/bin:/usr/bin:/bin" FAKE_OS=Darwin RUNNERCTL_CI_WORKFLOW_DIR="$FIXTURES/workflows" RUNNERCTL_CI_ACTION_METADATA_DIR="$FIXTURES/actions" bash "$ROOT/bin/runnerctl-ci" check example/repo --current-host)"
printf '%s\n' "$text_output" | grep -q 'anothrNick/github-tag-action@1.67.0'
printf '%s\n' "$text_output" | grep -q 'Action metadata declares runs.using: docker.'
printf '%s\n' "$text_output" | grep -q 'Result: INCOMPATIBLE'
printf '%s\n' "$text_output" | grep -q 'Linux self-hosted runner with Docker'

echo 'CI compatibility tests passed'
