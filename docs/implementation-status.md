# Issue #9 / #11 implementation and acceptance status

Updated: 2026-10-07. This records the implementation increment in this branch. “Fixture pass” means deterministic local tests passed; it does not imply live provider, tailnet, or physical-device acceptance. The proposals remain open for the external gates below.

## Issue #9: Sign in with ChatGPT

The native host now supports the public OpenAI Responses endpoint with either an explicit Platform API key or SIWC. SIWC uses host-browser OAuth with loopback callback, PKCE, verified OIDC identity, account-visible model discovery, protected credential storage, serialized refresh rotation, and model selection. Native UI/API projections do not expose access, refresh, or ID tokens. Selecting ChatGPT auth requires Responses and never falls back to API-key billing. The existing Node host remains available for its previous provider modes; the new native SIWC path adds no Node business logic.

Deterministic OAuth/JWKS, callback, credential-generation, refresh-rotation, protected-store, provider request/stream, and error-normalization fixtures are implemented. A live sign-in, model discovery against a real account, and a harmless request reaching response.completed have **not** been run. Remote/headless sign-in is not supported: the browser must open on the native host.

The optional live sequence is in [native runtime guide](native-runtime.md#optional-live-siwc-smoke). If plan usage is disabled, sign in to ChatGPT in the host browser and check Settings → Usage. Disconnect with the native sign-out action before switching accounts.

## Issue #11: roadmap status

| Milestone | Status |
| --- | --- |
| M0 contract/toolchain | Implemented for the selected native target and pinned official dependencies. CI and cross-platform results remain separate checks. |
| M1 typed kernel/API | Implemented: typed IDs and command/event/effect core, validated JSON boundary, durable approval restore behavior, and generated public interfaces. |
| M2 shared client/deterministic tests | Implemented: shared protocol/client/presentation packages and browser integration. PWA bundle-update fixtures now cover the whole fetch/body/cache deadline and rollback. |
| M3 native vertical path | Implemented on the tested macOS host: native CLI/service, workspace tools, provider/auth, checkpoint and receipt lifecycle, scheduler pool, cancellation, reload, and supervised SIGINT/SIGTERM shutdown. |
| M4 tailnet service/remote | Local synthetic HTTP service and owner/origin/receipt checks pass. Actual Tailscale Serve, remote device, and network outage acceptance are unrun. |
| M5 PWA | Shell generation refresh, offline fallback, body/cache deadline, and rollback are implemented and fixture-tested. Physical iPhone acceptance is unrun. |
| M6 Node-independent build/test | A local Node/npm-absent PATH run passed the native verifier: native checks, 159/159 tests, native/app/client builds, CLI help, and the checkpoint/approval/tool/context/reload demo. In CI, the outer standalone `.mbtx` command is non-frozen to resolve its separate source imports; the repository checks/builds it invokes remain frozen. The previous Ubuntu CI runs failed during cold import bootstrap; the corrected workflow awaits its next Actions run. |
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
| A07 | Partial | Native process timeout/output/cancellation fixtures run on the current host. macOS disables regex grep because it lacks the verified hard memory limit; Linux resource behavior still needs its clean CI run. |
| A08 | Synthetic integration pass | The local native HTTP carrier accepted a command, completed it, returned the receipt, replayed identical payload, rejected changed payload, and recovered accepted work as uncertain after restart without replay. Shutdown signal coverage also confirms a dead child and uncertain receipt after reopen with no effect replay. Real remote-network loss is unrun. |
| A09 | Fixture pass | Approval revision and command ownership checks reject stale or mismatched operations in the local service/runtime paths. |
| A10 | Partial | Versioned snapshot, revision/cursor, and SSE paths are implemented and exercised locally. Real tailnet load, slow-client, and extended disconnect/reconnect acceptance remain unrun. |
| A11 | Synthetic integration pass | Missing/wrong owner and Host/Origin were rejected by the local fixture service; owner change invalidated old authorization/receipt access. Actual Tailscale Serve identity delivery is unrun. |
| A12 | Not run | No physical iPhone lock, app kill, network switch, tailnet reconnect, or uncertain-send recovery test. |
| A13 | Partial | Simulator build/install/launch passed in the parent’s Xcode run. IME, keyboard resize, selection, and VoiceOver acceptance are unrun. |
| A14 | Fixture pass | Same-URL update, offline fallback, partial refresh rollback, worker-install race, stalled response-body deadline, and API/SSE/command/credential cache exclusion fixtures pass; combined web suite was 17/17 after the fix. Physical Home Screen behavior remains unrun. |
| A15 | Repository matrix pass | Final `npm test` passed: 128/128 MoonBit tests on each Wasm, Wasm GC, JS, and native target, plus 31 native suite cases, 42 host, 17 web, and 44 integration tests; own warnings 0 and JavaScript syntax 34 files. Generated .mbti is tracked. |
| A16 | Local Node-absent pass | A `/bin/sh` run verified Node and npm were unavailable with PATH limited to Moon and OS tools. The local native verifier passed check/format, 159/159 tests, native/app/client builds, CLI help, and checkpoint/approval/tool/context/reload demo using its warm Moon cache. In cold CI, only the standalone `.mbtx` wrapper runs non-frozen to resolve its separate source imports; its internal repository checks/builds use `--frozen`. The dedicated Ubuntu 24.04 Actions result remains pending. |
| A17 | Partial | A macOS generated-C harness passed three URLProtocol scenarios plus UTF-8/NUL and stale-handle ABI checks; separately, the SwiftUI + MoonC Simulator build/install/launch passed. These do not validate iOS memory, callback-after-close, IME, VoiceOver, or physical-device lifecycle. Formal gpui iOS host remains unimplemented. |
| A18 | Scoped evidence | QuickCheck: engine command sequences 80 cases, provider Unicode SSE splits 40 cases (max size 64), and retry bounds 100 cases; each uses seed 20261007. Retry proof: 1/1 goal. Production plugin mutation: 27/27 viable mutants killed, 8 unviable, zero surviving/timeouts; this measures plugins only. Engine benchmark is recorded below and shows no measurable speedup; per-operation allocation profiling is unavailable. |

## Reproducible measurements

Engine benchmark command: moon bench benchmarks/engine_core --target native --release. Environment: macOS 26.5.2 arm64, 10 logical CPUs, Moon CLI 0.1.20260920 and pinned compiler 0.10.14+7d59c7ec9. Ten samples per case:

| Same one-turn trace | Mean | Sample range |
| --- | ---: | ---: |
| Typed EngineCommand | 86.06 ± 1.66 µs, 1,141 runs/sample | 84.34–88.89 µs |
| Compatibility JSON adapter | 86.41 ± 1.61 µs, 1,158 runs/sample | 84.75–89.36 µs |

The results overlap and do not support a speedup claim. /usr/bin/time -l measured 286,081,024 bytes maximum RSS for the whole command, including the Moon toolchain/build; this is not per-operation memory. No runtime/native mutation score is claimed.

Native storage can migrate supported legacy session snapshots and Session v4 inputs into the native versioned envelope on first open. This conversion is one-way because the Node reader refuses that envelope. Back up before native startup and do not alternate writers; see the [native runtime guide](native-runtime.md#data-directory-compatibility).

The final local full npm test and local Node-absent verifier pass. The dedicated Ubuntu Node-absent Actions job, live SIWC account smoke, actual Tailscale Serve, and physical iPhone gates remain pending. See [verification record](verification.md) for exact commands and scope.
