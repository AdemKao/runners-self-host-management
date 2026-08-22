#!/usr/bin/env bash
set -euo pipefail
REPO="${RUNNERCTL_REPO:-AdemKao/runners-self-host-management}"
REF="${RUNNERCTL_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local}"
LIBEXEC_DIR="$PREFIX/libexec/runnerctl"
SCRIPT_DIR=""
TMP_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
info(){ printf '[runnerctl-install] %s\n' "$*"; }
die(){ printf '[runnerctl-install] ERROR: %s\n' "$*" >&2; exit 1; }
cleanup(){ [[ -z "${TMP_DIR:-}" ]] || rm -rf -- "$TMP_DIR"; TMP_DIR=""; }
trap cleanup EXIT
verify_sha256(){ local dir="$1" manifest="$2"; if command -v sha256sum >/dev/null 2>&1; then (cd "$dir" && sha256sum -c "$manifest"); elif command -v shasum >/dev/null 2>&1; then (cd "$dir" && shasum -a 256 -c "$manifest"); else die "sha256sum or shasum is required to verify release artifacts"; fi; }
download_verified(){ local base="$1" name="$2" tmp="$3"; curl -fsSL "$base/$name" -o "$tmp/$name"; curl -fsSL "$base/$name.sha256" -o "$tmp/$name.sha256"; verify_sha256 "$tmp" "$name.sha256"; }
install_extra(){ local source="$1" name="$2"; [[ -f "$source" ]] || die "missing v0.5 component: $source"; mkdir -p "$LIBEXEC_DIR"; install -m 0755 "$source" "$LIBEXEC_DIR/$name"; }
local_checkout_ready(){ [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/install-legacy.sh" && -f "$SCRIPT_DIR/runnerctl-base-legacy" && -f "$SCRIPT_DIR/bin/runnerctl-legacy" && -f "$SCRIPT_DIR/bin/runnerctl-queue-legacy" && -f "$SCRIPT_DIR/bin/runnerctl-scheduler" && -f "$SCRIPT_DIR/bin/runnerctl-scheduler-core" ]]; }
fetch_legacy_installer(){
  local target="$1"
  if local_checkout_ready; then printf '%s' "$SCRIPT_DIR/install-legacy.sh"; return; fi
  command -v curl >/dev/null 2>&1 || die "curl is required"
  if [[ -n "${RUNNERCTL_VERSION:-}" ]]; then curl -fsSL "https://raw.githubusercontent.com/$REPO/v${RUNNERCTL_VERSION}/install-legacy.sh" -o "$target"; else curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/install-legacy.sh" -o "$target"; fi
  printf '%s' "$target"
}
install_v05_components(){
  local tmp="$1" base
  if local_checkout_ready; then
    install_extra "$SCRIPT_DIR/runnerctl-base-legacy" runnerctl-base-legacy
    install_extra "$SCRIPT_DIR/bin/runnerctl-legacy" runnerctl-core-legacy
    install_extra "$SCRIPT_DIR/bin/runnerctl-queue-legacy" runnerctl-queue-legacy
    install_extra "$SCRIPT_DIR/bin/runnerctl-scheduler" runnerctl-scheduler
    install_extra "$SCRIPT_DIR/bin/runnerctl-scheduler-core" runnerctl-scheduler-core
    return
  fi
  if [[ -n "${RUNNERCTL_VERSION:-}" ]]; then
    base="https://github.com/$REPO/releases/download/v${RUNNERCTL_VERSION}"
    for name in runnerctl-base-legacy runnerctl-core-legacy runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core; do download_verified "$base" "$name" "$tmp"; install_extra "$tmp/$name" "$name"; done
  else
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/runnerctl-base-legacy" -o "$tmp/runnerctl-base-legacy"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-legacy" -o "$tmp/runnerctl-core-legacy"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-queue-legacy" -o "$tmp/runnerctl-queue-legacy"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-scheduler" -o "$tmp/runnerctl-scheduler"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-scheduler-core" -o "$tmp/runnerctl-scheduler-core"
    for name in runnerctl-base-legacy runnerctl-core-legacy runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core; do install_extra "$tmp/$name" "$name"; done
  fi
}
main(){
  command -v install >/dev/null 2>&1 || die "install command is required"
  TMP_DIR="$(mktemp -d)"
  local legacy
  legacy="$(fetch_legacy_installer "$TMP_DIR/install-legacy.sh")"
  RUNNERCTL_REPO="$REPO" RUNNERCTL_REF="$REF" RUNNERCTL_VERSION="${RUNNERCTL_VERSION:-}" PREFIX="$PREFIX" bash "$legacy"
  install_v05_components "$TMP_DIR"
  cleanup
  info "Installed v0.5 scheduler components to $LIBEXEC_DIR"
  printf '\nScheduler migration:\n  1. runnerctl queue disable      # if legacy gate is enabled\n  2. add runnerctl-scheduled to scheduled jobs runs-on labels\n  3. runnerctl scheduler enable --max-concurrency 1\n  4. runnerctl scheduler status\n'
}
main "$@"
