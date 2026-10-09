# dsh.mbt

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) の MoonBit 移植です。session、event log、agent / tool loop、承認、provider protocol、HTTP/MCP service、CLI、browser UI の product logic は MoonBit で動きます。native executable が唯一の product runtime です。Node.js は build/check/test tooling にだけ使い、browser JavaScript と service worker は MoonBit compiler の生成物です。

**現在は最初の動作する移植版です。** browser / CLI と macOS native desktop app から会話し、workspace tool を実行して履歴を保存できます。Session v4 は明示的な read-only import に限って対応し、Cordis / npm plugin 互換、subagent、live compaction などは未実装です。対応範囲と差分は[移植状況](docs/port-status.md)、今回の native / SIWC / iOS 実装は[実装状況](docs/implementation-status.md)を参照してください。

## Build and run

必要なのは固定版 MoonBit toolchain、Git、C compiler と submodule です。Yami-kumo は Mooncakes からインストールします。Node.js / npm はテストや開発スクリプトに使いますが、product build と runtime には不要です。

```sh
git clone --recurse-submodules https://github.com/f4ah6o/dsh.mbt.git
cd dsh.mbt

# .moonbit-version と同じ compiler / core を導入
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- '0.10.14+7d59c7ec9'
export PATH="${MOON_HOME:-$HOME/.moon}/bin:$PATH"

moon update
moon install
sh scripts/build.sh
```

`sh scripts/build.sh` は MoonBit browser module と service worker、Mooncakes から導入した Yami-kumo CSS を生成・配置し、すべての browser assets を `runtime/bundled_web.mbt` に埋め込んでから native runtime と `dsh` CLI を build します。Node/npm は使いません。fresh checkout の `npm run check` は compiler 生成 assets の freshness check を skip し、assets が build 済みなら embedded bundle との一致も確認します。`web/moonbit/browser.js` と `web/sw.js` は compiler 生成物で Git 管理せず、build 後も browser の runtime URL は同じです。

API key を使わない browser demo は native service を loopback で起動します。

```sh
moon run native --target native --release -- \
  web --demo --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project --port 3210
```

`http://127.0.0.1:3210` を開きます。demo provider は外部 request を送りません。browser UI から workspace tool を試せます。

### Provider configuration

DeepSeek を使うには API key を environment に渡し、native service を起動します。

```sh
export DEEPSEEK_API_KEY='your-api-key'
moon run native --target native --release -- \
  web --workspace /absolute/path/to/project --data-dir /absolute/path/to/dsh-data
```

既定は `deepseek-flash` と Messages API の `https://api.deepseek.com/anthropic` です。OpenAI Chat Completions 互換 endpoint は model を明示します。

```sh
export OPENAI_API_KEY='your-api-key'
moon run native --target native --release -- \
  web --mode openai --model MODEL --base-url https://YOUR-PROVIDER/v1 \
  --workspace /absolute/path/to/project
```

`DSH_API_KEY`、`DSH_MODE`、`DSH_MODEL`、`DSH_BASE_URL` も使えます。`--base-url` の `/v1` は重複させず結合します。OpenAI Responses は Platform API key と ChatGPT SIWC をサポートします。SIWC の credential は owner-only native store に保存します。実アカウント smoke は任意で、通常の検証では実行しません。詳細は[native runtime guide](docs/native-runtime.md)を参照してください。

## CLI

native executable は `run`、`import-session`、`prune-session`、`fork-session`、`web`、`mcp` subcommand を提供します。MoonBit から直接起動する例です。

```sh
moon run native --target native --release -- \
  run 'この workspace のファイルを確認してください' --workspace /absolute/path/to/project --json

moon run native --target native --release -- \
  import-session /path/to/session.v4.jsonl --workspace /absolute/path/to/project --json

moon run native --target native --release -- \
  prune-session SESSION_ID --threshold-chars 8192 --head-chars 4096 --tail-chars 1024

moon run native --target native --release -- \
  fork-session SESSION_ID --workspace /absolute/path/to/project

moon run native --target native --release -- --help
```

`run` は完了した会話を出力し、`--json` は session JSON を返します。`--data-dir` を省略すると workspace の `.dsh.mbt` を使います。同じ data directory を複数 runtime で同時に開けません。CLI の write / edit / bash は承認が必要です。対話端末では Allow を尋ね、非対話では turn を cancel して失敗します。`--approve-writes` と `--approve-tools write,edit` は明示した startup approval policy です。bash の自動承認には `--allow-shell --approve-tools bash` の両方が必要です。

`import-session` は bounded な upstream Session v4 JSONL を検証し、read-only history として保存します。記録された tool、permission、preset は実行や有効化に使いません。`fork-session` は settled な未 import session から idle child を作り、provider / tool / approval / retry を再生しません。native CLI は gpui MCP protocol を `mcp` subcommand から newline-delimited stdio で公開します。

### `dsh` としてインストール

Mooncakes registry から `dsh` command package を install できます。次の例では `dsh` を Moon の既定の `bin` directory に配置します。

```sh
moon install f4ah6o/dsh/cmd/dsh@0.1.2
export PATH="${MOON_HOME:-$HOME/.moon}/bin:$PATH"
dsh --help
```

再帰 submodule を含む checkout から Moon CLI の source install を実行できます。次の例では `dsh` を Moon の `bin` directory に配置します。

```sh
git clone --recurse-submodules https://github.com/f4ah6o/dsh.mbt.git
cd dsh.mbt
moon update
mkdir -p "${MOON_HOME:-$HOME/.moon}/bin"
moon install ./cmd/dsh --bin "${MOON_HOME:-$HOME/.moon}/bin"
export PATH="${MOON_HOME:-$HOME/.moon}/bin:$PATH"
dsh --help
dsh web --demo --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project --port 3210
```

`dsh web` は browser assets を executable から配信するため、checkout 外から起動できます。埋め込み bundle は source install と release binary の両方に含まれます。`--assets-dir /path/to/web` を明示するとその directory の assets で override できます。source install には再帰 submodule clone を使ってください。

事前に upstream [`moon-binstall`](https://github.com/f4ah6o/moon-binstall) を PATH に導入していれば、GitHub Release の対応 binary を `moon binstall dsh` で install できます。公開 asset は Linux x86-64 / ARM64 と macOS Apple Silicon 向けです。

### macOS native app

GitHub Release の `Dsh-macos-arm64.zip` に macOS 13+ / Apple Silicon 向けの `Dsh.app` を含めます。`/Applications` または `~/Applications` に置くと、`dsh desktop` から起動できます。インストール、source build、UI と現在の IME 制約は[native desktop guide](docs/desktop.md)を参照してください。release app は ad-hoc signed で、Developer ID signed / notarized ではありません。

## Browser UI and data

Browser UI は MoonBit module から生成される JavaScript と service worker、Mooncakes の `f4ah6o/yami_kumo@0.1.0` から導入する styles で構成します。これらと HTML、manifest、icon を `dsh` executable に埋め込み、`dsh web` から配信します。React や Node.js host は product runtime に含みません。日本語 UI は会話検索、responsive navigation / details drawer、session details、fork、tool output pruning を提供します。ChatGPT の sign-in、model refresh / selection、sign-out は Settings にあります。設定は browser local storage、session は native data directory に保存し、公式 API に履歴をアップロードしません。iOS UI は別の受け入れ範囲です。

Native v1 は versioned data envelope と command receipt を保存します。初回起動時に対応する legacy snapshot / Session v4 input を native envelope に一方向変換します。旧版 Node host はこの envelope を読めないため、upgrade 前に data directory を backup してください。旧 Node host はこの版では配布しません。migration の境界は[native runtime guide](docs/native-runtime.md#data-directory-compatibility)に記載しています。

`prune-session` は imported ではない idle / completed session の長い tool result を、将来の provider context 向けに縮めます。既定値は trigger 8,192、head 4,096、tail 1,024 Unicode code points です。元の output と transcript は保持します。browser の **Trim outputs** と `session_prune_tool_results` API からも実行できます。自動 context compaction、token meter、summary、spill は未実装です。詳しくは[アーキテクチャ](docs/architecture.md)を参照してください。

## Provider retry

一時的な provider failure は、同じ未完了 request を最大 5 回まで再試行します。backoff は 500 ms から始まり、最大 10 秒まで deterministic exponential に増えます。`--max-retries 0` で無効化できます。HTTP 408 / 429 / 5xx、timeout、空応答、一部の transport failure を対象にし、authentication、その他の 4xx、malformed response は再試行しません。受理済み stream delta 後も再試行しません。schedule と start は event log に checkpoint し、restore は未確定 request を再送しません。retry は provider に新しい request を送り、再課金される場合があります。upstream と異なり jitter は使いません。

## Tools and approvals

| Tool | Principal arguments | Run policy |
| --- | --- | --- |
| `read` | `file_path`, optional `offset`, `limit` | Automatic |
| `glob` | `pattern`, optional `path` | Automatic |
| `grep` | `pattern`, optional `path` | Automatic, bounded search/output |
| `write` | `file_path`, `content` | Per-call approval |
| `edit` | `file_path`, `old_string`, `new_string`, optional `replace_all` | Per-call approval |
| `bash` | `command`, optional `description`, `timeout` | `--allow-shell` and per-call approval |

File tools stay within the workspace and reject traversal, symlinks, and protected runtime data. Native glob implements a documented subset. Regex grep is disabled on macOS when a hard worker memory limit cannot be enforced. Bash runs as a normal OS child process in the workspace; there is no OS filesystem/network sandbox, so enable it only when its host-user permissions are appropriate.

## API and verification

Browser and CLI use the same MoonBit engine and capability registry. The native loopback service exposes `/api/v1/*`, `/api/call`, `/api/metadata`, and `/mcp`. MCP uses gpui's fixed **`2026-07-28` / `server/discover`** protocol without translating the older `initialize` handshake. See [architecture](docs/architecture.md) for request and safety boundaries.

```sh
npm ci                    # test-only Node/Playwright tooling
npm test                  # build first, then format/check, MoonBit matrix, browser modules and native browser smoke
npm run mutation:list     # list production plugin mutation cases
npm run mutation          # run the pinned turtles mutation gate
```

The portable MoonBit packages run on JS, native, Wasm, and Wasm GC. CI separately proves that the product build and native verification work with Node.js and npm absent. The real Chromium smoke uses a temporary native demo service and workspace; set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` when Chromium is installed outside Playwright's default cache. Test fixtures are keyless and local.

The retired Node host's tests and their native replacements are mapped in [the retirement crosswalk](docs/node-host-retirement-test-crosswalk.md). Dated results for the previous implementation remain in [verification history](docs/verification.md); current migration checks are recorded there separately.

## Documents

- [Architecture, API, and ownership](docs/architecture.md)
- [Implemented scope and upstream differences](docs/port-status.md)
- [Native runtime, SIWC, and Tailscale Serve](docs/native-runtime.md)
- [Implementation status and acceptance conditions](docs/implementation-status.md)
- [Node host retirement test crosswalk](docs/node-host-retirement-test-crosswalk.md)
- [Verification record](docs/verification.md)
- [Remaining parity work](issues/open/0001-upstream-parity.md)
- [Engine boundary](engine/README.md)
- [Provider wire protocol](provider/README.md)
- [Third-party licenses](THIRD_PARTY_NOTICES.md)
