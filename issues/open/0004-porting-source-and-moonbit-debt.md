# 0004: 移植元の不備と MoonBit 移植負債を記録し、後続の独立した改修でまとめて整理する

Status: open
Created: 2026-10-10
Updated: 2026-10-10
Branch: docs/20261010-porting-debt-register
Upstream baseline: [DeepSeek Harness 5badb15009ae1756c3afe0ae0cef1faafc290ccc](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc)
Port snapshot: [dsh.mbt 82b8a985341105bb0197e3dc8c6b4f9f34b53500](https://github.com/f4ah6o/dsh.mbt/tree/82b8a985341105bb0197e3dc8c6b4f9f34b53500)
Related: [0001 upstream parity](0001-upstream-parity.md) / [0003 native・MoonBit 設計](0003-moonbit-native-ios-tailnet-roadmap.md) / [移植状況](../../docs/port-status.md)

## 目的

DeepSeek Harness → dsh.mbt の移植時に見つけた不備を、移植と同時に修正して作業範囲を広げないための**保留台帳**とする。機能不具合だけでなく、MoonBit の型・エラー・所有権・非同期・モジュール設計・テストのプラクティスから外れた実装も対象にする。

- **0001** は「何を移植するか／どこまで互換か」の追跡。**本台帳**は「移植で持ち込まない、あるいは移植後に改善するべき品質上の課題」の追跡。
- **0003** は MoonBit 化の設計原則。本台帳は実際の箇所、根拠、改修条件を紐付ける。
- 移植元の実装上の欠陥と、移植により生じた MoonBit 固有の負債を混同しない。upstream 固有の不備を確証なしに「バグ」と呼ばない。
- 同じ機能差分でも、未移植なら 0001、実装済みコードの修正課題なら本台帳へ記録する。必要なら相互参照する。

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

## 運用ルール

1. 移植作業では発見をこの台帳へ**最小限追記するだけ**にし、ついでの大規模リファクタリング、API 改変、スタイル一括修正は行わない。確認に時間を要するものは `hypothesis` として残す。
2. 移植作業の変更と後続の品質改善は別 PR とする。移植の受入では parity の評価と負債の記録を分ける。小さな移植スライスが完了した区切りで、同じ原因の負債を束ねて専用 PR で修正する。
3. **安全・秘密情報漏えい・データ損失・外部作用の無断実行・復旧不能**など放置が危険なものは例外。起票と同時に、移植作業内での是正／機能停止／緊急修正 PR を判断する。記録を理由に必要な修正を延期しない。
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

## 本 issue を閉じる条件

- 登録した項目すべてを専用の修正 PR・別トラッカーへの移管・理由付き `wontfix` のいずれかに結び、未分類の記録を残さない。
- 同一種別の横断的な改善は、移植スライスとは独立に改修・回帰テスト・永続データ互換性の検証を行う。
- `0001` の upstream parity が完了しただけでは本 issue は閉じない。逆に本台帳の整理が終わっても parity 完了とは見なさない。

## この PR の検証

- ソースと既存 docs を GitHub 上で閲覧し、上記の箇所を確認。
- 実装コード、生成物、fixture、テストコードは変更しない。
- `moon test` / `moon check` / E2E は**未実行**（docs-only PR）。初期候補の動作・性能に関する仮説は PASS と記載しない。
