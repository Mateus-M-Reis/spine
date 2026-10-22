#!/usr/bin/env bash
# Runs the real-LÖVR smoke project. Requires a LÖVR binary (set LOVR_BIN) and
# an X display; xvfb-run is used automatically when available.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOVR_BIN="${LOVR_BIN:-lovr}"

if [ ! -x "$LOVR_BIN" ] && ! command -v "$LOVR_BIN" >/dev/null 2>&1; then
  echo "LOVR_BIN not found: $LOVR_BIN" >&2
  exit 2
fi

TMPDIR_SMOKE="$(mktemp -d)"
LOG="$TMPDIR_SMOKE/lovr.log"
cleanup() {
  rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

cp -R "$ROOT/spine" "$TMPDIR_SMOKE/"
cp "$ROOT/init.lua" "$TMPDIR_SMOKE/"
mkdir -p "$TMPDIR_SMOKE/assets"
cp -R "$ROOT/examples/basic_usage/assets/." "$TMPDIR_SMOKE/assets/"
cp "$ROOT/tests/lovr_smoke/conf.lua" "$TMPDIR_SMOKE/"
cp "$ROOT/tests/lovr_smoke/main.lua" "$TMPDIR_SMOKE/"

case "$LOVR_BIN" in
  *.AppImage) export APPIMAGE_EXTRACT_AND_RUN=1 ;;
esac

if command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
else
  RUNNER=()
fi

set +e
timeout 90 "${RUNNER[@]}" "$LOVR_BIN" "$TMPDIR_SMOKE" >"$LOG" 2>&1
STATUS=$?
set -e

cat "$LOG"

if ! grep -q "LOVR_SMOKE_OK" "$LOG"; then
  echo "LÖVR smoke test did not report LOVR_SMOKE_OK" >&2
  exit 1
fi
exit "$STATUS"
