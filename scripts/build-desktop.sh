#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Dsh.app requires macOS and Xcode command-line tools." >&2
  exit 2
fi

MODE=run
if [[ "$#" -gt 0 ]]; then
  MODE="$1"
  shift
fi
case "$MODE" in
  run|--run|--build|--smoke|--verify|--debug|--test-hooks|--offline-e2e|--visual-smoke)
    ;;
  *)
    echo "usage: $0 [run|--build|--smoke|--verify|--debug|--test-hooks|--offline-e2e] [desktop args...]" >&2
    exit 2
    ;;
esac

TEST_BUILD=0
case "$MODE" in
  --test-hooks|--offline-e2e|--visual-smoke) TEST_BUILD=1 ;;
esac
BUILD_KIND=release
if [[ "$MODE" == "--debug" ]]; then
  BUILD_KIND=debug
fi

APP_NAME=Dsh
BUNDLE_ID=org.fu2hito.dsh
if [[ "$TEST_BUILD" == 1 ]]; then
  APP_NAME=Dsh-Test
  BUNDLE_ID=org.fu2hito.dsh.test
fi
BUILD_ROOT="$ROOT_DIR/_build/macos"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/dsh-desktop"
GPUI_DYLIB="$APP_BUNDLE/Contents/Frameworks/libgpui_macos.dylib"
MOON_TARGET_ROOT="$ROOT_DIR/_build/desktop-macos13"
MOON_BUILD_ROOT="$MOON_TARGET_ROOT/native/$BUILD_KIND/build/f4ah6o/dsh"
DESKTOP_BINARY="$MOON_BUILD_ROOT/desktop/desktop.exe"
CLI_BINARY="$MOON_BUILD_ROOT/cmd/dsh/dsh.exe"
mkdir -p "$BUILD_ROOT"

if [[ "$BUILD_KIND" == release ]]; then
  MACOSX_DEPLOYMENT_TARGET=13.0 moon build --target native --release \
    --target-dir "$MOON_TARGET_ROOT" --frozen desktop cmd/dsh
else
  MACOSX_DEPLOYMENT_TARGET=13.0 moon build --target native \
    --target-dir "$MOON_TARGET_ROOT" --frozen desktop cmd/dsh
fi
if [[ ! -x "$DESKTOP_BINARY" || ! -x "$CLI_BINARY" ]]; then
  echo "MoonBit did not produce the desktop executable and bundled CLI helper." >&2
  exit 1
fi

STAGING_BUNDLE="$BUILD_ROOT/.$APP_NAME.app.tmp.$$"
rm -rf "$STAGING_BUNDLE"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Helpers" \
  "$STAGING_BUNDLE/Contents/Frameworks" "$STAGING_BUNDLE/Contents/Resources"
cleanup() {
  rm -rf "$STAGING_BUNDLE"
}
trap cleanup EXIT HUP INT TERM

if [[ "$TEST_BUILD" == 1 ]]; then
  xcrun clang -dynamiclib -mmacosx-version-min=13.0 -DGPUI_TESTING -fobjc-arc -Wall -Wextra -Werror \
    "$ROOT_DIR/vendor/gpui/platform/macos/native.m" \
    "$ROOT_DIR/vendor/gpui/platform/macos_text/core_text.c" \
    -framework AppKit -framework QuartzCore -framework Metal \
    -framework CoreText -framework CoreGraphics -framework CoreFoundation \
    -Wl,-install_name,@rpath/libgpui_macos.dylib \
    -o "$STAGING_BUNDLE/Contents/Frameworks/libgpui_macos.dylib"
else
  xcrun clang -dynamiclib -mmacosx-version-min=13.0 -fobjc-arc -Wall -Wextra -Werror \
    "$ROOT_DIR/vendor/gpui/platform/macos/native.m" \
    "$ROOT_DIR/vendor/gpui/platform/macos_text/core_text.c" \
    -framework AppKit -framework QuartzCore -framework Metal \
    -framework CoreText -framework CoreGraphics -framework CoreFoundation \
    -Wl,-install_name,@rpath/libgpui_macos.dylib \
    -o "$STAGING_BUNDLE/Contents/Frameworks/libgpui_macos.dylib"
fi
cp "$DESKTOP_BINARY" "$STAGING_BUNDLE/Contents/MacOS/dsh-desktop"
cp "$CLI_BINARY" "$STAGING_BUNDLE/Contents/Helpers/dsh"
chmod 755 "$STAGING_BUNDLE/Contents/MacOS/dsh-desktop" \
  "$STAGING_BUNDLE/Contents/Helpers/dsh"
VERSION="$(awk -F '"' '$1 ~ /^version = / {print $2; exit}' moon.mod)"
if [[ -z "$VERSION" ]]; then
  VERSION=0.1.0
fi
cat > "$STAGING_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>dsh-desktop</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Dsh</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [[ "$TEST_BUILD" == 1 ]]; then
  touch "$STAGING_BUNDLE/Contents/Resources/GPUI_TESTING"
fi

rm -rf "$APP_BUNDLE"
mv "$STAGING_BUNDLE" "$APP_BUNDLE"
trap - EXIT HUP INT TERM

if [[ "$MODE" == "--build" || "$MODE" == "--test-hooks" ]]; then
  echo "$APP_BUNDLE"
  exit 0
fi

export GPUI_MACOS_LIBRARY="$GPUI_DYLIB"
case "$MODE" in
  --smoke)
    SMOKE_ROOT="$(mktemp -d /tmp/dsh-native-smoke.XXXXXX)"
    trap 'rm -rf "$SMOKE_ROOT"' EXIT HUP INT TERM
    mkdir -p "$SMOKE_ROOT/workspace"
    HAS_WORKSPACE=0
    HAS_DATA_DIR=0
    for argument in "$@"; do
      [[ "$argument" == "--workspace" ]] && HAS_WORKSPACE=1
      [[ "$argument" == "--data-dir" ]] && HAS_DATA_DIR=1
    done
    if [[ "$HAS_WORKSPACE" == 0 ]]; then
      set -- "$@" --workspace "$SMOKE_ROOT/workspace"
    fi
    if [[ "$HAS_DATA_DIR" == 0 ]]; then
      set -- "$@" --data-dir "$SMOKE_ROOT/data"
    fi
    "$APP_EXECUTABLE" --smoke "$@"
    ;;
  --verify)
    SMOKE_ROOT="$(mktemp -d /tmp/dsh-native-smoke.XXXXXX)"
    trap 'rm -rf "$SMOKE_ROOT"' EXIT HUP INT TERM
    mkdir -p "$SMOKE_ROOT/workspace"
    "$APP_EXECUTABLE" --smoke \
      --workspace "$SMOKE_ROOT/workspace" \
      --data-dir "$SMOKE_ROOT/data"
    ;;
  --offline-e2e|--visual-smoke)
    export GPUI_NATIVE_E2E=1
    FRAME_ROOT="$BUILD_ROOT"
    if [[ "$#" -eq 0 ]]; then
      SMOKE_ROOT="$(mktemp -d /tmp/dsh-desktop-e2e.XXXXXX)"
      trap 'rm -rf "$SMOKE_ROOT"' EXIT HUP INT TERM
      mkdir -p "$SMOKE_ROOT/workspace"
      set -- --workspace "$SMOKE_ROOT/workspace" --data-dir "$SMOKE_ROOT/data"
    fi
    HAS_FRAME_OUTPUT=0
    for argument in "$@"; do
      if [[ "$argument" == "--frame-output" ]]; then
        HAS_FRAME_OUTPUT=1
        break
      fi
    done
    if [[ "$HAS_FRAME_OUTPUT" == 0 ]]; then
      set -- "$@" --frame-output "$FRAME_ROOT/dsh-desktop-frame.ppm"
    fi
    APP_STDOUT="$FRAME_ROOT/dsh-desktop-e2e.stdout"
    APP_STDERR="$FRAME_ROOT/dsh-desktop-e2e.stderr"
    rm -f "$APP_STDOUT" "$APP_STDERR"
    /usr/bin/open -n -F -W -a "$APP_BUNDLE" \
      --env "GPUI_NATIVE_E2E=1" \
      --env "GPUI_MACOS_LIBRARY=$GPUI_DYLIB" \
      --stdout "$APP_STDOUT" --stderr "$APP_STDERR" \
      --args --offline-e2e "$@"
    if ! rg -q '"nsevents":true' "$APP_STDOUT"; then
      cat "$APP_STDOUT" "$APP_STDERR" >&2
      echo "LaunchServices native offline E2E did not emit its success marker." >&2
      exit 1
    fi
    cat "$APP_STDOUT"
    FRAME_PPM="$FRAME_ROOT/dsh-desktop-frame.ppm"
    READ_FRAME=0
    for argument in "$@"; do
      if [[ "$READ_FRAME" == 1 ]]; then
        FRAME_PPM="$argument"
        break
      fi
      if [[ "$argument" == "--frame-output" ]]; then
        READ_FRAME=1
      fi
    done
    sips -s format png "$FRAME_PPM" --out "$FRAME_ROOT/dsh-desktop-frame.png" >/dev/null
    echo "$FRAME_ROOT/dsh-desktop-frame.png"
    SETTINGS_PPM="${FRAME_PPM}.settings.ppm"
    SETTINGS_PNG="${FRAME_PPM%.ppm}.settings.png"
    sips -s format png "$SETTINGS_PPM" --out "$SETTINGS_PNG" >/dev/null
    echo "$SETTINGS_PNG"
    ;;
  run|--run)
    /usr/bin/open -n -a "$APP_BUNDLE" --args "$@"
    ;;
  --debug)
    lldb -- "$APP_EXECUTABLE" "$@"
    ;;
esac
