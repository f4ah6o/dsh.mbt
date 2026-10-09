# Foreign-function boundary

MoonBit is the source of product behavior. Native C and browser JavaScript
interop expose operating-system and browser primitives; they do not implement
CLI grammar, JSON-RPC or HTTP protocols, provider policy, session transitions,
approval decisions, command scheduling, persistence formats, or UI state.

## Native C boundary

The native executable links three C files: `runtime/host_os.c`,
`runtime/oauth_os.c`, and `runtime/signal_os.c`. The reviewed C surface is limited
to these `extern "C"` symbols:

```text
dsh_auth_open_url              dsh_auth_random
dsh_auth_unix_time             dsh_crypto_sha256
dsh_crypto_verify_rs256        dsh_exec_worker
dsh_fs_atomic_write            dsh_fs_close
dsh_fs_create_exclusive        dsh_fs_list_dir
dsh_fs_mapping_matches         dsh_fs_open_file
dsh_fs_open_root               dsh_fs_read_fd
dsh_fs_root_matches            dsh_fs_set_root_mode
dsh_fs_stat_fd                  dsh_fs_stat_root
dsh_fs_unlink                   dsh_kill_process
dsh_kill_process_group          dsh_os_flush_stderr
dsh_os_executable_path          dsh_os_flush_stdout
dsh_os_hard_worker_memory_supported
dsh_os_hostname                 dsh_os_pid
dsh_os_process_alive            dsh_os_process_group_alive
dsh_os_stdin_is_terminal
dsh_os_timestamp                dsh_os_uid
dsh_service_signals_install     dsh_service_signals_requested
dsh_service_signals_restore
```

`host_os.c` wraps dirfd-relative file operations, no-follow opens, metadata,
atomic writes, process spawning and termination, terminal and process facts,
stdout/stderr flushing, and the low-level SHA-256 / RS256 primitives used by
MoonBit authentication code. Its filesystem walk rejects absolute paths and
`.` / `..` components as a syscall-level guard; MoonBit still owns workspace
admission, path normalization, bounds, tool policy, and error semantics.
The process trampoline pins and verifies the workspace before changing
directory, applies resource limits, then closes every inherited descriptor
above stdin/stdout/stderr before executing the requested program. This also
contains transient pipe descriptors inherited during concurrent native
spawns.
`oauth_os.c` supplies entropy, Unix time, and launching a validated authorization
URL in the host browser. `signal_os.c` installs and restores minimal SIGINT /
SIGTERM handlers and reports the requested signal; MoonBit owns shutdown and
task-drain behavior.

The C helpers do not parse user commands, provider or MCP messages, or session
files, and do not decide which workspace operation is allowed. Return values
are primitive statuses, bytes, descriptors, or metadata for MoonBit to check.
No product protocol or approval logic is embedded in a C helper.

`runtime/host_os.mbt`, `runtime/oauth.mbt`, and `runtime/service.mbt` contain the
MoonBit declarations. `scripts/check.mjs` compares every discovered native C
extern against the explicit allow-list above and confirms each symbol has a C
definition. Any change fails the check until this document and the list are
reviewed together.

## Browser host APIs

Browser and service-worker code is authored in `browser/**/*.mbt` and compiled
to `web/moonbit/browser.js` and `web/sw.js` at their runtime paths. These
generated JavaScript files are not tracked in Git. The
`extern "js"` declarations in `browser/dom.mbt`, `browser/transport.mbt`, and
`browser/sw/sw.mbt` are narrow adapters for standard browser facilities:
DOM nodes, events, focus, layout measurement, Canvas 2D, Fetch, EventSource,
local storage, timers, Cache API, service-worker events, and response/request
objects. The MoonBit controller, rendering projection, transport decisions,
authentication flow, caching policy, UI state, and error handling remain in
MoonBit. The web shell has no handwritten JavaScript entrypoint or product
logic.

The source inventory check permits only the two generated JavaScript assets
and explicitly test-only JavaScript. A fresh checkout needs
`sh scripts/build.sh` before service startup or direct web-test runs; `npm test`
runs the build first. `npm run check` can run before output generation and
compares generated modules when present. `scripts/build-web-shell.mjs` rebuilds the
browser and service-worker packages, writes their compiler outputs at the same
runtime paths, and copies CSS from Mooncakes dependency
`f4ah6o/yami_kumo@0.1.0` installed under `.mooncakes/f4ah6o/yami_kumo`. Its
`--check` mode freshly compiles the browser and service-worker modules, compares
them with the generated web files when present, and always checks the tracked
CSS and local shell stylesheet against their sources.
`scripts/native-verify.mbtx` performs the same browser/service-worker build and
asset comparison in the CI job where Node.js and npm are absent. Node-based
scripts and Playwright are development/test tooling, not product runtime
dependencies.
