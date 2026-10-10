# Native runtime

The native executable is the sole product host. MoonBit owns CLI parsing,
session and provider behavior, HTTP/MCP service, browser behavior, persistence,
and tool policy. Narrow C FFI supplies operating-system primitives such as
no-follow filesystem operations, process creation, cryptographic primitives,
signals, and terminal detection; the audited boundary is listed in
[ffi-boundary.md](ffi-boundary.md). No Node.js or npm package is loaded by the
product build or runtime.

The macOS GPUI desktop app uses this same runtime for sessions, provider work,
tool approval, and persistence. See the [native desktop guide](desktop.md) for
installation, `dsh desktop` launch, local builds, and the current text-input
limitations.

Build the executable and all browser assets with the pinned MoonBit toolchain:

```sh
moon update
moon install
sh scripts/build.sh
moon run native --target native --release -- \
  web --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project --port 3210
```

`sh scripts/build.sh` also builds the installable `cmd/dsh` executable after refreshing `runtime/bundled_web.mbt`. The generated bundle contains the compiled MoonBit browser module and service worker, the pinned styles, `index.html`, the web manifest, and the icon. Both `moon install ./cmd/dsh` and release executables serve these assets from any working directory. Pass `--assets-dir PATH` only when an explicit filesystem asset override is needed; the directory is resolved at service startup.

The server binds only to `127.0.0.1`. The browser carrier uses the same durable command, receipt, snapshot, approval, and effect path as native clients.

For a credential-free offline check, add `--demo`:

```sh
moon run native --target native --release -- \
  web --demo --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project --port 3210
```

This mode uses a deterministic provider response, never reads provider API-key environment variables, and never makes provider network requests. Its first response requests an approved workspace write; the next response includes the tool result. The demo writes `native-demo.txt` inside the selected workspace.

The foreground CLI uses the same native runtime and checkpoints each command. In an interactive terminal, `run` asks before each write, edit, or shell operation. Noninteractive runs cancel and fail when a tool needs approval; use an explicit startup policy with `--approve-writes` or `--approve-tools`. Automatic shell approval requires both `--allow-shell` and `--approve-tools bash`:

```sh
moon run native --target native --release -- \
  run 'Create and verify a durable file.' --demo --approve-writes \
  --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project
```

## Workspace skills

Filesystem skills are opt-in. Pass `--enable-skills` to `run`, `web`, `mcp`, or
`desktop`; repeated `--skill-dir PATH` options add workspace-relative roots.
The runtime scans `.dsh/skills`, then `.agents/skills`, then up to eight custom
roots in the order supplied. The first valid skill with a duplicate name wins.
Each root supports direct `<name>.md` files and one-level skill bundles at
`<directory>/SKILL.md`. Discovery is sorted by skill name and fixed for the
runtime lifetime.

Each skill starts with `---` YAML frontmatter containing `name` and
`description`. The bounded scalar subset also accepts `whenToUse`,
`disable-model-invocation`, and `user-invocable`; invocation fields require
`true` or `false`. Unknown keys, duplicate keys, nested YAML, block values,
legacy camelCase invocation flags, and malformed frontmatter are ignored as
invalid skills. `whenToUse` is accepted but is not shown in the model catalog.
Names use lowercase kebab case. Files are limited to 65,536 bytes, instruction
bodies to 60,000 bytes, descriptions to 4,096 characters, and each root to
1,024 entries. The catalog admits up to 64 valid skills and up to 16
model-invocable skills; catalog summaries are normalized, escaped, and capped
so the provider tool descriptor stays within the engine's 4,096-character
limit.

The provider-facing `skill` tool appears in the tool schema for every native
provider mode when skills are enabled. It lists summaries for model-invocable
skills only. The host rereads a requested skill with no-follow workspace file
access, verifies the discovered name still matches, and rechecks the current
model invocation policy before returning its full body. The result includes a
stable source label and is limited to the normal 64 KiB tool-result budget;
oversized instructions fail with an error rather than being truncated. The
tool is classified as read-only and does not need approval.

A user's first prompt token may directly invoke a user-enabled skill as
`/name`. The host appends a canonical skill block and a `skill-invocation`
provenance marker to that user message before checkpointing it. Unknown names
and skills with `user-invocable: false` remain ordinary prompt text. Skills
with `disable-model-invocation: true` are omitted from the tool catalog and
refused by the model loader, while remaining directly invocable by the user
unless separately disabled. Direct expansion is limited to 16,384 UTF-16 units
including the original prompt and rendered skill body; larger model-invocable
skills can be loaded through the `skill` tool, while user-only skills must be
shortened.

The catalog is a static provider tool description rather than an upstream
durable catalog message. Root changes are picked up after restarting the
runtime; there are no file watchers, live catalog replacement, user-home or
bundled roots, URL resources, runtime-registered skills, or full YAML/metadata
support. Skill bodies are treated as prompt instructions and referenced
resources are not loaded automatically. The loader does not execute skill
scripts or load npm/Cordis plugins.

Keep `--enable-skills` enabled when reopening a store that contains skill tool
calls: the engine validates historical tool calls against the registered tool
catalog, so disabling the tool prevents that store from restoring. Completed
skill results and their source labels are stored in the session history, and
cancelled direct invocations keep the already-checkpointed user message.
Ordinary stores without skill calls can be opened with skills enabled.

## Foreground subagents

Pass `--enable-subagents` to `run`, `web`, `mcp`, `acp`, or `desktop` to expose
the native `subagent` tool. It starts a fresh child engine for one foreground
task, waits for it to finish, then returns its bounded JSON result to the
parent turn. The child uses the same configured provider, model, and auth
route as the parent, but starts with only the delegated prompt rather than the
parent transcript. For example, the keyless demo exercises the complete
parent → child → workspace read → parent path:

```sh
dsh run 'Inspect the first line of README.md and report it.' \
  --enable-subagents --demo \
  --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project
```

Each child gets at most three model steps, eight dispatched workspace tool
calls, and 90 seconds. At most two subagent calls can be made in one parent
turn, and one child runs at a time in a native runtime. The prompt is limited
to 4,096 UTF-16 code units and the description to 128. The result is valid
JSON capped at 16,384 UTF-16 code units; it includes the child ID, parent
session/effect/tool-call identities, terminal status, bounded failure reason,
step/tool counts, and up to 16 transcript messages. This limit measures
UTF-16 code units, not bytes.

The child tool catalog contains only `read`, `glob`, and `grep`; attempts to
write, run shell commands, call MCP/LSP/skills, or recurse into another
subagent fail as unknown child tools. Those file tools reuse the parent's
SafeRoot and protected runtime-store checks. The child inherits configured
PreToolUse / PostToolUse command hooks. Hook commands are trusted host code
and can have side effects even when the child requested a read; the restricted
tool catalog is not an OS sandbox. A child cannot add tools or widen the
parent's configured tool policy.

The settled JSON result is stored in the parent session's ordinary tool result.
Reopen a store containing subagent calls with `--enable-subagents`; the engine
validates historical calls against the startup tool catalog. Restore reads
the saved result and issues no child provider or workspace requests. Child
sessions are not separately persisted or resumable: if parent cancellation,
timeout, or process interruption happens before the result settles, the
partial child transcript is not retained, and interrupted work is never
replayed. Keyless demo and local fake-provider tests cover child execution,
policy limits, cancellation, correlation, and restore; no live provider
account smoke is claimed.

This is a bounded foreground subset of the pinned upstream
[`tool-subagent`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/subagent/tool-subagent)
and in-process spawn packages. It does not implement background or
continuable children, child session listing / resume, independent child
provider selection, configurable tool filters / personas / output schemas,
or full upstream provider and lifecycle parity.

## External MCP stdio tools

`run`, `web`, `mcp`, and `desktop` accept `--mcp-config PATH` to start configured
MCP servers over newline-delimited JSON-RPC on stdio. The config is read only at
startup. A minimal file looks like this:

```json
{
  "servers": [
    {
      "name": "docs",
      "command": "/absolute/path/to/mcp-server",
      "args": ["--stdio"],
      "cwd": "/absolute/path/to/project",
      "env": { "SERVICE_TOKEN": "DOCS_SERVICE_TOKEN" },
      "toolCallTimeoutMs": 60000
    }
  ]
}
```

`name`, `command`, and `args` identify a server process; `cwd`, `env`, and
`toolCallTimeoutMs` are optional. The default working directory is the selected
workspace, and the default call timeout is 60 seconds. The `env` object maps
child variable names to names of variables already present in the host
environment. It never contains secret bytes. The child receives a small
baseline environment (`PATH`, `LANG`, `LC_ALL`) plus only those explicit
mappings; stderr is discarded. Commands are executed directly with argv, not
through a shell. Because an MCP server runs with the current user's operating
system privileges, configure only servers you trust.

Each discovered tool is exposed as `mcp__SERVER__TOOL` (with a stable suffix
when normalization or length limits require one). Calls are serialized per
server. Calls require explicit approval by default, including tools whose
server claims they are read-only. Foreground `dsh run` may auto-approve an exact
external name only when it is listed with `--approve-tools
mcp__SERVER__TOOL`. Text results are projected into the conversation;
image and audio content is omitted. The runtime accepts object input schemas
using `type`, `properties`, `required`, boolean `additionalProperties`, `items`,
and `enum`, plus bounded `$schema`, `$id`, `title`, `description`, `default`,
`examples`, `deprecated`, `readOnly`, and `writeOnly` annotations. Unsupported
schema keywords and tools requiring MCP task execution are rejected during
startup.

The config supports up to 8 servers and 64 tools total. It and the child
environment values are not written to the native data directory. The store
records a fingerprint of the discovered tool names, descriptions, and schemas
so persisted calls are only restored against the same catalog. Keep that
catalog stable and pass a matching `--mcp-config` on every later open, including
when reopening from `web` or the desktop app. A mismatch is rejected before the
stored engine is adopted. Native-only data created before this feature can
adopt its first catalog if it contains no historical `mcp__` tool calls.

If stdio fails, the server exits, the request times out or is cancelled, or the
server sends malformed JSON-RPC after a `tools/call` was sent, the result says
the remote outcome is unknown. The failed connection is closed and the call is
never replayed after reopening the session. A complete JSON-RPC response with
`isError: true` or invalid MCP content is treated as a known server/tool-result
error.

For example, start a local browser service and a foreground CLI session with
the same config:

```sh
moon run native --target native --release -- \
  web --mcp-config /absolute/path/to/mcp.json \
  --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project

moon run native --target native --release -- \
  run 'Find the relevant documentation.' \
  --mcp-config /absolute/path/to/mcp.json \
  --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project
```

## Native session todo tool

Every native provider mode exposes `todo_write`. It replaces the session's
complete visible task list using `{"todos":[{"content":"...","status":"pending"}]}`.
Content is trimmed, must be non-empty and unique, and statuses are `pending`,
`in_progress`, or `completed`. The native port allows at most 64 items, 512
UTF-16 code units per item, 8,192 code units in total, and one `in_progress` item.
The tool result reports counts for each status.

The list is session state recorded by a durable `todo/write` event linked to
the model call and its successful tool result. It is a whole-list replacement;
the latest write in a turn is shown. The projection starts as `null`, clears
when the next turn begins, and remains visible after the assistant finishes.
Forks carry the validated history and current list. Browser and native desktop
transcripts render the same checklist, and the session API exposes it as
`todos`.

This is an internal session update with no workspace, filesystem, or network
capability and no approval prompt. The engine completes it at the exclusive
tool barrier: earlier parallel reads settle first, and following writes still
wait for approval. It does not create a host tool effect, so PreToolUse and
PostToolUse command hooks do not run for `todo_write`. Imported Session v4
histories remain inert and do not acquire a native todo projection. Stores
from 0.1.7 that recorded `Unknown tool: todo_write` remain readable; opening
them does not retry the old call. Histories containing native `todo/write`
events require dsh 0.1.8 or later. Keep a pre-upgrade data-directory backup if
you need to downgrade.

## Native LSP navigation

`run`, `web`, `mcp`, `acp`, and `desktop` accept `--lsp-config PATH`. This
explicitly enables the `lsp` tool and starts configured local language servers
over Content-Length framed JSON-RPC on stdio. Without this option, the tool is
not registered. The top-level `servers` object maps stable server IDs to
server settings:

```json
{
  "servers": {
    "typescript": {
      "command": "/absolute/path/to/typescript-language-server",
      "args": ["--stdio"],
      "env": { "PATH": "PATH" },
      "extensionToLanguage": {
        ".ts": "typescript",
        ".tsx": "typescript"
      },
      "toolCallTimeoutMs": 60000
    }
  }
}
```

Start a foreground session with this file by passing the config path explicitly:

```sh
dsh run 'Find the definition of the selected symbol.' \
  --lsp-config /absolute/path/to/lsp.json \
  --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project
```

The config accepts 1–8 named servers and 128 extension mappings total. Each
server needs a nonempty `extensionToLanguage` map; each extension can route to
only one server. The map keys are file suffixes such as `.ts`; values are LSP
language IDs. `args`, `env`, `initializationOptions`, `configuration`,
`settingsRevision`, and `toolCallTimeoutMs` are optional. Unknown fields are
rejected. A config file is limited to 1 MiB; a server accepts at most 128
arguments (4,096 characters each, 32 KiB combined) and 64 environment mappings.
Settings JSON is limited to 24 levels, 65,536 nodes, and 1 MiB of string
content. The default routed-call timeout is 60 seconds; `toolCallTimeoutMs`
accepts 100–300,000 milliseconds.

`command` and `args` are launched directly as argv, without a shell. The
runtime starts one server process lazily for each configured server ID,
serializes its requests, and uses the selected workspace as its working
directory. The server receives a small fixed environment (`PATH`, `LANG`, and
`LC_ALL`) plus only explicit `env` mappings; it does not inherit other host
variables. Each mapping uses a child variable name as its key and the name of a
host environment variable as its value. Config files store the host variable
name, and the runtime looks up its value when the server starts. The host
variable must be set at that point. Server stderr is discarded.

`initializationOptions` and `configuration` are passed to the LSP server and
may contain sensitive settings. Their values are not persisted or included in
the catalog fingerprint. If either field is non-null, set `settingsRevision`
to a stable, nonsecret identifier, and change it whenever either settings
payload changes. The runtime cannot compare mapped environment values, so set
and change the revision when a change to those external values affects server
behavior. The native store binds LSP tool history to the configured
catalog, including server IDs, commands, arguments, environment-variable
names, extension routes, timeout, settings revision, and the native worker
resource-limit policy. Server IDs and
mapping keys are canonicalized before the catalog fingerprint is calculated.
Reopen a store with the matching config; a store without an earlier LSP
catalog can adopt its first config only if it has no historical `lsp` calls.
Pass `--lsp-config PATH` to every command that opens a store with a bound LSP
catalog, including tool approval/denial, import, pruning, fork, and auth/model
management actions, as well as `run`, service, and desktop startup.
The optional fingerprint is a small field in the existing native snapshot.
LSP calls and results use the existing session history capacity; LSP does not
increase that limit. Use dsh 0.1.7 or later for stores that contain LSP calls.

Each `lsp` call accepts an operation (`goToDefinition`, `findReferences`,
`goToImplementation`, or `hover`), a workspace-relative `file_path`, and
one-based `line` and `character` positions measured in UTF-16 code units. A
reference query includes the declaration. Before starting a worker, the host
checks the selected file against the workspace SafeRoot, rejects symlinks and
protected runtime-store files, reads a regular UTF-8 source file, and validates
the requested position. Source files are limited to 4 MiB. The server must
negotiate UTF-16 positions, support transient document open/close, and advertise
the requested operation. For each query the host reads the current source,
sends `textDocument/didOpen`, the operation request, and `textDocument/didClose`;
it does not keep an editor buffer or send `didChange` updates.

Definition, reference, and implementation results are normalized to bounded
workspace-relative file locations. Locations outside the workspace, non-local
URIs, and paths that cannot be resolved as safe workspace files are omitted.
These operations return at most 100 locations and 16,000 characters; hover
returns bounded text with the same character limit. Incoming server JSON-RPC
message bodies are limited to 4 MiB, headers to 64 KiB, JSON nesting to 32
levels, and queued messages to 64. Incoming server requests/notifications
while awaiting a response are limited to 64. `toolCallTimeoutMs` covers the
routed call after CLI config checks and
initial workspace path/extension routing: waiting for that server's serialized
slot, SafeRoot source reread and position validation, lazy startup and
initialize, `didOpen` / request / `didClose`, and result projection. Worker
startup also has a separate 10-second cap. On Linux, each worker has an 8 GiB
virtual address-space cap (not an RSS limit); Darwin does not currently enforce
a hard worker memory cap. The worker CPU-time limit is 3,600 seconds. Graceful
shutdown has a two-second budget per worker, including waiting for its
serialized slot, the LSP `shutdown` request, the `exit` notification write, and
process exit. If that phase fails or expires, the host escalates process-group
termination, allowing up to 500 milliseconds after `TERM` and one second after
`KILL` before closing pipes. Shutting down a pool with multiple servers can
take longer than one worker's graceful budget.

The `lsp` tool is classified as a write effect because a configured server is
trusted host code, so each call needs approval by default. Foreground `dsh run`
can auto-approve it only when `lsp` is explicitly listed in
`--approve-tools`, for example `--approve-tools lsp`. Cancellation, timeout,
malformed protocol data, or disconnect poisons and stops the server process
group. The failed call is never retried or replayed. A later independent,
approved call can evict the poisoned worker and start a fresh one. Injected
environment values, settings payloads, raw JSON-RPC error bodies, and server
stderr are not logged or directly persisted. Returned LSP content is saved as
a tool result and shown to the model, so configure only servers you trust.

The workspace path checks constrain which source files the host reads; they do
not sandbox a configured server's host authority. The worker is trusted local
code and runs without an operating-system sandbox. Use only server commands
you trust.

The keyless fake-server tests exercise protocol and failure behaviors. On
2026-10-10, the optional local macOS host check succeeded against its installed
`/usr/bin/clangd`, resolving a C definition. This is narrow single-server
evidence, not cross-language, Linux/V8, or live-provider acceptance. The
example above documents the config shape; this is a bounded navigation subset
of the pinned upstream `packages/lsp`, `packages/lsp/lsp-stdio`, and
`packages/lsp/tool-lsp`, not complete LSP or Cordis compatibility. It does not
support remote servers, dynamic providers, hot reload, `didChange`, diagnostics
UI, or workspace edits. Upstream connection pooling and its retry-once
behavior are not implemented; a failed request has no transparent retry. The
keyless fake-server tests use Python 3, which is a test-only prerequisite and
not a product runtime dependency.

## ACP stdio agent

`dsh acp` exposes the native runtime as an ACP v1 agent over newline-delimited
JSON-RPC on stdin and stdout. Start it from an ACP-compatible editor, or use
the native executable directly for an offline smoke test:

```sh
dsh acp --demo --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project
```

Without `--demo`, provider setup follows the native runtime environment and
options described above. The agent advertises session list, resume, and close
capabilities, no image, audio, or embedded-context prompt capabilities, and no
authentication methods. It accepts `initialize`, `authenticate`,
`session/new`, `session/list`, `session/resume`, `session/set_config_option`,
`session/prompt`, `session/cancel`, and `session/close`. A connection can be
initialized once with protocol version 1. The pinned upstream baseline also
lists `session/load` as unsupported ([upstream ACP scope](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/README.md));
this port does not add a load extension.

`session/new` and `session/resume` return a `model` select option in
`configOptions` when a startup model or account-visible selected model is
available. An unauthenticated ChatGPT route or one without a selected visible
model returns an empty `configOptions` array. The option's current value and
choices identify the configured provider route and model.
`session/set_config_option` changes that model for
one ACP session and persists the selection. It is accepted only while that
session is idle or settled; an active turn rejects the change, so every step
and retry in an admitted turn keeps its selected model. Other ACP sessions
and the host's shared provider selection are unaffected. Native foreground
subagents inherit the parent's selected model. This follows the pinned
upstream [`model-control.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/model-control.ts)
and [`session.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/session.ts)
model selection surface; the native port keeps its startup provider/auth route fixed.

ACP reserves stdout exclusively for JSON-RPC. Invalid ACP arguments and fatal
startup, carrier, or shutdown failures write a fixed diagnostic to stderr and
exit nonzero; they never print a runtime panic into the protocol stream. If a
durable checkpoint fails, the request returns a JSON-RPC error without a
`config_option_update`; the stopped runtime rejects subsequent operations, and
the fatal shutdown diagnostic remains on stderr.

The current startup route remains fixed: model selection does not switch
provider protocol or authentication route. For an API-key route,
`DSH_ACP_MODELS` adds selectable model names to the startup model. For a
ChatGPT route, choices come from the account-visible catalog; setting
`DSH_ACP_MODELS` restricts that catalog while retaining the currently selected
visible model. Set the variable to a strict JSON array of unique, nonempty
strings, for example `DSH_ACP_MODELS='["gpt-4.1","gpt-4.1-mini"]'`.
The input is limited to 16 KiB, 32 models, and 256 characters per model name.
Malformed values reject ACP initialization. The offline demo route does not
accept additional model names.

ACP model and a non-secret route fingerprint are stored in native session
metadata. The fingerprint binds provider protocol, auth mode, demo route, and
the provider-normalized API root (origin and path prefix) without storing the
raw URL. Equivalent roots such as an omitted `/v1` or trailing slash share a
fingerprint. Credentials and account
identity remain host-managed and are not copied into ACP metadata; a resumed
turn uses the currently configured account or API key. Within an admitted turn,
the provider selection's account and generation checks still fence retries.
A resumed session must match the saved route fingerprint and its model must
remain in the current catalog; otherwise resume is refused without changing
session activity or history. Keep the same
`DSH_ACP_MODELS` choices when reopening a session that selected an added
model. dsh 0.1.10 stores without an ACP model selection adopt the current
startup model on resume.

Each ACP session is bound to the one canonical workspace selected at startup.
`session/new` and `session/resume` require an absolute `cwd` matching that
workspace and an empty `mcpServers` array; other working directories,
additional directories, and ACP-provided MCP server mounts are rejected.
Existing `--mcp-config` and hooks configuration still apply as startup
settings. `session/list` optionally filters by a canonicalized `cwd`; absent
or `null` `cwd` and `cursor` values are treated as omitted, while other
non-string values are rejected. It uses bounded pages of 16 entries. Its
cursor is bound to the current native store revision, so a committed change
invalidates earlier cursors. Listing is read-only and returns only
ACP-registered, non-imported root sessions, newest ACP activity first. Prompt
batches preserve order and accept text
and `resource_link` blocks; a resource link is rendered as a bracketed name
and URI in the prompt, and the referenced resource is not fetched. Images,
audio, embedded context, and other content blocks are rejected. The prompt is
limited to 16,384 characters, 64 blocks, and the same bounded JSON parser used
by the ACP transport. Incoming lines are limited to 1 MiB and JSON container
nesting to 24 levels.

The ACP registry is stored beside the native session snapshot and records each
session's canonical workspace and last ACP activity. `updatedAt` is returned
when the host clock supplies a valid UTC timestamp; it means the last
ACP-managed creation, prompt, approval, cancellation, close, or resume activity,
not arbitrary activity made later through other native interfaces. Ordering
uses the persisted ACP activity order, then creation order; native events are
not reinterpreted to invent timestamps. The current ACP registry belongs to
the single startup workspace, so reopening this data directory requires that
same canonical workspace. Older native envelopes without ACP provenance still
open, but their sessions are not inferred from an `acp-` ID or adopted into
ACP list/resume. Use dsh 0.1.11 or later to preserve ACP model selections and
route identity; an older native reader may ignore the added metadata and later
rewrite the envelope without it. Back up the data directory before downgrading.

`session/resume` attaches an inactive, non-imported root session to the new
connection. A session already attached to the current connection must be
closed before it can be resumed again. It rejects unknown or unregistered
sessions, active or busy work, forks, imported history, and workspace
mismatches. Resume restores saved native context without emitting old
`session/update` messages or replaying provider, tool, or approval effects; a
new prompt continues from that context. Closing a connection session keeps its
durable ACP registration for a later list or resume.

When a native tool needs approval, the agent emits a generic `tool_call` update
before requesting an explicit `allow-once` or `reject-once` decision. Unknown,
stale, malformed, and cancelled decisions fail closed. It emits only committed
assistant message / thought chunks and committed tool lifecycle updates; raw
provider stream deltas stay private. Cancellation, session close, and stdio EOF
durably cancel outstanding native work and drain its task before the service
returns. Restoring the native store retains the committed outcome and does not
replay an interrupted provider request or tool call.

This is a bounded agent-service increment, not full upstream ACP parity. It
does not support multi-workspace sessions, client-mounted MCP servers,
resource fetching, attachments, streaming deltas, persistent permission
grants, provider switching, or reasoning controls. Keyless tests cover model
catalog validation, per-session routing, busy-change rejection, retries,
subagent inheritance, restart / resume, and no-replay alongside list
pagination, workspace / provenance rejection, approval lifecycle, and
cancellation; they do not claim a live provider-account smoke test.

## Native command hooks

`run`, `web`, `mcp`, and `desktop` accept `--hooks-config PATH`. This is an
explicit opt-in to running trusted shell commands as the host user. The same
option works when launching the desktop app with `dsh desktop`; use an absolute
config path there because LaunchServices may choose a different process launch
directory. For CLI and service commands, a relative config path is resolved
from the process launch directory, independently of `--workspace`. Hook
commands themselves run with the selected workspace as their working
directory.

The config may contain a top-level `hooks` object, or put these events at the
root. Only command-based `PreToolUse` and `PostToolUse` groups are supported:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "write|edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}/scripts/check-write.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__docs-server__lookup",
        "hooks": [{ "command": "/absolute/path/to/audit-hook" }]
      }
    ]
  }
}
```

The `matcher` is an exact tool name, `*` for every tool, or literal names
separated by `|`. Tool names may contain letters, digits, `_`, and `-`, which
covers public MCP aliases. Regex and partial wildcards such as `write.*` are
rejected. An omitted matcher applies to every tool. Each event accepts at most
16 groups and 32 commands; each command is limited to 8,192 characters. The
config is limited to 64 KiB. `timeout` is an integer number of seconds from 1
to 120, defaulting to 10 seconds (upstream allows longer waits). Each hook
receives one JSON object on stdin, limited to 64 KiB. Stdout and stderr are
captured independently up to 16 KiB each; overflow is treated as an unsupported
result.

The payload includes `session_id`, an empty `transcript_path`, the canonical
workspace `cwd`, `hook_event_name`, `tool_name`, `tool_input`, and
`tool_use_id`; PostToolUse also includes the string `tool_response`. Pass data
through stdin rather than interpolating tool input into command text. The child
gets only `PATH`, `LANG`, `LC_ALL`, and `CLAUDE_PROJECT_DIR`; it does not inherit
provider credentials or the rest of the host environment. Quote workspace
paths in shell commands as `"${CLAUDE_PROJECT_DIR}"`.

PreToolUse runs after the engine has recorded the call and received any
required explicit approval. A hook's `allow` result never approves a tool or
overrides the engine's approval gate. Exit status 2 denies and uses stderr as
the reason. On exit status 0, the supported structured results are top-level
`decision: "block"` / `"approve"` and matching
`hookSpecificOutput.permissionDecision: "allow"` / `"deny"`; exit codes other
than 0 or 2, spawn errors, and timeout are nonblocking. A structured `ask`
cannot open a new approval prompt at this point and is rejected safely.
PostToolUse runs after the tool has acted; a deny or malformed response marks
the result as an error but cannot undo a write or remote call. If cancellation
or shutdown stops PostToolUse after the tool completed, the known result is
checkpointed and settled without replay.

PostToolUse also accepts `hookSpecificOutput.additionalContext` as a string.
Empty strings are skipped and whitespace-only strings are retained. Each value
is limited to 4,096 UTF-16 code units; at most 32 values and 16,384 aggregate
code units may be accepted for one tool call. A completed call stores the
contexts in one separate `user/message` event with source
`hooks-claude-code` and one text block per matching hook, in hook order. For
parallel calls, every correlated tool result is committed before context
messages are appended in tool-call order. The next provider request therefore
retains the upstream ordering without weakening the provider's adjacent-result
validation.

An empty context array is omitted from the completion event. A PostToolUse
block still returns the native tool-error result, while any valid contexts from
that hook point remain separate model input; the already-known execution result
stays in its own durable outcome event. A hook that exits with status 2 ignores
its stdout, including any JSON context, while other successful matching hooks
can still contribute. Cancellation before PostToolUse completes admits no
context message and receipt replay does not rerun the hook. The local transcript
flattens the text blocks for display and labels them `フック補足`; durable and
provider history retain the structured blocks. ACP currently omits these
synthetic messages from its user/assistant text updates because its bridge has
no source-aware context update.

The parser rejects unknown config fields, unsupported events, malformed JSON,
unknown result fields, and truncated output. A wrong-type
`additionalContext` is rejected as a strict native error, whereas upstream
ignores it; native session capacity and provider-shape checks also remain
stricter. Only live PreToolUse and PostToolUse command hooks run. Restore,
Session v4 import, receipt replay, and retries do not rerun hooks. Arbitrary
async/prompt hooks, `${CLAUDE_PLUGIN_ROOT}` substitution, and dedicated durable
`hook/*` diagnostic events are not implemented. A matching PostToolUse hook
adds a durable `effect-known` result event before running the hook. Native
session capacity limits still apply to the additional context metadata and
messages.

Stores that contain `effect-known` events from this opt-in path require dsh
0.1.5 or later: dsh 0.1.4 and earlier readers reject this event source. dsh
0.1.5 can still read earlier native snapshots. A matching post-hook result is
checkpointed even when the hook later denies it, so restore can settle the
known tool outcome without repeating host work.

Stores containing PostToolUse `additional_contexts` completion metadata or
structured `hooks-claude-code` user messages require dsh 0.1.12 or later. Do
not rewrite such a store with dsh 0.1.11 or older. dsh 0.1.12 continues to read
context-free dsh 0.1.11 native stores; the engine replay tests cover the legacy
completion shape without `additional_contexts`.

`--approve-call` and `--deny-call` act on a session that is already waiting for approval, for example one started from the browser or MCP carrier. Pass its current `approval_revision` and `pending_approval.call_id`; stale or mismatched decisions are rejected:

```sh
moon run native --target native --release -- \
  --session SESSION_ID --approve-call CALL_ID --approval-revision REVISION \
  --demo \
  --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project
```

Create an independent branch from a settled native v1 conversation with `fork-session SESSION_ID`. It returns a completed command receipt containing the new idle session. The child preserves the validated transcript and parent link; it does not resume or replay provider, approval, retry, or tool work.

```sh
moon run native --target native --release -- \
  fork-session SESSION_ID --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project
```

`--deny-call` follows the same flow but rejects the tool. Provider account lifecycle actions are also available locally with `--auth-status`, `--sign-in`, `--models`, `--select-model MODEL`, and `--sign-out`; each action requires `--data-dir` and `--workspace`. CLI `--sign-in` opens the host operating system's default browser. Sign-in from the local browser UI opens a new tab in that same browser. In both cases, the callback flow and tokens stay on the host in the protected native store.

## Data directory compatibility

On first open, the native runtime can read supported legacy dsh session snapshots and Session v4 inputs, then writes the native versioned envelope and receipt ledger. This conversion is one-way; older Node-host versions reject the native envelope. The Node host is retired in this version. Back up the data directory before opening it with the native runtime, and do not run an older writer against that directory afterward.

### Optional live SIWC smoke

This opt-in check uses the ChatGPT account signed in through the host browser and sends one harmless prompt through the public Responses API. It has not been run as part of repository verification. It requires an eligible account and can consume ChatGPT plan usage; it does not use or fall back to an OpenAI Platform API key.

~~~~sh
export DSH_MODE=openai-responses
export DSH_AUTH=chatgpt
moon run native --target native --release -- --sign-in --data-dir /absolute/path/to/dsh-siwc-smoke-data --workspace /absolute/path/to/project
moon run native --target native --release -- --auth-status --data-dir /absolute/path/to/dsh-siwc-smoke-data --workspace /absolute/path/to/project
moon run native --target native --release -- --models --data-dir /absolute/path/to/dsh-siwc-smoke-data --workspace /absolute/path/to/project
~~~~

Choose a slug returned by --models and entitled to the signed-in account, then select and run it with the same data directory:

~~~~sh
moon run native --target native --release -- --select-model MODEL_SLUG --data-dir /absolute/path/to/dsh-siwc-smoke-data --workspace /absolute/path/to/project
moon run native --target native --release -- --run 'Reply with exactly: SIWC smoke passed.' --data-dir /absolute/path/to/dsh-siwc-smoke-data --workspace /absolute/path/to/project
~~~~

The smoke passes only when the returned session reaches completed after a validated response.completed event. For account disconnect or switching, run --sign-out before starting a new sign-in. If plan usage is disabled, open ChatGPT in the host browser and check **Settings → Usage**; the native host does not grant or change account eligibility. Tailnet browser clients can use the account already connected on the Mac, but sign-in and account switching must be started from dsh on the host Mac.

## Tailscale Serve

Configure the exact MagicDNS HTTPS hostname and one owner login before starting the service:

```sh
export DSH_TAILNET_HOST='machine.example-tailnet.ts.net'
export DSH_TAILNET_ALLOWED_USERS='owner@example.com'
export DSH_TAILNET_PORT=8443 # optional; defaults to 443
moon run native --target native --release -- \
  web --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project --port 3210
```

The service accepts the configured HTTPS authority and Origin only when the `Tailscale-User-Login` header matches the configured owner. The HTTPS port defaults to 443; when `DSH_TAILNET_PORT` is set, use that port in both the request Host and HTTPS Origin. For example, configure Tailscale Serve on 8443 to proxy to the loopback port:

```sh
tailscale serve --https=8443 http://127.0.0.1:3210
```

Requests without that identity, requests from tagged devices, and other logins are rejected. The initial policy grants the one configured owner full access; it does not implement multi-user roles. To revoke or replace the owner, update the environment and restart the native host. The restart changes the authorization scope and invalidates previous cursors and receipt access.

The identity-header trust boundary assumes a managed, single-user host. The service binds to loopback, as Tailscale recommends, but another process running as that host user can forge loopback headers. Do not expose the native port on a LAN or public interface, and do not use Tailscale Funnel.

Workspace operations use no-follow dirfd traversal and compare the live path back to the opened workspace before and after IO. Atomic writes check the mapping immediately before rename, after rename, and after the parent-directory fsync; if a move is detected during commit, they try to remove the committed inode from the anchored parent. A successful write linearizes at the native transaction's final mapping check. A returned error after rename or fsync can still have an uncertain commit outcome if rollback loses a race or durability reporting fails; inspect or reconcile the target before retrying. The file contents remain atomic, but the path may have moved with its original directory. POSIX does not provide an atomic guarantee against a same-user process that deliberately renames directories in the final check-to-rename window or immediately after an operation returns. Treat the local OS account as trusted; these checks are not a same-user sandbox.

Process tools run in a dedicated session with a CPU limit and bounded captured output. Linux applies a hard address-space limit and supports the POSIX ERE grep tool. macOS rejects `RLIMIT_AS`/`RLIMIT_RSS` limits, so regex grep is disabled there instead of running without a verified memory boundary. macOS bash remains an explicitly enabled, time/output-bounded trusted-host capability and does not have a hard per-process memory cap.

Native workspace glob supports literals, `*`, `?`, and `**`; `**/` can match zero directory components, so `**/*.txt` matches a root-level `a.txt`. Character classes and brace alternatives are rejected. Traversal stops after depth 32 or 10,000 visited entries, matching is bounded to 20 million pattern/path steps per call, and results are capped at 1,000 paths / 64 KiB. This is a documented subset rather than full `path.matchesGlob` compatibility.

API-key mode uses `DSH_MODE=deepseek|openai|openai-responses`, `DSH_MODEL`, and optional `DSH_BASE_URL`; keys come from `DSH_API_KEY` or the provider-specific environment variable. ChatGPT sign-in is selected with `DSH_MODE=openai-responses DSH_AUTH=chatgpt`; the OAuth token stays in the host's protected store. A Tailnet page uses the Mac-owned credential and cannot start a remote OAuth flow or receive tokens.

The iOS bridge and physical-device/Tailscale end-to-end checks remain separate acceptance gates.
