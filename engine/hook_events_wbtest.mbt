///|
fn hook_event_data(session : Json, kind : String) -> Json? raise EngineError {
  let events = array_value(required_field(session, "events"), "events", 32768)
  for event in events {
    if required_string(event, "type") == kind {
      return Some(required_field(event, "data"))
    }
  }
  None
}

///|
test "native hook checkpoints pair by turn and preserve upstream result fields" {
  let (engine, effect) = started_engine()
  let checkpoint = match
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:1",
      Some("read"),
    ) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  assert_true(
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:1",
      Some("read"),
    )
    is Err(_),
  )
  ignore(
    engine.record_native_hook_result(
      checkpoint,
      "block",
      Some(2),
      Some("  denied by policy  "),
      17,
    ),
  )
  let session = get_session(engine)
  let invoked = hook_event_data(session, "hook/invoked").unwrap()
  let result = hook_event_data(session, "hook/result").unwrap()
  assert_eq(required_field(invoked, "turn"), integer(1))
  assert_eq(required_string(invoked, "point"), "PreToolUse")
  assert_eq(required_string(invoked, "dialect"), "claude-code")
  assert_eq(required_string(invoked, "handlerId"), "claude-code:PreToolUse:1")
  assert_eq(required_string(invoked, "matcher"), "read")
  assert_eq(required_string(result, "decision"), "block")
  assert_eq(required_field(result, "exitCode"), integer(2))
  assert_eq(required_string(result, "stderrSummary"), "  denied by policy  ")
  assert_eq(required_field(result, "durationMs"), integer(17))

  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  let restored_session = get_session(restored)
  assert_eq(get_status(restored_session), "failed")
  assert_eq(
    required_string(
      hook_event_data(restored_session, "hook/result").unwrap(),
      "decision",
    ),
    "block",
  )
  ignore(effect)
}

///|
test "unresolved native hook invocation restores as interrupted without replay" {
  let (engine, _) = started_engine()
  ignore(
    engine.record_native_hook_invoked(
      "test",
      "PostToolUse",
      "claude-code:PostToolUse:7",
      None,
    ),
  )
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  let session = get_session(restored)
  assert_eq(get_status(session), "failed")
  assert_true(hook_event_data(session, "hook/invoked") is Some(_))
  assert_true(hook_event_data(session, "hook/result") is None)
  assert_true(restored.take_effects().is_empty())
}

///|
test "native hook result correlation rejects a mismatched persisted handler" {
  let (engine, _) = started_engine()
  let checkpoint = match
    engine.record_native_hook_invoked(
      "test",
      "Stop",
      "claude-code:Stop:2",
      None,
    ) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  ignore(engine.record_native_hook_result(checkpoint, "pass", Some(0), None, 3))
  let corrupted = json_copy(engine.snapshot())
  let session = array_value(
      required_field(corrupted, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let result_event = events[events.length() - 1]
  fields(required_field(result_event, "data")).set(
    "handlerId",
    Json::string("claude-code:Stop:3"),
  )
  let target = Engine::new(test_tools())
  let before = target.snapshot().stringify()
  assert_true(target.restore(corrupted) is Err(_))
  assert_eq(target.snapshot().stringify(), before)
}

///|
test "pending native hook cannot complete a provider turn and cancellation remains restorable" {
  let (engine, effect) = started_engine()
  ignore(
    engine.record_native_hook_invoked(
      "test",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:1",
      None,
    ),
  )
  assert_true(engine.complete(id_of(effect), stop_response("done")) is Err(_))
  assert_eq(required_string(get_session(engine), "status"), "running")
  ignore(
    success(engine.invoke("session_cancel", { "session_id": "test".to_json() })),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_status(get_session(restored)), "cancelled")
}

///|
test "completed native handler IDs may be reused in a later turn" {
  let (engine, effect) = started_engine()
  let checkpoint = match
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:1",
      None,
    ) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  ignore(engine.record_native_hook_result(checkpoint, "pass", Some(0), None, 1))
  ignore(success(engine.complete(id_of(effect), stop_response("first"))))
  ignore(
    success(
      engine.invoke("session_send", {
        "session_id": "test".to_json(),
        "prompt": "next".to_json(),
      }),
    ),
  )
  let next_effect = engine.take_effects()[0]
  let next_checkpoint = match
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:1",
      None,
    ) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  ignore(
    engine.record_native_hook_result(next_checkpoint, "pass", Some(0), None, 1),
  )
  assert_eq(
    required_field(
      hook_event_data(get_session(engine), "hook/invoked").unwrap(),
      "turn",
    ),
    integer(1),
  )
  assert_true(id_of(next_effect).has_prefix("effect-"))
  assert_eq(Engine::new(test_tools()).restore(engine.snapshot()), Ok(()))
}
