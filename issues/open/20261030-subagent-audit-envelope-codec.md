# Define a bounded inert envelope for child audit snapshots

Status: open
Model: gpt-6
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-subagent-audit-schema

## 概要

Specify a strict, bounded JSON envelope for a future settled foreground child audit snapshot. The codec validates the shape of parent correlation fields and terminal engine state while keeping the decoded record inert.

## 背景

The [subagent resume and ownership contract](https://github.com/f4ah6o/dsh.mbt/pull/76) leaves the child audit slice as the smallest candidate before background execution or resume. The proposed [child audit snapshot issue](https://github.com/f4ah6o/dsh.mbt/pull/80) requires a complete child record whose existence cannot adopt a parent result or trigger external work.

The current parent tool result remains the no-replay boundary. A child snapshot may contain private prompts, hook context, and tool results, so storing it requires separate access control and retention rules.

## 問題

The foreground child Engine is ephemeral, while the parent tool result remains the durable no-replay boundary. A future child audit record needs a strict bounded shape and terminal-state validation before storage work can safely consume it. An ambiguous or malformed snapshot could otherwise be mistaken for a live child, and duplicate JSON keys could make correlation fields parser-dependent.

## 目標

Define the `dsh-subagent-audit-v1` envelope with exactly these fields:

- `schema`: `dsh-subagent-audit-v1`.
- `parent_session_id`, `parent_turn_id`, `parent_effect_id`, and `parent_tool_call_id`.
- `child_id`, `workspace_id`, and `child_status` (`completed` or `failed`).
- `engine_snapshot`: one complete `dsh.mbt-session-v1` child session with matching ID and terminal status.

The codec caps encoded data at 4 MiB, JSON depth at 32, and JSON nodes at 65,536. It rejects duplicate JSON object keys, unknown or missing envelope fields, malformed IDs, a child ID/status mismatch, nonterminal outcomes, interrupted/cancelled children, malformed engine snapshots, and unsettled engine effects. It validates the engine snapshot in a throwaway pure Engine and requires an empty effect queue.

## 対象外

- Writing, listing, reading, deleting, encrypting, or retaining audit files.
- Runtime/store integration, public wire commands, UI, or an archive index. The codec functions are only in-process package operations.
- Background child execution, restore-to-run, explicit resume, replay, or parent result adoption.
- Quota accounting, temporary file recovery, or orphan cleanup.

## 提案する方針

Keep this increment as a pure in-process codec with no store or runtime hooks. Use exact envelope fields, explicit byte/depth/node limits, typed identity syntax checks, duplicate-key rejection, and validation through a throwaway pure Engine. The decoded snapshot must remain inert and must not expose an execution path.

Storage integration depends on the following separate work:

- [PR #80](https://github.com/f4ah6o/dsh.mbt/pull/80): exact pending tool-effect ownership query. The caller must check it together with command cancellation while holding the native runtime gate.
- [PR #81](https://github.com/f4ah6o/dsh.mbt/pull/81): bounded no-replace atomic publication with distinct known failure and unknown outcome results.
- A separate owner-only archive directory and aggregate byte/count quotas that include abandoned temporary files.
- A read-only inspection path that never constructs a live child runtime or dispatches provider/tool/hook effects.

## 受け入れ条件

- [x] The v1 envelope has an exact, bounded schema with typed identity validation.
- [x] Only one matching completed or known-failed child engine snapshot is accepted.
- [x] Decoding validates terminal state without dispatching effects or exposing a resume path.
- [x] Duplicate object keys are rejected, including escaped spellings of the same key.
- [x] Tests cover successful and failed round-trip, unknown fields, malformed identities, mismatches, interruption, byte/depth/node bounds, source detachment, and invalid engine state.
- [x] The [publication contract issue](20261030-subagent-audit-publication.md) defines the file-only reader boundary, quotas, orphan handling, and parent interruption semantics before storage integration.

## テスト計画

Run focused native codec tests with `moon test runtime --target native --filter '*subagent audit*'`. The fixtures cover successful and failed round-trip, unknown and missing fields, malformed identity, mismatched child identity/status, forged derived messages, interrupted outcomes, duplicate keys including escaped spellings, source detachment, and exact byte/depth/node limits. Also run `moon check runtime --target native`, formatting, and the native runtime package suite.

## リスク

Child snapshots contain sensitive prompts, hook context, and tool results. They require owner-only storage and retention limits before publication is integrated. If publication fails or its outcome is unknown, do not settle the child as an ordinary tool error and continue the parent model loop. That could invite a second child invocation after provider or hook work already ran. Interrupt the parent turn and never retry the child or infer success from an orphan. A successful archive followed by parent cancellation is also an orphan and must not be adopted or deleted automatically.

## 変更履歴

`CHANGES.md` impact: no

This codec is internal-only and does not change a user-facing command or durable store format.

## 注記

This codec alone does not persist child state and provides no durable audit guarantee. It does not prove that the parent session, turn, effect, tool call, or workspace fields correspond to a live authorized owner; those fields receive syntax/type checks only. A publisher must check pending-effect ownership and cancellation under the runtime gate. The codec does not prove authorization to execute or adopt the child. The snapshot remains sensitive data and needs owner-only storage before integration.
