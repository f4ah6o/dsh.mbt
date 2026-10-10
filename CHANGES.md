# Changes

## Unreleased

### Added

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

## 0.1.11 - 2026-10-10

### Added

- Add ACP v1 `session/set_config_option` with persistent per-session model selection, a bounded `DSH_ACP_MODELS` catalog, and a fixed provider/auth route. Active turns reject changes; retries and foreground subagents keep the admitted session model. Resume refuses a saved selection when its protocol/auth/normalized API-root fingerprint or permitted catalog no longer matches. Credentials and account identities remain host-managed. See the [native runtime guide](docs/native-runtime.md#acp-stdio-agent), [remaining port work](issues/open/0001-upstream-parity.md), and pinned upstream [`model-control.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/model-control.ts) / [`session.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/acp/acp/src/session.ts).

### Changed

### Fixed

- Keep fatal ACP argument, startup, carrier, and shutdown diagnostics on stderr with a nonzero exit. The native runtime's `abort` diagnostic could otherwise corrupt ACP's JSON-RPC stdout stream; checkpoint-failure regression coverage verifies no model update is emitted and later requests remain fenced.

### Deprecated

### Removed

### Security

### Migration

- Native envelopes from dsh 0.1.10 remain readable. Existing ACP records without a saved model adopt the current startup model when resumed; records with saved selections require the same route fingerprint and an available model. Use dsh 0.1.11+ to preserve model and route metadata when rewriting the envelope.

## 0.1.10 - 2026-10-10

### Added

- Add persistent ACP `session/list` and `session/resume` for registered root sessions, with canonical workspace filtering, bounded pagination, saved-context continuation, and no replay of old updates or effects. Existing native sessions without ACP provenance are not adopted. See the [native runtime guide](docs/native-runtime.md#acp-stdio-agent) and [remaining port work](issues/open/0001-upstream-parity.md).

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

- Native v1 envelopes without ACP provenance remain readable; sessions already present in those envelopes are not inferred from an `acp-` ID and do not appear in ACP list/resume. Use dsh 0.1.10+ while preserving ACP metadata; older native readers may drop the added registry when rewriting the envelope, so back up before downgrading.

## 0.1.9 - 2026-10-10

### Added

- Add opt-in native foreground subagents with a real bounded child model/tool loop, parent-child correlation, read-only workspace tools, parent cancellation propagation, and restore without replay. See the [native runtime guide](docs/native-runtime.md#foreground-subagents) and [remaining port work](issues/open/0001-upstream-parity.md).

### Changed

### Fixed

- Preserve the child provider terminal error in a failed subagent result instead of misreporting a final-step provider failure as the step limit.
- Capture browser session-row text and geometry from one DOM snapshot in the smoke test, avoiding a detach/rerender race while retaining the readable-row thresholds.
- Wait for service-worker shell assets by polling awaited CacheStorage snapshots; Playwright does not await promises returned by a waitForFunction predicate.

### Deprecated

### Removed

### Security

- Child agents receive only `read`, `glob`, and `grep` tools, with the parent's SafeRoot and protected-store checks. Explicitly configured command hooks remain trusted host code and may have side effects during child reads.

### Migration

- Stores containing native subagent calls require dsh 0.1.9 or later and `--enable-subagents` when reopening so the historical tool schema remains registered. Interrupted child work is not resumed or replayed.

## 0.1.8 - 2026-10-10

### Added

- Add the native `todo_write` session tool and visible per-session task list to provider requests, the session API, browser, and desktop transcripts. The bounded whole-list update is durably correlated with its model call and result, clears when a new turn starts, and does not create a host effect or approval. See the [native runtime guide](docs/native-runtime.md#native-session-todo-tool) and [remaining port work](issues/open/0001-upstream-parity.md).

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

- Native runtime accepts existing 0.1.7 stores, including sessions near the capacity limit, and preserves their historical `Unknown tool: todo_write` result without replaying the call. Histories containing native `todo/write` events require dsh 0.1.8 or later; keep a pre-upgrade data-directory backup if you need to downgrade.

## 0.1.7 - 2026-10-10

### Added

- Add opt-in native LSP navigation for `run`, `web`, `mcp`, `acp`, and `desktop` through `--lsp-config PATH`, with per-call approval and a bounded four-operation local-server subset. ([native runtime guide](docs/native-runtime.md#native-lsp-navigation), [remaining port work](issues/open/0001-upstream-parity.md))

### Changed

### Fixed

### Deprecated

### Removed

### Security

- Configured LSP commands run as trusted host code when `--lsp-config` is supplied; calls require approval by default.

### Migration

- Reopen a data directory with a persisted LSP catalog using the matching `--lsp-config`; dsh 0.1.7 or later can adopt a first catalog only when there are no historical LSP calls.

## 0.1.6 - 2026-10-10

### Added

- Add a native ACP stdio agent at `dsh acp`. The bounded ACP v1 subset supports initialization, authentication handshake, durable sessions, text and resource-link prompts, one-shot tool approval, cancellation, close, and committed session updates. It uses the native runtime and does not replay interrupted provider or tool work. Unsupported ACP features and limits are listed in the [native runtime guide](docs/native-runtime.md#acp-stdio-agent).

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

## 0.1.5 - 2026-10-09

### Added

- Add explicit `--hooks-config PATH` support to native `run`, `web`, `mcp`, and `desktop` for bounded PreToolUse and PostToolUse command hooks. The supported literal matcher, command/result subset, limits, and upstream differences are documented in the [native runtime guide](docs/native-runtime.md#native-command-hooks).

### Changed

- A matching PostToolUse hook checkpoints the actual host tool outcome before the hook runs, so cancellation or restart can settle that known outcome without replaying the tool.

### Fixed

### Deprecated

### Removed

### Security

- Hook commands are trusted host shell code and run only when an explicit config path is supplied. Their environment is rebuilt from a small allowlist and does not inherit provider credentials.

### Migration

- Stores with `effect-known` events require dsh 0.1.5 or later; dsh 0.1.4 and earlier reject that event source. dsh 0.1.5 continues to read earlier native snapshots.

## 0.1.4 - 2026-10-09

### Added

- Add opt-in native workspace skills for `dsh run`, `web`, `mcp`, and `desktop`. `--enable-skills` scans `.dsh/skills` and `.agents/skills`; repeatable workspace-relative `--skill-dir` adds custom roots. A model-facing read-only loader returns bounded skill instructions, while a leading user `/name` invokes only user-enabled skills. This is a static workspace-only subset; it does not load Cordis/npm plugins or execute skill scripts. ([native runtime guide](docs/native-runtime.md#workspace-skills), [remaining port work](issues/open/0001-upstream-parity.md))

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

- Keep `--enable-skills` enabled when reopening a store with historical skill tool calls; the engine requires their registered tool schema during restore. Stores without historical skill calls can opt in to skills when reopened.

## 0.1.3 - 2026-10-09

### Added

- Add an opt-in native MCP stdio client for `dsh run`, `web`, `mcp`, and `desktop`, configured with `--mcp-config`. It discovers and routes bounded tool catalogs and injects child environment values by host variable name. Every external tool call requires approval by default; foreground `dsh run` can auto-approve a specific public tool name through `--approve-tools`. Native persistence fingerprints the discovered catalog so incompatible schemas cannot be adopted on reopen. The implementation supports a bounded JSON Schema subset and text results; it does not implement MCP task execution or remote transports. ([native runtime guide](docs/native-runtime.md#external-mcp-stdio-tools), [remaining port work](issues/open/0001-upstream-parity.md))

### Changed

- Native-only session stores created before 0.1.3 can adopt their first external MCP catalog when they have no historical `mcp__` tool calls. Once a catalog has been persisted, later opens require the same discovered tool catalog.

## 0.1.2 - 2026-10-09

### Added

- Browser and native desktop now keep ChatGPT SIWC account and model controls in a dedicated Settings page, with sign-in, sign-out, model refresh, and model selection available there.
- `dsh` の source install と release binary に browser assets を埋め込み、checkout 外でも `dsh web` を使えるようにした。`--assets-dir` は明示的な asset override として引き続き使える。
- macOS 13+ / Apple Silicon 向けの native GPUI `Dsh.app` と `dsh desktop` launcher を追加した。session、prompt、tool approval、cancel、transcript は既存の native runtime と durable store を共有する。release app は ad-hoc signed で、Developer ID signed / notarized ではない。IME composition は現 GPUI text host の制約により未対応。([native desktop guide](docs/desktop.md))
- OpenAI Responses API に API key / ChatGPT SIWC の native provider 経路を追加した。SIWC は OAuth・PKCE・OIDC 検証、保護された credential store、model discovery、refresh rotation を使う。実アカウント smoke は未実行。
- Node を実行依存としない MoonBit native CLI / loopback service、永続 command receipt、snapshot / SSE 同期、最大 4 件の Read pool、session 単位 cancel、共有 client と SwiftUI + MoonC iOS embedding spike を追加した。gpui iOS host は未実装。
- typed command / event / effect API、再試行上限の小さな moon prove 対象、native verification の .mbtx entry point を追加した。
- 完了済み / idle の native session 向けに、元の tool output を保持しながら将来の provider context を縮める手動 pruning を API、CLI、browser UI に追加した。canonical session の保存上限は引き続き適用する。([残りの移植作業](issues/open/0001-upstream-parity.md))
- 完了済みなどの native v1 conversation を、履歴を保った独立した会話へ分岐できるようにした。native CLI と browser の **Fork conversation** が使え、fork lineage と再採番した effect / retry identity は restore 時に検証する。upstream Session v4 writer や runtime parity は含まない。([残りの移植作業](issues/open/0001-upstream-parity.md))

### Changed

- Browser UI を日本語化し、日本語フォント、プロジェクト / Git branch、provider と選択 model を表示するようにした。Session log の公式 API upload はなく、既定で無効のまま。iOS UI は対象外。
- Browser UI を Yami-kumo application shell に移し、会話検索、responsive な navigation / context drawer、live session details を追加した。browser / service worker は MoonBit package から生成し、UI の送信、承認、fork、trim は native v1 API に接続する。
- Yami-kumo を Git submodule から Mooncakes の `f4ah6o/yami_kumo@0.1.0` dependency に切り替えた。fresh checkout の service 起動前に build が必要で、browser JavaScript と service worker は Git 管理しない。
- native host の Tailscale Serve は `DSH_TAILNET_PORT` で HTTPS port を指定できる。未指定時は 443 を使う。
- ローカル browser UI の ChatGPT sign-in は同じ browser の新しい tab で完了する。Tailnet client の sign-in や account 切り替えは host Mac 上の dsh から開始する。

### Fixed

- ChatGPT action errors remain visible in Settings and stay available in the conversation if a pending action fails after Settings closes. Native model lists clamp their scroll position after catalog changes and show each provider's display name.
- iOS shared-client integration fences late snapshot, session, receipt, and event-stream results after suspension or endpoint/account changes. A host change during a submitted command retains its uncertain receipt ID and draft without replay; multi-step sends stop before crossing an account-scope change. The conversation view follows new messages only while near the latest position and offers an explicit jump action.
- ChatGPT Responses の SSE で Content-Type 省略を許容し、completed.output が空でも completed status と output_item.done の内容が streamed delta と一致した場合だけ完了扱いにする。検証済みの completed event が届いた後は HTTP EOF を待たず応答を返す。また native host は各 provider の text / reasoning delta を重複なく投影し、大きな delta を Unicode scalar の境界で分割する。
- ChatGPT の model picker で選んだ model が確実に有効になるようにした。
- native service を停止した直後に、同じ loopback port で再起動できるようにした。
- ChatGPT へのサインイン完了後にモデル一覧を自動取得し、取得失敗時は再試行できるようにした。

### Deprecated

### Removed

- Node.js product host と handwritten JavaScript / React browser runtime を削除した。MoonBit native executable が CLI、HTTP/MCP、provider、tool、storage runtime を所有し、browser JavaScript / service worker は compiler output とする。Node.js / npm は test/build tooling に限り、production runtime dependency はない。旧 host suites の移行範囲と未移植の細かな injection cases は[retirement crosswalk](docs/node-host-retirement-test-crosswalk.md)に記録した。

### Security

- SIWC credential は native host の owner-only store に保管する。ChatGPT plan request は Platform API key 課金へ自動 fallback しない。

### Migration

- Native v1 は versioned data envelope と command receipt を保存する。対応する legacy snapshot / Session v4 input は native envelope に一方向更新する。旧版 Node-host reader は native envelope を拒否するため、初回 native 起動前に backup し、更新済み data directory を旧版 writer に戻さない。
