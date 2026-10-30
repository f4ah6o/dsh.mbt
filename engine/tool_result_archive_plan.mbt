///|
/// A read-only observation of one original tool result and its direct pruning
/// projection. This plan carries no result text and is not authorization to
/// persist anything. The plan contains no event-count or freshness revision,
/// so it cannot prove by itself that no state changed after it was made. A
/// later storage operation must rederive eligibility inside its mutation gate;
/// if it requires same-revision freshness, it must separately validate a
/// revision token there.
pub struct ToolResultArchivePlan {
  priv session_id : SessionId
  priv call_id : ToolCallId
  priv effect_id : EffectId
  priv call_seq : Int32
  priv request_seq : Int32
  priv completed_seq : Int32
  priv result_seq : Int32
  priv pruned_seq : Int32
  priv chars_before : Int32
  priv chars_after : Int32
}

///|
pub fn ToolResultArchivePlan::session_id(
  self : ToolResultArchivePlan,
) -> SessionId {
  self.session_id
}

///|
pub fn ToolResultArchivePlan::call_id(
  self : ToolResultArchivePlan,
) -> ToolCallId {
  self.call_id
}

///|
pub fn ToolResultArchivePlan::effect_id(
  self : ToolResultArchivePlan,
) -> EffectId {
  self.effect_id
}

///|
pub fn ToolResultArchivePlan::call_sequence(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.call_seq
}

///|
pub fn ToolResultArchivePlan::request_sequence(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.request_seq
}

///|
pub fn ToolResultArchivePlan::completed_sequence(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.completed_seq
}

///|
pub fn ToolResultArchivePlan::result_sequence(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.result_seq
}

///|
pub fn ToolResultArchivePlan::pruned_sequence(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.pruned_seq
}

///|
pub fn ToolResultArchivePlan::chars_before(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.chars_before
}

///|
pub fn ToolResultArchivePlan::chars_after(
  self : ToolResultArchivePlan,
) -> Int32 {
  self.chars_after
}

///|
fn event_field_string(
  event : Event,
  key : String,
  max~ : Int32 = SESSION_CAPACITY,
) -> String raise EngineError {
  required_string(event.data, key, max~)
}

///|
fn archive_call_id(event : Event) -> String raise EngineError {
  match event.kind {
    EngineEventKind::ToolCall => event_field_string(event, "id", max=128)
    EngineEventKind::ToolRequest
    | EngineEventKind::ToolCompleted
    | EngineEventKind::ToolResult =>
      event_field_string(
        event,
        if event.kind == EngineEventKind::ToolResult {
          "tool_call_id"
        } else {
          "call_id"
        },
        max=128,
      )
    _ => raise Invalid("Event does not carry a regular tool call identity")
  }
}

///|
fn archive_effect_id(event : Event) -> String raise EngineError {
  required_string(event.data, "effect_id", max=128)
}

///|
fn archive_object_has_only_fields(
  value : Json,
  allowed : Array[String],
) -> Bool raise EngineError {
  for key, _ in fields(value) {
    if !allowed.contains(key) {
      return false
    }
  }
  true
}

///|
fn archive_string_property_schema(value : Json) -> Bool raise EngineError {
  if !archive_object_has_only_fields(value, ["type", "description"]) ||
    required_string(value, "type", max=16) != "string" {
    return false
  }
  match fields(value).get("description") {
    None | Some(Json::String(_)) => true
    _ => false
  }
}

///|
fn archive_positive_integer_property_schema(
  value : Json,
) -> Bool raise EngineError {
  if !archive_object_has_only_fields(value, ["type", "minimum", "description"]) ||
    required_string(value, "type", max=16) != "integer" {
    return false
  }
  match fields(value).get("minimum") {
    Some(Json::Number(number, ..)) if number == 1.0 => ()
    _ => return false
  }
  match fields(value).get("description") {
    None | Some(Json::String(_)) => true
    _ => false
  }
}

///|
fn archive_regular_read_schema(tool : Tool) -> Bool raise EngineError {
  if tool.name != "read" ||
    tool.effect != Read ||
    !archive_object_has_only_fields(tool.input_schema, [
      "type", "required", "properties", "additionalProperties",
    ]) ||
    required_string(tool.input_schema, "type", max=16) != "object" ||
    fields(tool.input_schema).get("additionalProperties") !=
    Some(Json::boolean(false)) {
    return false
  }
  let required = match required_field(tool.input_schema, "required") {
    Json::Array(values) => values
    _ => return false
  }
  if required != [Json::string("file_path")] {
    return false
  }
  let properties = fields(required_field(tool.input_schema, "properties"))
  if properties.get("file_path") is None {
    return false
  }
  for name, schema in properties {
    let valid = match name {
      "file_path" => archive_string_property_schema(schema)
      "offset" | "limit" => archive_positive_integer_property_schema(schema)
      _ => false
    }
    if !valid {
      return false
    }
  }
  true
}

///|
fn archive_read_tool_call(
  engine : Engine,
  event : Event,
  expected_call_id : String,
) -> (String, String) raise EngineError {
  if event.kind != EngineEventKind::ToolCall ||
    fields(event.data).length() != 3 ||
    archive_call_id(event) != expected_call_id {
    raise Invalid("Archive candidate has an ambiguous tool call event")
  }
  let name = required_string(event.data, "name", max=128)
  let arguments = required_string(event.data, "arguments")
  let tool = match engine.find_tool(name) {
    Some(tool) if archive_regular_read_schema(tool) => tool
    _ =>
      raise Invalid("Archive candidate is not the configured regular read tool")
  }
  let parsed_arguments = parse_arguments(arguments)
  validate_arguments(tool.input_schema, parsed_arguments)
  (name, arguments)
}

///|
fn archive_regular_result(
  event : Event,
  call_id : String,
) -> (String, Bool) raise EngineError {
  if event.kind != EngineEventKind::ToolResult ||
    fields(event.data).length() != 4 ||
    archive_call_id(event) != call_id ||
    required_string(event.data, "role", max=16) != "tool" {
    raise Invalid("Archive candidate result has an unsupported shape")
  }
  (
    required_string(event.data, "content"),
    bool_value(required_field(event.data, "is_error"), "is_error"),
  )
}

///|
fn archive_effect_completion(
  event : Event,
  call_id : String,
  effect_id : String,
  content : String,
  is_error : Bool,
) -> Unit raise EngineError {
  let data_fields = fields(event.data)
  for key, _ in data_fields {
    if ![
        "source", "call_id", "effect_id", "content", "is_error", "additional_contexts",
        "additional_contexts_source_kind", "post_tool_prompt_hook", "subagent_post_tool_prompt_hook",
      ].contains(key) {
      raise Invalid("Archive candidate completion has unknown provenance")
    }
  }
  if event.kind != EngineEventKind::ToolCompleted ||
    archive_call_id(event) != call_id ||
    required_string(event.data, "source", max=16) != "effect" ||
    archive_effect_id(event) != effect_id ||
    required_string(event.data, "content") != content ||
    bool_value(required_field(event.data, "is_error"), "is_error") != is_error {
    raise Invalid("Archive candidate completion does not match its result")
  }
}

///|
fn Engine::session_has_unsettled_archive_state(
  self : Engine,
  session : Session,
) -> Bool {
  if session.imported ||
    (session.status != Idle && session.status != Completed) ||
    session.open_step ||
    session.active_effect is Some(_) ||
    session.active_kind is Some(_) ||
    session.active_tool_effect_count() > 0 ||
    session.approval is Some(_) ||
    session.pending_retry_id is Some(_) ||
    !session.calls.is_empty() ||
    session.cursor != 0 ||
    session.schedule_cursor != 0 ||
    session.parallel_group ||
    !native_hook_pending_invocations(session).is_empty() ||
    session.stop_hook_pending ||
    session.stop_hook_event_seq is Some(_) ||
    session.stop_continuation_text is Some(_) ||
    !session.stop_continuation_hook_contexts.is_empty() ||
    session.stop_continuation_admitted ||
    !session.pending_hook_contexts.is_empty() ||
    session.subagent_prompt_hook_active ||
    session.subagent_prompt_hook_initial ||
    !session.subagent_prompt_hook_contexts.is_empty() ||
    session.subagent_prompt_hook_prompt is Some(_) ||
    !session.pending_subagent_post_tool_contexts.is_empty() ||
    !session.pending_subagent_post_tool_messages.is_empty() ||
    !session.subagent_prompt_hook_start_contexts.is_empty() ||
    !session.subagent_prompt_hook_post_tool_messages.is_empty() ||
    session.post_tool_prompt_hook_active ||
    session.post_tool_prompt_hook_event_seq is Some(_) ||
    !session.post_tool_prompt_hook_contexts.is_empty() ||
    !session.post_tool_prompt_hook_messages.is_empty() {
    return true
  }
  for _, effect in self.effects {
    if effect.session_id == session.id {
      return true
    }
  }
  false
}

///|
fn Engine::session_is_fork_related(self : Engine, session : Session) -> Bool {
  if session.fork_source is Some(_) {
    return true
  }
  for _, other in self.sessions {
    if other.id == session.id {
      continue
    }
    match other.fork_source {
      Some(source) if source.parent_session_id == session.id => return true
      _ => ()
    }
  }
  false
}

///|
/// Return false for a well-formed result that the native archive format does
/// not support. A regular Read candidate is checked strictly here; malformed
/// call/result identity or invalid Read arguments are errors, not a silent
/// fallback to inline storage.
pub fn Engine::tool_result_archive_supported(
  self : Engine,
  session_id : SessionId,
  result_seq : Int32,
) -> Result[Bool, String] {
  try {
    let session = self.lookup(session_id.as_string())
    if session.imported ||
      self.session_is_fork_related(session) ||
      session.events.any(event => {
        event.kind == EngineEventKind::CompactionSummary
      }) {
      return Ok(false)
    }
    if session.status == Failed || session.status == Cancelled {
      // The standalone archive planner deliberately supports only Idle and
      // Completed sessions. Keep the existing send-time projection behavior
      // on terminal failures while retaining their originals inline.
      return Ok(false)
    }
    if self.session_has_unsettled_archive_state(session) {
      raise Invalid("Archive planning requires a settled closed session")
    }
    if result_seq < 0 || result_seq >= session.events.length() {
      raise Invalid("Archive result sequence is outside the session history")
    }
    let result = session.events[result_seq]
    if result.seq != result_seq || result.kind != EngineEventKind::ToolResult {
      raise Invalid("Archive candidate is not an original tool result")
    }
    if session_tool_result_is_archived(session, result_seq) {
      return Ok(false)
    }
    let mut matching_prunes = 0
    let mut has_direct_prune = false
    for event in session.events {
      if event.kind == EngineEventKind::ToolResultPruned &&
        fields(event.data).get("result_seq") == Some(integer(result_seq)) {
        matching_prunes += 1
        has_direct_prune = has_direct_prune ||
          fields(event.data).get("source_seq") == Some(integer(result_seq))
      }
    }
    if matching_prunes != 1 || !has_direct_prune {
      // The archive-v2 object binds a single direct projection. The engine
      // still supports historical direct→tighter projection chains; leave
      // those valid results inline instead of rejecting their next send.
      return Ok(false)
    }
    let call_id = required_string(result.data, "tool_call_id", max=128)
    match ToolCallId::new(call_id) {
      Ok(_) => ()
      Err(_) => raise Invalid("Archive candidate call identity is invalid")
    }
    let calls : Array[Event] = []
    for event in session.events {
      if event.kind == EngineEventKind::ToolCall {
        match event.data {
          Json::Object(data) if data.get("id") == Some(Json::string(call_id)) =>
            calls.push(event)
          _ => ()
        }
      }
    }
    if calls.length() != 1 {
      raise Invalid(
        "Archive candidate has missing or duplicate call provenance",
      )
    }
    let call = calls[0]
    if fields(call.data).length() != 3 || archive_call_id(call) != call_id {
      raise Invalid("Archive candidate has an ambiguous tool call event")
    }
    let name = required_string(call.data, "name", max=128)
    let tool = match self.find_tool(name) {
      Some(value) => value
      None => return Ok(false)
    }
    if name != "read" ||
      tool.effect != Read ||
      !archive_regular_read_schema(tool) {
      return Ok(false)
    }
    let arguments = required_string(call.data, "arguments")
    validate_arguments(tool.input_schema, parse_arguments(arguments))
    ignore(archive_regular_result(result, call_id))
    Ok(true)
  } catch {
    Invalid(message) => Err(message)
  }
}

///|

///|
/// Derive source provenance either for a new archive command or for a
/// reference already tied to a historical direct prune. The historical mode
/// deliberately ignores the session's current status because later turns may
/// be active, but it still validates the exact original tool/effect/result.
fn Engine::plan_tool_result_archive_impl(
  self : Engine,
  session_id : SessionId,
  result_seq : Int32,
  historical_pruned_seq : Int32?,
) -> Result[ToolResultArchivePlan, String] {
  try {
    match self.config_error {
      Some(_) =>
        raise Invalid("Archive planning requires valid tool configuration")
      None => ()
    }
    let session = self.lookup(session_id.as_string())
    if historical_pruned_seq is None &&
      self.session_has_unsettled_archive_state(session) {
      raise Invalid("Archive planning requires a settled closed session")
    }
    if session.imported {
      raise Invalid("Imported histories cannot be archive planned")
    }
    if self.session_is_fork_related(session) {
      raise Invalid("Fork-related sessions cannot be archive planned")
    }
    if session.events.any(event => {
        event.kind == EngineEventKind::CompactionSummary
      }) {
      raise Invalid(
        "Sessions with compaction summaries cannot archive tool results",
      )
    }
    if session_tool_result_is_archived(session, result_seq) {
      raise Invalid("Archive planning cannot reuse an already archived result")
    }
    if result_seq < 0 || result_seq >= session.events.length() {
      raise Invalid("Archive result sequence is outside the session history")
    }
    let result = session.events[result_seq]
    if result.seq != result_seq || result.kind != EngineEventKind::ToolResult {
      raise Invalid("Archive candidate is not an original tool result")
    }
    let call_id = required_string(result.data, "tool_call_id", max=128)
    match ToolCallId::new(call_id) {
      Ok(_) => ()
      Err(_) => raise Invalid("Archive candidate call identity is invalid")
    }
    let (result_content, result_is_error) = archive_regular_result(
      result, call_id,
    )

    let calls : Array[Event] = []
    let requests : Array[Event] = []
    let completions : Array[Event] = []
    let results : Array[Event] = []
    let prunings : Array[Event] = []
    for event in session.events {
      match event.kind {
        EngineEventKind::ToolCall if archive_call_id(event) == call_id =>
          calls.push(event)
        EngineEventKind::ToolRequest if archive_call_id(event) == call_id =>
          requests.push(event)
        EngineEventKind::ToolCompleted if archive_call_id(event) == call_id =>
          completions.push(event)
        EngineEventKind::ToolResult if archive_call_id(event) == call_id =>
          results.push(event)
        EngineEventKind::ToolResultPruned => {
          let candidate_result_seq = int_value(
            required_field(event.data, "result_seq"),
            "result_seq",
            0,
            SESSION_CAPACITY,
          )
          if candidate_result_seq == result_seq {
            match historical_pruned_seq {
              Some(sequence) if event.seq == sequence => prunings.push(event)
              Some(_) => ()
              None => prunings.push(event)
            }
          }
        }
        _ => ()
      }
    }
    if calls.length() != 1 ||
      requests.length() != 1 ||
      completions.length() != 1 ||
      results.length() != 1 ||
      prunings.length() != 1 ||
      results[0].seq != result_seq {
      raise Invalid("Archive candidate has missing or duplicate provenance")
    }
    let call_event = calls[0]
    let request_event = requests[0]
    let completed_event = completions[0]
    let prune_event = prunings[0]
    let (tool_name, _) = archive_read_tool_call(self, call_event, call_id)
    ignore(tool_name)
    let effect_id = archive_effect_id(request_event)
    match EffectId::new(effect_id) {
      Ok(_) => ()
      Err(_) => raise Invalid("Archive candidate effect identity is invalid")
    }
    if fields(request_event.data).length() != 2 ||
      required_string(request_event.data, "call_id", max=128) != call_id {
      raise Invalid("Archive candidate request has an unsupported shape")
    }
    if call_event.seq >= request_event.seq ||
      request_event.seq >= completed_event.seq ||
      completed_event.seq >= result.seq ||
      call_event.turn_id != request_event.turn_id ||
      call_event.step != request_event.step ||
      request_event.turn_id != completed_event.turn_id ||
      request_event.step != completed_event.step ||
      completed_event.turn_id != result.turn_id ||
      completed_event.step != result.step {
      raise Invalid("Archive candidate event order or coordinates are invalid")
    }
    archive_effect_completion(
      completed_event, call_id, effect_id, result_content, result_is_error,
    )

    let mut matching_effect_requests = 0
    let mut matching_effect_completions = 0
    for _, candidate_session in self.sessions {
      for event in candidate_session.events {
        if event.kind == EngineEventKind::ToolRequest &&
          archive_effect_id(event) == effect_id {
          matching_effect_requests += 1
        } else if event.kind == EngineEventKind::ToolCompleted &&
          fields(event.data).get("effect_id") == Some(Json::string(effect_id)) {
          matching_effect_completions += 1
        }
      }
    }
    if matching_effect_requests != 1 || matching_effect_completions != 1 {
      raise Invalid("Archive candidate effect identity is reused or ambiguous")
    }

    let prune_data = prune_event.data
    if required_string(prune_data, "call_id", max=128) != call_id ||
      int_value(
        required_field(prune_data, "source_seq"),
        "source_seq",
        0,
        SESSION_CAPACITY,
      ) !=
      result_seq ||
      prune_event.seq <= result.seq {
      raise Invalid("Archive candidate pruning is not a direct projection")
    }
    let config = prune_config_from_event(prune_data)
    let expected_pruned_content = match prune_text(result_content, config) {
      Some(content) => content
      None =>
        raise Invalid("Archive candidate result is within its prune threshold")
    }
    let recorded_pruned_content = string_value(
      required_field(prune_data, "content"),
      "pruned content",
      max=SESSION_CAPACITY,
    )
    let chars_before = int_value(
      required_field(prune_data, "chars_before"),
      "chars_before",
      0,
      SESSION_CAPACITY,
    )
    let chars_after = int_value(
      required_field(prune_data, "chars_after"),
      "chars_after",
      0,
      SESSION_CAPACITY,
    )
    if chars_before != code_point_length(result_content) ||
      recorded_pruned_content != expected_pruned_content ||
      chars_after != code_point_length(expected_pruned_content) ||
      chars_after >= chars_before ||
      chars_after > config.threshold_chars {
      raise Invalid("Archive candidate pruning lengths are invalid")
    }
    Ok({
      session_id,
      call_id: ToolCallId::from_validated(call_id),
      effect_id: EffectId::from_validated(effect_id),
      call_seq: call_event.seq,
      request_seq: request_event.seq,
      completed_seq: completed_event.seq,
      result_seq,
      pruned_seq: prune_event.seq,
      chars_before,
      chars_after,
    })
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Derive a content-free archive eligibility plan for one already-pruned
/// regular Read result. This query only inspects validated in-memory state.
pub fn Engine::plan_tool_result_archive(
  self : Engine,
  session_id : SessionId,
  result_seq : Int32,
) -> Result[ToolResultArchivePlan, String] {
  self.plan_tool_result_archive_impl(session_id, result_seq, None)
}
