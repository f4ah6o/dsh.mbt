// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
priv suberror ProviderError {
  ProviderError(String)
}

///|
fn[A] reject(code : String, detail : String) -> A raise ProviderError {
  raise ProviderError(code + ": " + detail)
}

///|
fn object(
  value : Json,
  where_ : String,
) -> Map[String, Json] raise ProviderError {
  match value {
    Object(fields) => fields
    _ => reject("INVALID_JSON", where_ + " must be an object")
  }
}

///|
fn field(fields : Map[String, Json], key : String) -> Json raise ProviderError {
  match fields.get(key) {
    Some(value) => value
    None => reject("INVALID_JSON", "missing " + key)
  }
}

///|
fn string(value : Json, where_ : String) -> String raise ProviderError {
  match value {
    String(value) => value
    _ => reject("INVALID_JSON", where_ + " must be a string")
  }
}

///|
fn text_field(
  fields : Map[String, Json],
  key : String,
) -> String raise ProviderError {
  string(field(fields, key), key)
}

///|
fn text_content_blocks(
  value : Json,
  where_ : String,
) -> Array[Json] raise ProviderError {
  match value {
    String(text) =>
      if text.is_empty() {
        []
      } else {
        [{ "type": "text".to_json(), "text": text.to_json() }]
      }
    Array(raw_blocks) => {
      if raw_blocks.is_empty() {
        reject("INVALID_REQUEST", where_ + " content blocks must not be empty")
      }
      let blocks : Array[Json] = []
      for raw_block in raw_blocks {
        let block = object(raw_block, where_ + " content block")
        if block.length() != 2 || text_field(block, "type") != "text" {
          reject(
            "INVALID_REQUEST",
            where_ + " supports only text content blocks",
          )
        }
        let text = text_field(block, "text")
        blocks.push({ "type": "text".to_json(), "text": text.to_json() })
      }
      blocks
    }
    _ =>
      reject("INVALID_REQUEST", where_ + " content must be text or text blocks")
  }
}

///|
fn has_hooks_context_source(message : Map[String, Json]) -> Bool {
  match message.get("source") {
    Some(Json::Object(source)) =>
      source.length() == 1 &&
      source.get("kind") == Some(Json::string("hooks-claude-code"))
    _ => false
  }
}

///|
fn identity(
  fields : Map[String, Json],
  key : String,
) -> String raise ProviderError {
  let value = text_field(fields, key)
  if value.is_empty() {
    reject("INVALID_JSON", key + " must not be empty")
  }
  value
}

///|
fn optional_text(
  fields : Map[String, Json],
  key : String,
) -> String? raise ProviderError {
  match fields.get(key) {
    None | Some(Null) => None
    Some(value) => Some(string(value, key))
  }
}

///|
fn array(value : Json, where_ : String) -> Array[Json] raise ProviderError {
  match value {
    Array(values) => values
    _ => reject("INVALID_JSON", where_ + " must be an array")
  }
}

///|
fn optional_array(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise ProviderError {
  match fields.get(key) {
    None => []
    Some(value) => array(value, key)
  }
}

///|
fn boolean(value : Json, where_ : String) -> Bool raise ProviderError {
  match value {
    True => true
    False => false
    _ => reject("INVALID_JSON", where_ + " must be a boolean")
  }
}

///|
fn integer(value : Json, where_ : String) -> Int raise ProviderError {
  match value {
    Number(number, ..) => {
      if number < 0.0 ||
        number > 2147483647.0 ||
        number != number.to_int().to_double() {
        reject("INVALID_JSON", where_ + " must be a nonnegative 32-bit integer")
      }
      number.to_int()
    }
    _ => reject("INVALID_JSON", where_ + " must be an integer")
  }
}

///|
fn parse_object(value : String, where_ : String) -> Json raise ProviderError {
  let parsed = @json.parse(value) catch {
    _ => reject("INVALID_JSON", where_ + " must contain valid JSON")
  }
  ignore(object(parsed, where_))
  parsed
}

///|
fn validate_mode(mode : String) -> Unit raise ProviderError {
  if mode != "deepseek" && mode != "openai" {
    reject("INVALID_REQUEST", "provider mode must be deepseek or openai")
  }
}

///|
fn reject_provider_error(
  fields : Map[String, Json],
) -> Unit raise ProviderError {
  match fields.get("error") {
    None | Some(Null) => ()
    Some(error) => {
      let error = object(error, "provider error")
      let kind = optional_text(error, "type").unwrap_or("provider_error")
      let detail = optional_text(error, "message").unwrap_or(
        "provider returned an error",
      )
      reject("PROVIDER_ERROR", kind + ": " + detail)
    }
  }
}

///|
fn normalized_reason(mode : String, raw : String) -> String raise ProviderError {
  match (mode, raw) {
    ("deepseek", "end_turn" | "stop_sequence") | ("openai", "stop") => "stop"
    ("deepseek", "tool_use") | ("openai", "tool_calls") => "tool_calls"
    ("deepseek", "max_tokens") | ("openai", "length") => "length"
    ("openai", "content_filter") =>
      reject("REFUSAL", "provider applied a content filter")
    _ => reject("MALFORMED_RESPONSE", "unsupported finish reason " + raw)
  }
}

///|
fn update_usage(
  mode : String,
  usage : Map[String, Json],
  raw : Json,
) -> Unit raise ProviderError {
  let fields = object(raw, "usage")
  let keys = if mode == "deepseek" {
    [
      ("input_tokens", "input_tokens"),
      ("output_tokens", "output_tokens"),
      ("cache_read_input_tokens", "cache_read_input_tokens"),
      ("cache_creation_input_tokens", "cache_creation_input_tokens"),
    ]
  } else if mode == "responses" {
    [
      ("input_tokens", "input_tokens"),
      ("output_tokens", "output_tokens"),
      ("total_tokens", "total_tokens"),
    ]
  } else {
    [
      ("prompt_tokens", "input_tokens"),
      ("completion_tokens", "output_tokens"),
      ("total_tokens", "total_tokens"),
    ]
  }
  for pair in keys {
    let (wire, normalized) = pair
    match fields.get(wire) {
      None => ()
      Some(value) => usage[normalized] = integer(value, wire).to_json()
    }
  }
  if mode == "openai" {
    match fields.get("prompt_tokens_details") {
      Some(Null) | None => ()
      Some(value) => {
        let details = object(value, "prompt_tokens_details")
        match details.get("cached_tokens") {
          None => ()
          Some(value) =>
            usage["cache_read_input_tokens"] = integer(value, "cached_tokens").to_json()
        }
      }
    }
  } else if mode == "responses" {
    match fields.get("input_tokens_details") {
      Some(Null) | None => ()
      Some(value) => {
        let details = object(value, "input_tokens_details")
        match details.get("cached_tokens") {
          None => ()
          Some(value) =>
            usage["cache_read_input_tokens"] = integer(value, "cached_tokens").to_json()
        }
      }
    }
  }
}

///|
fn result_json(
  content : String,
  reasoning : String,
  calls : Array[Json],
  reason : String,
  usage : Map[String, Json],
) -> Json raise ProviderError {
  if reason == "tool_calls" && calls.is_empty() {
    reject("MALFORMED_RESPONSE", "tool_calls finish has no tool calls")
  }
  if reason == "stop" && !calls.is_empty() {
    reject("MALFORMED_RESPONSE", "tool calls require tool_calls finish")
  }
  if reason == "stop" && content.is_empty() && reasoning.is_empty() {
    reject("EMPTY_RESPONSE", "provider returned no content")
  }
  let result : Map[String, Json] = {
    "ok": true.to_json(),
    "content": content.to_json(),
    "tool_calls": Json::array(if reason == "length" { [] } else { calls }),
    "finish_reason": reason.to_json(),
  }
  if !reasoning.is_empty() {
    result["reasoning"] = reasoning.to_json()
  }
  if !usage.is_empty() {
    result["usage"] = Json::object(usage.copy())
  }
  Json::object(result)
}
