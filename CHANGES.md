# Changes

## Unreleased

### Added

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

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
