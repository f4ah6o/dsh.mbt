#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
install_root=$(mktemp -d "${TMPDIR:-/tmp}/dsh-install-smoke.XXXXXX")
install_bin="$install_root/bin"
outside_root="$install_root/outside"
web_cwd="$install_root/installed-web-cwd"
installed_web_pid=
cleanup() {
  if [ -n "$installed_web_pid" ]; then
    kill "$installed_web_pid" 2>/dev/null || true
    wait "$installed_web_pid" 2>/dev/null || true
  fi
  rm -rf "$install_root"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$install_bin" "$outside_root"
mkdir -p "$install_root/workspace" "$install_root/mcp-workspace" \
  "$install_root/demo-workspace" "$web_cwd"

start_installed_web() {
  server_name=$1
  asset_override=${2:-}
  server_log="$install_root/$server_name.log"
  server_data="$install_root/$server_name-data"
  server_workspace="$install_root/$server_name-workspace"
  mkdir -p "$server_data" "$server_workspace"
  if [ -n "$asset_override" ]; then
    (
      cd "$web_cwd"
      unset DSH_NATIVE_WORKER_BIN
      PATH="$install_bin:/usr/bin:/bin"
      export PATH
      dsh web --demo --data-dir "$server_data" --workspace "$server_workspace" \
        --assets-dir "$asset_override" --port 0
    ) > "$server_log" 2>&1 &
  else
    (
      cd "$web_cwd"
      unset DSH_NATIVE_WORKER_BIN
      PATH="$install_bin:/usr/bin:/bin"
      export PATH
      dsh web --demo --data-dir "$server_data" --workspace "$server_workspace" --port 0
    ) > "$server_log" 2>&1 &
  fi
  installed_web_pid=$!
  server_url=
  attempt=0
  while [ "$attempt" -lt 100 ]; do
    server_url=$(sed -n 's/^native service listening at \(http:\/\/127\.0\.0\.1:[0-9][0-9]*\)$/\1/p' \
      "$server_log" | head -n 1)
    if [ -n "$server_url" ]; then
      break
    fi
    if ! kill -0 "$installed_web_pid" 2>/dev/null; then
      cat "$server_log" >&2
      echo "Installed dsh web service exited before it opened its port." >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.1
  done
  if [ -z "$server_url" ]; then
    cat "$server_log" >&2
    echo "Installed dsh web service did not report its loopback port." >&2
    exit 1
  fi
}

stop_installed_web() {
  kill "$installed_web_pid" 2>/dev/null || true
  wait "$installed_web_pid" 2>/dev/null || true
  installed_web_pid=
}

verify_installed_web_assets() {
  asset_base_url=$1
  asset_headers="$install_root/asset-headers.txt"
  asset_response="$install_root/asset-response"
  while IFS='|' read -r asset_url asset_file asset_type; do
    [ -n "$asset_url" ] || continue
    curl -fsS -D "$asset_headers" -o "$asset_response" \
      "$asset_base_url$asset_url"
    if ! cmp -s "$DSH_ROOT/$asset_file" "$asset_response"; then
      echo "Installed dsh served unexpected bytes for $asset_url." >&2
      exit 1
    fi
    if ! grep -qi "^Content-Type: $asset_type" "$asset_headers"; then
      echo "Installed dsh returned the wrong content type for $asset_url." >&2
      exit 1
    fi
    if ! grep -qi "^Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self';" \
      "$asset_headers"; then
      echo "Installed dsh omitted the strict content security policy for $asset_url." >&2
      exit 1
    fi
    if grep -qi 'unsafe-inline' "$asset_headers" ||
      grep -qi 'unsafe-eval' "$asset_headers"; then
      echo "Installed dsh weakened the content security policy for $asset_url." >&2
      exit 1
    fi
  done <<'ASSETS'
/|web/index.html|text/html
/index.html|web/index.html|text/html
/moonbit/browser.js|web/moonbit/browser.js|text/javascript
/kumo-standalone.css|web/kumo-standalone.css|text/css
/yami-kumo-components.css|web/yami-kumo-components.css|text/css
/yami-kumo-shell.css|web/yami-kumo-shell.css|text/css
/manifest.webmanifest|web/manifest.webmanifest|application/manifest+json
/icon.svg|web/icon.svg|image/svg+xml
/sw.js|web/sw.js|text/javascript
ASSETS
  curl -fsS "$asset_base_url/api/metadata" > "$install_root/web-metadata.json"
  grep -q '"ok":true' "$install_root/web-metadata.json"
}

cd "$DSH_ROOT"
moon install ./cmd/dsh --bin "$install_bin"
cat > "$outside_root/dsh" <<'SH'
#!/bin/sh
echo "working-directory dsh decoy was launched" >&2
exit 91
SH
chmod 755 "$outside_root/dsh"
(
  cd "$outside_root"
  unset DSH_NATIVE_WORKER_BIN
  PATH="$install_bin:/usr/bin:/bin"
  export PATH
  dsh --help
  dsh --auth-status --data-dir "$install_root/data" \
    --workspace "$install_root/workspace" --json > "$install_root/auth-status.json"
  grep -q '"state"' "$install_root/auth-status.json"
  dsh --demo --data-dir "$install_root/demo-data" \
    --workspace "$install_root/demo-workspace" > "$install_root/demo-output.txt"
  grep -q 'native runtime demo passed' "$install_root/demo-output.txt"
  test "$(cat "$install_root/demo-workspace/native-demo.txt")" = \
    "durable native tool result"
  if [ "$(uname -s)" = Linux ] &&
    grep -q 'grep unsupported on this host' "$install_root/demo-output.txt"; then
    echo "Linux demo skipped the installed worker-process check." >&2
    exit 1
  fi
  printf '%s\n' '{"jsonrpc":"2.0","id":"install-smoke","method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}},"name":"session_list","arguments":{}}}' |
    dsh mcp --data-dir "$install_root/mcp-data" \
      --workspace "$install_root/mcp-workspace" --demo > "$install_root/mcp-response.json"
  grep -q '"id":"install-smoke"' "$install_root/mcp-response.json"
  grep -q '"result":' "$install_root/mcp-response.json"
  grep -q '"isError":false' "$install_root/mcp-response.json"
  if grep -q '"error":' "$install_root/mcp-response.json"; then
    echo "MCP source-install smoke returned a JSON-RPC error." >&2
    exit 1
  fi
)
start_installed_web "embedded-web"
verify_installed_web_assets "$server_url"
stop_installed_web

override_assets="$install_root/override-web"
mkdir -p "$override_assets"
cp -R "$DSH_ROOT/web/." "$override_assets/"
sed 's/<title>dsh.mbt/<title>Override dsh.mbt/' \
  "$DSH_ROOT/web/index.html" > "$override_assets/index.html"
start_installed_web "override-web" "$override_assets"
curl -fsS "$server_url/" > "$install_root/override-index.html"
cmp "$override_assets/index.html" "$install_root/override-index.html"
grep -q '<title>Override dsh.mbt' "$install_root/override-index.html"
stop_installed_web

echo "Moon CLI PATH install, terminal, MCP, demo, embedded web, and --assets-dir checks passed outside the checkout."
