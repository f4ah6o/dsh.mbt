// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Native-only HTTPS transport for OpenAI Responses and account model discovery.

///|
const NATIVE_PROVIDER_TOTAL_TIMEOUT_MS : Int = 120000

///|
const NATIVE_PROVIDER_IDLE_TIMEOUT_MS : Int = 30000

///|
const NATIVE_PROVIDER_BODY_LIMIT : Int = 16777216

///|
const NATIVE_PROVIDER_REQUEST_LIMIT : Int = 16777216

///|
enum NativeProviderRead {
  Data(Bytes)
  End
  IdleTimeout
  TooLarge
}

///|
async fn[T] native_provider_with_deadline(
  timeout_ms : Int,
  action : async () -> T,
) -> T? {
  @async.with_timeout_opt(timeout_ms, action)
}

///|
async fn native_provider_read_chunk(
  client : @http.Client,
  already_read : Int,
) -> NativeProviderRead {
  match
    native_provider_with_deadline(NATIVE_PROVIDER_IDLE_TIMEOUT_MS, async fn() {
      client.read_some(max_len=16384)
    }) {
    None => NativeProviderRead::IdleTimeout
    Some(None) => NativeProviderRead::End
    Some(Some(bytes)) if native_provider_body_limit_exceeded(
        already_read,
        bytes.length(),
      ) => NativeProviderRead::TooLarge
    Some(Some(bytes)) => NativeProviderRead::Data(bytes)
  }
}

///|
fn native_provider_body_limit_exceeded(
  already_read : Int,
  next_chunk_bytes : Int,
) -> Bool {
  already_read < 0 ||
  next_chunk_bytes < 0 ||
  already_read > NATIVE_PROVIDER_BODY_LIMIT - next_chunk_bytes
}

///|
fn native_provider_timeout_failure(message : String) -> Json {
  native_provider_failure_json("TIMEOUT", message)
}

///|
/// Send one Responses request using an immutable account/model snapshot. The
/// callback receives validated stream lifecycle events as they arrive; the
/// normalized completed response is returned only after a valid terminal event.
pub async fn NativeAuth::run_responses(
  self : NativeAuth,
  selection : NativeProviderSelection,
  request : Json,
  on_event : async (@provider.ResponsesEvent) -> Result[Unit, String],
) -> Result[Json, String] {
  match
    native_provider_with_deadline(NATIVE_PROVIDER_TOTAL_TIMEOUT_MS, async fn() {
      self.run_responses_inner(selection, request, on_event)
    }) {
    Some(result) => result
    None =>
      Ok(
        native_provider_timeout_failure(
          "Provider request exceeded the total time limit",
        ),
      )
  }
}

///|
async fn NativeAuth::run_responses_inner(
  self : NativeAuth,
  selection : NativeProviderSelection,
  request : Json,
  on_event : async (@provider.ResponsesEvent) -> Result[Unit, String],
) -> Result[Json, String] {
  if selection.protocol() != OpenAIResponses || selection.auth_mode() != ChatGPT {
    return Err("INVALID_SELECTION: ChatGPT auth requires OpenAI Responses")
  }
  let credential = match self.credential_for_selection(selection) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !credential.can_use_direct() {
    return Err(
      "AUTH_DIRECT_SCOPE_REQUIRED: direct ChatGPT inference is not enabled",
    )
  }
  let prepared = match @provider.prepare_responses(selection.model(), request) {
    Ok(value) => value
    Err(error) =>
      return Ok(native_provider_failure_json("INVALID_REQUEST", error))
  }
  let prepared_fields = match prepared {
    Object(fields) => fields
    _ => return Err("INVALID_REQUEST: Responses request could not be prepared")
  }
  let body = match prepared_fields.get("body") {
    Some(value) => value.stringify()
    None => return Err("INVALID_REQUEST: Responses request body is missing")
  }
  if @utf8.encode(body).length() > NATIVE_PROVIDER_REQUEST_LIMIT {
    return Ok(
      native_provider_failure_json(
        "REQUEST_TOO_LARGE", "Provider request exceeds the 16 MiB limit",
      ),
    )
  }
  let headers : @http.Headers = {
    "Accept": "text/event-stream",
    "Authorization": "Bearer " + credential.access_token_for_transport(),
    "Content-Type": "application/json",
  }
  let client = @http.Client("https://api.openai.com", headers~) catch {
    _ =>
      return Ok(
        native_provider_failure_json(
          "TRANSPORT", "Provider transport could not establish an HTTPS connection",
        ),
      )
  }
  defer client.close()
  let response = client
    ..request(@http.Post, "/v1/responses")
    ..write(body)
    .end_request() catch {
      _ =>
        return Ok(
          native_provider_failure_json(
            "TRANSPORT", "Provider HTTPS request failed",
          ),
        )
    }
  if response.code != 200 {
    ignore(native_provider_read_limited(client, 65536))
    return Ok(
      native_provider_http_failure(response.code, response.headers, "Responses"),
    )
  }
  let content_type = response.headers.get("content-type").unwrap_or("")
  if !content_type.to_lower().contains("text/event-stream") {
    return Ok(
      native_provider_failure_json(
        "MALFORMED", "Responses stream content type is invalid",
      ),
    )
  }
  let utf8 = Utf8StreamDecoder::new()
  let decoder = @provider.ResponsesStreamDecoder::new()
  let mut received_bytes = 0
  for ;; {
    match native_provider_read_chunk(client, received_bytes) {
      NativeProviderRead::End => break
      NativeProviderRead::IdleTimeout =>
        return Ok(
          native_provider_timeout_failure(
            "Provider response stream exceeded the idle time limit",
          ),
        )
      NativeProviderRead::TooLarge =>
        return Ok(
          native_provider_failure_json(
            "RESPONSE_TOO_LARGE", "Provider response exceeds the 16 MiB limit",
          ),
        )
      NativeProviderRead::Data(bytes) => {
        received_bytes += bytes.length()
        let text = match utf8.feed(bytes[:]) {
          Ok(value) => value
          Err(error) =>
            return Ok(native_provider_failure_json("MALFORMED", error))
        }
        match decoder.feed(text) {
          Ok(_) => ()
          Err(error) =>
            return Ok(native_provider_failure_json("MALFORMED", error))
        }
        match
          native_provider_dispatch_events(self, selection, decoder, on_event) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
    }
  }
  match utf8.finish() {
    Ok(_) => ()
    Err(error) => return Ok(native_provider_failure_json("MALFORMED", error))
  }
  let completion = match decoder.finish() {
    Ok(value) => value
    Err(error) => return Ok(native_provider_stream_failure(error))
  }
  match self.validate_generation(selection) {
    Ok(_) if native_provider_empty_completion(completion) =>
      Ok(
        native_provider_failure_json(
          "EMPTY_RESPONSE", "Provider returned an empty response",
        ),
      )
    Ok(_) => Ok(completion)
    Err(error) => Err(error)
  }
}

///|
/// Execute one explicit API-key provider request. The runtime supplies an
/// effect-local key snapshot; keys are never stored in provider selection or
/// included in errors. ChatGPT OAuth is handled only by run_responses.
pub async fn native_run_api_key(
  selection : NativeProviderSelection,
  request : Json,
  api_key : String,
  on_delta : async (String, String) -> Result[Unit, String],
) -> Result[Json, String] {
  match
    native_provider_with_deadline(NATIVE_PROVIDER_TOTAL_TIMEOUT_MS, async fn() {
      native_run_api_key_inner(selection, request, api_key, on_delta)
    }) {
    Some(result) => result
    None =>
      Ok(
        native_provider_timeout_failure(
          "Provider request exceeded the total time limit",
        ),
      )
  }
}

///|
async fn native_run_api_key_inner(
  selection : NativeProviderSelection,
  request : Json,
  api_key : String,
  on_delta : async (String, String) -> Result[Unit, String],
) -> Result[Json, String] {
  if selection.auth_mode() != ApiKey {
    return Err("INVALID_SELECTION: API-key runner requires API-key auth")
  }
  let is_responses = selection.protocol() == OpenAIResponses
  let mode = match selection.protocol() {
    DeepSeekMessages => "deepseek"
    OpenAIChatCompletions => "openai"
    OpenAIResponses => "openai"
  }
  if api_key.is_empty() || api_key.length() > 8192 {
    return Ok(
      native_provider_failure_json("AUTH", "Provider API key is missing"),
    )
  }
  for character in api_key {
    if character == '\r' || character == '\n' {
      return Ok(
        native_provider_failure_json(
          "AUTH", "Provider API key contains an invalid header separator",
        ),
      )
    }
  }
  let (origin, prefix) = match native_provider_base_url(selection.base_url()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let request = match request {
    Object(fields) => {
      fields["stream"] = true.to_json()
      Json::object(fields)
    }
    _ => return Err("INVALID_REQUEST: provider request must be an object")
  }
  let prepared = if is_responses {
    @provider.prepare_responses(selection.model(), request)
  } else {
    @provider.prepare(mode, selection.model(), request)
  }
  let prepared = match prepared {
    Ok(value) => value
    Err(error) =>
      return Ok(native_provider_failure_json("INVALID_REQUEST", error))
  }
  let prepared_fields = match prepared {
    Object(fields) => fields
    _ => return Err("INVALID_REQUEST: provider request could not be prepared")
  }
  let body = match prepared_fields.get("body") {
    Some(value) => value.stringify()
    None => return Err("INVALID_REQUEST: provider request body is missing")
  }
  if @utf8.encode(body).length() > NATIVE_PROVIDER_REQUEST_LIMIT {
    return Ok(
      native_provider_failure_json(
        "REQUEST_TOO_LARGE", "Provider request exceeds the 16 MiB limit",
      ),
    )
  }
  let path = match prepared_fields.get("path") {
    Some(String(path)) if (mode == "deepseek" && path == "/v1/messages") ||
      (mode == "openai" && !is_responses && path == "/v1/chat/completions") ||
      (is_responses && path == "/v1/responses") => path
    _ => return Err("INVALID_REQUEST: provider request path is invalid")
  }
  let request_path = prefix + path
  let headers : @http.Headers = if mode == "deepseek" {
    {
      "Accept": "text/event-stream",
      "Content-Type": "application/json",
      "anthropic-version": "2023-06-01",
      "x-api-key": api_key,
    }
  } else {
    {
      "Accept": "text/event-stream",
      "Authorization": "Bearer " + api_key,
      "Content-Type": "application/json",
    }
  }
  let client = @http.Client(origin, headers~) catch {
    _ =>
      return Ok(
        native_provider_failure_json(
          "TRANSPORT", "Provider transport could not establish an HTTP connection",
        ),
      )
  }
  defer client.close()
  let response = client
    ..request(@http.Post, request_path)
    ..write(body)
    .end_request() catch {
      _ =>
        return Ok(
          native_provider_failure_json(
            "TRANSPORT", "Provider HTTP request failed",
          ),
        )
    }
  if response.code != 200 {
    ignore(native_provider_read_limited(client, 65536))
    return Ok(
      native_provider_http_failure(response.code, response.headers, "provider"),
    )
  }
  let content_type = response.headers.get("content-type").unwrap_or("")
  if !content_type.to_lower().contains("text/event-stream") {
    return Ok(
      native_provider_failure_json(
        "MALFORMED", "Provider stream content type is invalid",
      ),
    )
  }
  let utf8 = Utf8StreamDecoder::new()
  if is_responses {
    let decoder = @provider.ResponsesStreamDecoder::new()
    let mut received_bytes = 0
    for ;; {
      match native_provider_read_chunk(client, received_bytes) {
        NativeProviderRead::End => break
        NativeProviderRead::IdleTimeout =>
          return Ok(
            native_provider_timeout_failure(
              "Provider response stream exceeded the idle time limit",
            ),
          )
        NativeProviderRead::TooLarge =>
          return Ok(
            native_provider_failure_json(
              "RESPONSE_TOO_LARGE", "Provider response exceeds the 16 MiB limit",
            ),
          )
        NativeProviderRead::Data(bytes) => {
          received_bytes += bytes.length()
          let text = match utf8.feed(bytes[:]) {
            Ok(value) => value
            Err(error) =>
              return Ok(native_provider_failure_json("MALFORMED", error))
          }
          match decoder.feed(text) {
            Ok(_) => ()
            Err(error) =>
              return Ok(native_provider_failure_json("MALFORMED", error))
          }
          match native_provider_dispatch_responses_deltas(decoder, on_delta) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
    }
    match utf8.finish() {
      Ok(_) => ()
      Err(error) => return Ok(native_provider_failure_json("MALFORMED", error))
    }
    let completion = match decoder.finish() {
      Ok(value) => value
      Err(error) => return Ok(native_provider_stream_failure(error))
    }
    if native_provider_empty_completion(completion) {
      Ok(
        native_provider_failure_json(
          "EMPTY_RESPONSE", "Provider returned an empty response",
        ),
      )
    } else {
      Ok(completion)
    }
  } else {
    let decoder = @provider.StreamDecoder::new(mode)
    let mut received_bytes = 0
    for ;; {
      match native_provider_read_chunk(client, received_bytes) {
        NativeProviderRead::End => break
        NativeProviderRead::IdleTimeout =>
          return Ok(
            native_provider_timeout_failure(
              "Provider response stream exceeded the idle time limit",
            ),
          )
        NativeProviderRead::TooLarge =>
          return Ok(
            native_provider_failure_json(
              "RESPONSE_TOO_LARGE", "Provider response exceeds the 16 MiB limit",
            ),
          )
        NativeProviderRead::Data(bytes) => {
          received_bytes += bytes.length()
          let text = match utf8.feed(bytes[:]) {
            Ok(value) => value
            Err(error) =>
              return Ok(native_provider_failure_json("MALFORMED", error))
          }
          match decoder.feed(text) {
            Ok(_) => ()
            Err(error) =>
              return Ok(native_provider_failure_json("MALFORMED", error))
          }
          match native_provider_dispatch_chat_deltas(decoder, on_delta) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
    }
    match utf8.finish() {
      Ok(_) => ()
      Err(error) => return Ok(native_provider_failure_json("MALFORMED", error))
    }
    let completion = match decoder.finish() {
      Ok(value) => value
      Err(error) => return Ok(native_provider_stream_failure(error))
    }
    if native_provider_empty_completion(completion) {
      Ok(
        native_provider_failure_json(
          "EMPTY_RESPONSE", "Provider returned an empty response",
        ),
      )
    } else {
      Ok(completion)
    }
  }
}

///|
async fn native_provider_dispatch_events(
  auth : NativeAuth,
  selection : NativeProviderSelection,
  decoder : @provider.ResponsesStreamDecoder,
  on_event : async (@provider.ResponsesEvent) -> Result[Unit, String],
) -> Result[Unit, String] {
  for event in decoder.take_events() {
    match auth.validate_generation(selection) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match on_event(event) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match auth.validate_generation(selection) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn native_provider_dispatch_chat_deltas(
  decoder : @provider.StreamDecoder,
  on_delta : async (String, String) -> Result[Unit, String],
) -> Result[Unit, String] {
  for delta in decoder.take_deltas() {
    let fields = match delta {
      Object(fields) => fields
      _ => return Err("PROVIDER_PROTOCOL_ERROR: provider emitted invalid delta")
    }
    let text = match fields.get("text") {
      Some(String(value)) => value
      _ =>
        return Err(
          "PROVIDER_PROTOCOL_ERROR: provider emitted invalid delta text",
        )
    }
    let (content, reasoning) = match fields.get("channel") {
      Some(String("content")) => (text, "")
      Some(String("reasoning")) => ("", text)
      _ =>
        return Err(
          "PROVIDER_PROTOCOL_ERROR: provider emitted unknown delta channel",
        )
    }
    match on_delta(content, reasoning) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn native_provider_dispatch_responses_deltas(
  decoder : @provider.ResponsesStreamDecoder,
  on_delta : async (String, String) -> Result[Unit, String],
) -> Result[Unit, String] {
  for event in decoder.take_events() {
    match event {
      @provider.ResponsesEvent::TextDelta(text) =>
        match on_delta(text, "") {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      @provider.ResponsesEvent::ReasoningDelta(text) =>
        match on_delta("", text) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      _ => ()
    }
  }
  Ok(())
}

///|
/// Validate and split a provider API root. Cleartext HTTP is allowed only for
/// loopback fixtures; all non-loopback requests require TLS.
fn native_provider_base_url(
  base_url : String,
) -> Result[(String, String), String] {
  let (scheme, rest) = match base_url.split_once("://") {
    Some((scheme, rest)) => (scheme.to_owned(), rest.to_owned())
    None => return Err("INVALID_BASE_URL: provider URL must use HTTP(S)")
  }
  if scheme != "https" && scheme != "http" {
    return Err("INVALID_BASE_URL: provider URL must use HTTP(S)")
  }
  let (authority, path) = match rest.split_once("/") {
    Some((authority, path)) => (authority.to_owned(), "/" + path.to_owned())
    None => (rest, "")
  }
  if authority.is_empty() ||
    base_url.contains("@") ||
    base_url.contains("?") ||
    base_url.contains("#") ||
    base_url.contains("\\") {
    return Err(
      "INVALID_BASE_URL: provider URL must omit credentials, query, and fragment",
    )
  }
  for character in authority {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '.' ||
      character == '-' ||
      character == ':' ||
      character == '[' ||
      character == ']') {
      return Err(
        "INVALID_BASE_URL: provider authority contains an invalid character",
      )
    }
  }
  let loopback = authority == "localhost" ||
    authority.has_prefix("localhost:") ||
    authority == "127.0.0.1" ||
    authority.has_prefix("127.0.0.1:") ||
    authority == "[::1]" ||
    authority.has_prefix("[::1]:")
  if scheme == "http" && !loopback {
    return Err("INVALID_BASE_URL: cleartext HTTP is limited to loopback")
  }
  if path.contains("?") ||
    path.contains("#") ||
    path.contains("\\") ||
    path.contains("/../") ||
    path.has_suffix("/..") ||
    path == "/.." {
    return Err("INVALID_BASE_URL: provider path is invalid")
  }
  let mut prefix = path
  while prefix.has_suffix("/") {
    prefix = prefix[:prefix.length() - 1].to_owned()
  }
  if prefix.has_suffix("/v1") {
    prefix = prefix[:prefix.length() - 3].to_owned()
  }
  Ok((scheme + "://" + authority, prefix))
}

///|
async fn native_provider_read_limited(
  client : @http.Client,
  limit : Int,
) -> Result[Bytes, String] {
  let bytes : Array[Byte] = []
  for ;; {
    match native_provider_read_chunk(client, bytes.length()) {
      NativeProviderRead::End => break
      NativeProviderRead::IdleTimeout =>
        return Err("provider error response exceeded the idle time limit")
      NativeProviderRead::TooLarge =>
        return Err("provider error response exceeds the size limit")
      NativeProviderRead::Data(chunk) => {
        if bytes.length() + chunk.length() > limit {
          return Err("provider error response exceeds the size limit")
        }
        for byte in chunk {
          bytes.push(byte)
        }
      }
    }
  }
  Ok(Bytes::from_array(bytes[:]))
}

///|
fn native_provider_http_failure(
  status : Int,
  headers : @http.Headers,
  label : String,
) -> Json {
  let code = if status == 408 || status == 504 {
    "TIMEOUT"
  } else if status == 429 {
    "RATE_LIMIT"
  } else if status >= 500 {
    "SERVER"
  } else if status == 401 || status == 403 {
    "AUTH"
  } else {
    "HTTP_ERROR"
  }
  let request_id = native_provider_request_id(headers)
  native_provider_failure_json(
    code,
    label + " endpoint returned HTTP " + status.to_string(),
    status~,
    retry_after_ms=native_provider_retry_after(headers.get("retry-after")),
    request_id~,
  )
}

///|
fn native_provider_failure_json(
  code : String,
  message : String,
  status? : Int,
  retry_after_ms? : Int? = None,
  request_id? : String? = None,
) -> Json {
  let safe_message = native_provider_clip(message, 512)
  let failure : Map[String, Json] = {
    "code": code.to_json(),
    "message": safe_message.to_json(),
  }
  match status {
    Some(value) if value >= 100 && value <= 599 =>
      failure["status"] = value.to_json()
    _ => ()
  }
  match retry_after_ms {
    Some(value) if value >= 0 => failure["retry_after_ms"] = value.to_json()
    _ => ()
  }
  match request_id {
    Some(value) if native_provider_valid_request_id(value) =>
      failure["request_id"] = value.to_json()
    _ => ()
  }
  Json::object({
    "ok": false.to_json(),
    "error": safe_message.to_json(),
    "failure": Json::object(failure),
  })
}

///|
fn native_provider_clip(value : String, max_chars : Int) -> String {
  let clipped = StringBuilder()
  let mut count = 0
  for character in value {
    if count < max_chars {
      clipped.write_char(character)
      count += 1
    }
  }
  clipped.to_string()
}

///|
fn native_provider_stream_failure(error : String) -> Json {
  let code = if error.has_prefix("PROVIDER_ERROR:") {
    "PROVIDER_ERROR"
  } else if error.has_prefix("INCOMPLETE_RESPONSE:") {
    "INCOMPLETE_RESPONSE"
  } else {
    "MALFORMED"
  }
  native_provider_failure_json(
    code, "Provider stream did not complete successfully",
  )
}

///|
fn native_provider_empty_completion(value : Json) -> Bool {
  let fields = match value {
    Object(fields) => fields
    _ => return true
  }
  let content = match fields.get("content") {
    Some(String(text)) => !text.is_empty()
    _ => false
  }
  let calls = match fields.get("tool_calls") {
    Some(Array(values)) => !values.is_empty()
    _ => false
  }
  !content && !calls
}

///|
fn native_provider_request_id(headers : @http.Headers) -> String? {
  for name in ["x-request-id", "openai-request-id", "request-id"] {
    match headers.get(name) {
      Some(value) if native_provider_valid_request_id(value) =>
        return Some(value)
      _ => ()
    }
  }
  None
}

///|
fn native_provider_valid_request_id(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for character in value {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' ||
      character == '.') {
      return false
    }
  }
  true
}

///|
/// Parse the numeric Retry-After form. Oversized delays are represented just
/// beyond the engine's ten-second cap, which preserves the server instruction
/// while preventing it from bypassing the bounded retry policy.
fn native_provider_retry_after(value : String?) -> Int? {
  let text = match value {
    Some(value) => value.trim().to_owned()
    None => return None
  }
  if text.is_empty() {
    return None
  }
  let mut whole = 0
  let mut fraction = 0
  let mut fraction_scale = 1
  let mut fraction_digits = 0
  let mut extra_fraction_nonzero = false
  let mut has_digit = false
  let mut decimal = false
  for character in text {
    if character == '.' && !decimal {
      decimal = true
    } else if character >= '0' && character <= '9' {
      has_digit = true
      let digit = character.to_int() - '0'.to_int()
      if decimal {
        if fraction_digits < 3 {
          fraction = fraction * 10 + digit
          fraction_scale *= 10
          fraction_digits += 1
        } else if digit != 0 {
          extra_fraction_nonzero = true
        }
      } else {
        whole = whole * 10 + digit
        if whole > 2147483 {
          return Some(10001)
        }
      }
    } else {
      return None
    }
  }
  if !has_digit {
    return None
  }
  if whole > 10 {
    return Some(10001)
  }
  let mut milliseconds = whole * 1000
  if fraction_digits > 0 {
    milliseconds += fraction * 1000 / fraction_scale
  }
  if extra_fraction_nonzero {
    milliseconds += 1
  }
  if milliseconds > 10000 {
    return Some(10001)
  }
  if milliseconds > 0 {
    Some(milliseconds)
  } else {
    None
  }
}
