# 0001: DeepSeek Harness の残りの機能を MoonBit へ移植する

状態: open。最初の browser / CLI 実行経路は [移植状況](../../docs/port-status.md) を参照。
Model: gpt-6-luna
Updated: 2026-10-07
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
external MCP client、ACP、hooks、LSP、skills、subagent の順に相関と終了条件を仕様化する。
Cordis / npm plugin をそのまま動かす場合は別の互換 host を設計し、MoonBit-only plugin とは区別する。

部分対応（2026-10-07）: `effect: "read"` に静的分類した連続 tool call は最大 4 件の rolling pool で並列実行し、
各 `tool/request` の checkpoint 後に host IO を始めます。out-of-order completion は call / effect ID とともに durable staging し、
`tool/result` と次の model context は call 順を保ちます。Write / Shell、unknown tool、schema-invalid call は先行 read group を drain する barrier
です。cancel / restore は新しい work の dispatch を止め、既知の成功を保持し、unknown outcome を再生しません。pinned upstream
parallel-tool-calls fixture の keyless runtime 経路と、pool refill、barrier、approval、cancel、capacity、reopen を検証します。
upstream default pool size 10 ではなく 4 に制限し、dynamic safety classification、parallel write / shell、full upstream tool policy は
引き続き未実装です。本 issue 全体は open のままです。

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

## 6. ハーネス機能差レビューの補足（2026-10-09）

上記 1〜5 節で追跡済みの session/replay、live compaction、Cordis/MCP/subagent、
並列 Read、sandbox/SSH/terminal、画像/attachment、UI の要件は重複して列挙しない。
今回の [公式 architecture](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) /
[package map](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/README.md) との比較で、
未明文化だったハーネス機能群と完了判定を追加する。以下は実装完了の宣言ではなく **parity backlog** である。

| 未明文化だった領域 | 現状・既存節との関係 | 追加する受入条件 |
| --- | --- | --- |
| Agent orchestration: `goal` / `plan` / `todo` / `workflow`、experimental Agent Teams | §3 の subagent、§5 の job/schedule は対象だが、目標・計画・タスクボード・協調実行の live semantics を未指定。現状は v4 import の inert metadata のみ。 | 親子/チームの所有権、タスク受渡し、終了・失敗・cancel・reopen の各状態を永続イベントから復元し、重複委譲・二重実行を防ぐ。experimental 機能は別 gate にする。 |
| 外部情報・操作: Web search / public HTTPS fetch、browser-use / computer-use | §3 の外部 MCP / Skills と §5 の host capability とは別の tool/provider 群。現状 live 実装なし。 | ネットワーク宛先制限、権限、timeout、出力上限、cancel と途中失敗を provider ごとの結合テストで確認する。ブラウザ/デスクトップ操作は対象ウィンドウと操作先を識別し、誤操作を拒否する。 |
| Interaction: permission preset、account authorization、ask-user | §3 の動的 tool policy、§5 の認証付き API を補完する。個別 tool Allow/Deny は既存だが、公式の preset / authorization / 対話ツールとは非互換。 | workspace・agent・session の policy scope、承認変更・失効・拒否、対話応答待ち、再接続・復元時に権限が昇格しないことを検証する。 |
| 外部アプリ統合: TypeScript/Python SDK、SDK JSON-RPC / ACP wire protocol | §3 に ACP はあるが、独自 gpui MCP server の提供と公式 SDK/ACP wire compatibility は異なる。現状公式互換なし。 | supported protocol/version を明示し、外部 client との handshake、request/response、stream、cancel、resume、error mapping を conformance fixture で検証する。互換でない部分は明示する。 |
| Session query / observability: searchable history、lineage、OTel telemetry | §1 の session replay と §5 の運用を補完する。現状 API timing 集計のみで、公式相当の session-query / OTel は未実装。 | 複数 session の検索・fork lineage・境界付き取得を reopen 後にも確認する。telemetry は無効化・機密情報の除外・export failure 時の動作を検証する。 |
| 実行環境の差: PowerShell、persistent PTY、platform-specific sandbox | §5 の sandbox/terminal に包含されるが Windows の shell parity と OS 別境界が未明文化。現状 bash のみで OS sandbox なし。 | macOS/Linux/Windows 別の権限境界と process-tree 停止を明示し、使えない安全機構では fail-closed とする。 |

### Parity の判定方法

- **基準を分離する:** 現行移植基準 `5badb15009ae1756c3afe0ae0cef1faafc290ccc`（0.2.1-alpha.1）に存在する機能と、
  公式 `master` に後から追加された機能は、実装着手前に upstream commit/feature provenance を確認して区別する。
  上表に挙げたすべてが固定基準に存在したとは扱わない。
- **サーバーとクライアントを分離する:** gpui MCP **server** が動くことを外部 MCP **client** 対応の PASS としない。
  同様に native API の存在を公式 SDK / ACP wire 互換としない。
- **ステータスを分離する:** `implemented` / `fixture PASS` / `live acceptance PASS` / `not run` /
  `not implemented` を受入記録で区別する。SIWC 実アカウント、実 Tailnet、iPhone 実機の未実行 gate は
  [実装状況](../../docs/implementation-status.md) に従い、fixture 成功だけで閉じない。
- **優先順:** 長時間会話の context 管理（§2）→ MoonBit の動的 service 境界（§3）→ MCP client/Skills/LSP（§3）→
  subagent と orchestration（§3・本節）→ sandbox / SDK・ACP compatibility（§5・本節）。
  本節は既存 §1〜5 の要件を置換せず、未記載領域を追跡対象にする。

## gpui-mbt 依存の追跡

`hotpath.mbt` の固定 revision は standalone LICENSE / manifest license field を含まない。
dependency の license metadata が upstream に追加されたら確認し、pin と第三者通知を更新する。
この repository の MIT 表記を依存ソースに転用しない。
