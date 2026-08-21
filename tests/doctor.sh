#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config" "$tmp/data"

cat > "$tmp/bin/uname" <<'EOF_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Linux\n' ;;
  -m) printf 'x86_64\n' ;;
  *) printf 'Linux\n' ;;
esac
EOF_UNAME

cat > "$tmp/bin/getconf" <<'EOF_GETCONF'
#!/usr/bin/env bash
if [[ "${1:-}" == "_NPROCESSORS_ONLN" ]]; then printf '2\n'; exit 0; fi
exit 1
EOF_GETCONF

cat > "$tmp/bin/df" <<'EOF_DF'
#!/usr/bin/env bash
cat <<'OUT'
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/fake 20971520 10485760 10485760 50% /
OUT
EOF_DF

cat > "$tmp/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "auth status" ]]; then printf 'test-account\n'; exit 0; fi
exit 0
EOF_GH

cat > "$tmp/bin/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${FAKE_DOCKER_FAIL:-0}" == "1" ]] && exit 1
  exit 0
fi
exit 0
EOF_DOCKER

for cmd in curl tar git; do
  cat > "$tmp/bin/$cmd" <<'EOF_CMD'
#!/usr/bin/env bash
exit 0
EOF_CMD
  chmod +x "$tmp/bin/$cmd"
done
chmod +x "$tmp/bin/uname" "$tmp/bin/getconf" "$tmp/bin/df" "$tmp/bin/gh" "$tmp/bin/docker"

cat > "$tmp/centos7-release" <<'EOF_CENTOS'
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
EOF_CENTOS

cat > "$tmp/alma8-release" <<'EOF_ALMA'
NAME="AlmaLinux"
VERSION="8.10 (Cerulean Leopard)"
ID="almalinux"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.10"
PRETTY_NAME="AlmaLinux 8.10 (Cerulean Leopard)"
EOF_ALMA

cat > "$tmp/low-meminfo" <<'EOF_LOW_MEM'
MemTotal:         980000 kB
MemFree:          100000 kB
SwapTotal:             0 kB
SwapFree:              0 kB
EOF_LOW_MEM

cat > "$tmp/healthy-meminfo" <<'EOF_HEALTHY_MEM'
MemTotal:        4194304 kB
MemFree:         2097152 kB
SwapTotal:       2097152 kB
SwapFree:        2097152 kB
EOF_HEALTHY_MEM

run_doctor() {
  local os_release="$1" meminfo="$2"
  shift 2
  env \
    PATH="$tmp/bin:/usr/bin:/bin" \
    RUNNERCTL_HOME="$tmp/data" \
    RUNNERCTL_CONFIG_HOME="$tmp/config" \
    RUNNERCTL_DOCTOR_OS_RELEASE_FILE="$os_release" \
    RUNNERCTL_DOCTOR_MEMINFO_FILE="$meminfo" \
    RUNNERCTL_DOCTOR_ROOT_PATH="/" \
    "$@" \
    bash "$ROOT/runnerctl" doctor --json
}

centos_json="$(run_doctor "$tmp/centos7-release" "$tmp/low-meminfo" env)"
printf '%s' "$centos_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.platform.distro_id !== "centos") process.exit(1);
if (x.platform.compatibility !== "unsupported") process.exit(1);
if (x.assessment.status !== "fail") process.exit(1);
if (!x.dependencies.git || !x.dependencies.docker || !x.dependencies.docker_daemon) process.exit(1);
if (!x.capabilities.container_actions) process.exit(1);
if (!(x.resources.memory_mib > 900 && x.resources.memory_mib < 1024)) process.exit(1);
if (!x.assessment.messages.some(m => m.includes("Unsupported runner OS"))) process.exit(1);
if (!x.assessment.messages.some(m => m.includes("Very low memory"))) process.exit(1);
'

alma_json="$(run_doctor "$tmp/alma8-release" "$tmp/healthy-meminfo" env)"
printf '%s' "$alma_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.platform.distro_id !== "almalinux") process.exit(1);
if (x.platform.distro_version !== "8.10") process.exit(1);
if (x.platform.compatibility !== "compatible") process.exit(1);
if (x.assessment.status !== "ok") process.exit(1);
if (x.resources.cpu_count !== 2) process.exit(1);
if (x.resources.memory_mib !== 4096) process.exit(1);
if (x.resources.swap_mib !== 2048) process.exit(1);
if (!x.capabilities.container_actions) process.exit(1);
'

alma_low_json="$(run_doctor "$tmp/alma8-release" "$tmp/low-meminfo" env)"
printf '%s' "$alma_low_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.platform.compatibility !== "compatible") process.exit(1);
if (x.assessment.status !== "warning") process.exit(1);
if (!x.assessment.messages.some(m => m.includes("Very low memory"))) process.exit(1);
if (!x.assessment.messages.some(m => m.includes("No swap"))) process.exit(1);
'

docker_down_json="$(run_doctor "$tmp/alma8-release" "$tmp/healthy-meminfo" env FAKE_DOCKER_FAIL=1)"
printf '%s' "$docker_down_json" | node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(0,"utf8"));
if (x.dependencies.docker !== true || x.dependencies.docker_daemon !== false) process.exit(1);
if (x.capabilities.container_actions !== false) process.exit(1);
if (x.assessment.status !== "warning") process.exit(1);
'

text_output="$(env PATH="$tmp/bin:/usr/bin:/bin" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" RUNNERCTL_DOCTOR_OS_RELEASE_FILE="$tmp/centos7-release" RUNNERCTL_DOCTOR_MEMINFO_FILE="$tmp/low-meminfo" RUNNERCTL_DOCTOR_ROOT_PATH=/ bash "$ROOT/runnerctl" doctor)"
printf '%s\n' "$text_output" | grep -q 'os: CentOS Linux 7 (Core)'
printf '%s\n' "$text_output" | grep -q 'os compatibility: UNSUPPORTED'
printf '%s\n' "$text_output" | grep -q 'git      OK'
printf '%s\n' "$text_output" | grep -q 'docker   OK'
printf '%s\n' "$text_output" | grep -q 'result: FAIL'
printf '%s\n' "$text_output" | grep -q 'Very low memory'

echo "doctor tests passed"
