#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/runnerctl"
bash -n "$ROOT/bin/runnerctl"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/package-release.sh"
bash -n "$ROOT/tests/launchd-status.sh"

[[ "$(bash "$ROOT/runnerctl" version)" == "0.3.2" ]]
bash "$ROOT/runnerctl" --help | grep -q 'Runner Management:'
bash "$ROOT/runnerctl" --help | grep -q 'upgrade'
bash "$ROOT/runnerctl" --help | grep -q 'AI AGENT:'
bash "$ROOT/runnerctl" add --help | grep -q 'Side effects:'
bash "$ROOT/runnerctl" upgrade --help | grep -q 'runnerctl upgrade --check --json'
bash "$ROOT/runnerctl" self-update --help | grep -q 'Check for or install the latest runnerctl release.'
bash "$ROOT/runnerctl" help auth map | grep -q 'Map a repository'
bash "$ROOT/runnerctl" agent | grep -q 'upgrade --check'
bash "$ROOT/runnerctl" completion bash | grep -q 'upgrade self-update'
bash "$ROOT/runnerctl" completion zsh | grep -q 'upgrade:Upgrade runnerctl'
bash "$ROOT/runnerctl" completion fish | grep -q 'upgrade self-update'
bash "$ROOT/tests/launchd-status.sh"

grep -Fq '(bin/"runnerctl").write_env_script' "$ROOT/Formula/runnerctl.rb"
! grep -Fq 'bin.write_env_script(' "$ROOT/Formula/runnerctl.rb"

node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(0,"utf8"))' < <(bash "$ROOT/runnerctl" agent --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(!x.agent_ready || x.version!=="0.3.2" || !x.commands["upgrade --check"]) process.exit(1)' < <(bash "$ROOT/runnerctl" agent --json)

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.current_version!=="0.3.2" || x.latest_version!=="0.3.3" || !x.update_available || x.install_method!=="shell") process.exit(1)' \
  < <(RUNNERCTL_LATEST_VERSION=0.3.3 RUNNERCTL_INSTALL_METHOD=shell bash "$ROOT/runnerctl" upgrade --check --json)

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.update_available) process.exit(1)' \
  < <(RUNNERCTL_LATEST_VERSION=0.3.2 RUNNERCTL_INSTALL_METHOD=shell bash "$ROOT/runnerctl" upgrade --check --json)

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

node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.version!=="0.3.2" || !x.dependencies.gh) process.exit(1)' < <(run doctor --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.runners.length!==1 || x.runners[0].name!=="example-runner-01") process.exit(1)' < <(run list --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.name!=="example-runner-01" || x.status!=="not-installed") process.exit(1)' < <(run status example-runner-01 --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.accounts.length!==2) process.exit(1)' < <(run auth list --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.mappings[0].pattern!=="example-org/*") process.exit(1)' < <(run auth mappings --json)
node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); if(x.account!=="work-account") process.exit(1)' < <(run auth resolve example-org/example-repo --json)
node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(0,"utf8"))' < <(run auth doctor --json)

RUNNERCTL_TEST_BREW_LOG="$tmp/brew.log" PATH="$tmp/bin:$PATH" RUNNERCTL_LATEST_VERSION=0.3.3 RUNNERCTL_INSTALL_METHOD=homebrew \
  bash "$ROOT/runnerctl" upgrade >/dev/null
grep -q '^update$' "$tmp/brew.log"
grep -q '^upgrade-head$' "$tmp/brew.log"

PREFIX="$tmp/local" bash "$ROOT/install.sh" >/dev/null
[[ -x "$tmp/local/bin/runnerctl" ]]
[[ -x "$tmp/local/libexec/runnerctl/runnerctl-core" ]]
[[ "$($tmp/local/bin/runnerctl version)" == "0.3.2" ]]
$tmp/local/bin/runnerctl agent --json | grep -q '"agent_ready": true'

DIST_DIR="$tmp/dist" bash "$ROOT/scripts/package-release.sh" >/dev/null
[[ -x "$tmp/dist/runnerctl" ]]
[[ -x "$tmp/dist/runnerctl-core" ]]
[[ -f "$tmp/dist/runnerctl.sha256" ]]
[[ -f "$tmp/dist/runnerctl-core.sha256" ]]
[[ -f "$tmp/dist/runnerctl-0.3.2.tar.gz" ]]

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp/dist" && sha256sum -c runnerctl.sha256 runnerctl-core.sha256 runnerctl-0.3.2.tar.gz.sha256 >/dev/null)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$tmp/dist" && shasum -a 256 -c runnerctl.sha256 runnerctl-core.sha256 runnerctl-0.3.2.tar.gz.sha256 >/dev/null)
fi

grep -q 'example-org/example-repo' "$ROOT/README.md"
grep -q 'example-org/example-repo' "$ROOT/README.zh-TW.md"
! grep -q 'Claire-s-English' "$ROOT/README.md"
! grep -q 'Claire-s-English' "$ROOT/README.zh-TW.md"

echo "smoke tests passed"
