from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1))


frontend_old = '''service_state() {
  local dir="$1" service=""
  service="$(cat "$dir/.service" 2>/dev/null || true)"
  [[ -n "$service" ]] || { printf 'not-installed'; return; }
  case "$(uname -s)" in
    Darwin)
      if launchctl list 2>/dev/null | grep -Fq "$service"; then printf 'running'; else printf 'stopped'; fi
      ;;
    Linux)
      if systemctl is-active --quiet "$service" 2>/dev/null; then printf 'running'; else printf 'stopped'; fi
      ;;
    *) printf 'unknown' ;;
  esac
}
'''

frontend_new = '''launchd_service_label() {
  local service="$1"
  service="${service##*/}"
  service="${service%.plist}"
  printf '%s' "$service"
}

launchd_service_running() {
  local service="$1" label domain output
  label="$(launchd_service_label "$service")"
  [[ -n "$label" ]] || return 1
  domain="gui/$(id -u)"

  if output="$(launchctl print "$domain/$label" 2>/dev/null)"; then
    if printf '%s\n' "$output" | grep -Eq '^[[:space:]]*state = running([[:space:]]|$)'; then
      return 0
    fi
    if printf '%s\n' "$output" | grep -Eq '^[[:space:]]*pid = [1-9][0-9]*([[:space:]]|$)'; then
      return 0
    fi
    return 1
  fi

  launchctl list 2>/dev/null | awk -v label="$label" \
    '$3 == label && $1 ~ /^[0-9]+$/ { found=1 } END { exit(found ? 0 : 1) }'
}

service_state() {
  local dir="$1" service=""
  service="$(cat "$dir/.service" 2>/dev/null || true)"
  [[ -n "$service" ]] || { printf 'not-installed'; return; }
  case "$(uname -s)" in
    Darwin)
      if launchd_service_running "$service"; then printf 'running'; else printf 'stopped'; fi
      ;;
    Linux)
      if systemctl is-active --quiet "$service" 2>/dev/null; then printf 'running'; else printf 'stopped'; fi
      ;;
    *) printf 'unknown' ;;
  esac
}
'''

core_old = '''service_state() {
  local dir="$1" service=""
  service="$(cat "$dir/.service" 2>/dev/null || true)"
  [[ -n "$service" ]] || { echo "not-installed"; return; }
  case "$(uname -s)" in
    Darwin)
      if launchctl list 2>/dev/null | grep -Fq "$service"; then echo "running"; else echo "stopped"; fi
      ;;
    Linux)
      if systemctl is-active --quiet "$service" 2>/dev/null; then echo "running"; else echo "stopped"; fi
      ;;
    *) echo "unknown" ;;
  esac
}
'''

core_new = '''launchd_service_label() {
  local service="$1"
  service="${service##*/}"
  service="${service%.plist}"
  printf '%s' "$service"
}

launchd_service_running() {
  local service="$1" label domain output
  label="$(launchd_service_label "$service")"
  [[ -n "$label" ]] || return 1
  domain="gui/$(id -u)"

  if output="$(launchctl print "$domain/$label" 2>/dev/null)"; then
    if printf '%s\n' "$output" | grep -Eq '^[[:space:]]*state = running([[:space:]]|$)'; then
      return 0
    fi
    if printf '%s\n' "$output" | grep -Eq '^[[:space:]]*pid = [1-9][0-9]*([[:space:]]|$)'; then
      return 0
    fi
    return 1
  fi

  launchctl list 2>/dev/null | awk -v label="$label" \
    '$3 == label && $1 ~ /^[0-9]+$/ { found=1 } END { exit(found ? 0 : 1) }'
}

service_state() {
  local dir="$1" service=""
  service="$(cat "$dir/.service" 2>/dev/null || true)"
  [[ -n "$service" ]] || { echo "not-installed"; return; }
  case "$(uname -s)" in
    Darwin)
      if launchd_service_running "$service"; then echo "running"; else echo "stopped"; fi
      ;;
    Linux)
      if systemctl is-active --quiet "$service" 2>/dev/null; then echo "running"; else echo "stopped"; fi
      ;;
    *) echo "unknown" ;;
  esac
}
'''

replace_once('runnerctl', 'VERSION="0.3.1"', 'VERSION="0.3.2"')
replace_once('runnerctl', frontend_old, frontend_new)
replace_once('bin/runnerctl', 'VERSION="0.2.0"', 'VERSION="0.3.2"')
replace_once('bin/runnerctl', core_old, core_new)
replace_once('package.json', '"version": "0.3.1"', '"version": "0.3.2"')

formula = Path('Formula/runnerctl.rb')
f = formula.read_text()
if f.count('0.3.1') != 3:
    raise SystemExit(f"Formula/runnerctl.rb: expected three 0.3.1 occurrences, got {f.count('0.3.1')}")
formula.write_text(f.replace('0.3.1', '0.3.2'))

smoke = Path('tests/smoke.sh')
s = smoke.read_text().replace('0.3.1', '0.3.2')
s = s.replace('x.latest_version!=="0.3.2" || !x.update_available', 'x.latest_version!=="0.3.3" || !x.update_available', 1)
s = s.replace('RUNNERCTL_LATEST_VERSION=0.3.2 RUNNERCTL_INSTALL_METHOD=shell', 'RUNNERCTL_LATEST_VERSION=0.3.3 RUNNERCTL_INSTALL_METHOD=shell', 1)
s = s.replace('RUNNERCTL_LATEST_VERSION=0.3.2 RUNNERCTL_INSTALL_METHOD=homebrew', 'RUNNERCTL_LATEST_VERSION=0.3.3 RUNNERCTL_INSTALL_METHOD=homebrew', 1)
syntax_marker = 'bash -n "$ROOT/scripts/package-release.sh"\n'
if s.count(syntax_marker) != 1:
    raise SystemExit('tests/smoke.sh: syntax marker mismatch')
s = s.replace(syntax_marker, syntax_marker + 'bash -n "$ROOT/tests/launchd-status.sh"\n', 1)
run_marker = 'bash "$ROOT/runnerctl" completion fish | grep -q \'upgrade self-update\'\n'
if s.count(run_marker) != 1:
    raise SystemExit('tests/smoke.sh: run marker mismatch')
s = s.replace(run_marker, run_marker + 'bash "$ROOT/tests/launchd-status.sh"\n', 1)
smoke.write_text(s)

Path('tests/launchd-status.sh').write_text(r'''#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

runner="$tmp/data/runners/example-runner-01"
mkdir -p "$runner" "$tmp/bin"
cat > "$runner/.runnerctl-meta" <<'EOF_META'
name=example-runner-01
repo=example-org/example-repo
labels=local,ci
version=2.999.0
account=work-account
created_at=2026-01-01T00:00:00Z
EOF_META
printf '%s\n' '/Users/example/Library/LaunchAgents/actions.runner.example-org-example-repo.example-runner-01.plist' > "$runner/.service"

cat > "$tmp/bin/uname" <<'EOF_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) printf 'Darwin\n' ;;
esac
EOF_UNAME
chmod +x "$tmp/bin/uname"

cat > "$tmp/bin/launchctl" <<'EOF_LAUNCHCTL'
#!/usr/bin/env bash
set -euo pipefail
label='actions.runner.example-org-example-repo.example-runner-01'
mode="${RUNNERCTL_TEST_LAUNCHCTL_MODE:-print}"
case "${1:-}" in
  print)
    [[ "${2:-}" == gui/*/"$label" ]] || exit 113
    case "$mode" in
      print)
        cat <<EOF_PRINT
service = $label
{
    state = running
    pid = 4242
}
EOF_PRINT
        ;;
      list) exit 113 ;;
      stopped)
        cat <<EOF_STOPPED
service = $label
{
    state = waiting
}
EOF_STOPPED
        ;;
      *) exit 1 ;;
    esac
    ;;
  list)
    [[ "$mode" == list ]] || exit 0
    printf '4242\t0\t%s\n' "$label"
    ;;
  *) exit 1 ;;
esac
EOF_LAUNCHCTL
chmod +x "$tmp/bin/launchctl"

run_frontend() {
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/runnerctl" "$@"
}

run_core() {
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" "$@"
}

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.status!=="running") process.exit(1)' \
  < <(run_frontend status example-runner-01 --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.runners[0].status!=="running") process.exit(1)' \
  < <(run_frontend list --json)
run_core status example-runner-01 | grep -q '^example-runner-01: running$'

RUNNERCTL_TEST_LAUNCHCTL_MODE=list run_frontend status example-runner-01 --json | \
  node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.status!=="running") process.exit(1)'
RUNNERCTL_TEST_LAUNCHCTL_MODE=stopped run_frontend status example-runner-01 --json | \
  node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.status!=="stopped") process.exit(1)'

echo "launchd status regression tests passed"
''')
