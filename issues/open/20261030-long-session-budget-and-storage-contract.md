# 長い会話の context budget と保存容量の契約を確定する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: research/20261030-long-session-contract

## 概要

自動 compaction / summary / spill の実装前に、provider context の予算と durable session の容量を分け、保持・縮約・失敗・復元の契約を調査して確定する。調査結果を根拠として、最初の小さな実装 Issue を作成する。

## 背景

実装基準は main `8e7ec94e2436edf0db961659130c0390122fd38c`（2026-10-30 調査）。既存の [0001 upstream parity](0001-upstream-parity.md) が長い会話の全体を追跡している。本チケットはその実装前に必要な契約調査に範囲を限定する。

- [現行 architecture の手動 pruning / 永続化と容量](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/architecture.md)
- [tool-result pruning 実装](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/engine/tool_result_pruning.mbt)
- [restore 検証](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/engine/persistence.mbt)
- [native store](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/runtime/store.mbt)
- upstream 比較基準: `deepseek-ai/deepseek-harness@5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

現行 pruning は idle / completed の非 imported session に対する手動操作で、次の provider context だけを head / marker / tail に縮約する。元の result と transcript を保持して pruning event を追加するため、保存量は減らない。canonical session の 262,144 UTF-16 code units / 32,768 events 上限は残る。これらは model token limit と異なる単位である。

## 問題

1. provider に送れる context、内部の文字数制限、serialized store 容量を混同すると、縮約後も保存できない状態になる。
2. 自動実行を加えるには、どの境界で判定し、どの history を保持し、失敗時にどこへ戻るかが未確定である。
3. summary 自体が provider request を伴う場合、課金・cancel・retry・結果不明・checkpoint 失敗の扱いを通常 turn と整合させる必要がある。
4. tool call / result、approval、hook context、fork、read-only imported history の関係を壊す縮約は許容できない。

## 目標

予算の種類、trigger、保持対象、縮約と永続化の単位、失敗・復元時の状態表を得る。現行方式の延長で対応できる範囲と schema / storage の変更が必要な範囲を分け、採用案と不採用案の理由を記録する。

## 対象外

- この調査中の production runtime / snapshot schema の変更。
- 未計測の効果を根拠とする上限撤廃や単純な上限引き上げ。
- full Session v4 writer、全 attachment / media 保存、汎用 vector memory。
- model ごとに正確な tokenizer が利用できるという仮定。
- 元 transcript の不可逆な削除を初期解とすること。

## 提案する方針

1. 着手時の main SHA と pinned upstream の関連 compaction / context / spill 実装を記録し、trigger と persistence の責務を比較する。importer が表示できる compaction event を、runtime の実行能力として数えない。
2. 現行コードの上限表を作る。単位、適用場所、拒否する操作、終了記録用の余地、provider model limit と独立している部分を整理する。
3. 次の候補を同じ条件で比較する。採用を先に固定しない。
   - 既存 pruning の自動実行範囲を限定して広げる。
   - 直近の会話と必要な tool 相関を残す summary / checkpoint を導入する。
   - 原本を分離保持し、active context / active store と archive / spill の責務を分ける。
4. summary / spill を採用する場合の操作単位を定義する。開始前、結果受信前、checkpoint 前後、cancel、capacity rejection、reopen の各状態で、見える transcript、次の context、外部作用の再送可否を表にする。
5. model budget をどこから取得するか、未取得・model 切替・Unicode・推定誤差をどう扱うか決める。文字数から token 数への正確な換算を仮定しない。
6. migration、旧 reader、fork、imported history、pruning の idempotence、tool / hook provenance、承認対象の識別を検討する。安全に復元できない入力は既存状態を壊さず拒否する。
7. 結論をこの Issue またはリンクした設計記録へ保存し、独立した受入条件を持つ最初の実装 Issue を作る。後続条件がまだ定義できない部分は親 map の Not yet specified に残す。

## 受け入れ条件

- [ ] context / serialized storage / event count の上限と単位、適用コード、失敗時の現行動作が表になっている。
- [ ] 最小 2 案を比較し、採用案・不採用理由・未決事項・初期 increment の範囲がある。
- [ ] 原本、summary、pruning projection、tool correlation、hook provenance、approval を保持する規則が明記されている。
- [ ] cancel / stream interruption / capacity rejection / checkpoint failure / reopen の遷移と no-replay が検証可能な条件になっている。
- [ ] migration / 旧 reader / fork / read-only import の互換境界と回復方法が示されている。
- [ ] 確定した契約から通常の実装 Issue が作成され、親 map と 0001 に対応関係が記録されている。

## テスト計画

1. 調査の根拠に SHA / source path / fixture を付け、現行の pruning / persistence テストと照合する。
2. keyless trace を使い、長大 tool result、連続 turn、UTF-16 と Unicode code point の差、model 切替、未解決 tool / approval、fork / import の期待結果表を作る。
3. provider response の前後、checkpoint の前後、store 上限直前、cancel と再起動の各点に対し「元 history が保持されるか」「context に何が入るか」「新たな effect が出るか」を確認する試験案を作る。
4. 調査で挙動を実測する場合は既存 package の対象テストを実行し、コマンド・SHA・件数を記録する。未実行の設計表は PASS と表記しない。
5. 後続実装では portable engine matrix、native store / provider 境界、必要な CLI / browser の受入を選ぶ。`npm test` と Node 不在 verifier は実装差分の必要な gate として扱う。

## リスク

- summary は情報を失う可能性があり、承認や tool 結果の根拠を曖昧にできない。
- archive / spill は保存量を別の場所へ移すため、retention、原本との参照、移行・破損時の回復が必要になる。
- summary provider の結果不明時の再送は重複課金を伴い得る。既存の no-replay を維持する。
- 現行上限の一部を変更すると他の API / UI / snapshot の上限へ移る可能性がある。

## 変更履歴

`CHANGES.md` impact: no

契約調査のみ。後続実装で context や store の互換性が変わる場合は、その Issue の impact を yes とする。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [dsh.mbt の開発方針と実利用までの判断順序を整理する](20261030-development-direction.md)
- Type: research
- Mode: AFK
- Depends on: none

実行状態: open。本文作成時点では契約調査・実測を未実行。現行ソースと文書の確認を根拠として問いと受入条件を定義した。
