# 置換しない atomic file create を追加する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-atomic-create

## 概要

SafeRoot に、完成済みの bounded file を既存 destination を置換せず公開する primitive を追加する。

## 背景

[PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) の長期保存・child 監査調査。現行 exclusive create は最終名に部分ファイルを残し得る一方、atomic write は既存 destination を置換する。

## 問題

immutable archive / child audit に必要な完全な公開と no-replace の両方を現行 API の組合せだけで保証できない。

## 目標

同じ安全な root 内で size を制限し、完成前に最終名を見せず、既存ファイルを変更せず公開できる。

## 対象外

archive、child 保存、quota、orphan の採用・削除、結果不明操作の自動 retry、既存 API の意味変更。

## 提案する方針

同一 directory の private temporary を完全に書き同期後、no-replace で公開し directory を同期する。destination の path containment と symlink 防御を既存 SafeRoot と整合させる。公開後の同期失敗は結果不明として返し、caller は再読で解決する。platform ごとの保証と未検証事項を区別する。

## 受け入れ条件

- [ ] 最終名から完成済み内容のみ読め、既存 destination を上書きしない。
- [ ] size、permission、path 境界、重複時の元内容と失敗時の扱いを検証する。
- [ ] crash や公開後の失敗を成功と偽らず、既存の保存 API に影響しない。

## テスト計画

- native SafeRoot の focused test と Linux CI、Windows の実装・CI を確認する。
- 独立レビュー、local issue validator、関連する native verifier を実施する。

## リスク

公開後の directory fsync 失敗は commit 状態不明となる。crash 後の temporary は orphan として別途扱う。OS ごとの no-replace / durability の違いを検証しない限り同一保証を主張しない。

## 変更履歴

`CHANGES.md` impact: no

## 注記

監査 snapshot と長期保存の前提であり、容量拡張・child resume を実装するものではない。PR #80 の ownership predicate と独立する。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。レビューで temporary alias、候補枯渇、Windows retry、公開結果不明の分類を修正。Linux の focused SafeRoot test 2 件と独立 POSIX 故障注入 7 ケース、native MoonBit check、format、`node scripts/check.mjs` の FFI inventory は PASS。Windows fixture は Linux 環境では未実行で CI を待つ。power-loss 実験は未実施であり同一 UID の敵対的な競合は trust boundary 外。公開後の結果不明は再読で解決する。
