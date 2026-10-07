# Native runtime

The native command runs the MoonBit runtime and loopback HTTP carrier without Node.js. It serves the built web assets from `web/` and the generated files under `_build/js/release/build/`.

```sh
moon update
moon install
moon run native --target native --release -- \
  --serve --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project --port 3210
```

The server binds only to `127.0.0.1`. The browser carrier uses the same durable command, receipt, snapshot, approval, and effect path as native clients.

For a credential-free offline check, add `--demo`:

```sh
moon run native --target native --release -- \
  --serve --demo --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project --port 3210
```

This mode uses a deterministic provider response, never reads provider API-key environment variables, and never makes provider network requests. Its first response requests an approved workspace write; the next response includes the tool result. The demo writes `native-demo.txt` inside the selected workspace.

The foreground CLI uses the same native runtime and persists its session after each command. For example, `--run` starts a session and prints its ID and any pending approval call. Resume that session by passing the JSON field `approval_revision` to the `--approval-revision` option and `pending_approval.call_id` to `--approve-call`:

```sh
moon run native --target native --release -- \
  --run 'Create and verify a durable file.' --demo \
  --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project

moon run native --target native --release -- \
  --session SESSION_ID --approve-call CALL_ID --approval-revision REVISION --demo \
  --data-dir /absolute/path/to/dsh-demo-data \
  --workspace /absolute/path/to/project
```

`--deny-call` follows the same flow but rejects the tool. Provider account lifecycle actions are also available locally with `--auth-status`, `--sign-in`, `--models`, `--select-model MODEL`, and `--sign-out`; each action requires `--data-dir` and `--workspace`. Sign-in opens the host browser and keeps all tokens in the protected native store.

## Data directory compatibility

On first open, the native host can read supported legacy dsh session snapshots and Session v4 inputs, then writes the native versioned envelope and receipt ledger. This conversion is one-way: the Node host rejects a native envelope. Back up the data directory before opening it with the native host, and do not alternate Node and native writers or run them concurrently against the same directory.

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

The smoke passes only when the returned session reaches completed after a validated response.completed event. For account disconnect or switching, run --sign-out before starting a new sign-in. If plan usage is disabled, open ChatGPT in the host browser and check **Settings → Usage**; the native host does not grant or change account eligibility. A remote browser cannot complete this initial host-browser sign-in flow.

## Tailscale Serve

Configure the exact MagicDNS HTTPS hostname and one owner login before starting the service:

```sh
export DSH_TAILNET_HOST='machine.example-tailnet.ts.net'
export DSH_TAILNET_ALLOWED_USERS='owner@example.com'
moon run native --target native --release -- \
  --serve --data-dir /absolute/path/to/dsh-data \
  --workspace /absolute/path/to/project --port 3210
```

In another terminal, configure Tailscale Serve to proxy to that loopback port:

```sh
tailscale serve 3210
```

The service accepts that configured Host and HTTPS Origin only when the `Tailscale-User-Login` header matches the configured owner. Requests without that identity, requests from tagged devices, and other logins are rejected. The initial policy grants the one configured owner full access; it does not implement multi-user roles. To revoke or replace the owner, update the environment and restart the native host. The restart changes the authorization scope and invalidates previous cursors and receipt access.

The identity-header trust boundary assumes a managed, single-user host. The service binds to loopback, as Tailscale recommends, but another process running as that host user can forge loopback headers. Do not expose the native port on a LAN or public interface, and do not use Tailscale Funnel.

Workspace operations use no-follow dirfd traversal and compare the live path back to the opened workspace before and after IO. Atomic writes repeat that mapping check immediately before rename and remove a commit if a directory move is detected during commit. This detects ordinary concurrent replacements, but POSIX does not provide an atomic guarantee against a same-user process that deliberately renames directories in the final check-to-rename window or immediately after an operation returns. Treat the local OS account as trusted; these checks are not a same-user sandbox.

Process tools run in a dedicated session with a CPU limit and bounded captured output. Linux applies a hard address-space limit and supports the POSIX ERE grep tool. macOS rejects `RLIMIT_AS`/`RLIMIT_RSS` limits, so regex grep is disabled there instead of running without a verified memory boundary. macOS bash remains an explicitly enabled, time/output-bounded trusted-host capability and does not have a hard per-process memory cap.

Native workspace glob supports literals, `*`, `?`, and `**`; `**/` can match zero directory components, so `**/*.txt` matches a root-level `a.txt`. Character classes and brace alternatives are rejected. Traversal stops after depth 32 or 10,000 visited entries, matching is bounded to 20 million pattern/path steps per call, and results are capped at 1,000 paths / 64 KiB. This is a documented subset rather than full `path.matchesGlob` compatibility.

API-key mode uses `DSH_MODE=deepseek|openai|openai-responses`, `DSH_MODEL`, and optional `DSH_BASE_URL`; keys come from `DSH_API_KEY` or the provider-specific environment variable. ChatGPT sign-in is selected with `DSH_MODE=openai-responses DSH_AUTH=chatgpt`; the OAuth token stays in the host's protected store. Sign-in opens a browser on the host and is not a remote token-delivery flow.

The iOS bridge and physical-device/Tailscale end-to-end checks remain separate acceptance gates.
