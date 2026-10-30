# provider request の UTF-8 byte ceiling を dispatch 前に適用する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-provider-request-byte-ceiling

## 概要

`session_send` の明示 opt-in により、一つの session turn で engine が構成する provider request の UTF-8 byte 上限を指定し、各 provider effect を作る前に拒否する。

## 背景

[PR #93](https://github.com/f4ah6o/dsh.mbt/pull/93) は、active engine request の serialized UTF-8 byte size と Unicode code point を read-only で測定する。次の小さな段階として、呼び出し側が選ぶ byte ceiling を request admission に使える。ただしこれは engine representation の測定であり、provider/model の tokenizer 情報ではない。

## 問題

現在は request size を観測できても、一定の byte 数を超える request を provider に渡さない opt-in admission rule がない。初回だけ検査すると、tool completion や hook context の後に組み直される同じ turn の request が上限を越えても dispatch される。

## 目標

API から 1..16 MiB の `max_provider_request_utf8_bytes` を指定可能にし、その `session_send` turn の各 request を bounded measurement で検査してから LLM effect を発行する。上限超過または測定不能時は provider effect を作らず、`provider_request_limit` で turn を閉じる。既に受け取った tool/hook 結果は通常の durable session capacity が許す範囲で保持し、拒否後に tool/provider/hook を暗黙再実行しない。

## 対象外

正確な token 計測、provider context-window の把握や保証、automatic summary/compaction、archive quota、session/event durable capacity の増加、他 session / 別途開始した child turn への ceiling 継承は対象外。byte ceiling を model limit や長期会話対応と説明しない。

## 提案する方針

optional な `session_send.max_provider_request_utf8_bytes` を 1..16 MiB に閉じて validate する。設定は `turn/start` event に記録し、旧 event の空 data はそのまま受理する。restore は ceiling の integer range と data shape を検証し、approval-waiting turn に設定を復元する。`start_step` は最終 message projection と tool schemas から一度だけ request を構成し、#93 の有界 size walker で `step/start` と `emit_effect` より前に測定する。上限超過・16 MiB measurement bound 超過・invalid string は provider effect を発行せず、別 reason で terminal failure にする。tool completion 後の拒否は candidate transaction に既知 outcome を含めて commit し、`Err` でそれを捨てない。既存 session-capacity failure semantics は変更しない。

## 受け入れ条件

- [ ] API は optional byte ceiling のみを受け付け、範囲外・fractional・型違いを状態変更前に拒否する。設定なしの挙動は変わらない。
- [ ] 設定 turn の初回および tool/hook continuation の各 request を `emit_effect` 前に測定し、超過時は LLM effect を queue に入れず `provider_request_limit` で閉じる。
- [ ] request ceiling は `turn/start` で durable になり、approval-waiting session restore 後にも適用される。古い turn-start の空 data は引き続き restore できる。
- [ ] tool outcome が durable session capacity 内であるとき、次 request の ceiling rejection は tool result/call correlation を保持し、reopen 後に effect を再発行しない。
- [ ] restore は malformed ceiling、ceiling なしの `provider_request_limit` reason、不正な境界列を拒否する。
- [ ] docs は engine request JSON UTF-8 bytes と wire/token/context-window の単位を区別し、durable capacity を別契約として説明する。

## テスト計画

- exact boundary と 1 byte under、無効な input range/type、API field validation を engine/API tests で確認する。
- LLM -> tool -> over-ceiling next request と late SubagentStart context の経路で、既知 outcome/context admission 後に新しい provider effect が無く、valid snapshot が restore できることを確認する。
- approval-waiting turn の snapshot/reopen/approve/completion で ceiling が維持されること、malformed/tampered turn-start と terminal reason が restore で拒否されることを確認する。
- `moon check`, `moon fmt`, engine/API portable/native matrix、Issue validator、independent exact-HEAD review を実行する。

## リスク

上限は provider-specific wire transformation より前の engine JSON UTF-8 bytes に適用されるため、provider が受け入れる bytes、token 数、context-window fit を保証しない。既に実行・記録された tool/hook outcome は後続 request 拒否で取り消せない。個別 result が既存 durable session capacity を越す問題も解決しない。ceiling は明示した session turn に限られる。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- session-send の明示 opt-in provider request UTF-8 byte ceiling を追加する。

## 注記

PR #93 の measurement primitive を再利用する段階。上限超過は turn を失敗として閉じるが、summary、history pruning、archive、durable session capacity の拡張を意味しない。最大値は measurement walker の 16 MiB request bound と一致させる。
