#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
DSH_ABI_DIR="$DSH_ROOT/ios/ClientEmbedding"
MOON_HOME=${MOON_HOME:-${HOME:?}/.moon}
RUNTIME="$MOON_HOME/lib/runtime"
OUTPUT="$DSH_ROOT/_build/ios-client-abi"
MOON_BUILD_ROOT=$(mktemp -d /private/tmp/dsh-moonbit-abi.XXXXXX)
GENERATED="$MOON_BUILD_ROOT/native/release/build/f4ah6o/dsh/client/client.c"
trap 'rm -rf "$MOON_BUILD_ROOT"' EXIT HUP INT TERM

cd "$DSH_ROOT"
mkdir -p "$OUTPUT"

# Always build into a unique target directory so the ABI test cannot silently
# consume stale C and does not contend for the workspace Moon build lock. The
# pinned backend emits C, then the foreign-library link step reports only the
# missing executable main.
build_log="$OUTPUT/moon-build.log"
if MOONBIT_NEW_NATIVE=0 moon build client --target native --release \
    --target-dir "$MOON_BUILD_ROOT" >"$build_log" 2>&1; then
  :
elif grep -Fq '"_main", referenced from:' "$build_log" && \
     [ "$(awk '/^Undefined symbols for architecture/{inside=1; next} /^ld: symbol/{inside=0} inside && /referenced from:/{count += 1} END{print count+0}' "$build_log")" -eq 1 ]; then
  echo "MoonBit emitted fresh client C; its foreign-library link step requires an executable main." >&2
else
  cat "$build_log" >&2
  exit 1
fi

if [ ! -s "$GENERATED" ]; then
  echo "MoonBit did not emit the expected client C source: $GENERATED" >&2
  exit 1
fi

clang \
  -I"$MOON_HOME/include" \
  -I"$DSH_ABI_DIR/include" \
  -fwrapv -fno-strict-aliasing -O2 \
  -DMOONBIT_TRIAL_DELETION=1 \
  -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM \
  "$GENERATED" \
  "$DSH_ABI_DIR/moonbit_bridge.c" \
  "$DSH_ABI_DIR/abi_smoke.c" \
  "$RUNTIME/runtime.c" \
  "$RUNTIME/env.c" \
  "$RUNTIME/backtrace.c" \
  "$RUNTIME/sync_io.c" \
  "$RUNTIME/utf.c" \
  -lm \
  -o "$OUTPUT/abi-smoke"

"$OUTPUT/abi-smoke"
