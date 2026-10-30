# Session の保存使用量を観測する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-session-capacity-inspection

## 概要

canonical session の保存使用量と制限を単位付きで読み取る。将来の容量管理の基礎とする。

## 背景

[0001](0001-upstream-parity.md) と未マージの[契約調査 PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) は provider context と durable storage を別の問題として扱う。session の上限は UTF-16 code units と event count で、native envelope の byte 上限や model tokens とは異なる。

## 問題

使用量と制限を比較する手段がなく、異なる単位や必要な終了予約を混同しやすい。

## 目標

既存 admission の計測を再利用した読み取り専用 API を提供し、観測値の意味と限界を明確にする。

## 対象外

容量の増加、token 推定、送信成功の保証、summary、spill、原本削除、native envelope の容量管理。

## 提案する方針

session の serialized UTF-16 使用量と event 数、各上限を返す。`todos:null` の既存互換計測と一致させる。完了・復元用 reserve や将来の入力は含まれないため、差分を利用可能な送信容量と解釈しない。読み取り操作で状態や effect を変更しない。

## 受け入れ条件

- [ ] 既存 admission 計測と一致した使用量、単位、上限を取得できる。
- [ ] Unicode、空・活動中・復元 session、上限付近を試験し、状態や外部作用の変更がない。
- [ ] public API と文書は token 数、native envelope bytes、送信可能保証と区別する。

## テスト計画

- 対象 package の MoonBit portable matrix と native check を実行する。
- 独立レビューと Issue validator を実施する。

## リスク

報告値は瞬間的な値であり、終了予約や serialization の変化を含む実際の admission の代用にならない。従来の容量上限は維持する。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- session の canonical 保存使用量を読み取る API を追加する。

## 注記

この増分は長期会話の完成ではない。immutable chunk、原子的 manifest、checkpoint/suffix 検証、履歴 API、migration、quota、fork、破損や commit 結果不明の扱いは後続設計が必要。PR #77 の provider 投影縮約とは独立する。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh、native query が checkpoint / effect drain していた指摘を修正後、追加指摘なし。`moon test engine provider auth protocol client plugins api ui verification/retry_math --target all` は各 backend 218/218 PASS、app/browser JS 17/17 PASS。native の対象テストは active session の queue、revision、store を保持。全 runtime suite は worker fixture 準備不足による失敗を含み未完了。CI と commit の最終結果は PR を参照する。
