# 0001: DeepSeek Harness の残りの機能を MoonBit へ移植する

状態: open。最初の browser / CLI 実行経路は [移植状況](../../docs/port-status.md) を参照。
Model: gpt-6-luna
Updated: 2026-10-09
upstream baseline は `5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

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
external MCP client と workspace skills は限定対応済み。ACP、hooks、LSP、subagent の順に相関と終了条件を仕様化する。
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
