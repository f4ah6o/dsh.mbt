// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Incremental MoonBit port of the Messages framing and translation in
// deepseek-ai/deepseek-harness at 5badb15009ae1756c3afe0ae0cef1faafc290ccc,
// packages/llm/llm-deepseek/src/{sse,translate}.ts; Chat Completions is the
// provider-neutral compatibility mode.

///|
struct StreamBlock {
  kind : String
  text : StringBuilder
  id : StringBuilder
  name : StringBuilder
  arguments : StringBuilder
  signature : StringBuilder
  mut input : Json
  mut closed : Bool
}

///|
fn StreamBlock::new(kind : String) -> StreamBlock {
  {
    kind,
    text: StringBuilder(),
    id: StringBuilder(),
    name: StringBuilder(),
    arguments: StringBuilder(),
    signature: StringBuilder(),
    input: Json::empty_object(),
    closed: false,
  }
}

///|
/// Incremental text/event-stream decoder. Supply UTF-8-decoded strings from
/// the host's streaming text decoder. CR, LF and CRLF may cross chunk boundaries.
/// Limits are 16 Mi UTF-16 code units per stream, 1 Mi per frame, 1024 blocks.
/// An error is sticky. `finish` requires a complete terminal event and refuses
/// incomplete tails; neither a socket EOF nor a finish reason is completion.
pub struct StreamDecoder {
  mode : String
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
  mut reason : String?
  blocks : Map[Int, StreamBlock]
  block_order : Array[Int]
  content : StringBuilder
  reasoning : StringBuilder
  pending_deltas : Array[Json]
  usage : Map[String, Json]
}

///|
/// Create a decoder. An unknown mode is returned as a sticky error by `feed`
/// or `finish`, so constructing a decoder requires no exception handling.
pub fn StreamDecoder::new(mode : String) -> StreamDecoder {
  {
    mode,
    line: StringBuilder(),
    line_units: 0,
    data: StringBuilder(),
    data_units: 0,
    has_data: false,
    event: "",
    ignore_lf: false,
    at_start: true,
    total_units: 0,
    failure: if mode == "deepseek" || mode == "openai" {
      None
    } else {
      Some("INVALID_REQUEST: provider mode must be deepseek or openai")
    },
    closed: false,
    terminal: false,
    started: false,
    reason: None,
    blocks: Map([]),
    block_order: [],
    content: StringBuilder(),
    reasoning: StringBuilder(),
    pending_deltas: [],
    usage: Map([]),
  }
}

///|
/// Consume a chunk without retaining the entire wire response.
/// Partial JSON and tool arguments are retained only in their current frame
/// and content block. Further chunks after an error return the original error.
pub fn StreamDecoder::feed(
  self : StreamDecoder,
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
/// Settle the stream after EOF and return the normalized engine completion.
/// Truncation errors are sticky. Successful repeated calls return equal data.
pub fn StreamDecoder::finish(self : StreamDecoder) -> Result[Json, String] {
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
/// Drain text and reasoning deltas from completely validated SSE frames. Tool
/// arguments and reasoning signatures are intentionally not projected.
pub fn StreamDecoder::take_deltas(self : StreamDecoder) -> Array[Json] {
  let result = self.pending_deltas.copy()
  self.pending_deltas.clear()
  result
}

///|
/// Decode one buffered SSE string using the same incremental state machine.
pub fn decode_sse(mode : String, input : String) -> Result[Json, String] {
  let decoder = StreamDecoder::new(mode)
  match decoder.feed(input) {
    Err(message) => Err(message)
    Ok(_) => {
      // Buffered callers consume only the final completion. Drop the optional
      // live projection so the decoder does not retain a second copy of it.
      ignore(decoder.take_deltas())
      decoder.finish()
    }
  }
}

///|
fn StreamDecoder::feed_impl(
  self : StreamDecoder,
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
fn StreamDecoder::consume_line(
  self : StreamDecoder,
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
fn StreamDecoder::consume_frame(
  self : StreamDecoder,
  event : String,
  data : String,
) -> Unit raise ProviderError {
  if self.terminal {
    reject("MALFORMED_RESPONSE", "data after terminal event")
  }
  if self.mode == "openai" && data == "[DONE]" {
    if self.reason is None {
      reject("MALFORMED_RESPONSE", "DONE without finish reason")
    }
    self.terminal = true
    return
  }
  let raw = @json.parse(data) catch {
    _ => reject("MALFORMED_RESPONSE", "SSE data contains invalid JSON")
  }
  let raw = object(raw, "SSE event")
  reject_provider_error(raw)
  if event == "error" {
    reject("PROVIDER_ERROR", "provider sent an error event")
  }
  if self.mode == "deepseek" {
    let kind = text_field(raw, "type")
    if !event.is_empty() && event != kind {
      reject("MALFORMED_RESPONSE", "SSE event type mismatch")
    }
    self.consume_messages(kind, raw)
  } else {
    self.consume_completion(raw)
  }
}

///|
fn stream_delta(channel : String, text : String) -> Json {
  Json::object({ "channel": Json::string(channel), "text": Json::string(text) })
}

///|
fn StreamDecoder::record_delta(
  self : StreamDecoder,
  channel : String,
  text : String,
) -> Unit {
  if !text.is_empty() {
    self.pending_deltas.push(stream_delta(channel, text))
  }
}

///|
fn block_index(raw : Map[String, Json]) -> Int raise ProviderError {
  let index = integer(field(raw, "index"), "block index")
  if index > 1023 {
    reject("STREAM_LIMIT", "block index exceeds 1023")
  }
  index
}

///|
fn StreamDecoder::consume_messages(
  self : StreamDecoder,
  kind : String,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  if kind == "error" {
    reject("PROVIDER_ERROR", "provider sent an error event")
  }
  if kind == "message_start" {
    if self.started {
      reject("MALFORMED_RESPONSE", "duplicate message_start")
    }
    let message = object(field(raw, "message"), "message_start message")
    if text_field(message, "role") != "assistant" ||
      text_field(message, "type") != "message" {
      reject("MALFORMED_RESPONSE", "expected an assistant message")
    }
    update_usage(self.mode, self.usage, field(message, "usage"))
    self.started = true
    return
  }
  if kind != "content_block_start" &&
    kind != "content_block_delta" &&
    kind != "content_block_stop" &&
    kind != "message_delta" &&
    kind != "message_stop" {
    return
  }
  if !self.started {
    reject("MALFORMED_RESPONSE", "event precedes message_start")
  }
  if kind == "content_block_start" {
    let index = block_index(raw)
    if self.blocks.contains(index) || self.reason is Some(_) {
      reject(
        "MALFORMED_RESPONSE", "block starts after settlement or repeats an index",
      )
    }
    let native = object(field(raw, "content_block"), "content block")
    let block = StreamBlock::new(text_field(native, "type"))
    let mut initial_text = ""
    match block.kind {
      "text" => {
        initial_text = text_field(native, "text")
        block.text.write_string(initial_text)
      }
      "thinking" => {
        initial_text = text_field(native, "thinking")
        block.text.write_string(initial_text)
        match optional_text(native, "signature") {
          None => ()
          Some(signature) => block.signature.write_string(signature)
        }
      }
      "tool_use" => {
        block.id.write_string(identity(native, "id"))
        block.name.write_string(identity(native, "name"))
        let input = field(native, "input")
        ignore(object(input, "tool input"))
        block.input = input
      }
      value =>
        reject("UNSUPPORTED_CONTENT", "unsupported Messages block " + value)
    }
    self.blocks[index] = block
    self.block_order.push(index)
    match block.kind {
      "text" => {
        self.content.write_string(initial_text)
        self.record_delta("content", initial_text)
      }
      "thinking" => {
        self.reasoning.write_string(initial_text)
        self.record_delta("reasoning", initial_text)
      }
      _ => ()
    }
    return
  }
  if kind == "content_block_delta" || kind == "content_block_stop" {
    let block = match self.blocks.get(block_index(raw)) {
      None =>
        reject("MALFORMED_RESPONSE", "delta or stop without an open block")
      Some(block) if block.closed =>
        reject("MALFORMED_RESPONSE", "delta or stop after block end")
      Some(block) => block
    }
    if self.reason is Some(_) {
      reject("MALFORMED_RESPONSE", "content after finish reason")
    }
    if kind == "content_block_stop" {
      block.closed = true
      return
    }
    let delta = object(field(raw, "delta"), "content delta")
    let delta_type = text_field(delta, "type")
    match (delta_type, block.kind) {
      ("text_delta", "text") => {
        let text = text_field(delta, "text")
        block.text.write_string(text)
        self.content.write_string(text)
        self.record_delta("content", text)
      }
      ("thinking_delta", "thinking") => {
        let text = text_field(delta, "thinking")
        block.text.write_string(text)
        self.reasoning.write_string(text)
        self.record_delta("reasoning", text)
      }
      ("signature_delta", "thinking") =>
        block.signature.write_string(text_field(delta, "signature"))
      ("input_json_delta", "tool_use") =>
        block.arguments.write_string(text_field(delta, "partial_json"))
      _ => reject("MALFORMED_RESPONSE", "delta type does not match its block")
    }
    return
  }
  if kind == "message_delta" {
    let delta = object(field(raw, "delta"), "message delta")
    match optional_text(delta, "stop_reason") {
      None => ()
      Some(reason) => {
        if self.reason is Some(_) {
          reject("MALFORMED_RESPONSE", "duplicate finish reason")
        }
        self.reason = Some(normalized_reason(self.mode, reason))
      }
    }
    match raw.get("usage") {
      None => ()
      Some(value) => update_usage(self.mode, self.usage, value)
    }
    return
  }
  if self.reason is None || self.blocks.values().any(block => !block.closed) {
    reject(
      "MALFORMED_RESPONSE", "message_stop requires closed blocks and finish reason",
    )
  }
  self.terminal = true
}

///|
fn StreamDecoder::consume_completion(
  self : StreamDecoder,
  raw : Map[String, Json],
) -> Unit raise ProviderError {
  match raw.get("usage") {
    None | Some(Null) => ()
    Some(value) => update_usage(self.mode, self.usage, value)
  }
  let choices = array(field(raw, "choices"), "choices")
  if choices.is_empty() {
    if !raw.contains("usage") {
      reject("MALFORMED_RESPONSE", "empty choices without usage")
    }
    return
  }
  if choices.length() != 1 {
    reject("MALFORMED_RESPONSE", "expected exactly one streaming choice")
  }
  let choice = object(choices[0], "choice")
  if integer(field(choice, "index"), "choice index") != 0 {
    reject("MALFORMED_RESPONSE", "only choice zero is supported")
  }
  if self.reason is Some(_) {
    reject("MALFORMED_RESPONSE", "completion after finish reason")
  }
  let delta = object(field(choice, "delta"), "completion delta")
  match optional_text(delta, "role") {
    None | Some("assistant") => ()
    Some(_) => reject("MALFORMED_RESPONSE", "expected assistant role")
  }
  match optional_text(delta, "refusal") {
    Some(refusal) if !refusal.is_empty() => reject("REFUSAL", refusal)
    _ => ()
  }
  let content_delta = optional_text(delta, "content").unwrap_or("")
  let reasoning_delta = optional_text(delta, "reasoning_content").unwrap_or("")
  if delta.contains("function_call") {
    reject("UNSUPPORTED_CONTENT", "legacy function_call is not supported")
  }
  for raw in optional_array(delta, "tool_calls") {
    let call = object(raw, "tool call delta")
    let index = block_index(call)
    let block = match self.blocks.get(index) {
      Some(block) => block
      None => {
        let block = StreamBlock::new("tool_use")
        self.blocks[index] = block
        self.block_order.push(index)
        block
      }
    }
    match optional_text(call, "type") {
      None | Some("function") => ()
      Some(_) =>
        reject("UNSUPPORTED_CONTENT", "only function tool calls are supported")
    }
    match optional_text(call, "id") {
      None => ()
      Some(id) => block.id.write_string(id)
    }
    match call.get("function") {
      None => ()
      Some(value) => {
        let function = object(value, "function delta")
        block.name.write_string(optional_text(function, "name").unwrap_or(""))
        block.arguments.write_string(
          optional_text(function, "arguments").unwrap_or(""),
        )
      }
    }
  }
  let finish_reason = optional_text(choice, "finish_reason").map(reason => {
    normalized_reason(self.mode, reason)
  })
  match finish_reason {
    None => ()
    Some(reason) => self.reason = Some(reason)
  }
  self.content.write_string(content_delta)
  self.reasoning.write_string(reasoning_delta)
  self.record_delta("content", content_delta)
  self.record_delta("reasoning", reasoning_delta)
  self.started = true
}

///|
fn StreamDecoder::finish_impl(self : StreamDecoder) -> Json raise ProviderError {
  if self.line_units != 0 || self.has_data || !self.event.is_empty() {
    reject("STREAM_CLOSED", "unterminated SSE frame at EOF")
  }
  if !self.terminal {
    reject("STREAM_CLOSED", "stream ended before terminal event")
  }
  let reason = match self.reason {
    Some(value) => value
    None => reject("MALFORMED_RESPONSE", "terminal event has no finish reason")
  }
  let content = StringBuilder()
  let reasoning = StringBuilder()
  content.write_string(self.content.to_string())
  reasoning.write_string(self.reasoning.to_string())
  let calls : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  for index in self.block_order {
    let block = self.blocks[index]
    match block.kind {
      "tool_use" =>
        if reason != "length" {
          let arguments = if self.mode == "deepseek" &&
            block.arguments.is_empty() {
            block.input.stringify()
          } else {
            block.arguments.to_string()
          }
          calls.push(
            decoded_call(
              block.id.to_string(),
              block.name.to_string(),
              arguments,
              seen,
            ),
          )
        }
      _ => ()
    }
  }
  result_json(
    content.to_string(),
    reasoning.to_string(),
    calls,
    reason,
    self.usage,
  )
}
