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
Engine::snapshot() -> Json
Engine::restore(snapshot : Json) -> Result[Unit, String]
```

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

Each tool descriptor has `name`, `description`, an object `input_schema`, and
`effect: "read" | "write" | "shell"`. Read effects start automatically. Every
write or shell call requires its own affirmative approval. Denial, unknown tools,
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

Calls execute sequentially in model order. Taking an effect removes it only
from the outgoing queue, not from outstanding work. Unknown, duplicate, stale,
or malformed completion attempts return `Err` without partial mutation.
Cancellation retires outstanding IDs, removes queued work, records error results
for unfinished calls, and closes the turn. It cannot physically stop host I/O;
the host must abort the owned operation as well. Late results cannot advance the
cancelled session or a later turn.

`length` preserves the truncated assistant answer and closes the turn as failed
with `max_tokens`. The model-step budget is enforced before another model effect
is emitted. A failed provider request records an attempt, not a fabricated
assistant answer.

## Persistence and ownership

The snapshot schema is **`dsh.mbt-session-v1`**, not upstream Session v4. It
contains the effect and session counters plus full session views. Restore checks
the schema, unique identities, contiguous event sequences, turn/step boundaries,
request and tool/result correlation, and agreement between projected messages
and logged events before atomically replacing an idle engine.

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
limited to **262,144 serialized UTF-16 code units**. Mutations execute against a
candidate copy and commit only when both the current view and its possible
interrupted closure fit. An oversized send or approval leaves the original
session unchanged. An oversized model/tool completion closes the original step
as `failed` with reason `session_capacity`, emits no candidate effects, and keeps
its previously admitted history reloadable. Start a new session when this limit
is reached. This deliberate initial-port bound also keeps all 32 session views
within the application's snapshot and API transport limits.

`session_import` is a separate, explicit path for a bounded Session v4 event
subset. It retains the v4 header and raw source lines inside the v1 snapshot,
projects basic messages/tool lifecycles, inbox splices and first-level fork
closures, then re-decodes the source during every restore. The imported state is
read-only: sending and canceling are rejected, the browser disables its
composer, and no provider, tool, permission preset, or approval policy is
activated. Unknown required semantics such as attachments, compaction, surface
replacement, developer header updates, retries, PTC/subagent workflows, and
nested forks fail import explicitly. Engine JSONL input is capped at 262,144
UTF-16 code units; the CLI additionally caps source files at 1 MiB.
Claimed inbox messages that never became a model-visible `user/message` remain
visible in `pending_inbox.unadmitted_turn` or `unadmitted_step`; they are not
requeued or executed.

## Upstream basis and verification

Behavior is distilled from DeepSeek Harness commit
`5badb15009ae1756c3afe0ae0cef1faafc290ccc`, especially
`packages/core/agent-loop`, `packages/core/session`, `packages/core/tools`, and
`snapshots/session/tool-call-turn/session.v4.jsonl`.

The focused tests cover the bash/result/DONE transcript, model history
reconstruction, sequential call ordering, required approvals and denial,
malformed/unknown tools, step/token limits, busy admission, provider errors,
duplicate and late results, cancellation, interrupted restore, input ownership,
and forged snapshot rejection. Run:

```sh
moon test --target js -p f4ah6o/dsh/engine
moon test --target native -p f4ah6o/dsh/engine
```

Cordis/npm plugin loading, automatic Session v4 restore migration and v4 writing,
v0–v3 migrations, parallel tools, stream deltas inside the engine, retry policy,
compaction, attachment replay, subagents, and durable inbox editing are not
implemented by this initial engine. The explicit v4 importer accepts only the
documented subset above; it is not full upstream compatibility.
