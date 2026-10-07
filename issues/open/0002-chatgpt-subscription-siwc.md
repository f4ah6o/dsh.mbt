# 0002: Sign in with ChatGPT で ChatGPT subscription を利用する

状態: 実装差分あり / open。fixture 検証済み、実アカウント SIWC smoke は未実行。
Model: gpt-5.6-sol
Updated: 2026-10-07

実装結果と残る受入条件は[実装状況](../../docs/implementation-status.md#issue-9-sign-in-with-chatgpt)に記録する。

## 目的

`dsh.mbt` から OpenAI Platform API key とは別に、OpenAI の **Sign in with ChatGPT (SIWC)** を使って、
利用者自身の ChatGPT Plus / Pro の利用枠で対象モデルを実行できる経路を追加する。

OpenAI は 2026-09-28 に OSS / local app 向けの ChatGPT plan usage を公開した。
この経路は非公開の `chatgpt.com/backend-api` を模倣せず、OAuth access token を使って
公開 `POST https://api.openai.com/v1/responses` を呼ぶ正式なフローである。

参考:

- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/token-reference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery

## 現状

以下は提案作成時点の構成を記録する。2026-10-07 の実装 increment では native host に Responses、SIWC OAuth、credential store、model discovery、account model selection を接続した。Node host の既存 API-key 経路は引き続き互換経路として残る。

現在の host provider は `deepseek` / `openai` の 2 mode を持ち、OpenAI mode は
`/v1/chat/completions` と `OPENAI_API_KEY` を前提にしている。

provider package は wire protocol の serialize / decode / SSE normalization を担当し、
Node.js host は HTTP / filesystem / subprocess / persistence など外部 I/O を担当している。

SIWC 対応でもこの MoonBit-first の境界を崩さない。Responses request / event schema、
OAuth / credential lifecycle の状態遷移、account / model selection の意味論は MoonBit が所有し、
host は HTTPS、system browser 起動、127.0.0.1 callback、secret の安全な保存といった
OS / I/O capability の実行だけを担当する。

SIWC を既存 `OPENAI_API_KEY` の別名として扱うことはしない。
ChatGPT plan usage は auth だけでなく Responses API 固有の request / stream contract を要求するため、
wire protocol と authentication strategy を独立に選べる設計へ進める。

## 提案する構成

概念上、次の 2 軸に分離する。protocol / auth の仕様と状態遷移は MoonBit が所有し、
host はそれを実行するための capability adapter とする。

### Wire protocol

- `deepseek-messages`
- `openai-chat-completions` — 現行互換
- `openai-responses` — 新規

### Authentication

- DeepSeek API key
- OpenAI Platform API key
- ChatGPT SIWC OAuth

`openai-responses` は API key と SIWC の双方で利用可能にする。
一方、SIWC direct route は `openai-responses` のみ許可し、Chat Completions や非公開 backend API へ流さない。

CLI / config の最終形は実装時に決めるが、意味としては以下を表現できること。

```text
provider = openai-responses
auth = chatgpt
model = <account-specific model slug>
```

既存の `--provider openai` / `OPENAI_API_KEY` の挙動は互換維持する。

## 1. SIWC OAuth

OAuth state machine は MoonBit 側で定義し、host は browser / loopback callback / HTTPS / secret persistence の
capability を提供する。初回 login は OSS client 用 dynamic registration を使う。

- system browser を開く
- callback は `127.0.0.1` loopback
- attempt ごとに fresh `state`, OIDC `nonce`, PKCE verifier / S256 challenge を生成する
- 初回は `client_id=dynamic_agent_client`
- app 名として一貫した `agent_name_hint=dsh.mbt` を送る
- host lifecycle ごとに stable `ext_agent_host_id` を生成・保存する
- scope:
  - `openid profile email`
  - `offline_access`
  - `resource.invoke`
  - `chatgpt.tokens.use.direct`
- resource は `https://api.openai.com/v1`
- callback で返る issued `client_id` を保存し、次回以降は再利用する
- token exchange に client secret / partner API key を要求しない

ID token は JWKS で署名を検証し、issuer / audience / expiry / nonce を確認する。
`chatgpt.tokens.use.direct` が grant されていない場合、login 自体は保持しても
ChatGPT plan inference は disabled とする。

## 2. Credential store と refresh

credential の schema、refresh rotation、expiry / revoke の状態遷移は MoonBit が所有し、
host は OS に適した secret persistence と atomic I/O を提供する。

credential は source tree、session log、analytics、diagnostics に出さない。

最低限保存するもの:

- verified account identity
- issued `client_id`
- stable `ext_agent_host_id`
- retained `id_token`
- `access_token`
- rotating `refresh_token`
- granted scopes
- expiry metadata

Unix では owner-only permission を前提に atomic write する。

OpenAI の現行仕様では access token は 1 時間、refresh token は 30 日。
refresh 成功時は replacement refresh token を返すため、同一 profile の refresh を serialize し、
古い refresh token を並行利用しない。

一時的な network / 5xx だけで credential を削除しない。
terminal refresh error または確認済み revoke でのみ再 login を要求する。

## 3. Responses API adapter

新しい pure provider adapter で、engine の request / tool model と Responses API を相互変換する。

SIWC direct request は少なくとも次を強制する。

- endpoint: `POST https://api.openai.com/v1/responses`
- `Authorization: Bearer <OAuth access token>`
- `store: false`
- `stream: true`
- full conversation context を `input` に送る
- HTTP direct route では `previous_response_id` に依存しない
- selected account が列挙した model slug を使う

現行 Chat Completions serializer に SIWC 条件分岐を追加するのではなく、
Responses request / event schema を別 adapter として持つ。

Preview で禁止されている request field は SIWC path で送らない。
特に current engine setting の `max_tokens` / reasoning knobs 等を機械的に Responses field へ写さず、
対応可否を明示した translation layer を置く。

## 4. Streaming と tool calls

SIWC の成功条件は HTTP 200 や stream EOF ではなく `response.completed` の受信とする。

最低限扱う event:

- text delta
- reasoning / summary のうち利用可能なもの
- function / custom tool call lifecycle
- usage
- `response.completed`
- `response.failed`
- `response.incomplete`

現在の live projection / effect ownership / checkpoint 境界へ接続し、
accepted delta 後の失敗で incomplete tool を実行しない。

Chat Completions の `[DONE]` terminal rule と Responses の terminal event rule は混同しない。

## 5. Model discovery

SIWC profile 選択後、同じ access token で `GET https://api.openai.com/v1/models` を呼び、
`visibility == "list"` の model を account-specific catalog として表示する。

固定 model list を entitlement として扱わない。
account / workspace の切替時には再取得する。

初回 acceptance では、列挙された model のうち 1 つで小さい Responses request が
`response.completed` まで到達することを実 access check とする。

## 6. Error と billing path の分離

ChatGPT plan usage が拒否・上限到達・利用不可になっても、
暗黙に OpenAI Platform API key 課金へ fallback しない。

明示的に区別する:

- SIWC permission missing
- account / workspace ineligible
- ChatGPT plan usage limit
- temporary admission / service failure
- expired / invalid refresh credential
- unsupported Responses capability
- ordinary provider / transport failure

API key fallback を将来入れる場合も、利用者が設定した明示的 auth order に従う。

OpenAI が返した request ID、HTTP status、stable error code は credential / prompt を含めない形で診断可能にする。

## 7. UI / CLI

最低限:

- `Sign in with ChatGPT`
- connected account / workspace の識別
- plan usage permission enabled / disabled
- account switch
- model picker
- sign out / disconnect guidance
- ChatGPT Settings → Usage への導線

browser UI と将来の gpui UI で auth state machine を共有し、
OAuth secret を browser storage へ置かない。

headless / remote host は別 increment とし、最初は local loopback browser sign-in を成立させる。

## 非目標

最初の increment では次を対象外とする。

- ChatGPT conversation history へのアクセス
- 非公開 `chatgpt.com/backend-api` の利用
- hosted Files API
- image generation
- Code Interpreter
- hosted MCP / connector invocation
- native computer use
- audio / transcription
- SIWC を使った background mode
- commercial / remotely hosted multi-tenant SaaS 化

これらは SIWC preview の capability と dsh.mbt の provider scope を分けて扱う。

## 実装順

1. MoonBit に Responses pure request / stream decoder を keyless fixture で追加する。
2. MoonBit に auth / credential lifecycle の型と状態遷移を追加し、既存 API-key path の regression を固定する。
3. host に browser / loopback callback / HTTPS / protected secret persistence の capability adapter を追加する。
4. local SIWC OAuth + refresh を MoonBit state machine と host capability の組合せで成立させる。
5. model discovery と account selection を追加する。
6. SIWC token を使う実 Responses smoke test を opt-in で追加する。
7. browser / gpui 向けの共通 auth state と model selector を接続する。

OAuth より先に Responses adapter を fixture で完成させ、認証・billing と wire correctness を同時にデバッグしない。

## 受入条件

- 既存 `deepseek` と OpenAI API-key Chat Completions の keyless regression が変わらず通る。
- Responses adapter は text / tool call / usage / failed / incomplete / completed を fixture で検証する。
- arbitrary SSE chunk / Unicode split / EOF / malformed event を fail closed で扱う。
- OAuth は state / nonce / PKCE / ID-token validation を行い、callback injection を拒否する。
- credential はログ・session・git diff に出ず、refresh rotation を安全に扱う。
- `chatgpt.tokens.use.direct` がない profile では inference を開始しない。
- SIWC request は `store:false`, `stream:true` を必ず満たす。
- private ChatGPT backend endpoint を呼ばない。
- model discovery は選択中 account の access token を使う。
- usage limit / ineligible / unsupported capability で API-key billing へ silent fallback しない。
- opt-in integration test で、利用可能 model を列挙し、1 request が `response.completed` まで到達する。
- sign out / revoked / expired credential 後に secret を残したまま無限 retry しない。

## セキュリティ確認

実装 PR では少なくとも次をレビュー対象にする。

- OAuth CSRF / callback hijack
- PKCE verifier lifecycle
- ID-token audience / nonce validation
- credential file permission
- refresh token reuse race
- authorization URL / token の log redaction
- localhost ではなく `127.0.0.1` callback の固定
- malicious provider response による unbounded buffering
- auth error と retryable transport error の混同
- account switch 中の旧 credential 混線
