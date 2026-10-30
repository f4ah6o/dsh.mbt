# Session 復元の event 検証を連続 batch に分離する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: refactor/20261030-incremental-session-replay

## 概要

既存 v1 session 復元の event replay を、状態を維持した連続 batch として検証できる内部構造へ分離する。

## 背景

[0001](0001-upstream-parity.md) と [PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) の長期保存調査。現行 restore は全 event を再生して tool 相関、approval、effect ID、hook、lineage を検証し、fork は全 prefix を複製・照合する。

## 問題

将来の archive に対して chunk ごとに検証状態を初期化したり、checkpoint を無検証で信頼すると、相関・承認・重複検出を失う。

## 目標

同一の event 列を一括または連続 batch で再生したとき、同じ復元結果と受理・拒否を得る。

## 対象外

新たな保存形式、上限緩和、summary、spill、履歴削除、実行再開、constant-memory の保証。

## 提案する方針

既存 v1 の入力・出力・上限を変えず、検証の初期化、event の適用、終端照合を分離する。全体の sequence、使用済み call/effect ID、pending hook、approval と tool correlation を batch 間で保持する。後続の保存形式で checkpoint を信頼する根拠とはしない。

## 受け入れ条件

- [ ] 一括と複数 batch は同じ入力に対して同じ結果または拒否を返す。
- [ ] tool call/result、approval、hook と不正な重複・欠損が batch 境界を跨いでも検証される。
- [ ] 既存 v1 format、容量制限、restore の no-replay、公開 API は変わらない。

## テスト計画

- 既存 restore fixture と境界を変えた valid / invalid fixture を portable matrix で実行する。
- 独立レビューと Issue validator、変更範囲の native check を実施する。

## リスク

状態を誤って batch 毎にリセットすると承認や重複検証が壊れる。使用済み ID は履歴に比例するためメモリ一定を保証しない。fork、ACP の event seq、PWA cursor の移行は後続設計が必要。

## 変更履歴

`CHANGES.md` impact: no

## 注記

この refactor 自体は長期会話の保存容量を増やさない。後続の immutable archive、manifest と receipt の原子的確定、v2 checkpoint/suffix、欠損・破損・結果不明時の回復、履歴 API と quota は別途必要。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。batch の prefix skip / repeat を処理前に拒否し、validation error 後の状態破棄を明示。portable package matrix は各 backend 218/218 PASS、独立 JS engine テスト 133/133 PASS。root 全 native テストは GPUI dependency の不足ファイルにより開始前に停止。形式や容量は変えていない。CI と commit の最終結果は PR を参照する。
