#!/usr/bin/env bash
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
