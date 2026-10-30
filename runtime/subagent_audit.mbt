///|
/// The bounded, inert v1 child-audit envelope. This codec is not wired to the
/// runtime or store; callers must not treat a decoded record as resumable work.
const NATIVE_SUBAGENT_AUDIT_SCHEMA : String = "dsh-subagent-audit-v1"

///|
const NATIVE_SUBAGENT_AUDIT_MAX_BYTES : Int32 = 4194304

///|
const NATIVE_SUBAGENT_AUDIT_MAX_DEPTH : Int32 = 32

///|
const NATIVE_SUBAGENT_AUDIT_MAX_NODES : Int32 = 65536

///|
priv struct NativeSubagentAuditJsonFrame {
  is_object : Bool
  keys : Map[String, Bool]
}

///|
priv struct NativeSubagentAuditJsonBudget {
  mut nodes : Int32
  mut text_bytes : Int32
}

///|
/// Copy one JSON value while bounding recursive work and UTF-8 text storage.
fn native_subagent_audit_copy_json(
  value : Json,
  depth : Int32,
  budget : NativeSubagentAuditJsonBudget,
) -> Result[Json, String] {
  let is_container = match value {
    Json::Object(_) | Json::Array(_) => true
    _ => false
  }
  if depth > NATIVE_SUBAGENT_AUDIT_MAX_DEPTH ||
    (is_container && depth >= NATIVE_SUBAGENT_AUDIT_MAX_DEPTH) {
    return Err("subagent audit JSON exceeds the nesting limit")
  }
  budget.nodes -= 1
  if budget.nodes < 0 {
    return Err("subagent audit JSON exceeds the node limit")
  }
  match value {
    Json::Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, item in fields {
        budget.text_bytes -= @utf8.encode(key).length()
        if budget.text_bytes < 0 {
          return Err("subagent audit JSON exceeds the text limit")
        }
        copied[key] = match
          native_subagent_audit_copy_json(item, depth + 1, budget) {
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
          match native_subagent_audit_copy_json(item, depth + 1, budget) {
            Ok(copy) => copy
            Err(error) => return Err(error)
          },
        )
      }
      Ok(Json::array(copied))
    }
    Json::String(text) => {
      budget.text_bytes -= @utf8.encode(text).length()
      if budget.text_bytes < 0 {
        Err("subagent audit JSON exceeds the text limit")
      } else {
        Ok(Json::string(text))
      }
    }
    Json::Number(number, ..) if !number.is_nan() && !number.is_inf() =>
      Ok(Json::number(number))
    Json::Number(_, ..) =>
      Err("subagent audit JSON contains a non-finite number")
    Json::True => Ok(Json::boolean(true))
    Json::False => Ok(Json::boolean(false))
    Json::Null => Ok(Json::null())
  }
}

///|
/// Reject duplicate object keys and excessive JSON budgets before invoking the
/// recursive parser. The core parser keeps the last duplicate key, which would
/// otherwise make the meaning of correlation fields depend on parser policy.
fn native_subagent_audit_validate_nesting(
  bytes : Bytes,
) -> Result[Unit, String] {
  let source = bytes.to_array()
  let mut depth = 0
  let mut nodes = 0
  let frames : Array[NativeSubagentAuditJsonFrame] = []
  let mut in_string = false
  let mut escaped = false
  let mut string_start = 0
  let mut index = 0
  while index < source.length() {
    let byte = source[index]
    if in_string {
      if escaped {
        escaped = false
      } else if byte == b'\\' {
        escaped = true
      } else if byte == b'"' {
        in_string = false
        let mut after_string = index + 1
        while after_string < source.length() &&
              (
                source[after_string] == b' ' ||
                source[after_string] == b'\n' ||
                source[after_string] == b'\r' ||
                source[after_string] == b'\t'
              ) {
          after_string += 1
        }
        if after_string < source.length() && source[after_string] == b':' {
          if frames.length() == 0 || !frames[frames.length() - 1].is_object {
            return Err("subagent audit JSON is malformed")
          }
          let token = @utf8.decode(
            Bytes::from_array(source[string_start:index + 1]),
          ) catch {
            _ => return Err("subagent audit JSON is malformed")
          }
          let parsed_key = @json.parse(token) catch {
            _ => return Err("subagent audit JSON is malformed")
          }
          let key = match parsed_key {
            Json::String(value) => value
            _ => return Err("subagent audit JSON is malformed")
          }
          let frame = frames[frames.length() - 1]
          if frame.keys.get(key) is Some(_) {
            return Err("subagent audit JSON contains a duplicate object key")
          }
          frame.keys[key] = true
        } else {
          nodes += 1
          if nodes > NATIVE_SUBAGENT_AUDIT_MAX_NODES {
            return Err("subagent audit JSON exceeds the node limit")
          }
        }
      }
    } else if byte == b'"' {
      in_string = true
      string_start = index
    } else if byte == b'{' || byte == b'[' {
      depth += 1
      if depth > NATIVE_SUBAGENT_AUDIT_MAX_DEPTH {
        return Err("subagent audit JSON exceeds the nesting limit")
      }
      nodes += 1
      if nodes > NATIVE_SUBAGENT_AUDIT_MAX_NODES {
        return Err("subagent audit JSON exceeds the node limit")
      }
      frames.push({ is_object: byte == b'{', keys: Map([]), })
    } else if byte == b'}' || byte == b']' {
      depth -= 1
      if depth < 0 {
        return Err("subagent audit JSON is malformed")
      }
      if frames.length() > 0 {
        ignore(frames.pop())
      }
    } else if byte == b't' ||
      byte == b'f' ||
      byte == b'n' ||
      byte == b'-' ||
      (byte >= b'0' && byte <= b'9') {
      nodes += 1
      if nodes > NATIVE_SUBAGENT_AUDIT_MAX_NODES {
        return Err("subagent audit JSON exceeds the node limit")
      }
      index += 1
      while index < source.length() &&
            source[index] != b' ' &&
            source[index] != b'\n' &&
            source[index] != b'\r' &&
            source[index] != b'\t' &&
            source[index] != b',' &&
            source[index] != b']' &&
            source[index] != b'}' &&
            source[index] != b':' &&
            source[index] != b'[' &&
            source[index] != b'{' &&
            source[index] != b'"' {
        index += 1
      }
      continue
    }
    index += 1
  }
  Ok(())
}

///|
fn native_subagent_audit_exact_fields(
  fields : Map[String, Json],
  expected : Array[String],
  description : String,
) -> Result[Unit, String] {
  if fields.length() != expected.length() {
    return Err(
      "subagent audit " + description + " has missing or unknown fields",
    )
  }
  for name in expected {
    if fields.get(name) is None {
      return Err("subagent audit " + description + " is missing " + name)
    }
  }
  Ok(())
}

///|
fn native_subagent_audit_required_string(
  fields : Map[String, Json],
  name : String,
  maximum_bytes : Int32,
) -> Result[String, String] {
  match fields.get(name) {
    Some(Json::String(value)) if !value.is_empty() &&
      @utf8.encode(value).length() <= maximum_bytes => Ok(value)
    _ => Err("subagent audit " + name + " is invalid")
  }
}

///|
fn native_subagent_audit_required_int(
  fields : Map[String, Json],
  name : String,
  minimum : Int32,
  maximum : Int32,
) -> Result[Int32, String] {
  match fields.get(name) {
    Some(Json::Number(number, ..)) if !number.is_nan() &&
      !number.is_inf() &&
      number >= minimum.to_double() &&
      number <= maximum.to_double() &&
      number.to_int().to_double() == number => Ok(number.to_int())
    _ => Err("subagent audit " + name + " is invalid")
  }
}

///|
fn native_subagent_audit_child_tools() -> Array[Json] {
  @plugins.builtin_tools().filter(tool => {
    let name = string_field(tool, "name").unwrap_or("")
    ["read", "glob", "grep"].contains(name)
  })
}

///|
/// Validate a full terminal child Engine snapshot in a throwaway pure Engine.
/// Restore validates the event log but performs no provider, tool, or hook I/O.
fn native_subagent_audit_validate_engine_snapshot(
  snapshot : Json,
  child_id : String,
  child_status : String,
) -> Result[Unit, String] {
  let fields = match snapshot {
    Json::Object(fields) => fields
    _ => return Err("subagent audit engine_snapshot must be an object")
  }
  match
    native_subagent_audit_exact_fields(
      fields,
      ["schema", "next_session", "next_effect", "sessions"],
      "engine snapshot",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if string_field(snapshot, "schema") != Some("dsh.mbt-session-v1") {
    return Err("subagent audit engine snapshot schema is unsupported")
  }
  match
    native_subagent_audit_required_int(fields, "next_session", 1, 1000000000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    native_subagent_audit_required_int(fields, "next_effect", 1, 1000000000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let sessions = match fields.get("sessions") {
    Some(Json::Array(values)) if values.length() == 1 => values
    _ => return Err("subagent audit must contain exactly one child session")
  }
  let session = sessions[0]
  if string_field(session, "id") != Some(child_id) ||
    string_field(session, "status") != Some(child_status) {
    return Err("subagent audit child identity or status does not match")
  }
  let turn_id = match object_field(session, "turn_id") {
    Some(Json::Number(number, ..)) if number >= 1.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ => return Err("subagent audit child turn is invalid")
  }
  let events = match object_field(session, "events") {
    Some(Json::Array(values)) if values.length() > 0 && values.length() <= 32768 =>
      values
    _ => return Err("subagent audit child event log is invalid")
  }
  let mut terminal_reason : String? = None
  let mut terminal_count = 0
  for event in events {
    if string_field(event, "type") == Some("session/interrupted") ||
      string_field(event, "type") == Some("session/cancelled") {
      return Err("subagent audit child log contains an interruption")
    }
    if string_field(event, "type") == Some("turn/end") &&
      object_field(event, "turn_id") == Some(Json::number(turn_id.to_double())) {
      terminal_count += 1
      terminal_reason = string_field(
        object_field(event, "data").unwrap_or(Json::null()),
        "reason",
      )
    }
  }
  if terminal_count != 1 {
    return Err("subagent audit child has no unique terminal turn")
  }
  match (child_status, terminal_reason) {
    ("completed", Some("completed")) => ()
    (
      "failed",
      Some(
        "provider_error"
        | "max_steps"
        | "max_tokens"
        | "effect_limit"
        | "session_capacity"
        | "blocked"
      ),
    ) => ()
    _ => return Err("subagent audit child outcome is not settled")
  }
  let validator = @engine.Engine::new(native_subagent_audit_child_tools())
  match validator.restore(snapshot) {
    Ok(_) => ()
    Err(_) =>
      return Err("subagent audit child snapshot failed engine validation")
  }
  let restored = match
    validator.invoke("session_get", { "session_id": child_id }) {
    Ok(value) => value
    Err(_) =>
      return Err("subagent audit child snapshot failed engine validation")
  }
  if string_field(restored, "status") != Some(child_status) ||
    !validator.take_typed_effects().is_empty() {
    return Err(
      "subagent audit snapshot did not restore as inert terminal state",
    )
  }
  Ok(())
}

///|
/// Validate and detach a v1 child-audit envelope. Unknown fields are rejected
/// so a future writer cannot silently rely on fields an older reader ignores.
fn native_subagent_audit_validate_record(value : Json) -> Result[Json, String] {
  let budget : NativeSubagentAuditJsonBudget = {
    nodes: NATIVE_SUBAGENT_AUDIT_MAX_NODES,
    text_bytes: NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
  }
  let copied = match native_subagent_audit_copy_json(value, 0, budget) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fields = match copied {
    Json::Object(fields) => fields
    _ => return Err("subagent audit record must be an object")
  }
  match
    native_subagent_audit_exact_fields(
      fields,
      [
        "schema", "parent_session_id", "parent_turn_id", "parent_effect_id", "parent_tool_call_id",
        "child_id", "workspace_id", "child_status", "engine_snapshot",
      ],
      "record",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if string_field(copied, "schema") != Some(NATIVE_SUBAGENT_AUDIT_SCHEMA) {
    return Err("subagent audit record schema is unsupported")
  }
  let parent_session_id = match
    native_subagent_audit_required_string(fields, "parent_session_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if @engine.SessionId::new(parent_session_id) is Err(_) {
    return Err("subagent audit parent_session_id is invalid")
  }
  match
    native_subagent_audit_required_int(fields, "parent_turn_id", 1, 2147483647) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let parent_effect_id = match
    native_subagent_audit_required_string(fields, "parent_effect_id", 16) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if @engine.EffectId::new(parent_effect_id) is Err(_) ||
    parent_effect_id[7] == '0' {
    return Err("subagent audit parent_effect_id is invalid")
  }
  let parent_tool_call_id = match
    native_subagent_audit_required_string(fields, "parent_tool_call_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if @engine.ToolCallId::new(parent_tool_call_id) is Err(_) {
    return Err("subagent audit parent_tool_call_id is invalid")
  }
  let child_id = match
    native_subagent_audit_required_string(fields, "child_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !child_id.has_prefix("subagent-") ||
    @engine.SessionId::new(child_id) is Err(_) {
    return Err("subagent audit child_id is invalid")
  }
  let workspace_id = match
    native_subagent_audit_required_string(fields, "workspace_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if @engine.SessionId::new(workspace_id) is Err(_) {
    return Err("subagent audit workspace_id is invalid")
  }
  let child_status = match
    native_subagent_audit_required_string(fields, "child_status", 16) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if child_status != "completed" && child_status != "failed" {
    return Err("subagent audit child_status is not a known terminal outcome")
  }
  let snapshot = match fields.get("engine_snapshot") {
    Some(value) => value
    None => return Err("subagent audit engine_snapshot is missing")
  }
  match
    native_subagent_audit_validate_engine_snapshot(
      snapshot, child_id, child_status,
    ) {
    Ok(_) => Ok(copied)
    Err(error) => Err(error)
  }
}

///|
/// Encode a validated v1 child-audit record under a strict UTF-8 byte limit.
pub fn native_subagent_audit_encode(value : Json) -> Result[String, String] {
  let validated = match native_subagent_audit_validate_record(value) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let raw = validated.stringify()
  if @utf8.encode(raw).length() > NATIVE_SUBAGENT_AUDIT_MAX_BYTES {
    return Err("subagent audit record exceeds the byte limit")
  }
  Ok(raw)
}

///|
/// Decode a bounded v1 child-audit record without exposing an execution path.
pub fn native_subagent_audit_decode(raw : String) -> Result[Json, String] {
  let bytes = @utf8.encode(raw)
  if bytes.length() > NATIVE_SUBAGENT_AUDIT_MAX_BYTES {
    return Err("subagent audit record exceeds the byte limit")
  }
  match native_subagent_audit_validate_nesting(bytes) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("subagent audit record is malformed JSON")
  }
  native_subagent_audit_validate_record(parsed)
}
