#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
VERSION="$(bash "$ROOT/runnerctl" version)"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin"

install -m 0755 "$ROOT/runnerctl" "$DIST_DIR/runnerctl"
install -m 0755 "$ROOT/runnerctl-base" "$DIST_DIR/runnerctl-base"
install -m 0755 "$ROOT/bin/runnerctl" "$DIST_DIR/runnerctl-core"
install -m 0755 "$ROOT/bin/runnerctl-cleanup" "$DIST_DIR/runnerctl-cleanup"
install -m 0755 "$ROOT/bin/runnerctl" "$DIST_DIR/bin/runnerctl"
install -m 0755 "$ROOT/bin/runnerctl-cleanup" "$DIST_DIR/bin/runnerctl-cleanup"

# Keep the source-compatible layout inside the tarball so the public dispatcher
# can resolve runnerctl-base and bin/runnerctl after extraction.
tar -czf "$DIST_DIR/runnerctl-${VERSION}.tar.gz" \
  -C "$DIST_DIR" runnerctl runnerctl-base bin/runnerctl bin/runnerctl-cleanup

checksum() {
  local file="$1" hash
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "sha256sum or shasum is required" >&2
    exit 1
  fi
  printf '%s  %s\n' "$hash" "$(basename "$file")"
}

for artifact in runnerctl runnerctl-base runnerctl-core runnerctl-cleanup "runnerctl-${VERSION}.tar.gz"; do
  checksum "$DIST_DIR/$artifact" > "$DIST_DIR/$artifact.sha256"
done

printf 'Created release artifacts in %s\n' "$DIST_DIR"
