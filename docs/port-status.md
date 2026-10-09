# 移植状況

基準は [DeepSeek Harness `5badb15009ae1756c3afe0ae0cef1faafc290ccc`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc)
（`0.2.1-alpha.1`）です。upstream 全体の TypeScript package を機械的に置換した版ではなく、
MoonBit で agent の基本実行経路を動かす最初の移植です。

**実装済み**はこの表に記載した範囲を動作させるコードとテストがあることを示します。
同じ行に対応する upstream package の全機能互換を意味しません。今回の native / SIWC increment の受入表は[実装状況](implementation-status.md)を参照してください。

| upstream の領域 | 移植先 | 状態と差分 |
| --- | --- | --- |
| `core/session`, `core/agent-loop`, `core/tools` | `engine/` | 基本 turn / step、event log、messages、follow-up、cancel、late result 拒否、LLM text/reasoning の bounded live projection と Read の bounded parallel tool を実装済み。連続 Read call を最大 4 件で rolling 実行し、Write / Shell / unknown / schema-invalid call は barrier。結果と model context は call 順を維持する。native v1 runtime は settled な非 imported session の fork を作成し、parent prefix と rekey 済み effect / retry identity を snapshot restore で検証する。upstream の default pool size 10、動的 policy、inbox の動的編集、その他の agent-loop 機能は未実装。 |
| `interaction/user-approval` | `engine/`, `api/`, `browser/`, `runtime/` | read / write / shell 分類、呼出しごとの Allow / Deny、対話 CLI と明示的 startup 自動承認を実装済み。非対話 CLI は承認待ち turn を cancel して失敗する。upstream permission preset / account authorization の互換は未実装。 |
| `llm/llm-deepseek` / Responses | `provider/`, `runtime/provider_http.mbt` | DeepSeek Messages、OpenAI Chat Completions / Responses の text・reasoning・function/custom call lifecycle・usage・SSE を実装済み。Responses API-key と SIWC は native runtime で利用でき、SIWC は account-visible model discovery と protected refresh lifecycle を使う。実アカウント smoke は未実行。画像、Files API、thinking signature の durable replay は未実装。 |
| `llm/llm-retry`、`llm/retry-policy` | `engine/retry.mbt`, `runtime/`, `engine/session_v4_retry.mbt` | MoonBit event log に schedule / start を保存する、最大 5 回の bounded retry を実装済み。既定 backoff は 500 ms から 10 秒までの deterministic exponential（jitter なし）。許可する一時 failure は空応答、429、408/504、5xx、識別済み transport error。positive `Retry-After` は上限以内で採用し、上限超過なら retry しません。accepted stream delta 後、auth / その他の 4xx / malformed response は再試行しません。read-only Session v4 importer は retry event schema と相関を検証して raw event として保持します。`runtime/runtime_carrier_wbtest.mbt` は実 HTTP 503 → request body が同一の再試行 → 承認済み tool → follow-up provider response → reopen 後の durable history を検証します。保存 failure / backoff interleaving の網羅は対象外で、制約は[retirement crosswalk](node-host-retirement-test-crosswalk.md)に記録しています。upstream `always` runtime mode、policy keying、jitter は未実装で、import した retry は再生しません。 |
| `session/session-persistence*`, `session/session-projection` | `engine/`, `runtime/store.mbt` | 検証付き復元と atomic writer、native versioned envelope / command receipt、interruption の終了、no replay を実装。native v1 は対応する legacy snapshot / Session v4 input を初回 open 時に一方向更新する。旧 Node-host version は native envelope を拒否するため、初回起動前に backup する。明示的な read-only v4 JSONL import projection は下記の範囲で対応。v0–v3 migration と v4 writer は未実装。 |
| `fs/tool-fs*`, `fs/tool-str-replace-editor` | `plugins/`, `runtime/tools.mbt` | read / write / edit / glob / grep を実装済み。workspace 制限、symlink 拒否、bounded output。Native glob は documented subset。macOS では hard worker memory limit がないため regex grep を明示的に disabled とする。SSH filesystem、filesystem observation は未実装。 |
| `shell`, `subprocess` | `runtime/tools.mbt`, `runtime/host_os.c` | opt-in bash、timeout / cancel、出力上限を実装済み。Native worker は dedicated process session を使い、OS memory limit は platform 差がある。persistent shell、terminal、PowerShell、OS sandbox は未実装。 |
| `client/ui-*`, `client/web` | `client/`, `protocol/`, `presentation/`, `ui/`, `browser/`, `web/moonbit/`, iOS bridge, `desktop/` | 共有 protocol / presentation / client と MoonBit browser / iOS adapter、account selector、session receipt lifecycle、PWA shell refresh を実装。browser JavaScript / service worker は compiler output。gpui scene は transcript、streaming、承認、会話一覧、再接続、scroll、Text view、mobile を提供する。macOS native GPUI app は session 選択、prompt 編集 / paste、transcript、tool approval / cancel、durable reload を提供する。現 GPUI host の IME composition は未対応で、paste を使う。全 upstream 設定 / attachment preview は未実装。 |
| `native runtime / platform boundary` | `runtime/`, `native/`, `cmd/dsh/`, `.mbtx`, `.github/workflows/ci.yml` | Node 不要の native CLI / loopback service、provider/auth、workspace tool、durable checkpoint、session task pool / cancel と Node-absent verification を実装。`cmd/dsh` は Moon CLI source install 用の executable entrypoint。現在の full verification と以前の dated Node-host baselines は[verification record](verification.md)を参照。 |
| `api`, `sdk/protocol`, `typert` | `api/`, `app/`, `protocol/`, `runtime/service.mbt` | typed application boundary、remote protocol、native loopback HTTP / SSE carrier と durable receipts を実装。upstream API / SDK wire compatibility は提供しない。実 Tailscale Serve acceptance は未実行。 |
| `boot/plugin-manager`, `extensions/cordis-*` | `plugins/` | MoonBit startup descriptor の依存・重複・tool 所有権を実装済み。npm / Cordis ABI、runtime code loading、HMR は未実装。 |
| `session/session-telemetry*`, inspector | `api/` + hotpath | API 呼出し時間の集計を実装済み。OpenTelemetry、CPU / allocation sampling は未実装。 |
| `test-support/session-snapshot`, `test-support/llm-replay` | `tests/fixtures/`, `engine/`, `runtime/` | upstream tool-call-turn fixture の provenance を保持し、engine/native demo tests で tool lifecycle を確認。固定 upstream Session v4 catalog の unmodified 25 snapshot は native runtime 経由で import / reopen し、read-only projection と effect 0 件を確認。別置きの derived retry fixtures は upstream retry bytes と source hashes を専用 `provenance.json` に記録し、25 件の不変 catalog には含めない。旧 Node-host 固有 integration test と現行 native coverage の差は[retirement crosswalk](node-host-retirement-test-crosswalk.md)に記録する。 |
| `compaction`, `spill`, `attachment`, `context` | `engine/` と read-only v4 projection | Native v1 runtime に explicit な tool-result pruning subset を実装済み。完了後に手動で起動し、将来の provider context だけを head / marker / tail に縮約します。original result と raw transcript は保存します。v4 importer は compaction summary/checkpoint と upstream tool-result pruning の一部を表示用に投影します。自動 / token-aware live compaction、summary、spill、attachment binary / preview は未実装。 |
| `subagent`, `goal`, `plan`, `workflow`, `jobs`, `schedule`, `todo` | `engine/` の read-only v4 projection | 限定的な subagent catalog / foreground workflow lifecycle metadata の相関のみ対応。子 agent、workflow、job の実行や再開は未実装。その他の機能も未実装。 |
| 外部 MCP client / ACP / hooks / LSP / skill loader | — | 未実装。gpui MCP server の公開とは別機能。 |
| browser / computer use、SSH、ChatGPT web search、office preview | — | 未実装。Native local SIWC OAuth は実装済みだが、実アカウント smoke は未実行。 |

## 意図的な初期版の選択

- Product runtime は MoonBit native executable と MoonBit browser / service-worker packages で構成する。JavaScript は browser / worker の生成物と test/build tooling に限り、Node runtime は配布しない。portable package の native test だけでは native UI の受入を意味しない。
- 依存を upstream Git revision に固定し、互換性が確認できていない latest へ自動更新しない。
- SSE は MoonBit で逐次解析し、text / reasoning を host が bounded event batch として永続化して session / browser / scene に投影する。live compaction と spill は後続作業とする。
- retry は同じ active provider effect に限定し、retry schedule と start の checkpoint が成功してから待機・次の request を始める。restore は未完了の retry を interruption として閉じ、再送しない。利用可能な request を使うため retry ごとに provider 側で再課金される場合がある。
- tool-result pruning は手動操作のみ。upstream の defaults は threshold 8,192 Unicode code points、head 4,096、tail 1,024。pruned event を append するので元 output を保持したまま provider context を縮める一方、canonical storage limit の解消にはならない。
- 1 session 262,144 serialized UTF-16 units、最大 32 sessions。stream projection と pruning event もこの上限内で、容量超過は candidate 更新を拒否して既存状態を保つ。長い会話向け自動 live compaction / token meter / summary / spill は未実装。
- Native service は loopback 専用。利用者が Tailscale Serve と owner allowlist を設定した場合だけ proxy identity header を信頼する。実 Tailnet / public hosting はこの実装検証の範囲外。

## Native v1 runtime の settled session fork

`session_fork` は `idle`、`completed`、`failed`、`cancelled` のうち実行状態が settled した native v1 session から独立した child を作ります。native CLI は `fork-session SESSION_ID`、browser UI は **Fork conversation** を提供します。child は元の transcript、tool call/result identity、pruning の sequence reference を保ちます。effect ID と retry ID は branch ごとに再採番し、pending effect、approval、retry wait、tool dispatch は継承せず、external work を開始しません。child は `idle` で始まり、`parent_session_id` と `session/forked` marker を記録します。

Restore は marker に固定された parent event prefix、session prompt / step limit、effect ID map、lineage graph を全 session の adoption 前に照合します。後続の parent continuation は既存 child の source prefix を変えません。native v1 runtime の forks-of-forks は対応します。Session v4 importer の seeded-fork subset は別仕様で、nested v4 fork と v4 writer は引き続き未対応です。fork は最大 32 session、session 262,144 UTF-16 unit、32,767 source event の既存上限に従い、active/imported session、capacity 超過、ID conflict は変更なしで拒否します。

## Session v4 の read-only import 範囲

`session_import` と `dsh-native import-session FILE` は、native v4 の physical JSONL と、
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
`llm/retry` / `llm/retry-started` は native envelope と snapshot shorthand の両方で schema、turn/step/provider、policy chain、
retry ID、attempt count、schedule/start の相関を検証し、failure / policy / delay metadata を raw history に保ちます。
fractional delay と Retry-After を許可し、未開始 schedule を含む interrupted retry history を受理します。
これは read-only projection であり retry wait や provider request を実行しません。通常の v1 runtime と upstream の retry
policy / `always` mode / jitter parity は別の範囲です。
retry fixtures は pinned upstream `empty-response-retry-current` snapshot の retry / attempt payload bytes と
`llm-retry` persistence example を元に v4 envelope へ適合させ、source path と SHA-256 を個別 provenance に記録しています。
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

spill / offload、unsupported attachment shape、background workflow、nested fork など projection の意味を安全に復元できない
event は、import 全体を明示的に拒否します。retry event についても不正な schema / correlation は拒否します。未知の
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
8. macOS native window で demo prompt を送り、AppKit input event で tool approval、workspace write、completed transcript、閉じた後の durable reload を確認する。

追加の受入条件は [次の移植作業](../issues/open/0001-upstream-parity.md) に追跡します。
live provider への有料 API 呼出しはまだ行っていません。macOS desktop app の対応範囲、install/build、IME 制約は[native desktop guide](desktop.md)を参照してください。
