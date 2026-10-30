///|
/// A content-free pointer to one native immutable tool-result archive object.
/// The engine checks that the pointer describes the exact event/pruning
/// candidate. The native host must verify the object bytes before committing
/// or restoring it.
pub struct ToolResultArchiveRef {
  priv value : Json
  priv session_id : String
  priv call_id : String
  priv effect_id : String
  priv call_seq : Int32
  priv request_seq : Int32
  priv completed_seq : Int32
  priv result_seq : Int32
  priv pruned_seq : Int32
  priv content_bytes : Int32
  priv chars_before : Int32
  priv pruned_bytes : Int32
  priv chars_after : Int32
  priv threshold_chars : Int32
  priv head_chars : Int32
  priv tail_chars : Int32
  priv object_id : String
}

///|
/// Per-object proof supplied by the native verifier to the v2 restore path.
/// The constructor validates lengths and pruning semantics; callers remain
/// responsible for verifying the persisted object bytes and digests first.
pub struct ToolResultArchiveSource {
  priv reference : ToolResultArchiveRef
  priv content : String
  priv pruned_content : String
  priv encoded_object : String
}

///|
priv struct NativeArchiveJsonBudget {
  mut nodes : Int32
  mut chars : Int32
}

///|

///|
/// A separate 7 MiB expansion ceiling leaves room for compact snapshot fields
/// and the ordinary JSON copy budget. Hydration expands each original into
/// completion, result, and transcript content; candidate, commit, and restore
/// all apply this same bound before accepting or materializing that history.
const NATIVE_ARCHIVE_MAX_HYDRATION_EXPANSION : Int32 = 7340032

///|
fn native_archive_check_copy_budget(
  value : Json,
  depth : Int32,
  budget : NativeArchiveJsonBudget,
) -> Unit raise EngineError {
  budget.nodes -= 1
  if depth > 64 || budget.nodes < 0 {
    raise Invalid("JSON exceeds the depth or node limit")
  }
  match value {
    Json::Object(entries) =>
      for key, entry in entries {
        budget.chars -= key.length()
        if budget.chars < 0 {
          raise Invalid("JSON exceeds the text limit after archive hydration")
        }
        native_archive_check_copy_budget(entry, depth + 1, budget)
      }
    Json::Array(entries) =>
      for entry in entries {
        native_archive_check_copy_budget(entry, depth + 1, budget)
      }
    Json::String(text) => {
      budget.chars -= text.length()
      if budget.chars < 0 {
        raise Invalid("JSON exceeds the text limit after archive hydration")
      }
    }
    _ => ()
  }
}

///|
pub fn ToolResultArchiveSource::from_object_text(
  reference : ToolResultArchiveRef,
  encoded_object : String,
) -> Result[ToolResultArchiveSource, String] {
  try {
    match native_archive_verify_object_text(reference, encoded_object) {
      Err(error) => Err(error)
      Ok((content, pruned_content)) =>
        Ok({ reference, content, pruned_content, encoded_object, })
    }
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
fn native_archive_source_set_within_limits(
  sources : Array[ToolResultArchiveSource],
) -> Result[Unit, String] {
  if sources.length() > 256 {
    return Err("Archive manifest exceeds the 256 object limit")
  }
  let mut original_bytes = 0
  let mut projection_bytes = 0
  for source in sources {
    if source.content.length() > 65536 ||
      source.pruned_content.length() > 65536 ||
      source.encoded_object.length() > 1048576 {
      return Err("Archive source exceeds its per-object bound")
    }
    original_bytes += source.reference.content_bytes
    projection_bytes += source.reference.pruned_bytes
    if original_bytes > 16777216 || projection_bytes > 16777216 {
      return Err("Archive sources exceed the 16 MiB aggregate object limit")
    }
  }
  Ok(())
}

///|
/// Check the limits from refs alone before a candidate can be committed. This
/// keeps the live archive population reopenable even though the engine does
/// not retain native object bytes.
fn native_archive_snapshot_sources_within_limits(
  snapshot : Json,
) -> Unit raise EngineError {
  let refs = array_value(
    required_field(snapshot, "archives"),
    "archive manifest",
    256,
  )
  if refs.length() > 256 {
    raise Invalid("Archive manifest exceeds the 256 object limit")
  }
  let seen : Map[String, Bool] = Map([])
  let mut original_bytes = 0
  let mut projection_bytes = 0
  let mut hydration_expansion = 0
  for raw_ref in refs {
    let reference = match ToolResultArchiveRef::from_json(raw_ref) {
      Ok(value) => value
      Err(error) => raise Invalid(error)
    }
    if seen.get(reference.object_id) is Some(_) {
      raise Invalid("Archive manifest contains a duplicate object id")
    }
    seen[reference.object_id] = true
    original_bytes += reference.content_bytes
    projection_bytes += reference.pruned_bytes
    hydration_expansion += Int32::max(
        reference.content_bytes - reference.pruned_bytes,
        0,
      ) *
      3
    if original_bytes > 16777216 || projection_bytes > 16777216 {
      raise Invalid(
        "Archive manifest exceeds the 16 MiB aggregate object limit",
      )
    }
    if hydration_expansion > NATIVE_ARCHIVE_MAX_HYDRATION_EXPANSION {
      raise Invalid(
        "Archive manifest exceeds the bounded restore hydration budget",
      )
    }
    // Canonical JSON escaping expands each control byte by at most six bytes.
    // The source and projection each have a 64 KiB bound, so even this
    // conservative encoded-size estimate remains below the 1 MiB object cap.
    let encoded_upper_bound = (reference.content_bytes + reference.pruned_bytes) *
      6 +
      8192
    if encoded_upper_bound > 1048576 {
      raise Invalid("Archive object exceeds its encoded 1 MiB bound")
    }
  }
  native_archive_check_copy_budget(snapshot, 0, {
    nodes: 1000000,
    chars: 16777216 - hydration_expansion,
  })
}

///|

///|
pub fn ToolResultArchiveSource::reference(
  self : ToolResultArchiveSource,
) -> ToolResultArchiveRef {
  self.reference
}

///|
pub fn ToolResultArchiveSource::content(
  self : ToolResultArchiveSource,
) -> String {
  self.content
}

///|
pub fn ToolResultArchiveSource::pruned_content(
  self : ToolResultArchiveSource,
) -> String {
  self.pruned_content
}

///|
fn tool_result_archive_ref_fields() -> Array[String] {
  [
    "schema", "format_version", "session_id", "call_id", "effect_id", "call_seq",
    "request_seq", "completed_seq", "result_seq", "pruned_seq", "content_bytes",
    "chars_before", "content_sha256", "pruned_bytes", "chars_after", "pruned_sha256",
    "threshold_chars", "head_chars", "tail_chars", "object_id",
  ]
}

///|
fn tool_result_archive_valid_digest(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for character in value {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return false
    }
  }
  true
}

///|
fn native_archive_quote(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for character in value {
    match character {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\b' => output.write_string("\\b")
      '\t' => output.write_string("\\t")
      '\n' => output.write_string("\\n")
      '\f' => output.write_string("\\f")
      '\r' => output.write_string("\\r")
      _ if character.to_int() < 0x20 =>
        output.write_string(
          "\\u00" +
          archive_sha256_hex_nibble(character.to_int() >> 4).to_string() +
          archive_sha256_hex_nibble(character.to_int()).to_string(),
        )
      _ => output.write_char(character)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
/// Limit the JSON parser's recursive depth before allocating a parsed tree.
fn native_archive_json_depth_is_bounded(raw : String) -> Bool {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for character in raw {
    if in_string {
      if escaped {
        escaped = false
      } else if character == '\\' {
        escaped = true
      } else if character == '"' {
        in_string = false
      }
      continue
    }
    if character == '"' {
      in_string = true
    } else if character == '{' || character == '[' {
      depth += 1
      if depth > 4 {
        return false
      }
    } else if character == '}' || character == ']' {
      depth -= 1
      if depth < 0 {
        return false
      }
    }
  }
  depth == 0 && !in_string
}

///|
fn native_archive_object_encode(
  reference : ToolResultArchiveRef,
  content : String,
  pruned_content : String,
  content_sha256 : String,
  pruned_sha256 : String,
  include_object_id : Bool,
) -> String {
  let output = StringBuilder()
  output.write_string("{")
  output.write_string("\"schema\":\"dsh.tool-result-archive-object-v2\"")
  output.write_string(",\"format_version\":2")
  output.write_string(
    ",\"session_id\":" + native_archive_quote(reference.session_id),
  )
  output.write_string(",\"call_id\":" + native_archive_quote(reference.call_id))
  output.write_string(
    ",\"effect_id\":" + native_archive_quote(reference.effect_id),
  )
  output.write_string(",\"call_seq\":" + reference.call_seq.to_string())
  output.write_string(",\"request_seq\":" + reference.request_seq.to_string())
  output.write_string(
    ",\"completed_seq\":" + reference.completed_seq.to_string(),
  )
  output.write_string(",\"result_seq\":" + reference.result_seq.to_string())
  output.write_string(",\"pruned_seq\":" + reference.pruned_seq.to_string())
  output.write_string(",\"content\":" + native_archive_quote(content))
  output.write_string(
    ",\"content_bytes\":" + reference.content_bytes.to_string(),
  )
  output.write_string(",\"chars_before\":" + reference.chars_before.to_string())
  output.write_string(
    ",\"content_sha256\":" + native_archive_quote(content_sha256),
  )
  output.write_string(
    ",\"pruned_content\":" + native_archive_quote(pruned_content),
  )
  output.write_string(",\"pruned_bytes\":" + reference.pruned_bytes.to_string())
  output.write_string(",\"chars_after\":" + reference.chars_after.to_string())
  output.write_string(
    ",\"pruned_sha256\":" + native_archive_quote(pruned_sha256),
  )
  output.write_string(
    ",\"threshold_chars\":" + reference.threshold_chars.to_string(),
  )
  output.write_string(",\"head_chars\":" + reference.head_chars.to_string())
  output.write_string(",\"tail_chars\":" + reference.tail_chars.to_string())
  if include_object_id {
    output.write_string(
      ",\"object_id\":" + native_archive_quote(reference.object_id),
    )
  }
  output.write_char('}')
  output.to_string()
}

///|
fn native_archive_verify_object_text(
  reference : ToolResultArchiveRef,
  raw : String,
) -> Result[(String, String), String] raise EngineError {
  if raw.length() > 1048576 || @utf8.encode(raw).length() > 1048576 {
    return Err("Archive object exceeds its 1 MiB byte limit")
  }
  if !native_archive_json_depth_is_bounded(raw) {
    return Err("Archive object exceeds its JSON nesting limit")
  }
  let value = @json.parse(raw) catch {
    _ => return Err("Archive object JSON is malformed")
  }
  let object_fields = match value {
    Json::Object(data) => data
    _ => return Err("Archive object must be an object")
  }
  let allowed = [
    "schema", "format_version", "session_id", "call_id", "effect_id", "call_seq",
    "request_seq", "completed_seq", "result_seq", "pruned_seq", "content", "content_bytes",
    "chars_before", "content_sha256", "pruned_content", "pruned_bytes", "chars_after",
    "pruned_sha256", "threshold_chars", "head_chars", "tail_chars", "object_id",
  ]
  if object_fields.length() != allowed.length() {
    return Err("Archive object has missing or unknown fields")
  }
  for key, _ in object_fields {
    if !allowed.contains(key) {
      return Err("Archive object has missing or unknown fields")
    }
  }
  let schema = match object_fields.get("schema") {
    Some(Json::String(value)) => value
    _ => return Err("Archive object schema is missing")
  }
  if schema != "dsh.tool-result-archive-object-v2" {
    return Err("Archive object schema is unsupported")
  }
  let format_version = match object_fields.get("format_version") {
    Some(Json::Number(value, ..)) if value == 2.0 => 2
    _ => return Err("Archive object format version is invalid")
  }
  ignore(format_version)
  let content = match object_fields.get("content") {
    Some(Json::String(value)) if value.length() <= 65536 => value
    _ => return Err("Archive object source is invalid")
  }
  let pruned_content = match object_fields.get("pruned_content") {
    Some(Json::String(value)) if value.length() <= 65536 => value
    _ => return Err("Archive object projection is invalid")
  }
  let metadata_value = Json::object(object_fields.copy())
  let session_id = required_string(metadata_value, "session_id", max=128)
  let call_id = required_string(metadata_value, "call_id", max=128)
  let effect_id = required_string(metadata_value, "effect_id", max=128)
  let object_id = required_string(metadata_value, "object_id", max=64)
  let content_sha256 = required_string(metadata_value, "content_sha256", max=64)
  let pruned_sha256 = required_string(metadata_value, "pruned_sha256", max=64)
  let sequence_fields = [
    ("call_seq", reference.call_seq),
    ("request_seq", reference.request_seq),
    ("completed_seq", reference.completed_seq),
    ("result_seq", reference.result_seq),
    ("pruned_seq", reference.pruned_seq),
    ("content_bytes", reference.content_bytes),
    ("chars_before", reference.chars_before),
    ("pruned_bytes", reference.pruned_bytes),
    ("chars_after", reference.chars_after),
    ("threshold_chars", reference.threshold_chars),
    ("head_chars", reference.head_chars),
    ("tail_chars", reference.tail_chars),
  ]
  if session_id != reference.session_id ||
    call_id != reference.call_id ||
    effect_id != reference.effect_id ||
    object_id != reference.object_id ||
    @utf8.encode(content).length() != reference.content_bytes ||
    content[:].char_length() != reference.chars_before ||
    @utf8.encode(pruned_content).length() != reference.pruned_bytes ||
    pruned_content[:].char_length() != reference.chars_after {
    return Err(
      "Archive object identity or content lengths differ from its reference",
    )
  }
  for (name, expected) in sequence_fields {
    match object_fields.get(name) {
      Some(Json::Number(value, ..)) if value == expected.to_double() => ()
      _ => return Err("Archive object metadata differs from its reference")
    }
  }
  if !tool_result_archive_valid_digest(content_sha256) ||
    !tool_result_archive_valid_digest(pruned_sha256) ||
    content_sha256 != required_string(reference.value, "content_sha256", max=64) ||
    pruned_sha256 != required_string(reference.value, "pruned_sha256", max=64) {
    return Err("Archive object digest metadata differs from its reference")
  }
  let actual_content_sha256 = archive_sha256(content)
  let actual_pruned_sha256 = archive_sha256(pruned_content)
  if actual_content_sha256 != content_sha256 ||
    actual_pruned_sha256 != pruned_sha256 {
    return Err("Archive object content digest does not match its metadata")
  }
  let payload = native_archive_object_encode(
    reference, content, pruned_content, content_sha256, pruned_sha256, false,
  )
  if archive_sha256(payload) != reference.object_id {
    return Err("Archive object id does not match its encoded payload")
  }
  if native_archive_object_encode(
      reference, content, pruned_content, content_sha256, pruned_sha256, true,
    ) !=
    raw {
    return Err("Archive object encoding is not canonical for v2")
  }
  let config = match
    ToolResultPruneConfig::new(
      reference.threshold_chars,
      reference.head_chars,
      reference.tail_chars,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if prune_text(content, config) != Some(pruned_content) {
    return Err("Archive object projection differs from its pruning policy")
  }
  Ok((content, pruned_content))
}

///|
/// Parse the exact structural v2 reference shape. This does not prove object
/// existence or integrity; those checks belong to the native storage boundary.
pub fn ToolResultArchiveRef::from_json(
  value : Json,
) -> Result[ToolResultArchiveRef, String] {
  try {
    let data = fields(value)
    let allowed = tool_result_archive_ref_fields()
    if data.length() != allowed.length() {
      raise Invalid("Archive reference has missing or unknown fields")
    }
    for key, _ in data {
      if !allowed.contains(key) {
        raise Invalid("Archive reference has missing or unknown fields")
      }
    }
    if required_string(value, "schema", max=64) !=
      "dsh.tool-result-archive-reference-v2" ||
      int_value(required_field(value, "format_version"), "format_version", 2, 2) !=
      2 {
      raise Invalid("Archive reference schema or version is unsupported")
    }
    let session_id = identifier(
      required_string(value, "session_id", max=128),
      "session id",
    )
    let call_id = identifier(
      required_string(value, "call_id", max=128),
      "tool call id",
    )
    let effect_id = required_string(value, "effect_id", max=128)
    match EffectId::new(effect_id) {
      Ok(_) => ()
      Err(_) => raise Invalid("Archive reference effect id is invalid")
    }
    let call_seq = int_value(
      required_field(value, "call_seq"),
      "call_seq",
      0,
      32767,
    )
    let request_seq = int_value(
      required_field(value, "request_seq"),
      "request_seq",
      0,
      32767,
    )
    let completed_seq = int_value(
      required_field(value, "completed_seq"),
      "completed_seq",
      0,
      32767,
    )
    let result_seq = int_value(
      required_field(value, "result_seq"),
      "result_seq",
      0,
      32767,
    )
    let pruned_seq = int_value(
      required_field(value, "pruned_seq"),
      "pruned_seq",
      0,
      32767,
    )
    if call_seq >= request_seq ||
      request_seq >= completed_seq ||
      completed_seq >= result_seq ||
      result_seq >= pruned_seq {
      raise Invalid("Archive reference event order is invalid")
    }
    let content_bytes = int_value(
      required_field(value, "content_bytes"),
      "content_bytes",
      1,
      65536,
    )
    let chars_before = int_value(
      required_field(value, "chars_before"),
      "chars_before",
      1,
      262144,
    )
    let content_sha256 = required_string(value, "content_sha256", max=64)
    let pruned_bytes = int_value(
      required_field(value, "pruned_bytes"),
      "pruned_bytes",
      1,
      65536,
    )
    let chars_after = int_value(
      required_field(value, "chars_after"),
      "chars_after",
      1,
      262144,
    )
    let pruned_sha256 = required_string(value, "pruned_sha256", max=64)
    let threshold_chars = int_value(
      required_field(value, "threshold_chars"),
      "threshold_chars",
      1,
      262144,
    )
    let head_chars = int_value(
      required_field(value, "head_chars"),
      "head_chars",
      0,
      262144,
    )
    let tail_chars = int_value(
      required_field(value, "tail_chars"),
      "tail_chars",
      0,
      262144,
    )
    let object_id = required_string(value, "object_id", max=64)
    let marker_chars = PRUNE_MARKER[:].char_length()
    if chars_before > content_bytes ||
      chars_after > pruned_bytes ||
      chars_after >= chars_before ||
      !tool_result_archive_valid_digest(content_sha256) ||
      !tool_result_archive_valid_digest(pruned_sha256) ||
      !tool_result_archive_valid_digest(object_id) ||
      head_chars + marker_chars + tail_chars > threshold_chars {
      raise Invalid("Archive reference lengths, digests, or policy are invalid")
    }
    Ok({
      value: detached(value),
      session_id,
      call_id,
      effect_id,
      call_seq,
      request_seq,
      completed_seq,
      result_seq,
      pruned_seq,
      content_bytes,
      chars_before,
      pruned_bytes,
      chars_after,
      threshold_chars,
      head_chars,
      tail_chars,
      object_id,
    })
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
pub fn ToolResultArchiveRef::json(self : ToolResultArchiveRef) -> Json {
  detached(self.value)
}

///|
pub fn ToolResultArchiveRef::object_id(self : ToolResultArchiveRef) -> String {
  self.object_id
}

///|
fn archive_plan_equal(
  left : ToolResultArchivePlan,
  right : ToolResultArchivePlan,
) -> Bool {
  left.session_id == right.session_id &&
  left.call_id == right.call_id &&
  left.effect_id == right.effect_id &&
  left.call_seq == right.call_seq &&
  left.request_seq == right.request_seq &&
  left.completed_seq == right.completed_seq &&
  left.result_seq == right.result_seq &&
  left.pruned_seq == right.pruned_seq &&
  left.chars_before == right.chars_before &&
  left.chars_after == right.chars_after
}

///|
fn archive_ref_matches_plan(
  reference : ToolResultArchiveRef,
  plan : ToolResultArchivePlan,
  content : String,
  pruned_content : String,
  config : ToolResultPruneConfig,
) -> Bool {
  reference.session_id == plan.session_id.as_string() &&
  reference.call_id == plan.call_id.as_string() &&
  reference.effect_id == plan.effect_id.as_string() &&
  reference.call_seq == plan.call_seq &&
  reference.request_seq == plan.request_seq &&
  reference.completed_seq == plan.completed_seq &&
  reference.result_seq == plan.result_seq &&
  reference.pruned_seq == plan.pruned_seq &&
  reference.content_bytes == @utf8.encode(content).length() &&
  reference.chars_before == content[:].char_length() &&
  reference.pruned_bytes == @utf8.encode(pruned_content).length() &&
  reference.chars_after == pruned_content[:].char_length() &&
  reference.threshold_chars == config.threshold_chars &&
  reference.head_chars == config.head_chars &&
  reference.tail_chars == config.tail_chars
}

///|
fn replace_archive_event_content(
  events : Array[Json],
  sequence : Int32,
  kind : String,
  projection : String,
  reference : ToolResultArchiveRef,
) -> Array[Json] raise EngineError {
  if sequence < 0 || sequence >= events.length() {
    raise Invalid("Archive event sequence is outside the candidate history")
  }
  let result : Array[Json] = []
  for index, event in events {
    if index != sequence {
      result.push(detached(event))
      continue
    }
    if required_string(event, "type", max=64) != kind ||
      int_value(required_field(event, "seq"), "seq", 0, 32767) != sequence {
      raise Invalid("Archive event type or sequence differs from its reference")
    }
    let event_fields = fields(event).copy()
    let data = fields(required_field(event, "data")).copy()
    data.set("content", Json::string(projection))
    data.set("archive_ref", reference.json())
    event_fields.set("data", Json::object(data))
    result.push(Json::object(event_fields))
  }
  result
}

///|
fn native_archive_restore_event(value : Json) -> Event raise EngineError {
  {
    seq: int_value(required_field(value, "seq"), "event seq", 0, 32767),
    kind: EngineEventKind::from_wire(required_string(value, "type", max=64)),
    turn_id: int_value(
      required_field(value, "turn_id"),
      "event turn_id",
      0,
      1000000,
    ),
    step: int_value(required_field(value, "step"), "event step", 0, 64),
    data: detached(required_field(value, "data")),
  }
}

///|
fn archive_candidate_snapshot(
  snapshot : Json,
  plan : ToolResultArchivePlan,
  reference : ToolResultArchiveRef,
  original_content : String,
  projection : String,
) -> Json raise EngineError {
  let root = fields(snapshot).copy()
  let schema = required_string(snapshot, "schema", max=64)
  if schema != "dsh.mbt-session-v1" && schema != "dsh.mbt-session-v2" {
    raise Invalid("Archive candidate snapshot schema is unsupported")
  }
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let updated_sessions : Array[Json] = []
  let mut found_session = false
  for session_value in sessions {
    if required_string(session_value, "id", max=128) !=
      plan.session_id.as_string() {
      updated_sessions.push(detached(session_value))
      continue
    }
    if found_session {
      raise Invalid("Archive candidate snapshot duplicates its session")
    }
    found_session = true
    let session = fields(session_value).copy()
    let messages = native_archive_replace_message_content(
      array_value(
        required_field(session_value, "messages"),
        "session messages",
        32768,
      ),
      plan.call_id.as_string(),
      original_content,
      projection,
      None,
      Some(reference.json()),
    )
    session.set("messages", Json::array(messages))
    let events = array_value(
      required_field(session_value, "events"),
      "session events",
      32768,
    )
    let with_completion = replace_archive_event_content(
      events,
      plan.completed_seq,
      "tool/completed",
      projection,
      reference,
    )
    let with_result = replace_archive_event_content(
      with_completion,
      plan.result_seq,
      "tool/result",
      projection,
      reference,
    )
    session.set("events", Json::array(with_result))
    updated_sessions.push(Json::object(session))
  }
  if !found_session {
    raise Invalid("Archive candidate session is missing from the snapshot")
  }
  root.set("schema", Json::string("dsh.mbt-session-v2"))
  root.set("sessions", Json::array(updated_sessions))
  let provisional = Json::object(root)
  root.set("archives", native_archive_manifest_from_snapshot(provisional))
  let candidate = Json::object(root)
  native_archive_snapshot_sources_within_limits(candidate)
  candidate
}

///|
/// A snapshot's messages are the legacy transcript view, so compact the same
/// tool row as the two event records. Requiring a unique exact match prevents
/// a candidate from leaving the original result in its older reader surface.
fn native_archive_replace_message_content(
  messages : Array[Json],
  call_id : String,
  expected_content : String,
  replacement_content : String,
  expected_archive_ref : Json?,
  replacement_archive_ref : Json?,
) -> Array[Json] raise EngineError {
  let result : Array[Json] = []
  let mut matches = 0
  for message in messages {
    let data = fields(message)
    if data.get("role") == Some(Json::string("tool")) &&
      data.get("tool_call_id") == Some(Json::string(call_id)) {
      if required_string(message, "content") != expected_content {
        raise Invalid("Archive message disagrees with its event projection")
      }
      if data.get("archive_ref") != expected_archive_ref {
        raise Invalid(
          "Archive message reference disagrees with its event history",
        )
      }
      matches += 1
      let compacted = data.copy()
      compacted.set("content", Json::string(replacement_content))
      match replacement_archive_ref {
        Some(value) => compacted.set("archive_ref", detached(value))
        None => ignore(compacted.remove("archive_ref"))
      }
      result.push(Json::object(compacted))
    } else {
      result.push(detached(message))
    }
  }
  if matches != 1 {
    raise Invalid("Archive candidate has no unique transcript tool result")
  }
  result
}

///|
fn native_archive_manifest_from_snapshot(
  snapshot : Json,
) -> Json raise EngineError {
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let references : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  for session in sessions {
    for
      event in array_value(
        required_field(session, "events"),
        "session events",
        32768,
      ) {
      let kind = required_string(event, "type", max=64)
      if kind != "tool/completed" && kind != "tool/result" {
        continue
      }
      match fields(required_field(event, "data")).get("archive_ref") {
        None => ()
        Some(value) => {
          let reference = match ToolResultArchiveRef::from_json(value) {
            Ok(value) => value
            Err(error) => raise Invalid(error)
          }
          if kind == "tool/completed" && seen.get(reference.object_id) is None {
            seen[reference.object_id] = true
            references.push(reference.json())
          }
        }
      }
    }
  }
  Json::array(references)
}

///|
fn native_archive_snapshot_has_markers(snapshot : Json) -> Bool {
  let root = match snapshot {
    Json::Object(root) => root
    _ => return false
  }
  if root.get("archives") is Some(_) {
    return true
  }
  let sessions = match root.get("sessions") {
    Some(Json::Array(values)) => values
    _ => return false
  }
  for session in sessions {
    let session_fields = match session {
      Json::Object(fields) => fields
      _ => continue
    }
    if session_fields.get("source_format") ==
      Some(Json::string("deepseek-session-v4")) {
      continue
    }
    match session_fields.get("events") {
      Some(Json::Array(events)) =>
        for event in events {
          let event_fields = match event {
            Json::Object(fields) => fields
            _ => continue
          }
          let kind = match event_fields.get("type") {
            Some(Json::String(kind)) => kind
            _ => continue
          }
          if kind != "tool/completed" && kind != "tool/result" {
            continue
          }
          match event_fields.get("data") {
            Some(Json::Object(data)) if data.get("archive_ref") is Some(_) =>
              return true
            _ => ()
          }
        }
      _ => ()
    }
    match session_fields.get("messages") {
      Some(Json::Array(messages)) =>
        for message in messages {
          match message {
            Json::Object(data) =>
              if data.get("role") == Some(Json::string("tool")) &&
                data.get("archive_ref") is Some(_) {
                return true
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  false
}

///|
fn session_has_archived_tool_results(session : Session) -> Bool {
  for event in session.events {
    if event.kind != EngineEventKind::ToolCompleted {
      continue
    }
    match event.data {
      Json::Object(data) if data.get("archive_ref") is Some(_) => return true
      _ => ()
    }
  }
  false
}

///|
fn session_tool_result_is_archived(
  session : Session,
  result_seq : Int32,
) -> Bool {
  if result_seq < 0 || result_seq >= session.events.length() {
    return false
  }
  let event = session.events[result_seq]
  if event.kind != EngineEventKind::ToolResult {
    return false
  }
  match event.data {
    Json::Object(data) => data.get("archive_ref") is Some(_)
    _ => false
  }
}

///|

///|
fn native_archive_event(
  events : Array[Json],
  sequence : Int32,
  kind : String,
) -> Json raise EngineError {
  if sequence < 0 || sequence >= events.length() {
    raise Invalid("Archive reference sequence is outside the session history")
  }
  let event = events[sequence]
  if int_value(required_field(event, "seq"), "event seq", 0, 32767) != sequence ||
    required_string(event, "type", max=64) != kind {
    raise Invalid("Archive reference points to the wrong event")
  }
  event
}

///|
fn native_archive_event_data(
  event : Json,
) -> Map[String, Json] raise EngineError {
  fields(required_field(event, "data"))
}

///|
fn native_archive_map_required(
  data : Map[String, Json],
  name : String,
) -> Json raise EngineError {
  match data.get(name) {
    Some(value) => value
    None => raise Invalid("Archive event is missing " + name)
  }
}

///|
fn native_archive_map_string(
  data : Map[String, Json],
  name : String,
  max~ : Int32 = 65536,
) -> String raise EngineError {
  string_value(native_archive_map_required(data, name), name, max~)
}

///|
fn native_archive_map_int(
  data : Map[String, Json],
  name : String,
  minimum : Int32,
  maximum : Int32,
) -> Int32 raise EngineError {
  int_value(native_archive_map_required(data, name), name, minimum, maximum)
}

///|
fn native_archive_remove_ref(
  event : Json,
  content : String,
) -> Json raise EngineError {
  let event_fields = fields(event).copy()
  let data = fields(required_field(event, "data")).copy()
  ignore(data.remove("archive_ref"))
  data.set("content", Json::string(content))
  event_fields.set("data", Json::object(data))
  Json::object(event_fields)
}

///|
fn native_archive_hydrate_session(
  session : Json,
  sources : Array[ToolResultArchiveSource],
) -> Json raise EngineError {
  let session_id = required_string(session, "id", max=128)
  let session_fields = fields(session).copy()
  let raw_events = array_value(
    required_field(session, "events"),
    "session events",
    32768,
  )
  let events = raw_events.copy()
  let mut messages = array_value(
    required_field(session, "messages"),
    "session messages",
    32768,
  ).copy()
  for source in sources {
    let reference = source.reference
    if reference.session_id != session_id {
      continue
    }
    let completion = native_archive_event(
      events,
      reference.completed_seq,
      "tool/completed",
    )
    let result = native_archive_event(
      events,
      reference.result_seq,
      "tool/result",
    )
    let call = native_archive_event(events, reference.call_seq, "tool/call")
    let request = native_archive_event(
      events,
      reference.request_seq,
      "tool/request",
    )
    let prune = native_archive_event(
      events,
      reference.pruned_seq,
      "tool/result/pruned",
    )
    let completion_data = native_archive_event_data(completion)
    let result_data = native_archive_event_data(result)
    let call_data = native_archive_event_data(call)
    let request_data = native_archive_event_data(request)
    let prune_data = native_archive_event_data(prune)
    let ref_json = reference.json()
    let projection = source.pruned_content
    let completion_content = match completion_data.get("content") {
      Some(value) => string_value(value, "completion content")
      None => raise Invalid("Archived completion has no content")
    }
    let result_content = match result_data.get("content") {
      Some(value) => string_value(value, "result content")
      None => raise Invalid("Archived result has no content")
    }
    let call_identity = match call_data.get("id") {
      Some(value) => string_value(value, "call id", max=128)
      None => raise Invalid("Archived call has no id")
    }
    let request_call_id = match request_data.get("call_id") {
      Some(value) => string_value(value, "request call id", max=128)
      None => raise Invalid("Archived request has no call id")
    }
    let request_effect_id = match request_data.get("effect_id") {
      Some(value) => string_value(value, "request effect id", max=128)
      None => raise Invalid("Archived request has no effect id")
    }
    let completion_call_id = match completion_data.get("call_id") {
      Some(value) => string_value(value, "completion call id", max=128)
      None => raise Invalid("Archived completion has no call id")
    }
    let completion_effect_id = match completion_data.get("effect_id") {
      Some(value) => string_value(value, "completion effect id", max=128)
      None => raise Invalid("Archived completion has no effect id")
    }
    let result_call_id = match result_data.get("tool_call_id") {
      Some(value) => string_value(value, "result call id", max=128)
      None => raise Invalid("Archived result has no call id")
    }
    if completion_data.get("archive_ref") != Some(ref_json) ||
      result_data.get("archive_ref") != Some(ref_json) ||
      required_string(completion, "type", max=64) != "tool/completed" ||
      required_string(result, "type", max=64) != "tool/result" ||
      completion_content != projection ||
      result_content != projection ||
      call_identity != reference.call_id ||
      request_call_id != reference.call_id ||
      request_effect_id != reference.effect_id ||
      completion_call_id != reference.call_id ||
      completion_effect_id != reference.effect_id ||
      result_call_id != reference.call_id ||
      native_archive_map_int(prune_data, "source_seq", 0, 32767) !=
      reference.result_seq ||
      native_archive_map_int(prune_data, "result_seq", 0, 32767) !=
      reference.result_seq ||
      native_archive_map_string(prune_data, "call_id", max=128) !=
      reference.call_id ||
      native_archive_map_string(prune_data, "content") != projection ||
      native_archive_map_int(prune_data, "threshold_chars", 1, 262144) !=
      reference.threshold_chars ||
      native_archive_map_int(prune_data, "head_chars", 0, 262144) !=
      reference.head_chars ||
      native_archive_map_int(prune_data, "tail_chars", 0, 262144) !=
      reference.tail_chars ||
      native_archive_map_int(prune_data, "chars_before", 0, 262144) !=
      reference.chars_before ||
      native_archive_map_int(prune_data, "chars_after", 0, 262144) !=
      reference.chars_after {
      raise Invalid("Archive object proof disagrees with its v2 event history")
    }
    events[reference.completed_seq] = native_archive_remove_ref(
      completion,
      source.content,
    )
    events[reference.result_seq] = native_archive_remove_ref(
      result,
      source.content,
    )
    messages = native_archive_replace_message_content(
      messages,
      reference.call_id,
      projection,
      source.content,
      Some(reference.json()),
      None,
    )
  }
  session_fields.set("events", Json::array(events))
  session_fields.set("messages", Json::array(messages))
  Json::object(session_fields)
}

///|
fn native_archive_hydrated_snapshot(
  snapshot : Json,
  sources : Array[ToolResultArchiveSource],
) -> Json raise EngineError {
  if required_string(snapshot, "schema", max=64) != "dsh.mbt-session-v2" {
    raise Invalid("Archived restore requires a v2 engine snapshot")
  }
  let root = fields(snapshot).copy()
  native_archive_snapshot_sources_within_limits(snapshot)
  let refs = array_value(
    required_field(snapshot, "archives"),
    "archive manifest",
    256,
  )
  if refs.length() != sources.length() {
    raise Invalid("Archive object set differs from the engine manifest")
  }
  let seen : Map[String, Bool] = Map([])
  let sources_by_object : Map[String, ToolResultArchiveSource] = Map([])
  for source in sources {
    let object_id = source.reference.object_id
    if sources_by_object.get(object_id) is Some(_) {
      raise Invalid("Archive object proof set contains a duplicate object")
    }
    sources_by_object[object_id] = source
  }
  for raw_ref in refs {
    let reference = match ToolResultArchiveRef::from_json(raw_ref) {
      Ok(value) => value
      Err(error) => raise Invalid(error)
    }
    if seen.get(reference.object_id) is Some(_) {
      raise Invalid("Engine archive manifest contains a duplicate object")
    }
    seen[reference.object_id] = true
    match sources_by_object.get(reference.object_id) {
      Some(source) if source.reference.json() == reference.json() => ()
      _ =>
        raise Invalid("Archive object proof does not match the engine manifest")
    }
  }
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let session_ids : Map[String, Bool] = Map([])
  for session in sessions {
    let session_id = required_string(session, "id", max=128)
    if session_ids.get(session_id) is Some(_) {
      raise Invalid("Archive snapshot contains a duplicate session id")
    }
    session_ids[session_id] = true
  }
  for source in sources {
    if session_ids.get(source.reference.session_id) is None {
      raise Invalid("Archive manifest references a missing session")
    }
    for session in sessions {
      let session_id = required_string(session, "id", max=128)
      if session_id == source.reference.session_id &&
        (
          fields(session).get("source_format") ==
          Some(Json::string("deepseek-session-v4")) ||
          fields(session).get("parent_session_id") is Some(_)
        ) {
        raise Invalid(
          "Imported or fork-related sessions cannot contain archives",
        )
      }
      if session_id != source.reference.session_id &&
        fields(session).get("parent_session_id") ==
        Some(Json::string(source.reference.session_id)) {
        raise Invalid("Fork-related sessions cannot contain archives")
      }
    }
  }
  let hydrated_sessions = sessions.map(session => {
    native_archive_hydrate_session(session, sources)
  })
  root.set("schema", Json::string("dsh.mbt-session-v1"))
  ignore(root.remove("archives"))
  root.set("sessions", Json::array(hydrated_sessions))
  let hydrated = Json::object(root)
  if native_archive_snapshot_has_markers(hydrated) {
    raise Invalid("V2 snapshot contains archive markers outside its manifest")
  }
  hydrated
}

///|
fn native_archive_compact_session(
  session : Session,
  sources : Array[ToolResultArchiveSource],
) -> Unit raise EngineError {
  for source in sources {
    let reference = source.reference
    if reference.session_id != session.id {
      continue
    }
    let events = session.events.map(Event::json)
    let with_completion = replace_archive_event_content(
      events,
      reference.completed_seq,
      "tool/completed",
      source.pruned_content,
      reference,
    )
    let with_result = replace_archive_event_content(
      with_completion,
      reference.result_seq,
      "tool/result",
      source.pruned_content,
      reference,
    )
    for index, event in with_result {
      session.events[index] = native_archive_restore_event(event)
    }
  }
}

///|
/// Restore a v2 native history only after the storage boundary has verified
/// every referenced object. The exact original text is replayed transiently,
/// then replaced by its validated projection before capacity admission.
pub fn Engine::restore_archived(
  self : Engine,
  snapshot : Json,
  sources : Array[ToolResultArchiveSource],
) -> Result[Unit, String] {
  try {
    if sources.is_empty() {
      raise Invalid("Archived restore has no verified object sources")
    }
    match native_archive_source_set_within_limits(sources) {
      Ok(_) => ()
      Err(error) => raise Invalid(error)
    }
    let hydrated = native_archive_hydrated_snapshot(snapshot, sources)
    self.restore_impl(
      hydrated,
      archive_sources=sources,
      allow_archive_overflow=true,
    )
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Derive a compact v2 snapshot without mutating the authoritative engine.
/// The caller must publish the referenced object and checkpoint this candidate
/// before committing the same reference into the live engine.
pub fn Engine::tool_result_archive_candidate(
  self : Engine,
  plan : ToolResultArchivePlan,
  source : ToolResultArchiveSource,
) -> Result[Json, String] {
  self.tool_result_archives_candidate([plan], [source])
}

///|
/// Build one compact archive snapshot for a batch of independently verified
/// Read results. Applying all replacements to one snapshot lets the native
/// host admit the final compact history even when no individual replacement
/// would make an over-capacity intermediate history fit.
pub fn Engine::tool_result_archives_candidate(
  self : Engine,
  plans : Array[ToolResultArchivePlan],
  sources : Array[ToolResultArchiveSource],
) -> Result[Json, String] {
  try {
    if plans.length() != sources.length() || plans.length() > 256 {
      raise Invalid("Archive batch has an invalid item count")
    }
    if plans.is_empty() {
      return Ok(self.snapshot())
    }
    let seen : Map[String, Bool] = Map([])
    let mut compact = self.snapshot()
    for index, plan in plans {
      let source = sources[index]
      let key = plan.session_id.as_string() + "\n" + plan.result_seq.to_string()
      if seen.get(key) is Some(_) {
        raise Invalid("Archive batch contains a duplicate result")
      }
      seen[key] = true
      let current = match
        self.plan_tool_result_archive(plan.session_id, plan.result_seq) {
        Ok(value) => value
        Err(error) => raise Invalid(error)
      }
      if !archive_plan_equal(plan, current) {
        raise Invalid(
          "Archive plan is stale or belongs to another engine state",
        )
      }
      let session = self.lookup(plan.session_id.as_string())
      let result = session.events[plan.result_seq]
      let (content, _) = archive_regular_result(
        result,
        plan.call_id.as_string(),
      )
      let prune = session.events[plan.pruned_seq]
      let projection = required_string(prune.data, "content")
      let config = prune_config_from_event(prune.data)
      if content != source.content ||
        projection != source.pruned_content ||
        prune_text(content, config) != Some(projection) ||
        !archive_ref_matches_plan(
          source.reference,
          plan,
          content,
          projection,
          config,
        ) {
        raise Invalid(
          "Archive reference does not match the verified pruning candidate",
        )
      }
      compact = archive_candidate_snapshot(
        compact,
        plan,
        source.reference,
        content,
        projection,
      )
    }
    native_archive_snapshot_sources_within_limits(compact)
    Ok(compact)
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Apply a previously published archive only to a candidate session value.
/// NativeRuntime calls this after its v2 manifest compare-and-swap succeeds.
pub fn Engine::commit_tool_result_archive(
  self : Engine,
  plan : ToolResultArchivePlan,
  source : ToolResultArchiveSource,
) -> Result[Unit, String] {
  self.commit_tool_result_archives([plan], [source])
}

///|
/// Apply a previously published archive batch to one candidate engine. The
/// combined candidate is checked for session capacity only after every object
/// has compacted its corresponding original.
pub fn Engine::commit_tool_result_archives(
  self : Engine,
  plans : Array[ToolResultArchivePlan],
  sources : Array[ToolResultArchiveSource],
) -> Result[Unit, String] {
  if plans.is_empty() && sources.is_empty() {
    return Ok(())
  }
  try {
    let staged = match self.tool_result_archives_candidate(plans, sources) {
      Ok(value) => value
      Err(error) => raise Invalid(error)
    }
    let candidate = self.copy_state()
    for index, plan in plans {
      let source = sources[index]
      let session = candidate.lookup(plan.session_id.as_string())
      let result = session.events[plan.result_seq]
      let (content, _) = archive_regular_result(
        result,
        plan.call_id.as_string(),
      )
      let prune = session.events[plan.pruned_seq]
      let projection = required_string(prune.data, "content")
      let config = prune_config_from_event(prune.data)
      if content != source.content ||
        projection != source.pruned_content ||
        prune_text(content, config) != Some(projection) ||
        !archive_ref_matches_plan(
          source.reference,
          plan,
          content,
          projection,
          config,
        ) {
        raise Invalid(
          "Archive reference does not match the verified pruning candidate",
        )
      }
      let events = session.events.map(Event::json)
      let with_completion = replace_archive_event_content(
        events,
        plan.completed_seq,
        "tool/completed",
        projection,
        source.reference,
      )
      let with_result = replace_archive_event_content(
        with_completion,
        plan.result_seq,
        "tool/result",
        projection,
        source.reference,
      )
      for event_index, event in with_result {
        session.events[event_index] = native_archive_restore_event(event)
      }
    }
    if !candidate.within_capacity() {
      raise Invalid("Archived session still exceeds its capacity limit")
    }
    let compact = candidate.snapshot()
    native_archive_snapshot_sources_within_limits(compact)
    if compact != staged {
      raise Invalid(
        "Committed archive batch differs from its admitted snapshot",
      )
    }
    self.adopt(candidate)
    Ok(())
  } catch {
    Invalid(message) => Err(message)
  }
}
