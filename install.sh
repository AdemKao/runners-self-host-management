#!/usr/bin/env bash
set -euo pipefail

REPO="${RUNNERCTL_REPO:-AdemKao/runners-self-host-management}"
REF="${RUNNERCTL_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIBEXEC_DIR="$PREFIX/libexec/runnerctl"
LIBEXEC_BIN_DIR="$LIBEXEC_DIR/bin"
SCRIPT_DIR=""
LOCAL_FRONTEND=""
LOCAL_BASE=""
LOCAL_CORE=""
LOCAL_CLEANUP=""
LOCAL_HOST=""
LOCAL_CI=""
LOCAL_HOOKS=""
LOCAL_QUEUE=""
INSTALL_TMP_DIR=""

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_FRONTEND="$SCRIPT_DIR/runnerctl"
  LOCAL_BASE="$SCRIPT_DIR/runnerctl-base"
  LOCAL_CORE="$SCRIPT_DIR/bin/runnerctl"
  LOCAL_CLEANUP="$SCRIPT_DIR/bin/runnerctl-cleanup"
  LOCAL_HOST="$SCRIPT_DIR/bin/runnerctl-host"
  LOCAL_CI="$SCRIPT_DIR/bin/runnerctl-ci"
  LOCAL_HOOKS="$SCRIPT_DIR/bin/runnerctl-hooks"
  LOCAL_QUEUE="$SCRIPT_DIR/bin/runnerctl-queue"
fi

info() { printf '[runnerctl-install] %s\n' "$*"; }
die() { printf '[runnerctl-install] ERROR: %s\n' "$*" >&2; exit 1; }

cleanup_install_tmp() {
  if [[ -n "${INSTALL_TMP_DIR:-}" ]]; then
    rm -rf -- "$INSTALL_TMP_DIR"
    INSTALL_TMP_DIR=""
  fi
}
trap cleanup_install_tmp EXIT

install_helper() {
  local source="$1" name="$2"
  [[ -f "$source" ]] || return 0
  install -m 0755 "$source" "$LIBEXEC_DIR/$name"
  install -m 0755 "$source" "$LIBEXEC_BIN_DIR/$name"
}

install_files() {
  local frontend="$1" base="$2" core="$3" cleanup="$4" host="${5:-}" ci="${6:-}" hooks="${7:-}" queue="${8:-}"
  mkdir -p "$BIN_DIR" "$LIBEXEC_DIR" "$LIBEXEC_BIN_DIR"
  install -m 0755 "$frontend" "$BIN_DIR/runnerctl"
  install -m 0755 "$base" "$LIBEXEC_DIR/runnerctl-base"
  install -m 0755 "$core" "$LIBEXEC_DIR/runnerctl-core"
  install -m 0755 "$cleanup" "$LIBEXEC_DIR/runnerctl-cleanup"

  # Keep the historical flattened helper paths while also preserving the source
  # layout expected by runnerctl-base ($SCRIPT_DIR/bin/runnerctl-*).
  [[ -z "$host" ]] || install_helper "$host" runnerctl-host
  [[ -z "$ci" ]] || install_helper "$ci" runnerctl-ci
  [[ -z "$hooks" ]] || install_helper "$hooks" runnerctl-hooks
  [[ -z "$queue" ]] || install_helper "$queue" runnerctl-queue

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
  [[ -f "$LOCAL_FRONTEND" && -f "$LOCAL_BASE" && -f "$LOCAL_CORE" && -f "$LOCAL_CLEANUP" && -f "$LOCAL_HOST" && -f "$LOCAL_CI" && -f "$LOCAL_HOOKS" && -f "$LOCAL_QUEUE" ]] || return 1
  info "Installing from local checkout"
  install_files "$LOCAL_FRONTEND" "$LOCAL_BASE" "$LOCAL_CORE" "$LOCAL_CLEANUP" "$LOCAL_HOST" "$LOCAL_CI" "$LOCAL_HOOKS" "$LOCAL_QUEUE"
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
  local version="$1" base tmp host="" ci="" hooks="" queue=""
  tmp="$(mktemp -d)"
  INSTALL_TMP_DIR="$tmp"
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
        curl -fsSL "$base/runnerctl-host.sha256" -o "$tmp/runnerctl-host.sha256"; verify_sha256 "$tmp" runnerctl-host.sha256; host="$tmp/runnerctl-host"
      fi
      if curl -fsSL "$base/runnerctl-ci" -o "$tmp/runnerctl-ci" 2>/dev/null; then
        curl -fsSL "$base/runnerctl-ci.sha256" -o "$tmp/runnerctl-ci.sha256"; verify_sha256 "$tmp" runnerctl-ci.sha256; ci="$tmp/runnerctl-ci"
      fi
      if curl -fsSL "$base/runnerctl-hooks" -o "$tmp/runnerctl-hooks" 2>/dev/null; then
        curl -fsSL "$base/runnerctl-hooks.sha256" -o "$tmp/runnerctl-hooks.sha256"; verify_sha256 "$tmp" runnerctl-hooks.sha256; hooks="$tmp/runnerctl-hooks"
      fi
      if curl -fsSL "$base/runnerctl-queue" -o "$tmp/runnerctl-queue" 2>/dev/null; then
        curl -fsSL "$base/runnerctl-queue.sha256" -o "$tmp/runnerctl-queue.sha256"; verify_sha256 "$tmp" runnerctl-queue.sha256; queue="$tmp/runnerctl-queue"
      fi
      install_files "$tmp/runnerctl" "$tmp/runnerctl-base" "$tmp/runnerctl-core" "$tmp/runnerctl-cleanup" "$host" "$ci" "$hooks" "$queue"
    else
      info "Release v$version uses the pre-cleanup frontend/core layout"
      install_legacy_pair "$tmp/runnerctl" "$tmp/runnerctl-core"
    fi
  else
    info "Release v$version uses the legacy single-file layout"
    install_legacy_binary "$tmp/runnerctl"
  fi

  cleanup_install_tmp
}

install_from_ref() {
  local tmp
  tmp="$(mktemp -d)"
  INSTALL_TMP_DIR="$tmp"
  info "Installing from $REPO@$REF"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/runnerctl" -o "$tmp/runnerctl"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/runnerctl-base" -o "$tmp/runnerctl-base"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl" -o "$tmp/runnerctl-core"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-cleanup" -o "$tmp/runnerctl-cleanup"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-host" -o "$tmp/runnerctl-host"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-ci" -o "$tmp/runnerctl-ci"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-hooks" -o "$tmp/runnerctl-hooks"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/runnerctl-queue" -o "$tmp/runnerctl-queue"
  install_files "$tmp/runnerctl" "$tmp/runnerctl-base" "$tmp/runnerctl-core" "$tmp/runnerctl-cleanup" "$tmp/runnerctl-host" "$tmp/runnerctl-ci" "$tmp/runnerctl-hooks" "$tmp/runnerctl-queue"
  cleanup_install_tmp
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

  printf '\nNext:\n  runnerctl doctor\n  runnerctl host inspect\n  runnerctl capacity\n  runnerctl queue status\n  runnerctl ci check OWNER/REPO --current-host\n  runnerctl cleanup status\n'
}

main "$@"
