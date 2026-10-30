# 既存履歴に束縛した bounded summary candidate を作る

Status: open
Model: GPT-6 Codex
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-compaction-plan-validation

## 概要

read-only prefix plan と呼び出し側が渡す summary text から、一時的な summary candidate を組み立てる。組み立て時に現在の session を再計画し、source event と projected message の両 fingerprint、event count と source range を照合する。session event、保存領域、provider queue は変更しない。

## 背景

PR #96 (`cb6ef8ecafd0e5cb9e68b1cc070b2df2fc5efdb7`) は settled history の古い whole-turn prefix を選ぶ read-only planner を追加した。plan は source event 配列と model message projection の両 SHA-256 を含む。2 つ目の digest は、選択範囲外の pruning state が projection を変えた場合も検出する。

summary provider effect、full-event archive、durable summary state、quota は引き続き未実装である。context request bytes は durable session や archive storage の容量を表さない。

## 問題

plan 作成後に event log や tool-result projection が変わると、呼び出し側が以前の summary output を現在の source に誤って結び付ける可能性がある。event count と source event fingerprint だけでは session-wide pruning projection の変更をすべて検知できない。

## 目標

明示された plan budgets と retention policy で現在の plan を再計算し、両 fingerprint を含むすべての source identity fields が一致する場合だけ、有限サイズの summary candidate を返す。candidate は元 event を置換せず、tool result、approval、hook と tool correlation を元 session で保つ。

## 対象外

- provider 呼び出し、summary generation、automatic trigger、tool / hook execution。
- candidate の event log / snapshot への保存、resume 後の candidate recovery。
- transcript replacement、original-event archive object、history UI、fork reader。
- durable archive quota や session capacity の拡張。
- cancellation、provider outcome unknown、save failure の summary transaction state machine。

## 提案する方針

`Engine::prepare_compaction_summary_candidate` は session id、以前の plan、plan 作成時と同じ retain / byte budgets、summary text、summary JSON UTF-8 byte limit を受け取る。既存 planner で fresh plan を作り、session id、expected event count、seq / turn bounds と counts、両 byte measurements、`source_events_sha256`、`source_messages_sha256`、unit を比較する。fresh plan が無い、session eligibility が変わった、または field が異なると candidate を返さない。

summary text は JSON string として serialize した正確な UTF-8 byte count で明示 limit を適用し、portable digest/source bound と同じ 1 MiB 上限を越さない。返却 candidate は schema name、exact source identity fields、summary text、summary byte count を持つ。candidate は advisory な一時値であり、後の mutation が使う場合はその transaction 内で同じ照合を改めて行う必要がある。

この API は provider effect の開始 / retry marker を記録しない。呼び出し元が summary provider を動かすようになった場合、cancel、unknown outcome、checkpoint failure、reopen no-replay は separate durable increment で実装する。candidate API 自体は provider / tool / hook を呼ばないため、作成失敗や stale refusal による replay はない。storage quota は active context budget から推論せず、archive object の durable quota として別に設計する。

## 受け入れ条件

- [ ] valid plan と bounded summary から、元 event を変更せず source identity を含む candidate を作る。
- [ ] candidate 構築前後で session snapshot と queued effects が同一。
- [ ] source event change、same-count projected-message-only change、event count change、異なる plan field の各場合に stale candidate を拒否する。
- [ ] candidate は最初の PR #96 planner の両 SHA-256 値を比較する。
- [ ] invalid / oversized summary は拒否し、provider/tool/hook effect を追加しない。
- [ ] completion を保存、resume、再送する能力や storage capacity の低下を主張しない。

## テスト計画

- no-effect candidate を Unicode / JSON escaped summary で作り、summary byte count と全 source identity fields を確認する。
- source history を変えた後、message projection だけ変えた後、event count を同じに保った projection mutation 後にそれぞれ stale refusal を確認する。
- plan JSON の source event / message fingerprint や range を個別に改変した場合を拒否する。
- empty / over-budget / invalid-limit summary inputs が snapshot と effect queue を維持したまま拒否されることを確認する。
- `moon check engine --target all --deny-warn`、focused `moon test --target all --deny-warn -p f4ah6o/dsh/engine`、`moon fmt --check engine`、`git diff --check` を実行する。

## リスク

candidate に対する provider output の意味的な正しさは確認しない。provider generation と durable commit の間の no-replay はこの increment の範囲外である。元 history は変更しないため、candidate API による durable storage relief はない。

現在の `EngineEventKind` に native summary lifecycle event はなく、`engine/session_v4_types.mbt` の compaction data は read-only import projection である。canonical session は `engine/transaction.mbt` の 262,144 UTF-16-unit / 32,768-event cap を持つ。archive v2 は pruned Read result object 用で任意の source event range を保存しない。durable replacement には full-range archive / manifest schema、有限 quota と orphan cleanup、summary effect identity / terminal outcome、atomic session + manifest checkpoint、restore・history・fork readers が必要で、これが揃うまでは summary result の保存や event replacement をこの小さな increment に含めない。

## 変更履歴

`CHANGES.md` impact: no

一時 candidate の読取専用 API。model request、保存形式、transcript 動作は変えない。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [長い会話の summary compaction と prefix 計画を安全に段階化する](20261030-compaction-prefix-planning.md)
- Type: implementation
- Mode: AFK
- Depends on: PR #96 (`feat/20261030-compaction-planning`)

実装状況: no-effect summary candidate のみ。provider effect、durable summary/archive state、quota、cancel/reopen state machine は未実装。
