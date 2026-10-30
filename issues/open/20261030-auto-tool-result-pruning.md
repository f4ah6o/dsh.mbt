# 送信前に tool result の投影を任意で縮約する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-auto-tool-result-pruning

## 概要

新しい turn の送信前に、明示的に有効化された場合だけ既存の tool-result pruning を適用する。

## 背景

[長期会話の契約調査](https://github.com/f4ah6o/dsh.mbt/pull/76) と [0001 upstream parity](0001-upstream-parity.md) の最初の増分。main 8e7ec94 では手動 pruning が原本を保持し、provider 用投影のみを変更する。

## 問題

長い tool result は後続の provider context を圧迫する。手動 pruning は自動では実行されず、保存容量を減らさない。

## 目標

既存の相関・原本・復元検証を維持し、利用者が選択した場合に送信前の投影を縮約する。

## 対象外

正確な token 計測、model window の保証、summary、spill、storage 上限の引き上げ、進行中 turn の縮約。

## 提案する方針

既存 policy の Unicode code point 単位と pruning event を再利用する。既定は無効。候補 transaction 内で送信開始前に適用し、容量拒否時は prompt、投影、effect をまとめて破棄する。復元は event の検証のみで外部作用を再実行しない。

## 受け入れ条件

- [ ] opt-in のみで適用され、既定の挙動は変わらない。
- [ ] 原本と call/result、承認・hook の根拠が保持され、再適用は冪等である。
- [ ] 容量拒否と保存失敗で未確定の provider/tool 実行を開始しない。
- [ ] Unicode、再起動、容量拒否を検証し、制限を文書化する。

## テスト計画

- engine の対象テストと portable matrix、native 境界に影響するテストを実行する。
- 変更 HEAD を独立レビューし、影響する CI を確認する。

## リスク

pruning は保存量を増やし得る。token budget、巨大 prompt、同一 turn 内の結果、保存容量不足は解決しない。保存後の検証失敗は commit 状態不明として扱う必要がある。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- opt-in の送信前 tool-result 投影縮約を追加する。

## 注記

親 map と契約調査は未マージの [PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) にある。実装の統合は同 PR に依存しない。調査の暫定判断: model token 数を code point から正確に推定しない。summary と原本の spill は別の schema / atomic commit を要し、後続調査が必要。既存 session の上限は serialized JSON 262144 UTF-16 units、32768 events、native envelope 32 MiB であり相互に独立する。

### 調査根拠と後続の境界

| 境界 | 現状 | この増分の扱い |
| --- | --- | --- |
| provider context | tool result 投影は Unicode code point で閾値を測る | opt-in で既存投影を適用。token limit は保証しない |
| canonical session | `engine/transaction.mbt`: JSON の UTF-16 262144 units と 32768 events、終了用の余地を予約 | 変更しない。pruning event は保存量を増やす |
| native envelope | `runtime/store.mbt`: 32 MiB bytes | 変更しない。保存失敗時は外部作用の開始を抑止 |

固定 upstream `5badb150` の basic compaction は model と output reservation を使う token meter と summary を用いる。文字数 policy だけでは同等の budget を表せないため、正確な token 換算や全会話の compaction として扱わない。既存 pruning の手動操作だけを採用する案は自動適用要件を満たさず、provider summary を即時採用する案は課金、unknown outcome、保存と再開の契約が未確定である。原本を別保存する spill は manifest の原子的確定、旧 reader、欠損・quota と fork の設計が必要であり別途決める。

本増分では元 event、transcript、tool call/result ID、approval と hook provenance を変えない。active / imported session の既存制約と restore の validation を維持する。cancel や interruption 後の reopen は durable checkpoint のみを表示し、provider/tool/hook を暗黙再実行しない。容量拒否は candidate を破棄する。保存が失敗した場合は外部作用を始めず、書込後の検証失敗が commit 済みの可能性を持つ場合は結果不明として扱う。summary / spill の旧 reader、fork、障害回復と自動実行の詳細は未確定であり、この Issue の完了では長期会話全体を完了としない。

### 2026-10-30 実装・検証記録

実装担当: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh、修正後の差分に指摘なし。`moon test engine api --target all` は各 backend 146/146 PASS、`moon check engine api runtime --target all` と `moon fmt --check engine api runtime` PASS。native runtime 全体は worker を指定して 207/211、外部 MCP 子プロセス cleanup 3 件と signal cleanup 1 件が FAIL（原因未確定）。auto-prune を伴う native store 保存失敗の専用試験は未実行。実アカウント、iPhone、macOS、Tailnet は未実行。最終 CI と PR は別途確認する。
