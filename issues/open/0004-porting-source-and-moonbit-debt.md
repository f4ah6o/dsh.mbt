# 0004: 移植元の不備と MoonBit 移植負債を記録し、後続の独立した改修でまとめて整理する

Status: open
Model: gpt-6-luna
Created: 2026-10-10
Updated: 2026-10-11
Branch: docs/20261010-porting-debt-register
Upstream baseline: [DeepSeek Harness 5badb15009ae1756c3afe0ae0cef1faafc290ccc](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc)
Port snapshot: [dsh.mbt 82b8a985341105bb0197e3dc8c6b4f9f34b53500](https://github.com/f4ah6o/dsh.mbt/tree/82b8a985341105bb0197e3dc8c6b4f9f34b53500)
Related: [0001 upstream parity](0001-upstream-parity.md) / [0003 native・MoonBit 設計](0003-moonbit-native-ios-tailnet-roadmap.md) / [移植状況](../../docs/port-status.md)

## 概要

DeepSeek Harness → dsh.mbt の移植時に見つけた不備を、移植と同時に修正して作業範囲を広げないための**保留台帳**とする。機能不具合だけでなく、MoonBit の型・エラー・所有権・非同期・モジュール設計・テストのプラクティスから外れた実装も対象にする。

- **0001** は「何を移植するか／どこまで互換か」の追跡。**本台帳**は「移植時に維持した不備・構造と、移植後に改善するべき品質上の課題」の追跡。
- **0003** は MoonBit 化の設計原則。本台帳は実際の箇所、根拠、改修条件を紐付ける。
- 移植元の実装上の欠陥と、移植により生じた MoonBit 固有の負債を混同しない。upstream 固有の不備を確証なしに「バグ」と呼ばない。
- 同じ機能差分でも、未移植なら 0001、実装済みコードの修正課題なら本台帳へ記録する。必要なら相互参照する。

## 背景

原典の構造を保った段階的な移植では、互換性の確認と設計改善を同じ変更に混ぜると、動作差の原因を追跡しにくい。

## 問題

移植中に確認した改善候補をチャットだけに残すと、出典、確度、意図的に維持した理由、後続の回帰条件が失われる。

## 目標

非不具合の不備を維持した事実と、修正した動作不具合の根拠を、固定した原典・移植先の参照とともに蓄積する。

## 対象外

本 PR での production code の変更、横断的リファクタリング、upstream への自動投稿、完全な機能互換の宣言。

## 対象と分類

| 起点 | 意味 | 記録例 |
| --- | --- | --- |
| `UPSTREAM` | 固定した DeepSeek Harness 原典にある、不具合・設計・テスト・安全性の課題 | 再現可能な動作不具合、互換性を壊す曖昧な契約、検証不足 |
| `PORT` | dsh.mbt の移植実装・移植アダプタで発生した課題 | デコード境界の重複、永続形式と型の不整合、移植特有の回避策 |
| `MOONBIT` | MoonBit のプラクティスの観点から改善したい課題 | 文字列の内部 dispatch、動的 Json payload、型を使える箇所での文字列エラー、不要なコピー |
| `CROSSCUT` | 原典・移植先を横断する課題 | 処理系間での意味の不一致、fixture・計測・移行ガイドの不足 |

種類は `bug` / `security` / `correctness` / `compatibility` / `design` / `idiom` / `performance` / `testing` / `docs` の複数選択可。種類・優先度・確度を区別する。**設計改善の候補があることは不具合の存在を意味しない。**

### 1 件の記録に必要な項目

- ID（例: `DEBT-001`）、起点、種類、優先度（未査定可）、状態（`observed` / `hypothesis` / `reproduced` / `accepted` / `in-progress` / `fixed` / `wontfix`）。
- **出典**: upstream の commit + package/path、移植先の commit + path。該当しない側は `N/A` とし、`main` や `latest` のみで根拠を固定しない。
- **観測事実**と**懸念・仮説**を別々に書く。エラーなら場所・原因（未確定なら未確定）・対処候補を分離する。影響先と再現条件を書く。
- **互換性判断**: upstream の振る舞いを維持すべきか、安全性のため意図的に異ならせるか。schema / provider / tool / session への影響も明記する。
- **後続の是正方針**、完了条件、必要な回帰テスト。検証済み・未実行・未確認を明記する。修正先 PR と残課題を追記できるようにする。

## 提案する方針

1. 移植元の不備や MoonBit のプラクティスに合わない構造も、**動作不具合を除いてそのまま移植する**。発見はこの台帳へ追記し、この PR のブランチへ追加コミットとして積む。ついでの大規模リファクタリング、API 改変、スタイル一括修正は行わない。確認に時間を要するものは `hypothesis` として残す。
2. 移植作業の変更と後続の品質改善は別 PR とする。移植の受入では parity の評価と負債の記録を分ける。小さな移植スライスが完了した区切りで、同じ原因の負債を束ねて専用 PR で修正する。
3. 確認できた**動作不具合は移植時に修正する**。安全・秘密情報漏えい・データ損失・外部作用の無断実行・復旧不能を含め、重大度にかかわらず再現と是正の根拠を記録する。原典の不具合と移植固有の不具合を区別し、記録を理由に必要な修正を延期しない。
4. upstream 自体は read-only として扱う。この台帳に書くことは upstream への issue / PR 提出を意味しない。差異を隠すために fixture や test を書き換えない。
5. 後続改修では同じ契約を横断して揃える。`typed internal state → explicit wire codec → durable replay` の順に検証し、snapshot migration、old data、cancel、approval、no-replay、並列 tool order を維持する。簡略化のために境界の検証を削らない。
6. `wontfix` / `fixed` は判断理由と証拠を残して閉じる。開いた項目の消去・単なる日付更新で「解決」としない。参照する baseline が変わった場合は再照合する。

## 初期台帳（2026-10-10、ソースを読んだ範囲）

以下の「観測事実」は固定 commit のコードから確認した構造。実行時の不具合を再現したという意味ではない。**今の時点で特定の upstream バグを確認したものはない**。新たに検証できた原典側の問題は `UPSTREAM` として同じ台帳へ追記する。

| ID | 起点 / 種類 | 状態 | 根拠 | 観測・懸念 | 後続の整理方針 |
| --- | --- | --- | --- | --- | --- |
| **DEBT-001** | `MOONBIT / idiom, design` | `observed`・優先度未査定 | [engine/types.mbt Event](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/types.mbt#L88-L94), [engine/engine.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/engine.mbt), [engine/domain.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/domain.mbt) | `Event.kind` は `EngineEventKind` だが `Event.data` は汎用 `Json`。`Session::append` は文字列名を `from_wire` で enum 化する。payload と kind の不正な組合せをコンパイル時には防ぎきれない可能性がある。実害は未確認。 | native event の生成を型付き payload に段階移行し、`upstream/event` / unknown wire は別経路で保持。永続 JSON は明示 codec に固定し、旧ログ復元 / 不明 event 拒否 / effect 不再実行を回帰確認。 |
| **DEBT-002** | `MOONBIT, PORT / idiom, design` | `observed`・優先度未査定 | [engine/types.mbt Effect](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/types.mbt#L142-L150), [engine/domain.mbt EngineEffect](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/domain.mbt) | effect の kind / ID は型付けがあるが request 本体は `Json`。provider と tool に使えるフィールドや validation の契約が型で表されない。境界は現状意図的に Json を用いているため、これ自体を動作バグと断定しない。 | provider / tool request を内部 ADT または typed record に分け、transport に渡す直前でのみ Json 化。現行プロトコル・checkpoint 順序・重複 completion 拒否を変えず fixture で比較。 |
| **DEBT-003** | `MOONBIT / idiom, design` | `observed`・優先度未査定 | [engine/engine.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/engine.mbt#L35-L49), [engine/domain.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/domain.mbt), [api/api.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/api/api.mbt#L19-L44) | `EngineCommand` などは型付きだが、複数の command API / parse 経路で `Result[..., String]` が残り、エラー分類は文字列から再解釈できない。`EngineError` も部分的に存在するため「全部 String」の状態ではない。 | 期待された拒否・状態競合・永続化障害の error taxonomy と API 変換を統一するか検討。旧 wire message / caller 互換を契約として保持し、必ず失敗系を test 化。 |
| **DEBT-004** | `MOONBIT, PORT / design, performance, testing` | `observed`・優先度未査定 | [engine/transaction.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/transaction.mbt#L41-L105), [engine/transaction.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/transaction.mbt#L130-L160) | transaction / capacity 判断で `Session::copy_state` による多数フィールドの個別コピーと `Engine::copy_state` がある。状態追加時のコピー漏れ・サイズと時間の増加が懸念。コピー不足や性能劣化の再現は未実行。 | 更新範囲の絞り込みや state の凝集を測定後に検討。mutation の atomicity・restore/fork・負荷 fixture の比較を必須にし、根拠なく deep copy を除去しない。 |
| **DEBT-005** | `PORT / design, testing` | `observed`・優先度未査定 | [api/api.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/api/api.mbt#L56-L87), [engine/domain.mbt](https://github.com/f4ah6o/dsh.mbt/blob/82b8a985341105bb0197e3dc8c6b4f9f34b53500/engine/domain.mbt) | API の operation schema と `EngineCommand::from_json` で近いフィールド契約を別々に記述する。防御的な重複検証は正常だが、将来の追加時の schema drift は検証候補。現時点の契約不一致は未確認。 | 入力の権威ある定義と境界ごとの責務を決め、contract test で schema/decoder 差分を検出。既存の二重防御を無批判に消さない。 |

### DEBT-006: command hook の transcript_path が空文字のまま

- 起点・種類・優先度・状態: `UPSTREAM, PORT / compatibility, design, docs`、優先度未査定、`observed`。
- upstream baseline / path: [`5badb150` の hooks-claude-code/src/index.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts)、`base` の `transcript_path: ''`。原典のコメントも persistence seam が artifact path を提供しない制約と説明する。
- port baseline / path: [`30da581` の runtime/hooks_runtime.mbt](https://github.com/f4ah6o/dsh.mbt/blob/30da581bc600a87355b20e7583aa7e7f87ae8d29/runtime/hooks_runtime.mbt)、`native_hook_payload` の `("transcript_path", Json::string(""))`。
- 観測事実 / 確認: 固定した両ソースを読み、hook stdin のフィールドが空文字になることを確認。外部 hook の障害を再現した結果ではない。
- 不明点・影響: `transcript_path` から履歴を読む既存 hook の互換性には制限がある。そのような hook の実行検証は未実施。実行時の不具合を確認したものではない。
- 互換性判断: 今回は原典と同じ空文字を維持する。native envelope のパスを、Claude Code transcript 互換ファイルのように渡さない。
- 後続改修方針: hook 向け transcript artifact を提供する場合は、schema、公開範囲、更新時点、読み取り権限、削除 lifecycle を独立に設計する。
- 完了条件・回帰テスト: 明示した transcript format を実 hook が読み、保存失敗・cancel・reopen・削除後の参照を検証できること。対応しない判断なら理由とともに `wontfix` を記録する。
- 修正 PR / close 判定: 未着手。今回の移植で維持する原典側の制約として記録。

### 0.1.12 PostToolUse 移植で維持した構造

機能実装の固定 snapshot は [`56d27f12`](https://github.com/f4ah6o/dsh.mbt/tree/56d27f12b576a8779421f44a5e351c76d29d527f)。以下は既存項目の追加根拠であり、新しい動作不具合の報告ではない。

- **DEBT-001**: [`engine/tool_calls.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/56d27f12b576a8779421f44a5e351c76d29d527f/engine/tool_calls.mbt#L238-L266) の completion は、既存の汎用 `Json` event payload に `additional_contexts` を追加する。同ファイルの `post_tool_context_message` も role / source / text block を Json で構築する。原典のメッセージ形と既存の永続 codec を保ち、今回の移植では型付き payload への横断的な置換を行わない。
- **DEBT-003**: [`runtime/hooks_codec.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/56d27f12b576a8779421f44a5e351c76d29d527f/runtime/hooks_codec.mbt#L98-L103) は成功値を `NativeHookOutcome` として型付けする一方、拒否・decode・上限の失敗は既存方針の `String` を使う。文字列エラーを保持する判断と、成功状態の型付けを区別して記録する。
- **DEBT-004**: [`engine/transaction.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/56d27f12b576a8779421f44a5e351c76d29d527f/engine/transaction.mbt#L62-L72) は追加した `completed_contexts` も個別にコピーする。既存の atomicity 方針を保った追加であり、コピー不足や性能劣化を確認したものではない。後続の状態整理ではこのフィールドも restore / cancel / transaction 回帰の対象とする。

確認方法は固定 source の静的照合。性能測定と typed payload / error taxonomy への改修は未実施。これらの改善は parity 移植とは独立に扱う。

### DEBT-007: 終了時の受理済み PostToolUse context 保存漏れ

- 起点・種類・優先度・状態: `PORT / bug, correctness`、復元を妨げるため優先度高、`fixed`。
- upstream baseline / path: N/A。移植先の終了処理と replay 契約の不整合であり、原典のバグを確認したものではない。
- port baseline / path: [`a8b02fea` の engine/engine.mbt](https://github.com/f4ah6o/dsh.mbt/blob/a8b02feaeadcfb475aff575af49a4c062dd671f3/engine/engine.mbt#L758-L786)、`Engine::terminate`。通常経路の `commit_ready_tool_results` と異なり、残りの tool result を保存した後に受理済み context を保存せず calls を clear していた。
- reproducer / 確認: 独立レビューの native whitebox probe で、並列 read 2 件の先頭を `additional_contexts` 付きで完了してから cancel すると、snapshot restore が `PostToolUse context is missing, reordered, or differs from its completion` を返す。後方の read を context 付きで完了した active snapshot では、最初の restore は成功するが、その結果の snapshot を再度 restore すると同じ拒否になる。両 probe の失敗を確認。
- 影響・互換性判断: 受理済み context を持つ終了 session が復元不能になり得る。今回の移植候補で発見した動作不具合のため、負債を残す方針の対象にせず公開前に修正する。
- 是正方針・回帰条件: 終了処理でも全 tool result の後、calls clear / step end より前に受理済み context を保存する。cancel、interrupted restore、capacity closure と繰り返し restore を検証する。post-hook 中の cancel で未受理の context は追加しない。
- 修正 commit / close 判定: [`2c792853`](https://github.com/f4ah6o/dsh.mbt/commit/2c792853279ff1a5f2b69ab8edc4e3b91bd2eaa9) で終了時の context 保存と回帰テストを追加。実装担当の engine native suite は 79 / 79 PASS。独立レビューで元の 2 probe は 2 / 2 PASS、cancel / interrupted restore、capacity closure、post-hook 中の未受理 context 排除も各 1 / 1 PASS。修正後の 3 パスレビューで新たな指摘はない。動作不具合の修正として閉じ、DEBT-001 / 003 / 004 の設計改善候補は開いたまま維持する。

### 0.1.13 UserPromptSubmit 移植で維持した構造

機能実装の固定 snapshot は [`b6f07c6d`](https://github.com/f4ah6o/dsh.mbt/tree/b6f07c6d580179ac508c3a4463b4426f3f3b98b4)。実装は `gpt-6-luna / max`、独立レビューは `gpt-6.1-sol / xhigh`。以下は既存項目の追加根拠であり、動作不具合の報告ではない。

- **DEBT-001**: [`engine/engine.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/engine/engine.mbt#L123-L157) と [`engine/tool_calls.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/engine/tool_calls.mbt#L16-L29) は、受理した prompt の後に原典と同じ source 付き user message を既存の Json event として追加する。複数 hook の context は 1 メッセージ内の text block に順序を保ってまとめる。型付き event payload への横断的な改修は行わない。
- **DEBT-003**: [`runtime/hooks_codec.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/hooks_codec.mbt#L257-L261) と [`runtime/runtime.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/runtime.mbt#L606-L679) も、成功値は型付き outcome、拒否や上限の失敗は String という既存の契約を維持する。型付き command の `SendPrompt(SessionId, String)` は保持し、内部 context を伴う別 variant を追加する。
- **DEBT-005**: [`engine/domain.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/engine/domain.mbt) の command decode / validate、[`engine/persistence.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/engine/persistence.mbt) の保存 event validation、[`runtime/hooks_codec.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/hooks_codec.mbt) の hook output decode に、context の長さ・件数・合計量の検証が分かれて存在する。境界ごとの防御を保持した観測であり、契約不一致を確認したものではない。
- **DEBT-006**: [`runtime/hooks_runtime.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/hooks_runtime.mbt#L33-L46) の UserPromptSubmit payload でも原典と同じ空の `transcript_path` を維持する。

確認方法は固定 source の静的照合。設計改善、性能測定、live provider / 外部 hook 製品との互換性検証は実施していない。最終的な feature 検証と独立レビュー結果は、結果が確定した後に追記する。

### DEBT-008: 原典の hook 出力にある未反映 control を維持

- 起点・種類・優先度・状態: `UPSTREAM, PORT / compatibility, design, docs`、優先度未査定、`observed`。
- upstream baseline / path: [`5badb150` の hooks-claude-code/src/index.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L181-L201)。`updatedInput` / `systemMessage` は警告して未反映、merge された stop は run-level halt mechanism が必要という TODO のまま。UserPromptSubmit listener は deny と additional context を消費する。
- port baseline / path: [`b6f07c6d` の runtime/hooks_codec.mbt](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/hooks_codec.mbt#L257-L355)、`native_hook_prompt_result_decision`。今回の prompt hook subset は `continue` / `stopReason` / `updatedInput` / `systemMessage` を実行制御や provider input の書換えに使わない。
- 観測事実 / 確認: 固定した原典と port のソースを照合した。原典に未反映の明示がある control を port の機能として新規実装しなかった。原典と port の診断ログや full output record は同一ではなく、今回の互換対象は prompt admission と context の挙動に限る。
- 不明点・影響: これらの control に依存する既存 hook は期待した停止・書換え・system message 表示を得られない可能性がある。特定 hook の動作不具合は再現しておらず、原典の動作バグと断定しない。
- 互換性判断: 非不具合の原典側制約を維持する指示に従い、今回の port では適用範囲を拡張しない。deny / blocking exit の拒否と bounded additionalContext は別に実装する。
- 後続改修方針: run halt、prompt rewrite、診断表示を別の capability として設計し、許可境界、receipt、checkpoint、cancel、replay の契約をそろえる。
- 完了条件・回帰テスト: control 単独と競合する hook の結果、拒否前後の履歴、provider 不実行、停止中の cancel、durable reopen / no replay を固定 fixture で検証する。未対応を維持する場合は公開契約と理由を記録して `wontfix` とする。
- 修正 PR / close 判定: 未着手。今回維持した原典の制約として登録する。

### UserPromptSubmit 独立レビューで見つかった動作不具合

以下はいずれも `PORT / bug, correctness`、優先度高。原典のバグではなく、公開前に修正する。固定した不具合 snapshot は [`b6f07c6d`](https://github.com/f4ah6o/dsh.mbt/tree/b6f07c6d580179ac508c3a4463b4426f3f3b98b4)。upstream の出典は各項目とも N/A。

#### DEBT-009: prompt context の復元 decoder が誤った値を読む

- 状態 / 根拠: `fixed`（初回は static `observed`）。[engine/persistence.mbt:1213](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/engine/persistence.mbt#L1213) が、text block の Json::String を object + key 用の `required_string` に渡す。
- 確認 / 影響: 復元 decoder の誤った引数は独立レビューの静的照合で確認。受理した prompt context を含む保存データを正しく復元できない経路がある。同レビューの `moon test engine --target native --frozen --target-dir /tmp/dsh-user-prompt-review-20261010 --filter '*UserPromptSubmit*'` は 0 / 1 FAIL、EngineError.Invalid だったが、当時の fixture は復元より前に表示用 content を誤って配列として読むため、この結果を decoder 単独の再現根拠にはできない（DEBT-015）。
- 是正 / 完了条件: 元 block の `text` を bounded string として読む。grouped context の snapshot restore、native close / reopen、no-hook replay を検証する。
- 修正 / 検証: `f7e9856` で decoder を修正し、`3176fa4` / `76d1893` で snapshot / 表示 projection の fixture を是正。初回の native check で見つかった追加テストの 4 件の型エラーも是正済み。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-010: pre-admission hook の予約が cancel fence に届かない

- 状態 / 根拠: `fixed`（初回は static `observed`）。[runtime/runtime.mbt:645](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/runtime.mbt#L645) の direct と同ファイルの MCP path は revision + 1 で予約するが hook 前に checkpoint しない。[scheduler.mbt:200](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/scheduler.mbt#L200) は厳密な `< cancel_revision` を使う。
- 確認 / 影響: 独立レビューの静的経路追跡。直後の cancel が予約と同じ revision となり、実行中の hook を中断できない。remote receipt path は先に checkpoint しており、この原因は共有しない。初回報告時点では実行 probe は未実施。
- 是正 / 完了条件: hook 前に予約リビジョンを checkpoint し、後続 command 用の既存 fence を弱めない。direct / MCP / remote の中断、turn / provider 未作成、子プロセス cleanup、次の送信を検証する。
- 修正 / 検証: `f7e9856` で direct / MCP の予約 checkpoint を修正。explicit cancellation の理由分類と remote regression は [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) を参照。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-011: owner task の cancel 後に hook 実行枠が残る

- 状態 / 根拠: `fixed`（初回は static `observed`）。[runtime/runtime.mbt](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/runtime.mbt) の direct / remote / MCP は `handle_cancellation` 後、保護されていない gate acquire を使う。pinned async は catch 後も cancellation を pending に保つ。
- 確認 / 影響: 独立レビューの静的経路追跡。再度の cancel で scheduler.finish に届かず、同じ session の後続送信が busy になり続ける経路がある。初回報告時点では実行 probe は未実施。
- 是正 / 完了条件: gate ownership、予約、reacquire / receipt / finish / release を cancellation-safe にする。owner cancel 後の process cleanup、未 admission、fresh command の受理、remote reservation の状態を検証する。
- 修正 / 検証: `f7e9856` で cancellation-safe な cleanup を修正。owner cancellation の receipt / no-replay / process cleanup / fresh send を確認。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-012: 内部 context が外部 API schema に拒否される

- 状態 / 根拠: `fixed`（初回は static `observed`）。[api/api.mbt:71](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/api/api.mbt#L71) の session_send schema は session_id / prompt のみ。runtime が注入する additional_contexts は unknown field として拒否される。
- 確認 / 影響: 独立レビューの静的 schema / handler 経路照合。context を返す hook の送信を admit できない。初回報告時点では runtime fixture の実行は未実施。
- 是正 / 完了条件: 外部 schema を維持し、信頼済み hook context だけを内部 dispatch へ渡す。direct / remote / MCP の grouped context と forged-context stripping を検証する。
- 修正 / 検証: `f7e9856` で scoped trusted context dispatch を実装。外部の closed schema を維持し、direct / remote / MCP の grouped context と caller context stripping を確認。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-013: 不正な送信でも hook が先に外部作用を起こす

- 状態 / 根拠: `fixed`（初回は static `observed`）。[runtime/runtime.mbt](https://github.com/f4ah6o/dsh.mbt/blob/b6f07c6d580179ac508c3a4463b4426f3f3b98b4/runtime/runtime.mbt) の preflight は EngineCommand decode を使い、closed capability schema、完全な MCP envelope / metadata、serialized state capacity を検証しない。
- 確認 / 影響: 独立レビューの静的経路追跡。unknown input field は hook 実行後に API が拒否する。MCP notification や不正 envelope でも intercept が通常 router の拒否 / 無応答判定より前に hook を始める。少ない event 数でも serialized capacity による拒否がある。初回報告時点では実行 probe は未実施。
- 是正 / 完了条件: 本来の capability / transport / engine admission を、副作用なしで hook 前に preview する。不正 field / JSON-RPC / metadata / notification / capacity fixture の hook counter が増えず、turn / provider も作成されないことを検証する。
- 修正 / 検証: `f7e9856` 以降の Engine preview / original MCP envelope preflight / sanitized trusted dispatch で修正。不正入力・notification の hook 不実行は runtime fixture で確認。capacity の admission 拒否は preview の source 照合と既存 engine capacity tests が根拠で、capacity + hook counter の runtime fixture は未追加。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-014: event-specific な拒否理由の優先順位が異なる

- 起点・種類・優先度・状態: `PORT / bug, compatibility`、優先度低（独立レビューの minor）、`fixed`（初回は `observed`）。
- upstream baseline / path: [`5badb150` の hook-protocol/codec.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts)。matching hookSpecificOutput の permissionDecisionReason は permissionDecision の有無・有効性と独立に top-level reason を上書きする。原典の不具合ではない。
- port baseline / path: [`3176fa4` の runtime/hooks_codec.mbt](https://github.com/f4ah6o/dsh.mbt/blob/3176fa453e0b1ca4db66f23a695eafbbd1dc19a7/runtime/hooks_codec.mbt)、native_hook_prompt_result_decision。
- 観測事実 / 影響: 独立レビューの静的照合。legacy block と matching permissionDecisionReason があり、permissionDecision がない / 無効な場合、port は top-level reason を残す。拒否判断は維持されるが native caller に返す理由が decoder の優先順位と異なる。upstream bridge 自体が同じ理由を user に表示するという主張ではない。
- 是正 / 完了条件: event-specific reason を独立に適用し、permissionDecision なし / 無効 / allow / deny / ask と legacy decision の組合せを fixture で検証する。
- 修正 / 検証: `2d067c2` で event-specific reason の優先順位を修正。permissionDecision なし / deny、空 / 不正型 reason、event mismatch の codec fixture を確認。無効な permissionDecision / allow / ask と legacy decision の組合せは source 照合であり、専用の実行 fixture は未追加。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

DEBT-009–013 は [`f7e9856`](https://github.com/f4ah6o/dsh.mbt/commit/f7e9856f1f3a949a0ceda62bef4f1b68f437f015) で production code / regression source を修正し、[`3176fa4`](https://github.com/f4ah6o/dsh.mbt/commit/3176fa453e0b1ca4db66f23a695eafbbd1dc19a7) で settled context の restore fixture を是正した。最終 [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) の独立 `gpt-6.1-sol / xhigh` 3 パス / 7 categories source review は approve、残存指摘なし。[最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) は成功し、DEBT-009–017 の修正と回帰確認を記録した。

#### DEBT-015: 表示用 hook transcript と内部 text block の fixture が混同される

- 起点・種類・優先度・状態: `PORT / bug, testing`、優先度高（CI を停止）、`fixed`（初回は `reproduced`）。production の不具合ではない。upstream 出典は N/A。
- port baseline / path: [`39c0f73` の engine/engine_wbtest.mbt](https://github.com/f4ah6o/dsh.mbt/blob/39c0f732a9e7ca5711e08eb414c4d2efd8f6d099/engine/engine_wbtest.mbt#L341) と [runtime/hooks_wbtest.mbt](https://github.com/f4ah6o/dsh.mbt/blob/39c0f732a9e7ca5711e08eb414c4d2efd8f6d099/runtime/hooks_wbtest.mbt#L1513)。
- 再現 / 影響: [初回 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042285182) は portable 各 target 162 / 163、native-without-node は `hook test expected array MCP hook content` の panic で失敗。session.messages / MCP structuredContent は hook context を newline-joined string + display_label に投影するが、fixture は配列として読む。raw durable user/message event と provider request は text block 配列を維持する。MCP 応答は provider の background dispatch より前に serialize されるため、provider timing race を示す失敗ではない。
- 是正 / 完了条件: 表示用 string / source / 順序と、raw event / provider 側の一つに grouped した text block / 順序を両方検証し、表示と保存・送信の契約を混同しない。
- 修正 / 検証: `76d1893` で表示用 string と grouped event / provider block の両方を検証する fixture に修正。production は変更しない。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-016: キャンセル fixture が session_id も slow branch として判定する

- 起点・種類・優先度・状態: `PORT / bug, testing`、優先度高（CI を停止）、`fixed`（初回は `reproduced`）。production の不具合ではない。upstream 出典は N/A。
- port baseline / path: [`76d1893` の runtime/hooks_wbtest.mbt](https://github.com/f4ah6o/dsh.mbt/blob/76d18938ce173f28f797e073411f77c039d8bec8/runtime/hooks_wbtest.mbt#L1887)、direct session_cancel と remote owner cancellation の shell command。
- 再現 / 影響: [修正後 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042930510) の native-without-node は 325 / 328。2 件は follow-up の counter が期待 `xy` に対して `xx`。shell case は stdin JSON 全体を短い `direct-cancel` / `remote-owner` で判定するが、同じ文字列が session_id にも存在するため、新しい prompt でも x branch に入る。独立レビューの shell-only probe でも確認。scheduler 枠が残る不具合を示す結果ではない。
- 是正 / 完了条件: 最初の prompt にだけ含まれる固有文字列で判定し、キャンセル後の fresh send の受理・一回の hook 実行・provider effect・`xy` の検証を保持する。
- 修正 / 検証: [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で最初の prompt に固有な文字列へ fixture を修正。fresh send の受理、provider effect、counter `xy` と process cleanup を確認。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

#### DEBT-017: explicit cancellation が一般的な hook failure として返る

- 起点・種類・優先度・状態: `PORT / bug, correctness`、優先度低（独立レビューの minor）、`fixed`（初回は `reproduced`）。upstream 出典は N/A。
- port baseline / path: [`76d1893` の runtime/runtime.mbt](https://github.com/f4ah6o/dsh.mbt/blob/76d18938ce173f28f797e073411f77c039d8bec8/runtime/runtime.mbt#L2073)、MCP hook settlement。同ファイルの remote receipt settlement helper も同じ順序。
- 再現 / 影響: [同 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042930510) の MCP session_cancel fixture は `cancelled before admission` の理由判定で失敗。独立レビューの静的な cancellation 経路追跡では `Some(Err("hook process was cancelled"))` が control.cancelled の確認より先に一般 hook error として処理される。CI log 自体は理由 assertion の失敗を記録するが、実際の error string は出力していない。hook は中断され、turn / provider は未 admission だが、caller に返す理由が explicit cancellation を表さない。remote の同じ分岐は独立レビューの静的照合で確認し、同 transport の実行再現とは区別する。
- 是正 / 完了条件: owner / control cancellation を hook result より先に判定し、MCP と remote durable receipt の理由を揃える。未 admission、process cleanup、receipt replay、次の送信を回帰検証する。
- 修正 / 検証: [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で MCP / remote settlement の cancellation を hook result より先に判定。remote explicit session_cancel の rejected receipt / replay / 未 admission / process cleanup / fresh send の regression も追加。 [最終 CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) の固定 head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/commit/982f2b6f4b5fd364ebf0500a032bb210b753db9a) で native-without-node 329 / 329、portable 各 163 / 163、native runtime 156 / 156 PASS。local behavioral run は ENOSPC で完走していない。修正先は [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)。

### Stop command hooks の初回移植

機能の最初の reviewable snapshot は [`8250c9e`](https://github.com/f4ah6o/dsh.mbt/tree/8250c9edd512009805f317b2943bea891083deeb)。この記録は追加 runtime integration / docs と最終 CI の前の固定 source 照合であり、機能全体の最終受入ではない。

- **DEBT-001**: [`engine/types.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/types.mbt#L99-L105) の `Event.data` は引き続き汎用 `Json`。Stop pending / continuation の durable event も [`engine/stop_hooks.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/stop_hooks.mbt#L33-L45) で `object(...)` として組み立てる。既存 wire / replay codec を拡張した構造上の根拠であり、payload mismatch の実害は確認していない。
- **DEBT-003**: [`engine/stop_hooks.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/stop_hooks.mbt#L111-L147) の公開 engine 操作は `Result[Json, String]` を返し、内部の `Invalid(message)` を文字列 error に変換する。native Stop の成功 outcome は [`runtime/hooks_codec.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_codec.mbt#L262-L319) の `NativeStopHookResult` に分ける。文字列エラー境界を維持した証拠であり、分類の不足や挙動不具合を確認したものではない。
- **DEBT-004**: [`engine/transaction.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/transaction.mbt#L87-L95) の `Session::copy_state` は Stop pending、event sequence、staged continuation、admission、context count / length を個別に複製する。Stop hook の pending / continuation / restore fixture は engine Stop suite 3 / 3 PASS。copy omission や性能劣化を確認したものではない。
- **DEBT-006**: [`runtime/hooks_runtime.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_runtime.mbt#L212-L229) の Stop stdin は共通 payload と同じく空の `transcript_path` を渡す。Claude Code transcript 互換 artifact を提供しない原典制約を継続している。
- **DEBT-008 / 018**: Stop output の適用範囲と upstream の制約は次項を参照。native adapter 固有の decoder 制限は原典 bridge の制限と分けて記録する。

この snapshot で報告された core native check (`engine/api/runtime`) は PASS、hotpath warning は 3 件。engine `*Stop*` は 3 / 3、runtime `*Stop*` は 2 / 2（codec と ACP mapping）、diff check は clean。review copy の engine 87 / 87 は既存 80 + feature 5 + reviewer 追加 2 件、reviewer isolated copy の engine/api `--target all` は Wasm / Wasm GC / JS / native 各 96 / 96 PASS（追加 probe 2 件を含む）。いずれも PR production suite の結果として扱わない。これらは機能担当・独立 reviewer から受けた個別結果で、最終 CI は未実行。

#### DEBT-018: Stop hook の payload と output control に制約がある

- 起点・種類・優先度・状態: `UPSTREAM, PORT / compatibility, design, docs`、優先度未査定、`observed`。原典仕様上の未対応と native adapter の対応範囲を記録する。確認済み動作不具合ではない。
- upstream baseline / path: [`5badb150` の hooks-claude-code/src/index.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L273-L283) の Stop listener / loop guard、同ファイルの [`base` / `stopPayload`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L327-L352)、[README の Stop / common fields limitations](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/README.md#L179-L180)。共通 merge は `continue:false` を `stop` として記録する ([`merge.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts#L62-L99))。
- port baseline / path: [`8250c9e` の Stop payload](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_runtime.mbt#L212-L229)、[native Stop output decoder](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_codec.mbt#L262-L319)、[native Stop settlement](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/runtime.mbt#L2900-L2923)、[generic per-turn step bound](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/stop_hooks.mbt#L214-L220)。空 `transcript_path` は DEBT-006 に分類する。
- 観測事実 / 確認: upstream Stop payload は `stop_hook_active: false` 固定で、`last_assistant_message` / `background_tasks` / `session_crons` を省く。原典 Stop listener は `decision === deny` の reason を steering にして次の step を促すが、`continue:false` による `merged.stop` には run-level halt mechanism が必要という TODO があり、`stopReason` / `additionalContext` / `systemMessages` も listener から適用しない。README は専用 consecutive-block cap 未実装と記し、無条件 blocking hook は self-limit がなければ毎 step force-continue と説明する。port payload は同じ固定値と欠落フィールドを持つ。native Stop decoder は `decision` / `reason` と matching `hookSpecificOutput` の permission decision / reason を読み、`continue` / `stopReason` / `systemMessage` / Stop `additionalContext` を outcome に渡さない。`ask` は rank 2 に集約されるが、native Stop dispatcher は rank 3 の block のみ continuation にする。これらは固定 source の静的照合であり、当該 control に依存する hook の個別実行不具合を再現したものではない。
- 原典制約と native adapter 制約: 上記 payload 欠落、固定 `stop_hook_active`、専用 loop cap / run-level halt の TODO は upstream に明記された制約。出力項目のうち native adapter が decode しない範囲は port の bridge boundary として別に追跡する。port は連続 Stop continuation を既存 `max_steps` で終了させるが、これは Stop 専用 cap の実装ではない。
- 影響・互換性判断: loop state や assistant 最終文を参照する hook は必要な入力を得られない。Stop output control に依存する既存 hook は停止、追加 context、system message の反映を期待できない。既知の source 制約と adapter scope を維持する方針で記録し、特定の hook 障害・移植実装 bug とは断定しない。
- 後続改修 / 完了条件: payload source、run-level halt、Stop 固有の連続 block cap、output controls を独立に設計する。必要な場合は cap 到達、複数 hook の優先順位、cancel、再開、provider 未 dispatch、durable reopen / no replay を検証する。未対応を維持する判断は公開契約と理由を記録して `wontfix` とする。
- 修正 PR / close 判定: 未着手。DEBT-006 / 008 と合わせ、確認済み動作不具合とは別に open で追跡する。

#### DEBT-019: Stop hook 内の child task 登録が owner task を置き換える

- 起点・種類・優先度・状態: `PORT / bug, correctness`、優先度高（独立 review の major finding）、`fixed`（8250c9e で再現、113d95f で修正、4e28edf への format-only correction 後も final review で承認）。upstream の不備ではない。
- upstream baseline / path: N/A。native scheduler と Stop integration の移植固有経路。
- port baseline / path: [`8250c9e` の NativeJobControl](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/scheduler.mbt#L13-L19)、[begin](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/scheduler.mbt#L54-L103)、[await_idle](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/scheduler.mbt#L122-L163)、[attach_task と cancel_through](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/scheduler.mbt#L167-L208)、[outer effects task registration](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/runtime.mbt#L2608-L2649)、[Stop child registration](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/runtime.mbt#L2747-L2763)。同じ `control` に対する UserPromptSubmit child 登録も [`runtime/runtime.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/runtime.mbt#L563-L585) にある。
- 静的経路: outer effects job が `control.task` に登録された後、Stop child が同じ slot を置き換える。cancel は `control.task` の child を cancel し、`await_idle` / `begin` はその登録済み task の終了だけを待つ。この経路では outer owner / 後続 effect の lifetime が child task より長い場合の待ち合わせが不足する。
- 再現 / 影響: `8250c9e` の独立 scheduler probe は outer task → 完了済み child attach → cancel → new control の順で、old owner が未 cancel / 未終了のまま再 admission することを再現した。この時点では provider I/O を含む full-runtime reproduction は未実施だった。修正後は final source の actual local HTTP runtime fixture が second provider response を保留し、Stop と nested UserPromptSubmit を実行してから cancel、新しい scheduler control の要求、owner drain、再利用を検証する。外部 provider 実サービスは使わず、full-runtime regression と initial isolated scheduler probe は区別する。
- 完了条件: owner job を hook child の終了前後も保持し、cancel 後に second provider request を含む全 child を drain してから同じ session の job を再利用する。final full-runtime fixture はこの drain / reuse 境界を確認する。
- 修正 / 検証: [`113d95f`](https://github.com/f4ah6o/dsh.mbt/commit/113d95f28651d63806f5c750122bd3c969c3fe54) は [Stop child](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/runtime.mbt#L2767) と [nested continuation UserPromptSubmit](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/runtime.mbt#L2941) が scheduler owner task を置き換えないよう修正し、[`4943dec`](https://github.com/f4ah6o/dsh.mbt/commit/4943decb5d0ab0ce21eecdb28a9bc038c114324a) は nested no-op UserPromptSubmit fixture を追加。[final source runtime cancellation / reuse regression](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/hooks_wbtest.mbt#L3284) は実 worker 注入下で通過し、pre-formatter final candidate `5a92c61` の independent review runtime suite 161 / 161 は PASS。format-only correction `4e28edf` 後の hosted CI run 38118293974 も全 job PASS。

#### DEBT-020: Stop continuation 拒否の prefix が上限検証を超える

- 起点・種類・優先度・状態: `PORT / bug, correctness`、優先度高（独立 review の major finding）、`fixed`（8250c9e で再現、113d95f で修正、4e28edf への format-only correction 後も final review で承認）。upstream の不備ではない。
- upstream baseline / path: N/A。既存の reason cap helper が新しい Stop continuation close 経路で表面化した移植固有の不整合。
- port baseline / path: [`native_hook_limit_reason`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_codec.mbt#L74-L85)、[`UserPromptSubmit` exit-2 reason decode](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_codec.mbt#L321-L339)、[Stop continuation denial settlement](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/runtime.mbt#L2947-L2969)、[`block_stop_continuation`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/engine/stop_hooks.mbt#L257-L291)。
- 再現 / 影響: native helper は理由を最大 4096 code points に切り詰める。16 KiB stream 上限内の exit-2 stderr に `😀` を 4096 個含めると、Stop hook の追加 prefix を含む denial error は engine の 8192 上限を超える。独立レビューの isolated engine probe で `block_stop_continuation` が `Err` を返し、状態が `Running` のまま `pending_stop_hook` が `Some`、effect なしとなることを再現した。full runtime command / receipt の uncertain 状態や scheduler slot の影響は実行再現しておらず、source 経路からの推論と区別する。
- 完了条件: prefix を含む denial error を 8,192 UTF-16 units 内に保ち、Unicode scalar を分割せずに切り詰め、pending boundary を terminal に settle する。4,096 emoji と実 native hook の regressions が blocked turn、保存済み回答、no effect、fresh turn を確認する。
- 修正 / 検証: [`113d95f`](https://github.com/f4ah6o/dsh.mbt/commit/113d95f28651d63806f5c750122bd3c969c3fe54) は [prefix-inclusive UTF-16 budget](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/engine/stop_hooks.mbt#L288) で denial reason を Unicode scalar 境界に切り詰め、pending boundary を Failed / blocked として terminal に settle する。[engine regression](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/engine/stop_hooks_wbtest.mbt#L136) は 4096 emoji、<=8192 UTF-16 units、turn/end、no effects、restore equality を検証。[native runtime regression](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/hooks_wbtest.mbt#L3462) は実 hook 経路で blocked terminal state と fresh turn を検証し、pre-formatter final candidate `5a92c61` の independent review engine 86 / 86、runtime 161 / 161 は PASS。format-only correction `4e28edf` 後の hosted CI run 38118293974 も全 job PASS。別の oversized-context atomicity probe の snapshot unchanged 成功とは混同しない。

#### DEBT-021: truncated capture が既知の Stop exit-2 veto を中立化する

- 起点・種類・優先度・状態: `PORT / bug, correctness, compatibility`、優先度高（独立 review の major finding）、`fixed`（8250c9e で再現、113d95f で修正、4e28edf への format-only correction 後も final review で承認）。upstream の不備ではない。
- upstream baseline / path: [`5badb150` の hook-protocol codec](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts#L65-L69) は exit code 2 を常に `block` とし、stderr は任意の reason として扱う。共通 merge は block を rank 3 / `deny` にする（[`merge.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts#L34-L50)）。Claude Code の Stop listener は deny を steering にして次の model step を促す（[`index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L273-L282)）。
- port baseline / path: [`8250c9e` の Stop decoder](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_codec.mbt#L266-L280) は `capture.truncated` を先に判定して rank 0 を返し、その後に exit code 2 の rank 3 判定を置く。child output decode は invalid UTF-8 時も process exit code を保持して `truncated: true` を返す（[`hooks_process.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/8250c9edd512009805f317b2943bea891083deeb/runtime/hooks_process.mbt#L126-L149)）。
- 再現 / 影響: 独立 reviewer の native isolated capture probe で `exit_code=2`, `truncated=true`, `stderr="keep working"` を与えると decoder が rank 0 を返すことを再現した。この probe は isolated decoder の再現で、full runtime / agent turn の完了までは実行していない。upstream 固定 source の keyless codec / merge probe は通常 reason、16,385 ASCII 文字、空 stderr の 3 assertion すべてで deny となった。固定 source の経路から、大きすぎる出力または invalid UTF-8 の truncation が既知の exit-2 veto を中立化し、この hook が continuation を強制しなくなる影響を推論する。reviewer isolated copy の engine/api `--target all` 各 backend 96 / 96 には reviewer probe を含み、PR production test count ではない。
- 不明点・仮説: exit-0 の truncated structured output は従来どおり中立に扱う。これはこの reproduction の対象外で、修正後も維持すべき境界。
- 完了条件: exit-2 blocking decision を truncation 判定より優先し、reason のみを bounded / optional にする。subprocess regressions は stderr overflow と invalid UTF-8 で exit-2 を blocking に保ち、codec regression は空 stderr と truncated exit-0 の境界を確認する。
- 修正 / 検証: [`113d95f`](https://github.com/f4ah6o/dsh.mbt/commit/113d95f28651d63806f5c750122bd3c969c3fe54) は [exit code 2](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/hooks_codec.mbt#L269) を `capture.truncated` より先に判定し、読めない stderr でも veto を維持する。[subprocess regression](https://github.com/f4ah6o/dsh.mbt/blob/5a92c61e37cefd954bd736c86b85e2e9ad195e7e/runtime/hooks_wbtest.mbt#L340) は stderr 16,385 bytes の overflow と invalid UTF-8 の両方で exit 2 / rank 3 を確認し、後者は reason を持たない。truncated exit-0 output は neutral のまま。[final review](https://github.com/f4ah6o/dsh.mbt/pull/47) は修正を unresolved findings なしで承認。hosted CI run 38118293974 は全 job PASS。

### Stop command hooks increment の最終レビューと検証状況

- 最終機能 head: [`4e28edf`](https://github.com/f4ah6o/dsh.mbt/tree/4e28edf434f554521361da897f103fe7451aa201)、version 0.1.14、[feature PR #47](https://github.com/f4ah6o/dsh.mbt/pull/47)。3 件の major finding は [`113d95f`](https://github.com/f4ah6o/dsh.mbt/commit/113d95f28651d63806f5c750122bd3c969c3fe54) で修正し、nested continuation owner regression を [`4943dec`](https://github.com/f4ah6o/dsh.mbt/commit/4943decb5d0ab0ce21eecdb28a9bc038c114324a) で強化。`5a92c61` の後続 production behavior 変更はなく、`4e28edf` は `engine/persistence.mbt`、`engine/stop_hooks.mbt`、`engine/stop_hooks_wbtest.mbt` の formatter correction のみ。
- 独立 final review は `APPROVE`、3 pass / 7 categories、unresolved findings 0。reviewer の engine 86 / 86、native runtime 161 / 161、release worker build PASS は pre-formatter final candidate [`5a92c61`](https://github.com/f4ah6o/dsh.mbt/tree/5a92c61e37cefd954bd736c86b85e2e9ad195e7e) での実測で、runtime は `DSH_NATIVE_WORKER_BIN` に independently built 0.1.14 worker を指定した。`4e28edf` はその後の formatter-only 差分であり、reviewer は 3 files の変更を read-only で確認、exact full formatter check `moon fmt --check engine provider auth protocol client plugins api ui native runtime cmd/dsh browser browser/sw desktop verification/retry_math` の 173 tasks PASS と `git diff --check` PASS を確認して `APPROVE` を維持した。86 / 86 と 161 / 161 を `4e28edf` で再実行したとは記録しない。
- fixed core `113d95f` の実装担当実測: native engine / api / runtime check は error 0、hotpath warning 3 件。engine `*astral*` 1 / 1、runtime `*Stop*` 5 / 5、runtime `*astral UserPromptSubmit*` 1 / 1 PASS（worker env 注入済み）。portable Wasm / Wasm GC / JS / native 各 169 / 169 は root が同 head で独立実測した結果であり、実装担当の実測とは分ける。これらの core-head counts と final review の production suite counts を別々に保持する。
- 最初の GitHub [CI run 38118048484](https://github.com/f4ah6o/dsh.mbt/actions/runs/38118048484) は `engine/persistence.mbt`、`engine/stop_hooks.mbt`、`engine/stop_hooks_wbtest.mbt` の 3 files で両 job とも format gate に失敗し、behavior gate には到達していない。これは feature behavior finding ではなく formatter 修正履歴として扱う。修正後の GitHub [CI run 38118293974](https://github.com/f4ah6o/dsh.mbt/actions/runs/38118293974) は head `4e28edf` で全 job success。portable-and-native job は Wasm / Wasm GC / JS / native 各 169 / 169、app / browser 17 / 17、native runtime 161 / 161、web 7 / 7、own warnings 0。ACP stdio、source-install、native-host Chromium strict-CSP smoke も PASS。native-without-node job は 340 / 340、native check は own warnings 0 / pinned warnings 3、Node-absent CLI / source-install / demo / reload も PASS。[native asset matrix run 38118293935](https://github.com/f4ah6o/dsh.mbt/actions/runs/38118293935) は同 head で Linux x86_64 / aarch64 と macOS arm64 の build / smoke がすべて成功し、PR 用 run のため publish jobs は正常に skip された。旧 matrix run 38118048478 は superseded として root が cancel 済み。
- Release preview は [`d7d78a3`](https://github.com/f4ah6o/dsh.mbt/tree/d7d78a377fc819d8f857367149962cdb946e50e1) で source / extracted 0.1.14 package check PASS。dry-run endpoint は HTTP 202 と成功本文を返したが、Moon CLI は後続処理で exit 255。これは source/package failure ではなく CLI の dry-run response handling 制限として記録し、preview 全体を CLI success と表現しない。後続候補 `5a92c61` は `d7d78a3` から docs 2 files のみを変更し、最終機能 head `4e28edf` はさらに formatter correction のみ。dry-run を実行した SHA は `d7d78a3` のまま。
- [feature PR #47](https://github.com/f4ah6o/dsh.mbt/pull/47) は 2026-10-11 06:42:51 UTC に merge commit [`94e59f3`](https://github.com/f4ah6o/dsh.mbt/commit/94e59f3b8761d2d77a7d2b9ce30866f7b70a0f31) で merged。merge tree は reviewed feature head `4e28edf` と一致する。`main` の merge commit から `moon publish` を実行し、version `0.1.14` を exit 0 で publish。source の `moon check` は 78 tasks / 4 warnings / 0 errors、extracted package check は 31 tasks / 0 errors、registry server は HTTP 200 OK を返した（publish log: `/private/tmp/dsh-stop-publish-0.1.14.log`）。
- Fresh temporary module `/private/tmp/dsh-0.1.14-registry-139m6d2s` で `moon update` と `moon install` は exit 0、registry から `f4ah6o/dsh@0.1.14` を download。public `moon.mod` は version `0.1.14` を示し、`engine/stop_hooks.mbt`、`engine/persistence.mbt`、`runtime/hooks_codec.mbt`、`runtime/runtime.mbt`、`runtime/hooks_wbtest.mbt` の内容は merge commit `94e59f3` と byte-equal（registry install log: `/private/tmp/dsh-stop-registry-install-0.1.14.log`）。
- Annotated tag [`v0.1.14`](https://github.com/f4ah6o/dsh.mbt/releases/tag/v0.1.14) は merge commit `94e59f3` に push 済み。GitHub release workflow [run 38118994836](https://github.com/f4ah6o/dsh.mbt/actions/runs/38118994836) は全 4 jobs success（3 platform builds と publish）、release は 2026-10-11 06:50:10 UTC に published（draft / prerelease ではない）。4 assets (`dsh-darwin-aarch64`、`dsh-linux-aarch64`、`dsh-linux-x86_64`、`Dsh-macos-arm64.zip`) が upload 済み。
- PR #47 の対象外として、ordinary internal tool-follow-up step では native UserPromptSubmit を実行せず、foreground subagent child completion は parent Stop dispatcher を通らない。これらは既存の native integration / parity gap であり upstream defect や DEBT-018 の原典制約ではない。feature guide / port status / umbrella [issue 0001](0001-upstream-parity.md) に分けて記録し、別 increment で扱う。reviewer は live provider account / desktop GUI smoke を行っていない。

#### 固定 upstream source による ordinary tool-follow-up 評価の訂正

上の bullet は当時の port 観測として保持する。ordinary tool-result-only step を UserPromptSubmit parity gap とした評価は、固定 upstream source の再照合により訂正する。

- upstream baseline / path: [`5badb150` の `agent.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L267-L326) は turn 内の各 proposed step で `preStep` を呼び、その中で claimed inbox messages を `agent/pre-step` waterfall に渡す。[`hooks-claude-code/src/index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L240) の listener は `messages.length === 0` なら `next()` を返し、非空の場合だけ `UserPromptSubmit` を起動する。
- 評価: upstream は各 step で pre-step dispatch を行うが、UserPromptSubmit payload はその step で claim された入力に限る。従って、新しい claimed input を伴わない tool-result-only follow-up が UserPromptSubmit を起動しないことは意図された入力フィルターであり、この事実だけでは port parity gap や upstream defect の根拠にならない。以前の記述は port での非実行を観測した記録として残し、普通の tool-result-only step を gap とする結論を撤回する。入力のない step でも hook を実行するかどうかは別の拡張判断である。
- 子 agent の初回入力と子 agent 自身の Stop dispatch に関する parity の問いは、この訂正の対象外で、child lifecycle increment で評価する。upstream の同じ hooks source は `SubagentStart` が child context を注入でき、`SubagentStop` は観測のみと区別している（[該当 listener](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L285-L300)）。これらの観測イベントを child 初回 UserPromptSubmit や child Stop behavior と混同せず、今回の increment の対象に含めない。

### 0.1.15 child lifecycle hooks increment

実装 commit は [`0ecba7e`](https://github.com/f4ah6o/dsh.mbt/commit/0ecba7e092be53fd4a2fa922fbfe240e78ee1125)、version / package metadata commit 後の固定 behavior candidate は [`28f896e`](https://github.com/f4ah6o/dsh.mbt/tree/28f896eddeb7b8c60a0ab11048647c19e2f82a40)、version は `0.1.15`。draft [PR #48](https://github.com/f4ah6o/dsh.mbt/pull/48) の最新 head は docs-only [`be0f251`](https://github.com/f4ah6o/dsh.mbt/commit/be0f251238893137ab99bb2fe42868585dcb0b08)。reviewer の用語指摘に従い `docs/native-runtime.md` で永続的な checkpoint と読める表現を、child 自身の Stop checkpoint を示す表現に改め、child state が永続化されるとの含意を除いた。28f896e と be0f251 の差はこの 1 行だけで、production / test source は同一。behavior test と package source の測定値は引き続き 28f896e に帰属させ、be0f251 の更新後結果は別に追記する。継続更新のためこの debt register を記録する [PR #44](https://github.com/f4ah6o/dsh.mbt/pull/44) は open のままとする。以下は uncommitted worktree ではなく固定 commit のソースを根拠にし、測定結果は実施主体・対象 tree・タイミングを区別して記録する。independent final review は be0f251 に対する最終承認まで完了した。最新 head の asset matrix は成功し、hosted CI は実行中。merge と publication は pending として残し、確定時に追記する。

- **子自身の初回 UserPromptSubmit と Stop continuation**: [`runtime/subagents.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L444-L460) は child `UserPromptSubmit` を親 turn の `NativeJobControl` 内で起動し、`attach_task=false` で子 hook を親 scheduler owner の代替登録にしない。[child start path](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L576-L617) は初回 prompt と受理した `additional_contexts` を child `session_send` に渡す。[provider completion path](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L463-L573) は child engine の Stop checkpoint を処理し、Stop allow では checkpoint を終え、Stop deny では continuation を準備して child `UserPromptSubmit` を実行する。後者が allow なら context とともに続行し、deny / hook failure なら continuation を blocked に settle する。child initial prompt と子自身の Stop の実際の port gap を埋める candidate implementation として記録する。前節の ordinary tool-result-only 評価訂正とは別の境界である。
- **子の上限・状態・結果**: child は別の ephemeral `Engine` として作り、`max_steps=3`、1 run あたり最大 8 tool calls、read / glob / grep の catalog、1 permit の semaphore、最大 90,000 ms の total deadline を使う（[limits](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L2-L20)、[catalog / child creation / deadline](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L793-L835)、[single permit](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/runtime.mbt#L381-L382)）。初回 prompt hook も deadline の内側にある。child transcript / failure reason は bounded な内部 JSON result に写し、settle 済みの parent tool result を durable history として保持する。restore 後に child effect を replay しない回帰条件は [`subagents_wbtest.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents_wbtest.mbt#L147-L378) にある。
- **既存の非不具合負債を維持**: **DEBT-001** — child result / transcript は candidate の [`native_subagent_transcript_result`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L239-L292) を含め引き続き汎用 Json。typed event payload への横断改修はない。**DEBT-003** — child driver と hook/provider 境界は [`Result[..., String]`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L444-L460) を維持し、新しい error taxonomy へ変更していない。**DEBT-004** — [`child effect-drain loop`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L693-L741) は child effects を手動で取得・完了し、[`child Engine::new と bounded run setup`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L812-L835) は既存の Engine / session 表現を使う。session state copy や owner state の横断整理を行わない。これらは実害を示す findings ではない。公開 API / 外部 API schema / generated interface の変更もない。
- **既存 hook payload / controls の制約**: candidate の child payload regression は Stop stdin の fields を 5 件、`transcript_path` を空文字、`stop_hook_active` を `false` と確認する（[test](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents_wbtest.mbt#L1748-L1768)）。Stop の ignored output controls と Stop 専用 loop cap 不在は既存の DEBT-018、空の transcript path は DEBT-006 に引き続き分類し、この increment で新しい不具合とはしない。3 step の child limit は既存総 step bound であり、専用 Stop cap の追加ではない（[bound](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L818-L835)）。`SubagentStart` は upstream で child context 注入を行い得て、`SubagentStop` は観測用である。別 hook event としての両 event はこの increment では実装しない（[upstream listener](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L285-L300)）。
- **adapter の拒否結果**: 初回 child `UserPromptSubmit` の deny は port では provider admission 前に止まり、既存 result envelope を `status=failed`、`steps=0`、bounded `failure_reason`、外側 tool result `ok=false` として返す（[implementation](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents.mbt#L587-L617) / [native regression](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents_wbtest.mbt#L1787-L1854)）。固定 upstream の in-process driver は pre-step blocked を terminal `refusal` に写す（[`toStopReason`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/subagent/subagent-in-process-driver/src/index.ts#L49-L67)）。これは native parent tool adapter の result vocabulary 差として明示して保持し、upstream の production bug とは扱わない。今回新たに確認した upstream production bug はない。

#### 28f896e candidate の検証と帰属

- 実装担当の candidate-preparation native behavior checks（production / test source contents は最終的に `28f896e` と同一）: [`runtime/subagents_wbtest.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/28f896eddeb7b8c60a0ab11048647c19e2f82a40/runtime/subagents_wbtest.mbt) は 18 / 18 PASS、通常 hook regression は 1 / 1 PASS。どちらも current release worker を `DSH_NATIVE_WORKER_BIN` で注入した。別途、commit 後に source change がない `28f896e` で native `runtime/hooks_wbtest.mbt` 全体が 28 / 28 PASS（同じ worker injection）。これらは実装担当の local suite 結果であり hosted CI や独立 review の count ではない。
- static path review、単独 shell command probe、runtime regression は別々の証拠として扱う。reviewer が修正済みの Stop fixture command を直接実行した結果は、初回が意図した block、次回が `{}`、exit 0。これは command fixture の確認で、単独では native runtime behavior の再現や production defect の証拠ではない。child lifecycle runtime 結果は上記の fixed-candidate suite に帰属する。
- 実装担当の candidate-preparation checks（production / test source contents は最終的に `28f896e` と同一）: configured targets 全体の formatter と `npm check` は PASS、project-owned warnings 0。残る hotpath warnings は pinned upstream warnings として区別。`changelog_guard` の structure / duplicates / dates validation と dry-run inspect / apply は PASS。root が `local_issues.py` を `--issue-root issues` で明示して検証した `0001-upstream-parity.md` も PASS。initial auto-discovery は initialized vendor/tools roots により複数 issue root として ambiguous だったが、明示 selector 後に問題なく通り、content defect ではない。
- root の package 検証: `moon package --frozen` は exit 0、28f896e snapshot からの extracted archive check は 78 tasks / 4 pinned hotpath warnings / 0 errors。archive は 907 entries、3,042,185 bytes。inspection では `.git`、`.mooncakes`、`node_modules`、`_build`、`target`、`.dsh.mbt`、`.env` paths を除外し、変更された 3 runtime files、manifest、embedded bundle を含むことを確認した。これは package 検証であり publish の成功を示さない。
- root の最新 head package 検証: docs-only head `be0f251` から archive を再生成し、907 entries / 3,042,183 bytes、予期しない path なし。extracted archive check は 78 tasks / 4 pinned hotpath warnings / 0 errors PASS（`/tmp/dsh-child-hook-final-package-check-0.1.15.log`）。これは 28f896e の測定値とは別の package snapshot であり、いずれも publish の成功を示さない。
- 実装反復中の失敗は fixture / runner / compile の修正履歴として分ける: shell fixture の二重 quoting、single-use `Iter` の再利用、`/tmp` と canonical workspace path の期待差、test executable への `DSH_NATIVE_WORKER_BIN` 未注入による hook dispatch 差、および commit 前に解消した初期 signature / compile error。これらは最終 candidate の PASS 結果と混ぜず、production behavior bug の再現として DEBT 登録しない。
- reviewer の独立実測は behavior source `28f896e` に帰属する: engine suite 95 / 95、runtime suite 168 / 168、いずれも exit 0。child `runtime/subagents_wbtest.mbt` 18 / 18 は runtime suite の内数なので、総数に加算しない。さらに reviewer-only の focused probe 2 件を、production source を変更せず test additions のある isolated `28f896e` tree で実行し、各 session が exit 0。対象は parent cancellation による child Stop の中断と、continuation UserPromptSubmit の process drain、parent reuse、semaphore、replay / reopen。これらは full-suite の再実行ではない。
- independent final review は PR #48 head `be0f251`（base `94e59f3`）に対して `APPROVE`: 3 passes / 7 categories、未解決の actionable finding 0。reviewer は documentation-only change も確認した。PR #48 の旧 [CI run 38121453064](https://github.com/f4ah6o/dsh.mbt/actions/runs/38121453064) は新 head update 後に自動 cancel、旧 [asset matrix run 38121453042](https://github.com/f4ah6o/dsh.mbt/actions/runs/38121453042) は superseded。最新 head の [CI run 38121536294](https://github.com/f4ah6o/dsh.mbt/actions/runs/38121536294) は両 job が実行中。[asset matrix run 38121536285](https://github.com/f4ah6o/dsh.mbt/actions/runs/38121536285) は Linux x86_64 / Linux ARM64 / macOS arm64 の build、package、smoke がすべて PASS し、PR に伴う publish jobs は期待どおり skip。CI、merge、publication は未確定。

### UserPromptSubmit increment の最終確認

- 修正先: [PR #46](https://github.com/f4ah6o/dsh.mbt/pull/46)、version 0.1.13、固定 source head [`982f2b6`](https://github.com/f4ah6o/dsh.mbt/tree/982f2b6f4b5fd364ebf0500a032bb210b753db9a)。実装は `gpt-6-luna / max`、独立レビューは `gpt-6.1-sol / xhigh`。
- [CI run 38043639573](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573): native-without-node 329 / 329、portable Wasm / Wasm GC / JS / native 各 163 / 163、browser/app 17 / 17、native runtime 156 / 156、web 7 / 7 PASS。ACP stdio、checkout 外の CLI source install / embedded assets、strict-CSP real Chromium smoke、checkpoint / approval / tool / context / durable reload demo も PASS。
- [配布物検証 run 38043639550](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639550): macOS arm64 / Linux x86_64 / Linux arm64 の build / package smoke と macOS app extraction validation が PASS。PR 上の publish job は skipped。
- Local format / native typecheck / diff check / browser asset generation は PASS、project-owned warnings 0。local behavioral test は ENOSPC で完走できず、hosted results と区別する。
- DEBT-007 と今回の DEBT-009–017 は修正済み。非不具合の DEBT-001–006 / 008 は維持する改善候補として残す。この docs-only PR と full upstream parity issue は open を維持し、後続 increment の記録を積む。

### 後続追記テンプレート

#### DEBT-NNN: 短い見出し
- 起点・種類・優先度・状態:
- upstream baseline / path（該当しなければ N/A）:
- port baseline / path（該当しなければ N/A）:
- 観測事実 / reproducer / 確認したコマンドと結果:
- 不明点・仮説（あれば）:
- 影響・発生条件 / 緊急度:
- 互換性に関する判断（未決なら未決）:
- 後続改修方針 / 対象をまとめる単位:
- 完了条件と追加するテスト:
- 修正 PR / 再検証 / close 判定:

## 受け入れ条件

- 登録した項目すべてを専用の修正 PR・別トラッカーへの移管・理由付き `wontfix` のいずれかに結び、未分類の記録を残さない。
- 同一種別の横断的な改善は、移植スライスとは独立に改修・回帰テスト・永続データ互換性の検証を行う。
- `0001` の upstream parity が完了しただけでは本 issue は閉じない。逆に本台帳の整理が終わっても parity 完了とは見なさない。

## テスト計画

- ソースと既存 docs を GitHub 上で閲覧し、上記の箇所を確認。
- 実装コード、生成物、fixture、テストコードは変更しない。
- `moon test` / `moon check` / E2E は**未実行**（docs-only PR）。初期候補の動作・性能に関する仮説は PASS と記載しない。

## リスク

構造上の改善候補を未確認の動作不具合と混同すること、後続の整理で wire / replay 互換性を変えること。観測事実と仮説を分け、実装側の検証結果を固定参照する。

## 変更履歴

- 2026-10-10: 非不具合の不備・非慣用的構造を維持して移植し、確認できた動作不具合は修正する方針を明記。既存の台帳項目を保持し、必須 issue フィールドとセクションを補完。
- 2026-10-10: command hooks の追加移植に合わせ、原典と移植先が維持する空の `transcript_path` を DEBT-006 に登録。
- 2026-10-10: PostToolUse `additionalContext` の移植で維持した Json payload、文字列エラー、個別 state copy を、DEBT-001 / 003 / 004 の固定 source 根拠として追記。
- 2026-10-10: 独立レビューで再現した移植固有の終了時 context 保存漏れを DEBT-007 に登録。公開前の是正対象として追跡。
- 2026-10-10: `2c792853` の修正と独立 probe の成功を記録し、DEBT-007 を `fixed` に更新。

- 2026-10-10: UserPromptSubmit 移植で維持した Json event、文字列エラー、境界ごとの手書き validation、空の transcript_path を固定 source で追記。原典の未反映 hook control を DEBT-008 に登録。

- 2026-10-10: UserPromptSubmit 独立レビューの動作不具合を DEBT-009–013 に登録。当初の復元再現という評価は後続の証拠訂正を参照。静的経路照合と実行結果を区別し、公開前の是正対象として追跡する。

- 2026-10-10: 3 パス source review の再確認と DEBT-009–013 の修正 snapshot を追記。追加の理由優先順位差分を DEBT-014 として公開前の修正対象に登録。

- 2026-10-10: 初回 CI の fixture shape mismatch を DEBT-015 に登録し、DEBT-009 の 0 / 1 run が decoder 単独の再現ではないことを訂正。両 fixture の修正と fixed-head source review を固定参照。

- 2026-10-10: 二回目の CI で判明した fixture の prompt 判定誤りを DEBT-016、explicit cancellation の理由分類を DEBT-017 として登録。実装とテストの不具合を区別し、公開前に修正する。

- 2026-10-10: 最終 source head `982f2b6` の 3 パス独立レビューと全 hosted gates の成功を記録。DEBT-009–017 を fixed に更新し、初回の再現・静的観測・証拠訂正の履歴は保持。
- 2026-10-11: Stop command hooks の固定 snapshot `8250c9e` に対し、Json event / String error / state copy の既存根拠を追記。原典制約と native adapter scope を DEBT-018 に分け、scheduler の isolated reproduction を DEBT-019、engine isolated reproduction を DEBT-020 に登録。最終 CI と full-runtime probes は未完了として明記。

- 2026-10-11: `8250c9e` の Stop truncated-capture / exit-2 経路と upstream codec 契約を照合し、native isolated decoder probe で rank 0 を再現した DEBT-021 を登録。review-only test counts と production suite を区別。UserPromptSubmit の最終確認欄を `982f2b6` 時点の記録に戻し、Stop 現況を Stop increment 内に保持。

- 2026-10-11: DEBT-019–021 の修正 commit と fixed-head runtime / engine regressions を追記し、機能 head `4e28edf` の独立レビュー `APPROVE` を記録。PR #47 を相互参照。最初の CI run は engine 3 files の format gate failure で両 job とも behavior gate 未到達。root 実測の portable matrix 帰属を明確化し、format-only correction 後の独立再レビュー、native asset matrix success、CI 全 job success を追記。PR #47 merge、0.1.14 publication と fresh registry install / source equality、tag release workflow 全 job success と release assets upload まで追記し、公開作業の証拠を確定。child-engine Stop dispatch と per-step UserPromptSubmit の既存 native parity gaps は原典制約と区別して別 scope に記録。
- 2026-10-11: 固定 upstream `agent.ts` と Claude Code hook listener を照合し、tool-result-only step の UserPromptSubmit 非実行を parity gap とした評価を訂正。child initial prompt / child Stop の問いは別 increment に保ち、観測用 SubagentStart / SubagentStop hooks と区別。
- 2026-10-11: `0ecba7e` implementation / `28f896e` fixed version candidate の child initial UserPromptSubmit と子自身の Stop continuation hook flow を記録。Json event, String error, manual lifecycle/state, bounded ephemeral child and parent no-replay remain related debt boundaries; five-field hook payload and ignored Stop controls remain in DEBT-006 / 018. Implementer suites, root's package checks, PR #48 draft and running hosted gates are attributed separately; review, CI completion and publication remain pending.
- 2026-10-11: reviewer の documentation finding を source commit `be0f251` で修正し、`28f896e` との差が `docs/native-runtime.md` 1 行のみで production/test source に変更がないことを確認。`28f896e` の behavior/package evidence と最新 head の review / hosted-gate evidence を分け、PR #48 は未完了のまま追跡する。

- 2026-10-11: PR #48 の final review は head `be0f251` / base `94e59f3` に対し `APPROVE`（3 passes / 7 categories、未解決 actionable finding 0）。reviewer suite / focused probe の count は behavior source `28f896e` に帰属させ、最新 head の asset matrix success と hosted CI 実行中を追記。merge / publication は pending。
## 注記

- 2026-10-10: 以前の文書編集では正確な実行モデル識別子を確認できず `Model: unknown` と記録した。2026-10-11 の編集では指定された `gpt-6-luna` を記録する。
