# Native macOS desktop app

`Dsh.app` is a native GPUI/AppKit/Metal conversation window backed by the same
MoonBit runtime and durable session store as `dsh`, `dsh web`, and the local
MCP service. It is available for macOS 13 or later on Apple Silicon. Linux and
Windows desktop packages are not provided.

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

On macOS with the pinned MoonBit toolchain, Git submodules, and Xcode command
line tools installed, build a local bundle with:

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
