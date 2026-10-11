///|
fn stop_hook_completion_id(value : Json) -> EffectId {
  let id = id_of(value)
  match EffectId::new(id) {
    Ok(effect_id) => effect_id
    Err(error) => abort(error)
  }
}

///|
fn stop_hook_checkpoint(engine : Engine) -> NativeStopHookCheckpoint {
  let session_id = match SessionId::new("test") {
    Ok(value) => value
    Err(error) => abort(error)
  }
  match engine.pending_stop_hook(session_id) {
    Some(value) => value
    None => abort("Expected a pending Stop hook")
  }
}

///|
fn max_tokens_response(text : String) -> Json {
  object([
    ("ok", boolean(true)),
    ("content", Json::string(text)),
    ("tool_calls", Json::array([])),
    ("finish_reason", Json::string("length")),
  ])
}

///|
fn event_type_count(session : Json, kind : String) -> Int raise EngineError {
  array_value(required_field(session, "events"), "events", 32768)
  .filter(event => required_string(event, "type") == kind)
  .length()
}

///|
test "Stop hook completion is an explicit durable boundary and allowed completion settles it" {
  let (engine, provider) = started_engine()
  let pending = success(
    engine.complete_effect_with_stop_hook(
      stop_hook_completion_id(provider),
      stop_response("Finished answer"),
    ),
  )
  assert_eq(get_status(pending), "running")
  assert_eq(event_type_count(pending, "hook/stop-pending"), 1)
  assert_true(engine.take_effects().is_empty())
  let checkpoint = stop_hook_checkpoint(engine)
  let finished = success(engine.finish_stop_hook(checkpoint))
  assert_eq(get_status(finished), "completed")
  assert_eq(event_type_count(finished, "turn/end"), 1)
  assert_true(engine.finish_stop_hook(checkpoint) is Err(_))
}

///|
test "Stop continuation stages before UserPromptSubmit and commits source messages only on admission" {
  let (engine, provider) = started_engine(max_steps=4)
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        stop_response("First answer"),
      ),
    ),
  )
  let checkpoint = stop_hook_checkpoint(engine)
  let staged = success(
    engine.prepare_stop_continuation(
      checkpoint, "continue: blocked by Stop hook",
    ),
  )
  assert_eq(event_type_count(staged, "hook/stop-continuation-pending"), 1)
  assert_eq(
    array_value(required_field(staged, "messages"), "messages", 16).length(),
    2,
  )

  let recovered = Engine::new(test_tools())
  assert_eq(recovered.restore(engine.snapshot()), Ok(()))
  let interrupted = get_session(recovered)
  assert_eq(get_status(interrupted), "failed")
  assert_true(
    array_value(required_field(interrupted, "events"), "events", 100).any(event => {
      required_string(event, "type") == "turn/end" &&
      required_string(required_field(event, "data"), "reason") == "interrupted"
    }),
  )
  assert_true(recovered.take_effects().is_empty())

  let continued = success(
    engine.continue_stop_hook(checkpoint, ["extra context"]),
  )
  assert_eq(get_status(continued), "running")
  assert_eq(event_type_count(continued, "hook/stop-continuation-admitted"), 1)
  let effects = engine.take_typed_effects()
  assert_eq(effects.length(), 1)
  let messages = array_value(
    required_field(effects[0].request(), "messages"),
    "messages",
    8,
  )
  assert_eq(messages.length(), 4)
  assert_eq(required_field(messages[2], "source"), {
    "kind": "hooks-claude-code",
  })
  assert_eq(required_field(messages[3], "source"), {
    "kind": "hooks-claude-code",
  })
  let restarted = Engine::new(test_tools())
  assert_eq(restarted.restore(engine.snapshot()), Ok(()))
  assert_eq(get_status(get_session(restarted)), "failed")
  assert_true(restarted.take_effects().is_empty())
}

///|
test "UserPromptSubmit rejection preserves the answer and ends with an explicit blocked status" {
  let (engine, provider) = started_engine()
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        stop_response("Kept answer"),
      ),
    ),
  )
  let checkpoint = stop_hook_checkpoint(engine)
  ignore(success(engine.prepare_stop_continuation(checkpoint, "continue")))
  let blocked = success(
    engine.block_stop_continuation(checkpoint, "sensitive request"),
  )
  assert_eq(get_status(blocked), "failed")
  assert_eq(event_type_count(blocked, "hook/stop-continuation-rejected"), 1)
  assert_eq(event_type_count(blocked, "assistant/message"), 1)
  assert_eq(
    array_value(required_field(blocked, "messages"), "messages", 16).length(),
    2,
  )
  assert_true(
    array_value(required_field(blocked, "events"), "events", 100).any(event => {
      required_string(event, "type") == "turn/end" &&
      required_string(required_field(event, "data"), "reason") == "blocked"
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), blocked)
}

///|
test "long astral UserPromptSubmit denial closes pending state within the error bound" {
  let (engine, provider) = started_engine()
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        stop_response("Answer retained before the blocked continuation"),
      ),
    ),
  )
  let checkpoint = stop_hook_checkpoint(engine)
  ignore(success(engine.prepare_stop_continuation(checkpoint, "continue")))
  let blocked = success(
    engine.block_stop_continuation(
      checkpoint,
      "😀"[:].repeat(4096).to_owned(),
    ),
  )
  let events = array_value(required_field(blocked, "events"), "events", 100)
  let mut rejection : Json? = None
  for event in events {
    if required_string(event, "type") == "hook/stop-continuation-rejected" {
      rejection = Some(event)
    }
  }
  let rejection = rejection.unwrap()
  let error = required_string(required_field(rejection, "data"), "error")
  assert_true(stop_hook_utf16_units(error) <= 8192)
  assert_true(stop_hook_utf16_units(error) >= 8000)
  assert_eq(get_status(blocked), "failed")
  assert_eq(event_type_count(blocked, "hook/stop-continuation-pending"), 1)
  assert_eq(event_type_count(blocked, "turn/end"), 1)
  assert_true(
    array_value(required_field(blocked, "messages"), "messages", 16).any(message => {
      required_string(message, "content") ==
      "Answer retained before the blocked continuation"
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), blocked)
}

///|
test "max-token ending stays sticky across an admitted same-turn continuation" {
  let (engine, provider) = started_engine(max_steps=4)
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        max_tokens_response("Partial answer"),
      ),
    ),
  )
  let first = stop_hook_checkpoint(engine)
  ignore(success(engine.prepare_stop_continuation(first, "continue")))
  ignore(success(engine.continue_stop_hook(first, [])))
  let next = engine.take_typed_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        next.id(),
        stop_response("Second answer"),
      ),
    ),
  )
  let ending = success(engine.finish_stop_hook(stop_hook_checkpoint(engine)))
  assert_eq(get_status(ending), "failed")
  assert_true(
    array_value(required_field(ending, "events"), "events", 100).any(event => {
      required_string(event, "type") == "turn/end" &&
      required_string(required_field(event, "data"), "reason") == "max_tokens"
    }),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), ending)
}

///|
test "oversized Stop reason closes the pending boundary without dispatch" {
  let (engine, provider) = started_engine()
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        stop_hook_completion_id(provider),
        stop_response("Answer before the oversized reason"),
      ),
    ),
  )
  let checkpoint = stop_hook_checkpoint(engine)
  let closed = success(
    engine.prepare_stop_continuation(
      checkpoint,
      "x".repeat(STOP_HOOK_MERGED_REASON_MAX_UNITS + 1),
    ),
  )
  assert_eq(get_status(closed), "failed")
  assert_eq(event_type_count(closed, "hook/stop-continuation-pending"), 0)
  assert_true(
    array_value(required_field(closed, "events"), "events", 100).any(event => {
      required_string(event, "type") == "turn/end" &&
      required_string(required_field(event, "data"), "reason") ==
      "session_capacity"
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), closed)
}
