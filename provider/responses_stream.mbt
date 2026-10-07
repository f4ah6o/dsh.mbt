// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Responses SSE has its own terminal contract; keep it separate from the
// Messages message_stop and Chat Completions [DONE] decoder.

///|
/// Validated lifecycle events emitted by the incremental Responses decoder.
/// Function argument deltas are informational; a tool is executable only
/// after `finish` returns a completed engine result.
pub(all) enum ResponsesEvent {
  TextDelta(String)
  ReasoningDelta(String)
  FunctionCallStarted(String, String, String)
  FunctionCallArgumentsDelta(String, String)
  FunctionCallArgumentsDone(String, String, String)
  CustomToolCallStarted(String, String, String)
  CustomToolInputDelta(String, String)
  CustomToolInputDone(String, String, String)
  Usage(Json)
  Completed
  Failed(String, String, String?)
  Incomplete(String)
}

///|
priv struct ResponsesFunctionCall {
  item_id : String
  call_id : String
  name : String
  is_custom : Bool
  arguments : StringBuilder
  mut arguments_units : Int
  mut settled : Bool
}

///|
struct ResponsesStreamDecoder {
  line : StringBuilder
  mut line_units : Int
  data : StringBuilder
  mut data_units : Int
  mut has_data : Bool
  mut event : String
  mut ignore_lf : Bool
  mut at_start : Bool
  mut total_units : Int
  mut failure : String?
  mut closed : Bool
  mut terminal : Bool
  mut started : Bool
  mut terminal_failure : String?
  mut terminal_incomplete : String?
  mut completion : Json?
  mut response_id : String?
  output_items : Map[String, String]
  output_item_order : Array[String]
  output_indices : Map[String, Int]
  completed_output_items : Map[String, Json]
  calls : Map[String, ResponsesFunctionCall]
  call_ids : Map[String, Bool]
  call_order : Array[String]
  content : StringBuilder
  mut content_units : Int
  reasoning : StringBuilder
  mut reasoning_units : Int
  pending_events : Array[ResponsesEvent]
}

///|
/// Create a bounded Responses stream decoder. Chunks must already be decoded
/// as UTF-8 text by the transport; HTTP and byte decoding remain host work.
pub fn ResponsesStreamDecoder::new() -> ResponsesStreamDecoder {
  {
    line: StringBuilder(),
    line_units: 0,
    data: StringBuilder(),
    data_units: 0,
    has_data: false,
    event: "",
    ignore_lf: false,
    at_start: true,
    total_units: 0,
    failure: None,
    closed: false,
    terminal: false,
    started: false,
    terminal_failure: None,
    terminal_incomplete: None,
    completion: None,
    response_id: None,
    output_items: Map([]),
    output_item_order: [],
    output_indices: Map([]),
    completed_output_items: Map([]),
    calls: Map([]),
    call_ids: Map([]),
    call_order: [],
    content: StringBuilder(),
    content_units: 0,
    reasoning: StringBuilder(),
    reasoning_units: 0,
    pending_events: [],
  }
}

///|
/// Consume a chunk. Framing, JSON, and known Responses event shapes are
/// validated before any corresponding event is exposed to the host.
pub fn ResponsesStreamDecoder::feed(
  self : ResponsesStreamDecoder,
  chunk : String,
) -> Result[Unit, String] {
  match self.failure {
    Some(message) => return Err(message)
    None => ()
  }
  if self.closed {
    return Err("STREAM_CLOSED: feed after finish")
  }
  try self.feed_impl(chunk) catch {
    ProviderError(message) => {
      self.failure = Some(message)
      Err(message)
    }
  } noraise {
    _ => Ok(())
  }
}

///|
/// Return validated live events and clear the pending queue.
pub fn ResponsesStreamDecoder::take_events(
  self : ResponsesStreamDecoder,
) -> Array[ResponsesEvent] {
  let result = self.pending_events.copy()
  self.pending_events.clear()
  result
}

///|
/// Report whether a validated response.completed result can be finalized.
/// Provider failures and incomplete responses never produce a ready result.
pub fn ResponsesStreamDecoder::has_completed_result(
  self : ResponsesStreamDecoder,
) -> Bool {
  !self.closed &&
  self.failure is None &&
  self.terminal_failure is None &&
  self.terminal_incomplete is None &&
  self.completion is Some(_)
}

///|
/// Finalization succeeds only after a complete response.completed event and
/// a clean SSE frame boundary. The transport may instead end before that
/// event; failures, incomplete responses, and malformed tails fail closed.
pub fn ResponsesStreamDecoder::finish(
  self : ResponsesStreamDecoder,
) -> Result[Json, String] {
  match self.failure {
    Some(message) => return Err(message)
    None => ()
  }
  try self.finish_impl() catch {
    ProviderError(message) => {
      self.failure = Some(message)
      self.closed = true
      Err(message)
    }
  } noraise {
    value => {
      self.closed = true
      Ok(value)
    }
  }
}

///|
fn ResponsesStreamDecoder::feed_impl(
  self : ResponsesStreamDecoder,
  chunk : String,
) -> Unit raise ProviderError {
  if chunk.length() > 16777216 - self.total_units {
    reject("STREAM_LIMIT", "response exceeds 16 Mi code units")
  }
  self.total_units += chunk.length()
  for character in chunk {
    if self.at_start {
      self.at_start = false
      if character == '\u{FEFF}' {
        continue
      }
    }
    if self.ignore_lf {
      self.ignore_lf = false
      if character == '\n' {
        continue
      }
    }
    if character == '\r' || character == '\n' {
      let line = self.line.to_string()
      self.line.reset()
      self.line_units = 0
      self.consume_line(line)
      self.ignore_lf = character == '\r'
    } else {
      self.line.write_char(character)
      self.line_units += 1
      if self.line_units > 1048576 {
        reject("STREAM_LIMIT", "SSE line exceeds 1 Mi characters")
      }
    }
  }
}

///|
fn ResponsesStreamDecoder::consume_line(
  self : ResponsesStreamDecoder,
  line : String,
) -> Unit raise ProviderError {
  if line.is_empty() {
    if self.has_data {
      let data = self.data.to_string()
      let event = self.event
      self.data.reset()
      self.data_units = 0
      self.has_data = false
      self.event = ""
      self.consume_frame(event, data)
    } else {
      self.event = ""
    }
    return
  }
  if line.has_prefix(":") {
    return
  }
  let (name, value) = match line.split_once(":") {
    Some((name, value)) => (name, value.strip_prefix(" ").unwrap_or(value))
    None => (line[:], ""[:])
  }
  if name == "data" {
    if value.length() + 1 > 1048576 - self.data_units {
      reject("STREAM_LIMIT", "SSE frame exceeds 1 Mi code units")
    }
    if self.has_data {
      self.data.write_char('\n')
    }
    self.data.write_view(value)
    self.data_units += value.length() + 1
    self.has_data = true
  } else if name == "event" {
    self.event = value.to_owned()
  }
}

///|
fn ResponsesStreamDecoder::consume_frame(
  self : ResponsesStreamDecoder,
  event : String,
  data : String,
) -> Unit raise ProviderError {
  if self.terminal {
    reject("MALFORMED_RESPONSE", "data after terminal Responses event")
  }
  let raw = @json.parse(data) catch {
    _ => reject("MALFORMED_RESPONSE", "SSE data contains invalid JSON")
  }
  let raw = object(raw, "Responses SSE event")
  let kind = text_field(raw, "type")
  if !event.is_empty() && event != kind {
    reject("MALFORMED_RESPONSE", "SSE event name does not match its type")
  }
  match kind {
    "response.created" => self.record_created(raw)
    "response.in_progress" =>
      if !self.started {
        reject(
          "MALFORMED_RESPONSE", "response.in_progress precedes response.created",
        )
      }
    "response.output_item.added" => self.record_output_item_added(raw)
    "response.output_text.delta" => self.record_text_delta(raw)
    "response.reasoning_summary_text.delta" | "response.reasoning_text.delta" =>
      self.record_reasoning_delta(raw)
    "response.function_call_arguments.delta" => self.record_function_delta(raw)
    "response.function_call_arguments.done" => self.record_function_done(raw)
    "response.custom_tool_call_input.delta" =>
      self.record_custom_input_delta(raw)
    "response.custom_tool_call_input.done" => self.record_custom_input_done(raw)
    "response.output_item.done" => self.record_output_item_done(raw)
    "response.completed" => self.record_completed(raw)
    "response.failed" | "error" => self.record_failed(raw)
    "response.incomplete" => self.record_incomplete(raw)
    // Background execution is outside this preview adapter. A queued response
    // cannot be treated like an in-progress foreground stream.
    "response.queued" =>
      reject(
        "UNSUPPORTED_CAPABILITY", "queued/background Responses are unsupported",
      )
    "response.refusal.delta" =>
      reject(
        "REFUSAL",
        optional_text(raw, "delta").unwrap_or("Provider refused the request"),
      )
    // Lifecycle events with no engine-visible content are intentionally ignored.
    "response.content_part.added"
    | "response.content_part.done"
    | "response.output_text.done"
    | "response.reasoning_summary_text.done"
    | "response.reasoning_text.done" => ()
    other => reject("UNSUPPORTED_EVENT", "unsupported Responses event " + other)
  }
}
