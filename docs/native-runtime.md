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

The server binds only to `127.0.0.1`. With no `--port`, it prefers port 3080; if another listener already owns that port, it binds an OS-assigned available loopback port and prints the actual URL. An explicit `--port N` is strict and reports the original OS error on failure; `--port 0` always requests an available port. A conflict never stops the existing listener or bypasses the data-directory lock. Other network or permission errors do not trigger a port fallback. For stable bookmarks, browser preferences/offline caches, or a Tailscale Serve target, choose an explicit unused `--port`: browser-local state is scoped to the URL origin, while session history remains in the selected data directory. The browser carrier uses the same durable command, receipt, snapshot, approval, and effect path as native clients.

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

## Windows x64 profile

The Windows x64 profile is a bounded native host, not a port of every macOS /
Linux capability. Build it with MSVC 2022 plus the Windows SDK, Python 3.11+
(the gpui prebuild script needs a real interpreter, not the Store alias), and
the pinned MoonBit toolchain:

```powershell
moon update
moon install
moon build --target native --release cmd/dsh
python scripts/test-windows-runtime.py
```

Supported: `dsh run` / `dsh web` / `dsh --help`, the demo and API-key
providers, read / write / edit / glob, the durable session store and host lock,
and approval. Paths are normalized to `/`; drive roots and UNC shares are
accepted, while `..`, ADS colons, reserved DOS device names, trailing spaces or
dots, and control characters are rejected. Every component is opened with
`FILE_FLAG_OPEN_REPARSE_POINT` and a junction or symlink is rejected rather than
traversed.

Data-directory protection uses a current-user-only DACL (`0700`), 0600 file
creates, and an owner-SID-derived uid. Atomic writes commit through
`ReplaceFileW` / `MoveFileExW` after re-checking the root and path mapping, and
remove a commit that fails the post-commit identity check. The guarantee is
path-based: a same-user process that swaps a directory between the final check
and the rename can still win that race. Windows is a bounded host, not an OS
sandbox.

Unsupported on the Windows profile (typed error, non-zero exit, and no data
directory or lock mutation): shell / bash, `grep` (there is no hard worker
memory limit), external MCP, LSP, command hooks, subagents, `dsh acp`,
`dsh mcp`, `--internal-worker`, and ChatGPT SIWC. `siwc-auth.json` is never read
or written and the auth projection stays signed out; use `--demo` or an API
key. The GPUI desktop executable is built from `desktop/windows` (see
[the desktop guide](desktop.md#windows)); the `dsh desktop` launcher remains
unsupported on Windows, so run `dsh-desktop.exe` directly.

The C boundary returns `ENOTSUP` for `exec_worker`, `child_exit_state`, and
`kill_process_group` on Windows, and `os_hard_worker_memory_supported` is 0.
The CLI rejects the corresponding options before opening the store, so a failed
capability check cannot modify the data directory. Verification commands and
the exact PASS / NOT RUN split are recorded in
[verification](verification.md#windows-x64-native-runtime-m1).

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

Configured `UserPromptSubmit` hooks run for the child's initial prompt and
for a Stop-denial continuation. Their bounded, source-tagged context is added
to the child request before provider admission; an initial denial prevents the
child provider request. The existing native child-result envelope reports
that denial as `status: "failed"`, `steps: 0`, and a bounded `failure_reason`
inside the parent tool's `ok: false` result; it does not introduce a distinct
child refusal status. Configured Stop hooks run after an accepted terminal
child provider result and use the child's own Stop checkpoint. A Stop
denial passes through `UserPromptSubmit` before the next child provider request.
The initial prompt, UserPromptSubmit work, provider retries, tools, and
continuations share the child's 90-second drive deadline. SubagentStart runs
alongside the driver. SubagentStop has a 1-second aggregate command-execution
grace after the drive settles, plus process-group cleanup and drain time. Parent
cancellation owns and drains nested hook processes.
Child state remains ephemeral and the parent tool result is the no-replay
boundary.

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

`run`, `web`, `mcp`, `acp`, and `desktop` accept `--hooks-config PATH`. This is an
explicit opt-in to running trusted shell commands as the host user. The same
option works when launching the desktop app with `dsh desktop`; use an absolute
config path there because LaunchServices may choose a different process launch
directory. For CLI and service commands, a relative config path is resolved
from the process launch directory, independently of `--workspace`. Hook
commands themselves run with the selected workspace as their working
directory.

The config may contain a top-level `hooks` object, or put these events at the
root. Only command-based `SessionStart`, `PreToolUse`, `PostToolUse`,
`UserPromptSubmit`, `Stop`, `SubagentStart`, and `SubagentStop` groups are
supported:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{ "command": "/absolute/path/to/record-session-start" }]
      }
    ],
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
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "command": "/absolute/path/to/check-prompt" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "command": "/absolute/path/to/check-stop" }]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "general-purpose",
        "hooks": [{ "command": "/absolute/path/to/record-child-start" }]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "general-purpose",
        "hooks": [{ "command": "/absolute/path/to/record-child-stop" }]
      }
    ]
  }
}
```

In the Claude Code dialect, tool-event `matcher` is an exact tool name, `*`
for every tool, or literal names separated by `|`. `SessionStart` uses the
same literal matcher syntax with the source values `startup` and `resume`;
`startup|resume` matches both. Regex and partial wildcards such as `write.*`
are rejected. An omitted matcher applies to every source or tool. Each event
accepts at most 16 groups
and 32 commands; each command is limited to 8,192 characters. The config is
limited to 64 KiB. `timeout` is an integer number of seconds from 1 to 120,
defaulting to 10 seconds (upstream allows longer waits). Each hook receives one
JSON object on stdin, limited to 64 KiB. Stdout and stderr are captured
independently up to 16 KiB each; overflow is treated as an unsupported result.

For the Claude Code dialect, `--hooks-plugin-root DIR` replaces every
`${CLAUDE_PLUGIN_ROOT}` occurrence in configured commands, and
`--hooks-project-dir DIR` replaces every `${CLAUDE_PROJECT_DIR}` occurrence.
The same optional values are available as `hooks_plugin_root~` and
`hooks_project_dir~` on internal `NativeRuntime::open` and public
`NativeDesktop::open`.
Substitution happens when the config is parsed, first for plugin root and then
for project directory. An omitted value leaves its token text unchanged; an
explicit empty value replaces it with an empty string. The project-directory
override also sets the hook process's `CLAUDE_PROJECT_DIR` environment value.
Without that override, the environment value defaults to the selected
workspace. Hooks still execute with the selected workspace as their working
directory, regardless of the project-directory override.

These options require `--hooks-config` and are rejected with the Codex
dialect. Native option values are limited to 4,096 characters and cannot
contain NUL. The expanded command must still fit the 8,192-character command
limit. Substitution inserts the values as raw shell command text, without
quoting or escaping; quote the token in the command template where shell
syntax requires it. Hook commands and replacement values are trusted host
code.

### Codex command hooks

Pass `--hooks-dialect codex` with `--hooks-config PATH` to select the native
Codex adapter; without it, the runtime keeps the Claude Code dialect. This is a
single process-wide dialect for the runtime. `--hooks-model NAME` sets the
static `model` value in Codex payloads and is valid only with the Codex dialect
and a hooks config. The model defaults to the empty string; it is not inferred
from a provider session or changed during a turn.

Codex reads `SessionStart`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, and
`Stop` command hooks from a `hooks` object or from event arrays at the config
root. Other events, including `SubagentStart` and `SubagentStop`, are not part
of this adapter. A matching tool-hook pattern uses JavaScript `RegExp` search
semantics, but native accepts only a bounded ASCII subset of at most 128
characters: literals, groups, alternation, positive ASCII character classes,
and quantifiers. `*` remains the match-all shorthand. Dot, negated or POSIX
classes, flags, non-ASCII patterns, lookaround, and unsupported escapes are
rejected at startup rather than interpreted with different regex semantics.
`UserPromptSubmit` and `Stop` have no matcher subject, so their matchers are
ignored.

For example, a Codex command hook config can look like this:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Terminal",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/check-command",
            "timeoutSec": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "command": "/absolute/path/to/check-prompt" }] }
    ]
  }
}
```

Start a CLI session with the selected dialect and static model:

```sh
dsh run \
  'Review this change.' \
  --hooks-config /absolute/path/to/hooks.json \
  --hooks-dialect codex --hooks-model MODEL \
  --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project
```

Hook commands are trusted host shell code; the matcher does not add an approval
step.

Codex command entries accept `timeout` or `timeoutSec`; native uses a 10-second
default and a 1–120 second integer range. It skips unsupported asynchronous
entries. The native config file is limited to 64 KiB, each command to 8,192
characters, each stdin payload to 64 KiB, and captured stdout and stderr to
16 KiB each. The pinned bridge permits longer waits and full JavaScript regular
expressions.

Codex payloads are JSON objects written without a trailing newline. They use
`transcript_path: null`, `permission_mode: "default"`, the configured static
model, and a decimal-string `turn_id` on PreToolUse, PostToolUse,
UserPromptSubmit, and Stop; SessionStart has no turn ID. Tool events expose
`tool_input` only as `{ "command": ... }`, where the value is the tool's string
command or an empty string. This intentionally preserves the pinned bridge's
shell-only projection even when a matched tool has richer arguments. Stop also
sets `stop_hook_active: false` and `last_assistant_message: null`.

Only blocking decisions affect admission: exit code 2, top-level
`decision: "block"`, or a matching event's nested
`permissionDecision: "deny"` can block. A matching nested `allow` or `ask`
clears a top-level block; native does not create an approval prompt.
On successful, nontruncated exit, matching JSON
`hookSpecificOutput.additionalContext` is consumed for SessionStart,
PostToolUse, and UserPromptSubmit. Successful trimmed plain stdout is also
context for SessionStart and UserPromptSubmit when it does not start with
`{`. Malformed JSON, continuation and input-rewrite controls, and context from
other events are ignored. Codex commands run with the native minimal process
environment and do not receive `CLAUDE_PROJECT_DIR` or provider credentials.

Root SessionStart activation remains lazy: it runs on the first preflight-valid,
non-replay send, using `resume` for sessions loaded when the runtime opened and
`startup` for sessions created later. Direct root and child-initial
UserPromptSubmit commands run before turn admission and have no diagnostic
invocation/result pair. Turn-scoped diagnostics retain dialect `codex` and
`codex:<point>:<counter>` identities. Codex context keeps `hooks-codex`
provenance through provider preparation, root and child turns, snapshots, reopen,
and fork; callers cannot forge that trusted provenance through request
metadata.

In the Claude Code dialect, `SessionStart` runs matching commands in
configuration order and consumes only a successful JSON
`hookSpecificOutput.additionalContext` string whose
`hookEventName` is `SessionStart`. The input has exactly `session_id`, an empty
`transcript_path`, the canonical workspace `cwd`, `hook_event_name`, and
`source`; Codex uses the null transcript path described above. The pinned
Claude bridge awaits SessionStart during agent publication and uses `startup`
for new agents and `resume` for restored agents; although its
source type also names `clear` and `compact`, the pinned creation paths do not
emit those values. The native root adapter runs lazily on the first
preflight-valid, non-replay `session_send`: sessions present when the runtime
opens use `resume`, and sessions created later use `startup`. It does not run
while merely creating or listing a root session. For foreground children,
SessionStart runs as `startup` before SubagentStart and before the child's
initial UserPromptSubmit admission, under the child's aggregate run deadline.

SessionStart contributes context before the original prompt. When
UserPromptSubmit is also configured, its `prompt` field is the SessionStart
context strings concatenated directly with the original prompt, matching the
pinned bridge's text-block flattening (there is no inserted separator); any
UserPromptSubmit context follows the prompt. The shared context cap is 32
strings and 16,384 UTF-16 code units, with a 4,096-unit limit per string.
If any SessionStart context would exceed that cap, the native adapter drops the
whole SessionStart context batch after it finishes running all matching
commands in order.
Upstream claims and removes this inbox before running UserPromptSubmit. If that
hook rejects the prompt, the claimed SessionStart context is dropped and the
SessionStart command does not run again on retry. Native admission keeps this
source behavior. A successful root SessionStart batch that completes just as
caller cancellation wins before prompt admission stays in a process-local,
per-session inbox. The inbox holds at most 64 nonempty pending batches; once
full, a new session's send is refused with
`native SessionStart pending inbox limit reached` before another hook command
is dispatched. Retrying the same session consumes its batch once. Closing or
reopening the runtime discards unclaimed context, and restore or receipt replay
never reruns the external hook.

The pinned listener applies only SessionStart `additionalContext`; decisions,
`continue`, `systemMessage`, and `updatedInput` are ignored, and it emits no
invocation/result pair for this event. Native history uses the existing
`hook/subagent-start-context` count/length marker followed by a
source-tagged user message for either child Start or root SessionStart context.
The marker name is a shared native representation, not evidence that the
context came only from SubagentStart. SessionStart reuses the marker/batch
format supported by the dsh 0.1.16 reader, based on a static audit of that
reader; the unchanged dsh 0.1.17 reader logic and current probes also accept
these batches. No dsh 0.1.16 binary was run. This per-format compatibility does
not establish whole-store downgrade safety: other persisted content can
require a newer reader, including PostToolUse boundaries introduced in 0.1.17.
Determine the minimum reader from all persisted content and never downgrade or
rewrite a store based only on this marker reuse.

`UserPromptSubmit` has no matcher subject in the pinned Claude Code bridge, so
any `matcher` field on one of its groups is ignored. It runs once for each
valid nonempty user `session_send`, before the engine admits the turn and
creates its first provider request; it does not run for provider follow-up
steps. The hook receives exactly `session_id`, an empty `transcript_path`, the
canonical workspace `cwd`, `hook_event_name`, and the submitted `prompt` on
stdin. Invalid, busy, imported, oversized, or capacity-exhausted sends are
rejected before a hook command starts. Do not pass caller-supplied
`additional_contexts`; the runtime discards them and accepts context only from
the configured hook.

Exit status 2, top-level `decision: "block"`, or matching
`hookSpecificOutput.permissionDecision: "deny"` rejects the prompt before any
turn or provider effect is created. The stderr text or structured reason is
returned as the rejection reason. Exit codes other than 0 or 2, plain stdout,
malformed JSON, non-object JSON, and event-specific output whose
`hookEventName` is missing or names another event are ignored, matching the
pinned hook protocol. `permissionDecision: "allow"` and `"ask"` do not add an
approval step for a user prompt. Remote command callers receive a durable
rejected receipt for a denial; MCP callers receive a JSON-RPC error. A
`session_cancel` can interrupt a running hook, and the native process runner
cleans up its process group before the request settles.

Each nonempty `additionalContext` string from a successful matching hook is
limited to 4,096 UTF-16 code units; up to 32 values and 16,384 code units in
total are accepted for one prompt. Empty strings are skipped and whitespace
is retained. The contexts follow the original user message in one
source-tagged `user/message` with one text block per hook, preserving upstream
hook order before the first provider request. A denied prompt contributes no
context. Once the remote receipt settles, replay returns that receipt without
running the hook or provider again. An interrupted, unsettled remote hook
reservation is restored as uncertain and is not replayed. Stores with these
prompt-context events require dsh 0.1.13 or later; do not rewrite them with
dsh 0.1.12 or older.

The pinned Claude Code bridge also leaves several prompt controls unapplied:
`continue: false` is marked TODO and does not stop the agent loop,
`stopReason` has no run-level effect, and `updatedInput` / `systemMessage` are
logged but ignored. This native path likewise does not apply those fields.

`Stop` groups also have no matcher subject, so any `matcher` field is ignored
and every configured command runs in config order at a terminal provider step,
including a max-token step. The payload contains exactly `session_id`, an empty
`transcript_path`, canonical workspace `cwd`, `hook_event_name: "Stop"`, and
`stop_hook_active: false`. The empty transcript path and fixed false marker
follow the pinned bridge payload; the native host has no transcript artifact
path or Stop recursion marker.

The Stop adapter consumes top-level `approve` / `block` plus `reason`, and
`hookSpecificOutput` only when `hookEventName` is exactly `Stop`. Matching
`permissionDecision` values `allow`, `deny`, and `ask` override that hook's
top-level decision; `permissionDecisionReason` overrides its reason when it is
a string. Across commands, `deny` outranks `ask`, which outranks `allow`; only
nonempty reasons for the winning rank are joined in config order with a blank
line. Exit status 2 also denies and uses trimmed stderr. If no nonempty reason
survives, native continuation text is `continue: blocked by Stop hook`.
Malformed JSON, unknown fields, wrong field types, other nonzero exit codes,
spawn failures, and timeout are neutral. A known exit-2 denial remains a denial
when stderr is truncated or invalid UTF-8; its reason is bounded by the captured
16 KiB stream, and unreadable stderr uses the fallback. Truncated non-exit-2
output is neutral for Stop.
The Stop listener consumes the merged decision and denial reason only;
additional context, `continue: false`, `stopReason`, and `updatedInput`
do not control the run in the pinned bridge and are not applied here.

`SubagentStart` and `SubagentStop` run for a child after its session has been
created. Both use the literal `general-purpose` matcher subject, matching the
pinned bridge's generic subagent type; an exact `general-purpose` matcher or
`*` matches, while a matcher for a specific agent kind does not. Commands run
sequentially in configured group order. Their payload contains exactly
`session_id`, an empty `transcript_path`, canonical workspace `cwd`,
`hook_event_name`, `agent_id`, and `agent_type: "general-purpose"`;
`SubagentStop` also has `stop_hook_active: false`.

`SubagentStart` runs as a sibling of the child driver, so it does not delay the
initial provider request or reject the child. Only a successful command's
matching `hookSpecificOutput.additionalContext` is used. Top-level decisions,
permission decisions, malformed output, mismatched events, nonzero exits, and
truncated output are ignored for lifecycle control. At each child input
boundary, native claims the currently queued Start batch and runs
`UserPromptSubmit` before the next provider request. On the initial boundary,
the hook sees the Start context and original child prompt; a later Start batch
is checked as the next-step input; a Stop continuation claims the current
Start batch together with the Stop reason. Hook input concatenates text without
adding separators. On acceptance, initial history order is Start context,
original prompt, then `UserPromptSubmit` additional context; late-batch order
is Start context then prompt-hook context; Stop-continuation order is claimed
Start context, Stop reason, then prompt-hook context. If a Start callback
finishes while `UserPromptSubmit` is running, its context stays queued for a
later step and is admitted through the prompt hook at that boundary. Denial or
failure of a late-batch admission preserves the previously committed assistant
answer and does not append rejected context. The initial prompt is still
subject to the existing three-step and child deadline limits. A callback that
finishes after the child becomes terminal cannot add context.

The direct-admission fallback counts initial Start source-message text once
toward the shared 32-item / 16,384 UTF-16-unit hook-context budget. The native
bridge invokes one Start callback per child; Engine callers may queue later
batches, which use the remaining budget on this fallback path. With
`UserPromptSubmit` checkpoint admission enabled, each currently claimed batch
is validated against the same per-batch bounds instead of cumulative turn
statistics. In the direct-admission fallback, queued text that exceeds the
shared budget is dropped; the next step still advances and its snapshot
replays from the ordinary `step/start` event after Stop settlement.

This admission path covers Start batches combined with the initial prompt,
Start-only input batches at later steps, Start batches combined with a Stop
continuation, and nonempty PostToolUse context batches. When configured,
`UserPromptSubmit` runs on the next root or child input boundary before another
provider request. The tool results are committed first. Accepted history keeps
the PostToolUse source messages in tool-call order, then appends the prompt
hook's context; a child Start batch remains earlier in the same claimed input.
As in the pinned bridge, ordinary tool-result-only follow-up steps have an
empty inbox and skip the command hook.

`SubagentStop` is observational: all output, including deny decisions and
additional context, is discarded and it never changes the child's result or
forces a continuation. It runs once when a created child settles, including
provider failure, prompt denial, timeout, and parent cancellation. Start tasks
are cancelled and drained when the native child lifecycle ends; the pinned
bridge instead keeps detached lifecycle hook tasks until bridge disposal.
This child-scoped lifetime can cancel a delayed Start hook before its context
is applied. Native Stop cleanup is protected from cancellation and has one
aggregate 1-second command-execution grace across all configured commands. It
runs after the child drive outcome, so it can truncate a command with a longer
configured timeout and delay the parent tool result. Cancellation, process-group
cleanup, reaping, and output draining can add wall-clock time beyond that grace,
but Stop cannot change the child outcome. This is a native lifecycle bound, not
an upstream timeout contract. No lifecycle hook runs when child validation,
provider binding, or session creation fails before publication.

A Stop denial steers a source-tagged user message into the same turn. Before a
provider request for that continuation, native runs `UserPromptSubmit` with the
steer text. If that hook denies or cannot run, the previous assistant answer
stays in the transcript and the turn ends `failed` with reason `blocked`; the
ACP carrier reports `stopReason: "refusal"`. A successful prompt hook may add
its bounded context to the continuation. UserPromptSubmit also runs for a new
valid user `session_send`. The pinned Claude Code bridge invokes its
`agent/pre-step` hook on each step but immediately skips the command hook when
the claimed inbox message list is empty. Ordinary tool-result-only follow-up
steps therefore do not run UserPromptSubmit upstream either. Stop-denial
continuations contain a steered message and do run it. Foreground child prompts
and Stop continuations use the same command hooks through the child's engine.

Stop is opt-in with hooks config and its external commands run only after the
terminal provider result has been checkpointed. Cancellation kills and drains
the hook process before the scheduler can reuse the session; restore closes an
unsettled Stop boundary as interrupted without rerunning hooks or provider
work. Max-token completion still invokes Stop, and the `max_tokens` terminal
reason stays sticky if a later continuation is allowed. The engine's existing
`max_steps` remains the bound; neither upstream nor native adds a separate
consecutive-Stop limit. The native decoder caps the aggregate joined Stop
reason at 524,350 UTF-16 units. Existing 64 KiB hook-stdin and 262,144
UTF-16-unit serialized-session limits apply separately; a candidate that
exceeds session capacity closes with `session_capacity` without dispatching
the provider effect. A denial in the continuation's UserPromptSubmit hook is
clipped on a Unicode scalar boundary to the existing 8,192 UTF-16-unit
event-error limit so the turn always settles. For PostToolUse admission, the
rejection prefix is included in that same limit, so a long Unicode reason does
not leave the known tool results unsettled.

PreToolUse and PostToolUse payloads include `session_id`, an empty
`transcript_path`, the canonical workspace `cwd`, `hook_event_name`,
`tool_name`, `tool_input`, and `tool_use_id`; PostToolUse also includes the
string `tool_response`. Pass data through stdin rather than interpolating tool
input into command text. The child gets only `PATH`, `LANG`, `LC_ALL`, and
`CLAUDE_PROJECT_DIR`; it does not inherit provider credentials or the rest of
the host environment. Quote workspace paths in shell commands as
`"${CLAUDE_PROJECT_DIR}"`.

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
validation. When `UserPromptSubmit` is configured, the next root or child input
boundary claims a nonempty batch before the next provider request. The shared
32-item / 16,384 UTF-16-unit context limit covers the claimed batch, including
returned prompt-hook contexts and any child Start contexts in that batch. On
denial or limit rejection, the already committed tool outcomes remain, rejected
context is not admitted, and no next provider request starts. Cancellation or
restore abandons unresolved admission without rerunning the hook or provider.

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

The config parser rejects unknown fields, unsupported events, and malformed
groups. PreToolUse and PostToolUse also use strict structured-result validation;
for those events a wrong-type `additionalContext` is rejected, whereas
upstream ignores it. UserPromptSubmit follows the upstream lenient output
decoder described above. For non-Stop hooks, truncated output and native
context-limit overflow reject the request instead of being silently truncated;
Stop keeps exit-2 control when its captured stderr truncates. Native session
capacity and provider-shape checks remain stricter. Restore, Session v4 import,
receipt replay, and retries do not rerun hooks. Arbitrary async hooks,
prompt-hook types other than command-based UserPromptSubmit, and events outside
the seven listed above are not implemented. A matching
PostToolUse hook adds a durable `effect-known` result event before running the
hook. Native session capacity
limits still apply to the additional context metadata and messages.

### Durable command-hook diagnostics

For turn-scoped hooks, native records a `hook/invoked` checkpoint before it
starts each matching command, then records the paired `hook/result` after the
command returns or a non-cancellation runner failure is known. The invocation
contains `turn`, `point`, `dialect: "claude-code"`, `handlerId`, and an optional
`matcher`. The result contains `turn`, `point`, `handlerId`, the per-command
`decision`, and `durationMs`, with optional `exitCode` and `stderrSummary`.
Native handler IDs use the `claude-code:<point>:<counter>` form. Results pair
by turn, point, and handler ID, including when hooks for parallel tools finish
in a different order from their invocations.

The diagnostic decision records the hook protocol's decoded result, not the
native merged action: exit status 2 records `block`; successful structured
output can record top-level `approve` / `block` or a matching
`hookSpecificOutput.permissionDecision` of `allow` / `deny` / `ask`; an
otherwise unmatched `continue: false` records `stop`; and unrecognized or
neutral output records `pass`. A timeout, process-start failure, or signal
termination can produce a `pass` result without an `exitCode`; native does not
synthesize one. Diagnostics do not store command text, stdin, or full stdout.
A nonempty stderr summary is trimmed first. When it exceeds 500 UTF-16 code
units, native stores its 500-unit prefix plus an ellipsis (at most 501 units).
The summary contains hook-emitted stderr and is not redacted. Hook processes do
not inherit provider credential environment variables and should not print
credentials to stderr.
MoonBit preserves valid Unicode scalars at that boundary, so a supplementary
character is not split even though the pinned JavaScript implementation may
slice between its surrogate units.

The invocation event is committed before the command can cause an external
effect. If that checkpoint fails, native does not start the command. If a
result checkpoint fails, the error is fatal to the pending transition; for a
PostToolUse hook the already-known tool outcome remains committed and is not
replayed. A cancelled process that has not returned a result leaves an
unresolved invocation rather than a fabricated exit code or result. Restore
marks an open turn with such an invocation interrupted and never reruns the
command. Normal completed, blocked, provider-error, and max-step closures
reject unresolved invocations; cancelled or interrupted closures may retain
them. If the observed result checkpoint wins the cancellation race, native
records that result before applying cancellation.

Diagnostics are emitted for PreToolUse, PostToolUse, Stop, and UserPromptSubmit
when its boundary is inside an open turn. Every direct root `session_send`
runs UserPromptSubmit before that new turn is admitted, so none of those root
prompt-hook commands have a diagnostic pair. A child's initial prompt hook is
also preturn and unpaired. Root UserPromptSubmit diagnostics therefore apply
only to in-turn continuations such as PostToolUse context or Stop steer.
SessionStart, SubagentStart, and
SubagentStop also have no pair, matching the pinned bridge's event shapes.
Root diagnostics are stored with the root session. Child diagnostics stay in
the ephemeral child Engine and are not copied into the parent snapshot; the
parent tool result remains the no-replay boundary for the child call.

Stores that contain `effect-known` events from this opt-in path require dsh
0.1.5 or later: dsh 0.1.4 and earlier readers reject this event source. dsh
0.1.5 can still read earlier native snapshots. A matching post-hook result is
checkpointed even when the hook later denies it, so restore can settle the
known tool outcome without repeating host work.

Stores containing PostToolUse `additional_contexts` completion metadata or
structured `hooks-claude-code` user messages from PostToolUse require dsh
0.1.12 or later. UserPromptSubmit context messages require dsh 0.1.13 or later.
Stores containing Stop boundary or continuation events require dsh 0.1.14 or
later. Do not rewrite any of these stores with an older reader. dsh 0.1.12
continues to read context-free dsh 0.1.11 native stores; the engine replay
tests cover the legacy completion shape without `additional_contexts`.
The `hook/subagent-start-context` marker/batch format is supported by the dsh
0.1.16 reader according to a static source audit; the unchanged dsh 0.1.17
reader logic and current probes also accept it. No dsh 0.1.16 binary was run.
The marker is a shared count/length boundary for child SubagentStart and root
SessionStart context batches; the following source-tagged user message carries
the text. The marker name does not identify the producer. This statement covers
only that format, not whole-store downgrade compatibility: all persisted
content sets the store's minimum reader version. For example, PostToolUse
boundaries introduced in 0.1.17 require dsh 0.1.17 or later. Never downgrade
or rewrite a store based only on marker reuse. The `hook/stop-settled` event is
an empty-data
boundary emitted when Stop completes without a staged continuation and queued
hook input advances to the next step. It may appear in root Engine snapshots
too. Replay clears only the completed Stop continuation state and preserves
sticky max-token completion; a following Start marker must come after this
boundary. If a snapshot ends here while prompt admission is unresolved,
restore marks the work interrupted and does not replay the hook or provider
effect. Do not reopen either event with an older reader.

Snapshots containing the optional `post_tool_prompt_hook` (root) or
`subagent_post_tool_prompt_hook` (child) field on an effect-backed
`tool/completed` event, or the additive `hook/post-tool-prompt-*` and
`hook/subagent-post-tool-prompt-*` events, require dsh 0.1.17 or later. The
child field is emitted as `true` while child prompt admission is enabled; it
restores that deferral mode before replay closes an interrupted child result
batch. The fields are true-only, valid only on effect-backed completions, and
mutually exclusive. Version 0.1.17 continues to read legacy completion events
without either optional field. The root markers record deferred PostToolUse
admission; child markers also make public child Engine snapshots
self-validating across admission, rejection, and interruption. Native
subagent sessions remain ephemeral and are not persisted as root sessions.
Do not reopen these snapshots with an older reader.

Snapshots containing `hook/invoked` or `hook/result` require dsh 0.1.19 or
later because earlier native readers reject these additive event kinds.
dsh 0.1.19 continues to read legacy snapshots without hook diagnostics. A
pending invocation is valid at an interrupted boundary; a normal turn closure
must contain its result.

Snapshots containing source-tagged user messages with `source.kind` equal to
`hooks-codex`, or `hook/invoked` events with dialect `codex`, require dsh 0.1.20
or later. Older readers reject these provenance values; dsh 0.1.20 continues to
read legacy stores. Determine a store's minimum reader from all persisted
content and do not downgrade or rewrite it using an older reader.

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

## Startup failures and platform support

`dsh desktop` launches the macOS `Dsh.app` bundle and is supported only on
macOS. On Linux, use `dsh web` for the browser UI. A Linux `/usr/bin/open`
(such as an `xdg-open` alias) does not provide macOS LaunchServices.
Expected CLI failures print a diagnostic to stderr and exit with status 1,
without aborting or generating a core dump.

Only one runtime may own a data directory at a time. If startup reports a
locked directory, the hostname and PID identify the **recorded** owner, not
proof that the current process with that PID is dsh. Verify the owning dsh
instance on that host and shut it down normally before retrying. Do not kill
an arbitrary PID or delete `host.lock` to bypass this check. To run an
independent instance, use a different `--data-dir /absolute/path` (it has its
own sessions and authentication state).

A same-host lock is recovered automatically only when its PID is confirmed
absent. Foreign-host locks, live or reused PIDs, invalid JSON, and
locks whose owners cannot be confirmed absent remain protected. An old creation timestamp alone is not
proof that a lock is stale. Upgrading or reinstalling dsh does not stop an
already-running instance or remove its lock.

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


ChatGPT のモデルを Settings または `--select-model` で選ぶと、その workspace の provider も ChatGPT に切り替わり、再起動後も保存された選択を使います。サインインだけでは起動時の API-key 設定を変更しません。サインアウト後は認証エラーになり、API key へ自動で戻りません。Settings の「起動時のプロバイダー設定を使用」で明示的に戻せます。`--demo-provider` ではモデル選択による実サービスへの切り替えを受け付けません。
