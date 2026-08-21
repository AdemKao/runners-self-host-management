#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
VERSION="$(bash "$ROOT/runnerctl" version)"
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR/bin"
install -m 0755 "$ROOT/runnerctl" "$DIST_DIR/runnerctl"
install -m 0755 "$ROOT/runnerctl-base" "$DIST_DIR/runnerctl-base"
install -m 0755 "$ROOT/runnerctl-base-legacy" "$DIST_DIR/runnerctl-base-legacy"
install -m 0755 "$ROOT/bin/runnerctl" "$DIST_DIR/runnerctl-core"
install -m 0755 "$ROOT/bin/runnerctl-legacy" "$DIST_DIR/runnerctl-core-legacy"
install -m 0755 "$ROOT/bin/runnerctl-cleanup" "$DIST_DIR/runnerctl-cleanup"
install -m 0755 "$ROOT/bin/runnerctl-host" "$DIST_DIR/runnerctl-host"
install -m 0755 "$ROOT/bin/runnerctl-ci" "$DIST_DIR/runnerctl-ci"
install -m 0755 "$ROOT/bin/runnerctl-hooks" "$DIST_DIR/runnerctl-hooks"
install -m 0755 "$ROOT/bin/runnerctl-queue" "$DIST_DIR/runnerctl-queue"
install -m 0755 "$ROOT/bin/runnerctl-queue-legacy" "$DIST_DIR/runnerctl-queue-legacy"
install -m 0755 "$ROOT/bin/runnerctl-scheduler" "$DIST_DIR/runnerctl-scheduler"
install -m 0755 "$ROOT/bin/runnerctl-scheduler-core" "$DIST_DIR/runnerctl-scheduler-core"
for f in runnerctl runnerctl-cleanup runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core; do src="$ROOT/bin/$f"; [[ "$f" == runnerctl ]] && src="$ROOT/bin/runnerctl"; [[ -f "$src" ]] && install -m 0755 "$src" "$DIST_DIR/bin/$f"; done
# Source-compatible tarball plus legacy implementation files used by v0.5 wrappers.
tar -czf "$DIST_DIR/runnerctl-${VERSION}.tar.gz" -C "$ROOT" \
  runnerctl runnerctl-base runnerctl-base-legacy \
  bin/runnerctl bin/runnerctl-legacy bin/runnerctl-cleanup bin/runnerctl-host bin/runnerctl-ci bin/runnerctl-hooks \
  bin/runnerctl-queue bin/runnerctl-queue-legacy bin/runnerctl-scheduler bin/runnerctl-scheduler-core \
  install.sh install-legacy.sh
checksum(){ local file="$1" hash; if command -v sha256sum >/dev/null 2>&1; then hash="$(sha256sum "$file" | awk '{print $1}')"; elif command -v shasum >/dev/null 2>&1; then hash="$(shasum -a 256 "$file" | awk '{print $1}')"; else echo "sha256sum or shasum is required" >&2; exit 1; fi; printf '%s  %s\n' "$hash" "$(basename "$file")"; }
for artifact in runnerctl runnerctl-base runnerctl-base-legacy runnerctl-core runnerctl-core-legacy runnerctl-cleanup runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core "runnerctl-${VERSION}.tar.gz"; do checksum "$DIST_DIR/$artifact" >"$DIST_DIR/$artifact.sha256"; done
printf 'Created release artifacts in %s\n' "$DIST_DIR"
