#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 PATH_TO_DSH_BINARY" >&2
  exit 2
fi

DSH_BINARY=$1
case "$DSH_BINARY" in
  /*) ;;
  *) DSH_BINARY="$(pwd)/$DSH_BINARY" ;;
esac
if [ ! -x "$DSH_BINARY" ]; then
  echo "dsh binary is missing or not executable: $DSH_BINARY" >&2
  exit 1
fi
unset GPUI_MACOS_LIBRARY DSH_NATIVE_WORKER_BIN

SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dsh-release-cli.XXXXXX")
SMOKE_LOG="$SMOKE_ROOT/server.log"
mkdir -p "$SMOKE_ROOT/cwd" "$SMOKE_ROOT/data" "$SMOKE_ROOT/workspace"
DSH_SERVER_PID=
cleanup() {
  if [ -n "$DSH_SERVER_PID" ]; then
    kill "$DSH_SERVER_PID" 2>/dev/null || true
    wait "$DSH_SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT HUP INT TERM

cd "$SMOKE_ROOT/cwd"
"$DSH_BINARY" web \
  --demo \
  --data-dir "$SMOKE_ROOT/data" \
  --workspace "$SMOKE_ROOT/workspace" \
  --port 0 \
  >"$SMOKE_LOG" 2>&1 &
DSH_SERVER_PID=$!

DSH_BROWSER_URL=
DSH_ATTEMPT=0
while [ "$DSH_ATTEMPT" -lt 100 ]; do
  DSH_BROWSER_URL=$(sed -n 's/^native service listening at \(http:\/\/127\.0\.0\.1:[0-9][0-9]*\)$/\1/p' "$SMOKE_LOG" | head -n 1)
  if [ -n "$DSH_BROWSER_URL" ]; then
    break
  fi
  if ! kill -0 "$DSH_SERVER_PID" 2>/dev/null; then
    cat "$SMOKE_LOG" >&2
    echo "Packaged dsh exited before opening its loopback service." >&2
    exit 1
  fi
  DSH_ATTEMPT=$((DSH_ATTEMPT + 1))
  sleep 0.1
done
if [ -z "$DSH_BROWSER_URL" ]; then
  cat "$SMOKE_LOG" >&2
  echo "Packaged dsh did not report its loopback port." >&2
  exit 1
fi

curl --fail --silent --show-error "$DSH_BROWSER_URL/" > "$SMOKE_ROOT/index.html"
grep -Fq '<title>dsh.mbt — エージェントのワークスペース</title>' "$SMOKE_ROOT/index.html"
grep -Fq 'src="/moonbit/browser.js"' "$SMOKE_ROOT/index.html"
curl --fail --silent --show-error \
  --dump-header "$SMOKE_ROOT/browser.headers" \
  "$DSH_BROWSER_URL/moonbit/browser.js" > "$SMOKE_ROOT/browser.js"
grep -Eiq '^Content-Type: text/javascript(;|[[:space:]])' "$SMOKE_ROOT/browser.headers"
test "$(wc -c < "$SMOKE_ROOT/browser.js" | tr -d ' ')" -gt 1024
for asset in kumo-standalone.css yami-kumo-components.css yami-kumo-shell.css; do
  curl --fail --silent --show-error \
    "$DSH_BROWSER_URL/$asset" > "$SMOKE_ROOT/$asset"
  test "$(wc -c < "$SMOKE_ROOT/$asset" | tr -d ' ')" -gt 256
done

echo "Packaged dsh served its embedded browser document, MoonBit JavaScript, and styles outside the checkout."
