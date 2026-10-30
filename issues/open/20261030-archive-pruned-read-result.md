# 縮約済み Read 原本を独立保存する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-archived-read-result

## 概要

settled session の直接 pruning 済み通常 Read 原文を durable object へ外置きし、同一 session の inline 容量を回復する。

## 背景

[PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) の長期会話調査。前提は [batch replay #79](https://github.com/f4ah6o/dsh.mbt/pull/79)、[atomic create #81](https://github.com/f4ah6o/dsh.mbt/pull/81)、[preflight #82](https://github.com/f4ah6o/dsh.mbt/pull/82)。原文は completed/result と derived messages に重複し、単にファイルを分けて v1 restore に hydrate すると上限を越えられない。

## 問題

長い tool output の原文を保持したままでは canonical session が上限に到達する。検証せず原文を取り除くと承認根拠・tool 相関・pruning の正当性を失う。

## 目標

原本と provider 用 projection を保持し、同一 session の累積原文が旧上限を越えても、保存・reopen・次の turn を整合させる。

## 対象外

未縮約結果、通常 Read 以外、active/imported/fork 関連 session、summary、自動 GC、無制限 storage、汎用 scheduler。

## 提案する方針

preflight を mutation gate 内で再導出し、bounded immutable object を known-success で先に公開する。completed と result の content を同一検証済み ref に置換し、v2 manifest・engine・receipt・revision を atomic CAS で確定。v2 restore は object の identity/length/digest と call/effect/result/approval/pruning を検証し、元原文を明示 API から取得可能にする。inline と object quota を分け、temporary/orphan も数える。unknown publication は自動採用・再試行せず、manifest 書込後 unknown は reopen で解決。旧 reader、未対応 fork と history 表示は黙って欠落させず拒否する。

## 受け入れ条件

- [ ] 個々の native Read は 65536 bytes 以下で、累積原文が旧 262144 UTF-16 上限を越えても同一 session が reopen 後に次の turn を完了する。
- [ ] Unicode の元結果・call/effect/approval・projection は復元され、provider には検証済み縮約を送る。
- [ ] object の欠損・破損・不一致、quota、cancel、各保存境界の failure/unknown で状態と外部作用回数が整合し no-replay を守る。
- [ ] v1 を維持し v2 を旧 reader が拒否、非対応 fork/import を変更前に拒否する。

## テスト計画

- 複数 Read と provider fixture で実行・保存・reopen・次 turn、原文 API、state/effect を照合。
- object 前後、manifest 前後、CAS、quota、重複 command、process interruption、破損の故障注入。
- portable/native matrix、Node 不在 verifier、独立レビューと該当 CI。

## リスク

v2 reader と history UI の対応前に旧表示を使うと原文が黙って欠落する。hash は承認や機密性の保証ではない。publish 結果不明と orphan の保全、disk quota、backup/GC、platform durability は別々に検証する。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- 縮約済み Read 原本を保持しながら session の inline 保存量を削減する。

## 注記

作業ブランチは未マージの #79/#81/#82 をローカルで結合した積み上げ。これらの CI・統合条件が確定するまで依存を明記し、main 実装済みと数えない。実装の安全性が成立しなければ曖昧な部分を拒否し、未完了として残す。
