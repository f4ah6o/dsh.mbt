# Issue #9 / #11 implementation and acceptance status

Updated: 2026-10-08. This records current ownership plus the dated implementation increments below. “Fixture pass” means deterministic local tests passed; it does not imply live provider, tailnet, or physical-device acceptance. The proposals remain open for the external gates below.

## Issue #9: Sign in with ChatGPT

The native host supports the public OpenAI Responses endpoint with either an explicit Platform API key or SIWC. SIWC uses host-browser OAuth with loopback callback, PKCE, verified OIDC identity, account-visible model discovery, protected credential storage, serialized refresh rotation, and model selection. Native UI/API projections do not expose access, refresh, or ID tokens. Selecting ChatGPT auth requires Responses and never falls back to API-key billing. As of 2026-10-08 the Node host is retired; the native MoonBit executable is the only product runtime for CLI, HTTP/MCP, provider, tool, and persistence behavior. Browser and service-worker JavaScript are generated from MoonBit packages. Node remains test/build tooling only.

Deterministic OAuth/JWKS, callback, credential-generation, refresh-rotation, protected-store, provider request/stream, and error-normalization fixtures are implemented. A live sign-in, model discovery against a real account, and a harmless request reaching response.completed have **not** been run. Remote/headless sign-in is not supported: the browser must open on the native host.

The optional live sequence is in [native runtime guide](native-runtime.md#optional-live-siwc-smoke). If plan usage is disabled, sign in to ChatGPT in the host browser and check Settings → Usage. Disconnect with the native sign-out action before switching accounts.

## Issue #11: roadmap status

| Milestone | Status |
| --- | --- |
| M0 contract/toolchain | Implemented for the selected native target and pinned official dependencies. CI and cross-platform results remain separate checks. |
| M1 typed kernel/API | Implemented: typed IDs and command/event/effect core, validated JSON boundary, durable approval restore behavior, and generated public interfaces. |
| M2 shared client/deterministic tests | Implemented: shared protocol/client/presentation packages and browser integration. PWA bundle-update fixtures now cover the whole fetch/body/cache deadline and rollback. |
| M3 native vertical path | Implemented on the tested macOS host: native CLI/service and GPUI desktop app, workspace tools, provider/auth, checkpoint and receipt lifecycle, scheduler pool, cancellation, reload, and supervised SIGINT/SIGTERM shutdown. The desktop app uses the same runtime for session selection, prompt editing, transcript, tool approval, cancellation, and persistence; an AppKit NSEvent offline demo exercises the approved write and reload path. |
| M4 tailnet service/remote | Local synthetic HTTP service and owner/origin/receipt checks pass. Actual Tailscale Serve, remote device, and network outage acceptance are unrun. |
| M5 PWA | Shell generation refresh, offline fallback, body/cache deadline, and rollback are implemented and fixture-tested. Physical iPhone acceptance is unrun. |
| M6 Node-independent build/test | Current local no-Node verification passes with Node/npm absent: native format/check/build, 208/208 tests, CLI help, browser/service-worker asset checks, and checkpoint/approval/tool/context/reload demo. The standalone `.mbtx` wrapper resolves its separate imports; its internal repository checks/builds remain frozen. [Earlier Actions run](https://github.com/f4ah6o/dsh.mbt/actions/runs/37589966829) tested the initial M6 implementation at `8dc1ea7744ae7902938afe4b3071fabff0340b51`, before the Node-host retirement. |
| M7 iOS native | Formal gpui iOS host is not implemented. The current iOS work is a SwiftUI + generated MoonC shared-client embedding spike; its Simulator build/install/launch was reported successful. Physical-device lifecycle, memory, callback, accessibility, and tailnet tests remain unrun. |

## A01–A18 acceptance map

| ID | Result | Evidence and remaining scope |
| --- | --- | --- |
| A01 | Fixture pass | Typed command validation, rejected-operation no-mutation, stale completion, approval restore, and snapshot round-trip tests. |
| A02 | Fixture pass | Responses event lifecycle and malformed/incomplete cases, Unicode SSE string splits, plus native UTF-8 byte splitting at multibyte boundaries. Custom tool input is parsed and preserved; the local executor fails closed instead of treating it as shell. |
| A03 | Scoped pass | Retry behavior tests and the implementation-connected retry bound prove passed 1/1 goal with Z3 4.12.6. Proof covers the bounded helper, not runtime, storage, or network behavior. |
| A04 | Fixture pass | Native scheduler exercises the four-read rolling pool, barriers, ordered completion, and cancellation; portable engine pool/order tests pass. |
| A05 | Partial | Workspace, protected credential, symlink, replacement, output-bound, and process fixtures exist. Same-user deliberate rename in the final check-to-rename window is outside the POSIX guarantee; see the native runtime guide. |
| A06 | Partial | Lock, atomic persistence, reopen, pending approval, uncertain receipt recovery, Node/native writer exclusion, and SIGINT/SIGTERM shutdown with a TERM-ignoring child are covered. Exhaustive power-loss injection at every filesystem commit stage is not established. |
| A07 | Linux CI pass, macOS grep fail-closed | Ubuntu 24.04 native CI passed process timeout/output/cancellation and hard-memory-bound fixtures. macOS disables regex grep because it lacks the verified hard memory limit; the native runtime guide documents that platform difference. |
| A08 | Synthetic integration pass | The local native HTTP carrier accepted a command, completed it, returned the receipt, replayed identical payload, rejected changed payload, and recovered accepted work as uncertain after restart without replay. Shutdown signal coverage also confirms a dead child and uncertain receipt after reopen with no effect replay. Real remote-network loss is unrun. |
| A09 | Fixture pass | Approval revision and command ownership checks reject stale or mismatched operations in the local service/runtime paths. |
| A10 | Partial | Versioned snapshot, revision/cursor, and SSE paths are implemented and exercised locally. Real tailnet load, slow-client, and extended disconnect/reconnect acceptance remain unrun. |
| A11 | Synthetic integration pass | Missing/wrong owner and Host/Origin were rejected by the local fixture service; owner change invalidated old authorization/receipt access. Actual Tailscale Serve identity delivery is unrun. |
| A12 | Not run | No physical iPhone lock, app kill, network switch, tailnet reconnect, or uncertain-send recovery test. |
| A13 | Partial | This increment builds against the iOS Simulator SDK and wires `follow_latest` to the SwiftUI scroll position with an explicit jump-to-latest action. IME, keyboard resize, selection, VoiceOver, and installed-simulator behavior remain unrun here. |
| A14 | Fixture pass | Same-URL update, offline fallback, partial refresh rollback, worker-install race, stalled response-body deadline, and API/SSE/command/credential cache exclusion fixtures pass; combined web suite was 17/17 after the fix. Physical Home Screen behavior remains unrun. |
| A15 | Repository matrix pass | Current `npm test` passed: 140/140 portable MoonBit tests on each Wasm, Wasm GC, JS, and native target, plus 15 additional fixtures, 68 native package tests, 7 web tests, and the strict-CSP native-host Chromium smoke. Own warnings are 0; JavaScript syntax and pure-source / FFI inventory checks pass. |
| A16 | Local Node-absent pass; earlier CI baseline | The current `/bin/sh` local run verified Node/npm were unavailable and passed check/format, 208/208 tests, native/browser/service-worker builds, CLI help, and checkpoint/approval/tool/context/reload demo. The standalone `.mbtx` wrapper resolves its separate imports; internal repository checks/builds use `--frozen`. [Earlier Actions run](https://github.com/f4ah6o/dsh.mbt/actions/runs/37589966829) tested commit `8dc1ea7744ae7902938afe4b3071fabff0340b51`, before the Node-host retirement. |
| A17 | Partial | This increment passes a 13-scenario macOS generated-C/model harness with delayed snapshot, session, POST, receipt, and SSE callbacks plus a direct synthetic account-scope snapshot through the C ABI, alongside UTF-8/NUL and stale-handle ABI checks; the SwiftUI + MoonC app builds against the iOS Simulator SDK. These do not validate installed-simulator interaction, iOS memory, callback-after-close, IME, VoiceOver, or physical-device lifecycle. Formal gpui iOS host remains unimplemented. |
| A18 | Scoped evidence | QuickCheck: engine command sequences 80 cases, provider Unicode SSE splits 40 cases (max size 64), and retry bounds 100 cases; each uses seed 20261007. Retry proof: 1/1 goal. Production plugin mutation: 27/27 viable mutants killed, 8 unviable, zero surviving/timeouts; this measures plugins only. Engine benchmark is recorded below and shows no measurable speedup; per-operation allocation profiling is unavailable. |

## Reproducible measurements

Engine benchmark command: moon bench benchmarks/engine_core --target native --release. Environment: macOS 26.5.2 arm64, 10 logical CPUs, Moon CLI 0.1.20260920 and pinned compiler 0.10.14+7d59c7ec9. Ten samples per case:

| Same one-turn trace | Mean | Sample range |
| --- | ---: | ---: |
| Typed EngineCommand | 86.06 ± 1.66 µs, 1,141 runs/sample | 84.34–88.89 µs |
| Compatibility JSON adapter | 86.41 ± 1.61 µs, 1,158 runs/sample | 84.75–89.36 µs |

The results overlap and do not support a speedup claim. /usr/bin/time -l measured 286,081,024 bytes maximum RSS for the whole command, including the Moon toolchain/build; this is not per-operation memory. No runtime/native mutation score is claimed.

Native storage can migrate supported legacy session snapshots and Session v4 inputs into the native versioned envelope on first open. This conversion is one-way; older Node-host readers refuse that envelope. Back up before native startup and do not reopen the upgraded directory with an older writer; see the [native runtime guide](native-runtime.md#data-directory-compatibility). The retired host test replacement and coverage boundaries are listed in the [retirement crosswalk](node-host-retirement-test-crosswalk.md).

At the earlier M6 baseline, local npm tests and both Ubuntu Actions jobs passed at `8dc1ea7744ae7902938afe4b3071fabff0340b51` ([run](https://github.com/f4ah6o/dsh.mbt/actions/runs/37589966829)); that CI result predates the Node-host retirement. The current local `npm test` and no-Node verifier results are recorded in [verification record](verification.md). Live SIWC account smoke, actual Tailscale Serve, formal gpui iOS host, and physical iPhone gates remain unrun or unimplemented.

## 2026-10-07 iOS client lifecycle increment

The shared Swift client now fences delayed snapshot, session, receipt, and SSE results against suspension, endpoint/account scope changes, and newer session-selection intent. A host change during a submitted command leaves its durable receipt ID uncertain; reconnect looks it up without resending and retains the draft. Multi-step sends stop before crossing an account-scope change. The SwiftUI conversation view preserves reading position and exposes a jump-to-latest action. The macOS model harness passes 13 delayed-callback/policy scenarios, the generated-C ABI smoke passes, `npm run check` passes, and Xcode builds the app for the Simulator SDK. Account-scope replacement is injected through the shared-client C ABI in the model harness; SSE response-body delivery is not covered by that fixture. These local fixtures do not establish live tailnet or physical-device behavior; A12 remains unrun, and the formal gpui iOS host remains unimplemented.
