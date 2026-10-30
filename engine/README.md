# Pure MoonBit harness engine

`f4ah6o/dsh/engine` owns sessions, append-only events, the model/tool loop,
approvals, and effect correlation. It performs no filesystem, network, process,
clock, or UI operations. The host drains effects and supplies their results.

## Public boundary

```moonbit
Engine::new(tools : Array[Json]) -> Engine
Engine::invoke(operation : String, input : Json) -> Result[Json, String]
Engine::take_effects() -> Array[Json]
Engine::complete(effect_id : String, result : Json) -> Result[Json, String]
Engine::provider_context_measurement(session_id : SessionId) -> Result[ProviderContextMeasurement?, String]
Engine::plan_compaction_prefix(session_id, retain_recent_turns, max_source_event_json_utf8_bytes, max_source_messages_json_utf8_bytes) -> Result[Json?, String]
Engine::prepare_compaction_summary_candidate(session_id, plan, summary, retain_recent_turns, max_source_event_json_utf8_bytes, max_source_messages_json_utf8_bytes, max_summary_json_utf8_bytes) -> Result[Json, String]
Engine::project_stream(effect_id : String, content : String, reasoning : String) -> Result[Json, String]
Engine::snapshot() -> Json
Engine::restore(snapshot : Json) -> Result[Unit, String]
Engine::restore_archived(snapshot : Json, sources : Array[ToolResultArchiveSource]) -> Result[Unit, String]
Engine::tool_result_archive_candidate(plan, source) -> Result[Json, String]
Engine::commit_tool_result_archive(plan, source) -> Result[Unit, String]
```

The in-process typed method `Engine::plan_tool_result_archive(session_id,
result_seq)` can inspect one already-pruned `read` tool result and return an
opaque `ToolResultArchivePlan` containing only identity, event sequences, and
Unicode lengths. `glob`, `grep`, `skill`, `subagent`, and other read-classified
tools are outside this first slice. The plan has no event-count or freshness
stamp, so it cannot prove by itself that no state changed after it was made.
It is a read-only eligibility observation, not a wire operation or
authorization to persist data. A later storage operation must rederive the
underlying eligibility facts inside its mutation gate; if it requires the
same session revision, it must validate a separate freshness revision there.
The plan intentionally contains no result text.

`plan_compaction_prefix` is a read-only planning query for a later summary
operation. It selects the longest oldest prefix of complete turns that fits
both explicit source-event and source-message JSON UTF-8 byte budgets, while
retaining at least the requested number of recent turns. Each budget is capped
at 1 MiB so the source digest stays within the portable SHA-256 helper's bound.
It accepts only settled, closed, non-imported, non-fork-related sessions. A
missing prefix returns `None`; invalid budgets or unsupported session state
return an error. The result contains contiguous event sequence bounds, the
expected event count, and SHA-256 digests of both the exact source event array
and exact projected message array. The message digest binds the session-wide
tool-result pruning projection, including later prune events outside the
selected range. A plan is advisory input, not authorization or proof that a
future mutation still has fresh inputs; any mutation must replan and compare
both digests and the event count inside its own candidate transaction. The plan
returns no transcript text, starts no provider or tool effect, and leaves
queued effects and the snapshot unchanged. Its byte counts exclude the future
compaction instruction and summary output; they are not token counts,
provider-wire sizes, or context-window guarantees. The query does not archive
or replace history and does not increase storage capacity.

`prepare_compaction_summary_candidate` re-plans with the same explicit options
and compares every plan field, including `source_events_sha256` and
`source_messages_sha256`, before binding caller-supplied summary text to the
fresh plan. It measures the serialized JSON string against the caller's summary
byte limit, capped at 1 MiB. A stale plan, missing prefix, or oversized summary
returns an error. The result is an in-memory candidate envelope with the exact
fresh plan and planning options; it does not append events, replace or archive
history, enqueue provider/tool/hook effects, or survive restore. A later
mutation must repeat the freshness check inside its own transaction. This
candidate API does not implement summary generation, storage reduction, or a
durable quota.

The v2 engine slice can verify a canonical `dsh.tool-result-archive-object-v2`
text object, produce a compact candidate snapshot, commit that same projection
to in-memory state, and reopen a v2 snapshot when the caller supplies every
verified source object. Candidate generation does not mutate the live engine;
commit is an in-memory operation and is not a durable checkpoint. The engine
rehashes UTF-8 content, projection, and canonical object payload with portable
SHA-256. The runtime codec also uses the host system SHA-256 adapter, so each
boundary verifies the object independently.

The engine enforces at most 256 objects, at most 65,536 bytes per original or
projection, at most 1 MiB per encoded object, and 16 MiB aggregate limits for
original and projected bytes. A separate 7 MiB hydration-expansion limit and
the exact 16 MiB JSON copy budget account for original text appearing in the
completion, result, and transcript during restore. Candidate, commit, and
restore apply the same admission check so a live snapshot accepted for archive
cannot exceed the engine's reopen budget. The engine-only test covers six
sequential 63 KiB results in one session and a completed next turn after
reopening; this does not prove a native store capacity improvement.

The engine remains a pure in-memory package: it has no filesystem store, native
manifest, receipt transaction, or history endpoint. NativeRuntime connects the
candidate/commit/restore boundary to its v2 immutable object store and explicit
original-read API. Web history marks archive projections and can request the
original. CLI uses the marked projection. Legacy MCP history and ACP history/
event surfaces reject archived sessions rather than returning a projection as
original content. Ordinary engine snapshots remain v1; generic v1 restore
rejects archive markers, and v2 restore rejects forked/imported histories and
validates the complete historical Read/result/prune chain before compacting
it. Effects are never replayed on reopen.

The runtime protects the object directory with a 64 MiB / 2,048-entry quota,
including temporary and orphan files, and bounds the outer snapshot to 32 MiB.
The engine's separate 256-object, 16 MiB original/projection, 7 MiB hydration
expansion, and 16 MiB JSON-copy limits still apply.

Portable MoonBit SHA-256 keeps the pure engine independent of platform C and
native crypto providers. The native codec also uses the host system SHA-256
adapter and independently checks the same UTF-8 object identity at storage and
restore boundaries; the two implementations are tested against standard
padding and Unicode vectors. This does not establish power-loss durability on
every filesystem.

| Operation | Input |
| --- | --- |
| `session_create` | Optional `id`, `title`, `system_prompt`, `max_steps` |
| `session_import` | `jsonl` containing an upstream Session v4 archive; returns a read-only history |
| `session_list` | `{}` |
| `session_get` | `session_id` |
| `session_send` | `session_id`, nonempty `prompt` |
| `session_cancel` | `session_id` |
| `tool_approve` | `session_id`, exact `call_id`, boolean `approved` |

Session views contain `id`, `title`, `system_prompt`, `max_steps`, `status`,
`turn_id`, `step`, `events`, and `messages`. A waiting session also has
`pending_approval: {call_id, name, arguments}`. `session_list` returns an array
in creation order. Terminal sessions accept a follow-up prompt as a new turn;
running and approval-waiting sessions reject overlapping prompts.

`project_stream` records bounded text/reasoning batches only for the exact live
LLM effect. An unfinished projection appears in `messages` as one assistant row
with `provisional: true`, `stream_status: "writing"` and its `turn_id` / `step`.
Failed, cancelled and interrupted attempts keep the row with
`stream_status: "partial"`; a matching final assistant message replaces it in
the transcript. `stream_revision` increases with projected UTF-16 units so a
browser can reject an older poll even when the event count has not changed.
These provisional rows are presentation-only and never enter a later provider
request. Successful completion must match the accumulated projection, and
restore replays the delta events without reissuing effects. Older
`dsh.mbt-session-v1` snapshots without `stream_revision` remain accepted.

`provider_context_measurement(session_id)` reads the exact active engine request,
including its current message projection and tool schemas, without consuming
the effect queue. It reports UTF-8 bytes for the serialized engine request,
messages array, and tool-schema array, system-prompt UTF-8 bytes and code points,
and message/tool counts. Each serialized measurement is capped at 16 MiB. These
are request-size measurements before provider-specific wire conversion. The
bounded walk rejects nesting beyond 128 levels, more than 16,777,216 visited
JSON values, invalid unpaired surrogates, and serialized components over 16 MiB.
The measurements do not estimate tokens, report a model context window, or
trigger compaction. A missing active provider effect returns `None`.

`session_send.max_provider_request_utf8_bytes` optionally enforces a per-turn
ceiling from 1 byte through 16 MiB. The engine measures each constructed request
before `emit_effect`; an over-limit or unmeasurable request closes the turn with
reason `provider_request_limit` and does not create a provider effect. The limit
is recorded in `turn/start`, so restoring an approval-waiting turn retains it.
The unit is serialized engine-request UTF-8 bytes before provider-specific wire
conversion; this is not a token count or model-window guarantee. It does not
change durable session/event capacity or automatically prune history. Tool or
hook outcomes already admitted before a later request is rejected remain subject
to the existing durable session-capacity rules.

Each tool descriptor has `name`, `description`, an object `input_schema`, and
`effect: "read" | "write" | "shell"`. Read effects start automatically. Every
write or shell call requires its own affirmative approval. The reserved
`effect: "session"` is accepted only for the canonical built-in `todo_write`
tool; the engine applies it internally at the tool barrier without dispatching
a host tool effect or running host Pre/PostTool hooks. Denial, unknown tools,
invalid JSON arguments, and input schema failures produce paired tool errors,
then allow the next model step to decide how to recover.

The initial schema validator supports object/array/string/number/integer/boolean/
null types, `required`, `properties`, `additionalProperties: false`, `enum`, and
`items`. Tools must validate their own path, process, and application-specific
constraints in the host. This is not a complete JSON Schema implementation.

## Effects and settlement

An effect is `{id, kind: "llm" | "tool", session_id, request}`. A model request
contains `{system, messages, tools}`. A tool request contains
`{name, arguments, call_id}`. Model and tool results use the shared completion
contract documented by the application host.

Consecutive calls with static `effect: "read"` classification execute in a
rolling pool of at most four effects. The host checkpoints the whole admitted
batch before starting I/O. Completion events correlate each result with its
call and effect identity, while committed tool results and later model context
remain in original model-call order even when reads finish out of order. The
limit is four for this port; upstream defaults to ten. Write and shell calls are
single-call approval barriers. Unknown tools and invalid arguments also wait
for a preceding read group to drain before recording a local error.

Taking an effect removes it only from the outgoing queue, not from outstanding
work. Unknown, duplicate, stale, or malformed completion attempts return `Err`
without partial mutation. Cancellation retires all active IDs, stops pool
refill, preserves durable successes already accepted by the engine, records
errors for unfinished or unstarted calls, and closes the turn. It cannot
physically stop host I/O; the host must abort each owned operation as well.
Late results cannot advance the cancelled session or a later turn. Restore
closes an interrupted pool without replaying any read, and strict event replay
validates staged results before admitting the snapshot.

`length` preserves the truncated assistant answer and closes the turn as failed
with `max_tokens`. The model-step budget is enforced before another model effect
is emitted. A failed provider request records an attempt, not a fabricated
assistant answer.

## Persistence and ownership

The snapshot schema is **`dsh.mbt-session-v1`**, not upstream Session v4. It
contains the effect and session counters plus full session views. Restore checks
the schema, unique identities, contiguous event sequences, turn/step boundaries,
request and tool/result correlation, stream effect identity/finality and
agreement between projected messages and logged events before atomically
replacing an idle engine.

Restoring `running` or `awaiting_approval` work records an explicit interruption,
settles remaining calls with error results, and marks the session failed. It
never reissues a persisted effect. A host may accept a fresh follow-up prompt
after showing the interrupted outcome. An engine with live work refuses restore.

Every JSON input and output collection is copied. Callers cannot change tool
policy, request arguments, or durable history through an alias. Ingress rejects
cycles/excessive depth, non-finite numbers, more than one million JSON nodes, or
more than 16 Mi UTF-16 code units of aggregate text. Other bounds include 32
sessions, 128 tools, 16 calls per model step, 1–64 steps per turn (default 16),
16 Ki prompt characters, 64 Ki response/tool argument/result characters, and
32,768 events per session.

Each canonical session view, including its events and derived messages, is
limited to **262,144 serialized UTF-16 code units**. The fixed optional
`todos: null` metadata field is excluded from this admission count so snapshots
created before the field existed remain restorable; non-null todo arrays count
in full, and the field remains present in current API and storage JSON.
Mutations execute against a candidate copy and commit only when both the
current view and its possible interrupted closure fit. An oversized send or
approval leaves the original session unchanged. An oversized model/tool
completion closes the original step as `failed` with reason `session_capacity`,
emits no candidate effects, and keeps its previously admitted history
reloadable. Start a new session when this limit is reached. This deliberate
initial-port bound also keeps all 32 session views within the application's
snapshot and API transport limits.

`session_import` is a separate, explicit path for a bounded Session v4 event
subset. It retains the v4 header and raw source lines inside the v1 snapshot,
projects basic messages/tool lifecycles, inbox splices, first-level fork
closures, selected developer/header updates, current-surface replacements,
compaction checkpoints/pruning, diagnostic assistant attempts, skill catalog
provenance, unresolved image references, and correlated PTC/subagent/foreground
workflow metadata, then re-decodes the source during every restore. Image data
is absent from JSONL and remains an inert placeholder; background workflow
events and unsupported attachment fields remain outside the accepted subset.
The imported state is read-only: sending and canceling are rejected, the browser
disables its composer, and no provider, tool, permission preset, or approval
policy is activated. Spill/offload, retry scheduling lifecycle, unsupported
execution-family events, and nested forks still fail import explicitly. Engine
JSONL input is capped at 262,144 UTF-16 code units; the CLI additionally caps
source files at 1 MiB. The checked-in integration catalog imports and reopens all
25 unmodified upstream Session v4 snapshots; this does not imply runtime feature
parity.
Restore also recognizes an exact older transcript projection for archives in
the original append-only subset, then stores the current canonical projection.
Any partial, reordered, or otherwise modified projection remains an error.
Claimed inbox messages that never became a model-visible `user/message` remain
visible in `pending_inbox.unadmitted_turn` or `unadmitted_step`; they are not
requeued or executed.

## Upstream basis and verification

Behavior is distilled from DeepSeek Harness commit
`5badb15009ae1756c3afe0ae0cef1faafc290ccc`, especially
`packages/core/agent-loop`, `packages/core/session`, `packages/core/tools`, and
`snapshots/session/tool-call-turn/session.v4.jsonl`. Parallel dispatch semantics
follow that revision's [tool-calls.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/core/agent-loop/src/tool-calls.ts)
and [implemented parallel-execution note](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/.agents/notes/implemented/feature/2026-07-10-parallel-tool-call-execution.md).

The focused tests cover the bash/result/DONE transcript, model history
reconstruction, bounded rolling reads, out-of-order completion, write barriers,
required approvals and denial, malformed/unknown tools, step/token limits, busy
admission, provider errors, duplicate and late results, cancellation,
capacity closure, interrupted restore, input ownership, and forged snapshot
rejection. Run:

```sh
moon test --target js -p f4ah6o/dsh/engine
moon test --target native -p f4ah6o/dsh/engine
```

Cordis/npm plugin loading, automatic Session v4 restore migration and v4 writing,
v0–v3 migrations, configurable/dynamic parallel-safety policy, retry policy, live compaction/context
management, spill/offload, attachment replay, subagents, and durable inbox
editing are not implemented by this engine. The explicit v4 importer accepts only the
documented subset above; it is not full upstream compatibility.
