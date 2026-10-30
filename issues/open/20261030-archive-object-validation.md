# Read 原本 object の参照と内容を検証する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-archive-object-codec

## 概要

将来の v2 archive が参照する Read 原本 object の format と相関を、保存や状態変更を伴わず厳密に検証する。

## 背景

[縮約済み Read 原本を独立保存する](20261030-archive-pruned-read-result.md) の前提。原本は completed/result に重複し、復元時に内容と pruning の一致を検証する必要がある。

## 問題

参照だけを信頼すると欠損・破損・別 session や call の原文を誤って採用し得る。

## 目標

明示した上限内で object の自己整合性、参照の identity、長さ、digest と提供された pruning を検証する。engine history との相関は別途検証する。

## 対象外

保存・読み出し・manifest、quota、外部 wire API、v2 migration、容量拡張、暗号化や hash による認可。

## 提案する方針

既存の hash boundary を使い、versioned な厳格 format と閉じた入力を採用する。String を再符号化した bytes のみを対象とし、storage から読んだ元 bytes の同一性は後続の byte boundary で確認する。内容が未検証なら失敗し、承認・effect を発行しない。Unicode と byte/code-point の単位を区別し、plan の freshness を保証しないことを明記する。

## 受け入れ条件

- [ ] 提供された文字列の参照・長さ・digest・縮約を検証し、不正な形・不一致を拒否する。engine history や storage bytes との一致を保証しない。
- [ ] 検証前後の状態・effect は不変で、wire API や v1 動作は変わらない。
- [ ] 上限・秘密情報・hash の保証範囲・未実装の storage と容量を説明する。

## テスト計画

- Unicode、境界、破損、相関と pruning の改竄を portable/native tests で確認する。
- 独立レビュー、local issue validator と変更範囲の CI。

## リスク

検証した object をそのまま保存済み・承認済みとみなせない。source の型と文字 encoding、再計算する hash と実際に保存された bytes の対応が不可欠。

## 変更履歴

`CHANGES.md` impact: no

## 注記

この単位は容量を増やさない。完全な縦切りには #79/#81/#82 と v2 replay、atomic manifest・receipt、quota、history API が必要。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。fixed-order encoding、String 範囲と engine provenance の限界を明確化し、同長の内容差替え・digest を再計算した偽 projection を試験。`moon test --target native -p f4ah6o/dsh/runtime --filter 'archive*' --no-parallelize --deny-warn` は 9/9 PASS、native check と format PASS。runtime 全件は LSP fixture の環境失敗で未完了。storage bytes/BOM と履歴 provenance、実際の保存と容量改善は未実装。直接依存は未マージ #82。
