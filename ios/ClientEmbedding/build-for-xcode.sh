#!/bin/sh
set -eu

DSH_PROJECT_DIR=${PROJECT_DIR:-$(CDPATH= cd "$(dirname "$0")" && pwd)}
DSH_ROOT=$(CDPATH= cd "$DSH_PROJECT_DIR/../.." && pwd)
MOON_HOME=${MOON_HOME:-${HOME:?}/.moon}
MOON_RUNTIME="$MOON_HOME/lib/runtime"
BUILD_ROOT="$DSH_ROOT/_build/ios-client/${PLATFORM_NAME:-iphonesimulator}"
BUILD_LOG="$BUILD_ROOT/moon-build.log"
MOON_BUILD_ROOT=$(mktemp -d /private/tmp/dsh-moonbit-client.XXXXXX)
GENERATED="$MOON_BUILD_ROOT/native/release/build/f4ah6o/dsh/client/client.c"
HOST_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
trap 'rm -rf "$MOON_BUILD_ROOT"' EXIT HUP INT TERM

mkdir -p "$BUILD_ROOT"
cd "$DSH_ROOT"

# Re-emit client C in an isolated target directory on every Xcode build so
# Swift never links stale shared state code and Moon does not contend for the
# repository build lock. The foreign-library link step reports the missing
# executable main after generating C.
if env -u SDK_NAME -u SDK_DIR -u PLATFORM_NAME -u EFFECTIVE_PLATFORM_NAME \
    -u ARCHS -u IPHONEOS_DEPLOYMENT_TARGET -u TARGET -u TOOLCHAINS \
    SDKROOT="$HOST_SDK_PATH" CC=/usr/bin/clang CFLAGS= CPPFLAGS= CXXFLAGS= \
    LDFLAGS= CPATH= C_INCLUDE_PATH= CPLUS_INCLUDE_PATH= LIBRARY_PATH= \
    MOONBIT_NEW_NATIVE=0 moon build client --target native --release \
    --target-dir "$MOON_BUILD_ROOT" >"$BUILD_LOG" 2>&1; then
  :
elif grep -Fq '"_main", referenced from:' "$BUILD_LOG" && \
     [ "$(awk '/^Undefined symbols for architecture/{inside=1; next} /^ld: symbol/{inside=0} inside && /referenced from:/{count += 1} END{print count+0}' "$BUILD_LOG")" -eq 1 ]; then
  echo "MoonBit emitted fresh client C; its foreign-library link step requires an executable main." >&2
else
  cat "$BUILD_LOG" >&2
  exit 1
fi

if [ ! -s "$GENERATED" ]; then
  echo "MoonBit did not emit the expected client C source: $GENERATED" >&2
  exit 1
fi

SDK_NAME=${PLATFORM_NAME:-iphonesimulator}
SDK_PATH=${SDKROOT:-$(xcrun --sdk "$SDK_NAME" --show-sdk-path)}
DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-18.0}
ARCHIVE_INPUTS=""

for ARCH in ${ARCHS:-arm64}; do
  TARGET="${ARCH}-apple-ios${DEPLOYMENT_TARGET}"
  if [ "$SDK_NAME" = "iphonesimulator" ]; then
    TARGET="$TARGET-simulator"
  elif [ "$SDK_NAME" != "iphoneos" ]; then
    echo "Unsupported Xcode platform for the MoonBit client: $SDK_NAME" >&2
    exit 1
  fi

  ARCH_DIR="$BUILD_ROOT/$ARCH"
  mkdir -p "$ARCH_DIR"
  OBJECTS=""
  for SOURCE in \
    "$GENERATED" \
    "$DSH_PROJECT_DIR/moonbit_bridge.c" \
    "$MOON_RUNTIME/runtime.c" \
    "$MOON_RUNTIME/env.c" \
    "$MOON_RUNTIME/backtrace.c" \
    "$MOON_RUNTIME/sync_io.c" \
    "$MOON_RUNTIME/utf.c"; do
    OBJECT="$ARCH_DIR/$(basename "$SOURCE" .c).o"
    xcrun --sdk "$SDK_NAME" clang \
      -target "$TARGET" \
      -isysroot "$SDK_PATH" \
      -I"$MOON_HOME/include" \
      -I"$DSH_PROJECT_DIR/include" \
      -fwrapv -fno-strict-aliasing -fvisibility=hidden \
      -DMOONBIT_TRIAL_DELETION=1 \
      -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM \
      -c "$SOURCE" -o "$OBJECT"
    OBJECTS="$OBJECTS $OBJECT"
  done

  ARCHIVE="$BUILD_ROOT/libdsh_moonbitclient_$ARCH.a"
  # Xcode provides one or more validated architecture tokens here.
  # shellcheck disable=SC2086
  xcrun --sdk "$SDK_NAME" ar rcs "$ARCHIVE" $OBJECTS
  xcrun --sdk "$SDK_NAME" ranlib "$ARCHIVE"
  ARCHIVE_INPUTS="$ARCHIVE_INPUTS $ARCHIVE"
done

set -- $ARCHIVE_INPUTS
if [ "$#" -eq 1 ]; then
  cp "$1" "$BUILD_ROOT/libdsh_moonbitclient.a"
else
  # shellcheck disable=SC2086
  xcrun lipo -create $ARCHIVE_INPUTS -output "$BUILD_ROOT/libdsh_moonbitclient.a"
fi

echo "Built $BUILD_ROOT/libdsh_moonbitclient.a for $SDK_NAME (${ARCHS:-arm64})"
