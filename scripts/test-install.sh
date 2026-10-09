#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
install_root=$(mktemp -d "${TMPDIR:-/tmp}/dsh-install-smoke.XXXXXX")
trap 'rm -rf "$install_root"' EXIT HUP INT TERM
install_bin="$install_root/bin"
outside_root="$install_root/outside"
mkdir -p "$install_bin" "$outside_root"
mkdir -p "$install_root/workspace" "$install_root/mcp-workspace"

cd "$DSH_ROOT"
moon install ./cmd/dsh --bin "$install_bin"
(
  cd "$outside_root"
  "$install_bin/dsh" --help
  "$install_bin/dsh" --auth-status --data-dir "$install_root/data" \
    --workspace "$install_root/workspace" --json > "$install_root/auth-status.json"
  grep -q '"state"' "$install_root/auth-status.json"
  printf '%s\n' '{"jsonrpc":"2.0","id":"install-smoke","method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}},"name":"session_list","arguments":{}}}' |
    "$install_bin/dsh" mcp --data-dir "$install_root/mcp-data" \
      --workspace "$install_root/mcp-workspace" --demo > "$install_root/mcp-response.json"
  grep -q '"id":"install-smoke"' "$install_root/mcp-response.json"
  grep -q '"result":' "$install_root/mcp-response.json"
  grep -q '"isError":false' "$install_root/mcp-response.json"
  if grep -q '"error":' "$install_root/mcp-response.json"; then
    echo "MCP source-install smoke returned a JSON-RPC error." >&2
    exit 1
  fi
)
echo "Moon CLI source install, terminal, and MCP checks passed outside the checkout."
