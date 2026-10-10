// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Pure Responses API adapter for the public OpenAI /v1/responses route.

///|
/// Prepare a Responses request from the engine's normalized conversation.
/// Credentials and transport stay with the host. This adapter always uses the
/// stateless streaming contract required by the ChatGPT plan direct route and
/// deliberately omits engine settings that do not have a safe translation.
pub fn prepare_responses(
  model : String,
  request : Json,
) -> Result[Json, String] {
  try prepare_responses_impl(model, request) catch {
    ProviderError(message) => Err(message)
  } noraise {
    value => Ok(value)
  }
}

///|
fn prepare_responses_impl(
  model : String,
  request : Json,
) -> Json raise ProviderError {
  if model.is_empty() {
    reject("INVALID_REQUEST", "model must not be empty")
  }
  let request = object(request, "request")
  let history = array(field(request, "messages"), "messages")
  if history.is_empty() {
    reject("INVALID_REQUEST", "messages must not be empty")
  }
  let system = optional_text(request, "system").unwrap_or("")
  let input : Array[Json] = []
  let pending : Map[String, String] = Map([])
  let seen_ids : Map[String, Bool] = Map([])
  for raw in history {
    let message = object(raw, "message")
    let role = text_field(message, "role")
    if role != "tool" && !pending.is_empty() {
      reject("INVALID_REQUEST", "tool calls need immediate matching results")
    }
    let content_value = field(message, "content")
    if content_value is Array(_) &&
      (role != "user" || !has_hooks_context_source(message)) {
      reject(
        "INVALID_REQUEST", "content blocks are supported only for hooks-claude-code user messages",
      )
    }
    let content_blocks = text_content_blocks(content_value, "message")
    let content = match content_value {
      String(value) => value
      _ if role == "tool" =>
        reject("INVALID_REQUEST", "tool result content must be a string")
      _ => ""
    }
    let calls = optional_array(message, "tool_calls")
    if role != "assistant" && !calls.is_empty() {
      reject(
        "INVALID_REQUEST", "only assistant messages may contain tool calls",
      )
    }
    if role == "tool" {
      let id = identity(message, "tool_call_id")
      let kind = match pending.get(id) {
        Some(kind) => kind
        None =>
          reject("INVALID_REQUEST", "tool result has no matching pending call")
      }
      pending.remove(id)
      input.push(
        if kind == "custom" {
          {
            "type": "custom_tool_call_output",
            "call_id": id.to_json(),
            "output": content.to_json(),
          }
        } else {
          {
            "type": "function_call_output",
            "call_id": id.to_json(),
            "output": content.to_json(),
          }
        },
      )
      continue
    }
    if role != "user" && role != "assistant" {
      reject("INVALID_REQUEST", "unsupported message role " + role)
    }
    if !content.is_empty() {
      input.push({ "role": role.to_json(), "content": content.to_json() })
    } else if !content_blocks.is_empty() {
      let response_blocks : Array[Json] = content_blocks.map(block => {
        "type": "input_text".to_json(),
        "text": text_field(object(block, "text content block"), "text").to_json(),
      })
      input.push({
        "role": role.to_json(),
        "content": Json::array(response_blocks),
      })
    }
    for raw_call in calls {
      let call = object(raw_call, "tool call")
      let id = identity(call, "id")
      let name = identity(call, "name")
      let arguments = text_field(call, "arguments")
      let kind = optional_text(call, "kind").unwrap_or("function")
      if seen_ids.contains(id) {
        reject("INVALID_REQUEST", "duplicate tool call id")
      }
      match kind {
        "function" =>
          // The engine validates live model arguments. Validate historical
          // values here too so restore cannot send malformed function JSON.
          ignore(parse_object(arguments, "tool arguments"))
        "custom" =>
          if arguments.length() > 65536 {
            reject("STREAM_LIMIT", "custom tool input exceeds 65536 code units")
          }
        _ => reject("INVALID_REQUEST", "unsupported tool call kind " + kind)
      }
      seen_ids[id] = true
      pending[id] = kind
      input.push(
        if kind == "custom" {
          {
            "type": "custom_tool_call",
            "call_id": id.to_json(),
            "name": name.to_json(),
            "input": arguments.to_json(),
          }
        } else {
          {
            "type": "function_call",
            "call_id": id.to_json(),
            "name": name.to_json(),
            "arguments": arguments.to_json(),
          }
        },
      )
    }
  }
  if !pending.is_empty() {
    reject("INVALID_REQUEST", "history ends with unresolved tool calls")
  }
  if input.is_empty() {
    reject("INVALID_REQUEST", "request has no nonempty messages")
  }

  let definitions : Array[Json] = []
  let seen_tools : Map[String, Bool] = Map([])
  for raw_tool in optional_array(request, "tools") {
    let tool = object(raw_tool, "tool definition")
    let name = identity(tool, "name")
    if seen_tools.contains(name) {
      reject("INVALID_REQUEST", "duplicate tool name")
    }
    seen_tools[name] = true
    let description = text_field(tool, "description")
    let schema = field(tool, "input_schema")
    ignore(object(schema, "tool input_schema"))
    definitions.push({
      "type": "function",
      "name": name.to_json(),
      "description": description.to_json(),
      "parameters": schema,
    })
  }
  // SIWC preview accepts client functions in additional_tools input items or
  // namespaces. Keeping names unchanged lets the existing local dispatcher
  // resolve calls without a protocol-specific rename layer.
  if !definitions.is_empty() {
    input.insert(0, {
      "type": "additional_tools",
      "role": "developer",
      "tools": Json::array(definitions),
    })
  }

  let body : Map[String, Json] = {
    "model": model.to_json(),
    "input": Json::array(input),
    "store": false.to_json(),
    "stream": true.to_json(),
  }
  if !system.is_empty() {
    body["instructions"] = system.to_json()
  }
  {
    "url": "https://api.openai.com/v1/responses".to_json(),
    "path": "/v1/responses".to_json(),
    "headers": {
      "content-type": "application/json".to_json(),
      "accept": "text/event-stream".to_json(),
    },
    "body": Json::object(body),
  }
}

///|
/// Decode the account-specific `/v1/models` response. Only entries explicitly
/// marked `visibility: "list"` are returned, in the provider's order.
pub fn decode_models(response : Json) -> Result[Array[Json], String] {
  try {
    let response = object(response, "model list")
    let rows = array(field(response, "models"), "models")
    let visible : Array[Json] = []
    for raw in rows {
      let model = object(raw, "model")
      if optional_text(model, "visibility").unwrap_or("") == "list" {
        let slug = identity(model, "slug")
        let display_name = identity(model, "display_name")
        visible.push({
          "slug": slug.to_json(),
          "display_name": display_name.to_json(),
        })
      }
    }
    Ok(visible)
  } catch {
    ProviderError(message) => Err(message)
  }
}

///|
/// Normalize one non-streaming Responses object into the engine completion
/// shape. Live ChatGPT plan requests use the stricter stream decoder below.
pub fn decode_responses(response : Json) -> Result[Json, String] {
  try decode_responses_impl(response) catch {
    ProviderError(message) => Err(message)
  } noraise {
    value => Ok(value)
  }
}

///|
fn decode_responses_impl(response : Json) -> Json raise ProviderError {
  let response = object(response, "response")
  reject_provider_error(response)
  if text_field(response, "status") != "completed" {
    reject("INCOMPLETE_RESPONSE", "Responses object is not completed")
  }
  let usage : Map[String, Json] = Map([])
  match response.get("usage") {
    None | Some(Null) => ()
    Some(value) => update_usage("responses", usage, value)
  }
  let content = StringBuilder()
  let reasoning = StringBuilder()
  let calls : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  for raw_item in array(field(response, "output"), "output") {
    let item = object(raw_item, "output item")
    match text_field(item, "type") {
      "message" => {
        if text_field(item, "role") != "assistant" {
          reject("MALFORMED_RESPONSE", "expected an assistant output message")
        }
        for raw_part in array(field(item, "content"), "message content") {
          let part = object(raw_part, "message content part")
          match text_field(part, "type") {
            "output_text" => content.write_string(text_field(part, "text"))
            "refusal" => reject("REFUSAL", text_field(part, "refusal"))
            kind =>
              reject(
                "UNSUPPORTED_CONTENT",
                "unsupported Responses message content " + kind,
              )
          }
        }
      }
      "reasoning" =>
        match item.get("summary") {
          None => ()
          Some(value) =>
            for raw_part in array(value, "reasoning summary") {
              let part = object(raw_part, "reasoning summary part")
              if text_field(part, "type") == "summary_text" {
                reasoning.write_string(text_field(part, "text"))
              }
            }
        }
      "function_call" => {
        let call_id = identity(item, "call_id")
        let name = identity(item, "name")
        if seen.contains(call_id) {
          reject("MALFORMED_RESPONSE", "duplicate function call id")
        }
        let arguments = text_field(item, "arguments")
        ignore(parse_object(arguments, "function arguments"))
        calls.push(decoded_call(call_id, name, arguments, seen))
      }
      "custom_tool_call" => {
        let call_id = identity(item, "call_id")
        let name = identity(item, "name")
        let input = text_field(item, "input")
        calls.push(decoded_custom_call(call_id, name, input, seen))
      }
      kind =>
        reject(
          "UNSUPPORTED_CONTENT",
          "unsupported Responses output item " + kind,
        )
    }
  }
  result_json(
    content.to_string(),
    reasoning.to_string(),
    calls,
    if calls.is_empty() {
      "stop"
    } else {
      "tool_calls"
    },
    usage,
  )
}

///|
fn decoded_custom_call(
  id : String,
  name : String,
  input : String,
  seen : Map[String, Bool],
) -> Json raise ProviderError {
  if seen.contains(id) {
    reject("MALFORMED_RESPONSE", "duplicate custom tool call id")
  }
  if input.length() > 65536 {
    reject("STREAM_LIMIT", "custom tool input exceeds 65536 code units")
  }
  seen[id] = true
  {
    "id": id.to_json(),
    "name": name.to_json(),
    "kind": "custom".to_json(),
    "arguments": input.to_json(),
  }
}
