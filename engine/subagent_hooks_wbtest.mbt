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
fn subagent_hook_post_tool_pending_engine() -> Engine {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([("child-read", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let read = engine.take_effects()[0]
  match engine.inject_hook_contexts("hook-child", ["start context"]) {
    Ok(true) => ()
    _ => abort("Could not queue child Start context for PostToolUse replay")
  }
  ignore(
    success(
      engine.complete(
        id_of(read),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"A\"]}",
        ),
      ),
    ),
  )
  engine
}

///|
fn subagent_hook_completed_post_tool_snapshot(
  prompt_contexts : Array[String],
) -> Json {
  let engine = subagent_hook_post_tool_pending_engine()
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  ignore(
    success(engine.accept_subagent_prompt_hook(checkpoint, prompt_contexts)),
  )
  let next_provider = engine.take_effects()[0]
  ignore(success(engine.complete(id_of(next_provider), stop_response("done"))))
  engine.snapshot()
}

///|
fn subagent_hook_over_limit_post_tool_engine(
  post_tool_contexts : Array[String],
) -> (Engine, Json) {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([("child-read", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let read = engine.take_effects()[0]
  match engine.inject_hook_contexts("hook-child", ["S"]) {
    Ok(true) => ()
    _ => abort("Could not queue child Start context for capacity test")
  }
  let failed = success(
    engine.complete(
      id_of(read),
      object([
        ("ok", boolean(true)),
        ("content", Json::string("alpha")),
        (
          "additional_contexts",
          Json::array(post_tool_contexts.map(context => Json::string(context))),
        ),
      ]),
    ),
  )
  (engine, failed)
}

///|
fn subagent_hook_partial_post_tool_engine() -> Engine {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([
          ("child-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("child-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  if reads.length() != 2 {
    abort("Expected two child tool results before the interruption snapshot")
  }
  ignore(
    success(
      engine.complete(
        id_of(reads[0]),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"A\"]}",
        ),
      ),
    ),
  )
  engine
}

///|
fn subagent_hook_forge_reordered_post_tool_message(
  snapshot : Json,
) -> Json raise EngineError {
  let forged = json_copy(snapshot)
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let mut admission_index = -1
  for index, event in events {
    if required_string(event, "type") ==
      "hook/subagent-post-tool-prompt-admitted" {
      admission_index = index
      break
    }
  }
  if admission_index < 0 || admission_index + 2 >= events.length() {
    abort("Child PostToolUse snapshot is missing its admission messages")
  }
  let first_message = events[admission_index + 1]
  let second_message = events[admission_index + 2]
  if required_string(first_message, "type") != "user/message" ||
    required_string(second_message, "type") != "user/message" {
    abort("Child PostToolUse admission marker is not followed by its messages")
  }
  let first_data = required_field(first_message, "data")
  let second_data = required_field(second_message, "data")
  fields(first_message).set("data", second_data)
  fields(second_message).set("data", first_data)
  forged
}

///|
fn subagent_hook_completed_initial_snapshot(
  start_contexts : Array[String],
  prompt_contexts : Array[String],
) -> Json {
  let engine = subagent_hook_engine()
  match engine.inject_hook_contexts("hook-child", start_contexts) {
    Ok(true) => ()
    _ => abort("Could not queue initial SubagentStart contexts")
  }
  let checkpoint = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(
    success(engine.accept_subagent_prompt_hook(checkpoint, prompt_contexts)),
  )
  let request = engine.take_effects()[0]
  ignore(success(engine.complete(id_of(request), stop_response("answer"))))
  engine.snapshot()
}

///|
fn subagent_hook_completed_stop_snapshot(
  start_contexts : Array[String],
  prompt_contexts : Array[String],
) -> Json {
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
  match engine.inject_hook_contexts("hook-child", start_contexts) {
    Ok(true) => ()
    _ => abort("Could not queue Stop-boundary SubagentStart contexts")
  }
  ignore(success(engine.prepare_stop_continuation(stop, "continue")))
  let staged = engine.pending_stop_hook(session_id).unwrap()
  ignore(success(engine.continue_stop_hook(staged, prompt_contexts)))
  let next = engine.take_effects()[0]
  ignore(success(engine.complete(id_of(next), stop_response("final answer"))))
  engine.snapshot()
}

///|
fn subagent_hook_forge_start_contexts(
  snapshot : Json,
  contexts : Array[String],
) -> Json raise EngineError {
  let forged = json_copy(snapshot)
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let mut marker_index = -1
  for index, event in events {
    if required_string(event, "type") == "hook/subagent-start-context" {
      marker_index = index
      break
    }
  }
  if marker_index < 0 || marker_index + 1 >= events.length() {
    abort("Completed Subagent snapshot is missing its Start context pair")
  }
  let marker_event = events[marker_index]
  let message_event = events[marker_index + 1]
  if required_string(message_event, "type") != "user/message" {
    abort("Start context marker is not followed by its user message")
  }
  let marker_data = required_field(marker_event, "data")
  fields(marker_data).set("context_count", integer(contexts.length()))
  fields(marker_data).set(
    "context_length",
    integer(engine_subagent_hook_context_length(contexts)),
  )
  let message_data = required_field(message_event, "data")
  let old_projection = transcript_user_message(message_data)
  let forged_message_data = json_copy(message_data)
  let content : Array[Json] = contexts.map(context => {
    object([("type", Json::string("text")), ("text", Json::string(context))])
  })
  fields(forged_message_data).set("content", Json::array(content))
  let messages = array_value(
    required_field(session, "messages"),
    "messages",
    32768,
  ).copy()
  let mut projection_index = -1
  for index, message in messages {
    if message == old_projection {
      projection_index = index
      break
    }
  }
  if projection_index < 0 {
    abort("Start context message is missing from the transcript projection")
  }
  messages[projection_index] = transcript_user_message(forged_message_data)
  fields(session).set("messages", Json::array(messages))
  fields(message_event).set("data", forged_message_data)
  forged
}

///|
fn subagent_hook_large_contexts(last : String) -> Array[String] {
  ["a".repeat(4096), "b".repeat(4096), "c".repeat(4096), last]
}

///|
test "initial Subagent prompt checkpoint validates prompt bounds atomically" {
  let engine = subagent_hook_engine()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["keep queued"]),
    Ok(true),
  )
  let before = engine.snapshot()
  assert_true(
    engine.begin_subagent_prompt_hook("hook-child", "", true) is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(engine.pending_subagent_prompt_hook("hook-child") is None)
  assert_true(
    engine.begin_subagent_prompt_hook("hook-child", "p".repeat(16385), true)
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  let valid = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "valid prompt", true),
  )
  assert_eq(valid.contexts(), ["keep queued"])
}

///|
test "restore enforces the combined initial Start context count" {
  let valid_snapshot = subagent_hook_completed_initial_snapshot(
    Array::make(31, "start"),
    ["prompt"],
  )
  let valid_restore = Engine::new(test_tools())
  assert_eq(valid_restore.restore(valid_snapshot), Ok(()))

  let forged = subagent_hook_forge_start_contexts(
    valid_snapshot,
    Array::make(32, "start"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)

  let writer = subagent_hook_engine()
  assert_eq(
    writer.inject_hook_contexts("hook-child", Array::make(32, "start")),
    Ok(true),
  )
  let checkpoint = subagent_checkpoint_success(
    writer.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  let before_accept = writer.snapshot()
  assert_true(
    writer.accept_subagent_prompt_hook(checkpoint, ["prompt"]) is Err(_),
  )
  assert_eq(writer.snapshot(), before_accept)
}

///|
test "restore enforces the combined initial Start context UTF-16 length" {
  let exact_snapshot = subagent_hook_completed_initial_snapshot(
    subagent_hook_large_contexts("d".repeat(4093) + "😀"),
    ["x"],
  )
  let exact_restore = Engine::new(test_tools())
  assert_eq(exact_restore.restore(exact_snapshot), Ok(()))

  let forged = subagent_hook_forge_start_contexts(
    exact_snapshot,
    subagent_hook_large_contexts("d".repeat(4094) + "😀"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restore enforces the combined staged Stop Start context count" {
  let valid_snapshot = subagent_hook_completed_stop_snapshot(
    Array::make(31, "start"),
    ["prompt"],
  )
  let valid_restore = Engine::new(test_tools())
  assert_eq(valid_restore.restore(valid_snapshot), Ok(()))

  let forged = subagent_hook_forge_start_contexts(
    valid_snapshot,
    Array::make(32, "start"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restore enforces the combined staged Stop Start context UTF-16 length" {
  let exact_snapshot = subagent_hook_completed_stop_snapshot(
    subagent_hook_large_contexts("d".repeat(4093) + "😀"),
    ["x"],
  )
  let exact_restore = Engine::new(test_tools())
  assert_eq(exact_restore.restore(exact_snapshot), Ok(()))

  let forged = subagent_hook_forge_start_contexts(
    exact_snapshot,
    subagent_hook_large_contexts("d".repeat(4094) + "😀"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
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
  let continued = success(
    engine.continue_stop_hook(checkpoint, ["prompt policy context"]),
  )
  assert_eq(get_status(continued), "running")
  let provider = engine.take_effects()[0]
  let messages = subagent_hook_user_messages(provider)
  assert_eq(subagent_hook_message_text(messages[1]), "start before stop")
  assert_eq(subagent_hook_message_text(messages[2]), "continue for review")
  assert_eq(subagent_hook_message_text(messages[3]), "prompt policy context")
  let completed = success(
    engine.complete(id_of(provider), stop_response("continued answer")),
  )
  assert_eq(get_status(completed), "completed")

  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), completed)

  let reordered = json_copy(snapshot)
  let sessions = array_value(
    required_field(reordered, "sessions"),
    "sessions",
    32,
  )
  let session = sessions[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let mut start_marker_index = -1
  let mut stop_reason_index = -1
  for index, event in events {
    let kind = required_string(event, "type")
    let data = required_field(event, "data")
    if kind == "hook/subagent-start-context" {
      start_marker_index = index
    } else if kind == "user/message" &&
      subagent_hook_message_text(data) == "continue for review" {
      stop_reason_index = index
    }
  }
  assert_true(start_marker_index >= 0 && stop_reason_index > start_marker_index)
  let marker = events[start_marker_index]
  let reason = events[stop_reason_index]
  let reordered_events : Array[Json] = []
  for index, event in events {
    let replacement = if index == start_marker_index {
      json_copy(reason)
    } else if index == stop_reason_index {
      json_copy(marker)
    } else {
      json_copy(event)
    }
    fields(replacement).set("seq", integer(index))
    reordered_events.push(replacement)
  }
  fields(session).set("events", Json::array(reordered_events))
  let rejected = Engine::new(test_tools())
  let rejected_before = rejected.snapshot()
  assert_true(rejected.restore(reordered) is Err(_))
  assert_eq(rejected.snapshot(), rejected_before)
}

///|
test "allowed Stop settles before queued Start admission and replays once" {
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
        stop_response("answer before allowed Stop"),
      ),
    ),
  )
  let session_id = SessionId::new("hook-child").unwrap()
  let stop = engine.pending_stop_hook(session_id).unwrap()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["Start queued during Stop"]),
    Ok(true),
  )
  let settled = success(engine.finish_stop_hook(stop))
  assert_eq(event_type_count(settled, "hook/stop-settled"), 1)
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  assert_false(checkpoint.is_initial())
  assert_eq(checkpoint.contexts(), ["Start queued during Stop"])

  let interrupted = Engine::new(test_tools())
  assert_eq(interrupted.restore(engine.snapshot()), Ok(()))
  let interrupted_session = get_session_for(interrupted, "hook-child")
  assert_eq(get_status(interrupted_session), "failed")
  assert_eq(engine.take_effects().length(), 0)

  ignore(
    success(
      engine.accept_subagent_prompt_hook(checkpoint, ["prompt policy context"]),
    ),
  )
  let next = engine.take_effects()[0]
  let messages = subagent_hook_all_messages(next)
  assert_true(
    messages.any(message => {
      required_string(message, "role") == "assistant" &&
      subagent_hook_message_text(message) == "answer before allowed Stop"
    }),
  )
  assert_true(
    messages.any(message => {
      required_string(message, "role") == "user" &&
      subagent_hook_message_text(message) == "Start queued during Stop"
    }),
  )
  assert_true(
    messages.any(message => {
      required_string(message, "role") == "user" &&
      subagent_hook_message_text(message) == "prompt policy context"
    }),
  )
  let completed = success(
    engine.complete(id_of(next), stop_response("answer after queued Start")),
  )
  assert_eq(get_status(completed), "completed")
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), completed)

  let reordered = json_copy(snapshot)
  let sessions = array_value(
    required_field(reordered, "sessions"),
    "sessions",
    32,
  )
  let session = sessions[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let mut settled_index = -1
  let mut start_index = -1
  for index, event in events {
    let kind = required_string(event, "type")
    if kind == "hook/stop-settled" {
      settled_index = index
    } else if kind == "hook/subagent-start-context" {
      start_index = index
    }
  }
  assert_true(settled_index >= 0 && start_index > settled_index)
  let settled_event = events[settled_index]
  let start_event = events[start_index]
  let reordered_events : Array[Json] = []
  for index, event in events {
    let replacement = if index == settled_index {
      json_copy(start_event)
    } else if index == start_index {
      json_copy(settled_event)
    } else {
      json_copy(event)
    }
    fields(replacement).set("seq", integer(index))
    reordered_events.push(replacement)
  }
  fields(session).set("events", Json::array(reordered_events))
  let rejected = Engine::new(test_tools())
  let rejected_before = rejected.snapshot()
  assert_true(rejected.restore(reordered) is Err(_))
  assert_eq(rejected.snapshot(), rejected_before)
}

///|
test "allowed Stop settlement replays when context budget drops queued Start input" {
  let engine = subagent_hook_engine()
  let initial_contexts = Array::make(32, "initial Start context")
  assert_eq(
    engine.inject_hook_contexts("hook-child", initial_contexts),
    Ok(true),
  )
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", false),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let first = engine.take_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_stop_hook(
        subagent_stop_effect_id(first),
        stop_response("answer before exhausted context budget"),
      ),
    ),
  )
  let stop = engine
    .pending_stop_hook(SessionId::new("hook-child").unwrap())
    .unwrap()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["dropped late Start context"]),
    Ok(true),
  )
  let continued = success(engine.finish_stop_hook(stop))
  assert_eq(get_status(continued), "running")
  assert_eq(event_type_count(continued, "hook/stop-settled"), 1)
  assert_eq(event_type_count(continued, "hook/subagent-start-context"), 1)
  let next = engine.take_effects()[0]
  assert_false(
    subagent_hook_all_messages(next).any(message => {
      subagent_hook_message_text(message) == "dropped late Start context"
    }),
  )
  let completed = success(
    engine.complete(id_of(next), stop_response("answer after exhausted budget")),
  )
  assert_eq(get_status(completed), "completed")
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), completed)
}

///|
test "allowed Stop settlement preserves the answer when Start admission is denied" {
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
        stop_response("answer retained after Start denial"),
      ),
    ),
  )
  let stop = engine
    .pending_stop_hook(SessionId::new("hook-child").unwrap())
    .unwrap()
  assert_eq(
    engine.inject_hook_contexts("hook-child", ["rejected Start context"]),
    Ok(true),
  )
  ignore(success(engine.finish_stop_hook(stop)))
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  let blocked = success(
    engine.block_subagent_prompt_hook(checkpoint, "prompt policy denied"),
  )
  assert_eq(get_status(blocked), "failed")
  assert_eq(event_type_count(blocked, "hook/stop-settled"), 1)
  let transcript = array_value(
    required_field(blocked, "messages"),
    "messages",
    16,
  )
  assert_true(
    transcript.any(message => {
      subagent_hook_message_text(message) ==
      "answer retained after Start denial"
    }),
  )
  assert_false(
    transcript.any(message => {
      subagent_hook_message_text(message) == "rejected Start context"
    }),
  )
  assert_eq(event_type_count(blocked, "hook/subagent-start-context"), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), blocked)
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

///|
test "child PostToolUse inbox passes through the next UserPromptSubmit checkpoint in call order" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([
          ("child-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("child-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  ignore(
    success(
      engine.complete(
        id_of(reads[1]),
        fixture(
          "{\"ok\":true,\"content\":\"beta\",\"additional_contexts\":[\"B\"]}",
        ),
      ),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(reads[0]),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"A1\",\"A2\"]}",
        ),
      ),
    ),
  )
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  assert_eq(checkpoint.prompt(), "A1A2B")
  assert_true(engine.take_effects().is_empty())
  ignore(success(engine.accept_subagent_prompt_hook(checkpoint, ["U"])))
  let next_provider = engine.take_effects()[0]
  let messages = subagent_hook_all_messages(next_provider)
  assert_eq(messages.length(), 7)
  assert_eq(subagent_hook_message_text(messages[4]), "A1A2")
  assert_eq(subagent_hook_message_text(messages[5]), "B")
  assert_eq(subagent_hook_message_text(messages[6]), "U")
  assert_eq(
    required_field(messages[4], "source"),
    Json::object({ "kind": "hooks-claude-code" }),
  )
}

///|
test "pending child UserPromptSubmit blocks prompt admission and denial" {
  let accepting = subagent_hook_post_tool_pending_engine()
  let accept_checkpoint = accepting
    .pending_subagent_prompt_hook("hook-child")
    .unwrap()
  let accept_invocation = accepting
    .record_native_hook_invoked(
      "hook-child",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:81",
      None,
    )
    .unwrap()
  let accept_before = accepting.snapshot()
  assert_true(
    accepting.accept_subagent_prompt_hook(accept_checkpoint, ["next"]) is Err(_),
  )
  assert_eq(accepting.snapshot(), accept_before)
  assert_true(accepting.take_effects().is_empty())
  ignore(
    accepting.record_native_hook_result(
      accept_invocation,
      "pass",
      Some(0),
      None,
      1,
    ),
  )
  assert_true(
    accepting.accept_subagent_prompt_hook(accept_checkpoint, ["next"]) is Ok(_),
  )
  assert_eq(accepting.take_effects().length(), 1)
  assert_eq(Engine::new(test_tools()).restore(accepting.snapshot()), Ok(()))

  let blocking = subagent_hook_post_tool_pending_engine()
  let block_checkpoint = blocking
    .pending_subagent_prompt_hook("hook-child")
    .unwrap()
  let block_invocation = blocking
    .record_native_hook_invoked(
      "hook-child",
      "UserPromptSubmit",
      "claude-code:UserPromptSubmit:82",
      None,
    )
    .unwrap()
  let block_before = blocking.snapshot()
  assert_true(
    blocking.block_subagent_prompt_hook(block_checkpoint, "denied") is Err(_),
  )
  assert_eq(blocking.snapshot(), block_before)
  assert_true(blocking.take_effects().is_empty())
  ignore(
    blocking.record_native_hook_result(
      block_invocation,
      "deny",
      Some(0),
      None,
      1,
    ),
  )
  assert_true(
    blocking.block_subagent_prompt_hook(block_checkpoint, "denied") is Ok(_),
  )
  assert_true(blocking.take_effects().is_empty())
  assert_eq(Engine::new(test_tools()).restore(blocking.snapshot()), Ok(()))
}

///|
test "settled child PostToolUse admission restores and rejects reordered source messages" {
  let engine = subagent_hook_post_tool_pending_engine()
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  assert_eq(checkpoint.contexts(), ["start context", "A"])
  ignore(success(engine.accept_subagent_prompt_hook(checkpoint, ["U"])))
  let next_provider = engine.take_effects()[0]
  let sourced = subagent_hook_all_messages(next_provider).filter(message => {
    fields(message).get("source") is Some(_)
  })
  assert_eq(sourced.map(subagent_hook_message_text), ["start context", "A", "U"])
  let completed = success(
    engine.complete(id_of(next_provider), stop_response("done")),
  )
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), completed)

  let forged = subagent_hook_forge_reordered_post_tool_message(snapshot)
  let untouched = Engine::new(test_tools())
  let before = untouched.snapshot()
  assert_true(untouched.restore(forged) is Err(_))
  assert_eq(untouched.snapshot(), before)
}

///|
test "denied child PostToolUse prompt admission restores without its context messages" {
  let engine = subagent_hook_post_tool_pending_engine()
  let checkpoint = engine.pending_subagent_prompt_hook("hook-child").unwrap()
  let blocked = success(
    engine.block_subagent_prompt_hook(checkpoint, "review denied"),
  )
  assert_eq(get_status(blocked), "failed")
  assert_eq(
    event_type_count(blocked, "hook/subagent-post-tool-prompt-rejected"),
    1,
  )
  assert_true(
    array_value(required_field(blocked, "messages"), "messages", 16).all(message => {
      let text = subagent_hook_message_text(message)
      text != "start context" && text != "A"
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), blocked)
}

///|
test "unresolved child PostToolUse prompt admission restores interrupted without replay" {
  let engine = subagent_hook_post_tool_pending_engine()
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  let interrupted = get_session_for(restored, "hook-child")
  assert_eq(get_status(interrupted), "failed")
  assert_eq(
    event_type_count(interrupted, "hook/subagent-post-tool-prompt-pending"),
    1,
  )
  assert_eq(event_type_count(interrupted, "hook/post-tool-prompt-abandoned"), 1)
  assert_true(restored.take_effects().is_empty())
  let replay = Engine::new(test_tools())
  assert_eq(replay.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session_for(replay, "hook-child"), interrupted)
}

///|
test "child cancellation abandons known PostToolUse context while a sibling is still active" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([
          ("child-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("child-b", "read", "{\"file_path\":\"b.txt\"}"),
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
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"A\"]}",
        ),
      ),
    ),
  )
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"hook-child\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")
  assert_eq(
    event_type_count(cancelled, "hook/subagent-post-tool-prompt-abandoned"),
    1,
  )
  let messages = array_value(
    required_field(cancelled, "messages"),
    "child cancellation messages",
    16,
  )
  assert_true(
    messages.any(message => {
      required_string(message, "role") == "tool" &&
      required_string(message, "content") == "alpha"
    }),
  )
  assert_false(
    messages.any(message => {
      fields(message).get("source") is Some(_) &&
      subagent_hook_message_text(message) == "A"
    }),
  )
  assert_true(engine.take_effects().is_empty())
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session_for(restored, "hook-child"), cancelled)
  let fresh = success(
    engine.invoke(
      "session_send",
      fixture(
        "{\"session_id\":\"hook-child\",\"prompt\":\"fresh prompt after cancellation\"}",
      ),
    ),
  )
  assert_eq(get_status(fresh), "running")
  let fresh_effects = engine.take_effects()
  assert_eq(fresh_effects.length(), 1)
  assert_eq(required_string(fresh_effects[0], "kind"), "llm")
  assert_true(engine.pending_subagent_prompt_hook("hook-child") is None)
  let fresh_user_messages = subagent_hook_all_messages(fresh_effects[0]).filter(message => {
      required_string(message, "role") == "user"
    },
  )
  assert_eq(fresh_user_messages.map(subagent_hook_message_text), [
    "child prompt", "fresh prompt after cancellation",
  ])
}

///|
test "restore enforces combined late Start and child PostTool context count" {
  let snapshot = subagent_hook_completed_post_tool_snapshot([])
  let exact = subagent_hook_forge_start_contexts(snapshot, Array::make(31, "s"))
  let valid = Engine::new(test_tools())
  assert_eq(valid.restore(exact), Ok(()))

  let one_over = subagent_hook_forge_start_contexts(
    snapshot,
    Array::make(32, "s"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(one_over) is Err(_))
  assert_eq(destination.snapshot(), before)

  let two_over = subagent_hook_forge_start_contexts(
    subagent_hook_completed_post_tool_snapshot(["U"]),
    Array::make(32, "s"),
  )
  let second_destination = Engine::new(test_tools())
  let second_before = second_destination.snapshot()
  assert_true(second_destination.restore(two_over) is Err(_))
  assert_eq(second_destination.snapshot(), second_before)
}

///|
test "restore enforces combined late Start and child PostTool UTF-16 length" {
  let snapshot = subagent_hook_completed_post_tool_snapshot([])
  let exact = subagent_hook_forge_start_contexts(
    snapshot,
    subagent_hook_large_contexts("d".repeat(4093) + "😀"),
  )
  let valid = Engine::new(test_tools())
  assert_eq(valid.restore(exact), Ok(()))

  let one_unit_over = subagent_hook_forge_start_contexts(
    snapshot,
    subagent_hook_large_contexts("d".repeat(4094) + "😀"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(one_unit_over) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "over-limit child PostTool prompt checkpoints terminate with restorable abandonment" {
  let over_count = subagent_hook_over_limit_post_tool_engine(
    Array::make(32, "A"),
  )
  assert_eq(get_status(over_count.1), "failed")
  assert_eq(
    event_type_count(over_count.1, "hook/subagent-post-tool-prompt-abandoned"),
    1,
  )
  assert_true(
    array_value(
      required_field(over_count.1, "messages"),
      "count-limited child messages",
      16,
    ).any(message => {
      required_string(message, "role") == "tool" &&
      required_string(message, "content") == "alpha"
    }),
  )
  let count_restore = Engine::new(test_tools())
  assert_eq(count_restore.restore(over_count.0.snapshot()), Ok(()))
  assert_eq(get_session_for(count_restore, "hook-child"), over_count.1)

  let over_length = subagent_hook_over_limit_post_tool_engine([
    "a".repeat(4096),
    "b".repeat(4096),
    "c".repeat(4096),
    "d".repeat(4096),
  ])
  assert_eq(get_status(over_length.1), "failed")
  assert_eq(
    event_type_count(over_length.1, "hook/subagent-post-tool-prompt-abandoned"),
    1,
  )
  let length_restore = Engine::new(test_tools())
  assert_eq(length_restore.restore(over_length.0.snapshot()), Ok(()))
  assert_eq(get_session_for(length_restore, "hook-child"), over_length.1)
}

///|
test "restore abandons child PostTool context completed before sibling result" {
  let engine = subagent_hook_partial_post_tool_engine()
  let session = get_session_for(engine, "hook-child")
  let events = array_value(
    required_field(session, "events"),
    "partial child completion events",
    64,
  )
  assert_true(
    events.any(event => {
      if required_string(event, "type") != "tool/completed" {
        false
      } else {
        let data = required_field(event, "data")
        required_string(data, "call_id") == "child-a" &&
        required_field(data, "subagent_post_tool_prompt_hook") == boolean(true)
      }
    }),
  )
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  let interrupted = get_session_for(restored, "hook-child")
  assert_eq(get_status(interrupted), "failed")
  assert_eq(
    event_type_count(interrupted, "hook/subagent-post-tool-prompt-abandoned"),
    1,
  )
  let messages = array_value(
    required_field(interrupted, "messages"),
    "interrupted child messages",
    16,
  )
  assert_true(
    messages.any(message => {
      required_string(message, "role") == "tool" &&
      required_string(message, "content") == "alpha"
    }),
  )
  assert_false(
    messages.any(message => {
      fields(message).get("source") is Some(_) &&
      subagent_hook_message_text(message) == "A"
    }),
  )
  assert_true(restored.take_effects().is_empty())
  let replay = Engine::new(test_tools())
  assert_eq(replay.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session_for(replay, "hook-child"), interrupted)
  assert_true(replay.take_effects().is_empty())
}

///|
test "child completion metadata keeps child admission precedence" {
  let engine = subagent_hook_engine()
  let initial = subagent_checkpoint_success(
    engine.begin_subagent_prompt_hook("hook-child", "child prompt", true),
  )
  ignore(success(engine.accept_subagent_prompt_hook(initial, [])))
  let provider = engine.take_effects()[0]
  ignore(
    success(
      engine.complete(
        id_of(provider),
        calls_response([("child-read", "read", "{\"file_path\":\"a.txt\"}")]),
      ),
    ),
  )
  let read = engine.take_effects()[0]
  ignore(
    success(
      engine.complete_effect_with_post_tool_prompt_hook(
        subagent_stop_effect_id(read),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"A\"]}",
        ),
      ),
    ),
  )
  let session = get_session_for(engine, "hook-child")
  let events = array_value(
    required_field(session, "events"),
    "child admission completion events",
    64,
  )
  let mut completion : Json? = None
  for event in events {
    if required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "child-read" {
      completion = Some(event)
    }
  }
  let completion = completion.unwrap()
  let data = required_field(completion, "data")
  assert_eq(
    required_field(data, "subagent_post_tool_prompt_hook"),
    boolean(true),
  )
  assert_true(fields(data).get("post_tool_prompt_hook") is None)
  assert_eq(Engine::new(test_tools()).restore(engine.snapshot()), Ok(()))

  let forged = json_copy(engine.snapshot())
  let forged_session = array_value(
      required_field(forged, "sessions"),
      "forged child admission sessions",
      32,
    )[0]
  let forged_events = array_value(
    required_field(forged_session, "events"),
    "forged child admission events",
    64,
  )
  for event in forged_events {
    if required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "child-read" {
      fields(required_field(event, "data")).set(
        "post_tool_prompt_hook",
        boolean(true),
      )
    }
  }
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}
