# 長い会話の summary compaction と prefix 計画を安全に段階化する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-compaction-planning

## 概要

既存の auto-pruning と provider request byte ceiling の先に、summary compaction の保存・失敗・再開契約を定義する。最初の実装増分は、settled history の古い whole-turn prefix を選ぶ read-only planner に限定し、summary provider call や transcript mutation を行わない。

## 背景

基準は #76 の長期会話調査と、未マージの PR #90 / #95 である。#90 は明示 opt-in の tool-result projection pruning と eligible Read の原本 archive を追加する。#95 は各 provider dispatch 前に engine request の UTF-8 bytes を測定し、per-turn ceiling を超える request を拒否する。これは token 数や model context-window の保証ではない。

現在の別契約は canonical session JSON 262,144 UTF-16 code units、session ごと 32,768 events、native outer snapshot 32 MiB、archive object directory 64 MiB である。archive quota は existing regular Read result objects に適用され、任意の conversation event range の archive 形式ではない。最新 tool completion 自体が session 上限を越す場合は、後続の summary / archive に到達する前に `session_capacity` で閉じる。

根拠:

- [PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) — contract research と長期会話の issue 分割。
- [PR #90](https://github.com/f4ah6o/dsh.mbt/pull/90) — opt-in automatic tool-result pruning と eligible Read archive。
- [PR #95](https://github.com/f4ah6o/dsh.mbt/pull/95) — request byte ceiling。exact head `4d0113c200d85e6c1739d2d983c7d6d35c1f8475`。
- pinned implementation baseline: main `8e7ec94e2436edf0db961659130c0390122fd38c`。

## 問題

1. byte ceiling は oversized request の dispatch を防ぐが、history を縮めない。
2. #90 の projection pruning は provider context を縮めても canonical history の保存量を減らさず、eligible でない Read 以外の原本を別保存しない。
3. model summary は課金を伴う外部 effect であり、単純な「summary を作ってから古い event を消す」では cancel、checkpoint failure、結果不明、reopen に安全でない。
4. existing archive v2 は regular Read result 用である。full event span の archive、summary projection、fork / import、history display の統合は未定義。

## 目標

選択肢と summary lifecycle を固定し、後続実装が provider context budget、durable quota、original provenance を混同しないようにする。最初の増分では、操作を起こさずに summary 入力候補を再現できる prefix plan を返す。

## 対象外

- この増分での model-generated summary、automatic trigger、transcript replacement、archive object publication。
- tokenization、provider model window の推測、bytes から tokens への換算。
- latest completion が canonical session capacity を越した後の回復。
- imported, fork-related, active, approval-waiting session の compaction。
- restore 時の provider, tool, hook, approval effect の再実行。

## 提案する方針

### 候補の比較と選択

| 案 | 効果 | 原本・相関・安全性 | 制限 |
| --- | --- | --- | --- |
| budget-driven tool-result pruning | byte ceiling に収まるまで既存 result projection を段階的に縮める | model call を増やさず、event / call correlation は維持できる。原本の外置きは現行 Read subset のみ | assistant/user history は縮まらず、canonical storage を空けない。#90 の後続拡張として有用だが summary ではない |
| generated summary + archived event prefix | 古い会話を短い summary message に置き換え、元 event range を archive に保存する | start/result/checkpoint、effect identity、source range、archive reference を原子的に結び、原本・approval・hook provenance を表示可能にする必要がある | 新しい event / manifest schema、quota、cancel / reopen / unknown outcome、fork reader、history API が必要。単独の小さな実装ではない |
| read-only whole-turn prefix planner | 明示した byte budgets に収まる最長の古い complete-turn prefix を選ぶ | snapshot / queue / events を変えない。event sequence range、exact source-event digest、現在の pruning state を反映した projected-message digest を返し、later caller は stale input を拒否できる | summary を生成せず、provider request fit や storage reduction を保証しない |

選択: 先に read-only prefix planner を実装する。summary executor は別の schema / lifecycle 増分にする。planner は `Idle` / `Completed` の non-imported, non-fork-related session のみを受け付ける。`retain_recent_turns >= 1` と `max_source_messages_json_utf8_bytes` を必須入力とし、最古から連続する complete turns のうち、model-message projection の serialized UTF-8 bytes が上限に収まる最長 prefix を返す。一番古い turn すら収まらない、または retained tail より前に turn が無い場合は plan なしを返す。

plan は `expected_event_count`、連続した source event seq bounds、exact source event array の `source_events_sha256` と exact projected message array の `source_messages_sha256` を含む。後者は、選択 event 範囲外にある `ToolResultPruned` event も含めた session-wide pruning state による表示内容を束縛する。plan は advisory input であり、将来の mutation API の認可や fresh snapshot の証明ではない。mutation は同じ candidate transaction 内で再計画・照合し、event append だけでなく event count が同じ projection change も検知してから開始する。planner が返す byte 数は source event array と source messages array の JSON bytes であり、compaction instruction、provider wire format、summary output、token 数を含まない。各配列は portable engine の既存 1 MiB SHA-256 bound 内に制限する。

## Summary lifecycle 契約案

将来の model-generated summary は `max_provider_request_utf8_bytes` の明示 opt-in がある `session_send` に限って、新しい turn / UserPromptSubmit hook admission より前に行う。summary 呼び出しに tool schema を含めず、tool / hook を実行しない。source span は prior settled turns の contiguous prefix で、system prompt と retained recent whole turns は保護する。model call は通常の assistant reply と区別する purpose、compaction ID、effect ID を durable に結び付ける。

| State / trigger | Durable history and visible context | Next external effects | Reopen behavior |
| --- | --- | --- | --- |
| Plan only | original transcript unchanged; no new event | none | same plan can be recalculated; stale fingerprint is rejected |
| Start checkpoint rejected | original transcript and current projection unchanged | provider/tool/hook none | retrying admission is safe because no provider effect started |
| Start checkpoint committed, before dispatch | durable start identifies source span, budget, model route, and unique effect | provider dispatch only after checkpoint; no tools or hooks | unmatched start becomes failed/unknown; never dispatch it again automatically |
| Summary request in flight, cancel / process loss | original transcript remains authoritative; partial stream is diagnostic only | abort owned provider task; no tool/hook | settle as unknown if final response was not durably committed; no provider replay |
| Provider failure or invalid / oversized summary | original transcript and projection unchanged; append one terminal summary failure if storage admits it | no retry of same effect; no user turn yet | failure remains visible; a later explicit request must use a new ID |
| Summary response known, archive / final checkpoint rejected | original transcript and projection remain authoritative; published but unreferenced object counts against quota | do not retry same provider effect; do not start user turn | receipt/revision decides whether commit landed; if unknown, never repeat the effect |
| Summary + archive manifest + replacement checkpoint committed | original event range remains retrievable with tool/call IDs, approval and hook provenance; compact projection becomes active atomically | only then admit the requested user turn and its hooks/tools | restore validates manifest, digest and references; no provider/tool/hook replay |
| Archive quota exhausted | original transcript and projection unchanged | no summary dispatch if reservation can be checked first; otherwise no user turn or tool dispatch | reject with quota failure; original history remains reopenable |

The table is the intended no-replay contract, not an assertion that the runtime already supports these transitions. The first planner increment implements only the first row.

## 受け入れ条件

- [ ] planner は settle 済み non-imported / non-fork-related session の whole-turn prefix だけを返す。
- [ ] prefix selection は明示 byte budget に対して最長の連続 source message prefix を返し、recent tail を 1 turn 以上保護する。
- [ ] result に exact source event seq bounds、expected event count、event と projected messages の SHA-256、turn/message counts、measured unit がある。
- [ ] query 前後で snapshot と queued effects が同一で、transcript / approval / hook / tool correlation が変わらない。
- [ ] active, approval-waiting, fork-related, imported session と invalid budget を fail closed する。insufficient history / oversized earliest turn は plan なしにする。
- [ ] docs が source-message UTF-8 bytes を provider/context-window tokens と区別し、planner が summary completion や storage relief を保証しないことを説明する。
- [ ] summary executor は別 increment とし、state table、bounded summary output、full-event archive schema、finite archive quota、restore/no-replay、history/fork reader を先に実装・検証する。

## テスト計画

- 2–4 completed turns から exact contiguous prefix と retained tail を選び、Unicode / JSON escape を含む source-message bytes を確認する。
- budget が最古 turn より小さい場合、turn 数不足時、invalid / out-of-range budget で plan が返らないことを確認する。
- active provider、pending approval、fork, imported session では拒否する。
- plan query の前後で snapshot と queued effects が不変であること、同じ selected event prefix から異なる projected message content が得られると `source_messages_sha256` が変わることを確認する。
- focused `moon test engine`, `moon check engine`, `moon fmt --check engine` を実行する。full summary transaction、native archive quota、cancel / reopen は後続の tested acceptance とし、この PR で PASS としない。

## リスク

Prefix planning は eligibility と bounded source input を可視化するだけである。summary provider request は追加課金、output、cancel、unknown outcome を持ち、元の session event stream と separate durable archive quota を同じ atomic commit に含める必要がある。Planner output は advisory であり、caller が event count や selected source events のみを照合して session-wide pruning projection の変更を見逃してはいけない。

## 変更履歴

`CHANGES.md` impact: no

Read-only planning API の追加。summary output や transcript の動作変更はない。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [dsh.mbt の開発方針と実利用までの判断順序を整理する](https://github.com/f4ah6o/dsh.mbt/blob/87042bb70af9fa5f9b64e4b82ef53cf4a227c5c6/issues/open/20261030-development-direction.md)
- Type: implementation
- Mode: AFK
- Depends on: PR #95 (`feat/20261030-provider-request-byte-ceiling`)

実装状況: planner のみ。summary provider effect、archive schema、quota policy と cancel / reopen state machine は未実装。
