# 送信時に Read 縮約と原本保存を一体化する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-automatic-archive

## 概要

明示 opt-in の送信で、既存 Read 縮約と durable 原本外置きを一つの候補・checkpoint に結び付ける。

## 背景

[#77](https://github.com/f4ah6o/dsh.mbt/pull/77) の送信時 pruning は provider projection のみを縮め、[#87](https://github.com/f4ah6o/dsh.mbt/pull/87) は明示操作で Read 原本を外置きする。両方未マージであり、単に連続実行すると receipt と副作用の確定境界が分裂する。

## 問題

手動操作に依存すると長い会話を自動継続できず、独立 transaction の連結は hook・provider の再実行や部分保存を招く。

## 目標

既定を変えず opt-in の送信において、候補の縮約・原本・prompt と receipt を一貫して確定し、成功後だけ provider を開始する。

## 対象外

正確な token meter、summary、未対応 tool result の外置き、容量無制限、失敗結果の暗黙再送。

## 提案する方針

予約・hook の既存 checkpoint を維持し、gate 内で state と eligibility を再検証。容量と quota を事前に検査し object を先に耐久化、engine・manifest・receipt を単一 CAS で確定してから effect を dispatch する。取消、保存結果不明と旧 session の状態を明示する。

## 受け入れ条件

- [ ] opt-in 送信は再 open 後も原本・tool 相関・承認根拠を保持し、provider projection を縮約する。
- [ ] 複数 turn で旧保存上限を越えて継続し、state・receipt・外部作用回数を確認する。
- [ ] cancel・容量拒否・object/manifest 失敗と結果不明で状態整合と no-replay を維持する。
- [ ] default off と非対象の session/tool の挙動、context 文字数 policy と token limit の違いを文書化する。

## テスト計画

- keyless native 実経路で送信・保存・reopen・next turn と fault / duplicate receipt を検証する。
- portable/native matrix、browser/CLI 該当受入、独立レビューと CI。

## リスク

threshold policy は token pressure meter ではない。object 公開と CAS の間に orphan が残り得る。hook など先行外部作用の結果不明は通常 retry できない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- opt-in 送信の Read 縮約と原本保存を durable に一体化する。

## 注記

未マージ #77/#87 の積み上げ。model 切替、summary、厳密 token budget と event 上限は後続課題。
