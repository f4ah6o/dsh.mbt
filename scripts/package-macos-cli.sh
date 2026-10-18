#!/bin/sh
set -eu
if [ "$(uname -s)" != Darwin ] || [ "$#" -ne 2 ]; then
  echo "usage (macOS): $0 APP_ARCHIVE.zip OUTPUT_CLI" >&2
  exit 2
fi
DSH_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"
case "$1" in /*) DSH_ARCHIVE=$1 ;; *) DSH_ARCHIVE="$DSH_ROOT/$1" ;; esac
case "$2" in /*) DSH_OUTPUT=$2 ;; *) DSH_OUTPUT="$DSH_ROOT/$2" ;; esac
DSH_PAYLOAD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-cli.XXXXXX")
trap 'rm -rf "$DSH_PAYLOAD_ROOT"' EXIT HUP INT TERM
DSH_VERSION=$(awk -F '"' '$1 ~ /^version = / {print $2; exit}' moon.mod)
python3 scripts/prepare-macos-desktop-payload.py --archive "$DSH_ARCHIVE" \
  --version "$DSH_VERSION" --output "$DSH_PAYLOAD_ROOT/app.payload"
# A fresh target dir prevents an environment-only payload change from reusing
# a previously linked CLI. The app archive carries the separate base helper.
MOON_CC="$DSH_ROOT/scripts/macos-cli-cc.py" MACOSX_DEPLOYMENT_TARGET=13.0 DSH_MACOS_DESKTOP_PAYLOAD="$DSH_PAYLOAD_ROOT/app.payload" \
  moon build cmd/dsh --target native --release --frozen --target-dir "$DSH_PAYLOAD_ROOT/build"
DSH_CLI="$DSH_PAYLOAD_ROOT/build/native/release/build/cmd/dsh/dsh.exe"
mkdir -p "$(dirname "$DSH_OUTPUT")"
cp "$DSH_CLI" "$DSH_PAYLOAD_ROOT/dsh"
chmod 755 "$DSH_PAYLOAD_ROOT/dsh"
# The Mach-O payload is part of the final signature; never append after signing.
codesign --force --sign - --timestamp=none "$DSH_PAYLOAD_ROOT/dsh"
codesign --verify --strict "$DSH_PAYLOAD_ROOT/dsh"
mv "$DSH_PAYLOAD_ROOT/dsh" "$DSH_OUTPUT"
echo "Packaged macOS CLI and embedded app: $DSH_OUTPUT"
