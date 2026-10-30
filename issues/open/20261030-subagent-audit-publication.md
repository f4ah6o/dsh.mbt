# Publish opt-in settled foreground child audit snapshots

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-child-audit-publication-contract

## Summary

When separately opted in, publish the complete terminal Engine snapshot of a foreground child as an immutable local audit file. The file records parent/child/workspace correlation and never authorizes execution, resume, or parent-result adoption.

## Dependencies

- [PR #89](https://github.com/f4ah6o/dsh.mbt/pull/89): strict inert `dsh-subagent-audit-v1` codec; maximum record size 4 MiB.
- [PR #80](https://github.com/f4ah6o/dsh.mbt/pull/80): exact pending parent tool-effect ownership query.
- [PR #81](https://github.com/f4ah6o/dsh.mbt/pull/81): bounded no-replace atomic file create with distinct `Exists`, `Failed`, and `OutcomeUnknown` results.
- [PR #91](https://github.com/f4ah6o/dsh.mbt/pull/91): anchored file metadata for counting partial temporary files without reading them; stacked on #81.

## Publication contract

Add a separate `--persist-subagent-audits` opt-in, requiring `--enable-subagents`. The default creates no audit directory or file. After the child drive and observational `SubagentStop` cleanup settle, encode `child.snapshot()` with the #89 codec. Publish only codec-accepted terminal `completed` children or `failed` children whose terminal reason is `provider_error`, `max_steps`, `max_tokens`, `effect_limit`, `session_capacity`, or `blocked`. Timed-out, cancelled, interrupted, unsettled, malformed, or over-limit snapshots have no audit record; with audit persistence enabled, they take the fatal parent-interruption path below instead of being returned as an ordinary child tool error.

Store each encoded envelope at `subagent-audits/<child_id>.json` beneath the owner-protected native data directory. Create the directory with mode 0700 and files with mode 0600. Use immutable no-replace publication. Keep this increment file-only: no list/read/delete command, index, automatic retention, or runtime path that restores a child Engine. A local owner may read the raw JSON file directly. Any future in-product reader must use the strict codec and expose inert data only.

Use these hard logical quotas:

- One encoded record: at most the codec's 4 MiB limit.
- Audit directory: at most 32 regular-file entries and 128 MiB total logical file bytes.
- Before creating a record of `N` bytes, reserve two entries and `2 * N` bytes. Atomic create may leave both a complete destination and a `.dsh-<pid>-<serial>.tmp` / `..dsh-<pid>-<serial>.tmp` file if interruption or cleanup failure makes publication uncertain; an interrupted temp can contain at most the submitted record size.

Before every publication, scan the flat directory with the anchored `SafeRoot` APIs. Charge every regular file, including temporary and unrecognized names, using `SafeRoot::file_version`; do not parse file contents to calculate quota. Reject directory entries, failed listings, uncountable files, or a quota that cannot reserve the candidate plus its possible temp. The store lock and runtime gate serialize this scan and publication. `file_version` is a sampled stat, not a content lock: same-user concurrent replacement or in-place writes are outside the host trust boundary. Do not automatically delete temp files or audit records at startup. Abandoned files remain charged until an owner removes them offline; quota exhaustion fails closed.

Immediately before the scan and atomic create, acquire `NativeRuntime.gate` and verify the runtime is open, the job is not cancelled, and the exact parent `(effect_id, session_id, call_id)` is still owned by the Engine. Read the live parent turn ID and workspace ID under that gate. Keep the gate through quota scan and atomic create so a parent cancellation accepted before the gate prevents publication. If publication wins first and cancellation follows, leave the file as an unadopted orphan.

Treat any codec, quota, or filesystem publication failure as fatal after child provider/tool/hook work has run:

| Outcome | Parent behavior |
| --- | --- |
| Atomic create succeeds | Continue to normal parent tool-result completion. The parent completion checkpoint is a separate transaction. |
| `Exists` | Do not read or compare the destination; fail the parent turn. |
| `Failed` | Treat as known unpublished, but do not retry the child or continue the parent model loop. |
| `OutcomeUnknown` | Do not reconcile, retry, or infer success. A destination or temp may remain as an orphan. |
| Codec/quota/scan error | Do not call the normal `finish_tool_effect` path. |

Add a distinct fatal result from `run_subagent_tool` through `run_tool_effect` so these failures bypass parent `PostToolUse`, `UserPromptSubmit`, tool-result continuation, and provider dispatch. Under the runtime gate, terminate the parent as `Failed` with reason `interrupted`, append `session/interrupted`, and record the pending child tool as an interrupted `tool/completed` outcome (`source: interrupted`) before checkpointing. This is a terminal diagnostic result, never a successful `source: effect` result. Add a narrow internal Engine/API interruption operation if required; do not use user-facing `session_cancel` semantics for a storage failure. A remote accepted-command receipt is `uncertain`, never replayable. If this checkpoint is uncertain, leave recovery to the existing no-replay restore path.

Publishing the child file and committing the parent tool result are separate transactions. Only the parent Engine checkpoint records the result delivered to the model. If cancellation or parent checkpoint failure follows a successful file publication, keep the file; it remains an orphan and must not be deleted, adopted, or retried automatically. `SubagentStop` command output is observational and is not claimed to be part of the Engine snapshot.

## Acceptance conditions

- [ ] A separate opt-in flag preserves default behavior and requires `--enable-subagents`.
- [ ] Only a fully validated terminal child Engine snapshot is written as the exact #89 envelope.
- [ ] Directory and file permissions, no-replace names, record cap, aggregate byte/count caps, and temp-file reservation are enforced.
- [ ] Parent ownership, cancellation, turn, and workspace are rechecked under the runtime gate immediately before publication.
- [ ] `Exists`, `Failed`, `OutcomeUnknown`, codec errors, and quota errors cannot settle as normal tool results or dispatch parent hooks/provider work.
- [ ] Parent interruption is durably checkpointed; any uncertain receipt or later cancellation does not replay provider, tool, or hook work.
- [ ] Successful publication followed by parent cancellation/checkpoint uncertainty leaves an inert orphan with no automatic adoption or deletion.
- [ ] Documentation states that no background execution, child resume, replay, read API, retention, or parent-result adoption is implemented.

## Test plan

- Keyless native fixtures for completed and known-failed children, exact envelope decode, default-off behavior, and flag dependency.
- Boundary tests for 4 MiB, 32 entries, 128 MiB, the two-entry/twice-byte reserve, partial NUL-containing temp files, and failed directory enumeration.
- Fault injection for `Exists`, pre-publication `Failed`, and `OutcomeUnknown`; verify each skips parent PostToolUse/UserPromptSubmit/provider work and does not retry child effects.
- Gate barriers for cancellation before publication and cancellation after publication; verify the first writes nothing and the second leaves an orphan.
- Parent checkpoint failure after file publication; verify uncertain receipt/no child replay and restore interruption.
- Native checks on supported POSIX hosts and Windows CI for SafeRoot metadata and atomic create.

## Non-goals

Background or continuable children, explicit resume, child re-execution, automatic orphan adoption/deletion, an archive index, UI/API reads, encryption, unbounded retention, or changing existing foreground-subagent defaults.

`CHANGES.md` impact: yes

Change item: Add optional durable audit files for settled foreground children.
