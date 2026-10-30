# 縮約済み Read 原本を独立保存する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-archive-runtime

## 概要

settled session の直接 pruning 済み通常 Read 原文を durable object へ外置きし、同一 session の inline 容量を回復する。local integration worktree に bounded native object store、v2 manifest/receipt CAS、explicit original-history endpoint、Browser archive controls を実装した。これは未マージの実装状態であり、main の実装済みとは扱わない。

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

- [x] 6 回の actual NativeTools Read (各 60,003 bytes) を同一 session へ追加し、毎回 close/reopen と次 turn を確認。累積 360,018 bytes は旧 262144-unit 上限を超える。
- [x] typed engine/archive tests と native object reopen test で Unicode 原文 bytes、call/effect/result correlation、projection hash を照合。provider は replay-verified projection を使う。
- [x] object corruption/mismatch、storage / envelope quota、post-publication unknown object, manifest CAS conflict, post-write unknown acknowledgement, duplicate replay を regression test 化。Checked-in Chromium smoke は原文取得・exact render・tamper rejection を通す。
- [ ] Dedicated cancellation-interleaving fault fixture と cross-filesystem power-loss durability は未検証。
- [x] v1 default と v1 marker rejection を保持し、archive は fork/import/active/approval-waiting session に fail closed。旧 MCP/ACP history carriers は projection を原文扱いせず拒否する。

## テスト計画

- Native regression: 6 actual Read results, per-turn durable reopen, exact original-history API, legacy carrier refusal, remote receipt replay, and a subsequent CLI turn.
- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium PATH=/workspace/.moon/bin:$PATH MOON_HOME=/workspace/.moon sh scripts/test-browser-smoke.sh`: PASS, including the archived-original fixture, exact 60,003-byte rendering, tampered-object 404/no-render, and the ordinary browser acceptance flow.
- Failure fixtures cover object OutcomeUnknown both without and after file creation, final manifest CAS conflict, post-write unknown acknowledgement, 32 MiB envelope admission, quota, corruption, and duplicate command. Cancellation interleaving and physical power-loss injection remain open.
- CI #87 run `41118710490` exposed three fixture assumptions: inherited orphan-file mode, treating format 2 as unsupported after adding v2, and a temp-name exhaustion test tied to the process-global serial. The fixtures now set mode 0600 explicitly, use unsupported version 3, and run the serial-range test in a dedicated fresh native process. Under `umask 022`, the affected runtime fixture group passes 11 / 11 and the isolated atomic-create test passes 1 / 1. The post-fix GitHub rerun is pending.
- A separate Windows native runtime smoke step failed in run `41118710627`: the first demo invocation reported `demo run did not resolve the write approval`. This fixture patch does not address that Windows smoke failure.
- portable/native matrix、Node 不在 verifier、独立レビューと該当 CI。

## リスク

v2 reader と history UI の対応前に旧表示を使うと原文が黙って欠落する。hash は承認や機密性の保証ではない。publish 結果不明と orphan の保全、disk quota、backup/GC、platform durability は別々に検証する。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- 縮約済み Read 原本を保持しながら session の inline 保存量を削減する。

## 注記

作業ブランチは未マージの #79/#81/#82/#83/#84 と engine v2 #85 をローカルで結合した積み上げ。実 Chromium smoke はローカル test fixture で通過したが、CI・他 PR への統合と全 platform の filesystem crash durability は未検証。依存の merge 前に main 実装済みと数えない。
