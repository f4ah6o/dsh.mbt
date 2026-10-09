#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"
node scripts/verify-env.mjs

# Explicit selectors keep vendor OS backend/example tests out of this gate.
moon test engine provider auth protocol client plugins api ui verification/retry_math --target all
moon test app browser browser/sw --target js

native_test_root=$(mktemp -d "${TMPDIR:-/tmp}/dsh-native-tests.XXXXXX")
trap 'rm -rf "$native_test_root"' EXIT HUP INT TERM
native_target="$native_test_root/worker-build"
moon build native --target native --release --frozen --target-dir "$native_target"
native_worker="$native_target/native/release/build/f4ah6o/dsh/native/native.exe"
if [ ! -x "$native_worker" ]; then
  echo "Native worker executable is missing: $native_worker" >&2
  exit 1
fi
node scripts/test-acp-stdio.mjs "$native_worker"
DSH_NATIVE_WORKER_BIN="$native_worker" moon test runtime --target native --frozen --target-dir "$native_test_root/tests"

sh scripts/build.sh
sh scripts/test-install.sh
