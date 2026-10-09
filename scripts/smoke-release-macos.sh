#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo "The macOS app smoke must run on macOS." >&2
  exit 1
fi
DSH_SCRIPT_ROOT=$(CDPATH='' cd "$(dirname "$0")" && pwd)
DSH_SMOKE_MODE=full
if [ "$#" -eq 2 ] && [ "$1" = "--bundle-only" ]; then
  DSH_SMOKE_MODE=bundle-only
  DSH_ARCHIVE=$2
elif [ "$#" -eq 1 ]; then
  DSH_ARCHIVE=$1
else
  echo "usage: $0 [--bundle-only] PATH_TO_ARCHIVE.zip" >&2
  exit 2
fi
case "$DSH_ARCHIVE" in
  /*) ;;
  *) DSH_ARCHIVE="$(pwd)/$DSH_ARCHIVE" ;;
esac
if [ ! -s "$DSH_ARCHIVE" ]; then
  echo "macOS app archive is missing or empty: $DSH_ARCHIVE" >&2
  exit 1
fi

SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dsh-release-macos.XXXXXX")
trap 'rm -rf "$SMOKE_ROOT"' EXIT HUP INT TERM
ditto -x -k --sequesterRsrc "$DSH_ARCHIVE" "$SMOKE_ROOT"
DSH_PACKAGE="$SMOKE_ROOT/Dsh-macos-arm64"
DSH_APP="$DSH_PACKAGE/Dsh.app"
DSH_APP=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$DSH_APP")
DSH_PLIST="$DSH_APP/Contents/Info.plist"
if [ ! -d "$DSH_APP" ] || [ ! -f "$DSH_PLIST" ]; then
  echo "The archive does not contain Dsh-macos-arm64/Dsh.app." >&2
  exit 1
fi
if [ -e "$DSH_APP/Contents/Resources/GPUI_TESTING" ]; then
  echo "The release archive contains a GPUI_TESTING app bundle." >&2
  exit 1
fi
for notice in \
  "$DSH_PACKAGE/LICENSE" \
  "$DSH_PACKAGE/THIRD_PARTY_NOTICES.md" \
  "$DSH_PACKAGE/licenses/gpui-LICENSE" \
  "$DSH_PACKAGE/licenses/yami-kumo-LICENSE" \
  "$DSH_PACKAGE/licenses/yami-kumo-cloudflare-kumo-LICENSE" \
  "$DSH_APP/Contents/Resources/LICENSE" \
  "$DSH_APP/Contents/Resources/THIRD_PARTY_NOTICES.md" \
  "$DSH_APP/Contents/Resources/licenses/gpui-LICENSE" \
  "$DSH_APP/Contents/Resources/licenses/yami-kumo-LICENSE" \
  "$DSH_APP/Contents/Resources/licenses/yami-kumo-cloudflare-kumo-LICENSE"; do
  if [ ! -s "$notice" ]; then
    echo "The macOS app archive is missing a required notice: $notice" >&2
    exit 1
  fi
done

DSH_EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DSH_PLIST")
DSH_EXECUTABLE="$DSH_APP/Contents/MacOS/$DSH_EXECUTABLE_NAME"
DSH_FRAMEWORKS="$DSH_APP/Contents/Frameworks"
DSH_HELPER="$DSH_APP/Contents/Helpers/dsh"
if [ ! -x "$DSH_EXECUTABLE" ]; then
  echo "The app's CFBundleExecutable is missing or not executable: $DSH_EXECUTABLE" >&2
  exit 1
fi
if [ ! -x "$DSH_HELPER" ]; then
  echo "The extracted app is missing Contents/Helpers/dsh." >&2
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
  echo "The extracted app is missing its GPUI dylib." >&2
  exit 1
fi
python3 "$DSH_SCRIPT_ROOT/check-macos-deployment-target.py" \
  "$DSH_APP" "$DSH_EXECUTABLE" "$DSH_GPUI_DYLIB" "$DSH_HELPER"

DSH_EXECUTABLE_DIR=$(dirname "$DSH_EXECUTABLE")
require_bundled_path() {
  source_binary=$1
  dependency=$2
  candidate=$3
  if [ ! -f "$candidate" ]; then
    echo "Unresolved dependency from $source_binary: $dependency" >&2
    return 1
  fi
  resolved=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$candidate")
  case "$resolved" in
    "$DSH_APP"/*) ;;
    *)
      echo "Dependency escapes the Dsh.app bundle: $source_binary -> $dependency" >&2
      return 1
      ;;
  esac
}
check_macos_dependencies() {
  binary=$1
  dependencies=$(otool -L "$binary" | sed '1d; s/^[[:space:]]*//; s/ (.*$//')
  for dependency in $dependencies; do
    case "$dependency" in
      /System/Library/*|/System/Volumes/Preboot/Cryptexes/OS/System/Library/*|/usr/lib/*|/System/Volumes/Preboot/Cryptexes/OS/usr/lib/*)
        ;;
      @rpath/*)
        relative_path=${dependency#@rpath/}
        require_bundled_path "$binary" "$dependency" "$DSH_FRAMEWORKS/$relative_path"
        ;;
      @executable_path/*)
        relative_path=${dependency#@executable_path/}
        require_bundled_path "$binary" "$dependency" "$DSH_EXECUTABLE_DIR/$relative_path"
        ;;
      @loader_path/*)
        relative_path=${dependency#@loader_path/}
        require_bundled_path "$binary" "$dependency" "$(dirname "$binary")/$relative_path"
        ;;
      *)
        echo "macOS app depends on a non-system library outside its bundle: $dependency" >&2
        return 1
        ;;
    esac
  done
}
for binary in "$DSH_EXECUTABLE" "$DSH_GPUI_DYLIB" "$DSH_HELPER"; do
  if [ "$(lipo -archs "$binary")" != arm64 ]; then
    echo "Expected an arm64 app binary after archive extraction: $binary" >&2
    exit 1
  fi
  check_macos_dependencies "$binary"
done
codesign --verify --deep --strict "$DSH_APP"
DSH_SIGNATURE=$(codesign -dv --verbose=2 "$DSH_APP" 2>&1 || true)
if ! printf '%s\n' "$DSH_SIGNATURE" | grep -Fq 'Signature=adhoc'; then
  echo "The extracted Dsh.app does not have the expected ad-hoc code signature." >&2
  printf '%s\n' "$DSH_SIGNATURE" >&2
  exit 1
fi

# The app's desktop executable loads this bundled GPUI dylib by a path beside
# its own executable. The app smoke below exercises that dynamic load.
if [ ! -f "$DSH_APP/Contents/MacOS/../Frameworks/libgpui_macos.dylib" ]; then
  echo "The app's relative GPUI dylib load path does not resolve." >&2
  exit 1
fi
sh "$DSH_SCRIPT_ROOT/smoke-release-cli.sh" "$DSH_HELPER"

if [ "$DSH_SMOKE_MODE" = bundle-only ]; then
  echo "Validated the extracted app bundle, signature, dependencies, notices, and helper; the graphical Metal launch smoke was explicitly skipped in bundle-only mode."
  exit 0
fi

mkdir -p "$SMOKE_ROOT/tmp" "$SMOKE_ROOT/data" "$SMOKE_ROOT/workspace" \
  "$SMOKE_ROOT/unrelated-working-directory"
python3 - "$DSH_APP" "$SMOKE_ROOT" <<'PY'
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

app_bundle, smoke_root = sys.argv[1:]
environment = os.environ.copy()
environment["TMPDIR"] = os.path.join(smoke_root, "tmp")
environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
for name in (
    "DSH_API_KEY",
    "DEEPSEEK_API_KEY",
    "OPENAI_API_KEY",
    "DSH_TAILNET_HOST",
    "DSH_TAILNET_ALLOWED_USERS",
    "DSH_TAILNET_PORT",
    "GPUI_MACOS_LIBRARY",
    "GPUI_NATIVE_E2E",
    "DSH_NATIVE_WORKER_BIN",
    "DYLD_LIBRARY_PATH",
    "DYLD_FRAMEWORK_PATH",
    "DYLD_INSERT_LIBRARIES",
    "DYLD_FALLBACK_LIBRARY_PATH",
    "DYLD_FALLBACK_FRAMEWORK_PATH",
):
    environment.pop(name, None)
stdout_path = os.path.join(smoke_root, "app.stdout")
stderr_path = os.path.join(smoke_root, "app.stderr")
smoke_executables = [
    os.path.join(app_bundle, "Contents", "MacOS", "dsh-desktop"),
    os.path.join(app_bundle, "Contents", "Helpers", "dsh"),
]


def smoke_pids():
    processes = subprocess.run(
        ["/bin/ps", "-ww", "-Ao", "pid=,command="],
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    matches = set()
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid_text, command = fields
        if any(
            command == executable or command.startswith(executable + " ")
            for executable in smoke_executables
        ):
            matches.add(int(pid_text))
    return matches


def stop_smoke_processes():
    pids = smoke_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        pids = smoke_pids()
        if not pids:
            return
        time.sleep(0.1)
    for pid in smoke_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


try:
    result = subprocess.run(
        [
            "/usr/bin/open",
            "-n",
            "-F",
            "-W",
            "--stdout",
            stdout_path,
            "--stderr",
            stderr_path,
            "-a",
            app_bundle,
            "--args",
            "--smoke",
            "--data-dir",
            os.path.join(smoke_root, "data"),
            "--workspace",
            os.path.join(smoke_root, "workspace"),
        ],
        cwd=os.path.join(smoke_root, "unrelated-working-directory"),
        env=environment,
        text=True,
        capture_output=True,
        timeout=90,
    )
except subprocess.TimeoutExpired as error:
    sys.stderr.write("The extracted Dsh.app smoke did not finish within 90 seconds.\n")
    try:
        stop_smoke_processes()
    except (OSError, subprocess.CalledProcessError, ValueError) as cleanup_error:
        sys.stderr.write(f"Could not clean up the extracted smoke app: {cleanup_error}\n")
    if error.stdout:
        sys.stderr.write(error.stdout if isinstance(error.stdout, str) else error.stdout.decode())
    if error.stderr:
        sys.stderr.write(error.stderr if isinstance(error.stderr, str) else error.stderr.decode())
    if Path(stdout_path).exists():
        sys.stderr.write(Path(stdout_path).read_text(errors="replace"))
    if Path(stderr_path).exists():
        sys.stderr.write(Path(stderr_path).read_text(errors="replace"))
    raise SystemExit(1)
sys.stdout.write(result.stdout)
if Path(stdout_path).exists():
    app_stdout = Path(stdout_path).read_text(errors="replace")
    sys.stdout.write(app_stdout)
else:
    app_stdout = ""
if Path(stderr_path).exists():
    app_stderr = Path(stderr_path).read_text(errors="replace")
else:
    app_stderr = ""
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.stderr.write(app_stderr)
    raise SystemExit(result.returncode)
expected = 'DSH_DESKTOP_SMOKE {"frame":true,"resized":true,"close_requested":true,"destroyed":true}'
if expected not in app_stdout:
    sys.stderr.write("The extracted Dsh.app did not report successful frame, resize, and shutdown checks.\n")
    sys.stderr.write(result.stderr)
    sys.stderr.write(app_stderr)
    raise SystemExit(1)
PY

echo "Extracted Dsh.app passed its native frame smoke from outside the checkout with only bundled non-system libraries."
