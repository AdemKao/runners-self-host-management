#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/install.sh"

[[ "$(bash "$ROOT/bin/runnerctl" version)" == "0.2.0" ]]
bash "$ROOT/bin/runnerctl" --help | grep -q 'runnerctl auth list'
bash "$ROOT/bin/runnerctl" --help | grep -q -- '--account ACCOUNT'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" list | grep -q 'ACCOUNT'

RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth mappings | grep -q 'REPOSITORY PATTERN'

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-} ${2:-}" == "auth token" ]]; then
  user=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--user" ]]; then
      user="${2:-}"
      break
    fi
    shift
  done
  [[ "$user" == "personal-user" || "$user" == "work-user" ]] || exit 1
  printf 'fake-token\n'
  exit 0
fi

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
  if [[ " $* " == *" --active "* ]]; then
    printf 'personal-user\n'
  else
    printf '*\tpersonal-user\tloggedIn\n \twork-user\tloggedIn\n'
  fi
  exit 0
fi

if [[ "${1:-} ${2:-}" == "auth switch" ]]; then
  exit 0
fi

if [[ "${1:-} ${2:-}" == "config get" ]]; then
  printf 'https\n'
  exit 0
fi

printf 'unsupported fake gh command: %s\n' "$*" >&2
exit 1
EOF_GH
chmod +x "$tmp/bin/gh"

env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth map 'Claire-s-English/*' work-user >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve Claire-s-English/billing-platform
)"
[[ "$resolved" == "work-user" ]]

env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth map Claire-s-English/billing-platform personal-user >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve Claire-s-English/billing-platform
)"
[[ "$resolved" == "personal-user" ]]

env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth unmap Claire-s-English/billing-platform >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve Claire-s-English/billing-platform
)"
[[ "$resolved" == "work-user" ]]

echo "smoke tests passed"
