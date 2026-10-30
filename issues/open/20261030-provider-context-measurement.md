# Measure the admitted provider request before dispatch

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-provider-context-measurement

## Overview

Expose a read-only size measurement for the exact provider request already admitted by the engine.

## Scope

- Count UTF-8 bytes for the serialized engine request, messages array, and tool-schema array.
- Count system-prompt UTF-8 bytes and Unicode code points, plus message and tool counts.
- Read the active provider effect from engine state without draining or changing its dispatch queue.
- Bound serialized components to 16 MiB, nesting to 128 levels, and visited JSON values to 16,777,216; label units explicitly.

## Limits

These values describe the engine request before provider-specific wire transformation. They are not tokenizer counts, provider context-window measurements, an admission budget, or a compaction trigger. This increment does not generate summaries, compact live history, or increase durable session capacity.

The latest tool-result capacity gap remains open: an over-capacity completion currently closes the turn as `session_capacity`. Existing v2 archives require an already committed regular Read result with a direct pruning event, so they cannot rescue the completion that crosses the cap. A follow-up must design active-result summary/archive semantics, preserve call/effect correlation, commit the object and compact projection atomically, and verify restore/no-replay. It must also define provider-specific budget inputs and finite archive-quota behavior before claiming long-session support.

## Acceptance

- [ ] Measurement reflects the exact request emitted by `start_step`, including the current message projection and tool schemas.
- [ ] Querying it leaves snapshots and queued effects unchanged, both before and after a host drains the dispatch queue.
- [ ] Missing active requests are reported as absent; malformed and over-bound request shapes fail without mutation.
- [ ] Documentation states the measurement units and limits without claiming token or model-window guarantees.

## Validation plan

- Engine tests cover Unicode bytes/code points, message/tool-schema accounting, exact request equality, non-draining reads, missing requests, malformed shapes, and the 16 MiB bound.
- API wrapper test verifies the native in-process query preserves queued effects.
- Existing engine/API package checks and tests remain green.
