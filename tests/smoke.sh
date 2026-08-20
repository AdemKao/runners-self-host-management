#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/package-release.sh"

[[ "$(bash "$ROOT/bin/runnerctl" version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
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
  [[ "$user" == "personal-account" || "$user" == "work-account" ]] || exit 1
  printf 'fake-token\n'
  exit 0
fi

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
  if [[ " $* " == *" --active "* ]]; then
    printf 'personal-account\n'
  else
    printf '*\tpersonal-account\tloggedIn\n \twork-account\tloggedIn\n'
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
  bash "$ROOT/bin/runnerctl" auth map 'example-org/*' work-account >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve example-org/example-repo
)"
[[ "$resolved" == "work-account" ]]

env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth map example-org/example-repo personal-account >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve example-org/example-repo
)"
[[ "$resolved" == "personal-account" ]]

env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
  bash "$ROOT/bin/runnerctl" auth unmap example-org/example-repo >/dev/null

resolved="$(
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/bin/runnerctl" auth resolve example-org/example-repo
)"
[[ "$resolved" == "work-account" ]]

PREFIX="$tmp/local" bash "$ROOT/install.sh" >/dev/null
[[ -x "$tmp/local/bin/runnerctl" ]]
[[ "$($tmp/local/bin/runnerctl version)" == "$(bash "$ROOT/bin/runnerctl" version)" ]]

DIST_DIR="$tmp/dist" bash "$ROOT/scripts/package-release.sh" >/dev/null
[[ -x "$tmp/dist/runnerctl" ]]
[[ -f "$tmp/dist/runnerctl.sha256" ]]
[[ -f "$tmp/dist/runnerctl-$(bash "$ROOT/bin/runnerctl" version).tar.gz" ]]

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp/dist" && sha256sum -c runnerctl.sha256 >/dev/null)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$tmp/dist" && shasum -a 256 -c runnerctl.sha256 >/dev/null)
fi

grep -q "example-org" "$ROOT/README.md"
grep -q "example-org" "$ROOT/README.zh-TW.md"
! grep -q "Claire-s-English" "$ROOT/README.md"
! grep -q "Claire-s-English" "$ROOT/README.zh-TW.md"

echo "smoke tests passed"
