# 0001: DeepSeek Harness の残りの機能を MoonBit へ移植する

Status: open
Model: gpt-6-luna
Created: 2026-10-05
Updated: 2026-10-10
Branch: feat/20261010-hook-user-prompt
upstream baseline は `5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

## 概要

DeepSeek Harness の残る session、provider、extension、UI、host 機能を MoonBit native runtime へ段階的に移植し、upstream baseline との差分を記録します。現在の範囲と確認済み acceptance は[移植状況](../../docs/port-status.md)を参照してください。

## 背景

upstream は複数 TypeScript package と Cordis lifecycle で構成されています。この repository は MoonBit engine / native host に製品実行経路を移し、upstream 互換が確認された細分化 scope だけを bounded subset として提供しています。

## 問題

多くの upstream event と native v1 feature に部分対応がありますが、完全な lifecycle parity、長い会話の compaction、Cordis extension runtime、background jobs、provider/media capabilities、host sandbox は未実装です。partial implementation を全体互換と誤って受け取られないよう、受け入れ範囲と移行条件を明示する必要があります。

## 目標

- upstream baseline の event、provider、tool、extension、host semantics を調査し、native MoonBit implementation と tests に反映する。
- 各 increment の制限、recovery、security boundary、compatibility requirements を docs と release notes に記録する。
- broad parity issue を open のまま維持し、完了条件のない範囲を完了扱いしない。

## 対象外

- upstream TypeScript / Cordis plugin ABI を MoonBit implementation と同等扱いにすること。
- 実 provider credentials を一般 regression tests に使うこと。
- 部分実装を full upstream parity と表現すること。

## 提案する方針

各 increment は pinned upstream source を参照し、native runtime の policy / persistence / no-replay boundary を定義してから、keyless fixture と user-facing migration notes を追加します。実装済みの bounded subset は本 issue を閉じず、残る upstream lifecycle を別途追跡します。

## 受け入れ条件

- native behaviour と upstream difference が同じ increment の tests / docs / changelog に記録される。
- cancellation / interruption / restore を含む external-effect boundary が検証される。
- この umbrella issue は対象の parity work がすべて終わるまで open のままにする。

## テスト計画

Keyless engine / provider / native runtime fixtures を優先し、必要な CLI / browser / ACP / desktop surface を回帰確認します。Live account tests は、認証情報をログに含めず明示的に実施した場合だけ別途記録します。

## リスク

Bounded native subset と upstream package の名称が近いため、互換範囲を過大に解釈される可能性があります。各機能の上限、trusted host code、restore / replay behaviour、unsupported lifecycle を明記して緩和します。

## 変更履歴

- 2026-10-10: pinned [`hooks-claude-code/index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts) の PostToolUse `additionalContext` を bounded native path に追加。matching hooks の text block を per-call `user/message` として保存し、[`core/tools/index.ts:1781`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/tools/src/index.ts#L1781) / [`agent-loop/tool-calls.ts:147`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/tool-calls.ts#L147) の consumer ordering に沿って parallel tool results 後、tool-call order で provider へ渡す。empty / whitespace、exit 2、block + context、Unicode / per-item / aggregate limits、no-match、cancel-after-known-outcome、receipt replay / reopen を keyless tests で確認。local transcript は `フック補足` として表示し、ACP text update は source-aware update がないため省略する。wrong-type の strict rejection、native block result shape、ACP omission を差分として記録し、issue は open のまま。
- 2026-10-10: pinned [`hooks-claude-code/index.ts:223-240`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L240)、[`config.ts:109-112`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/config.ts#L109-L112)、[`hook-protocol/codec.ts:59-88`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts#L59-L88)、[`merge.ts:62-99`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts#L62-L99) の UserPromptSubmit semantics を参照し、native `run` / `web` / `mcp` / `acp` / `desktop` に追加。valid user `session_send` ごとに一度だけ provider admission 前に command を実行し、matcher 無視、exit 2 / `block` / event-specific `deny`、lenient output parsing、bounded `additionalContext` を実装。context は upstream と同じ一つの source-tagged user message に hook 順で grouped 保存し、prompt 後 / provider request 前に置く。remote receipt replay は hook を再実行せず、interruption は unsettled reservation を uncertain として復元する。`index.ts:195` の `continue:false` は upstream 自身が run-level halt 未実装と記録している。`index.ts:181-185` の `updatedInput` / `systemMessage` も bridge 側で ignored。codec、pre-admission / forged-context stripping / replay / cancellation の keyless test source を追加した。Final verification at PR #46 head `982f2b6f4b5fd364ebf0500a032bb210b753db9a`: local native format and typecheck pass with zero errors and four pinned `vendor/hotpath` warnings. Browser/service-worker asset regeneration passed during candidate work, though its exact local source head was not recorded; final-head browser build is covered by hosted CI. The package preview passed on source snapshot `76d18938ce173f28f797e073411f77c039d8bec8`; its 905-entry / 3,019,163-byte size is not a final-head size claim. Local focused native behavior tests could not complete because compilation hit local-volume `ENOSPC`. Hosted [native/browser CI run 38043639573](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) passed: portable Wasm, Wasm GC, JS, and native each 163 / 163; app 17 / 17; native runtime 156 / 156; browser modules 7 / 7; no-Node native 329 / 329; Chromium smoke and ACP stdio passed. Hosted [three-platform asset workflow 38043639550](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639550) passed macOS arm64, Linux x86_64, and Linux arm64 packaging and smoke checks. The initial no-Node fixture failure at [38042285182](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042285182) was a transcript projection mismatch, not a production defect; the filtered engine result did not isolate a persistence-restore failure. The next 325 / 328 run at [38042930510](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042930510) exposed cancellation classification and prompt-matcher test issues fixed and covered at the final head. Other upstream lifecycle and compatibility increments remain open.
- 2026-10-10: pinned upstream ACP model control を参照し、persistent per-session `model` option、bounded `DSH_ACP_MODELS` catalog、busy-turn refusal、retry / subagent inheritance、route / catalog reopen fencing を追加。upstream の `session/load` 非実装も確認し、load はこの差分に含めない。本 issue は open のまま。
- 2026-10-10: Native ACP fatal-path defect: `runtime/main.mbt` used `abort` after ACP argument/startup/carrier/shutdown failures, and the native panic diagnostic could be written to stdout, corrupting JSON-RPC framing. Fixed with bounded stderr diagnostics and nonzero exit; checkpoint conflict stdio regression verifies an RPC error, no config update/effect, later request fencing, and JSON-only stdout through EOF. This is a native carrier issue, not an upstream parity defect.
- 2026-10-10: ACP v1 persistent list / resume slice を追加し、workspace provenance、pagination、restart continuation、no-replay と multi-workspace / MCP 差分を記録。
- 2026-10-10: bounded foreground subagent slice とその recovery / hook limits を section 3 に追加。upstream subagent lifecycle parity は未完了。

## 注記

- 2026-10-10: This is a broad parity tracker; individual bounded increments do not change its open status.

## 1. Session v4 と replay

upstream JSONL を version ごとに厳密に decode し、イベントの意味を MoonBit 型へ移す。
未知の event、attachment、interruption を黙って捨てない。v4 のまま保存するか、明示的な importer として独自 schema へ移すかを仕様に記録する。

部分対応: `session_import` は Session v4 native JSONL と upstream snapshot shorthand の限定 event subset を検証し、
元の raw lines を保持した read-only projection を作る。対応 event / 拒否する event は
[移植状況](../../docs/port-status.md) に記載する。2026-10-06 の increment では developer tool/header 更新、
current-position surface replacement、限定的な compaction checkpoint / pruning、診断用 assistant attempt を追加した。
2026-10-07 の increment では unmodified upstream catalog 25 件すべてを fixture と regression に追加し、import / reopen
後の raw source、transcript と call correlation を確認する。追加した image reference、skill provenance、mod append、
PTC / subagent / foreground workflow lifecycle は inert projection metadata に限り、background workflow、実行、nested fork、
spill/offload は引き続き拒否または未実装。2026-10-07 の retry import increment では native / shorthand の
`llm/retry` と `llm/retry-started` を strict schema と turn/step/provider/policy/attempt correlation で検証し、raw history に保持します。
retry delay や failure metadata も保存しますが、imported retry は待機も provider request も行いません。通常の v1
runtime には別途、限定的な provider retry lifecycle を追加しました。import history は
再開しない。v0–v3 migration、v4 writer、catalog 外の全 event semantics は引き続き本 issue の対象。

Native v1 runtime fork の部分対応（2026-10-07）: `session_fork` は idle / completed / failed / cancelled の settled な
非 imported session から新しい idle child を作り、履歴を保ったまま effect ID と retry ID を branch-local に再採番します。
approval / pending retry / active tool/provider work は受け付けず、fork や restore から external effect は発行しません。
`session/forked` marker は parent ID、固定 event prefix、source status / turn / step、effect map を保存します。
restore は全 session の adoption 前に親 prefix、creation settings、effect/retry metadata、missing parent、lineage cycle を
検証するため、親が後から続行しても既存 child は当時の prefix に結び付いたままです。fork-of-fork、fork後の tool-result pruning、
interrupted history、Node/native CLI、browser selection race、native durable command receipt replay を keyless test で確認します。
新機能は native v1 の settled runtime fork であり、Session v4 importer の seeded-fork subset を拡張せず、v4 writer / arbitrary
upstream branch semantics は実装しません。本 issue は open のままです。

受入条件:

- upstream の snapshot fixture を変更せずに読み、user / assistant / tool と相関情報を再構築する。
- branch / fork、inbox、複数 turn、failed / cancelled / interrupted の fixture を追加する。
- import と reopen で外部作用が発生しない。
- 現在の `dsh.mbt-session-v1` 履歴も明示的な migration で読み続けられる。

## 2. 長い会話と stream projection

Live compaction、tool result pruning、spill を導入し、262,144-unit 上限に依存しない長い会話を支える。
provider SSE の delta を engine event と UI に逐次反映し、切断時の未完了 tool を実行しない。

部分対応（2026-10-07）: OpenAI-compatible / DeepSeek Messages の検証済み text・reasoning delta を host が bounded batch で
`assistant/stream_delta` event に checkpoint し、browser と gpui scene は writing / partial として表示します。
final message は同じ provisional row を置き換え、次の provider context には provisional text を含めません。
effect・turn・step の照合、final text の一致検証、cancel / EOF failure / reopen 後の partial 保持、incomplete tool の不実行を
keyless regression で確認しています。provider parser は任意 chunk / UTF-8 境界を検証します。Session v1 の
262,144-unit 上限は維持され、拒否時は追加 batch を適用せず provider を止めます。live compaction と spill/offload は
未実装なので、長い会話の capacity limit は残ります。本 issue は open のままです。

retry の部分対応（2026-10-07）: 通常の v1 runtime は transient provider failure の bounded retry を実装します。
MoonBit が同じ active effect の `llm/retry` schedule と `llm/retry-started` を検証・記録し、host は各 checkpoint の成功後だけ
wait と次の provider request を始めます。既定は最大 5 retries、deterministic 500 ms exponential backoff、10 秒上限です。
対象は empty response、408/429/5xx、timeout、識別済み transport failure。accepted stream delta 後、auth、HTTP 408 / 429 以外の 4xx、
malformed response は再試行せず、Retry-After が上限を超える場合も retry しません。request body の同一性、ツールの重複実行なし、
backoff cancellation、start checkpoint failure、restore no-replay を keyless integration で確認しています。
upstream の jitter / `always` runtime mode / retry policy keying は未実装です。v4 retry event import は schema / history
validation のみで runtime replay ではありません。compaction、spill と
retry 可能な長い conversation を追加する設計・受入条件は残ります。

manual tool-result pruning の部分対応（2026-10-07）: pinned
[compaction-tool-result-pruner](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/compaction/compaction-tool-result-pruner)
の head / marker / tail policy を native v1 runtime に移し、idle / completed session 向けの
`session_prune_tool_results`、`prune-session` CLI、browser の **Trim outputs** を追加しました。
既定値は threshold 8,192、head 4,096、tail 1,024 Unicode code points です。projection は durable pruning event として保存し、
restore は source/result sequence、call identity、budgets、counts、projected content を再検証します。
元の `tool/result` と transcript は変更せず、次の provider context だけを projection します。imported / active session は拒否します。
keyless provider integration は 10,000-character parallel Read outputs が実 request で縮むこと、call order、reopen 後の同じ projection、
tool の no-replay を確認します。Browser smoke は同一 selection と遅延した prune response / session switch を確認します。

これは明示的な手動操作であり、token meter、pressure trigger、summary generation、自動 live compaction、spill は含みません。
pruning event 自体が保存量を増やすため、262,144 UTF-16 code unit の canonical session limit は維持されます。従って長い会話を
この上限を越えて継続する要件や capacity increase は満たしていません。本 issue 全体は open のままです。

受入条件:

- 旧上限を超える複数 turn の会話が継続し、縮約前後の履歴が説明可能である。
- arbitrary chunk / Unicode / EOF / cancel の途中状態を再現する。
- retry の回数、理由、重複実行防止を durable event として追跡する。

## 3. 拡張機能と tool 統合

MoonBit の typed service / lifetime を定義して、startup metadata から動的な拡張境界へ進める。
External MCP client、workspace skills、native command hook、ACP、LSP navigation、foreground subagent の bounded subset は実装済み。各 upstream 機能との差分を維持し、追加 hook event と LSP 対応範囲を整理する。
Cordis / npm plugin をそのまま動かす場合は別の互換 host を設計し、MoonBit-only plugin とは区別する。

部分対応（2026-10-07）: `effect: "read"` に静的分類した連続 tool call は最大 4 件の rolling pool で並列実行し、
各 `tool/request` の checkpoint 後に host IO を始めます。out-of-order completion は call / effect ID とともに durable staging し、
`tool/result` と次の model context は call 順を保ちます。Write / Shell、unknown tool、schema-invalid call は先行 read group を drain する barrier
です。cancel / restore は新しい work の dispatch を止め、既知の成功を保持し、unknown outcome を再生しません。pinned upstream
parallel-tool-calls fixture の keyless runtime 経路と、pool refill、barrier、approval、cancel、capacity、reopen を検証します。
upstream default pool size 10 ではなく 4 に制限し、dynamic safety classification、parallel write / shell、full upstream tool policy は
引き続き未実装です。本 issue 全体は open のままです。

workspace skill の部分対応（2026-10-09）: pinned upstream の `skill`, `skill-filesystem`,
`tool-skill` を元に、native runtime の `--enable-skills` と repeatable `--skill-dir PATH`、
workspace 内 `.dsh/skills` / `.agents/skills` / custom roots の決定的な discovery、bounded
frontmatter、model / user invocation controls、provider tool schema の static summary catalog、
read-only `skill` loader を追加しました。ユーザーの `/name` は user-invocable skill の本文と
provenance marker を user message に追加し、checkpoint 後に provider effect を返します。tool body と
source は result に含まれ、restore 時に同じ `skill` tool が無ければ engine validation が store を拒否します。
ordinary store は skill tool を有効にして開けます。symlink と protected runtime store を避け、body / result /
catalog の各上限を適用し、rename / policy change / disappearance を再読込時に再検証します。

これは upstream と同じ機能面全体ではありません。user-home / bundled / URL roots、file watcher、live catalog
replacement と durable catalog message、runtime skill registry、full YAML / arbitrary metadata、resource loader、
Cordis / npm code は含みません。catalog は起動時の provider tool description です。skill を含む store の
reopen には `--enable-skills` が必要で、同じ custom roots を指定して継続利用してください。upstream の
dynamic scoped registry / lifecycle semantics は引き続き未実装で、本 issue は open のままです。

native command hooks の初回対応（2026-10-09）: pinned upstream `hooks` と
`hooks-claude-code` を参照し、native `run` / `web` / `mcp` / `desktop` に明示的な
`--hooks-config PATH` を追加しました。初回範囲は `PreToolUse` / `PostToolUse` の command hooks、
literal exact matcher / `|` alternatives / `*`、JSON stdin、64 KiB config / stdin、各出力 16 KiB、
1–120 秒 timeout、process-group cancellation cleanup です。PreToolUse は engine の必要な approval 後に
実行され、hook の `allow` は approval を迂回しません。exit 2 と対応する `block` / `deny` は拒否し、
PostToolUse が拒否しても実行済み write / remote call は巻き戻しません。

PostToolUse に一致する tool は host outcome を `effect-known` source の durable event として hook の前に
checkpoint します。cancel / restore は既知の結果を順序通り settle し、external tool や hook を再実行しません。
通常の no-hook / no-match tool 経路には追加 event を書きません。keyless integration は explicit approval、
pre-denial、successful post-hook reopen、post-cancel と uncertain receipt replay / reopen、並列 read の結果順、
overflow / timeout / explicit cancellation を検証します。

これは upstream 互換全体ではありません。regex / partial wildcard、その他 event、async hooks と UserPromptSubmit command 以外の prompt hook types、
`ask` による新しい approval prompt、`additionalContext` 以外の feedback、`${CLAUDE_PLUGIN_ROOT}`、
hook-specific diagnostic event は未対応です。PostToolUse `additionalContext` は 2026-10-10 に bounded native path へ追加し、
per-call structured user message として全 correlated tool result 後に保存します。config / structured result は厳密に検証し、1–120 秒を上限とします。
hook command は設定した利用者の trusted shell code として動き、child environment は small allowlist に限定します。
新しい `effect-known` event source を含む store は dsh 0.1.5 以降で開いてください。以前の native snapshot は
0.1.5 で開けます。この additional durable content も既存 session capacity 上限を消費します。
全 upstream lifecycle / event coverage は未実装のため、本 issue は open のままです。

ACP の部分対応（2026-10-10）: pinned upstream `packages/acp` の automation-agent 方向を参照し、native `dsh acp` stdio
service を追加しました。ACP v1 の initialize / authenticate、session new / list / resume / set_config_option / prompt / cancel / close、ordered
text / resource-link prompt subset、generic committed update、engine の per-call approval を接続します。allow-once / reject-once は
pending native call ID、prompt generation、durable approval revision に結び、unknown / stale / cancelled response は許可しません。
cancel / close / EOF は durable native cancellation 後に active task を drain し、reopen は中断した provider / tool effect を再送しません。

ACP は root native session に結び付いた canonical workspace / ACP activity metadata を `sessions.json` envelope 内で永続化します。
`session/list` は canonical `cwd` filter と revision-bound 16-session cursor で newest ACP activity first の一覧を返し、read-only です。
`session/resume` は同じ workspace の inactive non-imported root session だけを接続に戻し、過去の `session/update`、provider / tool / approval
effect を replay せず、新しい prompt から保存 context を続けます。既存 0.1.9 envelope は引き続き読めますが、provenance のない session は
`acp-` ID prefix だけで自動採用しません。updatedAt は有効な host UTC clock がある場合のみ出し、ACP-managed activity を表します。
native runtime / CLI からの ACP 外 activity を global last-activity として推定しません。Native keyless tests は list pagination / canonical
filter / stale cursor、process restart、context continuation / no-replay、legacy / imported / forked / active / unknown / foreign workspace
rejection、resume / prompt / close fencing を確認します。

Pinned upstream の[`model-control.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/model-control.ts)、
[`session.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/session.ts)、
[`index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/index.ts)
にある standard `model` option と session response / update を参照して、per-session model selection を追加しました。native では startup
provider / auth route を固定し、API-key route は初期 model と `DSH_ACP_MODELS` の strict JSON string array、ChatGPT route は account-visible
catalog から選択します。環境 catalog は 16 KiB / 32 names / 256 characters per name までです。設定変更は session が idle / settled の時だけ
受け付け、active turn 中は拒否するため、複数 step / retry と foreground child は admitted model を保持します。model と非 secret route fingerprint は
provider protocol / auth mode / demo flag / provider-normalized API origin + path prefix を束ねて session metadata に保存しますが、raw URL、credential、ChatGPT account identity は保存しません。`/v1` suffix と trailing slash の等価 URL は同じ fingerprint になります。reopen 時の fingerprint 不一致または許可 catalog から消えた選択は、history / activity を変更せず拒否します。resume 後の turn は現在 host が管理する API key / ChatGPT account を使い、admitted turn 内の既存 account / generation fence は維持します。旧 0.1.10
ACP records without a model inherit the current startup model. Native tests / stdio fake-provider integration verify two simultaneous sessions route
independently, a busy mutation is rejected, retries and children retain the selected model, update notification precedes its response, changed base URLs
are refused, and a refused selection remains recoverable after the catalog is restored. Route tests cover omitted / explicit defaults, `/v1`, trailing slash, and a distinct endpoint.

これは ACP 全体の互換ではありません。接続あたり initialize は一度、session は起動時の単一 canonical workspace に限り、additional
directory と client MCP mounts は拒否します。prompt block は text と resource_link のみで、resource を fetch せず、image / audio /
embedded context、persistent grant、raw stream delta、provider switching / reasoning controls は提供しません。Pinned baseline の ACP
README も `session/load` を unsupported surface として明記しているため、load はこの実装の parity gap ではありません。JSON line は
1 MiB、nesting は 24、prompt は 16,384 characters、block は 64 個までです。authMethods は空です。実 provider credential を使う ACP
smoke test は未実行です。本 issue は open のままです。

LSP navigation の部分対応（2026-10-10）: pinned upstream
[`packages/lsp`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp)、
[`packages/lsp/lsp-stdio`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp/lsp-stdio)、
[`packages/lsp/tool-lsp`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp/tool-lsp)
を参照し、native `--lsp-config PATH` と `run` / `web` / `mcp` / `acp` / `desktop` 向け
`lsp` tool を追加しました。設定 server は必要な query まで lazy start し、trusted
direct-argv stdio process として動作します。対応 operation は `goToDefinition`、
`findReferences`、`goToImplementation`、`hover` です。extension-to-language routing、
one-based UTF-16 positions、SafeRoot による source / result path checks、transient
`didOpen` / query / `didClose`、bounded workspace-relative locations、UTF-16 / capability
negotiation、bounded Content-Length JSON-RPC、timeout / cancellation / malformed protocol /
disconnect 時の process-group cleanup、graceful close、per-call approval、durable config
fingerprint を実装します。`initializationOptions` / `configuration` の値は保存せず、非 secret
`settingsRevision` で設定変更を追跡します。

これは upstream LSP / Cordis ABI 全体の互換ではありません。remote server、hot reload、
dynamic provider、`didChange`、diagnostics UI、workspace edits、upstream pooled retry、
workspace 外 URI の結果は対象外です。失敗した request は自動 retry / replay しません。
poison された worker は次の独立した approved call で evict され、新しい worker を開始できますが、
失敗した call 自体は再実行しません。LSP server は利用者権限で動く trusted host code で、
workspace path boundary は OS sandbox ではありません。2026-10-10 に local macOS
`/usr/bin/clangd` を使った C definition lookup が成功し、keyless
fake-server tests でより広い protocol / failure paths を検証しました。これは単一 server の local smoke
であり、cross-language、Linux/V8、live-provider acceptance は確認していません。本 issue は open のままです。

Native session TODO の部分対応（2026-10-10）: provider catalog に内部
`todo_write` tool を追加し、per-session visible checklist の全置換、trim / unique / status / single-active
validation、bounded list、`todo/write` event と model call / completion / result の厳密な restore correlation を実装しました。
read/write barrier の順序を保ち、TODO 自体は host effect、approval、PreToolUse / PostToolUse hook を起動しません。
browser transcript、shared GPUI scene、native desktop transcript、session API / protocol projection に表示します。
new turn で clear し、completed checklist は次の turn まで保持し、validated fork は履歴と projection を継承します。
legacy 0.1.7 store と以前の `Unknown tool: todo_write` result は読め、imported v4 は inert のままです。
これは native v1 runtime の bounded subset であり、upstream TODO package の完全な lifecycle / UX parity は確認していません。
keyless engine、provider/API、runtime persistence、browser / desktop presentation tests を追加しました。本 issue は open のままです。

Foreground subagent の部分対応（2026-10-10）: pinned upstream
[`tool-subagent`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/subagent/tool-subagent)
と in-process spawn package を参照し、native `run` / `web` / `mcp` / `acp` / `desktop` の
`--enable-subagents` opt-in tool を追加しました。child は親 transcript を継承せず、同じ configured provider / model route で fresh engine の
foreground loop を実行し、SafeRoot / protected runtime-store checks を通る `read` / `glob` / `grep` だけを使います。
result JSON は 16,384 UTF-16 code units、16 transcript messages、3 model steps、8 child tool calls、90 秒に制限し、parent
session/effect/tool-call と相関させます。parent turn は最大二 child calls、runtime は同時に一 child に制限し、parent cancellation は queued / active
child work に伝わります。keyless fake-provider tests は child read + second response + parent continuation、limits、recursive/write denial、hook denial、
provider / queued cancellation、restore no-replay を確認しました。

これは upstream subagent lifecycle の全実装ではありません。child session は独立保存・再開せず、interruption 前に settlement した result だけが
parent tool result に残ります。background / continuable mode、provider selection、tool filters、persona、structured output schema、provider capability
negotiation、child-specific UI は含みません。Configured PreToolUse / PostToolUse hooks は child reads にも継承され、trusted host code として副作用を
起こし得ます。reopen には `--enable-subagents` が必要で、中断した child は replay しません。本 issue は open のままです。

受入条件:

- plugin mount / teardown 中の依存、保有リソース、tool 呼出しを一貫して扱う。
- 子 agent / process / external tool を親の cancel で停止し、再開時に重複実行しない。
- 各拡張に成功・拒否・timeout・切断・reopen の結合テストを追加する。

## 4. Provider と UI の機能範囲

画像 / file、thinking signature の保存と replay、mid-conversation system / tool update、model discovery を追加する。
gpui を使って settings、attachment preview、workspace change、terminal / subagent 表示へ広げる。
native window は browser と共有できる state / scene を保って別の host adapter として実装する。

受入条件:

- 保存して再読込した request を provider が受理でき、失われる metadata を明示する。
- 実 API 検証は認証をログへ残さず、keyless fixture の検証と区別して記録する。
- native target で window、入力、IME、resize、close の実機検証を完了する。

## 5. Host と運用

OS sandbox、persistent terminal、SSH workspace、job / schedule、認証付き remote API を独立した host capability として追加する。
現在の loopback / local workspace の挙動を維持し、利用者が有効化した機能だけを公開する。

受入条件:

- 対応 OS ごとの filesystem / process 権限と recovery を検証する。
- remote API には authentication / authorization と複数利用者の分離を導入する。
- 新しい production package を mutation gate に追加し、単なる mutant 列挙を成功扱いしない。

## gpui-mbt 依存の追跡

`hotpath.mbt` の固定 revision は standalone LICENSE / manifest license field を含まない。
dependency の license metadata が upstream に追加されたら確認し、pin と第三者通知を更新する。
この repository の MIT 表記を依存ソースに転用しない。
