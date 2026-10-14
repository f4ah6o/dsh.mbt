# 0001: DeepSeek Harness の残りの機能を MoonBit へ移植する

Status: open
Model: gpt-6-luna
Created: 2026-10-05
Updated: 2026-10-14
Branch: feat/20261014-hook-substitution
upstream baseline は `5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

## 概要

DeepSeek Harness の残る session、provider、extension、UI、host 機能を MoonBit native runtime へ段階的に移植し、upstream baseline との差分を記録します。現在の範囲と確認済み acceptance は[移植状況](../../docs/port-status.md)を参照してください。

## 背景

upstream は複数 TypeScript package と Cordis lifecycle で構成されています。この repository は MoonBit engine / native host に製品実行経路を移し、upstream 互換が確認された細分化 scope だけを bounded subset として提供しています。

## 問題

多くの upstream event と native v1 feature に部分対応がありますが、完全な lifecycle parity、長い会話の compaction、Cordis extension runtime、background jobs、provider/media capabilities、host sandbox は未実装です。partial implementation を全体互換と誤って受け取られないよう、受け入れ範囲と移行条件を明示する必要があります。

## 目標

- upstream baseline の event、provider、tool、extension、host semantics を調査し、native MoonBit implementation と tests に反映する。
- 各 increment の制限、recovery、security boundary、compatibility requirements を docs と release notes に記録する。
- broad parity issue を open のまま維持し、完了条件のない範囲を完了扱いしない。

## 対象外

- upstream TypeScript / Cordis plugin ABI を MoonBit implementation と同等扱いにすること。
- 実 provider credentials を一般 regression tests に使うこと。
- 部分実装を full upstream parity と表現すること。

## 提案する方針

各 increment は pinned upstream source を参照し、native runtime の policy / persistence / no-replay boundary を定義してから、keyless fixture と user-facing migration notes を追加します。実装済みの bounded subset は本 issue を閉じず、残る upstream lifecycle を別途追跡します。

## 受け入れ条件

- native behaviour と upstream difference が同じ increment の tests / docs / changelog に記録される。
- cancellation / interruption / restore を含む external-effect boundary が検証される。
- この umbrella issue は対象の parity work がすべて終わるまで open のままにする。

## テスト計画

Keyless engine / provider / native runtime fixtures を優先し、必要な CLI / browser / ACP / desktop surface を回帰確認します。Live account tests は、認証情報をログに含めず明示的に実施した場合だけ別途記録します。

## リスク

Bounded native subset と upstream package の名称が近いため、互換範囲を過大に解釈される可能性があります。各機能の上限、trusted host code、restore / replay behaviour、unsupported lifecycle を明記して緩和します。

## 変更履歴

- 2026-10-10: pinned [`hooks-claude-code/index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts) の PostToolUse `additionalContext` を bounded native path に追加。matching hooks の text block を per-call `user/message` として保存し、[`core/tools/index.ts:1781`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/tools/src/index.ts#L1781) / [`agent-loop/tool-calls.ts:147`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/tool-calls.ts#L147) の consumer ordering に沿って parallel tool results 後、tool-call order で provider へ渡す。empty / whitespace、exit 2、block + context、Unicode / per-item / aggregate limits、no-match、cancel-after-known-outcome、receipt replay / reopen を keyless tests で確認。local transcript は `フック補足` として表示し、ACP text update は source-aware update がないため省略する。wrong-type の strict rejection、native block result shape、ACP omission を差分として記録し、issue は open のまま。
- 2026-10-10: pinned [`hooks-claude-code/index.ts:223-240`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L240)、[`config.ts:109-112`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/config.ts#L109-L112)、[`hook-protocol/codec.ts:59-88`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts#L59-L88)、[`merge.ts:62-99`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts#L62-L99) の UserPromptSubmit semantics を参照し、native `run` / `web` / `mcp` / `acp` / `desktop` に追加。valid user `session_send` ごとに一度だけ provider admission 前に command を実行し、matcher 無視、exit 2 / `block` / event-specific `deny`、lenient output parsing、bounded `additionalContext` を実装。context は upstream と同じ一つの source-tagged user message に hook 順で grouped 保存し、prompt 後 / provider request 前に置く。remote receipt replay は hook を再実行せず、interruption は unsettled reservation を uncertain として復元する。`index.ts:195` の `continue:false` は upstream 自身が run-level halt 未実装と記録している。`index.ts:181-185` の `updatedInput` / `systemMessage` も bridge 側で ignored。codec、pre-admission / forged-context stripping / replay / cancellation の keyless test source を追加した。Final verification at PR #46 head `982f2b6f4b5fd364ebf0500a032bb210b753db9a`: local native format and typecheck pass with zero errors and four pinned `vendor/hotpath` warnings. Browser/service-worker asset regeneration passed during candidate work, though its exact local source head was not recorded; final-head browser build is covered by hosted CI. The package preview passed on source snapshot `76d18938ce173f28f797e073411f77c039d8bec8`; its 905-entry / 3,019,163-byte size is not a final-head size claim. Local focused native behavior tests could not complete because compilation hit local-volume `ENOSPC`. Hosted [native/browser CI run 38043639573](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639573) passed: portable Wasm, Wasm GC, JS, and native each 163 / 163; app 17 / 17; native runtime 156 / 156; browser modules 7 / 7; no-Node native 329 / 329; Chromium smoke and ACP stdio passed. Hosted [three-platform asset workflow 38043639550](https://github.com/f4ah6o/dsh.mbt/actions/runs/38043639550) passed macOS arm64, Linux x86_64, and Linux arm64 packaging and smoke checks. The initial no-Node fixture failure at [38042285182](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042285182) was a transcript projection mismatch, not a production defect; the filtered engine result did not isolate a persistence-restore failure. The next 325 / 328 run at [38042930510](https://github.com/f4ah6o/dsh.mbt/actions/runs/38042930510) exposed cancellation classification and prompt-matcher test issues fixed and covered at the final head. Other upstream lifecycle and compatibility increments remain open.
- 2026-10-10: pinned upstream ACP model control を参照し、persistent per-session `model` option、bounded `DSH_ACP_MODELS` catalog、busy-turn refusal、retry / subagent inheritance、route / catalog reopen fencing を追加。upstream の `session/load` 非実装も確認し、load はこの差分に含めない。本 issue は open のまま。
- 2026-10-10: Native ACP fatal-path defect: `runtime/main.mbt` used `abort` after ACP argument/startup/carrier/shutdown failures, and the native panic diagnostic could be written to stdout, corrupting JSON-RPC framing. Fixed with bounded stderr diagnostics and nonzero exit; checkpoint conflict stdio regression verifies an RPC error, no config update/effect, later request fencing, and JSON-only stdout through EOF. This is a native carrier issue, not an upstream parity defect.
- 2026-10-10: ACP v1 persistent list / resume slice を追加し、workspace provenance、pagination、restart continuation、no-replay と multi-workspace / MCP 差分を記録。
- 2026-10-10: bounded foreground subagent slice とその recovery / hook limits を section 3 に追加。upstream subagent lifecycle parity は未完了。
- 2026-10-11: pinned [hooks-claude-code/index.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts)、[hook-protocol/codec.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts)、[hook-protocol/merge.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts)、[core/agent-loop/agent.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts) の Stop lifecycle を参照し、native shared runtime の command Stop slice を追加。terminal result の durable checkpoint 後に matcher を無視して hook を実行し、deny は source-tagged user steer と同一 turn の continuation へつなぐ。continuation 前の UserPromptSubmit、winner-rank の reason merge、exit-2 denial、sticky max-token completion、checkpoint / restore no-replay、process cancellation を keyless fixtures で確認した。Native host の max-step bound、UTF-16 aggregate reason / session capacity、blocked-status mapping は仕様差として記録。ordinary tool-result-only follow-up の UserPromptSubmit は次の source correction を参照する。foreground child Stop は parent dispatcher ではなく child Engine で dispatch する。Stop payload の empty transcript path / false active marker と、pinned bridge でも適用しない additional controls を維持し、本 umbrella issue は open のまま。
- 2026-10-11: source audit corrected the ordinary tool-follow-up hook assessment. Pinned [`agent.ts:267-289`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L267-L289) runs `agent/pre-step` each step, but [`hooks-claude-code/index.ts:223-226`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L226) returns immediately when claimed inbox messages are empty. Ordinary tool-result-only steps therefore skip UserPromptSubmit upstream too; a Stop denial has a steered inbox message and does run it. Native child lifecycle coverage now runs UserPromptSubmit for the first child prompt and Stop after accepted terminal child provider outcomes, with child-owned checkpoint/continuation APIs, deadline and parent cancellation ownership. No durable child schema was added; the parent unsettled tool result remains the no-replay boundary. Regression evidence is recorded with this increment. The umbrella issue remains open.

- 2026-10-11: pinned [`hooks-claude-code/index.ts:285-301`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L285-L301), [`index.ts:305-365`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L305-L365), [`hook-protocol/codec.ts:59-88`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts#L59-L88), [`agent-loop/agent.ts:171-173,358-364`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L171-L173), and [`subagent/lifecycle.ts:134-162`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/subagent/subagent/src/lifecycle.ts#L134-L162) to add native `SubagentStart` / `SubagentStop` command hooks. Both use the literal `general-purpose` matcher and source-compatible payload fields; Start ignores decisions and queues only successful matching `additionalContext`, without mutating an in-flight request, while Stop is observational. The child-only context inbox is bounded, absent from persisted snapshots and wire commands, and consumed into source-tagged Engine messages; restore and no-replay checks cover the additive `hook/subagent-start-context` event. Native Start callbacks are canceled/drained at child settlement, and Stop has one protected aggregate 1-second grace after the child drive outcome; the pinned bridge instead retains detached tasks until bridge disposal. A frozen-head regression exposed that placing Stop inside the drive timeout could relabel a completed child as timed out; the fix and a slow-Stop regression keep cleanup outside that deadline. Cleanup can delay the parent tool result but cannot change the child outcome. These are explicit native lifetime bounds, not upstream contracts. Keyless lifecycle, cancellation, timeout, matcher, provider-failure, and restore tests were added. The umbrella issue remains open.

- 2026-10-11: pinned [`agent.ts:171-173,358-382`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L171-L173) and [`hooks-claude-code/index.ts:223-239`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L239) show that a nonempty next-step inbox, including PostToolUse `additionalContext`, reaches UserPromptSubmit, while an empty tool-result-only inbox skips the command hook. Native 0.1.17 now claims each nonempty PostToolUse batch at the next root or child provider boundary, after committing correlated tool results. Accepted history preserves PostToolUse tool-call order and appends UserPromptSubmit context afterward; child SubagentStart context stays earlier in the same batch. The combined 32-item / 16,384 UTF-16-unit context bound includes child Start contexts and prompt-hook output. Denial or overflow leaves known tool results intact without admitting rejected context or starting another provider request; cancellation and restore abandon unresolved admission without replaying the hook or provider. Additive root / child admission markers and the optional `post_tool_prompt_hook` (root) and `subagent_post_tool_prompt_hook` (child) fields on effect-backed `tool/completed` events are validated on restore. The child field is true-only, effect-only, and mutually exclusive with the root field; it restores deferred child admission before an interrupted completion batch is closed. Version 0.1.17 also reads legacy tool-completion events without either optional field. See [tool completion staging](../../engine/tool_calls.mbt), [root admission](../../engine/post_tool_prompt_hooks.mbt), [child admission](../../engine/subagent_hooks.mbt), [snapshot validation](../../engine/persistence.mbt), and [bounded denial handling](../../runtime/runtime.mbt). The umbrella issue remains open.
- 2026-10-12: pinned [`hooks-claude-code/index.ts:209-220,338-340`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L209-L220), [`index.ts:223-240`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L240), [`agent-loop/inbox.ts:109-113`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/inbox.ts#L109-L113), and [`agent-loop/agent.ts:267-285,316-320`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L267-L285) to add a bounded native SessionStart command-hook slice. Upstream awaits the hook during agent publication: create / child creation uses `startup`, restore uses `resume`, and the `clear` / `compact` source variants have no emitter in the pinned create/resume paths. The listener applies only `additionalContext`, uses an empty transcript path, and emits no invocation/result pair. It ignores decisions, `continue`, `systemMessage`, and `updatedInput`. The agent claims queued SessionStart context before UserPromptSubmit; the payload flattens context text directly before the prompt with no separator, and a denied prompt drops the claimed context without requeue or SessionStart retry. Native root timing is an adapter difference: activation is lazy at the first preflight-valid, non-replay `session_send`, with restored sessions marked `resume`; child SessionStart runs as `startup` before SubagentStart and the initial prompt under one aggregate child deadline. If caller cancellation wins after a successful root hook but before prompt admission, nonempty unclaimed context is held only in a process-local inbox capped at 64 session batches; a full inbox rejects another session's send before dispatching its hook. Closing/reopening the runtime discards unclaimed context, and receipt replay / restore never rerun the hook. Native history reuses the existing `hook/subagent-start-context` count/length marker for both child Start and root SessionStart, followed by the source-tagged context message; no new snapshot schema was added. The marker/batch format is supported by the dsh 0.1.16 reader according to a static source audit, and the unchanged 0.1.17 reader logic plus current probes accept it; no 0.1.16 binary was run. This does not guarantee downgrade safety for a whole store, since other persisted content (including 0.1.17 PostToolUse boundaries) can require a newer reader. A fresh frozen review found context overflow initially skipped later matching command side effects; `f771809` now runs all matching commands sequentially, then drops the whole context batch if the native count/UTF-16 cap is exceeded. Keyless fixtures cover startup and resume payloads, source order, prompt-denial drop/retry, receipt replay, child deadline, and per-item / aggregate overflow. The umbrella issue remains open.

- 2026-10-12: pinned [`hook-protocol/events.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/events.ts), [`types.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/types.ts), [`runner.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/runner.ts), [`codec.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts), and the [Claude bridge](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts) to add durable native `hook/invoked` / `hook/result` events. Turn-scoped UserPromptSubmit, PreToolUse, PostToolUse, and Stop commands checkpoint invocation before spawn and store the decoded decision, optional observed exit code, bounded stderr summary, and duration on completion; command text, stdin, and full stdout are omitted. Correlation uses turn, point, and handler ID. Cancellation can leave an unresolved invocation, restore does not rerun it, and ordinary terminal turn closure rejects a missing result. The bounded native adapter omits UserPromptSubmit pairs for every direct root `session_send`/new-turn admission and for each child initial prompt; those run before turn admission. In-turn root / child prompt hooks on continuations are traced. Child diagnostics stay in the transient child Engine instead of the parent snapshot. The stderr cap keeps valid Unicode scalar boundaries where JavaScript UTF-16 slicing can emit an isolated surrogate. Snapshots with new events require dsh 0.1.19+, while 0.1.19 reads legacy snapshots without diagnostics. Engine/runtime keyless tests cover completed, blocked, timed-out, interrupted, restored, overflow, privacy, and multi-command correlation paths; a fresh native worker passed the 181-test runtime suite and ACP stdio integration. The umbrella issue remains open.
- 2026-10-12: pinned [`hooks-codex/src/index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-codex/src/index.ts), [`hooks-codex/src/config.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-codex/src/config.ts), and [`hook-protocol/codec.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts) to add a native Codex command-hook dialect selected by `--hooks-dialect codex`. It covers SessionStart, PreToolUse, PostToolUse, UserPromptSubmit, and Stop; the Claude Code dialect remains the default. The adapter preserves null `transcript_path`, `permission_mode: default`, process-static model, decimal string turn IDs, no-newline JSON input, Stop’s null last message / inactive marker, and the source’s intentionally shell-only tool-input projection. It applies only blocking decisions and the supported SessionStart / PostToolUse / UserPromptSubmit context outputs. Its bounded ASCII regex subset rejects unsupported patterns instead of changing their meaning; native timeout is 10 seconds by default and capped at 120 seconds, while pinned JS RegExp and longer waits remain a parity gap. Root SessionStart activation is lazy on the first valid non-replay send rather than agent publication. A single selected dialect applies to the runtime, and Codex SubagentStart / SubagentStop events are not included. Context provenance and turn-scoped diagnostics survive root/child admission, provider routes, restore and fork; unknown provenance and externally forged source tags are rejected. Frozen probes found and fixed lost structured SessionStart context, nested reason fallback precedence, unrestorable Codex Stop continuation, and provider rejection of trusted Codex context. Keyless runtime, provider, lifecycle, cancellation, restore/fork and real HTTP worker fixtures cover the accepted paths; the feature remains partial and this umbrella issue stays open.

- 2026-10-14: pinned [`hooks-claude-code/config.ts:36-60,78-105`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/config.ts#L36-L60) and [`index.ts:60-71,107-115,151-157`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L60-L71) to add Claude Code command substitutions via `--hooks-plugin-root` / `--hooks-project-dir` and matching `NativeRuntime::open` / `NativeDesktop::open` parameters. All occurrences are replaced at config parse time, plugin root first and project directory second; unset tokens remain verbatim, and an explicit empty value remains set. Project override also sets `CLAUDE_PROJECT_DIR`, while command cwd stays the workspace. Values remain raw shell text with no quoting; overrides require Claude dialect and hooks config. Native option values cap at 4,096 characters and expanded commands at 8,192. The process-static config/manual dispatch and Json/String interfaces remain in place; upstream per-session hook discovery remains a TODO. A pre-freeze static allocation audit found that project expansion could build a very large intermediate from bounded raw values; native code now counts split pieces and rejects an over-limit result before joining, with a repeated nested-token probe. This is native hardening evidence, not an upstream defect. The umbrella issue remains open.

## 注記

- 2026-10-10: This is a broad parity tracker; individual bounded increments do not change its open status.

## 1. Session v4 と replay

upstream JSONL を version ごとに厳密に decode し、イベントの意味を MoonBit 型へ移す。
未知の event、attachment、interruption を黙って捨てない。v4 のまま保存するか、明示的な importer として独自 schema へ移すかを仕様に記録する。

部分対応: `session_import` は Session v4 native JSONL と upstream snapshot shorthand の限定 event subset を検証し、
元の raw lines を保持した read-only projection を作る。対応 event / 拒否する event は
[移植状況](../../docs/port-status.md) に記載する。2026-10-06 の increment では developer tool/header 更新、
current-position surface replacement、限定的な compaction checkpoint / pruning、診断用 assistant attempt を追加した。
2026-10-07 の increment では unmodified upstream catalog 25 件すべてを fixture と regression に追加し、import / reopen
後の raw source、transcript と call correlation を確認する。追加した image reference、skill provenance、mod append、
PTC / subagent / foreground workflow lifecycle は inert projection metadata に限り、background workflow、実行、nested fork、
spill/offload は引き続き拒否または未実装。2026-10-07 の retry import increment では native / shorthand の
`llm/retry` と `llm/retry-started` を strict schema と turn/step/provider/policy/attempt correlation で検証し、raw history に保持します。
retry delay や failure metadata も保存しますが、imported retry は待機も provider request も行いません。通常の v1
runtime には別途、限定的な provider retry lifecycle を追加しました。import history は
再開しない。v0–v3 migration、v4 writer、catalog 外の全 event semantics は引き続き本 issue の対象。

Native v1 runtime fork の部分対応（2026-10-07）: `session_fork` は idle / completed / failed / cancelled の settled な
非 imported session から新しい idle child を作り、履歴を保ったまま effect ID と retry ID を branch-local に再採番します。
approval / pending retry / active tool/provider work は受け付けず、fork や restore から external effect は発行しません。
`session/forked` marker は parent ID、固定 event prefix、source status / turn / step、effect map を保存します。
restore は全 session の adoption 前に親 prefix、creation settings、effect/retry metadata、missing parent、lineage cycle を
検証するため、親が後から続行しても既存 child は当時の prefix に結び付いたままです。fork-of-fork、fork後の tool-result pruning、
interrupted history、Node/native CLI、browser selection race、native durable command receipt replay を keyless test で確認します。
新機能は native v1 の settled runtime fork であり、Session v4 importer の seeded-fork subset を拡張せず、v4 writer / arbitrary
upstream branch semantics は実装しません。本 issue は open のままです。

受入条件:

- upstream の snapshot fixture を変更せずに読み、user / assistant / tool と相関情報を再構築する。
- branch / fork、inbox、複数 turn、failed / cancelled / interrupted の fixture を追加する。
- import と reopen で外部作用が発生しない。
- 現在の `dsh.mbt-session-v1` 履歴も明示的な migration で読み続けられる。

## 2. 長い会話と stream projection

Live compaction、tool result pruning、spill を導入し、262,144-unit 上限に依存しない長い会話を支える。
provider SSE の delta を engine event と UI に逐次反映し、切断時の未完了 tool を実行しない。

部分対応（2026-10-07）: OpenAI-compatible / DeepSeek Messages の検証済み text・reasoning delta を host が bounded batch で
`assistant/stream_delta` event に checkpoint し、browser と gpui scene は writing / partial として表示します。
final message は同じ provisional row を置き換え、次の provider context には provisional text を含めません。
effect・turn・step の照合、final text の一致検証、cancel / EOF failure / reopen 後の partial 保持、incomplete tool の不実行を
keyless regression で確認しています。provider parser は任意 chunk / UTF-8 境界を検証します。Session v1 の
262,144-unit 上限は維持され、拒否時は追加 batch を適用せず provider を止めます。live compaction と spill/offload は
未実装なので、長い会話の capacity limit は残ります。本 issue は open のままです。

retry の部分対応（2026-10-07）: 通常の v1 runtime は transient provider failure の bounded retry を実装します。
MoonBit が同じ active effect の `llm/retry` schedule と `llm/retry-started` を検証・記録し、host は各 checkpoint の成功後だけ
wait と次の provider request を始めます。既定は最大 5 retries、deterministic 500 ms exponential backoff、10 秒上限です。
対象は empty response、408/429/5xx、timeout、識別済み transport failure。accepted stream delta 後、auth、HTTP 408 / 429 以外の 4xx、
malformed response は再試行せず、Retry-After が上限を超える場合も retry しません。request body の同一性、ツールの重複実行なし、
backoff cancellation、start checkpoint failure、restore no-replay を keyless integration で確認しています。
upstream の jitter / `always` runtime mode / retry policy keying は未実装です。v4 retry event import は schema / history
validation のみで runtime replay ではありません。compaction、spill と
retry 可能な長い conversation を追加する設計・受入条件は残ります。

manual tool-result pruning の部分対応（2026-10-07）: pinned
[compaction-tool-result-pruner](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/compaction/compaction-tool-result-pruner)
の head / marker / tail policy を native v1 runtime に移し、idle / completed session 向けの
`session_prune_tool_results`、`prune-session` CLI、browser の **Trim outputs** を追加しました。
既定値は threshold 8,192、head 4,096、tail 1,024 Unicode code points です。projection は durable pruning event として保存し、
restore は source/result sequence、call identity、budgets、counts、projected content を再検証します。
元の `tool/result` と transcript は変更せず、次の provider context だけを projection します。imported / active session は拒否します。
keyless provider integration は 10,000-character parallel Read outputs が実 request で縮むこと、call order、reopen 後の同じ projection、
tool の no-replay を確認します。Browser smoke は同一 selection と遅延した prune response / session switch を確認します。

これは明示的な手動操作であり、token meter、pressure trigger、summary generation、自動 live compaction、spill は含みません。
pruning event 自体が保存量を増やすため、262,144 UTF-16 code unit の canonical session limit は維持されます。従って長い会話を
この上限を越えて継続する要件や capacity increase は満たしていません。本 issue 全体は open のままです。

受入条件:

- 旧上限を超える複数 turn の会話が継続し、縮約前後の履歴が説明可能である。
- arbitrary chunk / Unicode / EOF / cancel の途中状態を再現する。
- retry の回数、理由、重複実行防止を durable event として追跡する。

## 3. 拡張機能と tool 統合

MoonBit の typed service / lifetime を定義して、startup metadata から動的な拡張境界へ進める。
External MCP client、workspace skills、native command hook、ACP、LSP navigation、foreground subagent の bounded subset は実装済み。各 upstream 機能との差分を維持し、追加 hook event と LSP 対応範囲を整理する。
Cordis / npm plugin をそのまま動かす場合は別の互換 host を設計し、MoonBit-only plugin とは区別する。

部分対応（2026-10-07）: `effect: "read"` に静的分類した連続 tool call は最大 4 件の rolling pool で並列実行し、
各 `tool/request` の checkpoint 後に host IO を始めます。out-of-order completion は call / effect ID とともに durable staging し、
`tool/result` と次の model context は call 順を保ちます。Write / Shell、unknown tool、schema-invalid call は先行 read group を drain する barrier
です。cancel / restore は新しい work の dispatch を止め、既知の成功を保持し、unknown outcome を再生しません。pinned upstream
parallel-tool-calls fixture の keyless runtime 経路と、pool refill、barrier、approval、cancel、capacity、reopen を検証します。
upstream default pool size 10 ではなく 4 に制限し、dynamic safety classification、parallel write / shell、full upstream tool policy は
引き続き未実装です。本 issue 全体は open のままです。

workspace skill の部分対応（2026-10-09）: pinned upstream の `skill`, `skill-filesystem`,
`tool-skill` を元に、native runtime の `--enable-skills` と repeatable `--skill-dir PATH`、
workspace 内 `.dsh/skills` / `.agents/skills` / custom roots の決定的な discovery、bounded
frontmatter、model / user invocation controls、provider tool schema の static summary catalog、
read-only `skill` loader を追加しました。ユーザーの `/name` は user-invocable skill の本文と
provenance marker を user message に追加し、checkpoint 後に provider effect を返します。tool body と
source は result に含まれ、restore 時に同じ `skill` tool が無ければ engine validation が store を拒否します。
ordinary store は skill tool を有効にして開けます。symlink と protected runtime store を避け、body / result /
catalog の各上限を適用し、rename / policy change / disappearance を再読込時に再検証します。

これは upstream と同じ機能面全体ではありません。user-home / bundled / URL roots、file watcher、live catalog
replacement と durable catalog message、runtime skill registry、full YAML / arbitrary metadata、resource loader、
Cordis / npm code は含みません。catalog は起動時の provider tool description です。skill を含む store の
reopen には `--enable-skills` が必要で、同じ custom roots を指定して継続利用してください。upstream の
dynamic scoped registry / lifecycle semantics は引き続き未実装で、本 issue は open のままです。

native command hooks の初回対応（2026-10-09）: pinned upstream `hooks` と
`hooks-claude-code` を参照し、native `run` / `web` / `mcp` / `desktop` に明示的な
`--hooks-config PATH` を追加しました。初回範囲は `PreToolUse` / `PostToolUse` の command hooks、
literal exact matcher / `|` alternatives / `*`、JSON stdin、64 KiB config / stdin、各出力 16 KiB、
1–120 秒 timeout、process-group cancellation cleanup です。PreToolUse は engine の必要な approval 後に
実行され、hook の `allow` は approval を迂回しません。exit 2 と対応する `block` / `deny` は拒否し、
PostToolUse が拒否しても実行済み write / remote call は巻き戻しません。

PostToolUse に一致する tool は host outcome を `effect-known` source の durable event として hook の前に
checkpoint します。cancel / restore は既知の結果を順序通り settle し、external tool や hook を再実行しません。
通常の no-hook / no-match tool 経路には追加 event を書きません。keyless integration は explicit approval、
pre-denial、successful post-hook reopen、post-cancel と uncertain receipt replay / reopen、並列 read の結果順、
overflow / timeout / explicit cancellation を検証します。

これは upstream 互換全体ではありません。regex / partial wildcard、その他 event、async hooks と UserPromptSubmit command 以外の prompt hook types、
`ask` による新しい approval prompt、`additionalContext` 以外の feedback、`${CLAUDE_PLUGIN_ROOT}`、
hook-specific diagnostic event は未対応です。PostToolUse `additionalContext` は 2026-10-10 に bounded native path へ追加し、
per-call structured user message として全 correlated tool result 後に保存します。config / structured result は厳密に検証し、1–120 秒を上限とします。
hook command は設定した利用者の trusted shell code として動き、child environment は small allowlist に限定します。
新しい `effect-known` event source を含む store は dsh 0.1.5 以降で開いてください。以前の native snapshot は
0.1.5 で開けます。この additional durable content も既存 session capacity 上限を消費します。
全 upstream lifecycle / event coverage は未実装のため、本 issue は open のままです。

Stop command hooks の bounded native slice（2026-10-11）: pinned
[hooks-claude-code/index.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts)
の agent/turn-stopping と stopPayload、[hook-protocol/codec.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/codec.ts)、
[hook-protocol/merge.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hook-protocol/src/merge.ts)、
[core/agent-loop/agent.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts)
を照合しました。native の run / web / mcp / acp / desktop shared runtime は terminal
provider result を durable checkpoint した後に Stop command を実行します。Stop は matcher を無視し、
payload は pinned bridge と同じ five fields（空 transcript_path、stop_hook_active: false を含む）です。
exit 2 / top-level block / Stop-specific deny を decode し、deny > ask > allow の rank と winning-rank の
nonempty reason を config order で merge します。deny は source-tagged user message として同じ turn に steer
し、次 provider step の前に UserPromptSubmit を実行します。UserPromptSubmit rejection は既存 answer を保って
Failed / blocked とし、ACP では refusal として返します。Max-token terminal result も Stop を呼び、許可後も
max_tokens reason は sticky のままです。restore は unsettled boundary を interrupted として閉じ、hook / provider
を再実行しません。Hook process cancellation は drain 後に scheduler owner を解放します。確認済み regression として、
continuation child が provider job owner を奪う問題、長い astral denial が pending turn を残す問題、truncated /
invalid UTF-8 stderr が既知 exit-2 deny を neutralize する問題を修正し fixture で保護しました。

Native の制約は別途維持します。最大 32 command と 16 KiB output capture を元に Stop reason 合計を 524,350 UTF-16
units へ制限し、既存 64 KiB stdin / 262,144 UTF-16 units session capacity を適用します。容量超過候補は provider effect を
publish せず terminal session_capacity で閉じます。engine の既存 max_steps が上限で、dedicated
consecutive-Stop cap はありません。pinned bridge が Stop で利用しない additionalContext、continue:false、
stopReason、updatedInput 等は拡張せず、native も適用しません。upstream の agent/pre-step は各 step で
呼ばれますが、pinned bridge は `messages.length === 0` のとき command を呼ばずに return します。通常の tool-result-only
follow-up は upstream / native とも UserPromptSubmit を呼びません。Stop denial は steered message があるため呼ばれます。
foreground child は初回 prompt の UserPromptSubmit と terminal provider outcome の Stop、denial continuation の
UserPromptSubmit を child Engine の checkpoint / admission API で実行します。initial prompt、hooks、provider retries、tools、
continuations は既存 90 秒 deadline 内にあり、parent cancellation が nested hook process を drain します。Child state は
ephemeral のままで parent unsettled tool result が no-replay boundary です。これらの範囲と残る lifecycle 差分は
[native runtime guide](../../docs/native-runtime.md#native-command-hooks) と
本 issue の残件として記録し、本 issue は open のままです。

ACP の部分対応（2026-10-10）: pinned upstream `packages/acp` の automation-agent 方向を参照し、native `dsh acp` stdio
service を追加しました。ACP v1 の initialize / authenticate、session new / list / resume / set_config_option / prompt / cancel / close、ordered
text / resource-link prompt subset、generic committed update、engine の per-call approval を接続します。allow-once / reject-once は
pending native call ID、prompt generation、durable approval revision に結び、unknown / stale / cancelled response は許可しません。
cancel / close / EOF は durable native cancellation 後に active task を drain し、reopen は中断した provider / tool effect を再送しません。

ACP は root native session に結び付いた canonical workspace / ACP activity metadata を `sessions.json` envelope 内で永続化します。
`session/list` は canonical `cwd` filter と revision-bound 16-session cursor で newest ACP activity first の一覧を返し、read-only です。
`session/resume` は同じ workspace の inactive non-imported root session だけを接続に戻し、過去の `session/update`、provider / tool / approval
effect を replay せず、新しい prompt から保存 context を続けます。既存 0.1.9 envelope は引き続き読めますが、provenance のない session は
`acp-` ID prefix だけで自動採用しません。updatedAt は有効な host UTC clock がある場合のみ出し、ACP-managed activity を表します。
native runtime / CLI からの ACP 外 activity を global last-activity として推定しません。Native keyless tests は list pagination / canonical
filter / stale cursor、process restart、context continuation / no-replay、legacy / imported / forked / active / unknown / foreign workspace
rejection、resume / prompt / close fencing を確認します。

Pinned upstream の[`model-control.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/model-control.ts)、
[`session.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/session.ts)、
[`index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/index.ts)
にある standard `model` option と session response / update を参照して、per-session model selection を追加しました。native では startup
provider / auth route を固定し、API-key route は初期 model と `DSH_ACP_MODELS` の strict JSON string array、ChatGPT route は account-visible
catalog から選択します。環境 catalog は 16 KiB / 32 names / 256 characters per name までです。設定変更は session が idle / settled の時だけ
受け付け、active turn 中は拒否するため、複数 step / retry と foreground child は admitted model を保持します。model と非 secret route fingerprint は
provider protocol / auth mode / demo flag / provider-normalized API origin + path prefix を束ねて session metadata に保存しますが、raw URL、credential、ChatGPT account identity は保存しません。`/v1` suffix と trailing slash の等価 URL は同じ fingerprint になります。reopen 時の fingerprint 不一致または許可 catalog から消えた選択は、history / activity を変更せず拒否します。resume 後の turn は現在 host が管理する API key / ChatGPT account を使い、admitted turn 内の既存 account / generation fence は維持します。旧 0.1.10
ACP records without a model inherit the current startup model. Native tests / stdio fake-provider integration verify two simultaneous sessions route
independently, a busy mutation is rejected, retries and children retain the selected model, update notification precedes its response, changed base URLs
are refused, and a refused selection remains recoverable after the catalog is restored. Route tests cover omitted / explicit defaults, `/v1`, trailing slash, and a distinct endpoint.

これは ACP 全体の互換ではありません。接続あたり initialize は一度、session は起動時の単一 canonical workspace に限り、additional
directory と client MCP mounts は拒否します。prompt block は text と resource_link のみで、resource を fetch せず、image / audio /
embedded context、persistent grant、raw stream delta、provider switching / reasoning controls は提供しません。Pinned baseline の ACP
README も `session/load` を unsupported surface として明記しているため、load はこの実装の parity gap ではありません。JSON line は
1 MiB、nesting は 24、prompt は 16,384 characters、block は 64 個までです。authMethods は空です。実 provider credential を使う ACP
smoke test は未実行です。本 issue は open のままです。

LSP navigation の部分対応（2026-10-10）: pinned upstream
[`packages/lsp`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp)、
[`packages/lsp/lsp-stdio`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp/lsp-stdio)、
[`packages/lsp/tool-lsp`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/lsp/tool-lsp)
を参照し、native `--lsp-config PATH` と `run` / `web` / `mcp` / `acp` / `desktop` 向け
`lsp` tool を追加しました。設定 server は必要な query まで lazy start し、trusted
direct-argv stdio process として動作します。対応 operation は `goToDefinition`、
`findReferences`、`goToImplementation`、`hover` です。extension-to-language routing、
one-based UTF-16 positions、SafeRoot による source / result path checks、transient
`didOpen` / query / `didClose`、bounded workspace-relative locations、UTF-16 / capability
negotiation、bounded Content-Length JSON-RPC、timeout / cancellation / malformed protocol /
disconnect 時の process-group cleanup、graceful close、per-call approval、durable config
fingerprint を実装します。`initializationOptions` / `configuration` の値は保存せず、非 secret
`settingsRevision` で設定変更を追跡します。

これは upstream LSP / Cordis ABI 全体の互換ではありません。remote server、hot reload、
dynamic provider、`didChange`、diagnostics UI、workspace edits、upstream pooled retry、
workspace 外 URI の結果は対象外です。失敗した request は自動 retry / replay しません。
poison された worker は次の独立した approved call で evict され、新しい worker を開始できますが、
失敗した call 自体は再実行しません。LSP server は利用者権限で動く trusted host code で、
workspace path boundary は OS sandbox ではありません。2026-10-10 に local macOS
`/usr/bin/clangd` を使った C definition lookup が成功し、keyless
fake-server tests でより広い protocol / failure paths を検証しました。これは単一 server の local smoke
であり、cross-language、Linux/V8、live-provider acceptance は確認していません。本 issue は open のままです。

Native session TODO の部分対応（2026-10-10）: provider catalog に内部
`todo_write` tool を追加し、per-session visible checklist の全置換、trim / unique / status / single-active
validation、bounded list、`todo/write` event と model call / completion / result の厳密な restore correlation を実装しました。
read/write barrier の順序を保ち、TODO 自体は host effect、approval、PreToolUse / PostToolUse hook を起動しません。
browser transcript、shared GPUI scene、native desktop transcript、session API / protocol projection に表示します。
new turn で clear し、completed checklist は次の turn まで保持し、validated fork は履歴と projection を継承します。
legacy 0.1.7 store と以前の `Unknown tool: todo_write` result は読め、imported v4 は inert のままです。
これは native v1 runtime の bounded subset であり、upstream TODO package の完全な lifecycle / UX parity は確認していません。
keyless engine、provider/API、runtime persistence、browser / desktop presentation tests を追加しました。本 issue は open のままです。

Foreground subagent の部分対応（2026-10-10）: pinned upstream
[`tool-subagent`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/subagent/tool-subagent)
と in-process spawn package を参照し、native `run` / `web` / `mcp` / `acp` / `desktop` の
`--enable-subagents` opt-in tool を追加しました。child は親 transcript を継承せず、同じ configured provider / model route で fresh engine の
foreground loop を実行し、SafeRoot / protected runtime-store checks を通る `read` / `glob` / `grep` だけを使います。
result JSON は 16,384 UTF-16 code units、16 transcript messages、3 model steps、8 child tool calls、90 秒に制限し、parent
session/effect/tool-call と相関させます。parent turn は最大二 child calls、runtime は同時に一 child に制限し、parent cancellation は queued / active
child work に伝わります。Configured UserPromptSubmit は child initial prompt と Stop denial continuation に適用し、Stop は child
engine の accepted terminal boundary で dispatch します。keyless fake-provider tests は child read + second response + parent continuation、
limits、recursive/write denial、hook denial、provider / queued cancellation、restore no-replay を確認しました。

これは upstream subagent lifecycle の全実装ではありません。child session は独立保存・再開せず、interruption 前に settlement した result だけが
parent tool result に残ります。background / continuable mode、provider selection、tool filters、persona、structured output schema、provider capability
negotiation、child-specific UI は含みません。Configured PreToolUse / PostToolUse hooks は child reads にも継承され、trusted host code として副作用を
起こし得ます。Initial UserPromptSubmit denial は provider step 0 の failed child result と bounded `failure_reason` を既存 parent tool result に返し、別の
child refusal status を導入しません。reopen には `--enable-subagents` が必要で、中断した child は replay しません。本 issue は open のままです。

2026-10-11 に bounded `SubagentStart` / `SubagentStop` command-hook slice を追加しました。Start の deny は child を拒否せず、matching context は in-flight provider request を変えず、現在 claim された input batch を UserPromptSubmit に渡してから次 provider request へ進みます。Initial / later child input と Stop continuation の境界で batch を claim し、hook 中の到着は後続 step に残します。Stop の deny / context も child result を変えません。Native Start task は child settlement で cancel / drain し、Stop cleanup は child drive outcome 後に aggregate 1 秒の command-execution grace を使います。process cancellation / group cleanup / reaping / output drain は追加 wall time を要することがあり、pinned bridge の detached-until-dispose lifetime とも異なります。既存候補で slow Stop が成功済み child を timed_out に変える欠陥が再現し、cleanup を drive timeout の外へ移す regression を追加しました。cleanup は parent tool result の返却を遅らせますが child outcome を変更しません。`hook/subagent-start-context` は count / length を記録する additive Engine marker であり、後続 source-tagged user message が context を運びます。Native child Engine は root store に保存しません。SubagentStart / Stop の matcher、payload、late context、decision 非適用、provider failure、cancel / timeout、restore / no-replay を keyless tests で確認しました。後続の frozen-head probe では accepted Stop+Start batch の snapshot を restore 時に generic late-admission boundary と誤認して拒否する欠陥を確認しました。Stop continuation が claim した Start marker/message は既存 Stop admission state に属するよう修正し、正順の snapshot roundtrip と marker/reason の順序破損を検証する regression を追加しました。child Engine の public prompt checkpoint helper にも通常 prompt と同じ空 / 長さ上限を追加し、invalid input が queue を変更しないことを確認しました。さらに frozen replay probes で allowed Stop が queued Start の間に終わる場合の snapshot restore failure を検出しました。queued hook input による next-step admission 前に共有 Stop engine が empty-data `hook/stop-settled` boundary を保存し、replay は Stop continuation state だけを消して sticky max-token state を保ちます。この event は child snapshot だけでなく root snapshot にも現れるため、0.1.16 reader が必要です。accepted / denied / interrupted admission、Stop+Start order、malformed settlement order、root Stop snapshot を検証しました。別の frozen probe では initial batch が shared 32-item limit を使い切った後に queued Start text が既存 direct-admission fallback で drop されると、settlement の次境界が marker なしの `step/start` になるため restore が拒否する不整合を検出しました。reader は `hook/stop-settled` 後の通常 `step/start` も許可し、その event で境界状態を閉じます。32-item exhausted regression は dropped context と completed snapshot roundtrip を確認します。別の public Engine accounting regression では initial Start user message と step-0 marker の二重計上を修正し、16-item initial batch 後に残り item である late context が受け入れられて completed snapshot から restore されることを確認しました。Native bridge は child ごとに一度 Start callback を呼びますが、public Engine API の later injection batch は shared 32-item / 16,384 UTF-16-unit bounds を使います。

この increment の UserPromptSubmit admission は initial input の Start batch、後続 step 単独の Start batch、Stop continuation と一緒に claim した Start batch が対象です。残る差分は PostToolUse additionalContext で、native は既存の直接 Engine admission を維持し UserPromptSubmit を実行しません。Pinned [`agent.ts:171-173`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L171-L173) は next-step inbox を取り込み、[`agent.ts:358-382`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/agent.ts#L358-L382) は非empty inbox がある間に次 step を実行します。[`hooks-claude-code/index.ts:223-239`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/hooks/hooks-claude-code/src/index.ts#L223-L239) は空 inbox の場合だけ早期 return するため、PostToolUse message のような nonempty inbox は hook に渡ります。ordinary tool-result-only follow-up は inbox が空なので upstream も command hook を呼びません。詳細と他の native lifetime 差は[native runtime guide](../../docs/native-runtime.md#native-command-hooks)および[port status](../../docs/port-status.md)を参照してください。本 umbrella issue は open のままです。

受入条件:

- plugin mount / teardown 中の依存、保有リソース、tool 呼出しを一貫して扱う。
- 子 agent / process / external tool を親の cancel で停止し、再開時に重複実行しない。
- 各拡張に成功・拒否・timeout・切断・reopen の結合テストを追加する。

## 4. Provider と UI の機能範囲

画像 / file、thinking signature の保存と replay、mid-conversation system / tool update、model discovery を追加する。
gpui を使って settings、attachment preview、workspace change、terminal / subagent 表示へ広げる。
native window は browser と共有できる state / scene を保って別の host adapter として実装する。

受入条件:

- 保存して再読込した request を provider が受理でき、失われる metadata を明示する。
- 実 API 検証は認証をログへ残さず、keyless fixture の検証と区別して記録する。
- native target で window、入力、IME、resize、close の実機検証を完了する。

## 5. Host と運用

OS sandbox、persistent terminal、SSH workspace、job / schedule、認証付き remote API を独立した host capability として追加する。
現在の loopback / local workspace の挙動を維持し、利用者が有効化した機能だけを公開する。

受入条件:

- 対応 OS ごとの filesystem / process 権限と recovery を検証する。
- remote API には authentication / authorization と複数利用者の分離を導入する。
- 新しい production package を mutation gate に追加し、単なる mutant 列挙を成功扱いしない。

## gpui-mbt 依存の追跡

`hotpath.mbt` の固定 revision は standalone LICENSE / manifest license field を含まない。
dependency の license metadata が upstream に追加されたら確認し、pin と第三者通知を更新する。
この repository の MIT 表記を依存ソースに転用しない。
