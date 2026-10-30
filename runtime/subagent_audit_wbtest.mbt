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

///|
async fn native_subagent_audit_demo_runtime(
  data_dir : String,
  workspace : String,
  persist : Bool,
  hooks_config_path~ : String? = None,
) -> NativeRuntime {
  match
    NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      enable_subagents=true,
      persist_subagent_audits=persist,
      hooks_config_path~,
    ) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
async fn native_subagent_audit_demo_parent_tool(
  runtime : NativeRuntime,
  session_id : String,
) -> @engine.EngineEffect {
  native_subagent_parent_tool_effect(
    runtime,
    session_id,
    "audit-parent-call",
    "Inspect a file",
    child_prompt="Read README.md and report its first line.",
  )
}

///|
fn native_subagent_audit_fault_hook_config() -> String {
  let post_command = "printf x >> \"${CLAUDE_PROJECT_DIR}/post-tool-count\"; printf '{}'"
  let command_hook = fn(command : String) {
    Json::object({
      "type": Json::string("command"),
      "command": Json::string(command),
    })
  }
  Json::object({
    "PostToolUse": Json::array([
      Json::object({
        "matcher": Json::string("subagent"),
        "hooks": Json::array([command_hook(post_command)]),
      }),
    ]),
  }).stringify()
}

///|
async test "native subagent audit flag requires enabled subagents before startup" {
  match
    NativeRuntime::open(
      "/unused/data",
      "/unused/workspace",
      false,
      true,
      persist_subagent_audits=true,
    ) {
    Err(error) =>
      assert_eq(error, "--persist-subagent-audits requires --enable-subagents")
    Ok(runtime) => {
      ignore(runtime.close())
      fail("audit persistence started without --enable-subagents")
    }
  }
}

///|
async test "subagent audit quota reserves a destination and a possible temp file" {
  assert_true(native_subagent_audit_reservation_fits(30, 125829120L, 4194304))
  assert_false(native_subagent_audit_reservation_fits(31, 0L, 1))
  assert_false(native_subagent_audit_reservation_fits(32, 0L, 1))
  assert_false(native_subagent_audit_reservation_fits(30, 125829121L, 4194304))
  assert_false(native_subagent_audit_reservation_fits(30, 125829120L, 4194305))
  assert_false(native_subagent_audit_reservation_fits(-1, 0L, 1))
  assert_false(native_subagent_audit_reservation_fits(0, -1L, 1))

  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-quota")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let audit_dir = fixture + "/audits"
    @fs.mkdir(audit_dir)
    let temporary_name = ".dsh-123-1.tmp"
    @fs.write_file(audit_dir + "/" + temporary_name, "\u0000partial")
    let root = match SafeRoot::open(audit_dir) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_true(native_subagent_audit_check_quota(root, 1) is Ok(_))
    assert_eq(root.file_version(temporary_name).unwrap().size(), 8L)
    @fs.mkdir(audit_dir + "/nested")
    assert_true(native_subagent_audit_check_quota(root, 1) is Err(_))
    root.close()
    assert_true(native_subagent_audit_check_quota(root, 1) is Err(_))
  }
}

///|
async test "opt-in foreground child audit writes the validated terminal snapshot" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-publish")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "audit fixture\nsecond line\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-publication-parent",
    )
    let parent_effect_id = effect.id().as_string()
    let (parent, next) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(next.length(), 1)
    assert_true(next[0].kind() == @engine.EffectType::Provider)
    let result = native_subagent_result_for_call(parent, "audit-parent-call")
    let child_id = string_field(result, "child_id").unwrap()
    let relative_path = child_id + ".json"
    let audit_path = data_dir + "/subagent-audits/" + relative_path
    let raw = @fs.read_file(audit_path).text()
    let record = match native_subagent_audit_decode(raw) {
      Ok(value) => value
      Err(error) => fail("published audit failed strict decode: " + error)
    }
    assert_eq(
      string_field(record, "schema"),
      Some(NATIVE_SUBAGENT_AUDIT_SCHEMA),
    )
    assert_eq(
      string_field(record, "parent_session_id"),
      Some("audit-publication-parent"),
    )
    assert_eq(int_field(record, "parent_turn_id"), Some(1))
    assert_eq(string_field(record, "parent_effect_id"), Some(parent_effect_id))
    assert_eq(
      string_field(record, "parent_tool_call_id"),
      Some("audit-parent-call"),
    )
    assert_eq(string_field(record, "child_id"), Some(child_id))
    assert_eq(
      string_field(record, "workspace_id"),
      Some(runtime.state.workspace_id),
    )
    assert_eq(string_field(record, "child_status"), Some("completed"))
    let root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    assert_eq(root.file_version(relative_path).unwrap().permission(), 0o600)
    root.close()
    assert_true(@utf8.encode(raw).length() <= NATIVE_SUBAGENT_AUDIT_MAX_BYTES)
  }
}

///|
async test "foreground subagent audit default creates no directory or file" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-default-off")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "default audit fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, false)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-default-parent",
    )
    ignore(runtime.run_tool_effect(effect).unwrap())
    assert_false(@fs.exists(data_dir + "/subagent-audits"))
  }
}

///|
async test "audit setup failure interrupts the parent without normal tool completion" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-fatal")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.mkdir(data_dir)
    @fs.write_file(workspace + "/README.md", "fatal audit fixture\n")
    @fs.write_file(data_dir + "/subagent-audits", "blocks directory creation")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-fatal-parent",
    )
    assert_true(runtime.run_tool_effect(effect) is Err(_))
    let session = runtime.api
      .invoke("session_get", { "session_id": "audit-fatal-parent" })
      .unwrap()
    assert_eq(string_field(session, "status"), Some("failed"))
    let events = match object_field(session, "events") {
      Some(Json::Array(values)) => values
      _ => fail("fatal audit parent omitted its event log")
    }
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      1,
    )
    let interrupted = events.filter(event => {
      if string_field(event, "type") != Some("tool/completed") {
        false
      } else {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(data, "source") == Some("interrupted") &&
        string_field(data, "call_id") == Some("audit-parent-call")
      }
    })
    assert_eq(interrupted.length(), 1)
    assert_true(runtime.api.take_typed_effects().is_empty())
  }
}

///|
async test "atomic publication errors all map to fatal outcomes and Exists preserves the destination" {
  assert_true(
    native_subagent_audit_atomic_outcome(
      Err(AtomicCreateNoReplaceError::Exists),
    )
    is NativeSubagentAuditPublishOutcome::Fatal(_),
  )
  assert_true(
    native_subagent_audit_atomic_outcome(
      Err(AtomicCreateNoReplaceError::Failed("fixture failure")),
    )
    is NativeSubagentAuditPublishOutcome::Fatal(_),
  )
  match
    native_subagent_audit_atomic_outcome(
      Err(AtomicCreateNoReplaceError::OutcomeUnknown("fixture unknown")),
    ) {
    NativeSubagentAuditPublishOutcome::Fatal(message) =>
      assert_true(message.contains("unknown"))
    _ => fail("unknown atomic publication outcome was not fatal")
  }

  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-exists")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "Exists fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-exists-parent",
    )
    let child_id = "subagent-audit-exists-child"
    let audit_dir = data_dir + "/subagent-audits"
    @fs.mkdir(audit_dir)
    let destination = audit_dir + "/" + child_id + ".json"
    @fs.write_file(destination, "preserve-existing-destination")
    let outcome = runtime.publish_subagent_audit(
      effect,
      parent_turn_id=1,
      "audit-parent-call",
      child_id,
      "completed",
      native_subagent_audit_test_child_snapshot(child_id),
      None,
    )
    assert_true(outcome is NativeSubagentAuditPublishOutcome::Fatal(_))
    assert_eq(
      @fs.read_file(destination).text(),
      "preserve-existing-destination",
    )
    let parent = runtime.api
      .invoke("session_get", { "session_id": "audit-exists-parent" })
      .unwrap()
    assert_eq(string_field(parent, "status"), Some("running"))
    assert_true(runtime.api.take_typed_effects().is_empty())
  }
}

///|
async test "injected atomic failures interrupt parents, skip hooks, and never replay" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-fault-matrix")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let faults : Array[(String, NativeSubagentAuditAtomicFault, Int32)] = [
      ("exists", NativeSubagentAuditAtomicFault::Exists, 1),
      ("failed", NativeSubagentAuditAtomicFault::Failed, 0),
      ("unknown", NativeSubagentAuditAtomicFault::OutcomeUnknown, 0),
      (
        "unknown-after-write",
        NativeSubagentAuditAtomicFault::OutcomeUnknownAfterWrite,
        1,
      ),
    ]
    for (label, fault, expected_entries) in faults {
      let workspace = fixture + "/" + label + "-workspace"
      let data_dir = fixture + "/" + label + "-data"
      @fs.mkdir(workspace)
      @fs.write_file(workspace + "/README.md", "atomic fault fixture\n")
      let hooks_path = fixture + "/" + label + "-hooks.json"
      @fs.write_file(
        hooks_path,
        @utf8.encode(native_subagent_audit_fault_hook_config()),
      )
      let runtime = native_subagent_audit_demo_runtime(
        data_dir,
        workspace,
        true,
        hooks_config_path=Some(hooks_path),
      )
      let session_id = "audit-fault-" + label + "-parent"
      let effect = native_subagent_audit_demo_parent_tool(runtime, session_id)
      let result = runtime.run_tool_effect(effect, audit_fault=Some(fault))
      assert_true(result is Err(_))
      let parent = runtime.api
        .invoke("session_get", { "session_id": session_id })
        .unwrap()
      assert_eq(string_field(parent, "status"), Some("failed"))
      let events = match object_field(parent, "events") {
        Some(Json::Array(values)) => values
        _ => fail("faulted parent omitted its event log")
      }
      assert_eq(
        events
        .filter(event => {
          string_field(event, "type") == Some("session/interrupted")
        })
        .length(),
        1,
      )
      assert_eq(
        events
        .filter(event => {
          let data = object_field(event, "data").unwrap_or(Json::null())
          string_field(event, "type") == Some("tool/completed") &&
          string_field(data, "source") == Some("interrupted") &&
          string_field(data, "call_id") == Some("audit-parent-call")
        })
        .length(),
        1,
      )
      assert_false(@fs.exists(workspace + "/post-tool-count"))
      assert_true(runtime.api.take_typed_effects().is_empty())
      let event_count = events.length()
      let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
      let entries = audit_root.list_directory(".").unwrap()
      assert_eq(entries.length(), expected_entries)
      for (name, kind) in entries {
        assert_eq(kind, "file")
        let content = @fs.read_file(data_dir + "/subagent-audits/" + name).text()
        if fault is NativeSubagentAuditAtomicFault::Exists {
          assert_eq(content, "injected existing audit")
        } else {
          assert_true(native_subagent_audit_decode(content) is Ok(_))
        }
      }
      audit_root.close()
      runtime.close().unwrap()

      let reopened = native_subagent_audit_demo_runtime(
        data_dir,
        workspace,
        false,
        hooks_config_path=Some(hooks_path),
      )
      let restored = reopened.api
        .invoke("session_get", { "session_id": session_id })
        .unwrap()
      assert_eq(string_field(restored, "status"), Some("failed"))
      assert_eq(
        match object_field(restored, "events") {
          Some(Json::Array(values)) => values.length()
          _ => fail("restored faulted parent omitted events")
        },
        event_count,
      )
      assert_true(reopened.api.take_typed_effects().is_empty())
      assert_false(@fs.exists(workspace + "/post-tool-count"))
      let reopened_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
      assert_eq(
        reopened_root.list_directory(".").unwrap().length(),
        expected_entries,
      )
      reopened_root.close()
      reopened.close().unwrap()
    }
  }
}

///|
async test "fatal interruption and cancellation obey gate order exactly once" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-interrupt-race")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })

    let cancelled_session = "audit-interrupt-cancel-first"
    let cancelled_effect = native_subagent_audit_demo_parent_tool(
      runtime, cancelled_session,
    )
    runtime.gate.acquire()
    let first_gate_held = Ref(true)
    group.add_defer(() => {
      if first_gate_held.val {
        first_gate_held.val = false
        runtime.gate.release()
      }
    })
    let cancellation_first = group.spawn(
      async fn() {
        runtime.invoke("session_cancel", { "session_id": cancelled_session })
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { cancellation_first.wait() })
      is None,
    )
    let interruption_second = group.spawn(
      async fn() {
        runtime.interrupt_for_subagent_audit_failure(
          cancelled_effect,
          1,
          "audit-parent-call",
          None,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { interruption_second.wait() })
      is None,
    )
    runtime.gate.release()
    first_gate_held.val = false
    let (cancelled, cancel_effects) = match cancellation_first.wait() {
      Ok(value) => value
      _ => fail("cancellation queued ahead of fatal interruption failed")
    }
    assert_true(cancel_effects.is_empty())
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))
    assert_true(interruption_second.wait() is Ok(false))
    let cancelled_events = match object_field(cancelled, "events") {
      Some(Json::Array(values)) => values
      _ => fail("cancelled parent omitted events")
    }
    assert_eq(
      cancelled_events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      0,
    )
    assert_eq(
      cancelled_events
      .filter(event => {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(event, "type") == Some("tool/completed") &&
        string_field(data, "source") == Some("interrupted")
      })
      .length(),
      1,
    )

    let interrupted_session = "audit-interrupt-fatal-first"
    let interrupted_effect = native_subagent_audit_demo_parent_tool(
      runtime, interrupted_session,
    )
    runtime.gate.acquire()
    let second_gate_held = Ref(true)
    group.add_defer(() => {
      if second_gate_held.val {
        second_gate_held.val = false
        runtime.gate.release()
      }
    })
    let interruption_first = group.spawn(
      async fn() {
        runtime.interrupt_for_subagent_audit_failure(
          interrupted_effect,
          1,
          "audit-parent-call",
          None,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { interruption_first.wait() })
      is None,
    )
    let cancellation_second = group.spawn(
      async fn() {
        runtime.invoke("session_cancel", { "session_id": interrupted_session })
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { cancellation_second.wait() })
      is None,
    )
    runtime.gate.release()
    second_gate_held.val = false
    assert_true(interruption_first.wait() is Ok(true))
    let (failed, failed_effects) = match cancellation_second.wait() {
      Ok(value) => value
      _ => fail("cancellation queued after fatal interruption failed")
    }
    assert_true(failed_effects.is_empty())
    assert_eq(string_field(failed, "status"), Some("failed"))
    let failed_events = match object_field(failed, "events") {
      Some(Json::Array(values)) => values
      _ => fail("interrupted parent omitted events")
    }
    assert_eq(
      failed_events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      1,
    )
    assert_eq(
      failed_events
      .filter(event => {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(event, "type") == Some("tool/completed") &&
        string_field(data, "source") == Some("interrupted")
      })
      .length(),
      1,
    )
    assert_true(runtime.api.take_typed_effects().is_empty())
  }
}

///|
async test "direct audit publication timeout while waiting for the gate writes nothing" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-timeout-gate")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "timeout fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-timeout-parent",
    )
    let child_id = "subagent-audit-timeout-child"
    let snapshot = native_subagent_audit_test_child_snapshot(child_id)
    let root = runtime.open_subagent_audit_root().unwrap()
    root.close()
    runtime.gate.acquire()
    let gate_held = Ref(true)
    group.add_defer(() => {
      if gate_held.val {
        gate_held.val = false
        runtime.gate.release()
      }
    })
    let timed_out = @async.with_timeout_opt(250, async fn() {
      runtime.publish_subagent_audit(
        effect,
        parent_turn_id=1,
        "audit-parent-call",
        child_id,
        "completed",
        snapshot,
        None,
      )
    })
    assert_true(timed_out is None)
    runtime.gate.release()
    gate_held.val = false
    assert_true(@fs.exists(data_dir + "/subagent-audits"))
    let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    assert_true(audit_root.list_directory(".").unwrap().is_empty())
    audit_root.close()
    let gate_available = @async.with_timeout_opt(100, async fn() {
      runtime.gate.acquire()
    })
    assert_true(gate_available is Some(_))
    runtime.gate.release()
  }
}

///|
async test "accepted cancellation queued before audit publication prevents a file" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-cancel-before")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "cancel-before fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "audit-cancel-before-parent"
    let effect = native_subagent_audit_demo_parent_tool(runtime, session_id)
    let child_id = "subagent-audit-cancel-before-child"
    let snapshot = native_subagent_audit_test_child_snapshot(child_id)
    let root = runtime.open_subagent_audit_root().unwrap()
    root.close()
    runtime.gate.acquire()
    let gate_held = Ref(true)
    group.add_defer(() => {
      if gate_held.val {
        gate_held.val = false
        runtime.gate.release()
      }
    })
    let cancel_task = group.spawn(
      async fn() {
        runtime.invoke("session_cancel", { "session_id": session_id })
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { cancel_task.wait() }) is None,
    )
    let publication_task = group.spawn(
      async fn() {
        runtime.publish_subagent_audit(
          effect,
          parent_turn_id=1,
          "audit-parent-call",
          child_id,
          "completed",
          snapshot,
          None,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { publication_task.wait() })
      is None,
    )
    runtime.gate.release()
    gate_held.val = false
    let (cancelled, cancel_effects) = match cancel_task.wait() {
      Ok(value) => value
      _ => fail("queued session_cancel failed")
    }
    assert_true(cancel_effects.is_empty())
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))
    assert_true(
      publication_task.wait() is NativeSubagentAuditPublishOutcome::Abandoned(_),
    )
    let parent = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(parent, "status"), Some("cancelled"))
    let events = match object_field(parent, "events") {
      Some(Json::Array(values)) => values
      _ => fail("cancelled parent omitted its event log")
    }
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      0,
    )
    let interrupted = events.filter(event => {
      let data = object_field(event, "data").unwrap_or(Json::null())
      string_field(event, "type") == Some("tool/completed") &&
      string_field(data, "source") == Some("interrupted") &&
      string_field(data, "call_id") == Some("audit-parent-call")
    })
    assert_eq(interrupted.length(), 1)
    let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    assert_true(audit_root.list_directory(".").unwrap().is_empty())
    audit_root.close()
  }
}

///|
async test "publication queued before cancellation leaves one inert orphan" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-cancel-after")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/README.md", "cancel-after fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "audit-cancel-after-parent"
    let effect = native_subagent_audit_demo_parent_tool(runtime, session_id)
    let child_id = "subagent-audit-cancel-after-child"
    let snapshot = native_subagent_audit_test_child_snapshot(child_id)
    let root = runtime.open_subagent_audit_root().unwrap()
    root.close()
    runtime.gate.acquire()
    let gate_held = Ref(true)
    group.add_defer(() => {
      if gate_held.val {
        gate_held.val = false
        runtime.gate.release()
      }
    })
    let publication_task = group.spawn(
      async fn() {
        runtime.publish_subagent_audit(
          effect,
          parent_turn_id=1,
          "audit-parent-call",
          child_id,
          "completed",
          snapshot,
          None,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    assert_true(
      @async.with_timeout_opt(50, async fn() { publication_task.wait() })
      is None,
    )
    runtime.gate.release()
    gate_held.val = false
    match publication_task.wait() {
      NativeSubagentAuditPublishOutcome::Published => ()
      NativeSubagentAuditPublishOutcome::Fatal(error) =>
        fail("audit publication failed: " + error)
      NativeSubagentAuditPublishOutcome::Abandoned(error) =>
        fail("audit publication was abandoned: " + error)
    }
    let (cancelled, cancel_effects) = match
      runtime.invoke("session_cancel", { "session_id": session_id }) {
      Ok(value) => value
      _ => fail("session_cancel after publication failed")
    }
    assert_true(cancel_effects.is_empty())
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))
    assert_false(
      runtime.confirm_subagent_audit_publication(
        effect,
        1,
        "audit-parent-call",
        None,
      ),
    )
    let parent = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(parent, "status"), Some("cancelled"))
    let events = match object_field(parent, "events") {
      Some(Json::Array(values)) => values
      _ => fail("cancelled parent omitted its event log")
    }
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      0,
    )
    let interrupted = events.filter(event => {
      let data = object_field(event, "data").unwrap_or(Json::null())
      string_field(event, "type") == Some("tool/completed") &&
      string_field(data, "source") == Some("interrupted") &&
      string_field(data, "call_id") == Some("audit-parent-call")
    })
    assert_eq(interrupted.length(), 1)
    let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    let entries = audit_root.list_directory(".").unwrap()
    assert_eq(entries.length(), 1)
    assert_eq(entries[0].1, "file")
    assert_true(entries[0].0.has_suffix(".json"))
    let audit_path = data_dir + "/subagent-audits/" + entries[0].0
    assert_true(@fs.exists(audit_path))
    let record = native_subagent_audit_decode(@fs.read_file(audit_path).text())
    assert_true(record is Ok(_))
    assert_true(runtime.api.take_typed_effects().is_empty())
    audit_root.close()
  }
}

///|
async test "published audit survives a failed parent checkpoint and restore does not replay" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-checkpoint-orphan")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data_dir = workspace + "/data"
    @fs.write_file(workspace + "/README.md", "checkpoint fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    let effect = native_subagent_audit_demo_parent_tool(
      runtime, "audit-checkpoint-parent",
    )
    let tool_result = match
      runtime.run_subagent_tool(effect, parent_turn_id=1, control=None) {
      NativeSubagentToolOutcome::Result(value) => value
      NativeSubagentToolOutcome::Fatal(error) => fail(error)
      NativeSubagentToolOutcome::Abandoned(error) => fail(error)
    }
    @fs.rename(data_dir + "/sessions.json", data_dir + "/sessions.saved")
    @fs.mkdir(data_dir + "/sessions.json")
    let tool_outcome = runtime.finish_tool_effect(
      effect, "audit-checkpoint-parent", tool_result,
    )
    assert_true(tool_outcome is Err(_))
    assert_true(@fs.exists(data_dir + "/sessions.saved"))
    let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    let entries = audit_root.list_directory(".").unwrap()
    assert_eq(entries.length(), 1)
    assert_true(entries[0].0.has_suffix(".json"))
    let audit_path = data_dir + "/subagent-audits/" + entries[0].0
    let record = native_subagent_audit_decode(@fs.read_file(audit_path).text())
    assert_true(record is Ok(_))
    audit_root.close()
    assert_true(runtime.close() is Err(_))

    @fs.rmdir(data_dir + "/sessions.json", recursive=true)
    @fs.rename(data_dir + "/sessions.saved", data_dir + "/sessions.json")
    let reopened = native_subagent_audit_demo_runtime(
      data_dir, workspace, false,
    )
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let parent = reopened.api
      .invoke("session_get", { "session_id": "audit-checkpoint-parent" })
      .unwrap()
    assert_eq(string_field(parent, "status"), Some("failed"))
    let events = match object_field(parent, "events") {
      Some(Json::Array(values)) => values
      _ => fail("restored parent omitted its event log")
    }
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      1,
    )
    assert_eq(
      events
      .filter(event => {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(event, "type") == Some("tool/completed") &&
        string_field(data, "source") == Some("interrupted") &&
        string_field(data, "call_id") == Some("audit-parent-call")
      })
      .length(),
      1,
    )
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_true(@fs.exists(audit_path))
  }
}

///|
async test "fatal audit outcome leaves an uncertain remote receipt that never replays" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-remote-uncertain")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.mkdir(data_dir)
    @fs.write_file(workspace + "/README.md", "remote fixture\n")
    let runtime = native_subagent_audit_demo_runtime(data_dir, workspace, true)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "audit-remote-uncertain-parent"
    ignore(
      runtime
      .invoke("session_create", {
        "id": session_id,
        "title": "Remote audit failure",
      })
      .unwrap(),
    )
    let identity = runtime.state.identity_key
    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "abcdef0123456789abcdef0123456789",
    ).unwrap()
    let command = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "Use a foreground child to inspect README.md.",
    )
    let (accepted, effects, should_start, control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_true(should_start)
    assert_eq(string_field(accepted, "status"), Some("accepted"))
    assert_eq(effects.length(), 1)
    let accepted_revision = int_field(accepted, "accepted_revision").unwrap()
    runtime.run_command_job(
      command_id,
      identity,
      accepted_revision,
      effects,
      control~,
      audit_fault=Some(NativeSubagentAuditAtomicFault::OutcomeUnknownAfterWrite),
    )
    let receipt = runtime.find_receipt(command_id, identity).unwrap().unwrap()
    assert_eq(string_field(receipt, "status"), Some("uncertain"))
    let parent = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(parent, "status"), Some("failed"))
    let events = match object_field(parent, "events") {
      Some(Json::Array(values)) => values
      _ => fail("uncertain remote parent omitted its event log")
    }
    let event_count = events.length()
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("session/interrupted")
      })
      .length(),
      1,
    )
    assert_eq(
      events
      .filter(event => {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(event, "type") == Some("tool/completed") &&
        string_field(data, "source") == Some("interrupted")
      })
      .length(),
      1,
    )
    let audit_root = SafeRoot::open(data_dir + "/subagent-audits").unwrap()
    let audit_entries = audit_root.list_directory(".").unwrap()
    assert_eq(audit_entries.length(), 1)
    assert_true(audit_entries[0].0.has_suffix(".json"))
    let orphan_path = data_dir + "/subagent-audits/" + audit_entries[0].0
    let orphan_record = native_subagent_audit_decode(
      @fs.read_file(orphan_path).text(),
    )
    assert_true(orphan_record is Ok(_))
    let retry = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "Use a foreground child to inspect README.md.",
    )
    let (replayed, replay_effects, replay_started, _) = runtime
      .accept_remote_command(retry, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("uncertain"))
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)
    assert_eq(audit_root.list_directory(".").unwrap().length(), 1)
    let parent_after_retry = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    let events_after_retry = match object_field(parent_after_retry, "events") {
      Some(Json::Array(values)) => values
      _ => fail("retried remote parent omitted its event log")
    }
    assert_eq(events_after_retry.length(), event_count)
    audit_root.close()
  }
}
