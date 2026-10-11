///|
fn subagent_hook_engine() -> Engine {
  let engine = Engine::new(test_tools())
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([
          ("id", Json::string("hook-child")),
          ("title", Json::string("Hook child")),
        ]),
      ),
    ),
  )
  engine
}

///|
fn get_session_for(engine : Engine, session_id : String) -> Json {
  success(
    engine.invoke(
      "session_get",
      object([("session_id", Json::string(session_id))]),
    ),
  )
}

///|
fn subagent_checkpoint_success(
  result : Result[NativeSubagentPromptHookCheckpoint, String],
) -> NativeSubagentPromptHookCheckpoint {
  match result {
    Ok(value) => value
    Err(message) => abort("Unexpected checkpoint error: \{message}")
  }
}

///|
fn subagent_stop_effect_id(value : Json) -> EffectId {
  match EffectId::new(id_of(value)) {
    Ok(effect_id) => effect_id
    Err(error) => abort(error)
  }
}

///|
fn subagent_hook_user_messages(effect : Json) -> Array[Json] raise EngineError {
  subagent_hook_all_messages(effect).filter(message => {
    required_string(message, "role") == "user"
  })
}

///|
fn subagent_hook_all_messages(effect : Json) -> Array[Json] raise EngineError {
  array_value(
    required_field(required_field(effect, "request"), "messages"),
    "provider messages",
    32,
  )
}

///|
fn subagent_hook_message_text(message : Json) -> String raise EngineError {
  match fields(message).get("content") {
    Some(Json::String(content)) => content
    Some(Json::Array(blocks)) =>
      blocks.map(block => required_string(block, "text")).join("")
    _ => ""
  }
}

///|
test "initial and late SubagentStart batches pass through immutable prompt checkpoints" {
  let engine = subagent_hook_engine()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["start one", "start two"]),
    Ok(true),
  )
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook(
      "hook-child", "original child prompt", true,
    ),
  )
  assert_true(initial.is_initial())
  assert_eq(initial.contexts(), ["start one", "start two"])
  assert_eq(initial.prompt(), "start onestart twooriginal child prompt")
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["arrived during hook"]),
    Ok(true),
  )
  ignore(
    success(
      engine.accept_subagent_prompt_hook(initial, ["initial policy context"]),
    ),
  )
  let first = engine.take_effects()[0]
  let first_messages = subagent_hook_user_messages(first)
  assert_eq(first_messages.length(), 3)
  assert_eq(subagent_hook_message_text(first_messages[0]), "start onestart two")
  assert_eq(
    subagent_hook_message_text(first_messages[1]),
    "original child prompt",
  )
  assert_eq(
    subagent_hook_message_text(first_messages[2]),
    "initial policy context",
  )
  assert_true(fields(first_messages[0]).get("source") is Some(_))
  assert_true(fields(first_messages[2]).get("source") is Some(_))
  assert_false(
    first_messages.any(message => {
      subagent_hook_message_text(message).contains("arrived during hook")
    }),
  )

  ignore(success(engine.complete(id_of(first), stop_response("first answer"))))
  let late = match engine.pending_subagent_prompt_hook("hook-child") {
    Some(value) => value
    None => abort("Expected a late SubagentStart prompt checkpoint")
  }
  assert_false(late.is_initial())
  assert_eq(late.contexts(), ["arrived during hook"])
  assert_eq(late.prompt(), "arrived during hook")
  ignore(
    success(engine.accept_subagent_prompt_hook(late, ["late policy context"])),
  )
  let second = engine.take_effects()[0]
  let second_messages = subagent_hook_user_messages(second)
  assert_true(
    subagent_hook_all_messages(second).any(message => {
      required_string(message, "role") == "assistant" &&
      required_string(message, "content") == "first answer"
    }),
  )
  assert_true(
    second_messages.any(message => {
      subagent_hook_message_text(message) == "arrived during hook" &&
      fields(message).get("source") is Some(_)
    }),
  )
  assert_true(
    second_messages.any(message => {
      subagent_hook_message_text(message) == "late policy context" &&
      fields(message).get("source") is Some(_)
    }),
  )
  let completed = success(
    engine.complete(id_of(second), stop_response("final answer")),
  )
  assert_eq(get_status(completed), "completed")
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), completed)
}

///|
test "late prompt admission denial preserves the committed answer and dispatches nothing" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let first = engine.take_effects()[0]
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["must not be admitted"]),
    Ok(true),
  )
  ignore(
    success(engine.complete(id_of(first), stop_response("answer to retain"))),
  )
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  let blocked = success(
    engine.block_subagent_prompt_hook(checkpoint, "policy denied this input"),
  )
  assert_eq(get_status(blocked), "failed")
  assert_true(
    array_value(required_field(blocked, "messages"), "messages", 16).any(message => {
      required_string(message, "content") == "answer to retain"
    }),
  )
  assert_false(
    array_value(required_field(blocked, "messages"), "messages", 16).any(message => {
      required_string(message, "content").contains("must not be admitted")
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), blocked)
}

///|
test "SubagentStart prompt admission waits for every sibling tool result" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let first = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(first),
        calls_response([
          ("read-one", "read", "{\"file_path\":\"one.txt\"}"),
          ("read-two", "read", "{\"file_path\":\"two.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  assert_eq(reads.length(), 2)
  ignore(
    success(
      engine.complete(
        id_of(reads[0]),
        object([("ok", boolean(true)), ("content", Json::string("one"))]),
      ),
    ),
  )
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["after both tools"]),
    Ok(true),
  )
  assert_true(engine.pending_subagent_prompt_hook("hook-child") is None)
  assert_true(engine.take_effects().is_empty())
  ignore(
    success(
      engine.complete(
        id_of(reads[1]),
        object([("ok", boolean(true)), ("content", Json::string("two"))]),
      ),
    ),
  )
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  assert_eq(checkpoint.prompt(), "after both tools")
  assert_true(engine.take_effects().is_empty())
}

///|
test "Stop continuation batches earlier Start input before reason and prompt context" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let first = engine.take_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        subagent_stop_effect_id(first),
        stop_response("answer before continuation"),
      ),
    ),
  )
  let session_id = SessionId::new("hook-child").unwrap()
  let stop = engine.pending_stop_hook(session_id).unwrap()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["start before stop"]),
    Ok(true),
  )
  ignore(success(engine.prepare_stop_continuation(stop, "continue for review")))
  let checkpoint = engine.pending_stop_hook(session_id).unwrap()
  assert_eq(
    match engine.stop_continuation_prompt(checkpoint) {
      Ok(value) => value
      Err(error) => abort(error)
    },
    "start before stopcontinue for review",
  )
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["start during prompt hook"]),
    Ok(true),
  )
  let continued = success(
    engine.continue_stop_hook(checkpoint, ["prompt policy context"]),
  )
  assert_eq(get_status(continued), "running")
  let provider = engine.take_effects()[0]
  let messages = subagent_hook_user_messages(provider)
  assert_eq(subagent_hook_message_text(messages[1]), "start before stop")
  assert_eq(subagent_hook_message_text(messages[2]), "continue for review")
  assert_eq(subagent_hook_message_text(messages[3]), "prompt policy context")
  assert_false(
    messages.any(message => {
      subagent_hook_message_text(message).contains("start during prompt hook")
    }),
  )
  ignore(
    success(engine.complete(id_of(provider), stop_response("continued answer"))),
  )
  assert_eq(
    engine.pending_subagent_prompt_hook("hook-child").unwrap().prompt(),
    "start during prompt hook",
  )
}

///|
test "Stop prompt denial sees earlier Start input but commits neither message" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let first = engine.take_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        subagent_stop_effect_id(first),
        stop_response("answer kept after denial"),
      ),
    ),
  )
  let session_id = SessionId::new("hook-child").unwrap()
  let stop = engine.pending_stop_hook(session_id).unwrap()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["start before denial"]),
    Ok(true),
  )
  ignore(success(engine.prepare_stop_continuation(stop, "continue request")))
  let checkpoint = engine.pending_stop_hook(session_id).unwrap()
  assert_eq(
    match engine.stop_continuation_prompt(checkpoint) {
      Ok(value) => value
      Err(error) => abort(error)
    },
    "start before denialcontinue request",
  )
  let blocked = success(
    engine.block_stop_continuation(checkpoint, "policy denied continuation"),
  )
  assert_eq(get_status(blocked), "failed")
  let messages = array_value(
    required_field(blocked, "messages"),
    "messages",
    16,
  )
  assert_eq(messages.length(), 2)
  assert_true(
    messages.any(message => {
      required_string(message, "content") == "answer kept after denial"
    }),
  )
  assert_false(
    messages.any(message => {
      required_string(message, "content").contains("start before denial") ||
      required_string(message, "content").contains("continue request")
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), blocked)
}
