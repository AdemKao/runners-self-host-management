#!/usr/bin/env bash
set -euo pipefail

REPO="${RUNNERCTL_REPO:-AdemKao/runners-self-host-management}"
REF="${RUNNERCTL_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
SCRIPT_DIR=""
LOCAL_SOURCE=""

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_SOURCE="$SCRIPT_DIR/bin/runnerctl"
fi

info() { printf '[runnerctl-install] %s\n' "$*"; }
die() { printf '[runnerctl-install] ERROR: %s\n' "$*" >&2; exit 1; }

install_binary() {
  local source="$1"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$source" "$BIN_DIR/runnerctl"
  info "Installed runnerctl to $BIN_DIR/runnerctl"
}

install_from_checkout() {
  [[ -n "$LOCAL_SOURCE" && -f "$LOCAL_SOURCE" ]] || return 1
  info "Installing from local checkout"
  install_binary "$LOCAL_SOURCE"
}

install_from_release() {
  local version="$1" base tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/$REPO/releases/download/v$version"

  info "Downloading runnerctl v$version"
  curl -fsSL "$base/runnerctl" -o "$tmp/runnerctl"
  curl -fsSL "$base/runnerctl.sha256" -o "$tmp/runnerctl.sha256"

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp" && sha256sum -c runnerctl.sha256)
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$tmp" && shasum -a 256 -c runnerctl.sha256)
  else
    die "sha256sum or shasum is required to verify release artifacts"
  fi

  install_binary "$tmp/runnerctl"
}

install_from_ref() {
  local tmp url
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  url="https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl"
  info "Installing from $REPO@$REF"
  curl -fsSL "$url" -o "$tmp/runnerctl"
  install_binary "$tmp/runnerctl"
}

main() {
  command -v install >/dev/null 2>&1 || die "install command is required"

  if install_from_checkout; then
    :
  elif [[ -n "${RUNNERCTL_VERSION:-}" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required"
    install_from_release "$RUNNERCTL_VERSION"
  else
    command -v curl >/dev/null 2>&1 || die "curl is required"
    install_from_ref
  fi

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      printf '\nAdd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$BIN_DIR"
      ;;
  esac

  printf '\nNext:\n  runnerctl doctor\n'
}

main "$@"
