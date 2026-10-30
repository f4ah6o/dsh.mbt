///|
fn native_subagent_audit_test_child_snapshot(child_id : String) -> Json raise {
  let child = @engine.Engine::new(native_subagent_audit_child_tools())
  child
  .invoke("session_create", {
    "id": child_id,
    "title": "Audit codec fixture",
    "max_steps": 3,
  })
  .unwrap()
  |> ignore
  child
  .invoke("session_send", {
    "session_id": child_id,
    "prompt": "Finish the fixture child task.",
  })
  .unwrap()
  |> ignore
  let effects = child.take_typed_effects()
  if effects.length() != 1 || effects[0].kind() != @engine.EffectType::Provider {
    fail("audit fixture did not receive one provider effect")
  }
  child
  .complete_effect(effects[0].id(), {
    "ok": true,
    "content": "The fixture child completed.",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  if !child.take_typed_effects().is_empty() {
    fail("audit fixture left child effects pending")
  }
  child.snapshot()
}

///|
fn native_subagent_audit_test_record(
  child_id~ : String = "subagent-audit-child",
  workspace_id~ : String = "workspace-audit-123",
  child_status~ : String = "completed",
  snapshot? : Json,
) -> Json raise {
  {
    "schema": NATIVE_SUBAGENT_AUDIT_SCHEMA,
    "parent_session_id": "parent-audit-session",
    "parent_turn_id": 2,
    "parent_effect_id": "effect-9",
    "parent_tool_call_id": "parent-subagent-call",
    "child_id": child_id,
    "workspace_id": workspace_id,
    "child_status": child_status,
    "engine_snapshot": snapshot.unwrap_or(
      native_subagent_audit_test_child_snapshot(child_id),
    ),
  }
}

///|
fn native_subagent_audit_test_failed_snapshot(child_id : String) -> Json raise {
  let child = @engine.Engine::new(native_subagent_audit_child_tools())
  child.invoke("session_create", { "id": child_id, "max_steps": 3 }).unwrap()
  |> ignore
  child
  .invoke("session_send", {
    "session_id": child_id,
    "prompt": "Fail the fixture child task.",
  })
  .unwrap()
  |> ignore
  let effects = child.take_typed_effects()
  if effects.length() != 1 || effects[0].kind() != @engine.EffectType::Provider {
    fail("failed audit fixture did not receive one provider effect")
  }
  child
  .complete_effect(effects[0].id(), {
    "ok": false,
    "error": "fixture provider failure",
  })
  .unwrap()
  |> ignore
  if !child.take_typed_effects().is_empty() {
    fail("failed audit fixture left child effects pending")
  }
  child.snapshot()
}

///|
fn native_subagent_audit_test_nested_snapshot(
  snapshot : Json,
  nested_arrays : Int32,
) -> Json raise {
  let sessions = match object_field(snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("test engine snapshot omitted sessions")
  }
  let session_fields = match sessions[0] {
    Json::Object(fields) => fields
    _ => fail("test child session is not an object")
  }
  let mut nested = Json::null()
  for _ in 0..<nested_arrays {
    nested = Json::array([nested])
  }
  session_fields["codec_test_nested"] = nested
  let changed_sessions = sessions.copy()
  changed_sessions[0] = Json::object(session_fields)
  let snapshot_fields = match snapshot {
    Json::Object(fields) => fields
    _ => fail("test engine snapshot is not an object")
  }
  snapshot_fields["sessions"] = Json::array(changed_sessions)
  Json::object(snapshot_fields)
}

///|
test "subagent audit codec round-trips one correlated terminal snapshot" {
  let record = native_subagent_audit_test_record()
  let encoded = match native_subagent_audit_encode(record) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(@utf8.encode(encoded).length() <= NATIVE_SUBAGENT_AUDIT_MAX_BYTES)
  let decoded = match native_subagent_audit_decode(encoded) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(decoded, record)
  assert_eq(
    string_field(decoded, "parent_session_id"),
    Some("parent-audit-session"),
  )
  assert_eq(string_field(decoded, "parent_effect_id"), Some("effect-9"))
  assert_eq(
    string_field(decoded, "parent_tool_call_id"),
    Some("parent-subagent-call"),
  )
  assert_eq(string_field(decoded, "child_id"), Some("subagent-audit-child"))
  assert_eq(string_field(decoded, "workspace_id"), Some("workspace-audit-123"))
  assert_eq(string_field(decoded, "child_status"), Some("completed"))
}

///|
test "subagent audit codec round-trips a settled failed child" {
  let child_id = "subagent-audit-failed"
  let record = native_subagent_audit_test_record(
    child_id~,
    child_status="failed",
    snapshot=native_subagent_audit_test_failed_snapshot(child_id),
  )
  let encoded = match native_subagent_audit_encode(record) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let decoded = match native_subagent_audit_decode(encoded) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(decoded, record)
}

///|
test "subagent audit codec rejects unknown fields and malformed correlation" {
  let record = native_subagent_audit_test_record()
  let fields = match record {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  fields["unexpected"] = Json::boolean(true)
  assert_true(native_subagent_audit_encode(Json::object(fields)) is Err(_))

  let call_fields = match native_subagent_audit_test_record() {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  call_fields["parent_tool_call_id"] = Json::string("../outside")
  assert_true(native_subagent_audit_encode(Json::object(call_fields)) is Err(_))

  let effect_fields = match native_subagent_audit_test_record() {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  effect_fields["parent_effect_id"] = Json::string("effect-not-a-number")
  assert_true(
    native_subagent_audit_encode(Json::object(effect_fields)) is Err(_),
  )

  let zero_effect_fields = match native_subagent_audit_test_record() {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  zero_effect_fields["parent_effect_id"] = Json::string("effect-0")
  assert_true(
    native_subagent_audit_encode(Json::object(zero_effect_fields)) is Err(_),
  )

  let leading_zero_effect_fields = match native_subagent_audit_test_record() {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  leading_zero_effect_fields["parent_effect_id"] = Json::string("effect-09")
  assert_true(
    native_subagent_audit_encode(Json::object(leading_zero_effect_fields))
    is Err(_),
  )
}

///|
test "subagent audit decoder rejects unknown and missing fields and detaches input" {
  let record = native_subagent_audit_test_record()
  let encoded = native_subagent_audit_encode(record).unwrap()
  let unknown_fields = match @json.parse(encoded) {
    Json::Object(fields) => fields
    _ => fail("encoded test record is not an object")
  }
  unknown_fields["unexpected"] = Json::boolean(true)
  assert_true(
    native_subagent_audit_decode(Json::object(unknown_fields).stringify())
    is Err(_),
  )
  let missing_fields = match @json.parse(encoded) {
    Json::Object(fields) => fields
    _ => fail("encoded test record is not an object")
  }
  ignore(missing_fields.remove("workspace_id"))
  assert_true(
    native_subagent_audit_decode(Json::object(missing_fields).stringify())
    is Err(_),
  )

  let detached = native_subagent_audit_validate_record(record).unwrap()
  let source_snapshot = object_field(record, "engine_snapshot").unwrap()
  let source_sessions = match object_field(source_snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("source engine snapshot omitted sessions")
  }
  let source_session_fields = match source_sessions[0] {
    Json::Object(fields) => fields
    _ => fail("source child session is not an object")
  }
  source_session_fields["title"] = Json::string("mutated after validation")
  let detached_snapshot = object_field(detached, "engine_snapshot").unwrap()
  let detached_sessions = match object_field(detached_snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("detached engine snapshot omitted sessions")
  }
  assert_true(
    string_field(detached_sessions[0], "title") !=
    Some("mutated after validation"),
  )
}

///|
test "subagent audit decoder rejects duplicate JSON object keys" {
  let encoded = native_subagent_audit_encode(
    native_subagent_audit_test_record(),
  ).unwrap()
  let duplicate = "{\"schema\":\"dsh-subagent-audit-v1\"," +
    encoded[1:].to_owned()
  assert_true(native_subagent_audit_decode(duplicate) is Err(_))

  // The raw spellings differ, but JSON key identity is based on the decoded
  // string. This prevents escaped spellings from bypassing duplicate checks.
  let escaped_duplicate = "{\"\\u0073chema\":\"dsh-subagent-audit-v1\"," +
    encoded[1:].to_owned()
  assert_true(native_subagent_audit_decode(escaped_duplicate) is Err(_))
}

///|
test "subagent audit codec rejects nonterminal and mismatched child snapshots" {
  let child_id = "subagent-audit-running"
  let child = @engine.Engine::new(native_subagent_audit_child_tools())
  child.invoke("session_create", { "id": child_id, "max_steps": 3 }).unwrap()
  |> ignore
  child
  .invoke("session_send", {
    "session_id": child_id,
    "prompt": "Leave a provider request pending.",
  })
  .unwrap()
  |> ignore
  ignore(child.take_typed_effects())
  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(child_id~, snapshot=child.snapshot()),
    )
    is Err(_),
  )

  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(
        child_id="subagent-audit-other",
        snapshot=native_subagent_audit_test_child_snapshot(
          "subagent-audit-actual",
        ),
      ),
    )
    is Err(_),
  )
}

///|
test "subagent audit codec rejects forged derived messages" {
  let child_id = "subagent-audit-forged-messages"
  let snapshot = native_subagent_audit_test_child_snapshot(child_id)
  let sessions = match object_field(snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("test engine snapshot omitted sessions")
  }
  let session_fields = match sessions[0] {
    Json::Object(fields) => fields
    _ => fail("test child session is not an object")
  }
  let messages = match session_fields.get("messages") {
    Some(Json::Array(values)) if values.length() >= 2 => values
    _ => fail("test child snapshot omitted derived messages")
  }
  let forged_messages = messages.copy()
  let forged_assistant_message = match forged_messages[1] {
    Json::Object(fields) => fields
    _ => fail("test assistant message is not an object")
  }
  forged_assistant_message["content"] = Json::string("forged derived content")
  forged_messages[1] = Json::object(forged_assistant_message)
  session_fields["messages"] = Json::array(forged_messages)
  let forged_session = Json::object(session_fields)
  let forged_sessions = sessions.copy()
  forged_sessions[0] = forged_session
  let snapshot_fields = match snapshot {
    Json::Object(fields) => fields
    _ => fail("test engine snapshot is not an object")
  }
  snapshot_fields["sessions"] = Json::array(forged_sessions)
  let forged_snapshot = Json::object(snapshot_fields)
  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(child_id~, snapshot=forged_snapshot),
    )
    is Err(_),
  )
}

///|
test "subagent audit codec rejects interrupted outcomes and oversized or deep input" {
  let snapshot = native_subagent_audit_test_child_snapshot(
    "subagent-audit-interrupted",
  )
  let sessions = match object_field(snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("test engine snapshot omitted sessions")
  }
  let events = match object_field(sessions[0], "events") {
    Some(Json::Array(values)) => values
    _ => fail("test child snapshot omitted events")
  }
  let last = events[events.length() - 1]
  let end_data = object_field(last, "data").unwrap()
  let changed_data = match end_data {
    Json::Object(fields) => fields
    _ => fail("test turn/end data is not an object")
  }
  changed_data["reason"] = Json::string("interrupted")
  let changed_event = match last {
    Json::Object(fields) => fields
    _ => fail("test turn/end is not an object")
  }
  changed_event["data"] = Json::object(changed_data)
  let changed_events = events.copy()
  changed_events[changed_events.length() - 1] = Json::object(changed_event)
  let changed_session = match sessions[0] {
    Json::Object(fields) => fields
    _ => fail("test child session is not an object")
  }
  changed_session["events"] = Json::array(changed_events)
  let changed_sessions = sessions.copy()
  changed_sessions[0] = Json::object(changed_session)
  let changed_snapshot = match snapshot {
    Json::Object(fields) => fields
    _ => fail("test engine snapshot is not an object")
  }
  changed_snapshot["sessions"] = Json::array(changed_sessions)
  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(
        child_id="subagent-audit-interrupted",
        snapshot=Json::object(changed_snapshot),
      ),
    )
    is Err(_),
  )

  // Engine replay accepts this marker inside an open terminal turn, so the
  // archive contract must reject the interruption explicitly.
  let valid_snapshot = native_subagent_audit_test_child_snapshot(
    "subagent-audit-interruption-marker",
  )
  let valid_sessions = match object_field(valid_snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => fail("test engine snapshot omitted sessions")
  }
  let valid_session = valid_sessions[0]
  let valid_events = match object_field(valid_session, "events") {
    Some(Json::Array(values)) => values
    _ => fail("test child snapshot omitted events")
  }
  let terminal_event = valid_events[valid_events.length() - 1]
  let terminal_sequence = int_field(terminal_event, "seq").unwrap()
  let terminal_turn = int_field(terminal_event, "turn_id").unwrap()
  let terminal_step = int_field(terminal_event, "step").unwrap()
  let shifted_terminal_fields = match terminal_event {
    Json::Object(fields) => fields
    _ => fail("test terminal event is not an object")
  }
  shifted_terminal_fields["seq"] = Json::number(
    (terminal_sequence + 1).to_double(),
  )
  let interrupted_event : Json = {
    "seq": terminal_sequence,
    "type": "session/interrupted",
    "turn_id": terminal_turn,
    "step": terminal_step,
    "data": { "reason": "fixture interruption" },
  }
  let marked_events = valid_events.copy()
  marked_events[marked_events.length() - 1] = interrupted_event
  marked_events.push(Json::object(shifted_terminal_fields))
  let valid_session_fields = match valid_session {
    Json::Object(fields) => fields
    _ => fail("test child session is not an object")
  }
  valid_session_fields["events"] = Json::array(marked_events)
  let marked_sessions = valid_sessions.copy()
  marked_sessions[0] = Json::object(valid_session_fields)
  let valid_snapshot_fields = match valid_snapshot {
    Json::Object(fields) => fields
    _ => fail("test engine snapshot is not an object")
  }
  valid_snapshot_fields["sessions"] = Json::array(marked_sessions)
  let interruption_snapshot = Json::object(valid_snapshot_fields)
  let engine_validator = @engine.Engine::new(
    native_subagent_audit_child_tools(),
  )
  assert_true(engine_validator.restore(interruption_snapshot) is Ok(_))
  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(
        child_id="subagent-audit-interruption-marker",
        snapshot=interruption_snapshot,
      ),
    )
    is Err(_),
  )

  let encoded = native_subagent_audit_encode(
    native_subagent_audit_test_record(),
  ).unwrap()
  let encoded_length = @utf8.encode(encoded).length()
  let exact_size = encoded +
    " ".repeat(NATIVE_SUBAGENT_AUDIT_MAX_BYTES - encoded_length)
  assert_true(native_subagent_audit_decode(exact_size) is Ok(_))
  assert_true(native_subagent_audit_decode(exact_size + " ") is Err(_))
  let deeply_nested = "[".repeat(NATIVE_SUBAGENT_AUDIT_MAX_DEPTH + 1) +
    "null" +
    "]".repeat(NATIVE_SUBAGENT_AUDIT_MAX_DEPTH + 1)
  assert_true(native_subagent_audit_decode(deeply_nested) is Err(_))
}

///|
test "subagent audit encode and decode agree on the exact JSON container depth" {
  let child_id = "subagent-audit-depth"
  let base_snapshot = native_subagent_audit_test_child_snapshot(child_id)
  let at_limit = native_subagent_audit_test_nested_snapshot(
    base_snapshot,
    NATIVE_SUBAGENT_AUDIT_MAX_DEPTH - 4,
  )
  let encoded = match
    native_subagent_audit_encode(
      native_subagent_audit_test_record(child_id~, snapshot=at_limit),
    ) {
    Ok(value) => value
    Err(error) => fail("exact container depth was rejected: " + error)
  }
  assert_true(native_subagent_audit_decode(encoded) is Ok(_))

  let beyond_limit = native_subagent_audit_test_nested_snapshot(
    base_snapshot,
    NATIVE_SUBAGENT_AUDIT_MAX_DEPTH - 3,
  )
  assert_true(
    native_subagent_audit_encode(
      native_subagent_audit_test_record(child_id~, snapshot=beyond_limit),
    )
    is Err(_),
  )
}

///|
test "subagent audit codec enforces a node budget before accepting unknown data" {
  let exact_budget : NativeSubagentAuditJsonBudget = {
    nodes: NATIVE_SUBAGENT_AUDIT_MAX_NODES,
    text_bytes: NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
  }
  assert_true(
    native_subagent_audit_copy_json(
      Json::array(
        Array::make(NATIVE_SUBAGENT_AUDIT_MAX_NODES - 1, Json::null()),
      ),
      0,
      exact_budget,
    )
    is Ok(_),
  )
  let beyond_budget : NativeSubagentAuditJsonBudget = {
    nodes: NATIVE_SUBAGENT_AUDIT_MAX_NODES,
    text_bytes: NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
  }
  assert_true(
    native_subagent_audit_copy_json(
      Json::array(Array::make(NATIVE_SUBAGENT_AUDIT_MAX_NODES, Json::null())),
      0,
      beyond_budget,
    )
    is Err(_),
  )
  let exact_syntax_nodes = "[" +
    "null,".repeat(NATIVE_SUBAGENT_AUDIT_MAX_NODES - 2) +
    "null]"
  assert_true(
    native_subagent_audit_validate_nesting(@utf8.encode(exact_syntax_nodes))
    is Ok(_),
  )
  let excess_syntax_nodes = "[" +
    "null,".repeat(NATIVE_SUBAGENT_AUDIT_MAX_NODES - 1) +
    "null]"
  assert_true(
    native_subagent_audit_validate_nesting(@utf8.encode(excess_syntax_nodes))
    is Err(_),
  )
  let fields = match native_subagent_audit_test_record() {
    Json::Object(fields) => fields
    _ => fail("test audit record is not an object")
  }
  fields["extra"] = Json::array(
    Array::make(NATIVE_SUBAGENT_AUDIT_MAX_NODES, Json::null()),
  )
  match native_subagent_audit_encode(Json::object(fields)) {
    Err(error) => assert_true(error.contains("node limit"))
    Ok(_) => fail("audit codec accepted a record beyond its node budget")
  }
}
