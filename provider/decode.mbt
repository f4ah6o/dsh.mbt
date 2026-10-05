// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Messages normalization follows deepseek-ai/deepseek-harness
// packages/llm/llm-deepseek/src/translate.ts at
// 5badb15009ae1756c3afe0ae0cef1faafc290ccc.

///|
/// Decode a complete provider JSON response into an engine completion.
/// Unsupported content, provider errors and invalid tool arguments are errors.
/// A length-limited response never exposes executable tool calls.
pub fn decode(mode : String, response : Json) -> Result[Json, String] {
  try decode_impl(mode, response) catch {
    ProviderError(message) => Err(message)
  } noraise {
    value => Ok(value)
  }
}

///|
fn decoded_call(
  id : String,
  name : String,
  arguments : String,
  seen : Map[String, Bool],
) -> Json raise ProviderError {
  if id.is_empty() || name.is_empty() {
    reject("MALFORMED_RESPONSE", "tool id and name must not be empty")
  }
  if seen.contains(id) {
    reject("MALFORMED_RESPONSE", "duplicate tool call id")
  }
  seen[id] = true
  ignore(parse_object(arguments, "tool arguments"))
  {
    "id": id.to_json(),
    "name": name.to_json(),
    "arguments": arguments.to_json(),
  }
}

///|
fn decode_impl(mode : String, response : Json) -> Json raise ProviderError {
  validate_mode(mode)
  let response = object(response, "response")
  reject_provider_error(response)
  let usage : Map[String, Json] = Map([])
  match response.get("usage") {
    None | Some(Null) => ()
    Some(value) => update_usage(mode, usage, value)
  }
  let calls : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let content = StringBuilder()
  let reasoning = StringBuilder()
  let reason = if mode == "deepseek" {
    if text_field(response, "type") != "message" ||
      text_field(response, "role") != "assistant" {
      reject("MALFORMED_RESPONSE", "expected an assistant message")
    }
    let reason = normalized_reason(mode, text_field(response, "stop_reason"))
    for raw in array(field(response, "content"), "content") {
      let block = object(raw, "content block")
      match text_field(block, "type") {
        "text" => content.write_string(text_field(block, "text"))
        "thinking" => reasoning.write_string(text_field(block, "thinking"))
        "tool_use" => {
          let id = identity(block, "id")
          let name = identity(block, "name")
          if reason != "length" {
            let input = field(block, "input")
            ignore(object(input, "tool input"))
            calls.push(decoded_call(id, name, input.stringify(), seen))
          }
        }
        kind =>
          reject("UNSUPPORTED_CONTENT", "unsupported Messages block " + kind)
      }
    }
    reason
  } else {
    let choices = array(field(response, "choices"), "choices")
    if choices.length() != 1 {
      reject("MALFORMED_RESPONSE", "expected exactly one completion choice")
    }
    let choice = object(choices[0], "choice")
    let reason = normalized_reason(mode, text_field(choice, "finish_reason"))
    let message = object(field(choice, "message"), "assistant message")
    if text_field(message, "role") != "assistant" {
      reject("MALFORMED_RESPONSE", "expected an assistant message")
    }
    if message.contains("function_call") {
      reject("UNSUPPORTED_CONTENT", "legacy function_call is not supported")
    }
    match optional_text(message, "refusal") {
      Some(refusal) if !refusal.is_empty() => reject("REFUSAL", refusal)
      _ => ()
    }
    content.write_string(optional_text(message, "content").unwrap_or(""))
    reasoning.write_string(
      optional_text(message, "reasoning_content").unwrap_or(""),
    )
    for raw in optional_array(message, "tool_calls") {
      let call = object(raw, "tool call")
      if text_field(call, "type") != "function" {
        reject("UNSUPPORTED_CONTENT", "only function tool calls are supported")
      }
      let id = identity(call, "id")
      let function = object(field(call, "function"), "function")
      let name = identity(function, "name")
      if reason != "length" {
        calls.push(
          decoded_call(id, name, text_field(function, "arguments"), seen),
        )
      }
    }
    reason
  }
  result_json(content.to_string(), reasoning.to_string(), calls, reason, usage)
}
