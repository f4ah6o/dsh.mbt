///|
/// Keep model-supplied task lists small enough for snapshots and every
/// presentation surface to carry without truncation.
const TODO_MAX_ITEMS : Int = 64

///|
const TODO_MAX_CONTENT : Int = 512

///|
const TODO_MAX_TOTAL_CONTENT : Int = 8192

///|
fn todo_ecmascript_whitespace(character : Char) -> Bool {
  let codepoint = character.to_int()
  codepoint == 0x0009 ||
  codepoint == 0x000A ||
  codepoint == 0x000B ||
  codepoint == 0x000C ||
  codepoint == 0x000D ||
  codepoint == 0x0020 ||
  codepoint == 0x00A0 ||
  codepoint == 0x1680 ||
  (codepoint >= 0x2000 && codepoint <= 0x200A) ||
  codepoint == 0x2028 ||
  codepoint == 0x2029 ||
  codepoint == 0x202F ||
  codepoint == 0x205F ||
  codepoint == 0x3000 ||
  codepoint == 0xFEFF
}

///|
fn todo_ecmascript_trim(value : String) -> String {
  let characters = value.to_array()
  let mut start = 0
  while start < characters.length() &&
        todo_ecmascript_whitespace(characters[start]) {
    start += 1
  }
  let mut end = characters.length()
  while end > start && todo_ecmascript_whitespace(characters[end - 1]) {
    end -= 1
  }
  String::from_array(characters[start:end])
}

///|
fn todo_write_input_schema() -> Json {
  object([
    ("type", Json::string("object")),
    (
      "properties",
      object([
        (
          "todos",
          object([
            ("type", Json::string("array")),
            (
              "items",
              object([
                ("type", Json::string("object")),
                (
                  "properties",
                  object([
                    ("content", object([("type", Json::string("string"))])),
                    (
                      "status",
                      object([
                        ("type", Json::string("string")),
                        (
                          "enum",
                          Json::array([
                            Json::string("pending"),
                            Json::string("in_progress"),
                            Json::string("completed"),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
                (
                  "required",
                  Json::array([Json::string("content"), Json::string("status")]),
                ),
                ("additionalProperties", Json::boolean(false)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    ("required", Json::array([Json::string("todos")])),
    ("additionalProperties", Json::boolean(false)),
  ])
}

///|
fn normalize_todo_write(arguments : Json) -> Array[Json] raise EngineError {
  let argument_fields = fields(arguments)
  if argument_fields.length() != 1 || argument_fields.get("todos") is None {
    raise Invalid("todo_write arguments must contain only `todos`")
  }
  let raw_items = array_value(
    required_field(arguments, "todos"),
    "todos",
    TODO_MAX_ITEMS,
  )
  let normalized : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let mut active = 0
  let mut total_content = 0
  for item in raw_items {
    let item_fields = fields(item)
    if item_fields.length() != 2 ||
      item_fields.get("content") is None ||
      item_fields.get("status") is None {
      raise Invalid("each todo must contain only `content` and `status`")
    }
    let content = todo_ecmascript_trim(
      required_string(item, "content", max=TODO_MAX_CONTENT),
    )
    if content.is_empty() {
      raise Invalid("todo content must be non-empty after trimming")
    }
    if seen.get(content) is Some(_) {
      raise Invalid("todo content must be unique after trimming")
    }
    seen[content] = true
    total_content += content.length()
    if total_content > TODO_MAX_TOTAL_CONTENT {
      raise Invalid("todo content exceeds the total length limit")
    }
    let status = required_string(item, "status", max=16)
    match status {
      "pending" | "completed" => ()
      "in_progress" => active += 1
      _ =>
        raise Invalid("todo status must be pending, in_progress, or completed")
    }
    normalized.push(
      object([
        ("content", Json::string(content)),
        ("status", Json::string(status)),
      ]),
    )
  }
  if active > 1 {
    raise Invalid("at most one todo may be in_progress")
  }
  normalized
}

///|
fn checked_todo_write(arguments : Json) -> Result[Array[Json], String] {
  Ok(normalize_todo_write(arguments)) catch {
    Invalid(message) => Err(message)
  }
}

///|
fn todo_write_summary(items : Array[Json]) -> String {
  let mut pending = 0
  let mut in_progress = 0
  let mut completed = 0
  for item in items {
    let status = match item {
      { "status": Json::String(value), .. } => value
      _ => ""
    }
    match status {
      "pending" => pending += 1
      "in_progress" => in_progress += 1
      "completed" => completed += 1
      _ => ()
    }
  }
  "Updated todo list: " +
  pending.to_string() +
  " pending, " +
  in_progress.to_string() +
  " in progress, " +
  completed.to_string() +
  " completed."
}

///|
fn Session::record_todo_write(
  self : Session,
  call_id : String,
  items : Array[Json],
) -> Unit {
  self.todos = Some(items.map(detached))
  self.append(
    "todo/write",
    object([
      ("call_id", Json::string(call_id)),
      ("todos", Json::array(items.map(detached))),
    ]),
  )
}

///|
fn Session::stage_session_tool_result(
  self : Session,
  call : ToolCall,
  content : String,
  is_error : Bool,
) -> Unit {
  call.stage = Completed
  call.effect_id = None
  call.completed_content = Some(content)
  call.completed_error = Some(is_error)
  self.append(
    "tool/completed",
    object([
      ("source", Json::string("session")),
      ("call_id", Json::string(call.id)),
      ("content", Json::string(content)),
      ("is_error", boolean(is_error)),
    ]),
  )
}
