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
test "native hook invocation rejects matcher NUL before changing the snapshot" {
  let (engine, _) = started_engine()
  let before = engine.snapshot()
  assert_true(
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:3",
      Some("r\u0000ead"),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
}

///|
test "native hook result reservation includes the interrupted closure" {
  let (engine, provider) = started_engine()
  let mut fills = 0
  for _ in 0..<128 {
    let admitted = engine.copy_state()
    if admitted.project_stream(id_of(provider), "x".repeat(4096), "") is Err(_) {
      break
    }
    let checkpoint = match
      admitted.record_native_hook_invoked(
        "test",
        "PreToolUse",
        "claude-code:PreToolUse:14",
        None,
      ) {
      Ok(value) => value
      Err(_) => break
    }
    assert_true(
      admitted.record_native_hook_result(
        checkpoint,
        "approve",
        Some(-2147483648),
        Some("\u0000".repeat(501)),
        2147483647,
      )
      is Ok(_),
    )
    let filled = engine.copy_state()
    assert_true(
      filled.project_stream(id_of(provider), "x".repeat(4096), "") is Ok(_),
    )
    engine.adopt(filled)
    fills += 1
  }
  assert_true(fills > 0)
  let trial = engine.copy_state()
  let checkpoint = trial
    .record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:15",
      None,
    )
    .unwrap()
  assert_true(
    trial.record_native_hook_result(
      checkpoint,
      "approve",
      Some(-2147483648),
      Some("\u0000".repeat(501)),
      2147483647,
    )
    is Ok(_),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(trial.snapshot()), Ok(()))
}

///|
test "pending native hooks block Stop and PostTool closure until their result" {
  let (stop_engine, provider) = started_engine(max_steps=4)
  ignore(
    success(
      stop_engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        stop_response("answer"),
      ),
    ),
  )
  let stop = stop_hook_checkpoint(stop_engine)
  ignore(success(stop_engine.prepare_stop_continuation(stop, "continue")))
  let stop_result = stop_engine
    .record_native_hook_invoked(
      "test",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:31",
      None,
    )
    .unwrap()
  let stop_before = stop_engine.snapshot()
  assert_true(stop_engine.block_stop_continuation(stop, "denied") is Err(_))
  assert_true(stop_engine.continue_stop_hook(stop, []) is Err(_))
  assert_eq(stop_engine.snapshot(), stop_before)
  ignore(
    stop_engine.record_native_hook_result(stop_result, "deny", Some(0), None, 1),
  )
  assert_true(stop_engine.block_stop_continuation(stop, "denied") is Ok(_))
  assert_eq(Engine::new(test_tools()).restore(stop_engine.snapshot()), Ok(()))

  let (post_engine, llm) = started_engine(max_steps=4)
  ignore(
    success(
      post_engine.complete(
        id_of(llm),
        calls_response([("post-hook", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let tool = post_engine.take_effects()[0]
  ignore(
    success(
      post_engine.complete_effect_with_post_tool_prompt_hook(
        post_tool_effect_id(tool),
        fixture(
          "{\"ok\":true,\"content\":\"read\",\"additional_contexts\":[\"context\"]}",
        ),
      ),
    ),
  )
  let post = post_engine
    .pending_post_tool_prompt_hook(SessionId::new("test").unwrap())
    .unwrap()
  let post_result = post_engine
    .record_native_hook_invoked(
      "test",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:32",
      None,
    )
    .unwrap()
  let post_before = post_engine.snapshot()
  assert_true(post_engine.block_post_tool_prompt_hook(post, "denied") is Err(_))
  assert_eq(post_engine.snapshot(), post_before)
  ignore(
    post_engine.record_native_hook_result(post_result, "deny", Some(0), None, 1),
  )
  assert_true(post_engine.block_post_tool_prompt_hook(post, "denied") is Ok(_))
  assert_eq(Engine::new(test_tools()).restore(post_engine.snapshot()), Ok(()))
}

///|
test "pending UserPromptSubmit result blocks PostTool prompt admission" {
  let (engine, llm) = started_engine(max_steps=4)
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([("prompt-admit", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let tool = engine.take_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_post_tool_prompt_hook(
        post_tool_effect_id(tool),
        fixture(
          "{\"ok\":true,\"content\":\"read\",\"additional_contexts\":[\"context\"]}",
        ),
      ),
    ),
  )
  let post = engine
    .pending_post_tool_prompt_hook(SessionId::new("test").unwrap())
    .unwrap()
  let invocation = engine
    .record_native_hook_invoked(
      "test",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:33",
      None,
    )
    .unwrap()
  let before = engine.snapshot()
  assert_true(engine.accept_post_tool_prompt_hook(post, []) is Err(_))
  assert_eq(engine.snapshot(), before)
  assert_true(engine.take_effects().is_empty())
  ignore(engine.record_native_hook_result(invocation, "pass", Some(0), None, 1))
  assert_true(engine.accept_post_tool_prompt_hook(post, []) is Ok(_))
  assert_eq(engine.take_effects().length(), 1)
  assert_eq(Engine::new(test_tools()).restore(engine.snapshot()), Ok(()))
}

///|
test "a pending hook cannot let the final tool close a max-steps turn" {
  let (engine, provider) = started_engine(max_steps=1)
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([("last-read", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let tool = engine.take_effects()[0]
  ignore(
    engine
    .record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:15",
      None,
    )
    .unwrap(),
  )
  let before = engine.snapshot()
  assert_true(
    engine.complete(id_of(tool), fixture("{\"ok\":true,\"content\":\"read\"}"))
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
}

///|
test "a parallel tool result is preserved while a sibling hook is pending" {
  let (engine, provider) = started_engine(max_steps=4)
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([
          ("parallel-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("parallel-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  ignore(
    engine.record_native_hook_invoked(
      "test",
      "PreToolUse",
      "claude-code:PreToolUse:41",
      Some("read"),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(reads[0]),
        fixture("{\"ok\":true,\"content\":\"alpha\"}"),
      ),
    ),
  )
  let session = get_session(engine)
  let events = array_value(required_field(session, "events"), "events", 32768)
  let mut preserved = false
  for event in events {
    if required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "parallel-a" {
      preserved = true
    }
  }
  assert_true(preserved)
  assert_eq(get_status(session), "running")
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_status(get_session(restored)), "failed")
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
