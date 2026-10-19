# 0004: Windows x64 ネイティブランタイムと GPUI デスクトップの段階移植

Status: polished
Model: deepseek-flash
Created: 2026-10-18
Updated: 2026-10-18
Branch: feat/20261018-windows-native-desktop

## 概要

dsh.mbt を Windows 11 x64 で Node.js / WSL / 別ホストなしにローカル実行できるようにする。M1 で native runtime と CLI、M2 で GPUI desktop、M3 で zip / launcher / release を整備する。実装と検証は Windows 実機の DSH で行い、macOS host は計画と handoff だけを担当する。

## 背景

現行の native runtime は macOS / Linux を前提としている。

- [`runtime/host_os.c`](../../runtime/host_os.c) のファイル・ロック・プロセス処理は `__APPLE__` / `__linux__` 用で、それ以外は `ENOTSUP` スタブである。
- [`runtime/oauth_os.c`](../../runtime/oauth_os.c) は POSIX ヘッダを無条件に include しており、Windows native build の対象外である。
- [`desktop/`](../../desktop) は [`desktop/macos`](../../desktop/macos) と [`desktop/linux`](../../desktop/linux) だけを持ち、desktop は [`runtime/desktop.mbt`](../../runtime/desktop.mbt) の `NativeDesktop` 経由で native runtime を埋め込む。したがって GUI より先に runtime port が必要になる。
- [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) は Ubuntu のみ、[`scripts/native-release-plan.py`](../../scripts/native-release-plan.py) の release platform は `linux-x86_64` / `linux-aarch64` / `darwin-aarch64` のみである。
- gpui.mbt 0.9.0 の `windows.Host` は `platform.Backend`、`FrameReadback`、clipboard、DPI、`post_test_click` / `post_test_key`、可視ウィンドウの D3D11 backend を実装済みである。dsh の generic `desktop.Host` はこれをそのまま包める。
- Windows renderer の scene text 上限は 64 runs、1 run 4096 UTF-8 bytes、32 logical px、2048x128 clip である。dsh の settings overlay は現状この上限に近い。
- Windows 11 client は Yu Gothic / Yu Gothic UI を同梱する。Windows Server の hosted runner では不足する可能性がある。
- dsh の native desktop は Yami-kumo shared UI を実行経路に使っていない。Yami-kumo は browser UI の HTML API と CSS で使われており、この移植では変更を前提にしない。

基準 revision は macOS host で確認した main `cf68f68`（`refactor: resolve gpui.mbt from Mooncakes`）。Windows host では開始時に最新 main を fetch し、差分があれば rebase してから着手する。

## 問題

Windows native の build / run 経路が存在せず、次の制約がある。

- macOS host の MoonBit native toolchain では Windows の `dsh.exe` / `dsh-desktop.exe` を build できない。Windows 実機または Windows CI が必須である。
- SafeRoot の dirfd anchor、symlink 拒否、atomic write、ACL、single-writer lock に相当する Windows 実装がない。
- `dsh desktop` は macOS bundle と Linux embedded payload だけを扱い、Windows の launcher / packaging がない。
- Windows scene text の上限と、日本語 font fallback の実機確認がない。
- Windows で未対応の shell / MCP / LSP などを黙って成功扱いすると、data や外部 effect の整合性を壊す。

## 目標

Windows 11 x64 で、Node.js / WSL / remote service を要求せずに次を満たす。

1. M1: `dsh run --demo --approve-writes`、`dsh web --demo`、session store / host lock、read / write / edit / glob、demo / API-key provider が動く。
2. M2: GPUI の可視ウィンドウで日本語 UI、session、transcript、approval、workspace write、durable reload、resize / close が動く。
3. M3: `dsh-windows-x86_64.zip` を展開し、`dsh desktop --demo` から同じ経路を起動できる。
4. macOS / Linux の既存 runtime / desktop / web gate に回帰がない。
5. 未対応機能は typed error または非0終了で fail closed し、data / effect を変更しない。

最終像は M2 / M3 の local Windows desktop であり、M1 はその前提を満たす foundation である。

## 対象外

- shell / bash、grep。grep は hard worker memory limit を満たせないため、既存方針どおり Windows でも無効とする。
- external MCP、LSP、command hooks、subagents、ACP。
- ChatGPT SIWC / protected credential store。Windows では API-key provider と demo だけを対象とする。
- IME composition。paste は既存の clipboard 経路を使う。
- Windows ARM64、Windows 10 の正式資格付け、tailnet / remote service。
- CLI executable への desktop payload embed。M3 では別 exe の zip 配布とする。
- Yami-kumo shared UI の dsh native 導入。
- macOS / Linux の挙動変更。

## 提案する方針

### 実行ホストと handoff

実装・検証は Windows 11 x64 の DSH で行う。

- Windows host の前提: MSVC 2022 + Windows SDK（C/C++ workload）、Python 3.11+、Git、pinned MoonBit `0.10.15+943464bfa`、desktop session（RDP / console）、Japanese font。
- Windows host で `f4ah6o/dsh.mbt` を clone し、`feat/20261018-windows-native-desktop` を作る。
- 最初に `moon update && moon install`、`moon version --all`、`cl` の存在確認、変更前の `moon check --target native --deny-warn` を行い、baseline の失敗を記録する。
- この issue を `issues/polished/0004-windows-native-desktop.md` として記録し、draft PR を作る。
- macOS host ではこの issue の追加以外に実装せず、Windows build / GUI / font の成功を主張しない。
- 各 milestone は同じ branch 上の独立 commit / PR とし、最新 head の exact CI と evidence を記録する。M1 の未実行を M2/M3 の成功で補わない。

### M1: Windows native runtime foundation

#### C boundary

新規:

- `runtime/host_os_win32.c`: `_WIN32` 専用の OS boundary。
- `runtime/oauth_os_win32.c`: random / open URL / Unix time の Windows 実装。

変更:

- `runtime/host_os.c`: POSIX include と実装を `#if defined(__APPLE__) || defined(__linux__)` で囲み、fallback を `#elif !defined(_WIN32)` にする。`dsh_os_is_windows()` を追加する。
- `runtime/oauth_os.c`: POSIX 実装を guard し、Windows では `oauth_os_win32.c` が定義する。
- `runtime/signal_os.c`: `_WIN32` 分岐で `SetConsoleCtrlHandler` を実装する。CTRL_C / CTRL_BREAK を SIGINT、CTRL_CLOSE を SIGTERM 相当として記録する。
- `runtime/moon.pkg`: `native-stub` に `host_os_win32.c` / `oauth_os_win32.c` を追加する。
- payload C は既存の platform guard を維持し、Windows で stub がリンクされることを確認する。

`host_os_win32.c` の契約:

- handle table: Int32 の `fd` は process-global な bounded table index とし、WIN32 HANDLE を Int32 に切り詰めない。SRWLOCK で保護し、最大 entry 数を固定する。close で解放する。
- path: UTF-8 から UTF-16、`/` から `\`、`\\?\` / UNC の正規化。workspace-relative component は空・`.`・`..`・`\`・`:`（ADS）・`*?\"<>|`・control char・trailing space/dot・DOS device name を拒否し、長さ上限を設ける。
- reparse/symlink: すべての component で `FILE_ATTRIBUTE_REPARSE_POINT` を拒否し、open 時に `FILE_FLAG_OPEN_REPARSE_POINT` を使う。root も directory / non-reparse を確認する。
- SafeRoot: `open_root`, `close`, `root_matches`, `mapping_matches`, `open_file`, `read_fd`, `stat_fd`, `stat_root`, `list_dir`, `unlink`, `create_exclusive`, `atomic_write`, `sync_directory`, `set_root_mode`。
- identity: volume serial + file index を `FileVersion` の device / inode に写す。size、mtime / ctime、mode、uid / gid を POSIX 相当の 10 fields に写し、`same()` が read 前後で一致することを保証する。
- atomic write: 同一 directory に `CREATE_NEW` の temp を作り、write・flush・close する。expected version は既存 target の file ID / size / mtime で照合する。target があれば `ReplaceFileW`、なければ `MoveFileExW(MOVEFILE_WRITE_THROUGH)` を使う。前後で mapping を再検証し、不整合時は temp と commit 済み file の掃除を best-effort で行う。
- ACL: `set_root_mode(0700)` は current user のみを許可する protected DACL を設定する。mode 0600 の create / atomic write は current user のみの DACL を設定し、`stat` は owner SID と DACL から 0600 / 0644 を返す。設定・照合に失敗したら fail closed する。
- error mapping: Win32 error を dsh が使う POSIX 相当 code（`2 ENOENT`, `5 EIO`, `9 EBADF`, `13 EACCES`, `17 EEXIST`, `22 EINVAL`, `28 ENOSPC`, `95 ENOTSUP`, `116 ESTALE`）へ変換する。予期しない code は `EIO` と診断に落とす。
- OS services: `uid`（current user SID hash）, `pid`, `executable_path`, `hostname`, `timestamp`（`YYYY-MM-DDTHH:MM:SSZ`）, `stdin_is_terminal`, `process_alive`（`OpenProcess` + `GetExitCodeProcess`）, `process_group_alive`, `kill_process`, `kill_process_group`, `hard_worker_memory_supported=0`。`child_exit_state` / `exec_worker` は M1 では `ENOTSUP` とし、shell / MCP / LSP / hooks / subagents を gate する。
- crypto: `dsh_crypto_sha256` を BCrypt で実装する（remote cursor / digest に必須）。`dsh_crypto_verify_rs256` も BCrypt で実装し、SIWC 無効時も API 契約を壊さない。
- link: `bcrypt.lib` / `advapi32.lib` / `shell32.lib` などを C 側の `#pragma comment` で明示する。MSVC 前提を docs に記す。

`oauth_os_win32.c`:

- `dsh_auth_random`: `BCryptGenRandom`。
- `dsh_auth_open_url`: `ShellExecuteW(L"open", ...)`。http / https のみ、長さ上限あり。
- `dsh_auth_unix_time`: `time(NULL)`。

#### MoonBit runtime / CLI

- `runtime/host_os.mbt`: `native_os_is_windows()` FFI、`native_path_is_absolute`、`native_path_normalize`、`native_home_dir` を追加する。Windows は drive letter / UNC、`\` から `/`、`\\?\` 除去、drive letter の正規化を行う。`SafeRoot::open` と `native_executable_path` の `/` 前提を platform-aware にする。
- `runtime/store.mbt`: data_dir の絶対判定、`current_dir + "/" + data_dir`、`realpath` 結果を normalize する。`USERPROFILE` / `USERNAME` fallback を追加する。
- `runtime/runtime.mbt`: `workspace_path` / `worker_launcher` を normalize する。Windows profile で `allow_shell=true`、`mcp_config_path`、`lsp_config_path`、`hooks_config_path`、`enable_subagents` を `Err` にする。ACP / `mcp` subcommand は `runtime/main.mbt` で gate し、data / effect を変更せず非0終了する。
- `runtime/main.mbt`: `--internal-worker` の absolute workspace 判定を platform-aware にし、Windows では worker 経路を gate する。
- `runtime/oauth.mbt`: `NativeAuth` に Windows 用 in-memory mode を追加する。`siwc-auth.json` を read / write せず、sign-in / refresh / sign-out / model selection は typed unsupported error にする。API-key / demo の provider route は変更しない。`persist_locked` は Windows で no-op にする。
- `runtime/desktop.mbt` / `runtime/desktop_launch.mbt`: M1 ではコンパイルを維持する。Windows の `desktop` 起動は M3 で実装し、それまでは明示的な unsupported error にする。
- `runtime/acp_service.mbt` / `runtime/acp_sessions.mbt`: absolute path 判定を helper に置換する。ACP 自体は M1 で拒否する。
- `runtime/tools.mbt`: shell / grep の既存 unsupported error を維持する。grep は `os_hard_worker_memory_supported=false` により明示 error を返す。
- `cmd/dsh` / `native`: Windows native target で build できることを確認する。build 設定の追加は必要最小限にする。

#### Windows profile の挙動

- `dsh run --demo --approve-writes`、`dsh web --demo`、`dsh --help` は動作する。
- `dsh run --allow-shell`、`--mcp-config`、`--lsp-config`、`--hooks-config`、`--enable-subagents`、`dsh acp`、`dsh mcp` は非0終了 + stderr の明示 message とし、data directory / session / lock を変更しない。
- `grep` は起動自体を止めず、tool 呼出し時に既存の「hard worker memory limit がないため無効」error を返す。
- SIWC は `auth` projection で未接続のままにする。browser / desktop の ChatGPT 操作は typed unsupported にする。
- shell / MCP / LSP / hooks / subagents を含む保存済み session は Windows で開けない可能性がある。Windows profile の制約を docs に記録し、store を書き換えない。

#### M1 tests / CI

追加 test:

- `runtime/windows_wbtest.mbt`（`#cfg(platform="windows")` または Windows 専用 filter）:
  - path absolute / normalize / component validation。
  - SafeRoot の read / write / stat、nested dir、atomic write、expected version conflict、exclusive create / lock、unlink、list_dir。
  - reparse point / symlink 拒否（作成できる環境で実施。作成できなければ NOT RUN と記録し、成功扱いにしない）。
  - root ACL / 0600 file DACL / owner / permission。
  - `NativeRuntime::open` + demo turn + approval + workspace write + close / reopen。tool effect の replay がないこと。
  - unsupported options が no-mutation で失敗すること。
- `runtime/safety_fs_fixture_wbtest.mbt` などの POSIX-only fixture は、Unix process / shell / symlink 前提のものだけ `#cfg(not(platform="windows"))` で除外する。product failure を test 除外で隠さない。Windows 版の SafeRoot / store test を別途追加する。
- `scripts/test-windows-runtime.py`:
  - temp workspace / data dir。
  - `dsh.exe run "Create and verify a durable file." --demo --approve-writes --json` が exit 0、status completed、`native-demo.txt` を作成すること。
  - 同一 data dir で `dsh.exe prune-session <id>` が store reopen に成功し、replay しないこと。
  - `dsh.exe web --demo --port 0` を起動し、出力 URL を parse して `/` を HTTP GET し、その後 bounded shutdown すること。
  - 未対応 option / subcommand の fail-closed。
  - `sessions.json` / `host.lock` の残存・消去。

Windows host local gate:

```sh
moon check --target native --deny-warn
moon test engine provider plugins auth protocol client app ui --target native --deny-warn
moon test runtime --target native --deny-warn --filter "Windows"
moon build --target native --release cmd/dsh
python scripts/test-windows-runtime.py
cl /W4 /std:c11 /utf-8 /c runtime/host_os_win32.c
```

Hosted `.github/workflows/windows-native.yml`（または `ci.yml` の job）:

- `runs-on: windows-latest`、pinned MoonBit + MSVC、`moon update` / `moon install`。
- 上と同じ check / test / build / Python smoke。
- log / `sessions.json` / CLI output を artifact 化する。
- M1 では desktop build はまだ行わない。

#### M1 docs / changelog

- `README.md`: Windows profile の範囲と未対応機能。
- `docs/desktop.md`: Windows は M2 まで未提供、M1 は runtime foundation。
- `docs/native-runtime.md`: Windows の path / ACL / unsupported options / data directory 制約。
- `docs/port-status.md`: Windows native runtime の bounded subset。
- `docs/verification.md`: M1 の exact command / result / NOT RUN（Windows host と hosted CI を分ける）。
- `CHANGES.md`: 実装時に Added / Changed / Security / Migration。

### M2: Windows GPUI desktop

新規:

- `desktop/windows/main.mbt`: `@windows.Host::start()` で dsh `Host` を構築する。
  - `backend: host`
  - `asynchronous_frames: true`
  - `text_input_events: true`
  - `control_shortcuts: true`
  - `focus_changed` / `initialize_window` は no-op
  - clipboard は `host.read_clipboard` / `write_clipboard`
  - `capture_frame: @testing.capture_frame(host, window)`
  - `post_test_click: host.post_test_click`
- `desktop/windows/moon.pkg`: `f4ah6o/gpui/windows`, `platform/testing`, `desktop`, `runtime` を import する。`pkgtype(kind: "executable")`。
- `desktop/windows/font_wbtest.mbt`: Windows 専用。`@windows_text.measure` / `admit_scene_text_run_at` で `"日本語"` を検査し、失敗時は「Japanese font prerequisite not met」で fail する。
- `scripts/build-desktop-windows.ps1`: `Build` / `Smoke` / `E2E` mode。`moon build --target native --release desktop/windows cmd/dsh`、exe 存在確認、`DSH_NATIVE_WORKER_BIN` 設定、staging。
- `scripts/test-windows-desktop.py`: marker / PPM / workspace / settings を検査する。

変更:

- `desktop/app_config.mbt`: Windows home（`USERPROFILE`）と path normalization、Windows の usage / Settings 説明。
- `desktop/app_auth.mbt`: Windows では sign-in / refresh / sign-out / model select を typed error にし、Settings に「Windows profile では ChatGPT sign-in 非対応」を表示する。
- `desktop/view.mbt`: scene text budget を導入する。
  - `TextItem` / `TextRunItem` の count を返す helper。
  - settings open 時は occluded な conversation layer を描画しない（sidebar + settings のみ）。
  - 1 run を 4096 UTF-8 bytes 以下に Unicode scalar 境界で clip する（全 platform 共通の安全策）。
  - font size <= 32、width <= 2048、runs <= 64 を test で保証する。
- `desktop/view_wbtest.mbt`: empty / long transcript / settings 7–9 models / pending approval の scene で budget を検証する。
- `desktop/app_smoke.mbt`: Windows の `--smoke` / `--offline-e2e` を既存マーカーで実行する。`GPUI_NATIVE_E2E=1` の `post_test_click` を使う。

Windows host / CI gate:

- font probe。不足時は `Language.Fonts.Jpan~~~und-JPAN~0.0.1.0` などを導入して再 probe する。導入不能なら GUI gate を NOT RUN として失敗させ、成功扱いにしない。
- `moon build --target native --release desktop/windows cmd/dsh`
- `dsh-desktop.exe --smoke --workspace ... --data-dir ...`
- `GPUI_NATIVE_E2E=1 dsh-desktop.exe --offline-e2e --workspace ... --data-dir ... --frame-output ...`
- `python scripts/test-windows-desktop.py`
- logs / PPM / sessions を artifact 化する。

M2 acceptance:

1. visible Windows window が開き、initial frame が完成する。
2. demo prompt 送信 → awaiting approval → Allow click → `native-demo.txt` 作成 → completed。
3. close / reopen で session が残り、外部 effect を replay しない。
4. initial / transcript / settings の frame が非空で、日本語 heading / transcript / settings の pixel check が PASS。
5. scene text budget test が PASS。
6. macOS / Linux desktop test に回帰がない（hosted CI）。
7. Windows IME は未対応、paste は動作、と docs に明記する。

### M3: packaging / launcher / release

新規:

- `scripts/build-desktop-windows.ps1` の `Package` mode、または `scripts/package-windows-desktop.ps1`:
  - `release/dsh-windows-x86_64/` に `dsh.exe`, `dsh-desktop.exe`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `licenses/*`, `README-windows.md` を置く。
  - build cache / credentials / `.dsh.mbt` を含まないことを検証する。
  - `dsh-windows-x86_64.zip` を作成し、SHA-256 を log に記録する。
- `scripts/smoke-release-windows.ps1`: zip 展開先（space / non-ASCII path を含む）で CLI / web / desktop を smoke する。
- `.github/workflows/ci.yml` または `windows-native.yml` に package + smoke job。
- `publish-native.yml` に `windows-latest` / `windows-x86_64` を追加する。

変更:

- `runtime/desktop_launch.mbt` の Windows branch:
  - `--app-path` は native absolute path として受理し、`.exe` の存在 / regular file を確認する。
  - `--app-path` 未指定時は CLI と同じ directory の `dsh-desktop.exe` を探索する。
  - `DSH_NATIVE_WORKER_BIN` 未設定時は current CLI executable を設定する。
  - `@process.run` で desktop を起動し、終了 status を CLI に返す。
  - 見つからない / 起動不能は actionable stderr + 非0。
- `runtime/desktop.mbt`: `NativeDesktop::open` の Windows sibling worker discovery（`dsh-desktop.exe` → `dsh.exe`）。macOS bundle 判定は Windows で実行しない。
- `scripts/native-release-plan.py`:
  - `PLATFORMS` に `windows-x86_64` を追加する。
  - Windows asset は `dsh-windows-x86_64.zip` として扱う（raw `dsh-windows-x86_64` ではない）。
  - `scripts/test-native-release-plan.py` の expected assets / matrix を更新する。
- `.github/native-release.json` に `windows-x86_64` を追加する（release 時）。
- `publish-native.yml`: Windows では apt / Linux desktop steps を skip し、`pwsh` で build / package / smoke する。artifact と publish の expected assets を zip に合わせる。
- `docs/desktop.md` / `README.md` / `CHANGES.md` / `docs/releases/<version>.md`: Windows の install / run / 制約 / 未署名注意。

M3 acceptance:

1. clean Windows checkout から zip を作成できる。
2. zip を別 directory に展開し、`dsh.exe run --demo --approve-writes`、`dsh.exe web --demo`、`dsh.exe desktop --offline-e2e ...` が成功する。
3. `dsh.exe desktop --app-path ...` と sibling discovery の両方が動く。
4. zip に build / cache / credential がなく、license / notices が含まれる。
5. release plan test が PASS。macOS / Linux asset は不変。
6. exact-head CI / evidence を記録し、未実行を PASS と書かない。

### gpui.mbt / Yami-kumo への変更方針

- M1 / M2 の基本線では gpui.mbt / Yami-kumo を変更しない。dsh の Windows backend は既存 gpui public API で構成する。
- 次の場合だけ upstream 変更を検討する。
  1. Windows の system Japanese font で `@windows_text` の measure / admit が失敗し、FOD / font 導入でも解決しない。
  2. dsh の scene budget を 64 runs 以下に収められず、汎用の scene text budget / batching API が必要。
- その場合の gpui 変更は、dsh 固有の文字列・session・provider 概念を含まない public API とし、default behavior を変えず、Windows / non-Windows の standalone test を持つ。Mooncakes release と dsh pin 更新（`moon.mod`, `scripts/verify-env.mjs`, licenses）を同じ変更単位で行う。
- Yami-kumo は今回の native path にないため変更しない。将来 shared UI を dsh に導入する場合も、dsh 専用 component を追加せず、汎用 contract / fixture を先に定義する。
- 「dsh で必要になったから」だけを理由に、dsh 固有の挙動を gpui / Yami の public API に追加しない。

### データ / 公開 API / セキュリティ

- Native envelope schema（`dsh.mbt-session-v1`）/ event / protocol は変更しない。
- 新規 public API は dsh 内の path helper / OS detection 程度とし、gpui / Yami の public API 変更はない（M1 / M2 基本線）。
- Windows の data directory は current user のみの DACL とする。workspace tool は reparse point / ADS / `..` / reserved name を拒否する。
- Windows は POSIX の dirfd anchor と同じ保証を path-based に近似する。同じ user の最終 check-to-rename race は sandbox ではないことを docs に明記する。
- SIWC protected store は Windows で無効にする。既存 `siwc-auth.json` を Windows で read / write しない。API-key / demo のみ。
- 既存 POSIX data dir を Windows で開く場合の ACL / 相対 path / lock の制約を docs に記す。必要なら backup を要求する。
- Windows executable は ad-hoc / unsigned とする。SmartScreen / quarantine の注意を docs に記す。

## 受け入れ条件

- [ ] Windows host の clean checkout で `moon check --target native --deny-warn` が 0 errors / 0 own warnings。
- [ ] `dsh run --demo --approve-writes` が completed となり、`native-demo.txt` を作成し、`prune-session` で reopen できる。
- [ ] `dsh web --demo` が loopback で起動し、`/` を返す。
- [ ] SafeRoot / atomic write / lock / reparse / ACL / path tests が PASS。
- [ ] 未対応 option / subcommand が no-mutation で fail closed する。
- [ ] Windows CI で M1 の必須 gate が exact head で PASS。
- [ ] visible Windows window が open / resize / close し、frame evidence が残る。
- [ ] Windows desktop で demo send / approve / workspace write / completed / reopen が動く。
- [ ] initial / transcript / settings frame の日本語 pixel check と scene text budget test が PASS。
- [ ] `dsh-windows-x86_64.zip` を clean checkout から作成し、別 directory で CLI / web / desktop を起動できる。
- [ ] `dsh desktop --app-path` と sibling discovery の両方が動く。
- [ ] macOS / Linux の既存 runtime / desktop / web gate に回帰がない。
- [ ] `CHANGES.md` と docs に Windows profile の範囲 / 未対応 / migration 制約が記録され、未実行を PASS と書いていない。

## テスト計画

実行する gate:

```sh
# Windows host / windows-latest
moon update
moon install
moon check --target native --deny-warn
moon test engine provider plugins auth protocol client app ui --target native --deny-warn
moon test runtime --target native --deny-warn --filter "Windows"
moon build --target native --release cmd/dsh
python scripts/test-windows-runtime.py
```

```sh
# M2
moon test desktop/windows --target native --deny-warn --filter "font"
moon build --target native --release desktop/windows cmd/dsh
dsh-desktop.exe --smoke --workspace <tmp> --data-dir <tmp>
GPUI_NATIVE_E2E=1 dsh-desktop.exe --offline-e2e --workspace <tmp> --data-dir <tmp> --frame-output <tmp>/frame.ppm
python scripts/test-windows-desktop.py
```

```sh
# M3
pwsh -NoProfile -File scripts/build-desktop-windows.ps1 -Mode Package
pwsh -NoProfile -File scripts/smoke-release-windows.ps1 <zip> <tmp>
python3 scripts/test-native-release-plan.py
```

- macOS / Linux は既存 CI の `npm test` / `moon test` / desktop tests を実行し、Windows 変更が POSIX code に入っていないことを確認する。
- 実機がない環境の確認は NOT RUN と記録する。build 成功や synthetic input を physical input / IME / font の合格に置き換えない。
- 失敗時は exact command、candidate SHA、artifact、PASS / FAIL / NOT RUN、未実行理由を残す。

## リスク

- Windows C boundary の security / atomicity bug。SafeRoot / reparse / conflict tests で検出し、失敗時は fail closed する。POSIX code は guard 以外変更しない。
- ACL 設定失敗。data directory open / 0600 test で検出し、広い ACL で継続しない。
- Windows host / runner に日本語 font がない。font probe で検出し、FOD / font 導入不能なら M2 を NOT RUN にする。
- 64 text runs 超過。scene budget test と present error で検出し、occluded layer 削除で収める。必要なら汎用 gpui API を検討する。
- CI GUI flakiness。bounded retry と evidence を分け、fake PASS にしない。
- POSIX code の回帰。Windows code を別 file / `_WIN32` guard に限定し、macOS / Linux CI を維持する。
- scope creep（shell / MCP / LSP）。M1 / M2 では明示的に拒否し、後続 milestone で個別に扱う。

rollback は Windows 専用 file / `_WIN32` guard / release asset の追加に限定し、macOS / Linux の挙動を戻す必要がない構造にする。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- Added: Windows 11 x64 の bounded native runtime と GPUI desktop（demo / API-key、read / write / edit / glob、durable session / approval / reload）。
- Changed: Windows 用 path / OS detection / unsupported option diagnostics。macOS / Linux の既存経路は不変。
- Security: Windows data directory の current-user DACL、reparse / ADS / reserved name 拒否、atomic write の前後検証。SIWC は Windows で無効。
- Migration: Windows は API-key / demo のみ。SIWC protected store と POSIX data directory の再利用制約を docs に記す。zip は unsigned。
- この issue の追加だけでは `CHANGES.md` を変更しない。実装 commit で上記を反映する。

## 注記

- この issue は Windows 実機 DSH での実装を前提とする自己完結した handoff である。macOS host では issue の追加以外に実装・build・GUI 検証を行わない。
- 基準 revision は `cf68f68`。Windows host では開始時に最新 main を確認し、差分があれば rebase する。
- 実装 branch は `feat/20261018-windows-native-desktop`。この issue の追加 commit は docs branch で行う。
- dsh の既存 issue は連番ファイル名（`0001`–`0003`）なので、`local_issues.py reserve-path` の date-based 候補ではなく `0004-windows-native-desktop.md` を使う。必須 field / section は同 CLI の `validate` に合わせる。
- related: [0001 upstream parity](../open/0001-upstream-parity.md), [0003 iOS / tailnet roadmap](../open/0003-moonbit-native-ios-tailnet-roadmap.md), [docs/port-status.md](../../docs/port-status.md), [docs/desktop.md](../../docs/desktop.md), [docs/native-runtime.md](../../docs/native-runtime.md).
- gpui.mbt / Yami-kumo の upstream 変更は、この issue の dsh 固有要件を public API に持ち込まない。汎用機能として独立 issue / test / release を持つ場合だけ行う。
