#!/bin/sh
set -eu

DSH_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$DSH_ROOT"
node scripts/verify-env.mjs

# Explicit selectors keep vendor OS backend/example tests out of this gate.
moon test engine provider plugins api ui --target all
moon test app --target js
