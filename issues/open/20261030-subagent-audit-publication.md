# Publish opt-in settled foreground child audit snapshots

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-subagent-audit-publication

## 概要

When separately opted in, publish the complete terminal Engine snapshot of a foreground child as an immutable local audit file. The file records parent, child, and workspace correlation. Its presence never authorizes execution, resume, or parent-result adoption.

## 背景

- [PR #89](https://github.com/f4ah6o/dsh.mbt/pull/89) adds the strict inert `dsh-subagent-audit-v1` codec, with a 4 MiB maximum record size.
- [PR #80](https://github.com/f4ah6o/dsh.mbt/pull/80) adds the exact pending parent tool-effect ownership query.
- [PR #81](https://github.com/f4ah6o/dsh.mbt/pull/81) adds bounded no-replace atomic file creation with distinct `Exists`, `Failed`, and `OutcomeUnknown` results.
- [PR #91](https://github.com/f4ah6o/dsh.mbt/pull/91), stacked on #81, adds anchored file metadata so quota scans can size partial temp files without reading them.

Without opt-in publication, a foreground child exists only in memory and the parent receives a bounded result that may omit transcript data. This issue wires the existing codec and filesystem primitives into an owner-only immutable audit directory and defines failed publication as a fatal parent-turn outcome.

## 問題

Treating a save failure as an ordinary tool error would let the parent run `PostToolUse`, `UserPromptSubmit`, or another provider step after child provider/tool/hook work has already occurred. Retrying that child could repeat external work. A file publication and the parent tool-result checkpoint are also separate commits, so a successfully written file may outlive a cancelled or uncertain parent commit.

## 目標

- Preserve a complete, codec-validated terminal child Engine snapshot only when a separate audit option is enabled.
- Bound the record, directory entry count, and aggregate logical bytes, including abandoned atomic-create temp files.
- Recheck exact parent effect ownership and cancellation under the runtime gate before publication and before a fatal parent interruption.
- Make save uncertainty terminal for the active parent command, without replaying provider, tool, or hook work or adopting an orphan.

## 対象外

Background or continuable children, child resume, child re-execution, automatic orphan adoption/deletion, an archive index, runtime list/read/delete commands, encryption, unbounded retention, and changes to existing foreground-subagent defaults are out of scope.

## 提案する方針

**Opt-in and eligible records.** Add a separate `--persist-subagent-audits` option that requires `--enable-subagents`; the default creates no audit directory or file. After the child drive and observational `SubagentStop` cleanup settle, encode `child.snapshot()` using the #89 codec. Publish only codec-accepted terminal `completed` children or `failed` children whose terminal reason is `provider_error`, `max_steps`, `max_tokens`, `effect_limit`, `session_capacity`, or `blocked`. Timed-out, cancelled, interrupted, unsettled, malformed, or over-limit snapshots produce a fatal child outcome rather than an ordinary child tool error. The fatal path interrupts the parent only if the exact effect still owns an open parent turn; an already accepted parent cancellation remains authoritative.

**Storage and quotas.** Store each envelope at `subagent-audits/<child_id>.json` under the owner-protected native data directory. Set the directory to 0700 and files to 0600. Publish immutably with no-replace atomic create. The file remains raw JSON for local owner inspection; any future in-product reader must use the strict codec and expose inert data only.

Use these logical quotas:

- One encoded record: at most 4 MiB.
- Audit directory: at most 32 regular-file entries and 128 MiB total logical file bytes.
- Before creating a record of `N` bytes, reserve two entries and `2 * N` bytes. Atomic create may leave both a complete destination and a `.dsh-<pid>-<serial>.tmp` or `..dsh-<pid>-<serial>.tmp` file if interruption or cleanup failure makes publication uncertain; a temp contains at most the submitted record size.

Before every publication, scan the flat directory with anchored `SafeRoot` APIs. Charge every regular file, including temp files and unrecognized names, with `SafeRoot::file_version`; do not read file contents to calculate quota. Reject reported directory entries, failed listings, uncountable files, or a quota that cannot reserve the candidate and its possible temp. The native data-directory lock and runtime gate serialize writers. `file_version` samples one opened inode and does not lock against same-user replacement or in-place writes; those races are outside the host trust boundary. Do not clean temp files or audit records automatically. Abandoned files remain charged until an owner removes them offline, and quota exhaustion fails closed.

**Publication gate.** Immediately before quota scan and atomic create, acquire `NativeRuntime.gate`. Check that the runtime is open, the job is not cancelled, and the exact `(effect_id, session_id, call_id)` remains owned by the Engine. Read the live parent turn and workspace IDs under the gate. Keep the gate through the scan and create so a cancellation accepted first prevents publication. If publication wins first and cancellation follows, keep the file as an unadopted orphan.

**Save outcomes.** Treat codec, quota, scan, and publication failures as fatal after child work has run:

| Outcome | Parent behavior |
| --- | --- |
| Atomic create succeeds | Continue to normal parent tool-result completion. The parent checkpoint is a separate transaction. |
| `Exists` | Do not read or compare the destination; fail the parent turn. |
| `Failed` | Treat as known unpublished, but do not retry the child or continue the parent model loop. |
| `OutcomeUnknown` | Do not reconcile, retry, or infer success. A destination or temp may remain as an orphan. |
| Codec, quota, or scan error | Do not call normal `finish_tool_effect`. |
| Parent cancellation or settlement already won | Preserve that state; do not interrupt or complete the effect a second time. |

Add a distinct fatal result from `run_subagent_tool` through `run_tool_effect`. It must bypass parent `PostToolUse`, `UserPromptSubmit`, tool-result continuation, and provider dispatch. Before applying the fatal result, acquire `NativeRuntime.gate` again and recheck runtime state, cancellation, exact effect ownership, and that the parent remains running in the turn that owns the effect. If cancellation or another terminal transition won first, do not append `session/interrupted`, complete the effect, or emit another terminal event. If ownership remains live, terminate the parent as `Failed` with reason `interrupted`, append `session/interrupted`, record the pending child call as an interrupted `tool/completed` outcome (`source: interrupted`), and checkpoint. This is a terminal diagnostic outcome, never a successful `source: effect` result. Add an internal Engine/API interruption operation if needed; do not use user-facing `session_cancel` semantics for a storage failure.

A remote accepted-command receipt is `uncertain`, never replayable. If the interruption checkpoint is uncertain, existing no-replay restore behavior closes unfinished work. Publication and parent-result commit stay separate: if cancellation or parent checkpoint failure follows successful publication, keep the file as an orphan and do not delete, adopt, or retry it automatically. `SubagentStop` command output is observational and is not claimed to be part of the Engine snapshot.

## 受け入れ条件

- [x] A separate opt-in preserves default behavior and requires `--enable-subagents`.
- [x] Only a fully validated terminal child Engine snapshot is written as the exact #89 envelope.
- [x] Directory/file permissions, no-replace names, record cap, aggregate byte/count caps, and temp-file reservation are enforced.
- [x] Parent ownership, cancellation, turn, and workspace are checked under the runtime gate immediately before publication.
- [x] `Exists`, `Failed`, `OutcomeUnknown`, codec errors, and quota errors cannot settle as ordinary tool results or dispatch parent hooks/provider work.
- [x] Fatal interruption rechecks ownership and the open parent turn under the gate; if cancellation/settlement won, preserve that terminal state without duplicate interruption or effect completion.
- [x] Parent interruption is checkpointed; uncertain receipts or later cancellation do not replay provider, tool, or hook work.
- [x] Successful publication followed by cancellation/checkpoint uncertainty leaves an inert orphan without automatic adoption or deletion.
- [x] Documentation says background execution, child resume, replay, runtime reads, retention, and parent-result adoption are unsupported.

## テスト計画

- Keyless native fixtures for completed/known-failed children, exact envelope decode, default-off behavior, and the flag dependency.
- Boundary tests for 4 MiB, 32 entries, 128 MiB, two-entry/twice-byte reservation, partial NUL-containing temp files, and failed directory enumeration.
- Fault injection for `Exists`, pre-publication `Failed`, and `OutcomeUnknown`; verify each skips parent hooks/provider work and does not retry child effects.
- Gate barriers for cancellation before publication and after publication; the first writes nothing and the second leaves an orphan.
- A gate barrier between fatal publication outcome and parent interruption, exercising both winners. Cancellation first preserves `cancelled` without `session/interrupted` or duplicate tool completion. Fatal interruption first records exactly one interrupted outcome; later cancellation adds no terminal event.
- Parent checkpoint failure after file publication; verify uncertain receipt, no child replay, and restore interruption.
- Native checks on supported POSIX hosts and Windows CI for SafeRoot metadata and atomic create.

## リスク

Child prompts, hook context, and tool results can contain private data. Owner-only directory/file permissions reduce exposure to other local users; same-user hostile races remain outside the host trust boundary. Quota values bound logical file bytes, not filesystem allocation overhead. An `OutcomeUnknown` can leave both a final file and temp file. The audit record is inert and does not prove that the parent later committed the matching result. An interruption API must preserve existing cancellation/settlement if they win the gate first. `SubagentStop` command payloads and output are not part of the child Engine snapshot.

## 変更履歴

`CHANGES.md` impact: yes

Proposed item: Add optional durable audit files for settled foreground children.

### 2026-10-30 実装・検証記録

実装: GPT-6 Codex subagent。独立レビュー: gpt-6.1-sol / xhigh。`moon check runtime desktop verification/native_fs --target native --deny-warn`、`moon fmt --check runtime desktop verification/native_fs`、`git diff --check` は PASS。native worker と subreaper を指定した `moon test runtime --target native --deny-warn --no-parallelize` は 235/235 PASS。process-global temp serial exhaustion fixture は独立 native package に分離し、同 fixture は fresh process で 1/1 PASS。独立 reviewer の audit fixture run は 23/23 PASS。

この環境では Windows native CI と実際の power-loss crash test は未実施。`python3 /tmp/dsh-local-issues.py --repository-root /workspace/dsh-subagent-audit-publication validate --issue-root issues --path issues/open/20261030-subagent-audit-publication.md` は violations なしで PASS。Native full-suite run は一時 port conflict を検出して空き loopback port に切り替えた後に完了し、1 つの承認拒否 diagnostic を出したが、235 tests はすべて PASS。

## 注記

This branch implements the opt-in publication path stacked on #89. It adds no audit reader, retention manager, background execution, child resume, or replay support. The record remains inert and publication remains separate from the parent result checkpoint.
