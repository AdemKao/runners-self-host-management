#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.4.3"
NEXT_VERSION="0.4.4"

bash -n "$ROOT/runnerctl"
bash -n "$ROOT/runnerctl-base"
bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/bin/runnerctl-cleanup"
bash -n "$ROOT/bin/runnerctl-host"
bash -n "$ROOT/bin/runnerctl-ci"
bash -n "$ROOT/bin/runnerctl-hooks"
bash -n "$ROOT/bin/runnerctl-queue"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/package-release.sh"
bash -n "$ROOT/tests/launchd-status.sh"
bash -n "$ROOT/tests/host.sh"
bash -n "$ROOT/tests/ci-check.sh"
bash -n "$ROOT/tests/hooks.sh"
bash -n "$ROOT/tests/queue.sh"
bash -n "$ROOT/tests/installer.sh"

[[ "$(bash "$ROOT/runnerctl" version)" == "$VERSION" ]]
[[ "$(bash "$ROOT/bin/runnerctl" version)" == "$VERSION" ]]
bash "$ROOT/runnerctl" --help | grep -F 'Runner Management:' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'host' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'ci' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'capacity' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'queue' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'upgrade' >/dev/null
bash "$ROOT/runnerctl" --help | grep -F 'AI AGENT:' >/dev/null
bash "$ROOT/runnerctl" add --help | grep -F 'Side effects:' >/dev/null
bash "$ROOT/runnerctl" host --help | grep -F 'host prerequisites' >/dev/null
bash "$ROOT/runnerctl" ci --help | grep -F 'GitHub Actions workflows' >/dev/null
bash "$ROOT/runnerctl" capacity --help | grep -F 'safe job concurrency' >/dev/null
bash "$ROOT/runnerctl" queue --help | grep -F 'host-wide execution gate' >/dev/null
bash "$ROOT/runnerctl" upgrade --help | grep -F 'runnerctl upgrade --check --json' >/dev/null
bash "$ROOT/runnerctl" self-update --help | grep -F 'Check for or install the latest runnerctl release.' >/dev/null
bash "$ROOT/runnerctl" help auth map | grep -F 'Map a repository' >/dev/null
bash "$ROOT/runnerctl" agent | grep -F 'host inspect' >/dev/null
bash "$ROOT/runnerctl" agent | grep -F 'ci check' >/dev/null
bash "$ROOT/runnerctl" agent | grep -F 'capacity' >/dev/null
bash "$ROOT/runnerctl" agent | grep -F 'queue status' >/dev/null
bash "$ROOT/runnerctl" agent | grep -F 'upgrade --check' >/dev/null
bash "$ROOT/runnerctl" completion bash | grep -F 'capacity queue upgrade' >/dev/null
bash "$ROOT/runnerctl" completion zsh | grep -F 'queue:Manage host-wide job concurrency' >/dev/null
bash "$ROOT/runnerctl" completion fish | grep -F 'capacity queue upgrade' >/dev/null
bash "$ROOT/tests/launchd-status.sh"

grep -Fq '(bin/"runnerctl").write_env_script' "$ROOT/Formula/runnerctl.rb"
! grep -Fq 'bin.write_env_script(' "$ROOT/Formula/runnerctl.rb"

node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(0,"utf8"))' < <(bash "$ROOT/runnerctl" agent --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.agent_ready || x.version!==process.argv[1] || !x.commands["host inspect"] || !x.commands["host bootstrap --dry-run"] || !x.commands["ci check"] || !x.commands["capacity"] || !x.commands["queue status"] || !x.commands["queue enable"] || !x.commands["upgrade --check"]) process.exit(1)' "$VERSION" < <(bash "$ROOT/runnerctl" agent --json)

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.current_version!==process.argv[1] || x.latest_version!==process.argv[2] || !x.update_available || x.install_method!=="shell") process.exit(1)' "$VERSION" "$NEXT_VERSION" \
  < <(RUNNERCTL_LATEST_VERSION="$NEXT_VERSION" RUNNERCTL_INSTALL_METHOD=shell bash "$ROOT/runnerctl" upgrade --check --json)

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.update_available) process.exit(1)' \
  < <(RUNNERCTL_LATEST_VERSION="$VERSION" RUNNERCTL_INSTALL_METHOD=shell bash "$ROOT/runnerctl" upgrade --check --json)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/data/runners/example-runner-01"

cat > "$tmp/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-} ${2:-}" == "auth token" ]]; then
  user=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--user" ]]; then user="${2:-}"; break; fi
    shift
  done
  [[ "$user" == "personal-account" || "$user" == "work-account" ]] || exit 1
  printf 'fake-token\n'
  exit 0
fi

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
  args=" $* "
  if [[ "$args" == *'map({login:'* ]]; then
    printf '[{"login":"personal-account","active":true,"state":"loggedIn"},{"login":"work-account","active":false,"state":"loggedIn"}]\n'
  elif [[ "$args" == *' --active '* ]]; then
    printf 'personal-account\n'
  else
    printf '* personal-account loggedIn\n  work-account loggedIn\n'
  fi
  exit 0
fi

if [[ "${1:-} ${2:-}" == "auth switch" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "config get" ]]; then printf 'https\n'; exit 0; fi

printf 'unsupported fake gh command: %s\n' "$*" >&2
exit 1
EOF_GH
chmod +x "$tmp/bin/gh"

cat > "$tmp/bin/brew" <<'EOF_BREW'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == "list --versions" ]]; then printf 'runnerctl HEAD-deadbee\n'; exit 0; fi
if [[ "${1:-}" == "update" ]]; then printf 'update\n' >> "${RUNNERCTL_TEST_BREW_LOG:?}"; exit 0; fi
if [[ "${1:-} ${2:-} ${3:-}" == "upgrade --fetch-HEAD runnerctl" ]]; then printf 'upgrade-head\n' >> "${RUNNERCTL_TEST_BREW_LOG:?}"; exit 0; fi
exit 1
EOF_BREW
chmod +x "$tmp/bin/brew"

cat > "$tmp/data/runners/example-runner-01/.runnerctl-meta" <<'EOF_META'
name=example-runner-01
repo=example-org/example-repo
labels=local,ci
version=2.999.0
account=work-account
created_at=2026-01-01T00:00:00Z
EOF_META

run() {
  env PATH="$tmp/bin:$PATH" RUNNERCTL_HOME="$tmp/data" RUNNERCTL_CONFIG_HOME="$tmp/config" \
    bash "$ROOT/runnerctl" "$@"
}

run auth map 'example-org/*' work-account >/dev/null
[[ "$(run auth resolve example-org/example-repo)" == "work-account" ]]
run auth map example-org/example-repo personal-account >/dev/null
[[ "$(run auth resolve example-org/example-repo)" == "personal-account" ]]
run auth unmap example-org/example-repo >/dev/null
[[ "$(run auth resolve example-org/example-repo)" == "work-account" ]]

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.version!==process.argv[1] || !x.dependencies.gh) process.exit(1)' "$VERSION" < <(run doctor --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.runners.length!==1 || x.runners[0].name!=="example-runner-01") process.exit(1)' < <(run list --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.name!=="example-runner-01" || x.status!=="not-installed") process.exit(1)' < <(run status example-runner-01 --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.accounts.length!==2) process.exit(1)' < <(run auth list --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.mappings[0].pattern!=="example-org/*") process.exit(1)' < <(run auth mappings --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.account!=="work-account") process.exit(1)' < <(run auth resolve example-org/example-repo --json)
node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(0,"utf8"))' < <(run auth doctor --json)

RUNNERCTL_TEST_BREW_LOG="$tmp/brew.log" PATH="$tmp/bin:$PATH" RUNNERCTL_LATEST_VERSION="$NEXT_VERSION" RUNNERCTL_INSTALL_METHOD=homebrew \
  bash "$ROOT/runnerctl" upgrade >/dev/null
grep -q '^update$' "$tmp/brew.log"
grep -q '^upgrade-head$' "$tmp/brew.log"

PREFIX="$tmp/local" bash "$ROOT/install.sh" >/dev/null
[[ -x "$tmp/local/bin/runnerctl" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-core" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-host" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-ci" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-hooks" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-queue" ]]
[[ -x "$tmp/local/libexec/runnerctl/bin/runnerctl-host" ]]
[[ -x "$tmp/local/libexec/runnerctl/bin/runnerctl-ci" ]]
[[ -x "$tmp/local/libexec/runnerctl/bin/runnerctl-hooks" ]]
[[ -x "$tmp/local/libexec/runnerctl/bin/runnerctl-queue" ]]
[[ "$($tmp/local/bin/runnerctl version)" == "$VERSION" ]]
$tmp/local/bin/runnerctl agent --json | grep -F '"agent_ready": true' >/dev/null
$tmp/local/bin/runnerctl host --help | grep -F 'host prerequisites' >/dev/null
$tmp/local/bin/runnerctl ci --help | grep -F 'GitHub Actions workflows' >/dev/null
$tmp/local/bin/runnerctl capacity --help | grep -F 'safe job concurrency' >/dev/null
$tmp/local/bin/runnerctl queue --help | grep -F 'host-wide execution gate' >/dev/null
RUNNERCTL_HOME="$tmp/installed-data" "$tmp/local/bin/runnerctl" capacity --json | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.recommended) process.exit(1)'
RUNNERCTL_HOME="$tmp/installed-data" "$tmp/local/bin/runnerctl" queue status --json | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.enabled!==false) process.exit(1)'

DIST_DIR="$tmp/dist" bash "$ROOT/scripts/package-release.sh" >/dev/null
[[ -x "$tmp/dist/runnerctl" ]]
[[ -x "$tmp/dist/runnerctl-core" ]]
[[ -x "$tmp/dist/runnerctl-host" ]]
[[ -x "$tmp/dist/runnerctl-ci" ]]
[[ -x "$tmp/dist/runnerctl-hooks" ]]
[[ -x "$tmp/dist/runnerctl-queue" ]]
[[ -f "$tmp/dist/runnerctl.sha256" ]]
[[ -f "$tmp/dist/runnerctl-core.sha256" ]]
[[ -f "$tmp/dist/runnerctl-host.sha256" ]]
[[ -f "$tmp/dist/runnerctl-ci.sha256" ]]
[[ -f "$tmp/dist/runnerctl-hooks.sha256" ]]
[[ -f "$tmp/dist/runnerctl-queue.sha256" ]]
[[ -f "$tmp/dist/runnerctl-$VERSION.tar.gz" ]]

tar -tzf "$tmp/dist/runnerctl-$VERSION.tar.gz" > "$tmp/release-tar.list"
grep -q '^bin/runnerctl-host$' "$tmp/release-tar.list"
grep -q '^bin/runnerctl-ci$' "$tmp/release-tar.list"
grep -q '^bin/runnerctl-hooks$' "$tmp/release-tar.list"
grep -q '^bin/runnerctl-queue$' "$tmp/release-tar.list"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp/dist" && sha256sum -c runnerctl.sha256 runnerctl-core.sha256 runnerctl-host.sha256 runnerctl-ci.sha256 runnerctl-hooks.sha256 runnerctl-queue.sha256 "runnerctl-$VERSION.tar.gz.sha256" >/dev/null)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$tmp/dist" && shasum -a 256 -c runnerctl.sha256 runnerctl-core.sha256 runnerctl-host.sha256 runnerctl-ci.sha256 runnerctl-hooks.sha256 runnerctl-queue.sha256 "runnerctl-$VERSION.tar.gz.sha256" >/dev/null)
fi

grep -q 'example-org/example-repo' "$ROOT/README.md"
grep -q 'example-org/example-repo' "$ROOT/README.zh-TW.md"
! grep -q 'Claire-s-English' "$ROOT/README.md"
! grep -q 'Claire-s-English' "$ROOT/README.zh-TW.md"

echo "smoke tests passed"
