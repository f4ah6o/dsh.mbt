# 移植状況

基準は [DeepSeek Harness `5badb15009ae1756c3afe0ae0cef1faafc290ccc`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc)
（`0.2.1-alpha.1`）です。upstream 全体の TypeScript package を機械的に置換した版ではなく、
MoonBit で agent の基本実行経路を動かす最初の移植です。

**実装済み**はこの表に記載した範囲を動作させるコードとテストがあることを示します。
同じ行に対応する upstream package の全機能互換を意味しません。

| upstream の領域 | 移植先 | 状態と差分 |
| --- | --- | --- |
| `core/session`, `core/agent-loop`, `core/tools` | `engine/` | 基本 turn / step、event log、messages、直列 tool、follow-up、cancel、late result 拒否を実装済み。inbox の動的編集、fork の作成、parallel tool は未実装。 |
| `interaction/user-approval` | `engine/`, `api/`, `web/`, `host/cli.mjs` | read / write / shell 分類、呼出しごとの Allow / Deny、明示的 startup 自動承認を実装済み。upstream permission preset / account authorization の互換は未実装。 |
| `llm/llm-deepseek` | `provider/`, `host/provider.mjs` | Messages / Chat Completions の text、reasoning、function tool、usage、JSON / incremental SSE を実装済み。画像、Files API、model discovery、thinking signature の durable replay は未実装。 |
| `session/session-persistence*`, `session/session-projection` | `engine/`, `host/persistence.mjs` | 検証付き復元、atomic snapshot、interruption の終了、no replay を実装済み。保存形式は独自 `dsh.mbt-session-v1`。明示的な read-only v4 JSONL importer は下記の範囲で対応。v0–v3 migration、自動 v4 restore、v4 writer は未実装。 |
| `fs/tool-fs*`, `fs/tool-str-replace-editor` | `plugins/`, `host/tools.mjs` | read / write / edit / glob / grep を実装済み。workspace 制限、symlink 拒否、bounded regex / output。SSH filesystem、filesystem observation は未実装。 |
| `shell`, `subprocess` | `host/tools.mjs` | opt-in bash、timeout / cancel、出力上限を実装済み。persistent shell、terminal、PowerShell、OS sandbox は未実装。 |
| `client/ui-*`, `client/web` | `ui/`, `web/` | gpui scene による transcript、承認、会話一覧、再接続、scroll、Text view、mobile を実装済み。upstream の全設定画面 / sidebar / attachment preview は未実装。 |
| `api`, `sdk/protocol`, `typert` | `api/`, `app/`, `host/server.mjs` | gpui typed capability / GUI binding / MCP で置換。upstream API / SDK wire compatibility は提供しない。 |
| `boot/plugin-manager`, `extensions/cordis-*` | `plugins/` | MoonBit startup descriptor の依存・重複・tool 所有権を実装済み。npm / Cordis ABI、runtime code loading、HMR は未実装。 |
| `session/session-telemetry*`, inspector | `api/` + hotpath | API 呼出し時間の集計を実装済み。OpenTelemetry、CPU / allocation sampling は未実装。 |
| `test-support/session-snapshot`, `test-support/llm-replay` | `tests/fixtures/`, `tests/integration/` | upstream tool-call-turn fixture の provenance を保持し、実 tool と完了応答を再現。固定 upstream Session v4 catalog の unmodified 25 snapshot は import / reopen、transcript、tool correlation を integration test で確認。 |
| `compaction`, `spill`, `attachment`, `context` | `engine/` の read-only v4 projection | v4 importer は compaction summary/checkpoint と tool result pruning の一部を現在の transcript surface に反映し、画像参照を unresolved placeholder として表示。live context compaction、spill、attachment binary / preview は未実装。 |
| `subagent`, `goal`, `plan`, `workflow`, `jobs`, `schedule`, `todo` | `engine/` の read-only v4 projection | 限定的な subagent catalog / foreground workflow lifecycle metadata の相関のみ対応。子 agent、workflow、job の実行や再開は未実装。その他の機能も未実装。 |
| 外部 MCP client / ACP / hooks / LSP / skill loader | — | 未実装。gpui MCP server の公開とは別機能。 |
| browser / computer use、SSH、account login、web search、office preview | — | 未実装。 |

## 意図的な初期版の選択

- JavaScript output を Node host と browser の双方で使う。portable package の native テストは native GUI の完成を意味しない。
- 依存を upstream Git revision に固定し、互換性が確認できていない latest へ自動更新しない。
- SSE は MoonBit で逐次解析する。session / UI の streaming delta 更新は後続作業とする。
- 自動 HTTP retry は行わない。新しい外部作用を再試行する policy と durable recording は後続作業とする。
- 1 session 262,144 serialized UTF-16 units、最大 32 sessions。容量超過を明示し、履歴・承認・再開の整合性を保つ。
- browser host は loopback 専用。認証付き remote service や deployment platform はこの版に含めない。

## Session v4 の read-only import 範囲

`session_import` と `node host/cli.mjs import-session FILE` は、native v4 の physical JSONL と、
upstream snapshot fixture の sequence/time を省略した shorthand を明示的に decode します。
混在した envelope は拒否します。受理した元の header / raw event lines は `dsh.mbt-session-v1`
snapshot に保存し、reopen ごとに archive 全体と派生 projection を再検証します。

対応する projection は、基本的な user / system / assistant / tool message、tool 呼出しと result の
相関、複数 turn、通常の failed / cancelled / interrupted 終了、title の user-message citation、
基本的な inbox splice、および第一階層の seeded fork closure です。追加で、`developer/message` による
tool add/remove、request/header の更新、診断用 `assistant/attempt` stream、current-surface replacement、
compaction summary/checkpoint と `compaction/prune` による tool result の置換を検証します。
surface の順序は event sequence の数値順ではなく、現在の surface 上の位置で管理します。replacement は
shadowed surface node をすべて引用し、tool result の置換は同一 message identity と content 以外の
全フィールドを維持します。checkpoint は between-step と `turn: null` の standalone archive で受理し、
成功した compaction は summary・checkpoint・end の関係を検証します。第一階層の seeded fork は
compaction summary または prune の直後を cut として継承できます。

developer tool addition は過去の request/header から tool 定義を束縛します。native archive では完全な
tool object が必要です。upstream snapshot shorthand では名前配列を受理して raw history に保持しますが、
不足した schema を復元・生成しません。header の optional field は省略で clear され、null 値は受理しません。
`assistant/attempt` は診断 event のみで、retry schedule/start lifecycle や tool execution を意味しません。
content array が空の system / developer / assistant event は surface に残しますが、derived transcript message は作りません。
明示的な空文字 text block がある message は、空文字 content の transcript message として投影します。

2026-10-07 increment では、upstream catalog の unmodified 25 snapshot 全件を fixture として収録し、各 JSONL の
repository / commit / source path / SHA-256 / license を `provenance.json` に記録しました。integration catalog は
全件について raw source bytes、message source identity、tool-call/result correlation、pending tool がないこと、
import と reopen 後の同一 transcript を検証します。provider / tool effect はどちらの段階も 0 件です。

画像 block は JSONL にある opaque attachment ID、許可した media type (`image/png`, `image/jpeg`, `image/webp`,
`image/gif`)、寸法、byte 数を unresolved reference placeholder として transcript に表示します。画像の binary は
JSONL に含まれず取得もしません。現在の subset は attachment reference の `name` と `originalDimensions` を拒否します。
`skill-catalog` source の `kind` / `form` と entries schema を検証します。entry の名前と説明は raw event と
user transcript text にある内容をそのまま保持し、projected message の source metadata に複製しません。
Claude Code mod admission は inbox が保持した元 message の identity / source / content を prefix として保ち、
末尾への text block 追加だけを受け入れます。

PTC dispatch start/result は root / parent / child ID、name、arguments を相関し、親または root result より前に
子 dispatch が settle していることを検証します。`subagent/catalog` と foreground workflow run / agent lifecycle は
inert metadata として相関します。workflow run name は未 settlement の owning `workflow` call の
`arguments.meta.name` と一致する必要があり、その owner result は `run-end` の後でなければなりません。
`run_in_background: true` の workflow lifecycle、live execution、子 session の restore / continuation はこの importer
の対応範囲外です。画像取得、skill の実行、PTC / subagent / workflow の実行は行いません。

EOF 時に未完了の tool call は
`not_started` または `outcome_unknown` として表示し、結果を捏造しません。`ignorable: true` の未知 event は
raw history に保持し、projection に意味を持たせません。turn 開始時に inbox から claim 済みでも
model-visible user message にならなかった input は `pending_inbox.unadmitted_turn/step` に分離し、
通常の pending queue に戻したり実行したりしません。

spill / offload、unsupported attachment shape、background workflow、nested fork、retry scheduling lifecycle
など projection の意味を安全に復元できない event は、import 全体を明示的に拒否します。未知の
PTC / workflow / subagent / team execution-family event は `ignorable: true` があっても拒否します。
unmodified catalog 25 snapshot はすべて受理しますが、これは全 Session v4 event や runtime feature parity を
意味しません。
制約は engine 側の 262,144 UTF-16 code unit 上限と CLI の 1 MiB file 上限にも従います。
import history は画面上で read-only と表示され、prompt 送信と cancel を拒否します。これは決定的な履歴表示であり、
agent loop の再開ではありません。記録された provider / tool / approval / permission preset を実行・有効化しません。

## 完了済みの最初の受入経路

1. recursive checkout と固定 compiler / core から build できる。
2. API key なしの demo で browser / CLI から実際の workspace tool turn が完了する。
3. DeepSeek Messages / OpenAI Chat Completions を mock transport で実行できる。
4. approval 前の write は実行されず、Allow の記録後にだけ実行する。Deny / cancel も履歴に残る。
5. 保存して閉じ、再度開いても completed message を保持する。interrupted effect を自動再実行しない。
6. upstream の `echo SNAPSHOT_OK` → tool result → `DONE` の実記録を抽出 fixture で再現する。
7. gpui UI / capability API、hotpath 計測、turtles mutation gate を実際のアプリ経路で使う。

追加の受入条件は [次の移植作業](../issues/open/0001-upstream-parity.md) に追跡します。
live provider への有料 API 呼出しと macOS native window の実機試験はまだ行っていません。
