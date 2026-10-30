# 保留中 tool effect の所有者を照会する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-tool-effect-ownership

## 概要

native runtime が保留中 tool effect の session / call 所有権を型付きかつ読み取り専用で照会できるようにする。

## 背景

[PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) の subagent 再開契約調査。子の監査保存では親取消や effect 完了と競合するため、running status だけでは対象 effect の所有権を証明できない。

## 問題

現行の公開 session view だけでは、特定 effect が指定 session と call に属し現在も保留中かを安全に判定できない。

## 目標

既存の authoritative engine 状態を用い、effect ID、session ID、call ID と tool effect 種別の完全一致を確認する。

## 対象外

監査 snapshot、永続化、background、resume、親結果採用、外部 wire API、承認付与。

## 提案する方針

Engine と必要な HarnessApi に内部向けの型付き照会を加える。queue の drain 状態ではなく authoritative pending state を用い、読み取りで state や effect を変更しない。native caller は自身の gate 内で control の所有と取消も別途再確認する。

## 受け入れ条件

- [ ] 正しい pending tool effect のみ true とし、異なる ID、session、call、effect 種別、完了・取消済みは false。
- [ ] effect queue を drain しても pending ownership が変わらず、照会が state/effect を変更しない。
- [ ] 公開 wire 操作や既定の実行挙動は変わらない。

## テスト計画

- engine / API の focused tests と portable matrix、独立レビューを実施する。
- local issue validator と native check を実施する。

## リスク

この照会は瞬間の状態だけを表す。gate 外で確認してから作用すると取消や完了との競合を防げず、承認や再開の権限を与えない。

## 変更履歴

`CHANGES.md` impact: no

## 注記

child audit の候補 [完了済み foreground child の監査 snapshot を保存する](20261030-child-audit-snapshot.md) の前提。永続化には別途 no-replace atomic publish、quota、orphan と crash recovery が必要。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh、指摘なし。`moon test engine api --target all` は各 backend 143/143 PASS、`moon check engine api --target all` と format check PASS。portable package matrix は追加テスト前の実装に対して各 backend 218/218 PASS。将来の native caller は gate 内で predicate と control/cancel を再確認する。監査記録・resume は未実装。
