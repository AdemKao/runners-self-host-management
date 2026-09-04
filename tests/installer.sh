#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.8.0"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
DIST_DIR="$tmp/dist" bash "$ROOT/scripts/package-release.sh" >/dev/null
cp "$ROOT/install.sh" "$tmp/standalone-install.sh"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
root="${RUNNERCTL_TEST_SOURCE_ROOT:?}"
dist="${RUNNERCTL_TEST_DIST:?}"
out=""; url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="${2:?}"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[[ -n "$url" && -n "$out" ]] || exit 2
name="${url##*/}"
case "$url" in
  https://raw.githubusercontent.com/*/install-legacy.sh) cp "$root/install-legacy.sh" "$out" ;;
  https://github.com/*/releases/download/*) cp "$dist/$name" "$out" ;;
  *) echo "unsupported fake curl URL: $url" >&2; exit 2 ;;
esac
EOF_CURL
chmod +x "$tmp/bin/curl"
PATH="$tmp/bin:$PATH" RUNNERCTL_TEST_SOURCE_ROOT="$ROOT" RUNNERCTL_TEST_DIST="$tmp/dist" RUNNERCTL_VERSION="$VERSION" PREFIX="$tmp/prefix" \
  bash "$tmp/standalone-install.sh" >"$tmp/install.out" 2>"$tmp/install.err"
[[ ! -s "$tmp/install.err" ]]
cli="$tmp/prefix/bin/runnerctl"; lib="$tmp/prefix/libexec/runnerctl"
[[ "$($cli version)" == "$VERSION" ]]
for f in runnerctl-base runnerctl-base-v06 runnerctl-base-v05 runnerctl-base-legacy runnerctl-core runnerctl-core-legacy runnerctl-cleanup runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core runnerctl-notify runnerctl-notify-provider-telegram runnerctl-notify-provider-line runnerctl-notify-provider-webhook runnerctl-bot runnerctl-bot-controller.py; do
  [[ -x "$lib/$f" ]] || { echo "missing installed component: $f" >&2; exit 1; }
done
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled!==false)process.exit(1)' < <("$cli" scheduler status --json)
"$cli" scheduler --help >"$tmp/scheduler-help"; grep -q 'runnerctl-scheduled' "$tmp/scheduler-help"
"$cli" queue --help >"$tmp/queue-help"; grep -q 'Legacy host-side admission gate' "$tmp/queue-help"; grep -q 'default 300 seconds' "$tmp/queue-help"
"$cli" cleanup --help >"$tmp/cleanup-help"; grep -q 'Host disk hygiene' "$tmp/cleanup-help"; grep -q 'never prunes Docker volumes' "$tmp/cleanup-help"
"$cli" cleanup host policy --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.enabled!==false||x.min_free_gb!==10||!x.valid)process.exit(1)'
"$cli" notify --help >"$tmp/notify-help"; grep -q 'Notification integrations and provider plugins' "$tmp/notify-help"; grep -q 'notify doctor RUNNER' "$tmp/notify-help"
"$cli" notify providers --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(!x.find(p=>p.name==="telegram")||!x.find(p=>p.name==="line")||!x.find(p=>p.name==="webhook"))process.exit(1)'
"$cli" --help >"$tmp/root-help"; grep -q 'GitHub-native scheduling' "$tmp/root-help"; grep -q 'Notifications and integrations' "$tmp/root-help"; grep -q 'Read-only Bot/API controller' "$tmp/root-help"
if command -v python3 >/dev/null 2>&1; then
  "$cli" bot --help >"$tmp/bot-help"; grep -q 'Read-only Telegram, LINE, and HTTP API controller' "$tmp/bot-help"
  "$cli" bot doctor --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["version"]=="0.7.0" and x["read_only"] is True'
fi
RUNNERCTL_LATEST_VERSION="$VERSION" RUNNERCTL_INSTALL_METHOD=shell "$cli" upgrade --check --json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.current_version!=="0.8.0"||x.update_available)process.exit(1)'
for artifact in runnerctl runnerctl-base runnerctl-base-v06 runnerctl-base-v05 runnerctl-base-legacy runnerctl-core runnerctl-core-legacy runnerctl-cleanup runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core runnerctl-notify runnerctl-notify-provider-telegram runnerctl-notify-provider-line runnerctl-notify-provider-webhook runnerctl-bot runnerctl-bot-controller.py "runnerctl-$VERSION.tar.gz"; do
  [[ -f "$tmp/dist/$artifact.sha256" ]] || { echo "missing checksum: $artifact" >&2; exit 1; }
done
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp/dist" && sha256sum -c ./*.sha256 >/dev/null)
else
  for f in "$tmp/dist"/*.sha256; do (cd "$tmp/dist" && shasum -a 256 -c "$(basename "$f")" >/dev/null); done
fi
echo "v0.8.0 installer tests passed"
