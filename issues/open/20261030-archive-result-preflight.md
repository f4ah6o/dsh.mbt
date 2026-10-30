# 縮約済み Read 結果の外置き候補を検証する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-archive-preflight

## 概要

将来の原本外置きに先立ち、対象 Read 結果の相関・縮約・session 状態を読み取り専用で検証する。

## 背景

[PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) と [0001](0001-upstream-parity.md) の長期保存調査。Read の原文は tool/completed、tool/result、messages に現れ、単に file へ移すと restore と pruning の検証を壊す。

## 問題

曖昧な provenance、未確定 effect、fork prefix、改竄された pruning を含む結果は、安全に外置きできない。

## 目標

既存 state を根拠とした狭い候補のみを特定し、不適合を状態変更なしに拒否する。

## 対象外

object 保存、schema v2、quota、history API、自動縮約、容量拡張、公開 wire API。

## 提案する方針

session ID と result sequence から、非 imported・fork 関連なし・settled・未解決 effect/approval/hook なし、通常 Read の単一 effect completion と一致する result、原文から直接検証できる pruning を確認する。親参照だけでなく他 session からの子参照も拒否する。結果は内部の型付き plan に限定する。後続の保存操作は gate 内で候補を再導出する。全ての介在変更を検出するには別の freshness stamp が必要である。

## 受け入れ条件

- [ ] 正しい Unicode Read と有効な直接 pruning を認め、不一致・不明な provenance・複数 completion を拒否する。
- [ ] active、approval、import、fork 親子を拒否し snapshot や effect を変えない。
- [ ] reopen 後の同じ判定と、wire 非公開・容量が増えないことを確認する。

## テスト計画

- engine の対象 fixture と portable matrix、独立レビューを実施する。
- local issue validator、format/check を実施する。

## リスク

plan は時点の観測であり保存や承認を意味しない。原本には機密が含まれ得る。v2 replay、manifest、quota、object 原子保存と履歴参照が揃うまで容量改善はない。

## 変更履歴

`CHANGES.md` impact: no

## 注記

後続の原本外置きは completed/result の両コピー・derived messages を一致させ、同一 session の累積原文が旧上限を越えても no-replay で継続できることを受入条件とする。hash のみを承認の証明としない。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。Read effect に分類される glob/grep/skill/subagent を候補に含める指摘を修正し通常 read の schema に限定。`moon test engine provider auth protocol client plugins api ui verification/retry_math --target all` は各 backend 225/225 PASS、独立 focused test は各 backend 9/9 PASS。format/check と Issue validator PASS。plan に freshness revision はなく、後続 mutation は gate 内で候補の再導出と必要な revision 検証を行う。容量改善・保存は未実装。
