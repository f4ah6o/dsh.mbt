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
