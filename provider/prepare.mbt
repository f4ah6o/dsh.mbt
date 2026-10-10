// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Port of packages/llm/llm-deepseek/src/{serialize,wire-types,messages-api}.ts
// from deepseek-ai/deepseek-harness at 5badb15009ae1756c3afe0ae0cef1faafc290ccc.

///|
/// Prepare an HTTP request without reading credentials or performing I/O.
/// `deepseek` uses Messages; `openai` uses Chat Completions. The host owns URL
/// resolution and authentication. `stream` defaults to true, `max_tokens` to
/// 4096, and DeepSeek `reasoning_effort` to high. Tool effects stay local.
pub fn prepare(
  mode : String,
  model : String,
  request : Json,
) -> Result[Json, String] {
  try prepare_impl(mode, model, request) catch {
    ProviderError(message) => Err(message)
  } noraise {
    value => Ok(value)
  }
}

///|
fn append_message(
  messages : Array[Json],
  role : String,
  blocks : Array[Json],
) -> Unit {
  if messages.length() > 0 {
    match messages[messages.length() - 1] {
      Object(previous) =>
        match (previous.get("role"), previous.get("content")) {
          (Some(String(previous_role)), Some(Array(previous_blocks))) if previous_role ==
            role => {
            previous_blocks.append(blocks[:])
            return
          }
          _ => ()
        }
      _ => ()
    }
  }
  messages.push({ "role": role.to_json(), "content": Json::array(blocks) })
}

///|
// Historical failures must remain replayable after the engine records their
// paired tool error. Messages requires an object even for a rejected call;
// this matches upstream serialize.ts toolInput without changing durable text.
fn historical_input(arguments : String) -> Json {
  let value = @json.parse(arguments) catch { _ => Json::empty_object() }
  match value {
    Object(_) => value
    _ => Json::empty_object()
  }
}

///|
fn prepare_impl(
  mode : String,
  model : String,
  request : Json,
) -> Json raise ProviderError {
  validate_mode(mode)
  if model.is_empty() {
    reject("INVALID_REQUEST", "model must not be empty")
  }
  let request = object(request, "request")
  let system = optional_text(request, "system").unwrap_or("")
  let history = array(field(request, "messages"), "messages")
  if history.is_empty() {
    reject("INVALID_REQUEST", "messages must not be empty")
  }
  let stream = match request.get("stream") {
    None => true
    Some(value) => boolean(value, "stream")
  }
  let max_tokens = match request.get("max_tokens") {
    None => 4096
    Some(value) => integer(value, "max_tokens")
  }
  if max_tokens == 0 {
    reject("INVALID_REQUEST", "max_tokens must be positive")
  }
  let messages : Array[Json] = []
  if mode == "openai" && !system.is_empty() {
    messages.push({ "role": "system", "content": system.to_json() })
  }
  let pending : Map[String, Bool] = Map([])
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
        return reject("INVALID_REQUEST", "tool result content must be a string")
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
      if !pending.contains(id) {
        reject("INVALID_REQUEST", "tool result has no matching pending call")
      }
      pending.remove(id)
      if mode == "deepseek" {
        let result : Map[String, Json] = {
          "type": "tool_result",
          "tool_use_id": id.to_json(),
          "content": Json::array([{ "type": "text", "text": content.to_json() }]),
        }
        match message.get("is_error") {
          None => ()
          Some(value) =>
            result["is_error"] = boolean(value, "is_error").to_json()
        }
        append_message(messages, "user", [Json::object(result)])
      } else {
        messages.push({
          "role": "tool",
          "tool_call_id": id.to_json(),
          "content": content.to_json(),
        })
      }
      continue
    }
    if role != "user" && role != "assistant" {
      reject("INVALID_REQUEST", "unsupported message role " + role)
    }
    let blocks : Array[Json] = []
    let openai_calls : Array[Json] = []
    let reasoning = optional_text(message, "reasoning").unwrap_or("")
    if role == "assistant" && mode == "deepseek" && !reasoning.is_empty() {
      blocks.push({ "type": "thinking", "thinking": reasoning.to_json() })
    }
    blocks.append(content_blocks)
    for raw_call in calls {
      let call = object(raw_call, "tool call")
      let id = identity(call, "id")
      let name = identity(call, "name")
      let arguments = text_field(call, "arguments")
      if seen_ids.contains(id) {
        reject("INVALID_REQUEST", "duplicate tool call id")
      }
      seen_ids[id] = true
      pending[id] = true
      if mode == "deepseek" {
        blocks.push({
          "type": "tool_use",
          "id": id.to_json(),
          "name": name.to_json(),
          "input": historical_input(arguments),
        })
      }
      openai_calls.push({
        "id": id.to_json(),
        "type": "function",
        "function": { "name": name.to_json(), "arguments": arguments.to_json() },
      })
    }
    if mode == "deepseek" {
      if !blocks.is_empty() {
        append_message(messages, role, blocks)
      }
    } else {
      let wire : Map[String, Json] = {
        "role": role.to_json(),
        "content": match content_value {
          String(value) if value.is_empty() && !calls.is_empty() => Json::null()
          String(value) => value.to_json()
          Array(_) => Json::array(content_blocks)
          _ => Json::null()
        },
      }
      if !openai_calls.is_empty() {
        wire["tool_calls"] = Json::array(openai_calls)
      }
      if role == "assistant" && !reasoning.is_empty() {
        wire["reasoning_content"] = reasoning.to_json()
      }
      messages.push(Json::object(wire))
    }
  }
  if !pending.is_empty() {
    reject("INVALID_REQUEST", "history ends with unresolved tool calls")
  }
  if messages.is_empty() {
    reject("INVALID_REQUEST", "request has no nonempty messages")
  }
  let body : Map[String, Json] = {
    "model": model.to_json(),
    "messages": Json::array(messages),
    "stream": stream.to_json(),
    "max_tokens": max_tokens.to_json(),
  }
  if mode == "deepseek" {
    if !system.is_empty() {
      body["system"] = system.to_json()
    }
    let effort = optional_text(request, "reasoning_effort").unwrap_or("high")
    if effort != "off" && effort != "low" && effort != "high" && effort != "max" {
      reject("INVALID_REQUEST", "unsupported DeepSeek reasoning effort")
    }
    body["thinking"] = {
      "type": if effort == "off" {
        "disabled"
      } else {
        "enabled"
      },
    }
    if effort != "off" {
      body["output_config"] = { "effort": effort.to_json() }
    }
  } else {
    match optional_text(request, "reasoning_effort") {
      None => ()
      Some(effort) => body["reasoning_effort"] = effort.to_json()
    }
    if stream {
      body["stream_options"] = { "include_usage": true }
    }
  }
  let tools : Array[Json] = []
  let seen_tools : Map[String, Bool] = Map([])
  for raw in optional_array(request, "tools") {
    let tool = object(raw, "tool definition")
    let name = identity(tool, "name")
    if seen_tools.contains(name) {
      reject("INVALID_REQUEST", "duplicate tool name")
    }
    seen_tools[name] = true
    let description = text_field(tool, "description")
    let schema = field(tool, "input_schema")
    ignore(object(schema, "tool input_schema"))
    if mode == "deepseek" {
      tools.push({
        "name": name.to_json(),
        "description": description.to_json(),
        "input_schema": schema,
      })
    } else {
      tools.push({
        "type": "function",
        "function": {
          "name": name.to_json(),
          "description": description.to_json(),
          "parameters": schema,
        },
      })
    }
  }
  if !tools.is_empty() {
    body["tools"] = Json::array(tools)
  }
  let headers : Map[String, Json] = {
    "content-type": "application/json",
    "accept": if stream {
      "text/event-stream"
    } else {
      "application/json"
    },
  }
  if mode == "deepseek" {
    headers["anthropic-version"] = "2023-06-01"
  }
  {
    "path": if mode == "deepseek" {
      "/v1/messages"
    } else {
      "/v1/chat/completions"
    },
    "headers": Json::object(headers),
    "body": Json::object(body),
  }
}
