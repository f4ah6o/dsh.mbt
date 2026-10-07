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
  ignore(identity(response, "id"))
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
  match kind {
    "message" | "reasoning" => self.output_items[item_id] = kind
    "function_call" => {
      if self.call_order.length() >= 16 {
        reject("STREAM_LIMIT", "response contains more than 16 function calls")
      }
      let call_id = identity(item, "call_id")
      let name = identity(item, "name")
      if self.call_ids.contains(call_id) {
        reject("MALFORMED_RESPONSE", "function call id was reused")
      }
      let arguments = optional_text(item, "arguments").unwrap_or("")
      if arguments.length() > 65536 {
        reject("STREAM_LIMIT", "function arguments exceed 65536 code units")
      }
      let call = ResponsesFunctionCall::{
        item_id,
        call_id,
        name,
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
        ResponsesEvent::FunctionCallStarted(item_id, call_id, name),
      )
    }
    other =>
      reject(
        "UNSUPPORTED_CONTENT",
        "unsupported Responses output item " + other,
      )
  }
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
fn ResponsesStreamDecoder::record_output_item_done(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let item = object(field(raw, "item"), "completed output item")
  if text_field(item, "type") != "function_call" {
    return
  }
  let call = match self.calls.get(identity(item, "id")) {
    Some(call) => call
    None =>
      reject(
        "MALFORMED_RESPONSE", "function call completed without being added",
      )
  }
  let arguments = text_field(item, "arguments")
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
      ResponsesEvent::FunctionCallArgumentsDone(
        call.call_id,
        call.name,
        arguments,
      ),
    )
  }
}
