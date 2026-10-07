# Changes

## Unreleased

### Added

- OpenAI Responses API に API key / ChatGPT SIWC の native provider 経路を追加した。SIWC は OAuth・PKCE・OIDC 検証、保護された credential store、model discovery、refresh rotation を使う。実アカウント smoke は未実行。
- Node を実行依存としない MoonBit native CLI / loopback service、永続 command receipt、snapshot / SSE 同期、最大 4 件の Read pool、session 単位 cancel、共有 client と SwiftUI + MoonC iOS embedding spike を追加した。gpui iOS host は未実装。
- typed command / event / effect API、再試行上限の小さな moon prove 対象、native verification の .mbtx entry point を追加した。
- 完了済み / idle の native session 向けに、元の tool output を保持しながら将来の provider context を縮める手動 pruning を API、CLI、browser UI に追加した。canonical session の保存上限は引き続き適用する。([残りの移植作業](issues/open/0001-upstream-parity.md))

### Changed

- native host の Tailscale Serve は `DSH_TAILNET_PORT` で HTTPS port を指定できる。未指定時は 443 を使う。
- ローカル browser UI の ChatGPT sign-in は同じ browser の新しい tab で完了する。Tailnet client の sign-in や account 切り替えは host Mac 上の dsh から開始する。

### Fixed

- ChatGPT Responses の SSE で Content-Type 省略を許容し、completed.output が空でも completed status と output_item.done の内容が streamed delta と一致した場合だけ完了扱いにする。検証済みの completed event が届いた後は HTTP EOF を待たず応答を返す。また native host は各 provider の text / reasoning delta を重複なく投影し、大きな delta を Unicode scalar の境界で分割する。
- ChatGPT の model picker で選んだ model が確実に有効になるようにした。
- native service を停止した直後に、同じ loopback port で再起動できるようにした。
- ChatGPT へのサインイン完了後にモデル一覧を自動取得し、取得失敗時は再試行できるようにした。

### Deprecated

### Removed

### Security

- SIWC credential は native host の owner-only store に保管する。ChatGPT plan request は Platform API key 課金へ自動 fallback しない。

### Migration

- Native v1 は versioned data envelope と command receipt を保存する。対応する legacy snapshot / Session v4 input は native envelope に一方向更新する。Node host は native envelope を拒否するため、初回 native 起動前に backup し、両 host で同じ data directory を交互利用しない。
