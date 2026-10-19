# Foreign-function boundary

MoonBit is the source of product behavior. Native C and browser JavaScript
interop expose operating-system and browser primitives; they do not implement
CLI grammar, JSON-RPC or HTTP protocols, provider policy, session transitions,
approval decisions, command scheduling, persistence formats, or UI state.

## Native C boundary

The native executable links seven C files: `runtime/host_os.c`,
`runtime/host_os_win32.c`, `runtime/oauth_os.c`, `runtime/oauth_os_win32.c`,
`runtime/signal_os.c`, `runtime/linux_desktop_payload.c`, and
`runtime/macos_desktop_payload.c`. Each platform compiles only its own variant;
POSIX code is guarded by `__APPLE__` / `__linux__` and Windows code by `_WIN32`.
The reviewed C surface is limited to these `extern "C"` symbols:

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
dsh_os_is_macos                 dsh_os_is_linux
dsh_os_is_windows
dsh_linux_desktop_launch         dsh_macos_desktop_bundle
dsh_os_child_exit_state
dsh_os_process_alive            dsh_os_process_group_alive
dsh_os_stdin_is_terminal
dsh_os_timestamp                dsh_os_uid
dsh_service_address_in_use
dsh_service_signals_install     dsh_service_signals_requested
dsh_service_signals_restore
```

`host_os.c` wraps dirfd-relative file operations, no-follow opens, metadata,
atomic writes, process spawning and termination, terminal and process facts,
compile-time macOS/Linux platform flags,
stdout/stderr flushing, and the low-level SHA-256 / RS256 primitives used by
MoonBit authentication code. Its filesystem walk rejects absolute paths and
`.` / `..` components as a syscall-level guard; MoonBit still owns workspace
admission, path normalization, bounds, tool policy, and error semantics.
The process trampoline pins and verifies the workspace before changing
directory, applies resource limits, then closes every inherited descriptor
above stdin/stdout/stderr before executing the requested program. This also
contains transient pipe descriptors inherited during concurrent native
spawns. The MCP shutdown path uses `waitid(WNOWAIT | WNOHANG)` to
observe an owned child without reaping it: its PID reserves the process-group
identity until TERM grace and final KILL finish. Negative/non-child results do
not authorize signaling. The async process API remains the sole reaper; later
bounded group-disappearance checks are read-only. Those checks include zombies,
so a host init that does not reap orphan descendants can exhaust the bound.
`oauth_os.c` supplies entropy, Unix time, and launching a validated authorization
URL in the host browser. `signal_os.c` installs and restores minimal SIGINT /
SIGTERM handlers and reports the requested signal; MoonBit owns shutdown and
task-drain behavior. It also compares an OS error code with the platform's
address-in-use constant; MoonBit decides whether an implicit default port may
fall back, performs the loopback bind, and reports the selected endpoint.

`host_os_win32.c` implements the same SafeRoot contract on Windows x64 without
`openat`: every component is opened with `FILE_FLAG_OPEN_REPARSE_POINT` and must
not carry `FILE_ATTRIBUTE_REPARSE_POINT`, the configured root handle is
re-verified against its pathname before each operation, and a commit compares
the anchored and fresh walks by volume serial plus file index before and after
the rename. Handles live in a fixed process-global table so a 64-bit HANDLE is
never truncated into an Int32. Atomic writes use a same-directory `CREATE_NEW`
temporary, `ReplaceFileW` / `MoveFileExW(MOVEFILE_WRITE_THROUGH)`, an identity
check after the commit, and cleanup on failure. `set_root_mode(0700)` and 0600
file creates install an owner-only DACL; stat maps the owner SID to a stable
`uid` and reports 0600 / 0700 only when the DACL grants no other trustee.
`oauth_os_win32.c` supplies BCrypt CSPRNG bytes, `ShellExecuteW` for validated
http(s) URLs, and the Unix clock. `signal_os.c` installs a
`SetConsoleCtrlHandler` that maps CTRL_C / CTRL_BREAK to SIGINT (2) and
CTRL_CLOSE / logoff / shutdown to SIGTERM (15); the service loop still owns the
bounded shutdown. SHA-256 and RS256 verification use BCrypt so the API contract
does not change when SIWC is disabled on Windows.

`linux_desktop_payload.c` supplies a synchronous Linux process-supervision primitive.
It opens `/proc/self/exe` once, validates a bounded versioned trailer, copies the
native companion and CLI worker into an owner-only temporary directory using
exclusive no-follow file creation, and runs the companion with separate argv.
The trailer checksum detects accidental corruption, not authenticity. Signals
are forwarded, exit status is preserved, and extracted files are removed after
child exit. It does not download code, interpret shell syntax, or implement UI
state. MoonBit owns desktop argument parsing, platform selection, errors and
graceful runtime shutdown. The existing signal/flush primitives are exposed to
the shared UI through runtime wrappers; UI packages contain no direct FFI.

`macos_desktop_payload.c` locates a bounded Mach-O resource section and validates
its versioned envelope, SHA-256, and both central/local ZIP headers before
extracting the complete signed app with Apple's `ditto`. Archive entries are
bounded ASCII regular files/directories; absolute paths, aliases, symlinks,
hard links, alternate-name extras, and special files are rejected. The private
version/hash cache uses a per-content no-follow lock, exclusive atomic rename,
owner/type checks, and an embedded exact path/type/mode/size/SHA-256 manifest plus strict recursive
code-signature verification on every
launch. Existing entries are never replaced. The helper preserves quarantine
from the source CLI and never invokes Gatekeeper overrides. MoonBit still owns
argument parsing, explicit app override, diagnostics, and LaunchServices launch.
The build-only `MOON_CC` adapter adds the resource before the final CLI signature;
the app retains its separate unbundled CLI helper.

The C helpers do not parse user commands, provider or MCP messages, or session
files, and do not decide which workspace operation is allowed. Return values
are primitive statuses, bytes, descriptors, or metadata for MoonBit to check.
No product protocol or approval logic is embedded in a C helper.

`runtime/host_os.mbt`, `runtime/oauth.mbt`, `runtime/service.mbt`, and
`runtime/desktop_launch.mbt` contain the
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
