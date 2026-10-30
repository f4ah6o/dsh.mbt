# Inspect settled child audits without resuming work

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-subagent-audit-inspection

## 概要

Add a local read-only CLI to list and inspect settled foreground child audit records, scoped to the current OS user's native data directory and one exact parent session. Inspection never grants execution, adoption, or resume authority.

## 背景

- [PR #76](https://github.com/f4ah6o/dsh.mbt/pull/76) separates settled audit storage, foreground execution, background work, explicit child resume, and ACP root-session resume.
- [PR #89](https://github.com/f4ah6o/dsh.mbt/pull/89) adds the bounded inert `dsh-subagent-audit-v1` codec.
- [PR #92](https://github.com/f4ah6o/dsh.mbt/pull/92) defines owner-only publication and explicitly excludes runtime reads and adoption.
- [PR #98](https://github.com/f4ah6o/dsh.mbt/pull/98) publishes opt-in terminal snapshots as immutable files under `subagent-audits/`.

The files contain child prompts, hook context, and tool results. Their parent and workspace fields are correlation metadata saved in a local record; neither field proves live authorization or a committed parent result.

## 問題

PR #98 creates durable records but intentionally exposes no reader. Inspecting a record through the normal runtime path would initialize the provider, configured hooks, tools, session store, and host lock even though the operation needs none of them. A reader must also avoid presenting another parent session's record as belonging to the requested session or interpreting a terminal snapshot as a checkpoint for execution.

## 目標

- Add local CLI `subagent-audits list --session PARENT_SESSION_ID` and `subagent-audits show CHILD_ID --session PARENT_SESSION_ID` operations.
- Read only from the selected native data directory after checking that its opened root is current-OS-user-owned with mode 0700, the `subagent-audits/` directory is also current-OS-user-owned with mode 0700, and every inspected file is current-OS-user-owned with mode 0600.
- Verify each displayed record with the existing bounded v1 decoder and require its envelope child ID to match its filename.
- Filter records by the exact requested parent session and the selected store's workspace identity as correlation values only.
- Run inspection before `NativeRuntime::open`; do not create files or directories, acquire the host lock, checkpoint sessions, invoke providers, run tools or hooks, or expose an API/ACP method.
- Bound directory traversal by the existing 32-entry / 128 MiB directory limits and the 4 MiB per-record limit.
- Keep all displayed snapshots inert. Their presence never completes a parent tool result, adopts an orphan, replays work, or enables resume.

## 対象外

Background or continuable children, process-restart recovery, explicit child resume, parent-result adoption, retry, deletion, retention, mutation, UI, service/ACP/wire exposure, and changes to the foreground child lifecycle are out of scope. ACP resume remains limited to its separately registered root sessions.

## 提案する方針

Implement a standalone local CLI path that reads an existing owner-only native data directory and its `subagent-audits/` subdirectory through anchored `SafeRoot` operations. Check directory metadata without chmod or other mutation; reject a symlink, junction, non-directory entry, or directory with the wrong owner or mode. Require one parent session ID for both list and show. List returns only bounded correlation metadata and child status for matching records; show returns the selected validated envelope only when both the filename child ID and exact parent session ID match. A selected store's `workspace-id` may be compared to the envelope as an additional correlation filter, but it is local file data and is not independent live authorization.

Keep reads to 32 regular entries / 128 MiB logical bytes and cap every record at 4 MiB. Reject a nested directory, unreadable or over-limit file, invalid permissions, malformed recognized audit, filename/envelope mismatch, or unsupported schema with a bounded error. Ignore unrelated filenames and atomic-create temp files without reading them; continue to count them toward directory bounds. A missing audit directory returns an empty list for list and a not-found result for show, without creating the directory.

The CLI path must bypass `NativeRuntime::open`, including provider configuration, native store locking, hooks, and scheduler setup. It performs only local reads and serialization of inert data. The command does not require `--enable-subagents` or `--persist-subagent-audits`, because it grants no execution capability.

## 受け入れ条件

- [ ] List and show are available only as local CLI commands and require an exact parent session ID.
- [ ] Only current-user-owned, owner-only data directories and 0600 audit files are read; reads use bounded anchored APIs.
- [ ] List/show enforce record, entry, and directory byte caps and validate v1 schema plus filename/envelope identity.
- [ ] A wrong parent session or store workspace correlation does not reveal the record contents.
- [ ] The inspection branch bypasses provider, tool, hook, scheduler, host lock, and session checkpoint setup.
- [ ] Inspection cannot adopt, resume, replay, delete, or mutate an audit or parent session.
- [ ] Documentation distinguishes these inert records from background children, explicit child resume, and ACP root-session resume.

## テスト計画

- CLI parser fixtures cover list/show argument counts, required parent session, and rejection of unrelated execution modes.
- Native filesystem fixtures cover owner/mode checks, missing audit directory, wrong parent/workspace filters, strict decoder failures, filename mismatch, per-record cap, 32 entries, 128 MiB logical bytes, and nested directory rejection.
- Verify list exposes only matching metadata and show exposes only the selected matching envelope; use fixtures with different parent sessions to check no cross-session disclosure.
- Verify the inspection action is routed before native runtime startup and no mutation is made to the data directory, sessions, host lock, or audit files.
- Run focused runtime native checks, the relevant runtime fixture, formatting, diff check, local issue validation, and independent review.

## リスク

Audit contents are private local data. OS owner-only permissions and exact parent-session filtering limit accidental disclosure, but same-user processes remain inside the trust boundary. Parent and workspace values in a record are not proof of live authorization. A visible record can be an orphan whose parent result did not commit. The reader must preserve that distinction and never infer permission to continue external work.

## 変更履歴

`CHANGES.md` impact: yes

Proposed item: Add read-only local inspection for settled foreground child audits.

## 注記

This is a local owner inspection surface only. It does not make child snapshots resumable and does not change ACP's independent root-session resume behavior.
