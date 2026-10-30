# Command receipt の置換を owner 単位にする

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: fix/20261030-receipt-owner

## 概要

command receipt の検索と更新で同じ owner と command ID の組を使用し、異なる owner の記録を保持する。

## 背景

[0003 native / iOS / Tailnet](0003-moonbit-native-ios-tailnet-roadmap.md) の durable receipt と no-replay 契約。runtime の照会は owner と command ID を使うが、置換は command ID のみを使う。

## 問題

identity の変更後に同じ command ID が使われると、旧 owner の receipt まで別の結果へ置換され、再送判定の根拠を失う可能性がある。

## 目標

owner 毎の受理・確定・復元・再送を独立させ、他 owner の receipt と外部作用を変更しない。

## 対象外

認証方式の変更、receipt の無制限保持、公開 multi-tenant 機能、一般 scheduler の再設計。

## 提案する方針

現行の identity と legacy owner 解釈を維持し、置換で検索と同じ owner と ID を照合する。全 call site と保存・reopen の一貫性を確認する。

## 受け入れ条件

- [ ] 異なる owner の同じ command ID の receipt を独立に保持する。
- [ ] reopen と identity 変更後の再送で既存 receipt が保持され、外部作用を重複しない。
- [ ] 同 owner の重複、異なる payload、cancel、legacy owner が既存契約を維持する。

## テスト計画

- keyless runtime fixture で owner/ID、状態・保存内容・effect 回数を検証する。
- 独立レビューと native tests、local issue validator、CI を実施する。

## リスク

legacy receipt に owner が無い場合の既存 fallback を変えると読取互換や再送判定を壊す。過去に失われた receipt はこの修正では復元できない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- identity 別 command receipt を他の owner の同 ID 更新から保護する。

## 注記

archive runtime 実装の独立レビュー中に発見。現行 main での再現性と reachability を確認してから実装する。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。owner 切替で旧 receipt が残ること、reopen と再送で effect を再発行しないことを確認。focused receipt 4/4、独立 runtime/hooks native 57/57 PASS（既存 worker 指定）、native check と diff check PASS。過去に消えた receipt は復元できない。
