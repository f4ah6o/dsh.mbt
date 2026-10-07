// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
fn ResponsesStreamDecoder::record_completed(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  self.require_started()
  let response = field(raw, "response")
  let result = decode_responses_impl(response)
  let result_fields = object(result, "normalized completion")
  if text_field(result_fields, "content") != self.content.to_string() {
    reject("MALFORMED_RESPONSE", "completed text differs from streamed deltas")
  }
  let final_reasoning = optional_text(result_fields, "reasoning").unwrap_or("")
  if final_reasoning != self.reasoning.to_string() {
    reject(
      "MALFORMED_RESPONSE", "completed reasoning differs from streamed deltas",
    )
  }
  let result_calls = array(field(result_fields, "tool_calls"), "tool_calls")
  if result_calls.length() != self.call_order.length() {
    reject(
      "MALFORMED_RESPONSE", "completed function calls differ from streamed lifecycle",
    )
  }
  for index in 0..<self.call_order.length() {
    let call = self.calls[self.call_order[index]]
    if !call.settled {
      reject(
        "MALFORMED_RESPONSE", "completed response contains unfinished function arguments",
      )
    }
    let final_call = object(result_calls[index], "normalized function call")
    if text_field(final_call, "id") != call.call_id ||
      text_field(final_call, "name") != call.name ||
      text_field(final_call, "arguments") != call.arguments.to_string() {
      reject(
        "MALFORMED_RESPONSE", "completed function call differs from streamed lifecycle",
      )
    }
  }
  match result_fields.get("usage") {
    Some(value) => self.pending_events.push(ResponsesEvent::Usage(value))
    None => ()
  }
  self.completion = Some(result)
  self.terminal = true
  self.pending_events.push(ResponsesEvent::Completed)
}

///|
fn ResponsesStreamDecoder::record_failed(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  let failure = match raw.get("response") {
    Some(value) => {
      let response = object(value, "failed response")
      match response.get("error") {
        Some(Null) | None =>
          (
            "provider_error",
            "Responses request failed",
            optional_text(response, "id"),
          )
        Some(value) => {
          let error = object(value, "Responses error")
          (
            optional_text(error, "code").unwrap_or("provider_error"),
            optional_text(error, "message").unwrap_or(
              "Responses request failed",
            ),
            optional_text(response, "id"),
          )
        }
      }
    }
    None =>
      match raw.get("error") {
        Some(value) => {
          let error = object(value, "Responses error")
          (
            optional_text(error, "code").unwrap_or("provider_error"),
            optional_text(error, "message").unwrap_or(
              "Responses request failed",
            ),
            None,
          )
        }
        None => ("provider_error", "Responses request failed", None)
      }
  }
  let (code, detail, request_id) = failure
  self.terminal = true
  self.terminal_failure = Some("PROVIDER_ERROR: " + code)
  self.pending_events.push(ResponsesEvent::Failed(code, detail, request_id))
}

///|
fn ResponsesStreamDecoder::record_incomplete(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  let reason = match raw.get("response") {
    Some(value) => {
      let response = object(value, "incomplete response")
      match response.get("incomplete_details") {
        None | Some(Null) => "unknown"
        Some(value) => {
          let details = object(value, "incomplete details")
          optional_text(details, "reason").unwrap_or("unknown")
        }
      }
    }
    None => "unknown"
  }
  self.terminal = true
  self.terminal_incomplete = Some("INCOMPLETE_RESPONSE: " + reason)
  self.pending_events.push(ResponsesEvent::Incomplete(reason))
}

///|
fn ResponsesStreamDecoder::require_started(
  self : ResponsesStreamDecoder,
) -> Unit raise ProviderError {
  if !self.started {
    reject("MALFORMED_RESPONSE", "content event precedes response.created")
  }
}

///|
fn ResponsesStreamDecoder::require_output_item(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
  expected : String,
) -> Unit raise ProviderError {
  self.require_started()
  let item_id = identity(raw, "item_id")
  if self.output_items.get(item_id) != Some(expected) {
    reject(
      "MALFORMED_RESPONSE", "content delta does not match an open output item",
    )
  }
}

///|
fn ResponsesStreamDecoder::input_call(
  self : ResponsesStreamDecoder,
  raw : Map[String, Json],
) -> ResponsesFunctionCall raise ProviderError {
  let item_id = identity(raw, "item_id")
  if self.output_items.get(item_id) != Some("function_call") {
    reject(
      "MALFORMED_RESPONSE", "function event does not match an open function item",
    )
  }
  match self.calls.get(item_id) {
    Some(call) => call
    None => reject("MALFORMED_RESPONSE", "function event has no matching call")
  }
}

///|
fn ResponsesStreamDecoder::finish_impl(
  self : ResponsesStreamDecoder,
) -> Json raise ProviderError {
  if self.line_units != 0 || self.has_data || !self.event.is_empty() {
    reject("STREAM_CLOSED", "unterminated SSE frame at EOF")
  }
  match self.terminal_failure {
    Some(message) => reject("PROVIDER_ERROR", message)
    None => ()
  }
  match self.terminal_incomplete {
    Some(message) => reject("INCOMPLETE_RESPONSE", message)
    None => ()
  }
  if !self.terminal {
    reject("STREAM_CLOSED", "stream ended before response.completed")
  }
  match self.completion {
    Some(value) => value
    None =>
      reject("MALFORMED_RESPONSE", "completed event has no normalized result")
  }
}
