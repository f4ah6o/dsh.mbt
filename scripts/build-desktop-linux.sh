#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ "$(uname -s)" = Linux ] || { echo 'Linux desktop requires Linux.' >&2; exit 2; }
MODE=${1:-run}
[ "$#" -eq 0 ] || shift
case "$MODE" in --build|run|--run|--smoke|--debug|--verify) ;; *) echo "usage: $0 [--build|run|--smoke|--debug|--verify] [desktop args...]" >&2; exit 2;; esac
for tool in moon python3 pkg-config wayland-scanner; do
  command -v "$tool" >/dev/null || { echo "Required Linux desktop build tool missing: $tool" >&2; exit 1; }
done
pkg-config --atleast-version=1.50 pangoft2
pkg-config --exists wayland-client wayland-cursor wayland-egl egl glesv2 xkbcommon fontconfig
sh vendor/gpui/scripts/prepare_ubuntu.sh
BUILD_KIND=release
if [ "$MODE" = --debug ]; then
  BUILD_KIND=debug
  moon build desktop/linux --target native --frozen
else
  moon build desktop/linux --target native --release --frozen
fi
BIN="$ROOT/_build/native/$BUILD_KIND/build/f4ah6o/dsh/desktop/linux/linux.exe"
test -x "$BIN"
printf 'Built native Linux Wayland desktop: %s\n' "$BIN"
case "$MODE" in
  --build|--verify) exit 0;;
  --smoke) set -- --smoke --demo "$@";;
esac
# Source builds use the companion CLI for isolated runtime tool workers.
: "${DSH_NATIVE_WORKER_BIN:=$ROOT/_build/native/release/build/f4ah6o/dsh/cmd/dsh/dsh.exe}"
export DSH_NATIVE_WORKER_BIN
exec "$BIN" "$@"
