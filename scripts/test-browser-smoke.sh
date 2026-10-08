#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"

DSH_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dsh-native-browser.XXXXXX")
DSH_SERVER_LOG="$DSH_TEST_ROOT/server.log"
DSH_NATIVE="_build/native/release/build/f4ah6o/dsh/native/native.exe"
if [ ! -x "$DSH_NATIVE" ]; then
  echo "Build the native runtime before browser smoke: missing $DSH_NATIVE" >&2
  rm -rf "$DSH_TEST_ROOT"
  exit 1
fi
mkdir -p "$DSH_TEST_ROOT/data" "$DSH_TEST_ROOT/workspace"

"$DSH_NATIVE" web \
  --demo \
  --data-dir "$DSH_TEST_ROOT/data" \
  --workspace "$DSH_TEST_ROOT/workspace" \
  --port 0 \
  >"$DSH_SERVER_LOG" 2>&1 &
DSH_SERVER_PID=$!
trap 'kill "$DSH_SERVER_PID" 2>/dev/null || true; wait "$DSH_SERVER_PID" 2>/dev/null || true; rm -rf "$DSH_TEST_ROOT"' EXIT HUP INT TERM

DSH_BROWSER_URL=
DSH_ATTEMPT=0
while [ "$DSH_ATTEMPT" -lt 100 ]; do
  DSH_BROWSER_URL=$(sed -n 's/^native service listening at \(http:\/\/127\.0\.0\.1:[0-9][0-9]*\)$/\1/p' "$DSH_SERVER_LOG" | head -n 1)
  if [ -n "$DSH_BROWSER_URL" ]; then
    break
  fi
  if ! kill -0 "$DSH_SERVER_PID" 2>/dev/null; then
    cat "$DSH_SERVER_LOG" >&2
    echo "Native browser fixture exited before it opened its port." >&2
    exit 1
  fi
  DSH_ATTEMPT=$((DSH_ATTEMPT + 1))
  sleep 0.1
done
if [ -z "$DSH_BROWSER_URL" ]; then
  cat "$DSH_SERVER_LOG" >&2
  echo "Native browser fixture did not report its loopback port." >&2
  exit 1
fi
export DSH_BROWSER_URL
node web/browser-smoke.mjs
