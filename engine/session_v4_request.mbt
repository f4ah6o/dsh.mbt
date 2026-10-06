///|
fn validate_v4_request_header(
  replay : V4Replay,
  data : Json,
) -> Unit raise EngineError {
  let reason = required_string(data, "reason", max=32)
  if reason != "initial" &&
    reason != "resume" &&
    reason != "change" &&
    reason != "series" {
    raise Invalid("Unknown Session v4 request/header reason")
  }
  for key, _ in fields(data) {
    if key != "reason" && key != "header" && key != "startsSeries" {
      raise Invalid("Unsupported Session v4 request/header field: {key}")
    }
  }
  match fields(data).get("startsSeries") {
    None => ()
    Some(value) =>
      if !bool_value(value, "startsSeries") {
        raise Invalid("Session v4 startsSeries must be true when present")
      }
  }
  let header = required_field(data, "header")
  for key, _ in fields(header) {
    if key != "config" && key != "adapterDefaults" && key != "tools" {
      raise Invalid("Unsupported Session v4 request header field: {key}")
    }
  }
  let config = required_field(header, "config")
  for key, _ in fields(config) {
    if key != "provider" &&
      key != "model" &&
      key != "maxTokens" &&
      key != "reasoningEffort" {
      raise Invalid("Unsupported Session v4 model configuration field: {key}")
    }
  }
  if required_string(config, "provider", max=256).length() == 0 ||
    required_string(config, "model", max=256).length() == 0 {
    raise Invalid("Session v4 request header requires provider and model")
  }
  match fields(config).get("maxTokens") {
    None => ()
    Some(value) => ignore(int_value(value, "maxTokens", 1, 10000000))
  }
  match fields(config).get("reasoningEffort") {
    None => ()
    Some(value) => ignore(string_value(value, "reasoningEffort", max=32))
  }
  match fields(header).get("tools") {
    None => ()
    Some(Json::String("{{tools}}")) if replay.snapshot => ()
    Some(Json::String(_)) =>
      raise Invalid(
        "Session v4 request header tools string is not a snapshot placeholder",
      )
    Some(Json::Array(tools)) => {
      let names : Map[String, Bool] = Map([])
      for tool in tools {
        let name = match tool {
          Json::String(tool_name) if replay.snapshot => {
            if tool_name.length() == 0 {
              raise Invalid("Session v4 request tool name must not be empty")
            }
            tool_name
          }
          Json::Object(_) => validate_v4_tool_definition(tool)
          _ =>
            raise Invalid("Session v4 request tool must be a definition object")
        }
        if names.get(name) is Some(_) {
          raise Invalid("Session v4 request header repeats tool name: {name}")
        }
        names.set(name, true)
      }
    }
    Some(_) => raise Invalid("Session v4 request header tools must be an array")
  }
  match fields(header).get("adapterDefaults") {
    None => ()
    Some(defaults) =>
      for key, value in fields(defaults) {
        if key != "reasoningEffort" && key != "maxTokens" {
          raise Invalid("Unsupported Session v4 adapter default: {key}")
        }
        match value {
          Json::True => ()
          _ => raise Invalid("Session v4 adapter default markers must be true")
        }
        if fields(config).get(key) is None {
          raise Invalid(
            "Session v4 adapter default has no matching config value: {key}",
          )
        }
      }
  }
  replay.request_header = Some(header)
  replay.request_context_seen = false
}

///|
fn validate_v4_tool_definition(tool : Json) -> String raise EngineError {
  let name = required_string(tool, "name", max=256)
  if name.length() == 0 {
    raise Invalid("Session v4 request tool name must not be empty")
  }
  ignore(
    string_value(
      required_field(tool, "description"),
      "tool description",
      max=16384,
    ),
  )
  ignore(fields(required_field(tool, "parameters")))
  match fields(tool).get("deferLoading") {
    None => ()
    Some(Json::True) => ()
    Some(_) =>
      raise Invalid("Session v4 tool deferLoading must be true when present")
  }
  name
}

///|
fn validate_v4_developer_header(
  replay : V4Replay,
  data : Json,
  message : Json,
  source_seq : Int,
  line_number : Int,
) -> Unit raise EngineError {
  let content = project_v4_content(
    required_field(message, "content"),
    false,
    true,
    line_number,
  )
  let header_seq = fields(data).get("headerSeq")
  let mut addition_count = 0
  for change in content.changes {
    if required_string(change, "type", max=32) == "tool-addition" {
      addition_count += 1
    }
  }
  if addition_count == 0 {
    if header_seq is Some(_) {
      raise Invalid(
        "Session v4 developer/message must omit headerSeq without tool additions",
      )
    }
    return
  }
  let seq = match header_seq {
    Some(value) => int_value(value, "developer headerSeq", 0, source_seq)
    None => raise Invalid("Session v4 tool addition requires headerSeq")
  }
  if replay.source_types.get(seq) != Some("request/header") {
    raise Invalid(
      "Session v4 developer headerSeq must reference an earlier request/header",
    )
  }
  let header_record = match replay.source_records.get(seq) {
    Some(value) => value
    None => raise Invalid("Session v4 developer headerSeq source is missing")
  }
  let header = required_field(required_field(header_record, "data"), "header")
  let tools = match fields(header).get("tools") {
    Some(Json::Array(tools)) => tools
    _ =>
      raise Invalid("Session v4 tool addition header has no tool definitions")
  }
  for change in content.changes {
    if required_string(change, "type", max=32) != "tool-addition" {
      continue
    }
    let name = required_string(change, "tool_name", max=256)
    let mut matches = 0
    for tool in tools {
      let tool_name = match tool {
        Json::String(tool_name) if replay.snapshot => Some(tool_name)
        Json::Object(_) => Some(validate_v4_tool_definition(tool))
        _ => None
      }
      if tool_name == Some(name) {
        matches += 1
      }
    }
    if matches != 1 {
      raise Invalid(
        "Session v4 tool addition must name exactly one tool in its request/header",
      )
    }
  }
}

///|
fn validate_v4_attempt_stream(
  value : Json,
  _line_number : Int,
) -> Unit raise EngineError {
  let stream = array_value(value, "assistant/attempt stream", 32768)
  for entry in stream {
    match fields(entry).get("type") {
      Some(Json::String("chunk")) => {
        let chunk = required_field(entry, "chunk")
        let chunk_type = required_string(chunk, "type", max=64)
        if chunk_type == "block-start" {
          let block_type = required_string(chunk, "blockType", max=64)
          if block_type == "tool-addition" ||
            block_type == "tool-removal" ||
            block_type == "tool-result" {
            raise Invalid(
              "Session v4 assistant/attempt has an unsupported content block",
            )
          }
        } else if chunk_type == "block-end" {
          let block = required_field(chunk, "block")
          let block_type = required_string(block, "type", max=64)
          if block_type == "tool-addition" ||
            block_type == "tool-removal" ||
            block_type == "tool-result" {
            raise Invalid(
              "Session v4 assistant/attempt has an unsupported content block",
            )
          }
        }
      }
      _ => ()
    }
  }
}
