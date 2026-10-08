# Native runtime

The native executable is the sole product host. MoonBit owns CLI parsing,
session and provider behavior, HTTP/MCP service, browser behavior, persistence,
and tool policy. Narrow C FFI supplies operating-system primitives such as
no-follow filesystem operations, process creation, cryptographic primitives,
signals, and terminal detection; the audited boundary is listed in
[ffi-boundary.md](ffi-boundary.md). No Node.js or npm package is loaded by the
product build or runtime.

Build the executable and all browser assets with the pinned MoonBit toolchain:

```sh
moon update
moon install
sh scripts/build.sh
moon run native --target native --release -- \
  web --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project --port 3210
```

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
