///|
const NATIVE_ACP_PROTOCOL_VERSION : Int = 1

///|
const NATIVE_ACP_LINE_LIMIT : Int = 1048576

///|
const NATIVE_ACP_MAX_JSON_NODES : Int = 8192

///|
const NATIVE_ACP_MAX_JSON_TEXT : Int = 262144

///|
const NATIVE_ACP_MAX_PROMPT_CHARS : Int = 16384

///|
const NATIVE_ACP_UPDATE_CHUNK_CHARS : Int = 4096

///|
priv struct NativeAcpFrame {
  bytes : Array[Byte]
  too_large : Bool
}

///|
/// Bounded newline framing for the ACP JSON-RPC stdio transport.
priv struct NativeAcpFramer {
  mut buffered : Array[Byte]
  mut discarding : Bool
}

///|
fn NativeAcpFramer::new() -> NativeAcpFramer {
  { buffered: [], discarding: false, }
}

///|
fn NativeAcpFramer::take_line(self : NativeAcpFramer) -> NativeAcpFrame {
  if self.buffered.length() > 0 &&
    self.buffered[self.buffered.length() - 1] == b'\r' {
    ignore(self.buffered.pop())
  }
  let frame : NativeAcpFrame = { bytes: self.buffered, too_large: false, }
  self.buffered = []
  frame
}

///|
fn NativeAcpFramer::feed(
  self : NativeAcpFramer,
  chunk : Bytes,
) -> Array[NativeAcpFrame] {
  let frames : Array[NativeAcpFrame] = []
  for byte in chunk {
    if byte == b'\n' {
      if self.discarding {
        self.discarding = false
      } else {
        let frame = self.take_line()
        if frame.bytes.length() > NATIVE_ACP_LINE_LIMIT {
          frames.push({ bytes: [], too_large: true, })
        } else {
          frames.push(frame)
        }
      }
    } else if !self.discarding {
      let trailing_cr_candidate = self.buffered.length() ==
        NATIVE_ACP_LINE_LIMIT &&
        byte == b'\r'
      if self.buffered.length() > NATIVE_ACP_LINE_LIMIT ||
        (
          self.buffered.length() == NATIVE_ACP_LINE_LIMIT &&
          !trailing_cr_candidate
        ) {
        self.discarding = true
        self.buffered = []
        frames.push({ bytes: [], too_large: true, })
      } else {
        self.buffered.push(byte)
      }
    }
  }
  frames
}

///|
fn NativeAcpFramer::finish(self : NativeAcpFramer) -> Array[NativeAcpFrame] {
  if self.discarding || self.buffered.length() == 0 {
    []
  } else if self.buffered.length() > NATIVE_ACP_LINE_LIMIT {
    [{ bytes: [], too_large: true, }]
  } else {
    [self.take_line()]
  }
}

///|
priv struct NativeAcpJsonBudget {
  mut nodes : Int
  mut text : Int
}

///|
/// Copy one parsed JSON value under explicit depth, node, and text budgets.
fn native_acp_copy_bounded_json(
  value : Json,
  depth : Int,
  budget : NativeAcpJsonBudget,
) -> Result[Json, String] {
  if depth > 24 {
    return Err("ACP JSON exceeds the nesting limit")
  }
  budget.nodes -= 1
  if budget.nodes < 0 {
    return Err("ACP JSON exceeds the node limit")
  }
  match value {
    Json::Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, item in fields {
        budget.text -= key.length()
        if budget.text < 0 {
          return Err("ACP JSON exceeds the text limit")
        }
        copied[key] = match
          native_acp_copy_bounded_json(item, depth + 1, budget) {
          Ok(copy) => copy
          Err(error) => return Err(error)
        }
      }
      Ok(Json::object(copied))
    }
    Json::Array(items) => {
      let copied : Array[Json] = []
      for item in items {
        copied.push(
          match native_acp_copy_bounded_json(item, depth + 1, budget) {
            Ok(copy) => copy
            Err(error) => return Err(error)
          },
        )
      }
      Ok(Json::array(copied))
    }
    Json::String(text) => {
      budget.text -= text.length()
      if budget.text < 0 {
        Err("ACP JSON exceeds the text limit")
      } else {
        Ok(Json::string(text))
      }
    }
    Json::Number(number, ..) if !number.is_nan() && !number.is_inf() =>
      Ok(Json::number(number))
    Json::Number(_, ..) => Err("ACP JSON contains a non-finite number")
    Json::True => Ok(Json::boolean(true))
    Json::False => Ok(Json::boolean(false))
    Json::Null => Ok(Json::null())
  }
}

///|
fn native_acp_finite_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn native_acp_safe_integer(value : Double) -> Bool {
  native_acp_finite_number(value) &&
  value >= -9007199254740991.0 &&
  value <= 9007199254740991.0 &&
  value.to_int().to_double() == value
}

///|
fn native_acp_decode_json(bytes : Array[Byte]) -> Result[Json, String] {
  match native_acp_validate_nesting(Bytes::from_array(bytes[:])) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let text = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("ACP JSON-RPC line is not valid UTF-8")
  }
  let parsed = @json.parse(text) catch {
    _ => return Err("ACP JSON-RPC line is malformed JSON")
  }
  let budget : NativeAcpJsonBudget = {
    nodes: NATIVE_ACP_MAX_JSON_NODES,
    text: NATIVE_ACP_MAX_JSON_TEXT,
  }
  native_acp_copy_bounded_json(parsed, 0, budget)
}

///|
/// Reject excessive container depth before invoking the recursive JSON parser.
fn native_acp_validate_nesting(bytes : Bytes) -> Result[Unit, String] {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for byte in bytes {
    if in_string {
      if escaped {
        escaped = false
      } else if byte == b'\\' {
        escaped = true
      } else if byte == b'"' {
        in_string = false
      }
    } else if byte == b'"' {
      in_string = true
    } else if byte == b'{' || byte == b'[' {
      depth += 1
      if depth > 24 {
        return Err("ACP JSON exceeds the nesting limit")
      }
    } else if byte == b'}' || byte == b']' {
      depth -= 1
      if depth < 0 {
        return Err("ACP JSON-RPC line is malformed JSON")
      }
    }
  }
  // Incomplete strings and delimiters remain the JSON parser's responsibility.
  Ok(())
}

///|
priv struct NativeAcpRpcMessage {
  id : Json?
  request_method : String?
  params : Json
}

///|
/// Validate the JSON-RPC envelope before a method-specific parser sees it.
fn native_acp_rpc_message(value : Json) -> Result[NativeAcpRpcMessage, String] {
  let fields = match value {
    Json::Object(fields) => fields
    _ => return Err("ACP JSON-RPC message must be an object")
  }
  if native_mcp_json_string(fields.get("jsonrpc")) != Some("2.0") {
    return Err("ACP JSON-RPC version must be 2.0")
  }
  let id = fields.get("id")
  match id {
    Some(Json::String(value)) if value.length() <= 128 => ()
    Some(Json::Number(value, ..)) if native_acp_finite_number(value) => ()
    Some(Json::Null) | None => ()
    Some(_) => return Err("ACP JSON-RPC id must be a string or safe integer")
  }
  let request_method = match fields.get("method") {
    Some(Json::String(value)) if !value.is_empty() && value.length() <= 128 =>
      Some(value)
    Some(Json::String(_)) => return Err("ACP JSON-RPC method is invalid")
    Some(_) => return Err("ACP JSON-RPC method must be a string")
    None => None
  }
  if request_method is Some(_) &&
    (fields.get("result") is Some(_) || fields.get("error") is Some(_)) {
    return Err("ACP JSON-RPC request cannot contain a response body")
  }
  if request_method is None &&
    fields.get("result") is None &&
    fields.get("error") is None {
    return Err("ACP JSON-RPC response must contain result or error")
  }
  if fields.get("result") is Some(_) && fields.get("error") is Some(_) {
    return Err("ACP JSON-RPC response cannot contain result and error")
  }
  let params = match fields.get("params") {
    None => Json::empty_object()
    Some(Json::Object(_)) => fields.get("params").unwrap()
    Some(_) => return Err("ACP JSON-RPC params must be an object")
  }
  Ok({ id, request_method, params, })
}

///|
fn native_acp_id_key(value : Json) -> String? {
  match value {
    Json::String(text) if text.length() <= 128 => Some("s:" + text)
    Json::Number(number, ..) if native_acp_finite_number(number) =>
      Some("n:" + number.to_string())
    Json::Null => Some("z:null")
    _ => None
  }
}

///|
fn native_acp_rpc_success(id : Json, result : Json) -> String {
  Json::object({ "jsonrpc": Json::string("2.0"), "id": id, "result": result }).stringify()
}

///|
fn native_acp_rpc_error(id : Json, code : Int, message : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "error": Json::object({
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    }),
  }).stringify()
}

///|
fn native_acp_parse_tool_arguments(value : String) -> Json? {
  if value.length() > 65536 {
    return None
  }
  match native_acp_validate_nesting(@utf8.encode(value)) {
    Ok(_) => ()
    Err(_) => return None
  }
  let parsed = @json.parse(value) catch { _ => return None }
  match parsed {
    Json::Object(_) => {
      let budget : NativeAcpJsonBudget = { nodes: 1024, text: 65536, }
      match native_acp_copy_bounded_json(parsed, 0, budget) {
        Ok(copy) => Some(copy)
        Err(_) => None
      }
    }
    _ => None
  }
}

///|
fn native_acp_split_text(text : String) -> Array[String] {
  let chunks : Array[String] = []
  let mut count = 0
  let mut current = StringBuilder()
  for character in text {
    current.write_char(character)
    count += 1
    if count == NATIVE_ACP_UPDATE_CHUNK_CHARS {
      chunks.push(current.to_string())
      current = StringBuilder()
      count = 0
    }
  }
  if count > 0 {
    chunks.push(current.to_string())
  }
  chunks
}
