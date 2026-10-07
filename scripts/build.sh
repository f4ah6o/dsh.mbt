#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"
node scripts/verify-env.mjs
npm run build:shell
moon build app --target js --release
moon build client --target js --release

# moon.work places the module name between the build root and package path.
DSH_APP="_build/js/release/build/f4ah6o/dsh/app/app.js"
DSH_CLIENT="_build/js/release/build/f4ah6o/dsh/client/client.js"
if [ ! -s "$DSH_APP" ]; then
  echo "MoonBit did not produce $DSH_APP. Check the app package and moon.work configuration." >&2
  exit 1
fi
node --check "$DSH_APP"
if [ ! -s "$DSH_CLIENT" ]; then
  echo "MoonBit did not produce $DSH_CLIENT. Check the client package and moon.work configuration." >&2
  exit 1
fi
node --check "$DSH_CLIENT"
node --check web/yami-kumo-shell.js
if [ ! -s web/yami-kumo-shell.css ]; then
  echo "The Yami-kumo browser shell stylesheet was not produced." >&2
  exit 1
fi
echo "Built $DSH_APP"
echo "Built $DSH_CLIENT"
