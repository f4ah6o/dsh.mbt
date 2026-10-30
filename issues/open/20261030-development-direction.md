# dsh.mbt の開発方針と実利用までの判断順序を整理する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: docs/20261030-development-direction

## 概要

MoonBit native の agent runtime を日常利用できる状態へ進めるため、現在の実装・配布・受入証拠を分け、既存作業の優先順位と後続の設計調査を整理する。既存 Issue を追跡先として維持し、未確定の長期会話・subagent 再開契約だけを子チケットへ分ける。

## 背景

調査基準日は 2026-10-30 JST。実装基準は main [`8e7ec94e2436edf0db961659130c0390122fd38c`](https://github.com/f4ah6o/dsh.mbt/commit/8e7ec94e2436edf0db961659130c0390122fd38c)（2026-10-21 06:38:59 JST）とする。以下の実装済み判定はこの SHA に対するものであり、今後の着手時は最新 main と差分を照合する。

- [README](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/README.md)
- [アーキテクチャ](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/architecture.md)
- [移植状況](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/port-status.md)
- [M0–M7 / A01–A18 の受入記録](https://github.com/f4ah6o/dsh.mbt/blob/8e7ec94e2436edf0db961659130c0390122fd38c/docs/implementation-status.md)
- upstream parity の比較基準: `deepseek-ai/deepseek-harness@5badb15009ae1756c3afe0ae0cef1faafc290ccc`。比較基準を変更する際は、その変更と追加差分を明示する。

dsh は DeepSeek Harness の MoonBit 移植であり、gpui.mbt / Yami-kumo を使用する実アプリである。native executable が唯一の製品 runtime で、Node host の置換は完了している。Node.js は開発・検証 tooling に限り、browser JavaScript / service worker は MoonBit compiler の生成物である。

### 現在地

| 領域 | main で確認した到達点 | 残る範囲 |
| --- | --- | --- |
| 基本実行 | CLI / Web / desktop、承認、stream、atomic checkpoint、restore 時の no-replay、bounded retry / read 並列 | 実アカウント・実端末・配布物を組み合わせた継続利用の受入 |
| 外部連携 | opt-in MCP stdio client、workspace skills、command hooks、local LSP navigation、ACP session list / resume / model selection | 各機能の bounded subset 外、remote MCP、動的 plugin など |
| SIWC | OAuth、protected credential store、refresh rotation、model discovery / selection、Responses | repository の受入記録では実アカウント推論の完了証拠が未記録 |
| PWA / Tailnet | HTTP/SSE、owner / Host / Origin 検査、command receipt、再同期、PWA 更新 / rollback fixtures | real Tailscale Serve と physical iPhone の lock / kill / network 切替 / 再接続 |
| 長い会話 | 手動 tool-result pruning、元 transcript / tool result 保持 | 自動 compaction、summary、spill、token/context budget、保存容量の扱い |
| Subagent | 同じ provider/model を用いる bounded foreground read-only child | 独立保存、background / resumable child、job lifecycle |
| 移植互換 | Session v4 の明示的 read-only import、各 bounded native subset | v4 writer、Cordis/npm ABI、完全な upstream lifecycle parity |
| IME / 配布 | macOS / Windows / Wayland の opt-in composition と synthetic 検証 | dsh での実 IME・候補操作の受入、main と release の差分確認 |

外部 MCP、skills、LSP、ACP、foreground subagent を新規未実装機能として再登録しない。ACP session resume、Session v4 の履歴表示、subagent の実行再開を区別する。

### CI と release の固定点

| 対象 | 確認結果 | この証拠が示さないこと |
| --- | --- | --- |
| [main runtime/browser CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/39502070000) | `8e7ec94e…`、completed / success | live SIWC、実 Tailnet、iPhone の受入 |
| [main Windows CI](https://github.com/f4ah6o/dsh.mbt/actions/runs/39502069847) | 同じ SHA、completed / success | manual-only desktop smoke は skipped。実 Microsoft IME の受入 |
| [v0.1.28](https://github.com/f4ah6o/dsh.mbt/releases/tag/v0.1.28) | 公開済み、2026-10-20 07:34:20 JST | その後に統合された [Wayland PR #74](https://github.com/f4ah6o/dsh.mbt/pull/74) の配布完了 |

`moon.mod` の version 表示だけで配布済みと判断しない。main SHA、tag の commit、配布物、テスト対象をそれぞれ記録する。

## 問題

1. 古い提案には Node host、未実装 subagent、過去の OS 対応状況が残り、現在の main と同じ時点の記録として読めない。
2. CI の fixture 成功、ログイン成功、モデルの実応答、tool 実行、実機 UI、配布済みの範囲が別々に存在し、実利用の完了条件が把握しにくい。
3. 長い会話では、provider context の縮約と durable store 容量を同じ問題として扱うと設計を誤る。現行の手動 pruning は保存量を減らさず、イベントを追加する。
4. foreground child の拡張には、子の永続化、親子の所有権、承認、再開点、外部作用の重複防止の判断が必要である。
5. 未マージの実装・方針 PR があるため、同じ機能を新規 Issue で重複実装すると競合する。

## 目標

Mac / Linux 上の native runtime を iPhone PWA から使う主要経路について、実装・受入・配布の根拠を結び付ける。その上で、長い会話と実行再開の契約を決め、独立してレビューできる実装 Issue を作れる状態にする。

本 map の作成は、実機受入、子チケットの調査、未マージ PR の統合、機能実装の完了を意味しない。

## 対象外

- この文書変更での runtime 実装、既存 PR のマージ、release 公開。
- 未マージ PR の一括承認、既存の umbrella Issue の一括 close。
- dsh を ecosystem 全機能の必須 PoC または単一 release blocker にすること。
- PWA の受入前提としての formal gpui iOS native host 完成。
- 公開 SaaS、Funnel、multi-tenant hosting、iPhone 内の workspace / shell 実行。
- Cordis/npm runtime や Node product host の再導入、外部サービスの利用制限の回避。

## 提案する方針

### 1. 維持する設計境界

1. MoonBit が command / event / effect、承認、provider protocol、認証・再同期の意味を所有する。native runtime が I/O と task lifetime を管理し、C / browser interop は狭い OS / browser primitive とする。
2. checkpoint 成功前に外部作用を開始しない。復元・再接続で結果不明の provider / tool を暗黙再実行しない。
3. Linux CI と keyless fixture を継続し、macOS Apple Silicon、iPhone、各実 IME は環境別の受入として記録する。
4. gpui / Yami-kumo は製品依存として維持する。hotpath / turtles / vlmkit / conformance を通常 install / build / run / archive の必須依存にしない。[PR #65](https://github.com/f4ah6o/dsh.mbt/pull/65) の既存境界検査・fresh consumer 検証案を再利用する。
5. 新しい外部 MoonBit library は既存の依存方針に従う。UI library の不具合は最小 fixture に縮約して担当 repository へ返す。
6. 不具合と MoonBit 記述上の改善候補は [PR #44](https://github.com/f4ah6o/dsh.mbt/pull/44) の台帳へ集約し、移植作業ごとに無関係な全面改修を混ぜない。重大な安全性・データ損失の不具合は延期しない。

### 2. 優先順位

| 優先 | 作業 | 完了を判断する根拠 | 追跡先 |
| --- | --- | --- | --- |
| P0 | 現在地・受入証拠・配布範囲を整合させる | 同じ SHA / tag / 環境に対する結果表。古い記録は日付付き履歴として保持 | 既存 0001–0003、docs、PR #34 / #50 / #65 |
| P1 | Mac / Linux host → iPhone PWA の主要利用経路を受入する | SIWC 推論 terminal、tool approval、端末切断中の host 継続、receipt 照合、重複作用なし | 既存 0002 / 0003 |
| P1 | 長い会話の context と storage 契約を確定する | trigger、保持、上限、保存失敗・復元時の採否と実装分割 | 長期会話の子チケット |
| P2 | background / resumable subagent の契約を確定する | 親子所有権、明示再開、checkpoint、承認失効、cancel、no-replay の状態表 | subagent の子チケット |
| 独立追跡 | OpenCode、desktop IME、導入 UX、開発 tool 境界 | 既存 PR / Issue ごとの証拠。主経路と相互の完了条件を混ぜない | 下表 |

順位は機能追加の提案順であり、受入環境がない間も AFK の契約調査は進められる。長期会話と subagent の調査は独立して開始できるため、不要な依存関係を付けない。実装時に共有 store schema が必要と判明した場合は、その時点で依存を追加する。

### 3. 実利用の受入は既存 Issue に集約する

[0002 SIWC](0002-chatgpt-subscription-siwc.md) と [0003 native / iOS / Tailnet](0003-moonbit-native-ios-tailnet-roadmap.md) を実行先とする。

1. 既存の実機成功記録を先に回収する。ログイン成功、account-visible model discovery、`response.completed`、tool approval、再起動後の選択保持を個別に判定する。repository の NOT RUN 記載は「一度も成功していない」ことの断定には使わない。
2. actual Tailscale Serve の identity / Host / Origin と拒否経路を確認した上で、iPhone Safari / Home Screen PWA から送信・承認・取消を確認する。credential は host 側だけに保持する。
3. lock / app kill / network 切替中も host の処理が継続し、復帰時に snapshot / event cursor / durable receipt から同期することを確認する。未確認 command を新 ID で自動再送しない。
4. 認証情報を含めず、source SHA、配布物、OS / browser、手順、観測結果、未実行箇所を保存する。既存 A01–A18 の各条件を再利用し、fixture 成功で実機 gate を埋めない。

### 4. 既存の作業を再利用する

| 追跡先 | この map での扱い |
| --- | --- |
| [0001 upstream parity](0001-upstream-parity.md) | 残る互換範囲の親 Issue。子調査の結果を受けて実装単位を切り出す |
| [PR #30](https://github.com/f4ah6o/dsh.mbt/pull/30) | orchestration / browser / permission / ACP 等の追記案。現 main と差分を照合して採否を判断 |
| [PR #34](https://github.com/f4ah6o/dsh.mbt/pull/34) | 2026-10-09 の再確認記録。現在地の証拠へ読み替えない |
| [PR #44](https://github.com/f4ah6o/dsh.mbt/pull/44) | upstream / MoonBit debt 台帳 |
| [PR #50](https://github.com/f4ah6o/dsh.mbt/pull/50) | help / 導入 / desktop 起動回復。後続実装で済んだ項目と残件を照合 |
| [PR #65](https://github.com/f4ah6o/dsh.mbt/pull/65) | hobby consumer と開発 tooling の境界。既存 validator を使う |
| [PR #66](https://github.com/f4ah6o/dsh.mbt/pull/66) | `DSH_AUTH=none` は open・未マージ。fixture / CI 成功と無料モデル実会話成功を区別 |
| [PR #67](https://github.com/f4ah6o/dsh.mbt/pull/67) | OpenCode server 調査。公式 server の実応答は dsh adapter の実動作証拠ではない |
| [0005 macOS IME](../polished/0005-macos-ime-composition.md)、[Wayland guide](../../docs/wayland-ime-composition.md) | dsh 実経路での変換・候補操作を受入。gpui 単体の証拠をそのまま転用しない |
| [PR #42](https://github.com/f4ah6o/dsh.mbt/pull/42) | 古い依存更新案を現在の開発 tool 分離方針と照合 |
| [PR #27](https://github.com/f4ah6o/dsh.mbt/pull/27) | release 自動化の既存案。main と配布版の対応確認に使用 |

OpenCode は LLM provider 接続と Agent Runtime Backend を分ける。#66 の no-auth wire 経路は汎用 provider 機能であり、#67 の session / tool / approval を持つ外部 runtime とは責務が異なる。#67 に記録された利用条件は調査当時の記録とし、adapter 着手時に現行条件と実 server 契約を確認する。認証なしへの暗黙 fallback やクライアント偽装は導入しない。

## 受け入れ条件

- [ ] main、未マージ PR、release、fixture、実アカウント、実端末の状態を別欄で追跡し、SHA / 日付 / 環境 / 根拠リンクがある。
- [ ] 既存 0001–0003 と重複する実装 Issue を追加せず、実装済み subset と残件を照合できる。
- [ ] SIWC / PWA の既存成功証拠を照合し、不足する受入を既存 0002 / 0003 に記録した。利用可能性の主張は観測範囲に限定される。
- [ ] context budget / storage と subagent 再開の子調査に結論・選択肢・後続影響が記録され、確定した範囲だけ通常の実装 Issue に分割した。
- [ ] README / guide / status / release notes の矛盾を解消する作業と、未実装機能の作業を区別した。
- [ ] 未確定領域、対象外、次に着手可能なチケットが明記され、機能の完了を map 作成だけで主張していない。

## テスト計画

1. 作成した Markdown に `local_issues.py validate`、相対リンクと参照先 tree の照合、`git diff --check` を実行する。
2. GitHub API で main / PR の SHA、Actions の status / conclusion、release tag を照合する。過去の成功は今回の再実行結果と区別する。
3. 実装開始時は変更範囲に応じて `npm test`、`moon run scripts/native-verify.mbtx --target native`、`python3 scripts/check-performance-boundary.py` を選ぶ。文書だけの作成時に runtime テストを実行済みと記載しない。
4. 実アカウント・Tailnet・iPhone・IME は既存受入手順を実行した対象だけ PASS / FAIL とし、環境や観測がない項目は未実行のまま残す。

## リスク

- 古い設計文書や open PR の提案を現在の実装として扱うと、移植済み機能を再実装する。
- 手動 pruning を保存容量削減と誤認すると、長期会話が既存上限へ到達する。
- 不確かな再開を自動化すると、provider 課金や tool / hook の外部作用が重複する。
- 実機・実アカウント・Tailnet の条件不足は受入のブロッカーとなるが、fixture 成功に置き換えない。
- 未マージ Issue に連番の重複がある。新規ファイルは既存 `issues/open/` 内の日付付き命名を用い、古い番号を再利用しない。

## 変更履歴

`CHANGES.md` impact: no

計画・調査の整理のみ。実装による利用者向け変更は後続 Issue / PR で判定する。

## 注記

### Wayfinder

- Role: map
- Parent map: none
- Type: map
- Mode: AFK（文書整理）。実機・実アカウントの受入は既存 Issue で HITL。
- Depends on: none

### Destination

現在の native 製品経路を実利用するための根拠と優先順位が整い、長期会話・再開可能実行について未確定の実装を推測せずに着手可能な Issue を選べる。

### Decisions so far

- Node product host の退役と native executable への一本化は完了済み。根拠は固定 SHA の README / architecture。
- Mac / Linux host、Tailnet 内接続、PWA 先行、host 側 credential 保持は [0003](0003-moonbit-native-ios-tailnet-roadmap.md) の既存方針を維持する。
- MCP / skills / hooks / LSP / ACP / foreground subagent の bounded 実装は基礎として再利用する。
- 本 map の優先順位は開発順序の提案。OpenCode 等の未マージ案の承認や無料枠の利用許可を意味しない。

### Not yet specified

- 長期会話調査の結果から決める summary / spill の具体的な保存形式と導入 increment。
- subagent 調査の結果から決める child store / job API / UI の具体的な契約と実装順序。
- #67 の現行利用条件と runtime 契約を確認した後の OpenCode adapter の実装範囲。
- PWA 受入で判明する差分を踏まえた正式 iOS native 経路の優先度と詳細。

### Out of scope

この map の対象外は「対象外」節のとおり。新たに rejected にしたチケットはなし。

### Tickets

- [ ] [長い会話の context budget と保存容量の契約を確定する](20261030-long-session-budget-and-storage-contract.md) — research / AFK / depends on: none / P1
- [ ] [subagent の永続化・明示再開・親子所有権の契約を確定する](20261030-subagent-resume-ownership-contract.md) — research / AFK / depends on: none / P2

### Frontier と既存作業

新規チケットの frontier は上記 2 件。優先順位は記載順とする。SIWC と PWA の受入は既存 0002 / 0003 を再利用し、実機・実アカウント・Tailnet の用意と既存証拠の照合が必要な HITL 作業として並行管理する。別セッションが着手する前に状態と claim を再確認する。

### 2026-10-30 progress after main baseline

受入文書の比較対象は main `8e7ec94e2436edf0db961659130c0390122fd38c`。PR #76 の head は
`87042bb70af9fa5f9b64e4b82ef53cf4a227c5c6` で、以下の PR は GitHub 上で **OPEN / unmerged**
として確認した。head SHA は `gh pr view` の `headRefOid`。これらの提案を baseline main の機能や
実利用の証拠には数えない。

| PR / exact head SHA | 進捗と主な制限 |
| --- | --- |
| [#77](https://github.com/f4ah6o/dsh.mbt/pull/77) `f4ba131c84460fd9af04908bbcca882c599fd7a4` | 新しい turn 前の opt-in tool-result pruning。default off で、summary / spill / storage capacity は増やさない。post-rename unknown commit は未検証。 |
| [#78](https://github.com/f4ah6o/dsh.mbt/pull/78) `fe181ea431ebdc147c3afe5c584d8a1531024df0` | read-only capacity accounting。headroom は admission guarantee ではなく、長期保存容量も増やさない。 |
| [#79](https://github.com/f4ah6o/dsh.mbt/pull/79) `e1511dac76ee29165a939a78bdadda2b6d043ff0` | batched session replay validation。初回 Wayland UI failure は同じ head の rerun で pass、原因は未確定。長期会話機能の追加ではない。 |
| [#80](https://github.com/f4ah6o/dsh.mbt/pull/80) `6dc667358f5c05a0416f87d0b6266c535e14419a` | pending tool effect owner predicate。durable child storage / background / resume の caller はない。 |
| [#81](https://github.com/f4ah6o/dsh.mbt/pull/81) `d210374c378baa4bdc3c0de60b3f9d76ed0195f8` | bounded atomic create primitive。archive や child audit の integration ではなく、power-loss / macOS acceptance は未実施。 |
| [#82](https://github.com/f4ah6o/dsh.mbt/pull/82) `fcffd7f453a0eedd055402fccdee6e610fca4938` | eligible pruned Read の read-only preflight。object storage、replay integration、容量増加は含まない。 |
| [#83](https://github.com/f4ah6o/dsh.mbt/pull/83) `e1dface0f997b0951768d0e2f041a5eaf74652c2` | bounded archive object codec。実ファイル保存、raw stored-byte validation、v2 replay は未実装。 |
| [#84](https://github.com/f4ah6o/dsh.mbt/pull/84) `9777af34c4c8c21c5734ca468e513578c44b6655` | bounded byte-preserving SafeRoot read。archive storage や deterministic read-race coverage は含まない。 |
| [#85](https://github.com/f4ah6o/dsh.mbt/pull/85) `169de36cf0419e02f764454f337c997f29dd336a` | engine-only v2 archive candidate / commit / verified restore。native object store、manifest / receipt transaction、history API、web / ACP は未実装。 |
| [#86](https://github.com/f4ah6o/dsh.mbt/pull/86) `a64a335c25f9c5ae797f12a2d2c6c1b3c602ed5b` | command receipt を owner + ID で scope。過去に上書きされた receipt は復元しない。 |
| [#87](https://github.com/f4ah6o/dsh.mbt/pull/87) `76c5cd8d48e36e7bcbe36cd4435ba7f115fc17f5` | eligible regular Read result の手動 durable archive。一般 compaction ではない。旧 head の Linux fixture 失敗は修正し新 head の CI は進行中。旧 head の Windows smoke で CLI の承認 event 欠落が見つかり修正中。power-loss は未検証。 |

PR #77–#87 は長い会話や保存の候補を進めているが、main の実利用 gate とは独立する。
レビュー時は個別 PR の dependency / base を保ち、stack 全体を main の完了として数えない。
実 SIWC、Tailscale Serve、iPhone gate は[0002](0002-chatgpt-subscription-siwc.md)と
[0003](0003-moonbit-native-ios-tailnet-roadmap.md)に記録し、fixture と実アカウント / 実機の結果を分ける。
