# dsh.mbt

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) の MoonBit 移植。
セッション、イベントログ、LLM / tool loop、承認、provider wire protocol を MoonBit で実装し、
UI と capability API に [gpui-mbt/gpui.mbt](https://github.com/gpui-mbt/gpui.mbt) を使います。
ネットワーク・ファイル・子プロセス・永続化の I/O は Node.js host が担当します。

**現在は最初の動作する移植版です。** ブラウザ / CLI から会話し、ローカルツールを実行して履歴を保存できます。
upstream 全機能の互換移植は進行中です。Session v4 は明示的な read-only import に限って対応し、
Cordis / npm plugin 互換、subagent、live compaction、native window などは未実装です。
importer は一部の compaction checkpoint と transcript pruning を履歴表示用に復元しますが、
agent の context 管理や長い会話の継続には使いません。
詳細な対応範囲は [移植状況](docs/port-status.md) に記載しています。

## 起動

Node.js **24 以上**、Git、固定版の MoonBit toolchain を使用します。native テストと turtles には C compiler が必要です。

```sh
git clone --recurse-submodules https://github.com/f4ah6o/dsh.mbt.git
cd dsh.mbt

# .moonbit-version と同じ compiler / core を導入
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- '0.10.14+7d59c7ec9'
export PATH="${MOON_HOME:-$HOME/.moon}/bin:$PATH"

npm run verify:env
npm run demo
```

表示された `http://127.0.0.1:3080` を開きます。**demo は API key 不要の固定応答**で、
実際の workspace `glob` ツールを使って一連の処理を確認できます。
通常の build / 起動に npm パッケージのインストールは不要です。
既存 checkout の場合は `git submodule update --init --recursive` で依存を揃えてください。

### DeepSeek API を使う

```sh
npm run build
export DEEPSEEK_API_KEY='your-api-key'
node host/cli.mjs web --workspace /absolute/path/to/project
```

既定は `deepseek-flash` と Messages API の `https://api.deepseek.com/anthropic`。
モデルと API root は `--model` / `--base-url` で変更できます。認証情報は host の環境変数から読みます。

OpenAI Chat Completions 互換 endpoint は、利用先に合わせてモデルを明示します。

```sh
export OPENAI_API_KEY='your-api-key'
node host/cli.mjs web --mode openai --model MODEL --base-url https://YOUR-PROVIDER/v1
```

`DSH_API_KEY`、`DSH_MODE`、`DSH_MODEL`、`DSH_BASE_URL` でも設定できます。
`--base-url` 末尾の `/v1` は重複させずに結合します。

### CLI

```sh
node host/cli.mjs run "この workspace のファイルを確認してください" --demo --json
node host/cli.mjs run "README を確認してください" --workspace /absolute/path/to/project
node host/cli.mjs run "続きを進めてください" --session SESSION_ID
node host/cli.mjs import-session /path/to/session.v4.jsonl --json
node host/cli.mjs --help
```

`run` は完了した会話を出力します。`--json` はセッション全体を出力します。
同じ workspace の `.dsh.mbt/sessions.json` に履歴を保存し、次回起動で復元します。
保存先は `--data-dir` で指定できます。同一データディレクトリを複数プロセスから同時に開くことはできません。
`import-session` は upstream Session v4 を検証して、再開できない読み取り専用履歴として保存します。
記録された tool、inbox、permission、preset は履歴に残しますが、実行や権限設定には使いません。

### Provider retry

一時的な provider failure では、同じ未完了 request を最大 5 回まで再試行します。既定の backoff は 500 ms から始まり、
最大 10 秒まで倍増します。`--max-retries 0` で無効化でき、CLI と host API の上限は 5 です。
retry は各 provider request を新たに送信するため、provider 側では再度課金される場合があります。

対象は空応答、HTTP 408 / 429 / 5xx、timeout、および識別できた一時的な transport failure です。
HTTP 4xx（408 / 429 を除く）、authentication、malformed response は retry しません。正の `Retry-After` は 10 秒以内のときだけ
backoff を置き換え、上限を超える値は retry を止めます。受理した stream delta が一つでもある request は再試行しません。
MoonBit は retry schedule と開始を event log に記録してから host が待機・再接続し、shutdown や reopen で provider / tool を
重複実行しません。upstream と異なり jitter は使いません。`Session v4` read-only importer は `llm/retry` と
`llm/retry-started` の schema と相関を検証して raw history に保持しますが、待機や provider request は再生しません。
実装範囲と差分は [移植状況](docs/port-status.md) を参照してください。

## ツールと承認

| ツール | 主な引数 | 実行条件 |
| --- | --- | --- |
| `read` | `file_path`, 任意の `offset`, `limit` | 自動実行 |
| `glob` | `pattern`, 任意の `path` | 自動実行 |
| `grep` | `pattern`, 任意の `path` | 自動実行、検索時間と出力に上限 |
| `write` | `file_path`, `content` | 呼出しごとに承認 |
| `edit` | `file_path`, `old_string`, `new_string`, 任意の `replace_all` | 呼出しごとに承認 |
| `bash` | `command`, 任意の `description`, `timeout` | `--allow-shell` と呼出しごとの承認 |

ブラウザの **Allow once / Deny**、または対話 CLI で承認します。
明示的な起動方針として `--approve-writes`、`--approve-tools write,edit` も使用できます。
shell の自動承認には `--allow-shell --approve-tools bash` の両方が必要です。
非対話 CLI で承認待ちになると、その turn をキャンセルして終了コード 2 を返します。
既に完了したツールの作用は取り消しません。

ファイルツールは workspace 内に限定し、パストラバーサル、symlink、履歴保存ディレクトリへのアクセスを拒否します。
`bash` は workspace を作業ディレクトリにする通常の OS 子プロセスです。
**OS の filesystem / network sandbox は実装していません。** shell を有効にする場合はその権限でコマンドが動きます。

## gpui-mbt の利用

| 依存 | 実際の使用箇所 |
| --- | --- |
| [gpui.mbt](https://github.com/gpui-mbt/gpui.mbt) | MoonBit の flex layout / ElementTree / SceneSnapshot による会話描画。`App` が所有する typed capability registry、GUI binding、MCP protocol。 |
| [hotpath.mbt](https://github.com/gpui-mbt/hotpath.mbt) | capability 呼出しの計測・集計。`profile_stats` API で取得。 |
| [turtles.mbt](https://github.com/gpui-mbt/turtles.mbt) | 実際の `plugins/plugins.mbt` と同じテストを使う native mutation gate。 |

3 リポジトリは Git submodule で固定します。MoonBit module 名はそれぞれ `f4ah6o/gpui`、
`f4ah6o/hotpath`、`f4ah6o/turtles` です。`moon.work` はローカルの固定 revision を使います。
React / Vue や upstream TypeScript runtime を起動する構成ではありません。

会話のレイアウトと scene 生成は MoonBit、Canvas 2D への描画は gpui の browser renderer を使用します。
入力・承認ボタン・セッション選択には DOM の操作面を使い、IME、キーボード操作、選択可能な **Text view** を提供します。

## API

ブラウザと CLI は同じ MoonBit engine を使い、操作の schema 検証と dispatch は gpui の capability registry が担当します。

```sh
curl -sS http://127.0.0.1:3080/api/call \
  -H 'Content-Type: application/json' \
  -d '{"operation":"session_create","input":{"id":"example","title":"Example"}}'

curl -sS http://127.0.0.1:3080/api/call \
  -H 'Content-Type: application/json' \
  -d '{"operation":"session_send","input":{"session_id":"example","prompt":"List the files"}}'
```

返却形式は `{ "ok": true, "result": ... }` または `{ "ok": false, "error": "..." }`。
`session_send` は処理の受付を返します。完了は `session_get` で確認します。

公開操作は `session_create`、`session_import`、`session_list`、`session_get`、`session_send`、`session_cancel`、
`tool_approve`、`plugin_list`、`profile_stats`。`session_list` は一覧用の要約を返します。
HTTP carrier は loopback に限定します。

`session_import` は `jsonl` に Session v4 archive 全体を受け取ります。import は read-only で、
再オープン時も原文と派生 messages / status / pending inbox / tool outcome を再検証します。
これは deterministic history projection であり、agent loop の再開、provider request、tool execution は行いません。

`POST /mcp` と `node host/cli.mjs mcp` は gpui の MCP protocol を直接公開します。
この固定版は **`2026-07-28` / `server/discover`** を使用します。
旧 `initialize` handshake への変換はなく、tool の `structuredContent` は JSON 文字列です。
具体的なリクエストと境界仕様は [アーキテクチャ](docs/architecture.md) を参照してください。

## 検証

```sh
npm test                 # format / own warnings / portable MoonBit / build / host / web / integration
npm run mutation:list    # production plugin の mutation 対象を列挙
npm run mutation         # 固定 turtles を build し、実際に mutation test を実行
```

MoonBit の portable package は JS / native / Wasm / Wasm GC の全 target で検証します。
`app` は JavaScript FFI 用です。workspace 全体を無指定でテストすると、gpui の OS 専用 backend や example も対象になるため、
用意した package selector を使ってください。

テストは API key を使いません。pinned upstream の tool-call-turn と parallel-tool-calls fixture を keyless なローカル HTTP provider に流し、
承認済みの `echo SNAPSHOT_OK`、2 件の Read call と call-order の tool result、次のモデル応答 `DONE`、保存と再読込まで再現します。
任意の実 Chromium 検証は `web/browser-smoke.mjs` にあります。
Session v4 importer の対応 event と明示的な制約は [移植状況](docs/port-status.md) を参照してください。
詳細な結果と再実行方法は [検証記録](docs/verification.md) を参照してください。

## ドキュメント

- [アーキテクチャ・API・所有権](docs/architecture.md)
- [移植済み範囲と upstream との差分](docs/port-status.md)
- [検証記録](docs/verification.md)
- [次の移植作業と受入条件](issues/open/0001-upstream-parity.md)
- [Engine の境界仕様](engine/README.md)
- [Provider の wire protocol](provider/README.md)
- [ライセンスと第三者ソース](THIRD_PARTY_NOTICES.md)
