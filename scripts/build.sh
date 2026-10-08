#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"

moon build native --target native --release --frozen
moon build browser --target js --release --frozen
moon build browser/sw --target js --release --frozen

DSH_NATIVE="_build/native/release/build/f4ah6o/dsh/native/native.exe"
DSH_BROWSER="_build/js/release/build/f4ah6o/dsh/browser/browser.js"
DSH_SERVICE_WORKER="_build/js/release/build/f4ah6o/dsh/browser/sw/sw.js"
YAMI_PACKAGE=".mooncakes/f4ah6o/yami_kumo"
if [ ! -s "$DSH_NATIVE" ]; then
  echo "MoonBit did not produce $DSH_NATIVE." >&2
  exit 1
fi
if [ ! -s "$DSH_BROWSER" ]; then
  echo "MoonBit did not produce $DSH_BROWSER." >&2
  exit 1
fi
if [ ! -s "$DSH_SERVICE_WORKER" ]; then
  echo "MoonBit did not produce $DSH_SERVICE_WORKER." >&2
  exit 1
fi

mkdir -p web/moonbit
cp "$DSH_BROWSER" web/moonbit/browser.js
cp "$DSH_SERVICE_WORKER" web/sw.js
if ! cmp -s "$YAMI_PACKAGE/styles/kumo-standalone.css" web/kumo-standalone.css; then
  echo "web/kumo-standalone.css differs from the pinned Mooncakes package; refresh it with npm run build:shell." >&2
  exit 1
fi
if ! cmp -s "$YAMI_PACKAGE/styles/yami-kumo-components.css" web/yami-kumo-components.css; then
  echo "web/yami-kumo-components.css differs from the pinned Mooncakes package; refresh it with npm run build:shell." >&2
  exit 1
fi
cp "$YAMI_PACKAGE/styles/kumo-standalone.css" web/kumo-standalone.css
cp "$YAMI_PACKAGE/styles/yami-kumo-components.css" web/yami-kumo-components.css
if [ ! -s web/yami-kumo-shell.css ]; then
  echo "The dsh Yami-kumo shell stylesheet is missing." >&2
  exit 1
fi

echo "Built $DSH_NATIVE, web/moonbit/browser.js, web/sw.js, and pinned Yami-kumo styles."
