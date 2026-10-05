# Provider wire protocols

This package ports the request serialization and response normalization of
DeepSeek Harness into MoonBit. The source reference is
[`deepseek-ai/deepseek-harness` at `5badb15009ae1756c3afe0ae0cef1faafc290ccc`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/llm/llm-deepseek/src),
especially `serialize.ts`, `wire-types.ts`, `messages-api.ts`, `sse.ts`, and
`translate.ts`. Source and port use the MIT license; see the repository notices.

## Public API

| API | Behavior |
| --- | --- |
| `prepare(mode, model, request)` | Return `{path, headers, body}` for an HTTP POST. No credentials or network access. |
| `decode(mode, response)` | Validate a nonstreaming JSON response and normalize it for the engine. |
| `StreamDecoder::new(mode)` | Allocate one incremental decoder for one HTTP response. |
| `decoder.feed(chunk)` | Consume a UTF-8-decoded text chunk. Return a sticky error on malformed input. |
| `decoder.finish()` | Require a complete terminal SSE event and return the normalized completion. |
| `decode_sse(mode, text)` | Convenience entry point using the same decoder for already buffered SSE. |

All fallible public functions return `Result[..., String]`. Errors use a stable
category prefix such as `INVALID_REQUEST`, `INVALID_JSON`, `PROVIDER_ERROR`,
`MALFORMED_RESPONSE`, `REFUSAL`, `STREAM_CLOSED`, or `STREAM_LIMIT`.

`deepseek` means the Messages API at `/v1/messages`. The public endpoint base is
`https://api.deepseek.com/anthropic`. The host joins the returned versioned path
without duplicating an already configured `/v1` suffix. `openai` means the Chat
Completions protocol at `/v1/chat/completions`. The returned headers contain no
secrets; authentication and endpoint selection belong to the host.

## Engine data

Requests carry a system string, messages, and tool definitions. Assistant messages
may contain `reasoning` and `{id, name, arguments}` tool calls. A tool result carries
`tool_call_id`, `content`, and optionally `is_error`. New response tool arguments
must encode a JSON object. Historical rejected arguments remain replayable:
Messages substitutes `{}` for malformed/non-object historical inputs, and Chat
Completions preserves their raw argument strings. The durable request is unchanged,
so the paired tool error remains visible for model self-correction.
Calls require immediate, matching results in history. Duplicate tool
identities and unresolved or unrelated results are rejected before HTTP.

Tool definitions contain `{name, description, input_schema, effect}`. The `effect`
field is local policy and is omitted from both wire protocols. Messages combines
adjacent user messages and tool results into content blocks. Chat Completions
preserves separate tool messages. No API keys are accepted or emitted here.

Optional request settings are `stream` (default `true`), `max_tokens` (default
`4096`), and `reasoning_effort`. DeepSeek supports `off`, `low`, `high` (default),
and `max`. The output cap is a port default and deliberately differs from
upstream's deployment defaults. Setting `stream: false` changes the returned
`Accept` header to `application/json`.

Responses become:

```json
{
  "ok": true,
  "content": "Assistant text",
  "reasoning": "Optional reasoning text",
  "tool_calls": [{"id": "call_1", "name": "read_file", "arguments": "{\"path\":\"README.md\"}"}],
  "finish_reason": "tool_calls",
  "usage": {"input_tokens": 12, "output_tokens": 9}
}
```

The finish reason is `stop`, `tool_calls`, or `length`. Refusals and invalid JSON
objects are errors. A `length` completion has an empty tool-call array so a
truncated generation cannot execute actions. Usage preserves the provider's
cumulative counters; OpenAI prompt/completion counters become input/output
counters, and cached prompt tokens are reported separately.

## Streaming and limits

The parser accepts CR, LF, CRLF, initial BOMs, comments, and multiline `data`
fields across arbitrary chunks. It holds the current frame and accumulated
content, not the whole SSE transcript. OpenAI tool identities, names, arguments,
content, and reasoning can arrive in fragments. Messages enforces block lifecycle
and combines thinking, text, tool-input, signature, and usage events.

Transport EOF never implies successful completion. OpenAI requires a finish
reason followed by a framed `[DONE]`; Messages requires `message_start`, closed
content blocks, a stop reason, and `message_stop`. An unterminated tail, error
event, mismatched SSE event name, duplicate block or tool ID, or data after the
terminal event fails. A failure cannot be cleared by feeding more data.

The fixed parser limits are 16 Mi UTF-16 code units for the full response, 1 Mi
code units per data frame, 1 Mi characters per line, and indexes 0–1023 for content
blocks/tools. The host must use a streaming UTF-8 decoder before `feed`; this
package operates on strings rather than network bytes.

## Current port scope

Text, reasoning, function tools, tool results, token usage, nonstreaming responses,
and incremental SSE decoding are implemented. Network cancellation, timeouts,
HTTP retries, and authentication are host responsibilities. Image upload and
Files API fallback, mid-conversation system/tool updates, provider model
discovery, and native thinking-signature replay metadata are outside this first
package. Signature deltas are parsed and checked but the engine's current
normalized text format does not persist them. This package does not claim full
upstream provider feature parity.

## Verification

The keyless tests cover exact request fixtures, correlation failures, response
normalization, errors and refusals, arbitrary chunk boundaries, Unicode,
CR/LF/CRLF, tool fragments, block lifecycle, missing terminal events, truncated
JSON, and bounded buffering. Run `moon test --target js -p provider` or
`moon test --target native -p provider`. They make no paid API calls.
