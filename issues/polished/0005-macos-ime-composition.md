# 0005: macOS desktop IME composition

Status: implemented / real Kotoeri qualification open
Created: 2026-10-19
Updated: 2026-10-19
Branch: main

## 概要

dsh の macOS native desktop composer で、`DSH_DESKTOP_IME=1` の opt-in により gpui.mbt の bounded
`NSTextInputClient` transport を使った IME composition を提供する。preedit の
表示、commit / cancel、候補ウィンドウの caret 追従、Enter / Escape / 送信の
解決を扱う。dsh 専用の upstream API は追加せず、gpui.mbt 0.10.0 の汎用
composition event を consumer として使う。

## 背景

- dsh は macOS / Linux / Windows の desktop で IME composition 未対応と記録していた。
- upstream parity の受入条件に IME 実機検証が残っている。
- gpui.mbt 0.9.0 の macOS host は keyDown を KeyPressed に変換するだけで、
  `NSTextInputClient` を持たなかった。
- 既存の gpui draft PR #89 は full text-field / IME slice で、main との conflict
  と実機 harness の欠落があり、この bounded increment の前提にしない。

## 実装

### gpui.mbt 0.10.0

- `primitives.CompositionEvent` と `platform.EventKind::Composition`。
- macOS `Host::set_text_composition` / `set_text_composition_caret` /
  `finish_text_composition`。
- `NSTextInputClient`、preedit / commit 上限、UTF-16 cursor 検証、
  candidate caret、Enter / Escape の二重配送防止。
- opt-in `Host::post_test_composition` と native E2E。

### dsh

- `desktop/host.mbt` の capability / callback。
- macOS entrypoint の接続。Windows / Linux / X11 は typed unsupported。
- `DesktopComposition` state、preedit overlay、caret underline、候補 caret。
- 送信時の commit-then-send、focus / Settings / New / session switch / approval /
  Command shortcut での cancel。
- synthetic composition を `--offline-e2e` に追加し、成功 marker に
  `"ime_composition":true` を記録。

## 対象外

- Windows / Linux / X11 の IME。
- full editor、selection、undo、reconversion、attributed replacement range。
- Yami-kumo native UI への入力 component 追加。IME は platform host の責務で、
  dsh 専用 component は追加しない。

## 受入

- [x] gpui portable / macOS tests と native E2E。
- [x] dsh desktop unit / view tests。
- [x] synthetic desktop E2E（commit / cancel / caret / reload）。
- [ ] 実機 Kotoeri の composition / conversion / commit / cancel。
- [ ] 複数 display / Retina での candidate window 位置。
- [ ] Windows / Linux IME。

実機 Kotoeri は NOT RUN。headless harness は window input context で Kotoeri を
選択できたが、process を active application にできず composition event が
発生しなかった。synthetic pass を physical IME pass として扱わない。

## 検証コマンド

```sh
# gpui
moon check --target all --deny-warn
moon test platform/macos platform --target native --deny-warn
xcrun clang -fobjc-arc -Wall -Wextra -Werror -DGPUI_TESTING \
  tests/native/macos_e2e.m platform/macos_text/core_text.c \
  -framework AppKit -framework QuartzCore -framework Metal \
  -framework CoreText -framework CoreGraphics -framework CoreFoundation \
  -o /tmp/gpui_macos_e2e
GPUI_NATIVE_E2E=1 /tmp/gpui_macos_e2e

# dsh
moon test desktop --target native --deny-warn
sh scripts/build-desktop.sh --test-hooks
GPUI_NATIVE_E2E=1 _build/macos/Dsh-Test.app/Contents/MacOS/dsh-desktop \
  --offline-e2e --workspace <tmp> --data-dir <tmp> --frame-output <tmp>/frame.ppm
```

詳細な実測結果は[検証記録](../../docs/verification.md)に記録する。

## リスク

- AppKit の candidate window 位置は複数 display / Retina で未検証。
- `NSTextInputClient` の reconversion / attributed range は未対応。
- 実機 IME の受入がない限り、README で「日本語 IME 対応」と表現しない。
- gpui 0.10.0 の `EventKind` 追加は exhaustive match に影響する。
