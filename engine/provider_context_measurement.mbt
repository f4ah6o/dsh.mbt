///|
/// A model-independent measurement of one admitted engine provider request.
/// These serialized sizes are not tokenizer counts or provider window limits.
pub struct ProviderContextMeasurement {
  priv request_json_utf8_bytes : Int32
  priv system_text_utf8_bytes : Int32
  priv system_text_code_points : Int32
  priv messages_json_utf8_bytes : Int32
  priv message_count : Int32
  priv tools_json_utf8_bytes : Int32
  priv tool_count : Int32
}

///|
const PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES : Int32 = 16777216

///|
const PROVIDER_CONTEXT_MEASUREMENT_MAX_NODES : Int32 = 16777216

///|
const PROVIDER_CONTEXT_MEASUREMENT_MAX_DEPTH : Int32 = 128

///|
priv struct ProviderContextMeasureBudget {
  mut bytes : Int32
  mut nodes : Int32
}

///|
fn provider_context_measure_add(
  budget : ProviderContextMeasureBudget,
  bytes : Int32,
) -> Result[Unit, String] {
  if bytes < 0 ||
    budget.bytes > PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES - bytes {
    return Err("provider context measurement exceeds the 16 MiB bound")
  }
  budget.bytes += bytes
  Ok(())
}

///|
fn provider_context_measure_scalar_bytes(code : Int32) -> Int32 {
  if code <= 0x7F {
    1
  } else if code <= 0x7FF {
    2
  } else if code <= 0xFFFF {
    3
  } else {
    4
  }
}

///|
/// Count the exact default JSON-stringify UTF-8 size without creating the
/// serialized string. Reject invalid UTF-16 so native UTF-8 encoding can never
/// panic on a lone surrogate.
fn provider_context_measure_json_string(
  text : String,
  budget : ProviderContextMeasureBudget,
) -> Result[Unit, String] {
  match provider_context_measure_add(budget, 2) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut index = 0
  while index < text.length() {
    let code = text.unsafe_get(index).to_int()
    if code == 0x22 || code == 0x5C {
      match provider_context_measure_add(budget, 2) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      index += 1
    } else if code < 0x20 {
      let escaped_bytes = if code == 0x08 ||
        code == 0x09 ||
        code == 0x0A ||
        code == 0x0C ||
        code == 0x0D {
        2
      } else {
        6
      }
      match provider_context_measure_add(budget, escaped_bytes) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      index += 1
    } else if code >= 0xD800 && code <= 0xDBFF {
      if index + 1 >= text.length() {
        return Err("provider request contains an unpaired surrogate")
      }
      let trail = text.unsafe_get(index + 1).to_int()
      if trail < 0xDC00 || trail > 0xDFFF {
        return Err("provider request contains an unpaired surrogate")
      }
      match provider_context_measure_add(budget, 4) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      index += 2
    } else if code >= 0xDC00 && code <= 0xDFFF {
      return Err("provider request contains an unpaired surrogate")
    } else {
      match
        provider_context_measure_add(
          budget,
          provider_context_measure_scalar_bytes(code),
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      index += 1
    }
  }
  Ok(())
}

///|
/// Count raw UTF-8 bytes and Unicode scalar values for user-facing system text.
fn provider_context_measure_text_stats(
  text : String,
) -> Result[(Int32, Int32), String] {
  let mut bytes = 0
  let mut code_points = 0
  let mut index = 0
  while index < text.length() {
    let code = text.unsafe_get(index).to_int()
    if code >= 0xD800 && code <= 0xDBFF {
      if index + 1 >= text.length() {
        return Err("system text contains an unpaired surrogate")
      }
      let trail = text.unsafe_get(index + 1).to_int()
      if trail < 0xDC00 || trail > 0xDFFF {
        return Err("system text contains an unpaired surrogate")
      }
      bytes += 4
      index += 2
    } else if code >= 0xDC00 && code <= 0xDFFF {
      return Err("system text contains an unpaired surrogate")
    } else {
      bytes += provider_context_measure_scalar_bytes(code)
      index += 1
    }
    code_points += 1
  }
  Ok((bytes, code_points))
}

///|
fn provider_context_measure_ascii_number(
  text : String,
  budget : ProviderContextMeasureBudget,
) -> Result[Unit, String] {
  for code in text.code_units() {
    if code.to_int() > 0x7F {
      return Err("provider request contains a malformed JSON number")
    }
    match provider_context_measure_add(budget, 1) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn provider_context_measure_json_value(
  value : Json,
  depth : Int32,
  budget : ProviderContextMeasureBudget,
) -> Result[Unit, String] {
  if depth > PROVIDER_CONTEXT_MEASUREMENT_MAX_DEPTH {
    return Err("provider context measurement exceeds the nesting limit")
  }
  if budget.nodes >= PROVIDER_CONTEXT_MEASUREMENT_MAX_NODES {
    return Err("provider context measurement exceeds the node limit")
  }
  budget.nodes += 1
  match value {
    Json::Null => provider_context_measure_add(budget, 4)
    Json::True => provider_context_measure_add(budget, 4)
    Json::False => provider_context_measure_add(budget, 5)
    Json::Number(number, repr~) => {
      let rendered = match repr {
        Some(text) => text
        None => Json::number(number).stringify()
      }
      provider_context_measure_ascii_number(rendered, budget)
    }
    Json::String(text) => provider_context_measure_json_string(text, budget)
    Json::Array(values) => {
      match provider_context_measure_add(budget, 2) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      for index, item in values {
        if index > 0 {
          match provider_context_measure_add(budget, 1) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
        match provider_context_measure_json_value(item, depth + 1, budget) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      Ok(())
    }
    Json::Object(values) => {
      match provider_context_measure_add(budget, 2) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let mut first = true
      for key, item in values {
        if !first {
          match provider_context_measure_add(budget, 1) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
        match provider_context_measure_json_string(key, budget) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        match provider_context_measure_add(budget, 1) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        match provider_context_measure_json_value(item, depth + 1, budget) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        first = false
      }
      Ok(())
    }
  }
}

///|
fn provider_context_measure_json_bytes(value : Json) -> Result[Int32, String] {
  let budget : ProviderContextMeasureBudget = { bytes: 0, nodes: 0, }
  match provider_context_measure_json_value(value, 0, budget) {
    Ok(_) => Ok(budget.bytes)
    Err(error) => Err(error)
  }
}

///|
fn provider_context_measure_request(
  request : Json,
) -> Result[ProviderContextMeasurement, String] {
  let values = match request {
    Json::Object(value) => value
    _ => return Err("provider request must be an object")
  }
  if values.length() != 3 {
    return Err("provider request has an unsupported shape")
  }
  let system = match values.get("system") {
    Some(Json::String(value)) => value
    _ => return Err("provider request is missing its system text")
  }
  let messages = match values.get("messages") {
    Some(Json::Array(value)) => value
    _ => return Err("provider request is missing its messages")
  }
  let tools = match values.get("tools") {
    Some(Json::Array(value)) => value
    _ => return Err("provider request is missing its tool schemas")
  }
  let request_json_utf8_bytes = match
    provider_context_measure_json_bytes(request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let messages_json_utf8_bytes = match
    provider_context_measure_json_bytes(Json::array(messages)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tools_json_utf8_bytes = match
    provider_context_measure_json_bytes(Json::array(tools)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (system_text_utf8_bytes, system_text_code_points) = match
    provider_context_measure_text_stats(system) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    request_json_utf8_bytes,
    system_text_utf8_bytes,
    system_text_code_points,
    messages_json_utf8_bytes,
    message_count: messages.length(),
    tools_json_utf8_bytes,
    tool_count: tools.length(),
  })
}

///|
/// Return size measurements for the exact active provider request, if this
/// session currently has one. Reading the effect map leaves the dispatch queue
/// and active effect unchanged, even after a host has drained that queue.
pub fn Engine::provider_context_measurement(
  self : Engine,
  session_id : SessionId,
) -> Result[ProviderContextMeasurement?, String] {
  try {
    let session = self.lookup(session_id.as_string())
    match session.active_effect {
      None => Ok(None)
      Some(effect_id) => {
        let effect = match self.effects.get(effect_id) {
          Some(value) => value
          None => return Err("active provider effect is missing")
        }
        if effect.kind != Llm || effect.session_id != session.id {
          return Err("active effect is not this session's provider request")
        }
        match provider_context_measure_request(effect.request) {
          Ok(value) => Ok(Some(value))
          Err(error) => Err(error)
        }
      }
    }
  } catch {
    Invalid(error) => Err(error)
  }
}

///|
pub fn ProviderContextMeasurement::request_json_utf8_bytes(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.request_json_utf8_bytes
}

///|
pub fn ProviderContextMeasurement::system_text_utf8_bytes(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.system_text_utf8_bytes
}

///|
pub fn ProviderContextMeasurement::system_text_code_points(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.system_text_code_points
}

///|
pub fn ProviderContextMeasurement::messages_json_utf8_bytes(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.messages_json_utf8_bytes
}

///|
pub fn ProviderContextMeasurement::message_count(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.message_count
}

///|
pub fn ProviderContextMeasurement::tools_json_utf8_bytes(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.tools_json_utf8_bytes
}

///|
pub fn ProviderContextMeasurement::tool_count(
  self : ProviderContextMeasurement,
) -> Int32 {
  self.tool_count
}

///|
pub fn ProviderContextMeasurement::json(
  self : ProviderContextMeasurement,
) -> Json {
  Json::object({
    "request_json_utf8_bytes": Json::number(
      self.request_json_utf8_bytes.to_double(),
    ),
    "system_text_utf8_bytes": Json::number(
      self.system_text_utf8_bytes.to_double(),
    ),
    "system_text_code_points": Json::number(
      self.system_text_code_points.to_double(),
    ),
    "messages_json_utf8_bytes": Json::number(
      self.messages_json_utf8_bytes.to_double(),
    ),
    "message_count": Json::number(self.message_count.to_double()),
    "tools_json_utf8_bytes": Json::number(
      self.tools_json_utf8_bytes.to_double(),
    ),
    "tool_count": Json::number(self.tool_count.to_double()),
    "unit": Json::string("utf8_bytes_and_code_points"),
  })
}
