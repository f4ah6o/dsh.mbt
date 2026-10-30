# caller-supplied summary を durable event と provider context に結び付ける

Status: open
Model: GPT-6 Codex
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-durable-summary-checkpoint

## 概要

read-only whole-turn planner と呼び出し側が渡す bounded summary から、source provenance を検証した durable summary event を追加する。event と transcript は保持し、将来の provider context projection だけで summary を使う。

## 背景

`20261030-compaction-prefix-planning.md` は read-only plan と exact source fingerprints を追加した。`20261030-bounded-summary-candidate.md` は plan から一時 candidate を作るが、restore 後の context としては残らない。summary provider effect、event-range archive、storage quota 拡張は別の設計を要する。

## 問題

一時 candidate は process restart 後に使えず、caller が同じ bounded summary を繰り返し渡す必要がある。一方、元 history を削除・置換する event compaction を実装すると、tool result、approval、hook provenance、restore と既存 archive-v2 の互換性に別の schema と quota が必要になる。

## 目標

fresh plan に束縛した caller-supplied summary を event log に保存し、reopen 後の provider projection に同じ plain assistant historical context として戻す。original event と transcript はそのまま保持し、restore は event を検証するだけで provider、tool、hook、approval effect を replay しない。

## 対象外

- provider-generated summary、summary model route、automatic trigger、token meter、aggregate pressure policy。
- original event deletion、full event-range archive、spill / GC、storage/session quota 拡張。
- summary-bearing session の fork、summary と archive-v2 object reference の共存。
- runtime checkpoint error 後の in-memory rollback。既存 runtime は checkpoint failure で stopped になり error を返すが、candidate Engine の in-memory mutation は残る。

## 提案する方針

`session_compaction_plan` と `session_compact_summary` を持つ。mutation は fresh whole-turn plan の全 field と `source_events_sha256` / `source_messages_sha256` を比較し、JSON string として計測した summary byte limit を適用してから `compaction/summary` event を一つ追加する。record は `dsh.compaction-summary-record-v1` schema、plan、plan options、summary bytes、`origin: caller-supplied`、`context_role: assistant` を持つ。system role、tool call、reasoning metadata は付けない。

provider projection では source range に含まれる元 message を隠し、summary を「caller-supplied historical summary」であると明記した plain assistant message として、最古の source sequence に挿入する。表示 transcript と event log は変えず、approval / tool / hook event と相関 ID も保持する。後続 summary は前の summary 済み turn span を再利用せず、未要約の後続 whole turns のみを選ぶ。raw source event range は turn-boundary provenance として、以前 append された summary marker を含む場合がある。その marker 自体は source model message にはならない。

restore は各 summary event を append 直前の event prefix で再計画し、当時の pruning projection と両 fingerprint を再検証する。これにより summary 後の pruning が過去の source message digest を書き換えない。tampered provenance、role、options、range、summary bytes、plan digest は restore 全体を拒否する。

archive-v2 reference を含む session への summary commit は拒否する。summary-bearing history に対する後続 archive plan / commit も拒否する。summary のない session に対する read-only compaction planner は、archive-v2 reference のある履歴も含めて既存互換性を維持する。summary-bearing source の fork は拒否する。

summary は context size を減らす場合があるが、canonical event log、transcript、durable snapshot は短くしない。event と summary text は既存の 262,144 UTF-16-unit / 32,768-event session cap を消費する。1 MiB source / summary limits、32 MiB native outer snapshot、existing archive object quota は別個で、いずれも増やさない。

## 受け入れ条件

- [x] 有効な fresh plan から provenance-bound summary event を追加し、元 event と transcript を byte-for-byte 保持する。
- [x] provider model projection と restore 後 projection が一致し、summary は system authority を得ない。
- [x] event、summary の二つ目の source digest、options、role / provenance、range、byte metadata の改変を restore が拒否する。
- [x] 後続 prune を含む event history でも summary は append 時点の historical prefix で検証される。
- [x] stale / busy / event-capacity / serialized session-capacity refusal は live snapshot と effects を変更しない。
- [x] summary commit と restore は effects を生成せず、archive-v2・fork 境界を fail closed する。
- [ ] NativeRuntime `session_compact_summary` の専用 checkpoint-failure test を default-stack native test link で実行する。現時点では追加の direct async whitebox fixture が `moonc link-core` stack overflow を起こすため、既存の generic competing-SafeRoot failure fixture と engine snapshot/restore coverage を使っている。

## テスト計画

- `moon check engine api runtime --target all --deny-warn`
- `moon test engine --target all --deny-warn`
- `moon test api --target all --deny-warn`
- `moon test runtime --target native --deny-warn --no-parallelize` と summary-specific checkpoint test を実行し、native link が標準 stack で通ることを確認する。
- archive-v2 source fixture で archived session への commit refusal、summary-bearing history からの archive refusal、baseline read-only planner compatibility を確認する。
- `moon fmt`、`git diff --check`、issue validator、exact-HEAD independent review を行う。

## リスク

summary の内容の正しさや安全な要約を意味的には検証しない。caller text は plain assistant history として扱い、summary API は生成も自動化もしない。event / session quota を消費し、context projection の saving と durable storage relief は区別する。runtime checkpoint failure の操作固有 test は compiler stack limit のため未追加で、generic checkpoint failure test は別 operation を対象にしている。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- caller-supplied compaction summary を provenance-bound event として保存し、original history を保った provider context projection に使う。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [長い会話の summary compaction と prefix 計画を安全に段階化する](20261030-compaction-prefix-planning.md)
- Type: implementation
- Mode: AFK
- Depends on: PR #99 (`feat/20261030-compaction-plan-validation`)

実装状況: Engine event、historical restore validation、API capability、context projection、fork/archive guards を追加。これは manual context projection の increment であり、summary generation、event deletion、storage archive quota、automatic compaction を実装しない。
