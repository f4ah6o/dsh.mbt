# OpenCode free chat models

## Configuration

```sh
DSH_AUTH=none dsh web --mode openai --model deepseek-v4.1-flash-free \
  --base-url https://opencode.ai/inference/openai/v1
```

For one turn, use `dsh run 'Reply with exactly DSH_OK.'` with the same environment and provider options. A new data directory avoids a previously persisted explicit ChatGPT provider choice. In an existing host, choose the configured provider to return from ChatGPT SIWC. API keys and SIWC continue to use their existing paths; omission of a key never enables no-auth implicitly. No-auth is startup configuration, including for child agents and retries.

The equivalent environment-only settings are:

```sh
export DSH_AUTH=none
export DSH_MODE=openai
export DSH_MODEL=deepseek-v4.1-flash-free
export DSH_BASE_URL=https://opencode.ai/inference/openai/v1
```

Do not set a placeholder API key. No-auth ignores `DSH_API_KEY`, `OPENAI_API_KEY`, and `DEEPSEEK_API_KEY`, and sends no credential headers or cookies. Invalid roots, missing roots, and empty models are rejected before dispatch. The selected model ID is sent verbatim; the OpenCode CLI's `opencode/` provider prefix is not part of an Inference API model ID. Authentication failures remain terminal; rate limits and server failures use the existing bounded retry policy. Provider response bodies are excluded from normalized errors.

## Catalogue checked on 2026-10-15

Sources:

- [Inference API and authentication](https://dev.opencode.ai/v2/docs/console/api/inference)
- [Model endpoints, free pricing, and data handling](https://dev.opencode.ai/v2/docs/console/models)
- [Live model IDs](https://opencode.ai/inference/v1/models)

The following IDs appeared in the live list and in the official free Chat Completions model table:

| Model ID | API family |
| --- | --- |
| `big-pickle` | Chat Completions |
| `cat-jam-free` | Chat Completions |
| `deepseek-v4.1-flash-free` | Chat Completions |
| `longcat-2.5-preview-free` | Chat Completions |
| `mimo-v2.6-flash-free` | Chat Completions |
| `nemotron-3.5-lightning-free` | Chat Completions |
| `space-bunny-free` | Chat Completions |
| `step-5-preview-free` | Chat Completions |

The live list alone does not specify price or API family. For example, the official table puts `muse-spark-1.3-contributor-free` on Responses, and `jev-1.13-free` uses SystemOne; neither belongs on this Chat Completions route. Some documented free models were absent from the live list. Availability, free periods, and data policies can change, so recheck both sources before selecting a model. No catalogue is hardcoded into the runtime.

The Inference API reference specifies `/inference/openai/v1/chat/completions`; the models table also lists `/inference/v1/chat/completions`. This example uses the explicit OpenAI-family path from the API reference.

## Live verification

Unauthenticated curl JSON POSTs from this environment to the explicit OpenAI-family endpoint, using only synthetic `Reply with exactly DSH_OK.` prompts and `stream: true`, returned HTTP 403 for `deepseek-v4.1-flash-free` and `big-pickle`:

```json
{"type":"error","error":{"type":"FreeTierError","message":"OpenCode's free tier can only be used from within OpenCode. Download it at https://opencode.ai and keep building."}}
```

This differs from the API reference's statement that free chat models can be called without an Authorization header. Model discovery succeeded; direct free inference did not. Conversation, real SSE deltas, and real tool calling through OpenCode remain unverified. Local HTTP fixtures verify those protocol behaviors independently. The implementation does not impersonate the OpenCode client, retry with credentials, or change providers on a 403.

The freshly built native `dsh run` was also attempted against that endpoint with `DSH_AUTH=none`, a synthetic prompt, and zero retries. This restricted environment returned a normalized transport connection failure before an HTTP response was obtained; it did not reach `AUTH_REQUIRED`. The CLI process exited 0 while its JSON session status was `failed`; that exit code is not evidence of a successful conversation. The 403 observations above belong to curl, which can use this environment's network proxy.
