# 縮約済み Read の参照付き engine 復元を実装する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-archive-engine-v2

## 概要

検証済み原文 object を使い、縮約済み Read 原本の参照付き engine 候補と復元を実装する。

## 背景

[縦切りの親](20261030-archive-pruned-read-result.md)、[preflight #82](https://github.com/f4ah6o/dsh.mbt/pull/82)、[codec #83](https://github.com/f4ah6o/dsh.mbt/pull/83)、[batch replay #79](https://github.com/f4ah6o/dsh.mbt/pull/79) の後続。原文を全 event に保持したままでは従来の session 容量を越えられない。

## 問題

外置き ref を無検証で信頼すると原文・prune・tool 相関を失う。一方、復元時に全原文を展開する一時的な容量も無制限にはできない。

## 目標

参照と原文 object を厳密に検証し、candidate/commit/restore で同じ状態と provider projection を得る。状態変更は明示 commit に限定する。

## 対象外

NativeRuntime の保存・manifest・receipt、disk quota、history UI、外部 wire API、実機受入、公開製品としての容量改善。

## 提案する方針

旧 v1 を維持し v2 のみ参照を認める。object、SHA、sequence、call/effect、completion/result、pruning と derived messages を検証する。容量・復元一時展開の上限を candidate/commit/restore で一致させる。未対応 fork、偽 ref や余剰 marker は拒否する。副作用を restore で再実行しない。

## 受け入れ条件

- [ ] 複数 Read の累積原文が旧 262144 上限を越えても engine 候補・commit・復元・次 turn が整合する。
- [ ] 改竄、相関不一致、marker 漏れ、容量超過は状態変更なく拒否される。
- [ ] approval・cancel・中断の復元で外部作用が再実行されず、v1 と fork の境界を維持する。
- [ ] engine 限定の制限と SHA 検証、実際の storage・履歴表示未実装を明記する。

## テスト計画

- portable matrix と native codec interoperability、外部 SHA vectors、累積原文と hydration quota の試験。
- 独立レビュー、format/check、Issue validator と CI。

## リスク

object を検証した engine state だけでは durable publication や receipt の原子性を保証しない。v2 の旧 UI への表示は禁止または archive-aware 対応が必要。proof の一時展開に追加 7 MiB 上限がある。

## 変更履歴

`CHANGES.md` impact: no

## 注記

積み上げ先は未マージ #83、#79 は別依存。保存・読取・quota・unknown outcome・実機受入を満たすまで長期会話の完成としない。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。候補と derived messages の不一致、未消費 ref、v1 imported extension の互換性、reopen の hydration budget 等の指摘を修正。独立試験では 6×63000 bytes の累積原文・毎回 reopen・次 turn と approval/cancel/interruption no-replay を全4 target で確認。38 object 後の hydration quota 拒否で前状態の reopen を確認。portable SHA は独立 38 vectors を全4 target と既存 native SHA に照合。保存・history UI は未実装、製品容量改善とは扱わない。
