#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
DSH_IOS="$DSH_ROOT/ios/ClientEmbedding"
MOON_HOME=${MOON_HOME:-${HOME:?}/.moon}
MOON_RUNTIME="$MOON_HOME/lib/runtime"
BUILD_ROOT=$(mktemp -d /private/tmp/dsh-client-model.XXXXXX)
MOON_BUILD_ROOT="$BUILD_ROOT/moon"
GENERATED="$MOON_BUILD_ROOT/native/release/build/f4ah6o/dsh/client/client.c"
BUILD_LOG="$BUILD_ROOT/moon-build.log"
trap 'rm -rf "$BUILD_ROOT"' EXIT HUP INT TERM

cd "$DSH_ROOT"

# Emit fresh generated C for every run; tolerate only the expected missing
# executable entry point from the MoonBit foreign-library link phase.
if MOONBIT_NEW_NATIVE=0 moon build client --target native --release \
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

OBJECTS=""
for SOURCE in \
  "$GENERATED" \
  "$DSH_IOS/moonbit_bridge.c" \
  "$MOON_RUNTIME/runtime.c" \
  "$MOON_RUNTIME/env.c" \
  "$MOON_RUNTIME/backtrace.c" \
  "$MOON_RUNTIME/sync_io.c" \
  "$MOON_RUNTIME/utf.c"; do
  OBJECT="$BUILD_ROOT/$(basename "$SOURCE" .c).o"
  clang \
    -I"$MOON_HOME/include" \
    -I"$DSH_IOS/include" \
    -fwrapv -fno-strict-aliasing -O0 \
    -DMOONBIT_TRIAL_DELETION=1 \
    -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM \
    -c "$SOURCE" -o "$OBJECT"
  OBJECTS="$OBJECTS $OBJECT"
done

# shellcheck disable=SC2086
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$BUILD_ROOT/swift-module-cache" \
  -import-objc-header "$DSH_IOS/include/dsh_moonbit_client.h" \
  "$DSH_IOS/Sample/DshClientModel.swift" \
  "$DSH_IOS/Tests/DshClientModelTests.swift" \
  $OBJECTS \
  -framework Security -lm \
  -o "$BUILD_ROOT/dsh-client-model-tests"

"$BUILD_ROOT/dsh-client-model-tests"
