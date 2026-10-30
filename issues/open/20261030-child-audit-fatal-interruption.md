# 子監査の fatal 結果で親 turn を中断する内部 primitive

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-subagent-audit-interrupt

## 概要

完了済み child の監査公開が fatal になった場合に備え、exact live parent tool effect だけを中断し、取消・settlement が先に成立した状態は保つ Engine/API primitive を追加する。

## 背景

- [PR #80](https://github.com/f4ah6o/dsh.mbt/pull/80) は pending tool effect の exact owner query を追加した。
- [PR #92](https://github.com/f4ah6o/dsh.mbt/pull/92) は opt-in child audit publication の契約を定め、save failure 後に通常の parent tool result と hook/provider continuation を進めないこと、親取消が先なら terminal state を維持することを要求する。
- publication を成功したかのように tool error として settle すると、child provider/tool/hook work を暗黙に繰り返す危険がある。

## 問題

owner query だけでは cancellation、known tool outcome、completion との競合に対して原子的な fatal transition を実装できない。running status だけを再確認して `session/interrupted` と terminal events を追加すると、すでに取消・settlement された turn に重複イベントを書き、restore 不能な履歴を作る可能性がある。

## 目標

- exact `(effect_id, session_id, call_id)` の live tool effect のみを中断する。
- Engine が owned pending effect、open step、`Dispatched` call stage と effect identity を再確認し、known outcome を上書きしない。
- Engine/API の typed operation は wire operation にせず、既存の通常実行経路から呼ばれない。
- 中断 transition が先に採用された場合は Failed / `interrupted` を一度だけ記録する。取消・完了・known outcome が先なら Engine state を変更しない。
- provider、tool、hook を再実行せず、effect queue を再生成しない。

## 対象外

child audit の opt-in option、codec、ファイル保存、quota、orphan の列挙や cleanup、NativeRuntime の gate/checkpoint wrapper、`run_subagent_tool` の fatal-result propagation、save outcome injection、background child、resume、provider/tool/hook replay、親結果 adoption は対象外。既定の foreground 実行経路は変更しない。

## 提案する方針

Engine に非 wire の typed operation を追加し、exact pending tool identity と `Dispatched` stage を candidate state 上で確認する。確認できた場合のみ `session/interrupted` を記録して既存 terminate closure を使い、Failed status、`turn/end(reason=interrupted)`、`tool/completed(source=interrupted)` / `tool/result` を記録する。lost ownership、settled effect、known outcome は `false` として候補を破棄する。Engine capacity と event limit を超える候補も採用しない。

HarnessApi はこの operation を typed in-process method としてのみ公開し、capability manifest や JSON / MCP operation には追加しない。この increment は caller を追加しないため、default foreground behavior と checkpoint semantics は変わらない。後続の NativeRuntime integration は stopped/closed と control cancellation を確認し、runtime `gate` 内で API ownership を再検証してこの operation を呼び、成功結果を checkpoint する必要がある。

## 受け入れ条件

- [ ] provider effect、異なる session/call/effect、settled effect は中断されない。
- [ ] `record_effect_outcome` 後の `OutcomeKnown` call は中断されず、known outcome を保持する。
- [ ] 正しい pending dispatched tool effect は一度だけ Failed / interrupted となり、source `interrupted` の tool completion を記録して effect を retire する。
- [ ] cancellation/terminal settlement が先なら Engine operation は no-op となり、`session/interrupted` や二重 terminal events を追加しない。
- [ ] Engine restore で終端状態が復元され、provider/tool effect が再出力されない。
- [ ] 新しい操作は capability/wire API に現れず、child audit publication や background/resume 対応を主張しない。

## テスト計画

- Engine typed tests で正しい owner、owner mismatch、provider effect mismatch、cancellation-first、known-outcome-first、exactly-once events と restore を確認する。
- API test で内部 typed boundary、wire manifest 不在、重複呼び出しの no-op を確認する。
- focused Engine/API tests で両 winner order、terminal event exactly-once、restore/no effects、wire manifest 不在を確認する。
- focused engine/api native tests、`moon check`、format/diff check、local issue validator を実施する。

## リスク

親 tool result と child audit file の atomic commit はこの increment では扱わない。実際の publication caller が fatal outcome を既存の `finish_tool_effect` に流さず、cancel/settlement を runtime `gate` 内で再確認して checkpoint する配線は後続作業で必要となる。そこでは checkpoint failure の uncertain result と no-replay behavior も検証する。#89 codec、#81 atomic create、#91 metadata と #92 publication contract は後続の完全な opt-in publication に必要だが、この Engine/API primitive 自体はファイルを読み書きしない。

## 変更履歴

`CHANGES.md` impact: no

内部の terminal transition とテストのみ。利用者向けの default behavior は変えない。

## 注記

この issue と実装は fatal interruption primitive のみを扱う。子監査の publication、background execution、resume、replay、親結果採用は未実装であり、サポートを示さない。
