#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
DSH_OUTPUT="$DSH_ROOT/runtime/bundled_web.mbt"
DSH_MODE=${1:-write}
DSH_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dsh-bundled-web.XXXXXX")
trap 'rm -rf "$DSH_TMP_DIR"' EXIT HUP INT TERM

case "$DSH_MODE" in
  write|--check) ;;
  *)
    echo "Usage: sh scripts/generate-bundled-web.sh [--check]" >&2
    exit 2
    ;;
esac

DSH_GENERATED="$DSH_TMP_DIR/bundled_web.mbt"
DSH_ASSET_LIST="$DSH_TMP_DIR/assets"
cat > "$DSH_ASSET_LIST" <<'ASSETS'
/index.html|web/index.html|index_html
/moonbit/browser.js|web/moonbit/browser.js|browser_js
/kumo-standalone.css|web/kumo-standalone.css|kumo_standalone_css
/yami-kumo-components.css|web/yami-kumo-components.css|yami_kumo_components_css
/yami-kumo-shell.css|web/yami-kumo-shell.css|yami_kumo_shell_css
/manifest.webmanifest|web/manifest.webmanifest|manifest_webmanifest
/icon.svg|web/icon.svg|icon_svg
/sw.js|web/sw.js|sw_js
ASSETS
cat > "$DSH_GENERATED" <<'MBT'
///|
/// Built browser assets embedded in every `dsh` executable.
/// Regenerate with `sh scripts/generate-bundled-web.sh` after building web assets.
fn native_embedded_web_asset(path : String) -> String? {
  match path {
MBT

while IFS='|' read -r DSH_URL DSH_FILE DSH_NAME; do
  [ -n "$DSH_URL" ] || continue
  DSH_SOURCE="$DSH_ROOT/$DSH_FILE"
  if [ ! -s "$DSH_SOURCE" ]; then
    echo "Cannot embed missing browser asset: $DSH_FILE" >&2
    exit 1
  fi
  {
    DSH_FUNCTION="native_embedded_web_$DSH_NAME"
    DSH_MATCH_LINE="    \"$DSH_URL\" => Some($DSH_FUNCTION())"
    if [ "${#DSH_MATCH_LINE}" -gt 80 ]; then
      printf '    "%s" =>\n      Some(%s())\n' "$DSH_URL" "$DSH_FUNCTION"
    else
      printf '%s\n' "$DSH_MATCH_LINE"
    fi
  } >> "$DSH_GENERATED"
done < "$DSH_ASSET_LIST"

cat >> "$DSH_GENERATED" <<'MBT'
    _ => None
  }
}
MBT

while IFS='|' read -r DSH_URL DSH_FILE DSH_NAME; do
  [ -n "$DSH_URL" ] || continue
  DSH_SOURCE="$DSH_ROOT/$DSH_FILE"
  if [ ! -s "$DSH_SOURCE" ]; then
    echo "Cannot embed missing browser asset: $DSH_FILE" >&2
    exit 1
  fi
  DSH_BASE64="$DSH_TMP_DIR/asset.base64"
  base64 < "$DSH_SOURCE" | tr -d '\r\n' > "$DSH_BASE64"
  {
    # shellcheck disable=SC2016 # Backticks are literal MoonBit doc-comment delimiters.
    printf '\n///|\n/// Embedded source for `%s`.\nfn native_embedded_web_%s() -> String {\n  let encoded = [\n' "$DSH_FILE" "$DSH_NAME"
    fold -w 96 "$DSH_BASE64" | while IFS= read -r DSH_CHUNK || [ -n "$DSH_CHUNK" ]; do
      printf '    "%s",\n' "$DSH_CHUNK"
    done
    printf '  ].join("")\n  @utf8.decode_lossy(@base64.decode_lossy(encoded))\n}\n'
  } >> "$DSH_GENERATED"
done < "$DSH_ASSET_LIST"

if [ "$DSH_MODE" = "--check" ]; then
  if ! cmp -s "$DSH_GENERATED" "$DSH_OUTPUT"; then
    echo "runtime/bundled_web.mbt is stale; run sh scripts/build.sh to refresh the embedded assets." >&2
    exit 1
  fi
  echo "Embedded browser bundle matches all built web assets."
else
  if ! cmp -s "$DSH_GENERATED" "$DSH_OUTPUT"; then
    mv "$DSH_GENERATED" "$DSH_OUTPUT"
  fi
  echo "Generated runtime/bundled_web.mbt from all built browser assets."
fi
