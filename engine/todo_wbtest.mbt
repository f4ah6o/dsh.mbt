///|
fn todo_test_tools() -> Array[Json] {
  let tools = test_tools()
  tools.push({
    "name": "todo_write",
    "description": "Replace the complete visible task list.",
    "effect": "session",
    "input_schema": todo_write_input_schema(),
  })
  tools
}

///|
fn todo_get(value : Json, key : String) -> Json raise EngineError {
  required_field(value, key)
}

///|
fn todo_string(value : Json, key : String) -> String {
  try {
    match required_field(value, key) {
      Json::String(text) => text
      _ => ""
    }
  } catch {
    _ => ""
  }
}

///|
fn todo_array(value : Json, key : String) -> Array[Json] {
  try {
    match required_field(value, key) {
      Json::Array(values) => values
      _ => []
    }
  } catch {
    _ => []
  }
}

///|
fn todo_event_index(events : Array[Json], event_type : String) -> Int? {
  for index in 0..<events.length() {
    if todo_string(events[index], "type") == event_type {
      return Some(index)
    }
  }
  None
}

///|
fn todo_event_record(
  seq : Int,
  event_type : String,
  turn_id : Json,
  step : Json,
  data : Json,
) -> Json {
  object([
    ("seq", integer(seq)),
    ("type", Json::string(event_type)),
    ("turn_id", turn_id),
    ("step", step),
    ("data", data),
  ])
}

///|
fn todo_count_events(session : Json, event_type : String) -> Int {
  todo_array(session, "events")
  .filter(event => todo_string(event, "type") == event_type)
  .length()
}

///|
test "todo_write trimming matches ECMAScript whitespace boundaries" {
  let whitespace_only = object([
    (
      "todos",
      Json::array([
        object([
          (
            "content",
            Json::string(
              "\u0009\u000A\u000B\u000C\u000D\u0020\u00A0\u1680\u2000\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF",
            ),
          ),
          ("status", Json::string("pending")),
        ]),
      ]),
    ),
  ])
  assert_true(checked_todo_write(whitespace_only) is Err(_))

  let duplicate_after_trim = object([
    (
      "todos",
      Json::array([
        object([
          ("content", Json::string("\u00A0Same\u3000")),
          ("status", Json::string("pending")),
        ]),
        object([
          ("content", Json::string("Same")),
          ("status", Json::string("completed")),
        ]),
      ]),
    ),
  ])
  assert_true(checked_todo_write(duplicate_after_trim) is Err(_))

  let canonical_and_preserved = object([
    (
      "todos",
      Json::array([
        object([
          ("content", Json::string("\u00A0Canonical\u3000")),
          ("status", Json::string("pending")),
        ]),
        object([
          ("content", Json::string("\u0085kept\u200B")),
          ("status", Json::string("completed")),
        ]),
      ]),
    ),
  ])
  match checked_todo_write(canonical_and_preserved) {
    Ok(items) =>
      assert_eq(items, [
        { "content": "Canonical", "status": "pending" },
        { "content": "\u0085kept\u200B", "status": "completed" },
      ])
    Err(message) => abort(message)
  }
}

///|
fn todo_create_and_send(engine : Engine, id : String) -> String {
  ignore(
    success(engine.invoke("session_create", object([("id", Json::string(id))]))),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string(id)),
          ("prompt", Json::string("Plan a small implementation")),
        ]),
      ),
    ),
  )
  let effects = engine.take_effects()
  if effects.length() != 1 {
    abort("todo test expected one provider effect")
  }
  id_of(effects[0])
}

///|
fn todo_session(engine : Engine, id : String) -> Json {
  success(
    engine.invoke("session_get", object([("session_id", Json::string(id))])),
  )
}

///|
fn todo_finish_prompt_turn(
  engine : Engine,
  id : String,
  prompt : String,
) -> Unit {
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string(id)),
          ("prompt", Json::string(prompt)),
        ]),
      ),
    ),
  )
  let effects = engine.take_effects()
  if effects.length() != 1 || todo_string(effects[0], "kind") != "llm" {
    abort("Todo capacity test expected one provider effect")
  }
  ignore(success(engine.complete(id_of(effects[0]), stop_response("done"))))
}

///|
fn todo_capacity_trial(
  base : Json,
  id : String,
  prompt_length : Int,
  response_length : Int,
) -> (Int, Json)? {
  let trial = Engine::new(todo_test_tools())
  match trial.restore(base) {
    Ok(_) => ()
    Err(error) => abort("Todo capacity base snapshot did not restore: " + error)
  }
  let prompt = "p".repeat(prompt_length)
  match
    trial.invoke(
      "session_send",
      object([
        ("session_id", Json::string(id)),
        ("prompt", Json::string(prompt)),
      ]),
    ) {
    Err(_) => return None
    Ok(_) => ()
  }
  let effects = trial.take_effects()
  if effects.length() != 1 {
    return None
  }
  let completed = match
    trial.complete(
      id_of(effects[0]),
      stop_response("d".repeat(response_length)),
    ) {
    Err(_) => return None
    Ok(value) => value
  }
  if todo_string(completed, "status") != "completed" {
    return None
  }
  Some((session_capacity_length(todo_session(trial, id)), trial.snapshot()))
}

///|
fn todo_snapshot_without_projection(snapshot : Json) -> Json raise EngineError {
  let copied = checked_copy(snapshot)
  let snapshot_fields = fields(copied)
  let sessions = array_value(required_field(copied, "sessions"), "sessions", 32)
  if sessions.length() != 1 {
    abort("Todo capacity fixture expected one session")
  }
  let session_fields = fields(sessions[0])
  ignore(session_fields.remove("todos"))
  sessions[0] = Json::object(session_fields)
  snapshot_fields["sessions"] = Json::array(sessions)
  Json::object(snapshot_fields)
}

///|
fn todo_snapshot_with_projection(
  snapshot : Json,
  projection : Json,
) -> Json raise EngineError {
  let copied = checked_copy(snapshot)
  let copied_fields = fields(copied)
  let sessions = array_value(required_field(copied, "sessions"), "sessions", 32)
  if sessions.length() != 1 {
    abort("Todo capacity fixture expected one session")
  }
  let session_fields = fields(sessions[0])
  session_fields["todos"] = projection
  sessions[0] = Json::object(session_fields)
  copied_fields["sessions"] = Json::array(sessions)
  Json::object(copied_fields)
}

///|
test "legacy sessions at the capacity boundary reopen with null todo metadata" {
  let engine = Engine::new(todo_test_tools())
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("todo-capacity-legacy"))]),
      ),
    ),
  )
  let full_prompt = "p".repeat(16384)
  for _ in 0..<7 {
    todo_finish_prompt_turn(engine, "todo-capacity-legacy", full_prompt)
  }
  let base = engine.snapshot()
  let base_size = session_capacity_length(
    todo_session(engine, "todo-capacity-legacy"),
  )
  assert_true(base_size < SESSION_CAPACITY)
  let mut prompt_low = 1
  let mut prompt_high = 16384
  while prompt_low < prompt_high {
    let middle = (prompt_low + prompt_high + 1) / 2
    match todo_capacity_trial(base, "todo-capacity-legacy", middle, 4) {
      Some((size, _)) if size <= SESSION_CAPACITY => prompt_low = middle
      _ => prompt_high = middle - 1
    }
  }
  assert_true(
    todo_capacity_trial(base, "todo-capacity-legacy", prompt_low, 4) is Some(_),
  )

  let mut response_low = 4
  let mut response_high = 16384
  while response_low < response_high {
    let middle = (response_low + response_high + 1) / 2
    match
      todo_capacity_trial(base, "todo-capacity-legacy", prompt_low, middle) {
      Some((size, _)) if size <= SESSION_CAPACITY => response_low = middle
      _ => response_high = middle - 1
    }
  }
  let (legacy_size, new_snapshot) = match
    todo_capacity_trial(base, "todo-capacity-legacy", prompt_low, response_low) {
    Some(value) => value
    None => abort("Todo capacity test could not create a boundary session")
  }
  assert_true(legacy_size <= SESSION_CAPACITY)
  assert_eq(legacy_size, SESSION_CAPACITY - 1)

  let old_snapshot = todo_snapshot_without_projection(new_snapshot)
  let old_session = todo_array(old_snapshot, "sessions")[0]
  assert_true(fields(old_session).get("todos") is None)
  assert_eq(session_capacity_length(old_session), legacy_size)
  let restored = Engine::new(todo_test_tools())
  assert_eq(restored.restore(old_snapshot), Ok(()))
  let current = restored.snapshot()
  let current_session = todo_array(current, "sessions")[0]
  assert_eq(todo_get(current_session, "todos"), Json::null())
  assert_eq(session_capacity_length(current_session), legacy_size)
  assert_eq(current_session.stringify().length(), legacy_size + 13)

  let reopened = Engine::new(todo_test_tools())
  assert_eq(reopened.restore(current), Ok(()))
  assert_eq(reopened.snapshot(), current)
  let before_overflow = reopened.snapshot().stringify()
  assert_true(
    reopened.invoke(
      "session_send",
      object([
        ("session_id", Json::string("todo-capacity-legacy")),
        ("prompt", Json::string("must not fit")),
      ]),
    )
    is Err(_),
  )
  assert_eq(reopened.snapshot().stringify(), before_overflow)
  assert_true(reopened.take_effects().is_empty())
  let overflow = todo_snapshot_with_projection(
    current,
    Json::array([
      object([
        ("content", Json::string("extra counted task")),
        ("status", Json::string("completed")),
      ]),
    ]),
  )
  assert_true(
    session_capacity_length(todo_array(overflow, "sessions")[0]) >
    SESSION_CAPACITY,
  )
  match reopened.restore(overflow) {
    Err(error) =>
      assert_eq(error, "Snapshot session exceeds the 262144-character capacity")
    Ok(_) => abort("Todo capacity restore accepted a genuine overflow")
  }
  assert_eq(reopened.snapshot().stringify(), before_overflow)
}

///|
fn todo_snapshot_forged_event(
  snapshot : Json,
  change : String,
) -> Json raise EngineError {
  let copied = checked_copy(snapshot)
  let sessions = array_value(required_field(copied, "sessions"), "sessions", 32)
  let session = sessions[0]
  let session_fields = fields(session)
  let events = array_value(required_field(session, "events"), "events", 32768)
  let target = todo_event_index(events, "todo/write")
  let index = match target {
    Some(value) => value
    None => raise Invalid("Todo test snapshot has no todo/write event")
  }
  if change == "call_id" {
    let event_fields = fields(events[index])
    let data_fields = fields(required_field(events[index], "data"))
    data_fields["call_id"] = Json::string("unrelated-call")
    event_fields["data"] = Json::object(data_fields)
    events[index] = Json::object(event_fields)
  } else if change == "approval" {
    let call_data = required_field(events[index - 1], "data")
    let call_id = required_field(call_data, "id")
    let arguments = parse_arguments(required_string(call_data, "arguments"))
    let target_fields = fields(events[index])
    let prefix : Array[Json] = []
    for prefix_index in 0..<index {
      prefix.push(events[prefix_index])
    }
    prefix.push(
      todo_event_record(
        index,
        "tool/approval/requested",
        required_field(events[index], "turn_id"),
        required_field(events[index], "step"),
        object([
          ("call_id", call_id),
          ("name", Json::string("todo_write")),
          ("arguments", arguments),
        ]),
      ),
    )
    session_fields["events"] = Json::array(prefix)
    session_fields["status"] = Json::string("awaiting_approval")
    session_fields["pending_approval"] = object([
      ("call_id", call_id),
      ("name", Json::string("todo_write")),
      ("arguments", arguments),
    ])
    ignore(target_fields)
  } else if change == "request" {
    let call_data = required_field(events[index - 1], "data")
    let call_id = required_field(call_data, "id")
    let arguments = parse_arguments(required_string(call_data, "arguments"))
    let turn_id = required_field(events[index], "turn_id")
    let step = required_field(events[index], "step")
    let prefix : Array[Json] = []
    for prefix_index in 0..<index {
      prefix.push(events[prefix_index])
    }
    prefix.push(
      todo_event_record(
        index,
        "tool/approval/requested",
        turn_id,
        step,
        object([
          ("call_id", call_id),
          ("name", Json::string("todo_write")),
          ("arguments", arguments),
        ]),
      ),
    )
    prefix.push(
      todo_event_record(
        index + 1,
        "tool/approval/resolved",
        turn_id,
        step,
        object([("call_id", call_id), ("approved", Json::boolean(true))]),
      ),
    )
    let next_effect = int_value(
      required_field(copied, "next_effect"),
      "next_effect",
      1,
      1000000000,
    )
    let effect_id = "effect-" + next_effect.to_string()
    prefix.push(
      todo_event_record(
        index + 2,
        "tool/request",
        turn_id,
        step,
        object([("call_id", call_id), ("effect_id", Json::string(effect_id))]),
      ),
    )
    session_fields["events"] = Json::array(prefix)
    session_fields["status"] = Json::string("running")
    ignore(session_fields.remove("pending_approval"))
    fields(copied)["next_effect"] = integer(next_effect + 1)
  } else if change == "remove" {
    let kept : Array[Json] = []
    for event in events {
      if todo_string(event, "type") != "todo/write" {
        let event_fields = fields(event)
        event_fields["seq"] = integer(kept.length())
        kept.push(Json::object(event_fields))
      }
    }
    session_fields["events"] = Json::array(kept)
  } else if change == "completion" {
    let completion : Int? = {
      let mut found : Int? = None
      for event_index in 0..<events.length() {
        let event = events[event_index]
        if todo_string(event, "type") == "tool/completed" &&
          todo_string(todo_get(event, "data"), "source") == "session" {
          found = Some(event_index)
          break
        }
      }
      found
    }
    let completion_index = match completion {
      Some(value) => value
      None => raise Invalid("Todo test snapshot has no internal completion")
    }
    let event_fields = fields(events[completion_index])
    let data_fields = fields(required_field(events[completion_index], "data"))
    data_fields["content"] = Json::string("different result")
    event_fields["data"] = Json::object(data_fields)
    events[completion_index] = Json::object(event_fields)
  }
  sessions[0] = Json::object(session_fields)
  let copied_fields = fields(copied)
  copied_fields["sessions"] = Json::array(sessions)
  Json::object(copied_fields)
}

///|
test "todo_write replaces whole lists at an exclusive barrier and clears only when a new turn starts" {
  let engine = Engine::new(todo_test_tools())
  let llm_id = todo_create_and_send(engine, "todo-replacement")
  let first = "{\"todos\":[{\"content\":\" Plan \",\"status\":\"in_progress\"},{\"content\":\"Test\",\"status\":\"pending\"}]}"
  let second = "{\"todos\":[{\"content\":\"Ship\",\"status\":\"completed\"}]}"
  let projected = success(
    engine.complete(
      llm_id,
      calls_response([
        ("todo-1", "todo_write", first),
        ("todo-2", "todo_write", second),
      ]),
    ),
  )
  let expected : Json = [{ "content": "Ship", "status": "completed" }]
  assert_eq(todo_get(projected, "todos"), expected)
  assert_eq(todo_count_events(projected, "todo/write"), 2)
  assert_eq(todo_count_events(projected, "tool/request"), 0)
  assert_eq(todo_count_events(projected, "tool/approval/requested"), 0)
  let completions = todo_array(projected, "events").filter(event => {
    todo_string(event, "type") == "tool/completed" &&
    todo_string(todo_get(event, "data"), "source") == "session"
  })
  assert_eq(completions.length(), 2)
  assert_eq(
    todo_string(todo_get(completions[1], "data"), "content"),
    "Updated todo list: 0 pending, 0 in progress, 1 completed.",
  )
  let follow_up = engine.take_effects()
  assert_eq(follow_up.length(), 1)
  assert_eq(todo_string(follow_up[0], "kind"), "llm")
  let completed = success(
    engine.complete(id_of(follow_up[0]), stop_response("Done")),
  )
  assert_eq(todo_get(completed, "todos"), expected)
  assert_eq(todo_string(completed, "status"), "completed")
  let next_turn = success(
    engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string("todo-replacement")),
        ("prompt", Json::string("Start another task")),
      ]),
    ),
  )
  assert_eq(todo_get(next_turn, "todos"), Json::null())
}

///|
test "invalid todo lists produce tool errors without changing the current projection" {
  let engine = Engine::new(todo_test_tools())
  let llm_id = todo_create_and_send(engine, "todo-validation")
  let too_many : Array[Json] = []
  for index in 0..<=TODO_MAX_ITEMS {
    too_many.push({
      "content": "step-" + index.to_string(),
      "status": "pending",
    })
  }
  let calls = [
    (
      "todo-valid", "todo_write", "{\"todos\":[{\"content\":\"Known task\",\"status\":\"pending\"}]}",
    ),
    (
      "todo-blank", "todo_write", "{\"todos\":[{\"content\":\"  \",\"status\":\"pending\"}]}",
    ),
    (
      "todo-duplicate", "todo_write", "{\"todos\":[{\"content\":\"Same\",\"status\":\"pending\"},{\"content\":\" Same \",\"status\":\"completed\"}]}",
    ),
    (
      "todo-parallel", "todo_write", "{\"todos\":[{\"content\":\"One\",\"status\":\"in_progress\"},{\"content\":\"Two\",\"status\":\"in_progress\"}]}",
    ),
    (
      "todo-extra", "todo_write", "{\"todos\":[{\"content\":\"One\",\"status\":\"pending\",\"id\":\"extra\"}]}",
    ),
    (
      "todo-too-many",
      "todo_write",
      object([("todos", Json::array(too_many))]).stringify(),
    ),
  ]
  let result = success(engine.complete(llm_id, calls_response(calls)))
  assert_eq(todo_get(result, "todos"), [
    { "content": "Known task", "status": "pending" },
  ])
  assert_eq(todo_count_events(result, "todo/write"), 1)
  let errors = todo_array(result, "events").filter(event => {
    todo_string(event, "type") == "tool/result" &&
    todo_get(event, "data") is { "is_error": Json::True, .. }
  })
  assert_eq(errors.length(), 5)
  assert_true(
    todo_array(result, "events").any(event => {
      todo_string(event, "type") == "tool/completed" &&
      todo_string(todo_get(event, "data"), "source") == "local" &&
      todo_string(todo_get(event, "data"), "call_id") == "todo-extra"
    }),
  )
}

///|
test "todo state is isolated, survives fork and reopen, and interrupted follow-up is not replayed" {
  let engine = Engine::new(todo_test_tools())
  let a_llm = todo_create_and_send(engine, "todo-session-a")
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("todo-session-b"))]),
      ),
    ),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string("todo-session-b")),
          ("prompt", Json::string("Do not share the other list")),
        ]),
      ),
    ),
  )
  let b_effects = engine.take_effects()
  assert_eq(b_effects.length(), 1)
  let a_response = success(
    engine.complete(
      a_llm,
      calls_response([
        (
          "todo-a-call", "todo_write", "{\"todos\":[{\"content\":\"A only\",\"status\":\"in_progress\"}]}",
        ),
      ]),
    ),
  )
  let a_todos = todo_get(a_response, "todos")
  assert_eq(
    todo_get(todo_session(engine, "todo-session-b"), "todos"),
    Json::null(),
  )
  let a_follow_up = engine.take_effects()
  assert_eq(a_follow_up.length(), 1)
  let pending_snapshot = engine.snapshot()
  let recovered = Engine::new(todo_test_tools())
  assert_eq(recovered.restore(pending_snapshot), Ok(()))
  let recovered_a = todo_session(recovered, "todo-session-a")
  assert_eq(todo_get(recovered_a, "todos"), a_todos)
  assert_eq(todo_string(recovered_a, "status"), "failed")
  assert_eq(todo_count_events(recovered_a, "todo/write"), 1)
  assert_true(recovered.take_effects().is_empty())

  ignore(
    success(engine.complete(id_of(a_follow_up[0]), stop_response("Finished A"))),
  )
  ignore(
    success(engine.complete(id_of(b_effects[0]), stop_response("Finished B"))),
  )
  let forked = success(
    engine.invoke(
      "session_fork",
      object([
        ("session_id", Json::string("todo-session-a")),
        ("id", Json::string("todo-session-a-fork")),
      ]),
    ),
  )
  assert_eq(todo_get(forked, "todos"), a_todos)
  let settled_snapshot = engine.snapshot()
  let reopened = Engine::new(todo_test_tools())
  assert_eq(reopened.restore(settled_snapshot), Ok(()))
  assert_eq(
    todo_get(todo_session(reopened, "todo-session-a-fork"), "todos"),
    a_todos,
  )
  let fork_next_turn = success(
    reopened.invoke(
      "session_send",
      object([
        ("session_id", Json::string("todo-session-a-fork")),
        ("prompt", Json::string("Continue the branch")),
      ]),
    ),
  )
  assert_eq(todo_get(fork_next_turn, "todos"), Json::null())
}

///|
test "restore requires a todo write to match its call, successful completion, and result" {
  let engine = Engine::new(todo_test_tools())
  let llm_id = todo_create_and_send(engine, "todo-restore-validation")
  let result = success(
    engine.complete(
      llm_id,
      calls_response([
        (
          "todo-restore-call", "todo_write", "{\"todos\":[{\"content\":\"Match this call\",\"status\":\"completed\"}]}",
        ),
      ]),
    ),
  )
  let follow_up = engine.take_effects()
  ignore(success(engine.complete(id_of(follow_up[0]), stop_response("Done"))))
  let snapshot = engine.snapshot()
  let missing = todo_snapshot_forged_event(snapshot, "remove")
  let wrong_call = todo_snapshot_forged_event(snapshot, "call_id")
  let changed_completion = todo_snapshot_forged_event(snapshot, "completion")
  let forged_approval = todo_snapshot_forged_event(snapshot, "approval")
  let forged_effect = todo_snapshot_forged_event(snapshot, "request")
  let restored = Engine::new(todo_test_tools())
  assert_true(restored.restore(missing) is Err(_))
  assert_true(restored.restore(wrong_call) is Err(_))
  assert_true(restored.restore(changed_completion) is Err(_))
  assert_true(restored.restore(forged_approval) is Err(_))
  assert_true(restored.restore(forged_effect) is Err(_))
  assert_eq(restored.restore(snapshot), Ok(()))
  let saved = todo_session(restored, "todo-restore-validation")
  assert_eq(todo_get(saved, "todos"), todo_get(result, "todos"))
  assert_eq(todo_count_events(saved, "todo/write"), 1)
}

///|
test "only the canonical todo_write descriptor may use the session effect" {
  let other_session_tool : Json = {
    "name": "not_todo_write",
    "description": "Attempt to register an arbitrary session tool.",
    "effect": "session",
    "input_schema": todo_write_input_schema(),
  }
  let malformed_todo : Json = {
    "name": "todo_write",
    "description": "Attempt to change the reserved schema.",
    "effect": "session",
    "input_schema": { "type": "object", "properties": {}, "required": [] },
  }
  for tool in [other_session_tool, malformed_todo] {
    let engine = Engine::new([tool])
    assert_true(
      engine.invoke("session_create", object([("id", Json::string("bad"))]))
      is Err(_),
    )
  }
}

///|
test "unstarted todo calls after a live read interrupt and reopen without replay" {
  let engine = Engine::new(todo_test_tools())
  let llm_id = todo_create_and_send(engine, "todo-interrupted-read")
  ignore(
    success(
      engine.complete(
        llm_id,
        calls_response([
          ("read-before-todo", "read", "{\"file_path\":\"note.txt\"}"),
          (
            "todo-after-read", "todo_write", "{\"todos\":[{\"content\":\"Never applied\",\"status\":\"pending\"}]}",
          ),
        ]),
      ),
    ),
  )
  let active_read = engine.take_effects()
  assert_eq(active_read.length(), 1)
  assert_eq(todo_string(active_read[0], "kind"), "tool")
  let pending = engine.snapshot()

  let restored = Engine::new(todo_test_tools())
  assert_eq(restored.restore(pending), Ok(()))
  let restored_session = todo_session(restored, "todo-interrupted-read")
  assert_eq(todo_string(restored_session, "status"), "failed")
  assert_eq(todo_get(restored_session, "todos"), Json::null())
  assert_eq(todo_count_events(restored_session, "todo/write"), 0)
  assert_true(
    todo_array(restored_session, "events").any(event => {
      todo_string(event, "type") == "tool/result" &&
      todo_string(todo_get(event, "data"), "tool_call_id") == "todo-after-read" &&
      todo_get(todo_get(event, "data"), "is_error") == boolean(true)
    }),
  )
  assert_true(restored.take_effects().is_empty())

  ignore(
    success(
      engine.invoke(
        "session_cancel",
        object([("session_id", Json::string("todo-interrupted-read"))]),
      ),
    ),
  )
  let cancelled = engine.snapshot()
  let cancelled_reopen = Engine::new(todo_test_tools())
  assert_eq(cancelled_reopen.restore(cancelled), Ok(()))
  let cancelled_session = todo_session(
    cancelled_reopen, "todo-interrupted-read",
  )
  assert_eq(todo_string(cancelled_session, "status"), "cancelled")
  assert_eq(todo_get(cancelled_session, "todos"), Json::null())
  assert_true(cancelled_reopen.take_effects().is_empty())
}

///|
test "legacy snapshots with a previously unknown todo_write call remain readable" {
  let old_engine = Engine::new(test_tools())
  let llm_id = todo_create_and_send(old_engine, "todo-legacy-unknown")
  let called = success(
    old_engine.complete(
      llm_id,
      calls_response([("legacy-todo-call", "todo_write", "{\"todos\":[]}")]),
    ),
  )
  let follow_up = old_engine.take_effects()
  ignore(
    success(old_engine.complete(id_of(follow_up[0]), stop_response("Done"))),
  )
  let snapshot = checked_copy(old_engine.snapshot())
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let old_session_fields = fields(sessions[0])
  ignore(old_session_fields.remove("todos"))
  sessions[0] = Json::object(old_session_fields)
  let snapshot_fields = fields(snapshot)
  snapshot_fields["sessions"] = Json::array(sessions)
  let newer_engine = Engine::new(todo_test_tools())
  assert_eq(newer_engine.restore(Json::object(snapshot_fields)), Ok(()))
  let restored = todo_session(newer_engine, "todo-legacy-unknown")
  assert_eq(todo_get(restored, "todos"), Json::null())
  assert_true(
    todo_array(restored, "messages").any(message => {
      todo_string(message, "role") == "tool" &&
      todo_string(message, "content") == "Unknown tool: todo_write"
    }),
  )
  ignore(called)
}
