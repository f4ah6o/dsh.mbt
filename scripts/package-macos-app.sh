#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo "The macOS app packager must run on macOS." >&2
  exit 1
fi
if [ "$#" -ne 2 ]; then
  echo "usage: $0 PATH_TO_APP_BUNDLE PATH_TO_ARCHIVE.zip" >&2
  exit 2
fi

DSH_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
DSH_APP=$1
DSH_ARCHIVE=$2
case "$DSH_APP" in
  /*) ;;
  *) DSH_APP="$DSH_ROOT/$DSH_APP" ;;
esac
case "$DSH_ARCHIVE" in
  /*) ;;
  *) DSH_ARCHIVE="$DSH_ROOT/$DSH_ARCHIVE" ;;
esac
if [ ! -d "$DSH_APP" ] || [ ! -f "$DSH_APP/Contents/Info.plist" ]; then
  echo "Expected a macOS app bundle with Contents/Info.plist: $DSH_APP" >&2
  exit 1
fi
if [ -e "$DSH_APP/Contents/Resources/GPUI_TESTING" ]; then
  echo "Refusing to package a GPUI_TESTING app bundle; use the production --build output." >&2
  exit 1
fi

DSH_EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DSH_APP/Contents/Info.plist")
DSH_EXECUTABLE="$DSH_APP/Contents/MacOS/$DSH_EXECUTABLE_NAME"
DSH_FRAMEWORKS="$DSH_APP/Contents/Frameworks"
DSH_HELPER="$DSH_APP/Contents/Helpers/dsh"
if [ ! -x "$DSH_EXECUTABLE" ]; then
  echo "The app's CFBundleExecutable is missing or not executable: $DSH_EXECUTABLE" >&2
  exit 1
fi
if [ ! -x "$DSH_HELPER" ]; then
  echo "The app bundle must include its dsh CLI helper at Contents/Helpers/dsh." >&2
  exit 1
fi

DSH_GPUI_DYLIB=
for candidate in "$DSH_FRAMEWORKS"/*gpui*.dylib; do
  [ -f "$candidate" ] || continue
  if [ -n "$DSH_GPUI_DYLIB" ]; then
    echo "Expected one bundled GPUI dylib; found more than one." >&2
    exit 1
  fi
  DSH_GPUI_DYLIB=$candidate
done
if [ -z "$DSH_GPUI_DYLIB" ]; then
  echo "The app bundle must include its GPUI dylib under Contents/Frameworks." >&2
  exit 1
fi

for binary in "$DSH_EXECUTABLE" "$DSH_GPUI_DYLIB" "$DSH_HELPER"; do
  if [ "$(lipo -archs "$binary")" != arm64 ]; then
    echo "Expected an Apple silicon arm64 binary in the macOS app: $binary" >&2
    exit 1
  fi
done
python3 "$DSH_ROOT/scripts/check-macos-deployment-target.py" \
  "$DSH_APP" "$DSH_EXECUTABLE" "$DSH_GPUI_DYLIB" "$DSH_HELPER"

mkdir -p "$(dirname "$DSH_ARCHIVE")"
DSH_STAGE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-release.XXXXXX")
trap 'rm -rf "$DSH_STAGE_ROOT"' EXIT HUP INT TERM
DSH_STAGE="$DSH_STAGE_ROOT/Dsh-macos-arm64"
mkdir -p "$DSH_STAGE/licenses"
ditto "$DSH_APP" "$DSH_STAGE/Dsh.app"
cp "$DSH_ROOT/LICENSE" "$DSH_STAGE/LICENSE"
cp "$DSH_ROOT/THIRD_PARTY_NOTICES.md" "$DSH_STAGE/THIRD_PARTY_NOTICES.md"
cp "$DSH_ROOT/vendor/gpui/LICENSE" "$DSH_STAGE/licenses/gpui-LICENSE"
cp "$DSH_ROOT/licenses/yami-kumo-LICENSE" \
  "$DSH_STAGE/licenses/yami-kumo-LICENSE"
cp "$DSH_ROOT/licenses/yami-kumo-cloudflare-kumo-LICENSE" \
  "$DSH_STAGE/licenses/yami-kumo-cloudflare-kumo-LICENSE"
DSH_APP_RESOURCES="$DSH_STAGE/Dsh.app/Contents/Resources"
mkdir -p "$DSH_APP_RESOURCES/licenses"
cp "$DSH_ROOT/LICENSE" "$DSH_APP_RESOURCES/LICENSE"
cp "$DSH_ROOT/THIRD_PARTY_NOTICES.md" "$DSH_APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$DSH_ROOT/vendor/gpui/LICENSE" \
  "$DSH_APP_RESOURCES/licenses/gpui-LICENSE"
cp "$DSH_ROOT/licenses/yami-kumo-LICENSE" \
  "$DSH_APP_RESOURCES/licenses/yami-kumo-LICENSE"
cp "$DSH_ROOT/licenses/yami-kumo-cloudflare-kumo-LICENSE" \
  "$DSH_APP_RESOURCES/licenses/yami-kumo-cloudflare-kumo-LICENSE"
codesign --force --deep --sign - --timestamp=none "$DSH_STAGE/Dsh.app"
codesign --verify --deep --strict "$DSH_STAGE/Dsh.app"

DSH_ARCHIVE_DIR=$(dirname "$DSH_ARCHIVE")
DSH_ARCHIVE_NAME=$(basename "$DSH_ARCHIVE")
DSH_ARCHIVE_TMP="$DSH_STAGE_ROOT/$DSH_ARCHIVE_NAME"
ditto -c -k --sequesterRsrc --keepParent \
  "$DSH_STAGE" "$DSH_ARCHIVE_TMP"
unzip -tq "$DSH_ARCHIVE_TMP"
mv -f "$DSH_ARCHIVE_TMP" "$DSH_ARCHIVE_DIR/$DSH_ARCHIVE_NAME"
echo "Packaged $DSH_APP with its GPUI dylib and license notices as $DSH_ARCHIVE."
