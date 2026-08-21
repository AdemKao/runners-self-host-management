#!/usr/bin/env bash
set -euo pipefail

REPO="${RUNNERCTL_REPO:-AdemKao/runners-self-host-management}"
REF="${RUNNERCTL_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIBEXEC_DIR="$PREFIX/libexec/runnerctl"
SCRIPT_DIR=""
LOCAL_FRONTEND=""
LOCAL_BASE=""
LOCAL_CORE=""
LOCAL_CLEANUP=""
LOCAL_HOST=""

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_FRONTEND="$SCRIPT_DIR/runnerctl"
  LOCAL_BASE="$SCRIPT_DIR/runnerctl-base"
  LOCAL_CORE="$SCRIPT_DIR/bin/runnerctl"
  LOCAL_CLEANUP="$SCRIPT_DIR/bin/runnerctl-cleanup"
  LOCAL_HOST="$SCRIPT_DIR/bin/runnerctl-host"
fi

info() { printf '[runnerctl-install] %s\n' "$*"; }
die() { printf '[runnerctl-install] ERROR: %s\n' "$*" >&2; exit 1; }

install_files() {
  local frontend="$1" base="$2" core="$3" cleanup="$4" host="${5:-}"
  mkdir -p "$BIN_DIR" "$LIBEXEC_DIR"
  install -m 0755 "$frontend" "$BIN_DIR/runnerctl"
  install -m 0755 "$base" "$LIBEXEC_DIR/runnerctl-base"
  install -m 0755 "$core" "$LIBEXEC_DIR/runnerctl-core"
  install -m 0755 "$cleanup" "$LIBEXEC_DIR/runnerctl-cleanup"
  if [[ -n "$host" && -f "$host" ]]; then
    install -m 0755 "$host" "$LIBEXEC_DIR/runnerctl-host"
  fi
  info "Installed runnerctl to $BIN_DIR/runnerctl"
}

install_legacy_pair() {
  local frontend="$1" core="$2"
  mkdir -p "$BIN_DIR" "$LIBEXEC_DIR"
  install -m 0755 "$frontend" "$BIN_DIR/runnerctl"
  install -m 0755 "$core" "$LIBEXEC_DIR/runnerctl-core"
}

install_legacy_binary() {
  local source="$1"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$source" "$BIN_DIR/runnerctl"
}

install_from_checkout() {
  [[ -f "$LOCAL_FRONTEND" && -f "$LOCAL_BASE" && -f "$LOCAL_CORE" && -f "$LOCAL_CLEANUP" && -f "$LOCAL_HOST" ]] || return 1
  info "Installing from local checkout"
  install_files "$LOCAL_FRONTEND" "$LOCAL_BASE" "$LOCAL_CORE" "$LOCAL_CLEANUP" "$LOCAL_HOST"
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

download_verified() {
  local base="$1" name="$2" tmp="$3"
  curl -fsSL "$base/$name" -o "$tmp/$name"
  curl -fsSL "$base/$name.sha256" -o "$tmp/$name.sha256"
  verify_sha256 "$tmp" "$name.sha256"
}

install_from_release() {
  local version="$1" base tmp host=""
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/$REPO/releases/download/v$version"

  info "Downloading runnerctl v$version"
  download_verified "$base" runnerctl "$tmp"

  if curl -fsSL "$base/runnerctl-core" -o "$tmp/runnerctl-core" 2>/dev/null; then
    curl -fsSL "$base/runnerctl-core.sha256" -o "$tmp/runnerctl-core.sha256"
    verify_sha256 "$tmp" runnerctl-core.sha256

    if curl -fsSL "$base/runnerctl-base" -o "$tmp/runnerctl-base" 2>/dev/null && \
       curl -fsSL "$base/runnerctl-cleanup" -o "$tmp/runnerctl-cleanup" 2>/dev/null; then
      curl -fsSL "$base/runnerctl-base.sha256" -o "$tmp/runnerctl-base.sha256"
      curl -fsSL "$base/runnerctl-cleanup.sha256" -o "$tmp/runnerctl-cleanup.sha256"
      verify_sha256 "$tmp" runnerctl-base.sha256
      verify_sha256 "$tmp" runnerctl-cleanup.sha256

      if curl -fsSL "$base/runnerctl-host" -o "$tmp/runnerctl-host" 2>/dev/null; then
        curl -fsSL "$base/runnerctl-host.sha256" -o "$tmp/runnerctl-host.sha256"
        verify_sha256 "$tmp" runnerctl-host.sha256
        host="$tmp/runnerctl-host"
      fi
      install_files "$tmp/runnerctl" "$tmp/runnerctl-base" "$tmp/runnerctl-core" "$tmp/runnerctl-cleanup" "$host"
    else
      info "Release v$version uses the pre-cleanup frontend/core layout"
      install_legacy_pair "$tmp/runnerctl" "$tmp/runnerctl-core"
    fi
  else
    info "Release v$version uses the legacy single-file layout"
    install_legacy_binary "$tmp/runnerctl"
  fi
}

install_from_ref() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  info "Installing from $REPO@$REF"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/runnerctl" -o "$tmp/runnerctl"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/runnerctl-base" -o "$tmp/runnerctl-base"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl" -o "$tmp/runnerctl-core"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-cleanup" -o "$tmp/runnerctl-cleanup"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-host" -o "$tmp/runnerctl-host"
  install_files "$tmp/runnerctl" "$tmp/runnerctl-base" "$tmp/runnerctl-core" "$tmp/runnerctl-cleanup" "$tmp/runnerctl-host"
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
    *) printf '\nAdd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
  esac

  printf '\nNext:\n  runnerctl doctor\n  runnerctl host inspect\n  runnerctl cleanup status\n'
}

main "$@"
