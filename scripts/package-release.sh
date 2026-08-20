#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
VERSION="$(bash "$ROOT/bin/runnerctl" version)"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
install -m 0755 "$ROOT/bin/runnerctl" "$DIST_DIR/runnerctl"

tar -czf "$DIST_DIR/runnerctl-${VERSION}.tar.gz" -C "$DIST_DIR" runnerctl

checksum() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1 "  " FILENAME}' FILENAME="$(basename "$file")"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1 "  " FILENAME}' FILENAME="$(basename "$file")"
  else
    echo "sha256sum or shasum is required" >&2
    exit 1
  fi
}

(
  cd "$DIST_DIR"
  checksum "$DIST_DIR/runnerctl" > runnerctl.sha256
  checksum "$DIST_DIR/runnerctl-${VERSION}.tar.gz" > "runnerctl-${VERSION}.tar.gz.sha256"
)

printf 'Created release artifacts in %s\n' "$DIST_DIR"
