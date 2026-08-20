#!/usr/bin/env bash
set -euo pipefail

REPO="${RUNNERCTL_REPO:-AdemKao/runners-self-host-management}"
REF="${RUNNERCTL_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIBEXEC_DIR="$PREFIX/libexec/runnerctl"
SCRIPT_DIR=""
LOCAL_FRONTEND=""
LOCAL_CORE=""

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_FRONTEND="$SCRIPT_DIR/runnerctl"
  LOCAL_CORE="$SCRIPT_DIR/bin/runnerctl"
fi

info() { printf '[runnerctl-install] %s\n' "$*"; }
die() { printf '[runnerctl-install] ERROR: %s\n' "$*" >&2; exit 1; }

install_files() {
  local frontend="$1" core="$2"
  mkdir -p "$BIN_DIR" "$LIBEXEC_DIR"
  install -m 0755 "$frontend" "$BIN_DIR/runnerctl"
  install -m 0755 "$core" "$LIBEXEC_DIR/runnerctl-core"
  info "Installed runnerctl to $BIN_DIR/runnerctl"
  info "Installed runnerctl core to $LIBEXEC_DIR/runnerctl-core"
}

install_legacy_binary() {
  local source="$1"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$source" "$BIN_DIR/runnerctl"
  info "Installed legacy runnerctl to $BIN_DIR/runnerctl"
}

install_from_checkout() {
  [[ -n "$LOCAL_FRONTEND" && -f "$LOCAL_FRONTEND" && -f "$LOCAL_CORE" ]] || return 1
  info "Installing from local checkout"
  install_files "$LOCAL_FRONTEND" "$LOCAL_CORE"
}

verify_sha256() {
  local dir="$1" manifest="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum -c "$manifest")
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$dir" && shasum -a 256 -c "$manifest")
  else
    die "sha256sum or shasum is required to verify release artifacts"
  fi
}

install_from_release() {
  local version="$1" base tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/$REPO/releases/download/v$version"

  info "Downloading runnerctl v$version"
  curl -fsSL "$base/runnerctl" -o "$tmp/runnerctl"
  curl -fsSL "$base/runnerctl.sha256" -o "$tmp/runnerctl.sha256"
  verify_sha256 "$tmp" runnerctl.sha256

  if curl -fsSL "$base/runnerctl-core" -o "$tmp/runnerctl-core" 2>/dev/null; then
    curl -fsSL "$base/runnerctl-core.sha256" -o "$tmp/runnerctl-core.sha256"
    verify_sha256 "$tmp" runnerctl-core.sha256
    install_files "$tmp/runnerctl" "$tmp/runnerctl-core"
  else
    info "Release v$version uses the legacy single-file layout"
    install_legacy_binary "$tmp/runnerctl"
  fi
}

install_from_ref() {
  local tmp frontend_url core_url
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  frontend_url="https://raw.githubusercontent.com/$REPO/$REF/runnerctl"
  core_url="https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl"
  info "Installing from $REPO@$REF"
  curl -fsSL "$frontend_url" -o "$tmp/runnerctl"
  curl -fsSL "$core_url" -o "$tmp/runnerctl-core"
  install_files "$tmp/runnerctl" "$tmp/runnerctl-core"
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

  printf '\nNext:\n  runnerctl doctor\n  runnerctl agent\n'
}

main "$@"
