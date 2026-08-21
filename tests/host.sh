#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/alma-release" <<'EOF_ALMA'
NAME="AlmaLinux"
VERSION="8.10 (Cerulean Leopard)"
ID="almalinux"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.10"
PRETTY_NAME="AlmaLinux 8.10 (Cerulean Leopard)"
EOF_ALMA

cat > "$tmp/centos7-release" <<'EOF_CENTOS'
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
EOF_CENTOS

cat > "$tmp/bin/uname" <<'EOF_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${FAKE_OS:-Linux}" ;;
  -m) printf '%s\n' "${FAKE_ARCH:-x86_64}" ;;
  *) printf '%s\n' "${FAKE_OS:-Linux}" ;;
esac
EOF_UNAME
chmod +x "$tmp/bin/uname"

cat > "$tmp/bin/dnf" <<'EOF_DNF'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >> "${HOST_TEST_LOG:?}"
exit 0
EOF_DNF
chmod +x "$tmp/bin/dnf"

cat > "$tmp/bin/brew" <<'EOF_BREW'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "${HOST_TEST_LOG:?}"
exit 0
EOF_BREW
chmod +x "$tmp/bin/brew"

for cmd in git gh curl tar; do
  cat > "$tmp/bin/$cmd" <<'EOF_CMD'
#!/usr/bin/env bash
exit 0
EOF_CMD
  chmod +x "$tmp/bin/$cmd"
done

run_host() {
  env PATH="$tmp/bin:/usr/bin:/bin" \
    RUNNERCTL_HOST_OS_RELEASE_FILE="$1" \
    RUNNERCTL_HOST_FORCE_MISSING="${2:-}" \
    HOST_TEST_LOG="$tmp/host.log" \
    bash "$ROOT/bin/runnerctl-host" "${@:3}"
}

alma_json="$(run_host "$tmp/alma-release" 'git,gh' inspect --json)"
printf '%s' "$alma_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.platform.distro_id !== "almalinux") process.exit(1);
if (x.platform.distro_version !== "8.10") process.exit(1);
if (x.platform.family !== "rhel" || x.platform.supported !== true) process.exit(1);
if (x.package_manager.name !== "dnf" || x.package_manager.available !== true) process.exit(1);
if (!x.missing.includes("git") || !x.missing.includes("gh")) process.exit(1);
if (x.bootstrap_available !== true) process.exit(1);
'

alma_plan="$(run_host "$tmp/alma-release" 'git,gh' bootstrap --dry-run)"
printf '%s\n' "$alma_plan" | grep -q 'dnf install -y git'
printf '%s\n' "$alma_plan" | grep -q 'dnf-command(config-manager)'
printf '%s\n' "$alma_plan" | grep -q 'gh-cli.repo'
printf '%s\n' "$alma_plan" | grep -q 'dnf install -y gh'
[[ ! -f "$tmp/host.log" ]]

alma_plan_json="$(run_host "$tmp/alma-release" 'git,gh' bootstrap --dry-run --json)"
printf '%s' "$alma_plan_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (!x.dry_run || !x.missing.includes("git") || !x.plan.includes("gh-cli.repo")) process.exit(1);
'

if run_host "$tmp/centos7-release" 'git' bootstrap --dry-run >/dev/null 2>&1; then
  echo 'CentOS 7 bootstrap should be rejected' >&2
  exit 1
fi

mac_json="$(env PATH="$tmp/bin:/usr/bin:/bin" FAKE_OS=Darwin FAKE_ARCH=arm64 HOST_TEST_LOG="$tmp/host.log" RUNNERCTL_HOST_FORCE_MISSING=gh bash "$ROOT/bin/runnerctl-host" inspect --json)"
printf '%s' "$mac_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.platform.os !== "Darwin" || x.platform.family !== "macos") process.exit(1);
if (x.package_manager.name !== "brew" || x.package_manager.available !== true) process.exit(1);
'

mac_plan="$(env PATH="$tmp/bin:/usr/bin:/bin" FAKE_OS=Darwin FAKE_ARCH=arm64 HOST_TEST_LOG="$tmp/host.log" RUNNERCTL_HOST_FORCE_MISSING=gh bash "$ROOT/bin/runnerctl-host" bootstrap --dry-run)"
printf '%s\n' "$mac_plan" | grep -q 'brew install gh'

# A healthy host should be a no-op and must not invoke the package manager.
rm -f "$tmp/host.log"
env PATH="$tmp/bin:/usr/bin:/bin" RUNNERCTL_HOST_OS_RELEASE_FILE="$tmp/alma-release" HOST_TEST_LOG="$tmp/host.log" \
  bash "$ROOT/bin/runnerctl-host" bootstrap >/dev/null
[[ ! -f "$tmp/host.log" ]]

echo 'host bootstrap tests passed'
