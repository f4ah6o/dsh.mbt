# 完了済み foreground child の監査 snapshot を保存する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-child-audit-snapshot

## 概要

明示的に有効化した場合に限り、settled foreground child の完全な監査 snapshot を独立して耐久保存する。

## 背景

[PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) の子再開契約調査と [0001](0001-upstream-parity.md) の継続。現行 child はメモリ内で実行され、親へ渡す bounded result は transcript を省略し得る。

## 問題

親 result は child 原本保存ではなく、子の終了と親の結果確定の間の中断を監査できない。v1 envelope に未知フィールドを追加すると旧 writer が捨てる危険がある。

## 目標

子の完全な settled 記録を、実行や採用を許さない監査記録として保持する。既存 default の foreground 挙動は維持する。

## 対象外

background、親による結果採用の新契約、子の再開、provider/tool/hook の自動再実行、汎用 scheduler、無制限の retention。

## 提案する方針

opt-in 時は子の終端後、親 session/turn/effect/call、child ID、workspace と形式を束ね、owner-only の immutable file として耐久化する。記録は常に unadopted であり、その存在だけで親結果確定や再実行を行わない。保存失敗は明示的に失敗として扱い、結果不明の外部作用を暗黙 retry しない。中断で生じた orphan は自動採用・削除しない。サイズ、件数、権限、検証可能性と機密性を定義する。

## 受け入れ条件

- [ ] opt-in で完全な settled child snapshot と識別情報を保存し、default の動作を維持する。
- [ ] 保存失敗、親取消、child 完了競合、checkpoint 前後の中断で親採用と外部作用の重複がない。
- [ ] 復元や検査で provider/tool/hook が再実行されず、orphan は自動採用されない。
- [ ] サイズ・件数上限、所有者権限、機密性、既存 reader との互換境界を明記する。

## テスト計画

- child snapshot の原本・相関、effect と hook の呼出回数、破損と保存失敗を keyless native fixture で確認する。
- 対象 engine/runtime 検証、独立レビューと local issue validator を実施する。

## リスク

子の原文には機密情報が含まれ得る。child snapshot と親 checkpoint は別の atomic transaction であり、未採用ファイルを親の committed result と扱えない。SubagentStop hook は child Engine の完全履歴に含まれる保証がない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- 任意設定で完了済み foreground child の監査 snapshot を保存する。

## 注記

本作業の実行可能性は ownership、quota と失敗時の状態を既存実装で検証した後に確定する。未決事項が安全に解消できなければ実装を強行しない。
