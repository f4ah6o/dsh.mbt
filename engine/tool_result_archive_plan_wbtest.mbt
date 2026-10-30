///|
fn archive_plan_fixture(content : String) -> (Engine, Int32) {
  let engine = completed_engine_with_tool_result(content)
  let threshold = code_point_length(PRUNE_MARKER) + 7
  ignore(
    success(
      engine.invoke(
        "session_prune_tool_results",
        pruning_input(threshold_chars=threshold, head_chars=4, tail_chars=3),
      ),
    ),
  )
  let session = match engine.sessions.get("test") {
    Some(session) => session
    None => abort("Archive fixture session is missing")
  }
  let mut result_seq = -1
  for event in session.events {
    if event.kind == EngineEventKind::ToolResult {
      result_seq = event.seq
    }
  }
  if result_seq < 0 {
    abort("Archive fixture tool result is missing")
  }
  (engine, result_seq)
}

///|
fn archive_tool_schema(
  name : String,
  extra_read_property~ : Bool = false,
) -> Json {
  let properties : Map[String, Json] = Map([])
  let required : Array[Json] = []
  match name {
    "read" | "mcp__fixture__read" => {
      properties["file_path"] = object([("type", Json::string("string"))])
      if name == "read" && extra_read_property {
        properties["command"] = object([("type", Json::string("string"))])
      }
      required.push(Json::string("file_path"))
    }
    "glob" | "grep" => {
      properties["pattern"] = object([("type", Json::string("string"))])
      properties["path"] = object([("type", Json::string("string"))])
      required.push(Json::string("pattern"))
    }
    "skill" => {
      properties["name"] = object([("type", Json::string("string"))])
      required.push(Json::string("name"))
    }
    "subagent" => {
      properties["description"] = object([("type", Json::string("string"))])
      properties["prompt"] = object([("type", Json::string("string"))])
      required.push(Json::string("description"))
      required.push(Json::string("prompt"))
    }
    _ => abort("Unexpected archive test tool name")
  }
  object([
    ("type", Json::string("object")),
    ("required", Json::array(required)),
    ("properties", Json::object(properties)),
    ("additionalProperties", Json::boolean(false)),
  ])
}

///|
fn archive_tool_arguments(name : String) -> String {
  match name {
    "glob" | "grep" => "{\"pattern\":\"needle\",\"path\":\"src\"}"
    "skill" => "{\"name\":\"guide\"}"
    "subagent" =>
      "{\"description\":\"Inspect files\",\"prompt\":\"Read one file\"}"
    _ => "{\"file_path\":\"large.txt\"}"
  }
}

///|
fn archive_builtin_read_schema() -> Json {
  object([
    ("type", Json::string("object")),
    ("required", Json::array([Json::string("file_path")])),
    (
      "properties",
      object([
        (
          "file_path",
          object([
            ("type", Json::string("string")),
            ("description", Json::string("Path within the selected workspace")),
          ]),
        ),
        (
          "offset",
          object([("type", Json::string("integer")), ("minimum", integer(1))]),
        ),
        (
          "limit",
          object([("type", Json::string("integer")), ("minimum", integer(1))]),
        ),
      ]),
    ),
    ("additionalProperties", Json::boolean(false)),
  ])
}

///|
fn archive_candidate_for_tool(name : String, schema : Json) -> (Engine, Int32) {
  let descriptor = object([
    ("name", Json::string(name)),
    ("description", Json::string("Archive planner test tool")),
    ("input_schema", schema),
    ("effect", Json::string("read")),
  ])
  let engine = Engine::new([descriptor])
  ignore(
    success(
      engine.invoke("session_create", object([("id", Json::string("test"))])),
    ),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string("test")),
          ("prompt", Json::string("Inspect the workspace")),
        ]),
      ),
    ),
  )
  let provider = engine.take_effects()
  let response = calls_response([
    ("archive-read-call", name, archive_tool_arguments(name)),
  ])
  ignore(success(engine.complete(id_of(provider[0]), response)))
  let read_effects = engine.take_effects()
  ignore(
    success(
      engine.complete(
        id_of(read_effects[0]),
        object([
          ("ok", Json::boolean(true)),
          ("content", Json::string("😀"[:].repeat(60).to_owned())),
        ]),
      ),
    ),
  )
  let followup = engine.take_effects()
  ignore(
    success(
      engine.complete(id_of(followup[0]), stop_response("Tool result recorded")),
    ),
  )
  ignore(
    success(
      engine.invoke(
        "session_prune_tool_results",
        pruning_input(
          threshold_chars=code_point_length(PRUNE_MARKER) + 7,
          head_chars=4,
          tail_chars=3,
        ),
      ),
    ),
  )
  let session = archive_test_session(engine)
  let result_seq = archive_event_sequence(session, EngineEventKind::ToolResult)
  (engine, result_seq)
}

///|
fn archive_test_session(engine : Engine) -> Session {
  match engine.sessions.get("test") {
    Some(session) => session
    None => abort("Archive fixture session is missing")
  }
}

///|
fn archive_event_sequence(session : Session, kind : EngineEventKind) -> Int32 {
  for event in session.events {
    if event.kind == kind {
      return event.seq
    }
  }
  abort("Archive fixture event is missing")
}

///|
fn archive_replace_event_field(
  session : Session,
  seq : Int32,
  key : String,
  value : Json,
) -> Unit {
  let event = session.events[seq]
  let data = match event.data {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive fixture event data is not an object")
  }
  data.set(key, value)
  session.events[seq] = {
    seq: event.seq,
    kind: event.kind,
    turn_id: event.turn_id,
    step: event.step,
    data: Json::object(data),
  }
}

///|
fn archive_legacy_result_snapshot(
  engine : Engine,
) -> (Json, Int32) raise EngineError {
  let snapshot = json_copy(engine.snapshot())
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let session = sessions[0]
  let old_events = array_value(
    required_field(session, "events"),
    "events",
    32768,
  )
  let new_events : Array[Json] = []
  let mut legacy_result_seq = -1
  for event in old_events {
    let kind = required_string(event, "type")
    if kind == "tool/completed" {
      continue
    }
    let seq = new_events.length()
    let event_fields = fields(event).copy()
    event_fields.set("seq", integer(seq))
    if kind == "tool/result" {
      legacy_result_seq = seq
    }
    if kind == "tool/result/pruned" {
      let data = fields(required_field(event, "data")).copy()
      data.set("source_seq", integer(legacy_result_seq))
      data.set("result_seq", integer(legacy_result_seq))
      event_fields.set("data", Json::object(data))
    }
    new_events.push(Json::object(event_fields))
  }
  fields(session).set("events", Json::array(new_events))
  if legacy_result_seq < 0 {
    abort("Legacy archive fixture result is missing")
  }
  (snapshot, legacy_result_seq)
}

///|
fn archive_effect_fingerprint(engine : Engine) -> Array[String] {
  let result : Array[String] = []
  for id, effect in engine.effects {
    let kind = match effect.kind {
      Llm => "llm"
      ToolExecution => "tool"
    }
    let call_id = effect.call_id.unwrap_or("")
    result.push(
      "\{id}/\{kind}/\{effect.session_id}/\{effect.turn_id}/\{effect.step}/\{call_id}/\{effect.request.stringify()}",
    )
  }
  result.sort()
  result
}

///|
fn archive_is_rejected_without_mutation(
  engine : Engine,
  session_id : String,
  result_seq : Int32,
) -> Bool {
  let before_snapshot = engine.snapshot()
  let before_effects = archive_effect_fingerprint(engine)
  let before_queue = engine.queued.copy()
  let before_next_effect = engine.next_effect
  let rejected = engine.plan_tool_result_archive(
      SessionId::from_validated(session_id),
      result_seq,
    )
    is Err(_)
  rejected &&
  engine.snapshot() == before_snapshot &&
  archive_effect_fingerprint(engine) == before_effects &&
  engine.queued == before_queue &&
  engine.next_effect == before_next_effect
}

///|
fn archive_is_rejected(engine : Engine, result_seq : Int32) -> Bool {
  archive_is_rejected_without_mutation(engine, "test", result_seq)
}

///|
fn archive_test_object_source(
  plan : ToolResultArchivePlan,
  content : String,
  projection : String,
  config : ToolResultPruneConfig,
  session_id~ : String = plan.session_id().as_string(),
) -> ToolResultArchiveSource {
  let reference_json = Json::object(
    Map::from_array([
      ("schema", Json::string("dsh.tool-result-archive-reference-v2")),
      ("format_version", integer(2)),
      ("session_id", Json::string(session_id)),
      ("call_id", Json::string(plan.call_id().as_string())),
      ("effect_id", Json::string(plan.effect_id().as_string())),
      ("call_seq", integer(plan.call_sequence())),
      ("request_seq", integer(plan.request_sequence())),
      ("completed_seq", integer(plan.completed_sequence())),
      ("result_seq", integer(plan.result_sequence())),
      ("pruned_seq", integer(plan.pruned_sequence())),
      ("content_bytes", integer(@utf8.encode(content).length())),
      ("chars_before", integer(content[:].char_length())),
      ("content_sha256", Json::string(archive_sha256(content))),
      ("pruned_bytes", integer(@utf8.encode(projection).length())),
      ("chars_after", integer(projection[:].char_length())),
      ("pruned_sha256", Json::string(archive_sha256(projection))),
      ("threshold_chars", integer(config.threshold_chars)),
      ("head_chars", integer(config.head_chars)),
      ("tail_chars", integer(config.tail_chars)),
      (
        "object_id",
        Json::string(
          "0000000000000000000000000000000000000000000000000000000000000000",
        ),
      ),
    ]),
  )
  let initial_reference = match
    ToolResultArchiveRef::from_json(reference_json) {
    Ok(value) => value
    Err(error) => abort("Archive test reference is invalid: " + error)
  }
  let content_sha = archive_sha256(content)
  let projection_sha = archive_sha256(projection)
  let payload = native_archive_object_encode(
    initial_reference, content, projection, content_sha, projection_sha, false,
  )
  let object_id = archive_sha256(payload)
  let final_fields = match reference_json {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive test reference is not an object")
  }
  final_fields.set("object_id", Json::string(object_id))
  let reference = match
    ToolResultArchiveRef::from_json(Json::object(final_fields)) {
    Ok(value) => value
    Err(error) => abort("Archive test reference is invalid: " + error)
  }
  let encoded = native_archive_object_encode(
    reference, content, projection, content_sha, projection_sha, true,
  )
  match ToolResultArchiveSource::from_object_text(reference, encoded) {
    Ok(source) => source
    Err(error) => abort("Archive test object is invalid: " + error)
  }
}

///|
fn archive_snapshot_with_message_ref(
  snapshot : Json,
  archive_ref : Json?,
) -> Json raise EngineError {
  let root = fields(snapshot).copy()
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  ).copy()
  for session_index, session in sessions {
    if required_string(session, "id", max=128) != "test" {
      continue
    }
    let session_fields = fields(session).copy()
    let messages = array_value(
      required_field(session, "messages"),
      "messages",
      32768,
    ).copy()
    for message_index, message in messages {
      if fields(message).get("role") != Some(Json::string("tool")) {
        continue
      }
      let message_fields = fields(message).copy()
      match archive_ref {
        Some(value) => message_fields.set("archive_ref", value)
        None => ignore(message_fields.remove("archive_ref"))
      }
      messages[message_index] = Json::object(message_fields)
    }
    session_fields.set("messages", Json::array(messages))
    sessions[session_index] = Json::object(session_fields)
  }
  root.set("sessions", Json::array(sessions))
  Json::object(root)
}

///|
fn archive_snapshot_with_extra_ref(
  snapshot : Json,
  reference : ToolResultArchiveRef,
) -> Json raise EngineError {
  let root = fields(snapshot).copy()
  let refs = array_value(
    required_field(snapshot, "archives"),
    "archive manifest",
    256,
  ).copy()
  refs.push(reference.json())
  root.set("archives", Json::array(refs))
  Json::object(root)
}

///|
fn archive_snapshot_as_v1(snapshot : Json) -> Json raise EngineError {
  let root = fields(snapshot).copy()
  root.set("schema", Json::string("dsh.mbt-session-v1"))
  ignore(root.remove("archives"))
  Json::object(root)
}

///|
fn archive_snapshot_with_unlisted_read_markers(
  snapshot : Json,
  call_id : String,
  reference : ToolResultArchiveRef,
) -> Json raise EngineError {
  let root = fields(snapshot).copy()
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  ).copy()
  let mut updated = false
  for session_index, session in sessions {
    if required_string(session, "id", max=128) != "test" {
      continue
    }
    let session_fields = fields(session).copy()
    let events = array_value(required_field(session, "events"), "events", 32768).copy()
    let mut marker_count = 0
    for event_index, event in events {
      let event_fields = fields(event).copy()
      let kind = required_string(event, "type", max=64)
      let data = fields(required_field(event, "data"))
      let is_target = (
          kind == "tool/completed" &&
          data.get("call_id") == Some(Json::string(call_id))
        ) ||
        (
          kind == "tool/result" &&
          data.get("tool_call_id") == Some(Json::string(call_id))
        )
      if is_target {
        let updated_data = data.copy()
        updated_data.set("archive_ref", reference.json())
        event_fields.set("data", Json::object(updated_data))
        events[event_index] = Json::object(event_fields)
        marker_count += 1
      }
    }
    if marker_count != 2 {
      abort("Unlisted archive fixture needs one completion/result pair")
    }
    session_fields.set("events", Json::array(events))
    sessions[session_index] = Json::object(session_fields)
    updated = true
  }
  if !updated {
    abort("Unlisted archive fixture session is missing")
  }
  root.set("sessions", Json::array(sessions))
  Json::object(root)
}

///|
fn archive_committed_fixture(
  content : String,
) -> (Engine, ToolResultArchivePlan, ToolResultArchiveSource) {
  let (engine, result_seq) = archive_plan_fixture(content)
  let plan = engine
    .plan_tool_result_archive(SessionId::from_validated("test"), result_seq)
    .unwrap()
  let prune = archive_test_session(engine).events[plan.pruned_sequence()]
  let projection = required_string(prune.data, "content") catch {
    Invalid(message) => abort("Archive fixture projection failed: " + message)
  }
  let config = prune_config_from_event(prune.data) catch {
    Invalid(message) => abort("Archive fixture policy failed: " + message)
  }
  let source = archive_test_object_source(plan, content, projection, config)
  match engine.commit_tool_result_archive(plan, source) {
    Ok(_) => ()
    Err(message) => abort("Archive fixture commit failed: " + message)
  }
  (engine, plan, source)
}

///|
test "archive planner returns only sequence metadata for a direct Unicode pruning" {
  let original = "😀"[:].repeat(60).to_owned()
  let (engine, result_seq) = archive_plan_fixture(original)
  let before_snapshot = engine.snapshot()
  let before_effects = engine.effects.length()
  let before_queue = engine.queued.copy()
  let before_next_effect = engine.next_effect
  let plan = match
    engine.plan_tool_result_archive(
      SessionId::from_validated("test"),
      result_seq,
    ) {
    Ok(plan) => plan
    Err(message) => abort("Expected eligible archive candidate: " + message)
  }
  let session = archive_test_session(engine)
  let expected_content = "😀"[:].repeat(4).to_owned() +
    PRUNE_MARKER +
    "😀"[:].repeat(3).to_owned()
  assert_eq(plan.session_id().as_string(), "test")
  assert_eq(plan.call_id().as_string(), "read-long")
  assert_eq(plan.effect_id().as_string(), "effect-2")
  assert_eq(
    plan.call_sequence(),
    archive_event_sequence(session, EngineEventKind::ToolCall),
  )
  assert_eq(
    plan.request_sequence(),
    archive_event_sequence(session, EngineEventKind::ToolRequest),
  )
  assert_eq(
    plan.completed_sequence(),
    archive_event_sequence(session, EngineEventKind::ToolCompleted),
  )
  assert_eq(plan.result_sequence(), result_seq)
  assert_eq(
    plan.pruned_sequence(),
    archive_event_sequence(session, EngineEventKind::ToolResultPruned),
  )
  assert_eq(plan.chars_before(), 60)
  assert_eq(plan.chars_after(), code_point_length(expected_content))
  assert_true(plan.chars_after() < plan.chars_before())
  assert_eq(engine.snapshot(), before_snapshot)
  assert_eq(engine.effects.length(), before_effects)
  assert_eq(engine.queued, before_queue)
  assert_eq(engine.next_effect, before_next_effect)
  assert_true(
    engine.invoke(
      "session_plan_tool_result_archive",
      object([
        ("session_id", Json::string("test")),
        ("result_seq", integer(result_seq)),
      ]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before_snapshot)

  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(before_snapshot), Ok(()))
  let reopened = match
    restored.plan_tool_result_archive(
      SessionId::from_validated("test"),
      result_seq,
    ) {
    Ok(plan) => plan
    Err(message) => abort("Expected reopened archive candidate: " + message)
  }
  assert_eq(reopened.call_id().as_string(), plan.call_id().as_string())
  assert_eq(reopened.effect_id().as_string(), plan.effect_id().as_string())
  assert_eq(reopened.result_sequence(), plan.result_sequence())
  assert_eq(reopened.pruned_sequence(), plan.pruned_sequence())
  assert_eq(restored.snapshot(), before_snapshot)
  assert_eq(restored.effects.length(), 0)
}

///|
test "archive candidate and commit keep one projection and restore rejects v1 interpretation" {
  let original = "😀"[:].repeat(60).to_owned()
  let (engine, result_seq) = archive_plan_fixture(original)
  let plan = engine
    .plan_tool_result_archive(SessionId::from_validated("test"), result_seq)
    .unwrap()
  let prune = archive_test_session(engine).events[plan.pruned_sequence()]
  let projection = required_string(prune.data, "content") catch {
    _ => abort("Archive prune event has no projection")
  }
  let config = prune_config_from_event(prune.data) catch {
    _ => abort("Archive prune event has no policy")
  }
  let source = archive_test_object_source(plan, original, projection, config)
  let before = engine.snapshot()
  let messages_before = archive_test_session(engine).model_messages()
  let candidate = engine.tool_result_archive_candidate(plan, source).unwrap()
  assert_eq(engine.snapshot(), before)
  assert_eq(required_string(candidate, "schema"), "dsh.mbt-session-v2")
  let candidate_session = match
    array_value(required_field(candidate, "sessions"), "sessions", 32).get(0) {
    Some(value) => value
    None => abort("Archive candidate has no session")
  }
  let candidate_messages = array_value(
    required_field(candidate_session, "messages"),
    "candidate messages",
    32768,
  )
  let mut archived_tool_message : Json? = None
  for message in candidate_messages {
    if fields(message).get("tool_call_id") ==
      Some(Json::string(plan.call_id().as_string())) {
      archived_tool_message = Some(message)
    }
  }
  let archived_tool_message = match archived_tool_message {
    Some(value) => value
    None => abort("Archive candidate message is missing")
  }
  assert_eq(required_string(archived_tool_message, "content"), projection)
  assert_eq(
    fields(archived_tool_message).get("archive_ref"),
    Some(source.reference().json()),
  )
  assert_true(
    fields(archive_test_session(engine).events[plan.result_sequence()].data).get(
      "archive_ref",
    )
    is None,
  )
  assert_eq(engine.commit_tool_result_archive(plan, source), Ok(()))
  assert_eq(engine.snapshot(), candidate)
  let compacted_messages = archive_test_session(engine).model_messages()
  assert_eq(compacted_messages, messages_before)
  assert_true(
    compacted_messages.all(message => {
      match message {
        Json::Object(data) => data.get("archive_ref") is None
        _ => false
      }
    }),
  )
  let old_reader = Engine::new(test_tools())
  assert_true(old_reader.restore(candidate) is Err(_))
  assert_true(
    Engine::new(test_tools()).restore(archive_snapshot_as_v1(candidate))
    is Err(_),
  )
  let missing_message_ref = archive_snapshot_with_message_ref(candidate, None)
  assert_true(
    Engine::new(test_tools()).restore_archived(missing_message_ref, [source])
    is Err(_),
  )
  let forged_message_ref_fields = fields(source.reference().json()).copy()
  forged_message_ref_fields.set(
    "object_id",
    Json::string(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
  )
  let forged_message_ref = archive_snapshot_with_message_ref(
    candidate,
    Some(Json::object(forged_message_ref_fields)),
  )
  assert_true(
    Engine::new(test_tools()).restore_archived(forged_message_ref, [source])
    is Err(_),
  )
  let extra_reference_source = archive_test_object_source(
    plan,
    original,
    projection,
    config,
    session_id="missing-session",
  )
  let missing_session_snapshot = archive_snapshot_with_extra_ref(
    candidate,
    extra_reference_source.reference(),
  )
  assert_true(
    Engine::new(test_tools()).restore_archived(missing_session_snapshot, [
      source, extra_reference_source,
    ])
    is Err(_),
  )
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore_archived(candidate, [source]), Ok(()))
  assert_eq(reopened.snapshot(), candidate)
  let reopened_messages = reopened.lookup("test").model_messages()
  assert_eq(reopened_messages, messages_before)
  assert_eq(
    reopened.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("Continue after archive")),
      ]),
    )
    is Ok(_),
    true,
  )
}

///|
fn archive_append_read_turn(
  engine : Engine,
  session_id : String,
  call_id : String,
  content : String,
) -> Unit {
  match
    engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string(session_id)),
        ("prompt", Json::string("Read another file")),
      ]),
    ) {
    Ok(_) => ()
    Err(message) => abort("Second read send failed: " + message)
  }
  let provider = engine.take_effects()
  if provider.length() != 1 {
    abort("Archive fixture expected one provider effect")
  }
  match
    engine.complete(
      id_of(provider[0]),
      calls_response([(call_id, "read", "{\"file_path\":\"second.txt\"}")]),
    ) {
    Ok(_) => ()
    Err(message) => abort("Second read call dispatch failed: " + message)
  }
  let reads = engine.take_effects()
  if reads.length() != 1 || call_id_of(reads[0]) != call_id {
    abort("Archive fixture expected its named read effect")
  }
  match
    engine.complete(
      id_of(reads[0]),
      object([("ok", Json::boolean(true)), ("content", Json::string(content))]),
    ) {
    Ok(_) => ()
    Err(message) => abort("Second read completion failed: " + message)
  }
  let followup = engine.take_effects()
  if followup.length() != 1 {
    abort("Archive fixture expected one follow-up effect")
  }
  match
    engine.complete(id_of(followup[0]), stop_response("Second turn complete")) {
    Ok(_) => ()
    Err(message) => abort("Second read follow-up failed: " + message)
  }
}

///|
fn archive_prune_for_result(
  session : Session,
  result_seq : Int32,
) -> Event raise EngineError {
  for event in session.events {
    if event.kind == EngineEventKind::ToolResultPruned &&
      fields(event.data).get("result_seq") == Some(integer(result_seq)) {
      return event
    }
  }
  abort("Archive fixture has no direct pruning event")
}

///|
test "archive compacts two original results in one session and restores both exact refs" {
  let first_content = "A"[:].repeat(60).to_owned()
  let second_content = "B"[:].repeat(70).to_owned()
  let engine = completed_engine_with_tool_result(first_content)
  archive_append_read_turn(engine, "test", "read-second", second_content)
  match
    engine.invoke(
      "session_prune_tool_results",
      pruning_input(
        threshold_chars=code_point_length(PRUNE_MARKER) + 7,
        head_chars=4,
        tail_chars=3,
      ),
    ) {
    Ok(_) => ()
    Err(message) => abort("Two-result pruning failed: " + message)
  }
  let session = archive_test_session(engine)
  let result_sequences : Array[Int32] = []
  for event in session.events {
    if event.kind == EngineEventKind::ToolResult {
      result_sequences.push(event.seq)
    }
  }
  assert_eq(result_sequences.length(), 2)
  let first_plan = match
    engine.plan_tool_result_archive(
      SessionId::from_validated("test"),
      result_sequences[0],
    ) {
    Ok(value) => value
    Err(message) => abort("First archive plan failed: " + message)
  }
  let first_prune = archive_prune_for_result(session, result_sequences[0])
  let first_projection = required_string(first_prune.data, "content") catch {
    Invalid(message) => abort("First projection failed: " + message)
  }
  let first_config = prune_config_from_event(first_prune.data) catch {
    Invalid(message) => abort("First policy failed: " + message)
  }
  let first_source = archive_test_object_source(
    first_plan, first_content, first_projection, first_config,
  )
  assert_eq(engine.commit_tool_result_archive(first_plan, first_source), Ok(()))
  let unlisted_pair = archive_snapshot_with_unlisted_read_markers(
    engine.snapshot(),
    "read-second",
    first_source.reference(),
  )
  assert_true(
    Engine::new(test_tools()).restore_archived(unlisted_pair, [first_source])
    is Err(_),
  )
  let second_plan = match
    engine.plan_tool_result_archive(
      SessionId::from_validated("test"),
      result_sequences[1],
    ) {
    Ok(value) => value
    Err(message) => abort("Second archive plan failed: " + message)
  }
  let second_prune = archive_prune_for_result(
    archive_test_session(engine),
    result_sequences[1],
  )
  let second_projection = required_string(second_prune.data, "content") catch {
    Invalid(message) => abort("Second projection failed: " + message)
  }
  let second_config = prune_config_from_event(second_prune.data) catch {
    Invalid(message) => abort("Second policy failed: " + message)
  }
  let second_source = archive_test_object_source(
    second_plan, second_content, second_projection, second_config,
  )
  let candidate = match
    engine.tool_result_archive_candidate(second_plan, second_source) {
    Ok(value) => value
    Err(message) => abort("Second archive candidate failed: " + message)
  }
  assert_eq(
    engine.commit_tool_result_archive(second_plan, second_source),
    Ok(()),
  )
  assert_eq(engine.snapshot(), candidate)
  assert_eq(
    array_value(required_field(candidate, "archives"), "archive manifest", 256).length(),
    2,
  )
  let reopened = Engine::new(test_tools())
  assert_eq(
    reopened.restore_archived(candidate, [first_source, second_source]),
    Ok(()),
  )
  assert_eq(reopened.snapshot(), candidate)
  let reopened_messages = reopened.lookup("test").model_messages()
  let reopened_tool_contents : Array[String] = []
  for message in reopened_messages {
    if fields(message).get("role") == Some(Json::string("tool")) {
      reopened_tool_contents.push(required_string(message, "content"))
    }
  }
  assert_eq(reopened_tool_contents, [first_projection, second_projection])
}

///|
test "archive reopen keeps six cumulative 63 KiB originals and completes the next turn" {
  let original = "x".repeat(63000)
  let (first_engine, first_result_seq) = archive_plan_fixture(original)
  let mut engine = first_engine
  let mut result_seq = first_result_seq
  let sources : Array[ToolResultArchiveSource] = []
  for turn in 0..<6 {
    if turn > 0 {
      archive_append_read_turn(
        engine,
        "test",
        "read-" + turn.to_string(),
        original,
      )
      match
        engine.invoke(
          "session_prune_tool_results",
          pruning_input(
            threshold_chars=code_point_length(PRUNE_MARKER) + 7,
            head_chars=4,
            tail_chars=3,
          ),
        ) {
        Ok(_) => ()
        Err(message) => abort("Cumulative archive pruning failed: " + message)
      }
      for event in archive_test_session(engine).events {
        if event.kind == EngineEventKind::ToolResult {
          result_seq = event.seq
        }
      }
    }
    let plan = match
      engine.plan_tool_result_archive(
        SessionId::from_validated("test"),
        result_seq,
      ) {
      Ok(value) => value
      Err(message) => abort("Cumulative archive plan failed: " + message)
    }
    let prune = archive_test_session(engine).events[plan.pruned_sequence()]
    let projection = required_string(prune.data, "content") catch {
      Invalid(message) =>
        abort("Cumulative archive projection failed: " + message)
    }
    let config = prune_config_from_event(prune.data) catch {
      Invalid(message) => abort("Cumulative archive policy failed: " + message)
    }
    let source = archive_test_object_source(plan, original, projection, config)
    let candidate = match engine.tool_result_archive_candidate(plan, source) {
      Ok(value) => value
      Err(message) => abort("Cumulative archive candidate failed: " + message)
    }
    assert_eq(engine.commit_tool_result_archive(plan, source), Ok(()))
    assert_eq(engine.snapshot(), candidate)
    sources.push(source)
    let reopened = Engine::new(test_tools())
    assert_eq(reopened.restore_archived(candidate, sources), Ok(()))
    assert_true(reopened.take_effects().is_empty())
    assert_eq(reopened.snapshot(), candidate)
    engine = reopened
  }
  assert_true(63000 * 6 > SESSION_CAPACITY)
  assert_eq(sources.length(), 6)
  archive_append_read_turn(engine, "test", "archive-read-after", "next result")
  assert_eq(get_status(get_session(engine)), "completed")
  let final_snapshot = engine.snapshot()
  let final_reopen = Engine::new(test_tools())
  assert_eq(final_reopen.restore_archived(final_snapshot, sources), Ok(()))
  assert_true(final_reopen.take_effects().is_empty())
  assert_eq(final_reopen.snapshot(), final_snapshot)
}

///|
test "archive admission rejects histories whose three-copy hydration exceeds its budget" {
  let original = "x".repeat(63000)
  let engine = Engine::new(test_tools())
  let sources : Array[ToolResultArchiveSource] = []
  let mut archived = 0
  let mut rejected = false
  for session_index in 0..<8 {
    if !rejected {
      let session_id = "review-multi-" + session_index.to_string()
      ignore(
        success(
          engine.invoke(
            "session_create",
            object([("id", Json::string(session_id))]),
          ),
        ),
      )
      for turn in 0..<12 {
        if !rejected {
          let call_id = "read-" +
            session_index.to_string() +
            "-" +
            turn.to_string()
          archive_append_read_turn(engine, session_id, call_id, original)
          match
            engine.invoke(
              "session_prune_tool_results",
              object([
                ("session_id", Json::string(session_id)),
                (
                  "threshold_chars",
                  integer(code_point_length(PRUNE_MARKER) + 7),
                ),
                ("head_chars", integer(4)),
                ("tail_chars", integer(3)),
              ]),
            ) {
            Ok(_) => ()
            Err(message) => abort("Multi-session pruning failed: " + message)
          }
          let session = engine.lookup(session_id)
          let mut result_seq = -1
          for event in session.events {
            if event.kind == EngineEventKind::ToolResult {
              result_seq = event.seq
            }
          }
          if result_seq < 0 {
            abort("Multi-session archive result is missing")
          }
          let plan = match
            engine.plan_tool_result_archive(
              SessionId::from_validated(session_id),
              result_seq,
            ) {
            Ok(value) => value
            Err(message) =>
              abort("Multi-session archive plan failed: " + message)
          }
          let prune = session.events[plan.pruned_sequence()]
          let projection = required_string(prune.data, "content") catch {
            Invalid(message) =>
              abort("Multi-session projection failed: " + message)
          }
          let config = prune_config_from_event(prune.data) catch {
            Invalid(message) => abort("Multi-session policy failed: " + message)
          }
          let source = archive_test_object_source(
            plan, original, projection, config,
          )
          let before = engine.snapshot()
          match engine.tool_result_archive_candidate(plan, source) {
            Ok(candidate) => {
              assert_eq(engine.commit_tool_result_archive(plan, source), Ok(()))
              assert_eq(engine.snapshot(), candidate)
              sources.push(source)
              archived += 1
            }
            Err(_) => {
              rejected = true
              assert_eq(engine.snapshot(), before)
              assert_true(
                engine.commit_tool_result_archive(plan, source) is Err(_),
              )
              assert_eq(engine.snapshot(), before)
              let over_budget_snapshot = archive_snapshot_with_extra_ref(
                before,
                source.reference(),
              )
              let over_budget_sources = sources.copy()
              over_budget_sources.push(source)
              assert_true(
                Engine::new(test_tools()).restore_archived(
                  over_budget_snapshot, over_budget_sources,
                )
                is Err(_),
              )
            }
          }
        }
      }
    }
  }
  assert_true(rejected)
  assert_eq(archived, 38)
  assert_true(archived * 63000 < 16777216)
  let compact_snapshot = engine.snapshot()
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore_archived(compact_snapshot, sources), Ok(()))
  assert_true(reopened.take_effects().is_empty())
  assert_eq(reopened.snapshot(), compact_snapshot)
}

///|
test "archived history restores later running approval and cancelled turns without replay" {
  let (running, _, running_source) = archive_committed_fixture(
    "R"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      running.invoke(
        "session_send",
        object([
          ("session_id", Json::string("test")),
          ("prompt", Json::string("Leave an active turn")),
        ]),
      ),
    ),
  )
  assert_eq(running.take_effects().length(), 1)
  let running_snapshot = running.snapshot()
  let reopened_running = Engine::new(test_tools())
  assert_eq(
    reopened_running.restore_archived(running_snapshot, [running_source]),
    Ok(()),
  )
  assert_eq(get_status(get_session(reopened_running)), "failed")
  assert_eq(reopened_running.effects.length(), 0)

  let (approval, _, approval_source) = archive_committed_fixture(
    "P"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      approval.invoke(
        "session_send",
        object([
          ("session_id", Json::string("test")),
          ("prompt", Json::string("Ask for a write")),
        ]),
      ),
    ),
  )
  let approval_llm = approval.take_effects()
  assert_eq(approval_llm.length(), 1)
  ignore(
    success(
      approval.complete(
        id_of(approval_llm[0]),
        calls_response([
          (
            "write-after-archive", "write", "{\"file_path\":\"x\",\"content\":\"y\"}",
          ),
        ]),
      ),
    ),
  )
  assert_eq(get_status(get_session(approval)), "awaiting_approval")
  let approval_snapshot = approval.snapshot()
  let reopened_approval = Engine::new(test_tools())
  assert_eq(
    reopened_approval.restore_archived(approval_snapshot, [approval_source]),
    Ok(()),
  )
  assert_eq(get_status(get_session(reopened_approval)), "awaiting_approval")
  assert_eq(reopened_approval.effects.length(), 0)
  let approval_input = object([
    ("session_id", Json::string("test")),
    ("call_id", Json::string("write-after-archive")),
    ("approved", Json::boolean(true)),
  ])
  ignore(success(reopened_approval.invoke("tool_approve", approval_input)))
  let writes = reopened_approval.take_effects()
  assert_eq(writes.length(), 1)
  assert_true(reopened_approval.take_effects().is_empty())
  assert_true(
    reopened_approval.invoke("tool_approve", approval_input) is Err(_),
  )
  let in_flight_snapshot = reopened_approval.snapshot()
  let interrupted_write = Engine::new(test_tools())
  assert_eq(
    interrupted_write.restore_archived(in_flight_snapshot, [approval_source]),
    Ok(()),
  )
  assert_eq(get_status(get_session(interrupted_write)), "failed")
  assert_eq(interrupted_write.effects.length(), 0)
  assert_true(
    interrupted_write.complete(
      id_of(writes[0]),
      object([
        ("ok", Json::boolean(true)),
        ("content", Json::string("Late write completion")),
      ]),
    )
    is Err(_),
  )
  ignore(
    success(
      reopened_approval.invoke(
        "session_cancel",
        object([("session_id", Json::string("test"))]),
      ),
    ),
  )
  assert_eq(get_status(get_session(reopened_approval)), "cancelled")
  assert_true(
    reopened_approval.complete(
      id_of(writes[0]),
      object([
        ("ok", Json::boolean(true)),
        ("content", Json::string("Late cancelled write")),
      ]),
    )
    is Err(_),
  )
  let cancelled_write = Engine::new(test_tools())
  assert_eq(
    cancelled_write.restore_archived(reopened_approval.snapshot(), [
      approval_source,
    ]),
    Ok(()),
  )
  assert_eq(get_status(get_session(cancelled_write)), "cancelled")
  assert_eq(cancelled_write.effects.length(), 0)

  let (cancelled, _, cancelled_source) = archive_committed_fixture(
    "C"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      cancelled.invoke(
        "session_send",
        object([
          ("session_id", Json::string("test")),
          ("prompt", Json::string("Cancel this turn")),
        ]),
      ),
    ),
  )
  ignore(cancelled.take_effects())
  ignore(
    success(
      cancelled.invoke(
        "session_cancel",
        object([("session_id", Json::string("test"))]),
      ),
    ),
  )
  let cancelled_snapshot = cancelled.snapshot()
  let reopened_cancelled = Engine::new(test_tools())
  assert_eq(
    reopened_cancelled.restore_archived(cancelled_snapshot, [cancelled_source]),
    Ok(()),
  )
  assert_eq(get_status(get_session(reopened_cancelled)), "cancelled")
  assert_eq(reopened_cancelled.effects.length(), 0)
}

///|
test "archive planner rejects forged call, effect, completion, result, and prune correlation" {
  let (forged_request, request_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_request),
    archive_event_sequence(
      archive_test_session(forged_request),
      EngineEventKind::ToolRequest,
    ),
    "effect_id",
    Json::string("effect-999"),
  )
  assert_true(archive_is_rejected(forged_request, request_result_seq))

  let (forged_completion, completion_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  let completion_seq = archive_event_sequence(
    archive_test_session(forged_completion),
    EngineEventKind::ToolCompleted,
  )
  archive_replace_event_field(
    archive_test_session(forged_completion),
    completion_seq,
    "content",
    Json::string("different completion text"),
  )
  assert_true(archive_is_rejected(forged_completion, completion_result_seq))

  let (forged_source, source_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_source),
    archive_event_sequence(
      archive_test_session(forged_source),
      EngineEventKind::ToolCompleted,
    ),
    "source",
    Json::string("local"),
  )
  assert_true(archive_is_rejected(forged_source, source_result_seq))

  let (forged_result, result_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_result),
    result_result_seq,
    "is_error",
    Json::boolean(true),
  )
  assert_true(archive_is_rejected(forged_result, result_result_seq))

  let (forged_prune, prune_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_prune),
    archive_event_sequence(
      archive_test_session(forged_prune),
      EngineEventKind::ToolResultPruned,
    ),
    "content",
    Json::string("forged projection"),
  )
  assert_true(archive_is_rejected(forged_prune, prune_result_seq))

  let (forged_source, source_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_source),
    archive_event_sequence(
      archive_test_session(forged_source),
      EngineEventKind::ToolResultPruned,
    ),
    "source_seq",
    integer(
      archive_event_sequence(
        archive_test_session(forged_source),
        EngineEventKind::ToolCall,
      ),
    ),
  )
  assert_true(archive_is_rejected(forged_source, source_result_seq))

  let (forged_policy, policy_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  let policy_prune_seq = archive_event_sequence(
    archive_test_session(forged_policy),
    EngineEventKind::ToolResultPruned,
  )
  archive_replace_event_field(
    archive_test_session(forged_policy),
    policy_prune_seq,
    "head_chars",
    integer(5),
  )
  archive_replace_event_field(
    archive_test_session(forged_policy),
    policy_prune_seq,
    "tail_chars",
    integer(2),
  )
  assert_true(archive_is_rejected(forged_policy, policy_result_seq))

  let (forged_counts, counts_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_counts),
    archive_event_sequence(
      archive_test_session(forged_counts),
      EngineEventKind::ToolResultPruned,
    ),
    "chars_before",
    integer(59),
  )
  assert_true(archive_is_rejected(forged_counts, counts_result_seq))

  let (forged_after_count, after_count_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  archive_replace_event_field(
    archive_test_session(forged_after_count),
    archive_event_sequence(
      archive_test_session(forged_after_count),
      EngineEventKind::ToolResultPruned,
    ),
    "chars_after",
    integer(0),
  )
  assert_true(archive_is_rejected(forged_after_count, after_count_result_seq))

  let (duplicate_completion, duplicate_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  let duplicate_session = archive_test_session(duplicate_completion)
  let completion = duplicate_session.events[archive_event_sequence(
      duplicate_session,
      EngineEventKind::ToolCompleted,
    )]
  duplicate_session.events.push({
    seq: duplicate_session.events.length(),
    kind: completion.kind,
    turn_id: completion.turn_id,
    step: completion.step,
    data: detached(completion.data),
  })
  assert_true(archive_is_rejected(duplicate_completion, duplicate_result_seq))

  let (chained_prune, chained_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      chained_prune.invoke(
        "session_prune_tool_results",
        pruning_input(
          threshold_chars=code_point_length(PRUNE_MARKER) + 5,
          head_chars=2,
          tail_chars=2,
        ),
      ),
    ),
  )
  assert_true(archive_is_rejected(chained_prune, chained_result_seq))
}

///|
test "archive planner rejects unpruned results and only accepts the requested original result" {
  let engine = completed_engine_with_tool_result(
    "😀"[:].repeat(60).to_owned(),
  )
  let session = archive_test_session(engine)
  let result_seq = archive_event_sequence(session, EngineEventKind::ToolResult)
  assert_true(archive_is_rejected(engine, result_seq))
  assert_true(
    archive_is_rejected(
      engine,
      archive_event_sequence(session, EngineEventKind::ToolCompleted),
    ),
  )
}

///|
test "archive planner rejects restored legacy direct tool results without completion provenance" {
  let (engine, _) = archive_plan_fixture("😀"[:].repeat(60).to_owned())
  let (legacy_snapshot, result_seq) = archive_legacy_result_snapshot(engine)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(legacy_snapshot), Ok(()))
  assert_true(archive_is_rejected(restored, result_seq))
}

///|
test "archive marker recognition preserves inert v4 extension metadata" {
  let jsonl = session_v4_portable_fixture() +
    "\n{\"type\":\"future/annotation\",\"ignorable\":true,\"data\":{\"archive_ref\":{\"note\":\"ordinary upstream metadata\"}}}"
  let engine = Engine::new(test_tools())
  ignore(
    success(
      engine.invoke("session_import", object([("jsonl", Json::string(jsonl))])),
    ),
  )
  let snapshot = engine.snapshot()
  assert_eq(required_string(snapshot, "schema"), "dsh.mbt-session-v1")
  assert_true(snapshot.stringify().contains("ordinary upstream metadata"))
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore(snapshot), Ok(()))
  assert_eq(reopened.snapshot(), snapshot)
}

///|
test "archive planner limits candidates to the closed regular read tool schema" {
  let (regular_read, read_result_seq) = archive_candidate_for_tool(
    "read",
    archive_builtin_read_schema(),
  )
  assert_true(
    regular_read.plan_tool_result_archive(
      SessionId::from_validated("test"),
      read_result_seq,
    )
    is Ok(_),
  )

  for name in ["glob", "grep", "skill", "subagent", "mcp__fixture__read"] {
    let (engine, result_seq) = archive_candidate_for_tool(
      name,
      archive_tool_schema(name),
    )
    assert_true(archive_is_rejected(engine, result_seq))
  }

  let (unsafe_read, result_seq) = archive_candidate_for_tool(
    "read",
    archive_tool_schema("read", extra_read_property=true),
  )
  assert_true(archive_is_rejected(unsafe_read, result_seq))
}

///|
test "archive planner rejects running, drained live effects, approval, and cancellation" {
  let (running, result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      running.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Continue\"}"),
      ),
    ),
  )
  assert_eq(get_status(get_session(running)), "running")
  assert_true(archive_is_rejected(running, result_seq))
  let drained = running.take_effects()
  assert_eq(drained.length(), 1)
  // The outgoing queue is drained, but the authoritative outstanding effect
  // remains in Engine.effects and still blocks a plan.
  assert_true(archive_is_rejected(running, result_seq))

  let (approval, approval_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      approval.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Write next\"}"),
      ),
    ),
  )
  let provider = approval.take_effects()
  assert_eq(provider.length(), 1)
  ignore(
    success(
      approval.complete(
        id_of(provider[0]),
        calls_response([
          ("write-next", "write", "{\"file_path\":\"x\",\"content\":\"y\"}"),
        ]),
      ),
    ),
  )
  assert_eq(get_status(get_session(approval)), "awaiting_approval")
  assert_true(archive_is_rejected(approval, approval_result_seq))

  let (cancelled, cancelled_result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      cancelled.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Cancel next\"}"),
      ),
    ),
  )
  ignore(cancelled.take_effects())
  let cancellation = success(
    cancelled.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancellation), "cancelled")
  assert_true(archive_is_rejected(cancelled, cancelled_result_seq))
}

///|
test "archive planner rejects imported and both sides of fork lineage" {
  let imported_engine = Engine::new(test_tools())
  ignore(
    success(
      imported_engine.invoke(
        "session_import",
        object([("jsonl", Json::string(session_v4_metadata_fixture()))]),
      ),
    ),
  )
  let imported = imported_engine.sessions.get("session-1").unwrap()
  let mut imported_result_seq = -1
  for event in imported.events {
    if event.kind == EngineEventKind::UpstreamEvent &&
      required_string(required_field(event.data, "record"), "type") ==
      "tool/result" {
      imported_result_seq = event.seq
    }
  }
  assert_true(imported_result_seq >= 0)
  assert_true(
    archive_is_rejected_without_mutation(
      imported_engine, "session-1", imported_result_seq,
    ),
  )

  let (forked, result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      forked.invoke(
        "session_fork",
        object([
          ("session_id", Json::string("test")),
          ("id", Json::string("child")),
        ]),
      ),
    ),
  )
  assert_true(archive_is_rejected(forked, result_seq))
  assert_true(archive_is_rejected_without_mutation(forked, "child", result_seq))
}

///|
test "archive planner fails closed on hidden retry and hook state in a settled-looking session" {
  let (engine, result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  let session = archive_test_session(engine)
  session.pending_retry_id = Some("retry-effect-1-1")
  assert_true(archive_is_rejected(engine, result_seq))
  session.pending_retry_id = None

  session.stop_hook_pending = true
  assert_true(archive_is_rejected(engine, result_seq))
  session.stop_hook_pending = false

  session.subagent_prompt_hook_active = true
  assert_true(archive_is_rejected(engine, result_seq))
  session.subagent_prompt_hook_active = false

  session.post_tool_prompt_hook_active = true
  assert_true(archive_is_rejected(engine, result_seq))
  session.post_tool_prompt_hook_active = false

  session.events.push({
    seq: session.events.length(),
    kind: EngineEventKind::HookInvoked,
    turn_id: session.turn_id,
    step: session.step,
    data: object([
      ("turn", integer(session.turn_id)),
      ("point", Json::string("Stop")),
      ("dialect", Json::string("claude-code")),
      ("handlerId", Json::string("claude-code:Stop:1")),
    ]),
  })
  assert_true(archive_is_rejected(engine, result_seq))
}

///|
test "archive planner rejects a stale active effect even after the queue is drained" {
  let (engine, result_seq) = archive_plan_fixture(
    "😀"[:].repeat(60).to_owned(),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Start another turn\"}"),
      ),
    ),
  )
  ignore(engine.take_effects())
  let session = archive_test_session(engine)
  // Simulate stale restored/runtime bookkeeping that looks settled at the
  // session level while Engine.effects still owns the exact effect.
  session.status = Completed
  session.open_step = false
  session.active_effect = None
  session.active_kind = None
  assert_true(archive_is_rejected(engine, result_seq))
}

///|
test "archive and summary records fail closed across their incompatible identity boundary" {
  let archived_content = "x".repeat(96)
  let (archived, _, _) = archive_committed_fixture(archived_content)
  compaction_plan_complete_turn(archived, "test", "recent", "answer")
  let archived_plan = compaction_plan_required(
    archived, "test", 1, 1048576, 1048576,
  )
  let archived_before = archived.snapshot()
  assert_true(
    archived.invoke("session_compact_summary", {
      "session_id": "test",
      "plan": archived_plan,
      "summary": "Cannot bind across archived source bytes.",
      "retain_recent_turns": 1,
      "max_source_event_json_utf8_bytes": 1048576,
      "max_source_messages_json_utf8_bytes": 1048576,
      "max_summary_json_utf8_bytes": 1048576,
    })
    is Err(_),
  )
  assert_eq(archived.snapshot(), archived_before)
  assert_true(archived.take_effects().is_empty())

  let (summary_engine, result_seq) = archive_plan_fixture(archived_content)
  compaction_plan_complete_turn(summary_engine, "test", "recent", "answer")
  let summary_plan = compaction_plan_required(
    summary_engine, "test", 1, 1048576, 1048576,
  )
  ignore(
    compaction_summary_commit(
      summary_engine, "test", summary_plan, "The old exchange is summarized; the recent turn remains intact.",
    ),
  )
  let summary_before_archive = summary_engine.snapshot()
  assert_true(
    summary_engine.plan_tool_result_archive(
      SessionId::from_validated("test"),
      result_seq,
    )
    is Err(_),
  )
  assert_eq(summary_engine.snapshot(), summary_before_archive)
  assert_true(summary_engine.take_effects().is_empty())
}
