# Native desktop

## Windows

Not provided yet. The Windows work starts with the bounded native runtime
(M1): CLI, web, session store, approval, and the SafeRoot boundary. A Windows
build reports an explicit unsupported error for `dsh desktop` instead of
launching a stub. See the
[Windows native profile](native-runtime.md#windows-x64-profile).

## Linux Wayland and X11

The Linux release CLI embeds a real GPUI Wayland/X11 EGL desktop executable. `dsh desktop` extracts it and a private CLI worker into an owner-only temporary directory, launches the desktop, preserves argument boundaries and exit status, and removes the files after exit. It does not open a browser or download executable code. The embedded checksum detects corruption; release authenticity comes from the release distribution/checksum workflow.

Supported baseline: Ubuntu 24.04, x86-64 and ARM64, with a Wayland compositor or X11 server and EGL/GLES drivers (Mesa software rendering is valid). Install the runtime libraries and Japanese fonts listed in README. The X11 backend connects directly to the X server and does not require a Wayland compositor or XWayland. Keyboard input, pointer, scrolling and Ctrl+A/C/V/X are supported. IME composition is not yet implemented. Clipboard requires session support; unsupported capabilities are reported rather than simulated. X11 currently uses scale 1.

`DSH_DESKTOP_BACKEND=auto` (the default) prefers a nonempty `WAYLAND_DISPLAY` or `WAYLAND_SOCKET`, then a nonempty `DISPLAY`. Set `DSH_DESKTOP_BACKEND=wayland` or `DSH_DESKTOP_BACKEND=x11` to choose explicitly. Unknown values and missing session variables fail with an actionable error. Once selected, connection or driver errors are reported without silently trying the other backend.

Build from the checkout with the pinned MoonBit toolchain and installed MoonBit dependencies:

```sh
sudo apt-get install libx11-dev libwayland-dev wayland-protocols libegl1-mesa-dev \
  libgles2-mesa-dev libxkbcommon-dev libpango1.0-dev libfontconfig1-dev
sh scripts/build.sh
sh scripts/build-desktop-linux.sh --build
python3 scripts/package-linux-desktop.py \
  --cli _build/native/release/build/f4ah6o/dsh/cmd/dsh/dsh.exe \
  --desktop _build/native/release/build/f4ah6o/dsh/desktop/linux/linux.exe \
  --output release/dsh-linux-$(uname -m)
release/dsh-linux-$(uname -m) desktop --demo
```

`sh scripts/build-desktop.sh run --demo` also dispatches to the Linux builder. An unbundled source CLI may use `dsh desktop --app-path /absolute/path/to/linux.exe`; it carries its own private CLI helper for native tool execution. Packaging preserves a single executable for `moon binstall`. Only the GUI child links X11/Wayland/text libraries; the CLI/web host remains usable without GUI libraries.

Release CI runs the actual packaged executable twice: Wayland through a private authenticated Xvfb plus nested Weston compositor, and native X11 directly against private authenticated Xvfb. Both use genuine keyboard/pointer input, approval, a workspace write, persisted reload and GPU frame readback. X11 additionally checks external Unicode clipboard round-trips, server-driven resize and WM_DELETE_WINDOW close; Wayland keeps its normal-shell resize/close pass. Tests also check termination and private-file cleanup on x86-64 and ARM64. A build-only check does not establish GUI runtime success.

## macOS


`Dsh.app` is a native GPUI/AppKit/Metal conversation window backed by the same
MoonBit runtime and durable session store as `dsh`, `dsh web`, and the local
MCP service. The app bundle is available for macOS 13 or later on Apple Silicon. Linux uses the embedded Linux executable described above; Windows desktop packages are not provided.

## Install the release app

Download `Dsh-macos-arm64.zip` from the [GitHub Releases page](https://github.com/f4ah6o/dsh.mbt/releases/latest),
unzip it, and move `Dsh.app` into `/Applications` or
`~/Applications`. The packaged app contains its desktop executable, private
`dsh` worker helper, GPUI native library, and third-party license notices.
The release bundle is ad-hoc signed after packaging. It is not Developer ID
signed or notarized.

macOS may block its first launch. Only if you verified the archive came from
the project's Releases page, Control-click `Dsh.app` in Finder and choose
**Open**. If macOS still blocks it, try opening the app once, then use System
Settings → Privacy & Security → **Open Anyway**. See [Apple's instructions for
opening apps safely](https://support.apple.com/en-gb/102445).

Launch `Dsh.app` from Finder, or use the installed `dsh` command:

```sh
dsh desktop --workspace /absolute/path/to/project \
  --data-dir /absolute/path/to/dsh-data
```

`dsh desktop` searches `/Applications/Dsh.app`, followed by
`~/Applications/Dsh.app`. Pass `--app-path /absolute/path/to/Dsh.app` to use a
bundle in another location. The launcher opens the app through macOS
LaunchServices and forwards the remaining desktop options as separate argument
values.

## Build and run from source

On macOS with the pinned MoonBit toolchain, installed MoonBit dependencies, and
Xcode command line tools installed, build a local bundle with:

```sh
sh scripts/build-desktop.sh --build
open -n -a "$PWD/_build/macos/Dsh.app" --args \
  --workspace /absolute/path/to/project \
  --data-dir /absolute/path/to/dsh-data
```

`sh scripts/build-desktop.sh --run` builds and opens the app. `--verify`
checks a real native frame, resize, close, and destroy lifecycle without
using the caller's workspace or data directory. The packaged app archive is
built separately from the source bundle; release packaging copies notices
before signing.

## Use the window

Choose or create a session in the left pane, type into the composer, and press
Enter or choose **送信 Enter** to send. Shift-Enter inserts a newline. Command-V
pastes text from the clipboard. While a response is running, use **キャンセル**
to cancel it. Review each requested tool in the transcript and choose Allow or
Deny before it runs. Use Up/Down or PageUp/PageDown to scroll transcript
history; mouse-wheel forwarding is not available in the current GPUI host. The
app checkpoints conversations in the same data directory used by other native
dsh surfaces; close other dsh processes that use that directory before
starting the desktop app.

Choose **設定** in the left pane to open the ChatGPT account page. It supports
host-browser sign-in, sign-out, refreshing the account's visible model list,
and selecting the model used for conversations. Tab / Shift-Tab or the arrow
keys move through settings controls; Escape or **閉じる** returns to the
conversation composer.

By default, the workspace is the current user's home directory and data is
stored in `<workspace>/.dsh.mbt`. Pass `--workspace` and `--data-dir` to select
explicit locations. Provider configuration uses the same `DSH_MODE`,
`DSH_MODEL`, `DSH_BASE_URL`, and API-key environment variables as the CLI. For
a network-free demo that exercises approval and a workspace write, start with
`dsh desktop --demo --workspace /absolute/path/to/scratch`.

The current GPUI macOS text host does not implement IME composition; paste
supports Japanese prompt entry. A few unsupported glyphs may render as a
fallback square, but prompt contents remain intact. The app's Japanese session
list, transcript, composer, and approval flow were exercised on macOS with the
offline demo; live provider calls and other macOS versions are separate checks.

For the hosted release build, the macOS CI job validates the app archive,
signature, bundled dependencies, license notices, and declared deployment
target. Metal window interaction requires an active macOS desktop and is
verified locally with the scripts above.


macOS の raw release CLI は、`moon binstall` の単一 executable に完全な署名済みアプリを含みます。`dsh desktop` は同梱版を優先して version/hash 別の owner-only cache (`~/Library/Caches/org.fu2hito.dsh/bundled-desktop/`) へ展開し、毎回署名を検証して、その正確な app path を LaunchServices で開きます。同時起動は抽出 lock で直列化し、別 version/hash の既存アプリを置き換えません。キャッシュの改変や不正な権限を検出した場合は停止します。CLI helper は payload のない別 executable のままアプリ内に保持します。

`--app-path /absolute/path/to/Dsh.app` は同梱版より優先します。payload を含まない source build は従来の `/Applications/Dsh.app` / `~/Applications/Dsh.app` を参照します。release app と CLI は ad-hoc signed です。Developer ID signing / notarization は含まず、quarantine を削除したり Gatekeeper の判定を回避したりしません。

macOS release の作成は app build → `scripts/package-macos-app.sh` → `scripts/package-macos-cli.sh` の順です。後者は専用の `MOON_CC` adapter で Mach-O resource section を作成してから最終署名を行います。`python3 scripts/test-macos-desktop-payload.py` は隔離した synthetic app を使い、抽出、同時実行、version 更新、署名、不正 archive / cache と quarantine 保持を確認します。
