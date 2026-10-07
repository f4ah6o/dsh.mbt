///|
fn fork_input(session_id : String, id? : String) -> Json {
  let values = Map::from_array([("session_id", Json::string(session_id))])
  match id {
    Some(value) => values.set("id", Json::string(value))
    None => ()
  }
  Json::object(values)
}

///|
fn event_with_type(session : Json, kind : String) -> Json {
  let events = array_value(required_field(session, "events"), "events", 32768) catch {
    _ => abort("Session has invalid events")
  }
  let mut index = 0
  while index < events.length() {
    let event = events[index]
    let matches_kind = match event {
      Json::Object(values) => values.get("type") == Some(Json::string(kind))
      _ => false
    }
    if matches_kind {
      return event
    }
    index += 1
  }
  abort("Expected \{kind} event")
}

///|
test "settled fork keeps a validated fixed prefix through parent and child continuation" {
  let (engine, request) = started_engine()
  let source = success(
    engine.complete(id_of(request), stop_response("First answer")),
  )
  let source_before = source
  let child = success(engine.invoke("session_fork", fork_input("test")))
  let child_id = required_string(child, "id")
  assert_eq(child_id, "session-2")
  assert_eq(required_string(child, "parent_session_id"), "test")
  assert_eq(get_status(child), "idle")
  assert_eq(
    required_field(child, "messages"),
    required_field(source, "messages"),
  )
  let source_events = array_value(
    required_field(source, "events"),
    "source events",
    32768,
  )
  let child_events = array_value(
    required_field(child, "events"),
    "child events",
    32768,
  )
  assert_eq(child_events.length(), source_events.length() + 1)
  assert_eq(
    required_string(child_events[source_events.length()], "type"),
    "session/forked",
  )
  let source_request = event_with_type(source, "llm/request")
  let child_request = event_with_type(child, "llm/request")
  let source_effect = required_string(
    required_field(source_request, "data"),
    "effect_id",
  )
  let child_effect = required_string(
    required_field(child_request, "data"),
    "effect_id",
  )
  assert_true(source_effect != child_effect)
  assert_eq(
    success(engine.invoke("session_get", fixture("{\"session_id\":\"test\"}"))),
    source_before,
  )

  // Later parent writes do not change the prefix the child was forked from.
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Parent continues\"}"),
      ),
    ),
  )
  let parent_followup = engine.take_effects()
  assert_eq(parent_followup.length(), 1)
  ignore(
    success(
      engine.complete(
        id_of(parent_followup[0]),
        stop_response("Later parent answer"),
      ),
    ),
  )

  // A fork of the fork retains both lineage markers and the current fixed prefix.
  let grandchild = success(
    engine.invoke("session_fork", fork_input(child_id, id="session-3")),
  )
  assert_eq(required_string(grandchild, "parent_session_id"), child_id)
  assert_eq(get_status(grandchild), "idle")
  assert_true(
    array_value(
      required_field(grandchild, "events"),
      "grandchild events",
      32768,
    ).any(event => required_string(event, "type") == "session/forked"),
  )

  let parent_after_continuation = success(
    engine.invoke("session_get", fixture("{\"session_id\":\"test\"}")),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture(
          "{\"session_id\":\"session-2\",\"prompt\":\"Child continues independently\"}",
        ),
      ),
    ),
  )
  let child_followup = engine.take_effects()
  assert_eq(child_followup.length(), 1)
  let child_request_messages = array_value(
    required_field(required_field(child_followup[0], "request"), "messages"),
    "child provider messages",
    100,
  )
  assert_true(
    child_request_messages.any(message => {
      required_string(message, "content") == "First answer"
    }),
  )
  assert_true(
    child_request_messages.any(message => {
      required_string(message, "content") == "Child continues independently"
    }),
  )
  let child_after_continuation = success(
    engine.complete(
      id_of(child_followup[0]),
      stop_response("Independent child answer"),
    ),
  )
  assert_eq(get_status(child_after_continuation), "completed")
  assert_true(engine.take_effects().is_empty())
  assert_eq(
    success(engine.invoke("session_get", fixture("{\"session_id\":\"test\"}"))),
    parent_after_continuation,
  )

  // Restore validates the whole graph after loading, independent of row order.
  let snapshot = engine.snapshot()
  let sessions = array_value(
    required_field(snapshot, "sessions"),
    "sessions",
    32,
  )
  let reversed : Array[Json] = []
  let mut index = sessions.length()
  while index > 0 {
    index -= 1
    reversed.push(sessions[index])
  }
  fields(snapshot).set("sessions", Json::array(reversed))
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  assert_eq(restored.take_effects().length(), 0)
  let loaded_grandchild = success(
    restored.invoke("session_get", fixture("{\"session_id\":\"session-3\"}")),
  )
  assert_eq(required_string(loaded_grandchild, "parent_session_id"), child_id)
  assert_eq(get_status(loaded_grandchild), "idle")
}

///|
test "fork rekeys retry metadata without changing user data and preserves pruning references" {
  let (retry_engine, request) = started_engine()
  let source_effect = id_of(request)
  let scheduled = success(
    retry_engine.schedule_retry(source_effect, retry_policy(initial_delay_ms=0)),
  )
  let source_retry = required_string(scheduled, "retry_id")
  ignore(success(retry_engine.start_retry(source_effect, source_retry)))
  let source = success(
    retry_engine.complete(source_effect, stop_response("Retried answer")),
  )
  let child = success(retry_engine.invoke("session_fork", fork_input("test")))
  let child_effect = required_string(
    required_field(event_with_type(child, "llm/request"), "data"),
    "effect_id",
  )
  assert_true(source_effect != child_effect)
  let source_retry_event = event_with_type(source, "llm/retry")
  let source_retry_data = required_field(source_retry_event, "data")
  let child_retry = event_with_type(child, "llm/retry")
  let child_retry_data = required_field(child_retry, "data")
  assert_eq(required_string(child_retry_data, "effect_id"), child_effect)
  assert_eq(
    required_string(child_retry_data, "retry_id"),
    "retry-\{child_effect}-1",
  )
  assert_true(required_string(child_retry_data, "retry_id") != source_retry)
  assert_eq(
    required_field(child_retry_data, "failure"),
    required_field(source_retry_data, "failure"),
  )
  let restored_retry = Engine::new(test_tools())
  assert_eq(restored_retry.restore(retry_engine.snapshot()), Ok(()))
  assert_eq(restored_retry.take_effects().length(), 0)

  let pruning_engine = completed_engine_with_tool_result(
    "😀"[:].repeat(60).to_owned(),
  )
  let threshold = code_point_length(PRUNE_MARKER) + 7
  let pruned = success(
    pruning_engine.invoke(
      "session_prune_tool_results",
      pruning_input(threshold_chars=threshold, head_chars=4, tail_chars=3),
    ),
  )
  let pruned_source = prune_response_session(pruned)
  let pruned_child = success(
    pruning_engine.invoke("session_fork", fork_input("test")),
  )
  assert_eq(
    required_field(pruned_child, "messages"),
    required_field(pruned_source, "messages"),
  )
  let source_prune = event_with_type(pruned_source, "tool/result/pruned")
  let child_prune = event_with_type(pruned_child, "tool/result/pruned")
  for key in ["source_seq", "result_seq", "call_id"] {
    assert_eq(
      required_field(required_field(child_prune, "data"), key),
      required_field(required_field(source_prune, "data"), key),
    )
  }
  let restored_pruning = Engine::new(test_tools())
  assert_eq(restored_pruning.restore(pruning_engine.snapshot()), Ok(()))
  assert_eq(restored_pruning.take_effects().length(), 0)

  // The fork begins idle, so a new prune event after its fork marker must also
  // replay as a valid idle-session projection.
  let idle_pruning_engine = completed_engine_with_tool_result(
    "😀"[:].repeat(60).to_owned(),
  )
  let idle_child = success(
    idle_pruning_engine.invoke("session_fork", fork_input("test")),
  )
  let idle_child_id = required_string(idle_child, "id")
  let idle_pruned = success(
    idle_pruning_engine.invoke(
      "session_prune_tool_results",
      object([
        ("session_id", Json::string(idle_child_id)),
        ("threshold_chars", integer(threshold)),
        ("head_chars", integer(4)),
        ("tail_chars", integer(3)),
      ]),
    ),
  )
  assert_eq(get_status(prune_response_session(idle_pruned)), "idle")
  let restored_idle_pruning = Engine::new(test_tools())
  assert_eq(
    restored_idle_pruning.restore(idle_pruning_engine.snapshot()),
    Ok(()),
  )
  assert_eq(restored_idle_pruning.take_effects().length(), 0)
}

///|
test "fork preserves effectless local tool completion events" {
  let (engine, request) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(request),
        calls_response([("unknown-call", "not-installed", "{}")]),
      ),
    ),
  )
  let followup = engine.take_effects()
  assert_eq(followup.length(), 1)
  let source = success(
    engine.complete(id_of(followup[0]), stop_response("Settled")),
  )
  let local_completion = event_with_type(source, "tool/completed")
  assert_eq(
    required_string(required_field(local_completion, "data"), "source"),
    "local",
  )
  assert_true(
    fields(required_field(local_completion, "data")).get("effect_id") is None,
  )
  let child = success(engine.invoke("session_fork", fork_input("test")))
  let copied_completion = event_with_type(child, "tool/completed")
  assert_eq(
    required_field(copied_completion, "data"),
    required_field(local_completion, "data"),
  )
  assert_true(
    fields(required_field(copied_completion, "data")).get("effect_id") is None,
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(restored.take_effects().length(), 0)
}

///|
test "fork keeps interrupted outcomes inert and rejects unsettled imported or conflicting sources atomically" {
  let (running, request) = started_engine()
  ignore(request)
  let recovered = Engine::new(test_tools())
  assert_eq(recovered.restore(running.snapshot()), Ok(()))
  let interrupted_source = get_session(recovered)
  assert_eq(get_status(interrupted_source), "failed")
  let interrupted_child = success(
    recovered.invoke("session_fork", fork_input("test")),
  )
  assert_eq(get_status(interrupted_child), "idle")
  assert_true(
    array_value(
      required_field(interrupted_child, "events"),
      "child events",
      32768,
    ).any(event => required_string(event, "type") == "session/interrupted"),
  )
  assert_true(
    array_value(
      required_field(interrupted_child, "events"),
      "child events",
      32768,
    ).any(event => required_string(event, "type") == "assistant/attempt"),
  )
  assert_true(recovered.take_effects().is_empty())
  let restored_interrupted = Engine::new(test_tools())
  assert_eq(restored_interrupted.restore(recovered.snapshot()), Ok(()))

  let (active, active_effect) = started_engine()
  let active_before = active.snapshot()
  assert_true(active.invoke("session_fork", fork_input("test")) is Err(_))
  assert_eq(active.snapshot(), active_before)
  ignore(active_effect)

  let imported_engine = Engine::new(test_tools())
  ignore(
    success(
      imported_engine.invoke(
        "session_import",
        object([("jsonl", Json::string(session_v4_portable_fixture()))]),
      ),
    ),
  )
  let imported_before = imported_engine.snapshot()
  assert_true(
    imported_engine.invoke("session_fork", fork_input("fixture-v4")) is Err(_),
  )
  assert_eq(imported_engine.snapshot(), imported_before)

  let (settled, effect) = started_engine()
  ignore(success(settled.complete(id_of(effect), stop_response("Done"))))
  let conflict_before = settled.snapshot()
  assert_true(
    settled.invoke("session_fork", fork_input("test", id="test")) is Err(_),
  )
  assert_eq(settled.snapshot(), conflict_before)
}

///|
test "fork rejects event capacity and restore rejects a forged parent prefix atomically" {
  let (engine, request) = started_engine()
  ignore(success(engine.complete(id_of(request), stop_response("Done"))))
  for index in 1..<32 {
    ignore(
      success(
        engine.invoke(
          "session_create",
          object([("id", Json::string("other-\{index}"))]),
        ),
      ),
    )
  }
  let full_before = engine.snapshot()
  assert_true(engine.invoke("session_fork", fork_input("test")) is Err(_))
  assert_eq(engine.snapshot(), full_before)

  let (source, effect) = started_engine()
  ignore(success(source.complete(id_of(effect), stop_response("Done"))))
  ignore(success(source.invoke("session_fork", fork_input("test", id="child"))))
  let forged = source.snapshot()
  let sessions = array_value(required_field(forged, "sessions"), "sessions", 32)
  let child = sessions[1]
  let child_events = array_value(
    required_field(child, "events"),
    "child events",
    32768,
  )
  // This extra event field does not affect the derived transcript. The exact
  // source-prefix check must still reject it before adopting any snapshot state.
  fields(required_field(child_events[1], "data")).set(
    "forged",
    Json::boolean(true),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restore binds fork creation settings and parent identity to validated lineage" {
  let (source, effect) = started_engine()
  ignore(success(source.complete(id_of(effect), stop_response("Done"))))
  ignore(success(source.invoke("session_fork", fork_input("test", id="child"))))
  let original = source.snapshot()

  for key in ["system_prompt", "max_steps"] {
    let forged = @json.parse(original.stringify()) catch {
      _ => abort("Could not clone fork snapshot")
    }
    let sessions = array_value(
      required_field(forged, "sessions"),
      "sessions",
      32,
    )
    let child = sessions[1]
    let child_events = array_value(
      required_field(child, "events"),
      "child events",
      32768,
    )
    let change = if key == "system_prompt" {
      Json::string("forged system prompt")
    } else {
      integer(1)
    }
    fields(child).set(key, change)
    fields(required_field(child_events[0], "data")).set(key, change)
    let destination = Engine::new(test_tools())
    let before = destination.snapshot()
    assert_true(destination.restore(forged) is Err(_))
    assert_eq(destination.snapshot(), before)
  }

  let missing_parent = @json.parse(original.stringify()) catch {
    _ => abort("Could not clone fork snapshot")
  }
  let missing_sessions = array_value(
    required_field(missing_parent, "sessions"),
    "sessions",
    32,
  )
  let missing_child = missing_sessions[1]
  let missing_events = array_value(
    required_field(missing_child, "events"),
    "child events",
    32768,
  )
  fields(missing_child).set("parent_session_id", Json::string("missing-parent"))
  fields(required_field(missing_events[missing_events.length() - 1], "data")).set(
    "parent_session_id",
    Json::string("missing-parent"),
  )
  let missing_destination = Engine::new(test_tools())
  let missing_before = missing_destination.snapshot()
  assert_true(missing_destination.restore(missing_parent) is Err(_))
  assert_eq(missing_destination.snapshot(), missing_before)

  // A forged reciprocal marker can satisfy both fixed-prefix checks, but the
  // final graph validation must still reject the resulting cycle.
  let cycle = @json.parse(original.stringify()) catch {
    _ => abort("Could not clone fork snapshot")
  }
  let cycle_sessions = array_value(
    required_field(cycle, "sessions"),
    "sessions",
    32,
  )
  let root = cycle_sessions[0]
  let child = cycle_sessions[1]
  let root_events = array_value(
    required_field(root, "events"),
    "root events",
    32768,
  )
  let child_events = array_value(
    required_field(child, "events"),
    "child events",
    32768,
  )
  let source_count = root_events.length()
  let root_effect = required_string(
    required_field(event_with_type(root, "llm/request"), "data"),
    "effect_id",
  )
  let child_effect = required_string(
    required_field(event_with_type(child, "llm/request"), "data"),
    "effect_id",
  )
  let root_marker = object([
    ("seq", integer(source_count)),
    ("type", Json::string("session/forked")),
    ("turn_id", required_field(root, "turn_id")),
    ("step", required_field(root, "step")),
    (
      "data",
      object([
        ("parent_session_id", Json::string("child")),
        ("source_event_count", integer(source_count)),
        ("source_status", Json::string("completed")),
        ("source_turn_id", required_field(root, "turn_id")),
        ("source_step", required_field(root, "step")),
        (
          "effect_map",
          Json::array([
            object([
              ("source_id", Json::string(child_effect)),
              ("fork_id", Json::string(root_effect)),
            ]),
          ]),
        ),
      ]),
    ),
  ])
  let extended_root_events = root_events.copy()
  extended_root_events.push(root_marker)
  fields(root).set("events", Json::array(extended_root_events))
  fields(root).set("parent_session_id", Json::string("child"))
  fields(root).set("status", Json::string("idle"))
  ignore(child_events)
  let cycle_destination = Engine::new(test_tools())
  let cycle_before = cycle_destination.snapshot()
  let cycle_error = match cycle_destination.restore(cycle) {
    Ok(_) => fail("fork lineage cycle must be rejected")
    Err(error) => error
  }
  assert_true(cycle_error.contains("cycle"))
  assert_eq(cycle_destination.snapshot(), cycle_before)
}
