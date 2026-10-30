# subagent の永続化・明示再開・親子所有権の契約を確定する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: research/20261030-subagent-resume-contract

## 概要

既存の foreground read-only child を基礎として、background / resumable subagent へ進む前に、保存対象、親子所有権、再開点、承認・取消・外部作用の契約を調査する。結果を根拠に最初の実装範囲を確定し、job / workflow 全体を先に設計しない。

## 背景

実装基準は main `8e7ec94e2436edf0db961659130c0390122fd38c`（2026-10-30 調査）。[0001 upstream parity](0001-upstream-parity.md) が subagent / job の残る全体を追跡する。

- [現行 foreground subagent](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/runtime/subagents.mbt)
- [状態と effect 所有権](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/architecture.md)
- [foreground subagent の制約](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/native-runtime.md)
- [移植状況](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/port-status.md)
- upstream 比較基準: `deepseek-ai/deepseek-harness@5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

`--enable-subagents` は同じ provider/model route で bounded child loop を実行し、read / glob / grep と configured hooks を使用する。child は独立した durable session ではなく、settled result を親の tool result として保存する。復元時は子の provider / tool を再実行しない。configured hooks は trusted host code であり、read-only tool catalog は OS sandbox を意味しない。

ACP session resume は別の既存機能であり、child の保存・再開能力を示さない。

## 問題

1. background 実行、接続断後の host 継続、process 再起動後の復旧、利用者が明示する再開は異なる契約である。
2. child を永続化すると、parent result と child state のどちらが確定済みかを矛盾なく識別する必要がある。
3. 外部作用の結果が不明な場合、単に未完了 step を再実行すると tool / hook / provider が重複する。
4. provider/model/account、workspace、tool catalog、承認 policy が変わった後に古い実行権限を継承できるとは限らない。
5. existing foreground child、PWA remote receipt、ACP session の lifecycle を同じ「resume」として扱うと、境界が不明になる。

## 目標

foreground の現行保証を維持しながら、child 保存・background 化・明示再開のどこまでを初期 increment にするか決める。状態遷移、永続 ID、親子関係、cancel、承認、restore と再開の違いを明示し、実装可能な Issue へ展開する。

## 対象外

- この調査中の production engine / child store / runtime 実装。
- unrestricted write / shell child、共有 mutable workspace の並列書込、無制限の子生成。
- scheduler、cron、汎用 workflow、複数ホスト分散実行の一括実装。
- OpenCode runtime adapter の実装や、外部 runtime が所有する session との統合。
- 結果不明の外部作用を暗黙再実行する recovery、型だけでの exactly-once 保証。

## 提案する方針

1. 着手時の main と pinned upstream の subagent / lifecycle / persistence を比較する。現行 foreground、ACP resume、remote receipt のそれぞれについて、保存対象と結果不明時の現行動作を整理する。
2. 次の候補を区別して比較する。子の監査・閲覧用保存だけ、host 生存中の bounded background child、settled checkpoint からの明示再開、のどれを最初に出すか決める。
3. parent / child / turn / effect / command の識別と所有者を定義する。親と子の checkpoint 前後、parent result 採用前後、process kill の時点で、重複 result や orphan がどう扱われるかを表にする。
4. pending approval、provider request、tool dispatch、hook invocation、retry wait、child settlement、parent の取消・削除・fork の状態ごとに復元後の許可操作を定める。
5. restore は既知の記録を読む操作、resume は新しい明示 command として区別する。結果不明の作用、失効した権限、変更された workspace / account / tool catalog を自動引き継ぎしない。resume 可否と拒否理由を定義する。
6. child 数、深さ、時間、出力、保存量、cleanup / reap の上限を検討する。model override や tool filter は初期契約の必要性を確認してから扱う。
7. UI が表示すべき状態、承認主体、取消対象を整理する。表示用状態と実行権限を混同しない。
8. 結論と採用しない案の理由を保存し、最初の実装 Issue に state / recovery / migration の受入条件を写す。未確定の job API や保存形式は親 map に残す。

## 受け入れ条件

- [ ] foreground / background / process restore / explicit resume / ACP resume の違いが表になっている。
- [ ] 初期 increment と対象外の lifecycle が決まり、最低 2 案の比較と採否理由が記録されている。
- [ ] 親子の所有権、永続 ID、checkpoint と result 採用の規則が定義されている。
- [ ] 各 interruption point の restore / resume 操作、結果不明、二重完了、orphan、cancel の期待状態が記録されている。
- [ ] approval / account / model / workspace / tool catalog の変更時の再検証と拒否条件がある。
- [ ] foreground 互換、旧 store、migration、上限、cleanup の受入条件を持つ実装 Issue が作られ、親 map / 0001 へリンクされている。

## テスト計画

1. keyless の既存 foreground subagent / cancellation / restore / hook fixtures を読み、守るべき保証と追加が必要な保証を分ける。
2. provider 送信前後、tool / hook 実行前後、child checkpoint 前後、parent result 採用前後の crash / cancel / reopen 行列を作る。
3. 重複 resume command、遅延 completion、親取消と child 完了の競合、二重 reopen、catalog / account / workspace 変更の trace を定義する。出力だけでなく provider / tool / hook の呼出回数と書込の有無を検証対象とする。
4. parent と child の保存片方のみが成功する状態について、不整合を拒否するか安全に回復できるかを検討する。構成を選ぶ前に atomicity の保証を仮定しない。
5. 調査で既存テストを実行した場合はコマンド・SHA・件数を記録する。後続実装では portable engine / native runtime と実際に公開する CLI / browser / ACP 面だけに必要な受入を追加する。

## リスク

- 結果不明を単純に retry すると副作用や課金が重複する。
- 永続 child を導入すると、既存 reader、restore 検証、parent fork と cleanup の互換条件が増える。
- read-only tools でも configured hooks は host code であり、background 化により実行 lifetime が延びる。
- 長期会話の storage 契約と後で共通変更が必要になる可能性がある。調査は独立して始め、実装上の依存が判明した時点で map を更新する。

## 変更履歴

`CHANGES.md` impact: no

契約調査のみ。後続実装で保存形式・再開挙動・承認や運用が変わる場合は、その Issue の impact を yes とする。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [dsh.mbt の開発方針と実利用までの判断順序を整理する](20261030-development-direction.md)
- Type: research
- Mode: AFK
- Depends on: none

実行状態: open。本文作成時点では契約調査・実測を未実行。background / resumable subagent が使用可能になったとは扱わない。
