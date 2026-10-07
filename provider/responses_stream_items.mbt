// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
fn ResponsesStreamDecoder::record_created(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  if self.started {
    reject("MALFORMED_RESPONSE", "duplicate response.created event")
  }
  let response = object(field(raw, "response"), "created response")
  if text_field(response, "status") != "in_progress" {
    reject("MALFORMED_RESPONSE", "created response is not in progress")
  }
  self.response_id = Some(identity(response, "id"))
  self.started = true
}

///|
fn ResponsesStreamDecoder::record_output_item_added(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let item = object(field(raw, "item"), "output item")
  let item_id = identity(item, "id")
  let kind = text_field(item, "type")
  if self.output_items.contains(item_id) {
    reject("MALFORMED_RESPONSE", "output item id was reused")
  }
  let output_index = integer(field(raw, "output_index"), "output_index")
  if output_index != self.output_item_order.length() {
    reject(
      "MALFORMED_RESPONSE", "output item indexes are not unique and contiguous",
    )
  }
  match kind {
    "message" | "reasoning" => self.output_items[item_id] = kind
    "function_call" | "custom_tool_call" => {
      if self.call_order.length() >= 16 {
        reject("STREAM_LIMIT", "response contains more than 16 tool calls")
      }
      let call_id = identity(item, "call_id")
      let name = identity(item, "name")
      if self.call_ids.contains(call_id) {
        reject("MALFORMED_RESPONSE", "function call id was reused")
      }
      let is_custom = kind == "custom_tool_call"
      let arguments = optional_text(
        item,
        if is_custom {
          "input"
        } else {
          "arguments"
        },
      ).unwrap_or("")
      if arguments.length() > 65536 {
        reject("STREAM_LIMIT", "tool input exceeds 65536 code units")
      }
      let call = ResponsesFunctionCall::{
        item_id,
        call_id,
        name,
        is_custom,
        arguments: StringBuilder(),
        arguments_units: arguments.length(),
        settled: false,
      }
      call.arguments.write_string(arguments)
      self.calls[item_id] = call
      self.call_ids[call_id] = true
      self.call_order.push(item_id)
      self.output_items[item_id] = kind
      self.pending_events.push(
        if is_custom {
          ResponsesEvent::CustomToolCallStarted(item_id, call_id, name)
        } else {
          ResponsesEvent::FunctionCallStarted(item_id, call_id, name)
        },
      )
    }
    other =>
      reject(
        "UNSUPPORTED_CONTENT",
        "unsupported Responses output item " + other,
      )
  }
  self.output_item_order.push(item_id)
  self.output_indices[item_id] = output_index
}

///|
fn ResponsesStreamDecoder::record_text_delta(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_output_item(raw, "message")
  let text = text_field(raw, "delta")
  if text.length() > 16777216 - self.content_units {
    reject("STREAM_LIMIT", "response text exceeds stream limit")
  }
  self.content.write_string(text)
  self.content_units += text.length()
  if !text.is_empty() {
    self.pending_events.push(ResponsesEvent::TextDelta(text))
  }
}

///|
fn ResponsesStreamDecoder::record_reasoning_delta(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_output_item(raw, "reasoning")
  let text = text_field(raw, "delta")
  if text.length() > 16777216 - self.reasoning_units {
    reject("STREAM_LIMIT", "response reasoning summary exceeds stream limit")
  }
  self.reasoning.write_string(text)
  self.reasoning_units += text.length()
  if !text.is_empty() {
    self.pending_events.push(ResponsesEvent::ReasoningDelta(text))
  }
}

///|
fn ResponsesStreamDecoder::record_function_delta(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let call = self.input_call(raw)
  if call.is_custom {
    reject(
      "MALFORMED_RESPONSE", "function argument event targets a custom tool",
    )
  }
  if call.settled {
    reject("MALFORMED_RESPONSE", "function arguments changed after completion")
  }
  let delta = text_field(raw, "delta")
  if delta.length() > 65536 - call.arguments_units {
    reject("STREAM_LIMIT", "function arguments exceed 65536 code units")
  }
  call.arguments.write_string(delta)
  call.arguments_units += delta.length()
  self.pending_events.push(
    ResponsesEvent::FunctionCallArgumentsDelta(call.item_id, delta),
  )
}

///|
fn ResponsesStreamDecoder::record_function_done(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let call = self.input_call(raw)
  if call.is_custom {
    reject(
      "MALFORMED_RESPONSE", "function argument event targets a custom tool",
    )
  }
  if call.settled {
    reject("MALFORMED_RESPONSE", "duplicate function arguments completion")
  }
  let arguments = text_field(raw, "arguments")
  if call.arguments.is_empty() {
    call.arguments.write_string(arguments)
    call.arguments_units = arguments.length()
  } else if call.arguments.to_string() != arguments {
    reject(
      "MALFORMED_RESPONSE", "function argument deltas differ from final arguments",
    )
  }
  call.settled = true
  self.pending_events.push(
    ResponsesEvent::FunctionCallArgumentsDone(
      call.call_id,
      call.name,
      arguments,
    ),
  )
}

///|
fn ResponsesStreamDecoder::record_custom_input_delta(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let call = self.input_call(raw)
  if !call.is_custom {
    reject("MALFORMED_RESPONSE", "custom input event targets a function tool")
  }
  if call.settled {
    reject("MALFORMED_RESPONSE", "custom input changed after completion")
  }
  let delta = text_field(raw, "delta")
  if delta.length() > 65536 - call.arguments_units {
    reject("STREAM_LIMIT", "custom tool input exceeds 65536 code units")
  }
  call.arguments.write_string(delta)
  call.arguments_units += delta.length()
  self.pending_events.push(
    ResponsesEvent::CustomToolInputDelta(call.item_id, delta),
  )
}

///|
fn ResponsesStreamDecoder::record_custom_input_done(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let call = self.input_call(raw)
  if !call.is_custom {
    reject("MALFORMED_RESPONSE", "custom input event targets a function tool")
  }
  if call.settled {
    reject("MALFORMED_RESPONSE", "duplicate custom input completion")
  }
  let input = text_field(raw, "input")
  if call.arguments.is_empty() {
    call.arguments.write_string(input)
    call.arguments_units = input.length()
  } else if call.arguments.to_string() != input {
    reject("MALFORMED_RESPONSE", "custom input deltas differ from final input")
  }
  call.settled = true
  self.pending_events.push(
    ResponsesEvent::CustomToolInputDone(call.call_id, call.name, input),
  )
}

///|
fn ResponsesStreamDecoder::record_output_item_done(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let item = object(field(raw, "item"), "completed output item")
  let item_id = identity(item, "id")
  let kind = text_field(item, "type")
  let output_index = integer(field(raw, "output_index"), "output_index")
  if self.completed_output_items.contains(item_id) {
    reject("MALFORMED_RESPONSE", "duplicate output item completion")
  }
  if self.output_indices.get(item_id) != Some(output_index) {
    reject("MALFORMED_RESPONSE", "completed output item index changed")
  }
  match kind {
    "message" | "reasoning" => {
      if self.output_items.get(item_id) != Some(kind) {
        reject(
          "MALFORMED_RESPONSE", "output item completed without being added",
        )
      }
      self.completed_output_items[item_id] = Json::object(item.copy())
      return
    }
    "function_call" | "custom_tool_call" => ()
    other =>
      reject(
        "UNSUPPORTED_CONTENT",
        "unsupported completed output item " + other,
      )
  }
  if self.output_items.get(item_id) != Some(kind) {
    reject("MALFORMED_RESPONSE", "tool output completed without being added")
  }
  let call = match self.calls.get(item_id) {
    Some(call) => call
    None =>
      reject("MALFORMED_RESPONSE", "tool call completed without being added")
  }
  let is_custom = kind == "custom_tool_call"
  if call.is_custom != is_custom {
    reject("MALFORMED_RESPONSE", "tool call kind changed before completion")
  }
  let arguments = text_field(
    item,
    if is_custom {
      "input"
    } else {
      "arguments"
    },
  )
  if call.settled {
    if call.arguments.to_string() != arguments {
      reject(
        "MALFORMED_RESPONSE", "completed function item differs from its arguments event",
      )
    }
  } else {
    if call.arguments.is_empty() {
      call.arguments.write_string(arguments)
      call.arguments_units = arguments.length()
    } else if call.arguments.to_string() != arguments {
      reject(
        "MALFORMED_RESPONSE", "function argument deltas differ from output item",
      )
    }
    call.settled = true
    self.pending_events.push(
      if is_custom {
        ResponsesEvent::CustomToolInputDone(call.call_id, call.name, arguments)
      } else {
        ResponsesEvent::FunctionCallArgumentsDone(
          call.call_id,
          call.name,
          arguments,
        )
      },
    )
  }
  self.completed_output_items[item_id] = Json::object(item.copy())
}
