///|
fn fixture(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("Invalid test fixture")
  }
}

///|
fn success(result : Result[Json, String]) -> Json {
  match result {
    Ok(value) => value
    Err(message) => abort("Unexpected engine error: \{message}")
  }
}

///|
fn test_tools() -> Array[Json] {
  [
    fixture(
      "{\"name\":\"read\",\"description\":\"Read text\",\"input_schema\":{\"type\":\"object\",\"required\":[\"file_path\"],\"properties\":{\"file_path\":{\"type\":\"string\"}},\"additionalProperties\":false},\"effect\":\"read\"}",
    ),
    fixture(
      "{\"name\":\"write\",\"description\":\"Write text\",\"input_schema\":{\"type\":\"object\",\"required\":[\"file_path\",\"content\"],\"properties\":{\"file_path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}}},\"effect\":\"write\"}",
    ),
    fixture(
      "{\"name\":\"bash\",\"description\":\"Run a command\",\"input_schema\":{\"type\":\"object\",\"required\":[\"command\"],\"properties\":{\"command\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"}}},\"effect\":\"shell\"}",
    ),
  ]
}

///|
fn started_engine(max_steps? : Int = 16) -> (Engine, Json) {
  let engine = Engine::new(test_tools())
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("test")), ("max_steps", integer(max_steps))]),
      ),
    ),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture(
          "{\"session_id\":\"test\",\"prompt\":\"Please inspect the project\"}",
        ),
      ),
    ),
  )
  let effects = engine.take_effects()
  if effects.length() != 1 {
    abort("Expected one LLM effect")
  }
  (engine, effects[0])
}

///|
fn get_session(engine : Engine) -> Json {
  success(engine.invoke("session_get", fixture("{\"session_id\":\"test\"}")))
}

///|
fn id_of(effect : Json) -> String {
  required_string(effect, "id") catch {
    _ => abort("Missing effect id")
  }
}

///|
fn call_id_of(effect : Json) -> String {
  required_string(required_field(effect, "request"), "call_id") catch {
    _ => abort("Missing tool effect call id")
  }
}

///|
fn get_status(value : Json) -> String {
  required_string(value, "status") catch {
    _ => abort("Missing status")
  }
}

///|
fn stop_response(text : String) -> Json {
  object([
    ("ok", boolean(true)),
    ("content", Json::string(text)),
    ("tool_calls", Json::array([])),
    ("finish_reason", Json::string("stop")),
  ])
}

///|
fn calls_response(calls : Array[(String, String, String)]) -> Json {
  object([
    ("ok", boolean(true)),
    ("content", Json::string("")),
    (
      "tool_calls",
      Json::array(
        calls.map(call => {
          object([
            ("id", Json::string(call.0)),
            ("name", Json::string(call.1)),
            ("arguments", Json::string(call.2)),
          ])
        }),
      ),
    ),
    ("finish_reason", Json::string("tool_calls")),
  ])
}

///|
fn engine_waiting_on_exclusive_call(
  name : String,
  arguments : String,
) -> Engine {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("barrier", name, arguments),
          ("read-after", "read", "{\"file_path\":\"after.txt\"}"),
        ]),
      ),
    ),
  )
  engine
}

///|
fn append_forged_read_dispatch(snapshot : Json) -> Json raise EngineError {
  let session = array_value(
      required_field(snapshot, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let turn_id = required_field(session, "turn_id")
  let step = required_field(session, "step")
  let call_id = "read-after"
  let arguments = "{\"file_path\":\"after.txt\"}"
  events.push(
    object([
      ("seq", integer(events.length())),
      ("type", Json::string("tool/call")),
      ("turn_id", turn_id),
      ("step", step),
      (
        "data",
        object([
          ("id", Json::string(call_id)),
          ("name", Json::string("read")),
          ("arguments", Json::string(arguments)),
        ]),
      ),
    ]),
  )
  let effect_number = int_value(
    required_field(snapshot, "next_effect"),
    "next_effect",
    1,
    999999999,
  )
  let effect_id = "effect-\{effect_number}"
  events.push(
    object([
      ("seq", integer(events.length())),
      ("type", Json::string("tool/request")),
      ("turn_id", turn_id),
      ("step", step),
      (
        "data",
        object([
          ("effect_id", Json::string(effect_id)),
          ("call_id", Json::string(call_id)),
        ]),
      ),
    ]),
  )
  fields(session).set("events", Json::array(events))
  fields(snapshot).set("next_effect", integer(effect_number + 1))
  snapshot
}

///|
fn remove_last_snapshot_event(
  snapshot : Json,
  expected_kind : String,
  status : String?,
) -> Json raise EngineError {
  let session = array_value(
      required_field(snapshot, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  if events.is_empty() ||
    required_string(events[events.length() - 1], "type") != expected_kind {
    abort("Unexpected final event while constructing a barrier probe")
  }
  let kept = []
  for index = 0; index < events.length() - 1; index = index + 1 {
    kept.push(events[index])
  }
  fields(session).set("events", Json::array(kept))
  match status {
    Some(status) => {
      fields(session).set("status", Json::string(status))
      fields(session).remove("pending_approval")
    }
    None => ()
  }
  snapshot
}

///|
test "upstream tool-call-turn distilled transcript preserves correlation and follow-up history" {
  // Source: deepseek-ai/deepseek-harness @
  // 5badb15009ae1756c3afe0ae0cef1faafc290ccc,
  // snapshots/session/tool-call-turn/session.v4.jsonl.
  // The model calls bash echo SNAPSHOT_OK, receives its result, then says DONE.
  // This tests the projected scenario, not upstream v4 storage compatibility.
  let (engine, llm) = started_engine()
  let waiting = success(
    engine.complete(
      id_of(llm),
      calls_response([
        (
          "call_00_Rn2Mz1y8uZN62ukEXiNO2077", "bash", "{\"command\":\"echo SNAPSHOT_OK\",\"description\":\"Run echo SNAPSHOT_OK\"}",
        ),
      ]),
    ),
  )
  assert_eq(get_status(waiting), "awaiting_approval")
  assert_eq(engine.take_effects().length(), 0)
  ignore(
    success(
      engine.invoke(
        "tool_approve",
        fixture(
          "{\"session_id\":\"test\",\"call_id\":\"call_00_Rn2Mz1y8uZN62ukEXiNO2077\",\"approved\":true}",
        ),
      ),
    ),
  )
  let shell = engine.take_effects()[0]
  assert_eq(required_string(shell, "kind"), "tool")
  let shell_request = required_field(shell, "request")
  assert_eq(
    required_string(shell_request, "call_id"),
    "call_00_Rn2Mz1y8uZN62ukEXiNO2077",
  )
  ignore(
    success(
      engine.complete(
        id_of(shell),
        fixture("{\"ok\":true,\"content\":\"SNAPSHOT_OK\\n\"}"),
      ),
    ),
  )
  let second = engine.take_effects()[0]
  let history = array_value(
    required_field(required_field(second, "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(history.length(), 3)
  assert_eq(
    required_string(history[2], "tool_call_id"),
    "call_00_Rn2Mz1y8uZN62ukEXiNO2077",
  )
  assert_eq(required_string(history[2], "content"), "SNAPSHOT_OK\n")
  let done = success(engine.complete(id_of(second), stop_response("DONE")))
  assert_eq(get_status(done), "completed")
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), done)
}

///|
test "read calls overlap while durable results stay in model order" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("first", "read", "{\"file_path\":\"one.txt\"}"),
          ("second", "read", "{\"file_path\":\"two.txt\"}"),
        ]),
      ),
    ),
  )
  let first = engine.take_effects()
  assert_eq(first.length(), 2)
  assert_eq(call_id_of(first[0]), "first")
  assert_eq(call_id_of(first[1]), "second")
  ignore(
    success(
      engine.complete(
        id_of(first[1]),
        fixture("{\"ok\":true,\"content\":\"two\"}"),
      ),
    ),
  )
  assert_eq(engine.take_effects().length(), 0)
  let early = get_session(engine)
  assert_eq(
    array_value(required_field(early, "messages"), "messages", 100).length(),
    2,
  )
  ignore(
    success(
      engine.complete(
        id_of(first[0]),
        fixture("{\"ok\":false,\"error\":\"Missing file\"}"),
      ),
    ),
  )
  let next = engine.take_effects()[0]
  let messages = array_value(
    required_field(required_field(next, "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(required_string(messages[2], "tool_call_id"), "first")
  assert_eq(required_field(messages[2], "is_error"), boolean(true))
  assert_eq(required_string(messages[3], "tool_call_id"), "second")
  assert_eq(required_field(messages[3], "is_error"), boolean(false))
  assert_eq(required_string(messages[3], "content"), "two")
}

///|
test "UserPromptSubmit contexts are one source-tagged message after the prompt" {
  let engine = Engine::new(test_tools())
  let session_id = SessionId::new("prompt-context-session").unwrap()
  ignore(
    success(
      engine.invoke("session_create", {
        "id": Json::string(session_id.as_string()),
        "title": Json::string("Prompt hook context"),
      }),
    ),
  )
  let session = success(
    engine.invoke("session_send", {
      "session_id": Json::string(session_id.as_string()),
      "prompt": Json::string("original prompt"),
      "additional_contexts": Json::array([
        Json::string("first hook context"),
        Json::string("second hook context"),
      ]),
    }),
  )
  let messages = array_value(required_field(session, "messages"), "messages", 8)
  assert_eq(messages.length(), 2)
  assert_eq(required_string(messages[0], "content"), "original prompt")
  assert_eq(required_string(messages[1], "role"), "user")
  assert_eq(
    required_field(messages[1], "source"),
    Json::object({ "kind": Json::string("hooks-claude-code") }),
  )
  assert_eq(
    required_string(messages[1], "content"),
    "first hook context\nsecond hook context",
  )
  let events = array_value(required_field(session, "events"), "events", 16)
  let user_message_events = events.filter(event => {
    required_string(event, "type") == "user/message"
  })
  assert_eq(user_message_events.length(), 2)
  assert_eq(
    required_string(required_field(user_message_events[0], "data"), "content"),
    "original prompt",
  )
  let context_event = required_field(user_message_events[1], "data")
  assert_eq(
    required_field(context_event, "source"),
    Json::object({ "kind": Json::string("hooks-claude-code") }),
  )
  assert_eq(
    array_value(required_field(context_event, "content"), "content", 8).map(block => {
      required_string(block, "text")
    }),
    ["first hook context", "second hook context"],
  )
  let mut last_user_message_index = -1
  let mut llm_request_index = -1
  for index, event in events {
    match required_string(event, "type") {
      "user/message" => last_user_message_index = index
      "llm/request" => llm_request_index = index
      _ => ()
    }
  }
  assert_true(
    last_user_message_index >= 0 && last_user_message_index < llm_request_index,
  )
  let provider = engine.take_effects()[0]
  let request_messages = array_value(
    required_field(required_field(provider, "request"), "messages"),
    "provider messages",
    8,
  )
  assert_eq(request_messages.length(), 2)
  assert_eq(
    array_value(required_field(request_messages[1], "content"), "content", 8).map(block => {
        required_string(block, "text")
      },
    ),
    ["first hook context", "second hook context"],
  )
  ignore(success(engine.complete(id_of(provider), stop_response("done"))))
  let settled = success(
    engine.invoke("session_get", {
      "session_id": Json::string(session_id.as_string()),
    }),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(
    success(
      restored.invoke("session_get", {
        "session_id": Json::string(session_id.as_string()),
      }),
    ),
    settled,
  )
}

///|
test "PostToolUse contexts stay structured after every result and reject forged restore" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("context-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("context-b", "read", "{\"file_path\":\"b.txt\"}"),
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
          "{\"ok\":true,\"content\":\"beta\",\"additional_contexts\":[\"b context\"]}",
        ),
      ),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(reads[0]),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"a context\",\"second a context\"]}",
        ),
      ),
    ),
  )
  let follow_up = engine.take_effects()[0]
  let messages = array_value(
    required_field(required_field(follow_up, "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 6)
  assert_eq(required_string(messages[2], "tool_call_id"), "context-a")
  assert_eq(required_string(messages[3], "tool_call_id"), "context-b")
  assert_eq(required_string(messages[4], "role"), "user")
  assert_eq(
    array_value(required_field(messages[4], "content"), "content", 8).map(block => {
      required_string(block, "text")
    }),
    ["a context", "second a context"],
  )
  assert_eq(
    required_field(messages[4], "source"),
    Json::object({ "kind": "hooks-claude-code" }),
  )
  assert_eq(
    array_value(required_field(messages[5], "content"), "content", 8).map(block => {
      required_string(block, "text")
    }),
    ["b context"],
  )

  ignore(success(engine.complete(id_of(follow_up), stop_response("Done"))))
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(snapshot), Ok(()))
  assert_eq(get_session(restored), get_session(engine))

  let tampered = engine.snapshot()
  let session = array_value(
      required_field(tampered, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  let mut forged = false
  for event in events {
    if required_string(event, "type") == "user/message" &&
      fields(required_field(event, "data")).get("source") is Some(_) {
      let content = array_value(
        required_field(required_field(event, "data"), "content"),
        "content",
        8,
      )
      fields(content[0]).set("text", Json::string("forged context"))
      forged = true
      break
    }
  }
  assert_true(forged)
  assert_true(Engine::new(test_tools()).restore(tampered) is Err(_))
}

///|
test "known host outcome stays behind earlier reads and finalizes before restore" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  assert_eq(reads.length(), 2)
  ignore(
    success(
      engine.record_effect_outcome(
        id_of(reads[0]),
        fixture("{\"ok\":true,\"content\":\"alpha\"}"),
      ),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(reads[1]),
        fixture("{\"ok\":true,\"content\":\"beta\"}"),
      ),
    ),
  )
  let pending = get_session(engine)
  assert_eq(
    array_value(required_field(pending, "messages"), "messages", 100).length(),
    2,
  )
  let pending_events = array_value(
    required_field(pending, "events"),
    "events",
    100,
  )
  assert_true(
    pending_events.any(event => {
      required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "read-a" &&
      required_string(required_field(event, "data"), "source") == "effect-known"
    }),
  )
  assert_true(
    pending_events.any(event => {
      required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "read-b" &&
      required_string(required_field(event, "data"), "source") == "effect"
    }),
  )
  assert_true(
    pending_events.any(event => {
      required_string(event, "type") == "tool/completed" &&
      required_string(required_field(event, "data"), "call_id") == "read-b" &&
      fields(required_field(event, "data")).get("additional_contexts") is None
    }),
  )
  assert_true(
    !pending_events.any(event => required_string(event, "type") == "tool/result"),
  )
  let provider = success(
    engine.complete(
      id_of(reads[0]),
      fixture(
        "{\"ok\":false,\"error\":\"PostToolUse hook blocked the result\"}",
      ),
    ),
  )
  assert_eq(get_status(provider), "running")
  let followup = engine.take_effects()
  assert_eq(followup.length(), 1)
  let history = array_value(
    required_field(required_field(followup[0], "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(required_string(history[2], "tool_call_id"), "read-a")
  assert_eq(required_field(history[2], "is_error"), boolean(true))
  assert_true(required_string(history[2], "content").contains("PostToolUse"))
  assert_eq(required_string(history[3], "tool_call_id"), "read-b")
  assert_eq(required_field(history[3], "is_error"), boolean(false))
  assert_eq(required_string(history[3], "content"), "beta")
  let finished = success(
    engine.complete(id_of(followup[0]), stop_response("Done")),
  )
  assert_eq(get_status(finished), "completed")
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), finished)
}

///|
test "session cancellation commits a known host outcome and restores it without replay" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  ignore(
    success(
      engine.record_effect_outcome(
        id_of(reads[0]),
        fixture("{\"ok\":true,\"content\":\"alpha\"}"),
      ),
    ),
  )
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")
  let messages = array_value(
    required_field(cancelled, "messages"),
    "messages",
    100,
  )
  assert_eq(required_string(messages[2], "tool_call_id"), "read-a")
  assert_eq(required_string(messages[2], "content"), "alpha")
  assert_eq(required_field(messages[2], "is_error"), boolean(false))
  assert_eq(required_string(messages[3], "tool_call_id"), "read-b")
  assert_eq(required_field(messages[3], "is_error"), boolean(true))
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), cancelled)
  assert_eq(restored.take_effects().length(), 0)
}

///|
test "termination commits accepted PostToolUse contexts before closing the batch" {
  let (cancelled_engine, llm) = started_engine()
  ignore(
    success(
      cancelled_engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = cancelled_engine.take_effects()
  ignore(
    success(
      cancelled_engine.complete(
        id_of(reads[0]),
        fixture(
          "{\"ok\":true,\"content\":\"alpha\",\"additional_contexts\":[\"accepted context\"]}",
        ),
      ),
    ),
  )
  let cancelled = success(
    cancelled_engine.invoke(
      "session_cancel",
      fixture("{\"session_id\":\"test\"}"),
    ),
  )
  assert_eq(get_status(cancelled), "cancelled")
  let cancelled_messages = array_value(
    required_field(cancelled, "messages"),
    "messages",
    100,
  )
  assert_eq(cancelled_messages.length(), 5)
  assert_eq(required_string(cancelled_messages[2], "tool_call_id"), "read-a")
  assert_eq(required_string(cancelled_messages[3], "tool_call_id"), "read-b")
  assert_eq(required_field(cancelled_messages[3], "is_error"), boolean(true))
  assert_eq(required_string(cancelled_messages[4], "role"), "user")
  assert_eq(
    required_field(cancelled_messages[4], "source"),
    Json::object({ "kind": "hooks-claude-code" }),
  )
  assert_eq(
    required_string(cancelled_messages[4], "content"),
    "accepted context",
  )
  let cancelled_restored = Engine::new(test_tools())
  assert_eq(cancelled_restored.restore(cancelled_engine.snapshot()), Ok(()))
  let cancelled_reopened = Engine::new(test_tools())
  assert_eq(cancelled_reopened.restore(cancelled_restored.snapshot()), Ok(()))
  assert_eq(get_session(cancelled_reopened), cancelled)

  let (interrupted_engine, interrupted_llm) = started_engine()
  ignore(
    success(
      interrupted_engine.complete(
        id_of(interrupted_llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let interrupted_reads = interrupted_engine.take_effects()
  ignore(
    success(
      interrupted_engine.complete(
        id_of(interrupted_reads[1]),
        fixture(
          "{\"ok\":true,\"content\":\"beta\",\"additional_contexts\":[\"restored context\"]}",
        ),
      ),
    ),
  )
  let interrupted_restored = Engine::new(test_tools())
  assert_eq(interrupted_restored.restore(interrupted_engine.snapshot()), Ok(()))
  let interrupted = get_session(interrupted_restored)
  assert_eq(get_status(interrupted), "failed")
  let interrupted_messages = array_value(
    required_field(interrupted, "messages"),
    "messages",
    100,
  )
  assert_eq(interrupted_messages.length(), 5)
  assert_eq(required_string(interrupted_messages[2], "tool_call_id"), "read-a")
  assert_eq(required_string(interrupted_messages[3], "tool_call_id"), "read-b")
  assert_eq(required_field(interrupted_messages[3], "is_error"), boolean(false))
  assert_eq(required_string(interrupted_messages[4], "role"), "user")
  assert_eq(
    required_string(interrupted_messages[4], "content"),
    "restored context",
  )
  let interrupted_reopened = Engine::new(test_tools())
  assert_eq(
    interrupted_reopened.restore(interrupted_restored.snapshot()),
    Ok(()),
  )
  assert_eq(get_session(interrupted_reopened), interrupted)
}

///|
test "read pool is bounded and replenishes as individual effects settle" {
  let (engine, llm) = started_engine()
  let calls = []
  for index = 0; index < 6; index = index + 1 {
    calls.push(("read-\{index}", "read", "{\"file_path\":\"f\{index}.txt\"}"))
  }
  ignore(success(engine.complete(id_of(llm), calls_response(calls))))
  let initial = engine.take_effects()
  assert_eq(initial.length(), 4)
  for index = 0; index < 4; index = index + 1 {
    assert_eq(call_id_of(initial[index]), "read-\{index}")
  }
  ignore(
    success(
      engine.complete(
        id_of(initial[3]),
        fixture("{\"ok\":true,\"content\":\"three\"}"),
      ),
    ),
  )
  let fifth = engine.take_effects()
  assert_eq(fifth.length(), 1)
  assert_eq(call_id_of(fifth[0]), "read-4")
  ignore(
    success(
      engine.complete(
        id_of(fifth[0]),
        fixture("{\"ok\":true,\"content\":\"four\"}"),
      ),
    ),
  )
  let sixth = engine.take_effects()
  assert_eq(sixth.length(), 1)
  assert_eq(call_id_of(sixth[0]), "read-5")
  ignore(
    success(
      engine.complete(
        id_of(sixth[0]),
        fixture("{\"ok\":true,\"content\":\"five\"}"),
      ),
    ),
  )
  assert_eq(engine.take_effects().length(), 0)
  ignore(
    success(
      engine.complete(
        id_of(initial[0]),
        fixture("{\"ok\":true,\"content\":\"zero\"}"),
      ),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(initial[2]),
        fixture("{\"ok\":true,\"content\":\"two\"}"),
      ),
    ),
  )
  ignore(
    success(
      engine.complete(
        id_of(initial[1]),
        fixture("{\"ok\":true,\"content\":\"one\"}"),
      ),
    ),
  )
  let next = engine.take_effects()[0]
  let history = array_value(
    required_field(required_field(next, "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(history.length(), 8)
  for index = 0; index < 6; index = index + 1 {
    assert_eq(
      required_string(history[index + 2], "tool_call_id"),
      "read-\{index}",
    )
  }
}

///|
test "read groups drain before an approved write barrier and later reads" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
          ("write", "write", "{\"file_path\":\"c.txt\",\"content\":\"c\"}"),
          ("read-c", "read", "{\"file_path\":\"c.txt\"}"),
        ]),
      ),
    ),
  )
  let reads = engine.take_effects()
  assert_eq(reads.length(), 2)
  ignore(
    success(
      engine.complete(
        id_of(reads[1]),
        fixture("{\"ok\":true,\"content\":\"b\"}"),
      ),
    ),
  )
  assert_eq(get_status(get_session(engine)), "running")
  assert_eq(engine.take_effects().length(), 0)
  let waiting = success(
    engine.complete(id_of(reads[0]), fixture("{\"ok\":true,\"content\":\"a\"}")),
  )
  assert_eq(get_status(waiting), "awaiting_approval")
  assert_eq(engine.take_effects().length(), 0)
  ignore(
    success(
      engine.invoke(
        "tool_approve",
        fixture(
          "{\"session_id\":\"test\",\"call_id\":\"write\",\"approved\":true}",
        ),
      ),
    ),
  )
  let write = engine.take_effects()
  assert_eq(write.length(), 1)
  assert_eq(call_id_of(write[0]), "write")
  ignore(
    success(
      engine.complete(
        id_of(write[0]),
        fixture("{\"ok\":true,\"content\":\"written\"}"),
      ),
    ),
  )
  let last_read = engine.take_effects()
  assert_eq(last_read.length(), 1)
  assert_eq(call_id_of(last_read[0]), "read-c")
  ignore(
    success(
      engine.complete(
        id_of(last_read[0]),
        fixture("{\"ok\":true,\"content\":\"c\"}"),
      ),
    ),
  )
  let next = engine.take_effects()[0]
  let history = array_value(
    required_field(required_field(next, "request"), "messages"),
    "messages",
    100,
  )
  for index = 0; index < 4; index = index + 1 {
    let expected = ["read-a", "read-b", "write", "read-c"][index]
    assert_eq(required_string(history[index + 2], "tool_call_id"), expected)
  }
}

///|
test "unknown and schema-invalid calls drain reads before local failures" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("unknown", "unregistered", "{}"),
          ("invalid", "read", "{\"file_path\":7}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  let first = engine.take_effects()
  assert_eq(first.length(), 1)
  assert_eq(call_id_of(first[0]), "read-a")
  let before = array_value(
    required_field(get_session(engine), "events"),
    "events",
    100,
  )
  assert_true(
    !before.any(event => {
      required_string(event, "type") == "tool/call" &&
      required_string(required_field(event, "data"), "id") == "unknown"
    }),
  )
  ignore(
    success(
      engine.complete(
        id_of(first[0]),
        fixture("{\"ok\":true,\"content\":\"a\"}"),
      ),
    ),
  )
  let next = engine.take_effects()
  assert_eq(next.length(), 1)
  assert_eq(call_id_of(next[0]), "read-b")
  let messages = array_value(
    required_field(get_session(engine), "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 5)
  assert_eq(required_string(messages[2], "tool_call_id"), "read-a")
  assert_eq(required_string(messages[3], "tool_call_id"), "unknown")
  assert_eq(required_field(messages[3], "is_error"), boolean(true))
  assert_eq(required_string(messages[4], "tool_call_id"), "invalid")
  assert_eq(required_field(messages[4], "is_error"), boolean(true))
}

///|
test "write approval is explicit and denial never produces a tool effect" {
  let (engine, llm) = started_engine()
  let pending = success(
    engine.complete(
      id_of(llm),
      calls_response([
        ("write-1", "write", "{\"file_path\":\"a.txt\",\"content\":\"hello\"}"),
      ]),
    ),
  )
  assert_eq(get_status(pending), "awaiting_approval")
  assert_eq(engine.take_effects().length(), 0)
  assert_true(
    engine.invoke(
      "tool_approve",
      fixture(
        "{\"session_id\":\"test\",\"call_id\":\"wrong\",\"approved\":true}",
      ),
    )
    is Err(_),
  )
  assert_eq(get_session(engine), pending)
  ignore(
    success(
      engine.invoke(
        "tool_approve",
        fixture(
          "{\"session_id\":\"test\",\"call_id\":\"write-1\",\"approved\":false}",
        ),
      ),
    ),
  )
  let effects = engine.take_effects()
  assert_eq(effects.length(), 1)
  assert_eq(required_string(effects[0], "kind"), "llm")
  let history = array_value(
    required_field(required_field(effects[0], "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(required_field(history[2], "is_error"), boolean(true))
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_status(get_session(restored)), "failed")
}

///|
test "unknown and malformed tools settle errors and continue the loop" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("missing", "unknown", "{}"),
          ("bad-json", "read", "{"),
          ("bad-schema", "read", "{}"),
        ]),
      ),
    ),
  )
  let effects = engine.take_effects()
  assert_eq(effects.length(), 1)
  assert_eq(required_string(effects[0], "kind"), "llm")
  let history = array_value(
    required_field(required_field(effects[0], "request"), "messages"),
    "messages",
    100,
  )
  assert_eq(history.length(), 5)
  for index = 2; index < 5; index = index + 1 {
    assert_eq(required_field(history[index], "is_error"), boolean(true))
  }
}

///|
test "max-step budget closes after paired tool results without another request" {
  let (engine, llm) = started_engine(max_steps=1)
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([("read-1", "read", "{\"file_path\":\"a\"}")]),
      ),
    ),
  )
  let read = engine.take_effects()[0]
  let failed = success(
    engine.complete(id_of(read), fixture("{\"ok\":true,\"content\":\"a\"}")),
  )
  assert_eq(get_status(failed), "failed")
  assert_eq(engine.take_effects().length(), 0)
  let events = array_value(required_field(failed, "events"), "events", 100)
  assert_eq(
    required_string(
      required_field(events[events.length() - 1], "data"),
      "reason",
    ),
    "max_steps",
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
}

///|
test "length finish preserves the truncated answer and reports failure" {
  let (engine, llm) = started_engine()
  let failed = success(
    engine.complete(
      id_of(llm),
      fixture(
        "{\"ok\":true,\"content\":\"partial answer\",\"tool_calls\":[],\"finish_reason\":\"length\"}",
      ),
    ),
  )
  assert_eq(get_status(failed), "failed")
  let history = array_value(required_field(failed, "messages"), "messages", 100)
  assert_eq(required_string(history[1], "content"), "partial answer")
  assert_eq(engine.take_effects().length(), 0)
}

///|
test "cancel removes queued work and rejects late or duplicate completion" {
  let (engine, llm) = started_engine()
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")
  assert_true(engine.complete(id_of(llm), stop_response("late")) is Err(_))
  assert_eq(get_session(engine), cancelled)
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"follow up\"}"),
      ),
    ),
  )
  let next = engine.take_effects()[0]
  let done = success(engine.complete(id_of(next), stop_response("answer")))
  assert_true(
    engine.complete(id_of(next), stop_response("duplicate")) is Err(_),
  )
  assert_eq(get_session(engine), done)
}

///|
test "cancel awaiting approval settles remaining calls without dispatch" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("shell", "bash", "{\"command\":\"do something\"}"),
          ("read-next", "read", "{\"file_path\":\"a\"}"),
        ]),
      ),
    ),
  )
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")
  let messages = array_value(
    required_field(cancelled, "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 4)
  assert_eq(required_string(messages[2], "tool_call_id"), "shell")
  assert_eq(required_string(messages[3], "tool_call_id"), "read-next")
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
}

///|
test "restoring an outstanding tool closes interrupted history without replaying it" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([("read-1", "read", "{\"file_path\":\"a\"}")]),
      ),
    ),
  )
  let outstanding = engine.take_effects()[0]
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  let state = get_session(restored)
  assert_eq(get_status(state), "failed")
  assert_eq(restored.take_effects().length(), 0)
  assert_true(
    restored.complete(
      id_of(outstanding),
      fixture("{\"ok\":true,\"content\":\"late\"}"),
    )
    is Err(_),
  )
  let history = array_value(required_field(state, "messages"), "messages", 100)
  assert_eq(required_field(history[2], "is_error"), boolean(true))
  let twice = Engine::new(test_tools())
  assert_eq(twice.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session(twice), state)
  ignore(
    success(
      restored.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"continue safely\"}"),
      ),
    ),
  )
  let fresh = restored.take_effects()[0]
  assert_true(id_of(fresh) != id_of(outstanding))
}

///|
test "restoring a quiescent approval preserves it for later approval" {
  let engine = engine_waiting_on_exclusive_call(
    "write", "{\"file_path\":\"resumable.txt\",\"content\":\"kept\"}",
  )
  let waiting = get_session(engine)
  assert_eq(get_status(waiting), "awaiting_approval")
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  let resumed = get_session(restored)
  assert_eq(get_status(resumed), "awaiting_approval")
  assert_eq(
    required_field(resumed, "pending_approval"),
    required_field(waiting, "pending_approval"),
  )
  assert_eq(restored.take_effects().length(), 0)
  let events = array_value(required_field(resumed, "events"), "events", 100)
  assert_true(
    !events.any(event => required_string(event, "type") == "session/interrupted"),
  )
  ignore(
    success(
      restored.invoke(
        "tool_approve",
        fixture(
          "{\"session_id\":\"test\",\"call_id\":\"barrier\",\"approved\":true}",
        ),
      ),
    ),
  )
  let approved = restored.take_effects()
  assert_eq(approved.length(), 1)
  assert_eq(call_id_of(approved[0]), "barrier")
}

///|
test "canceling parallel reads retains staged success and survives repeated restore" {
  let (engine, llm) = started_engine()
  let calls = []
  for index = 0; index < 5; index = index + 1 {
    calls.push(("read-\{index}", "read", "{\"file_path\":\"f\{index}.txt\"}"))
  }
  ignore(success(engine.complete(id_of(llm), calls_response(calls))))
  let in_flight = engine.take_effects()
  assert_eq(in_flight.length(), 4)
  ignore(
    success(
      engine.complete(
        id_of(in_flight[2]),
        fixture("{\"ok\":true,\"content\":\"accepted\"}"),
      ),
    ),
  )
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")
  let history = array_value(
    required_field(cancelled, "messages"),
    "messages",
    100,
  )
  assert_eq(history.length(), 7)
  for index = 0; index < 5; index = index + 1 {
    assert_eq(
      required_string(history[index + 2], "tool_call_id"),
      "read-\{index}",
    )
    if index == 2 {
      assert_eq(required_string(history[index + 2], "content"), "accepted")
      assert_eq(required_field(history[index + 2], "is_error"), boolean(false))
    } else {
      assert_eq(required_field(history[index + 2], "is_error"), boolean(true))
    }
  }
  assert_eq(engine.take_effects().length(), 0)
  assert_true(
    engine.complete(
      id_of(in_flight[0]),
      fixture("{\"ok\":true,\"content\":\"late\"}"),
    )
    is Err(_),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), cancelled)
  let restored_again = Engine::new(test_tools())
  assert_eq(restored_again.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session(restored_again), cancelled)
  assert_eq(restored_again.take_effects().length(), 0)
}

///|
test "restore preserves a staged read result and closes unknown siblings once" {
  let (engine, llm) = started_engine()
  let calls = []
  for index = 0; index < 5; index = index + 1 {
    calls.push(("read-\{index}", "read", "{\"file_path\":\"f\{index}.txt\"}"))
  }
  ignore(success(engine.complete(id_of(llm), calls_response(calls))))
  let in_flight = engine.take_effects()
  ignore(
    success(
      engine.complete(
        id_of(in_flight[2]),
        fixture("{\"ok\":true,\"content\":\"accepted\"}"),
      ),
    ),
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  let state = get_session(restored)
  assert_eq(get_status(state), "failed")
  let history = array_value(required_field(state, "messages"), "messages", 100)
  assert_eq(history.length(), 7)
  for index = 0; index < 5; index = index + 1 {
    assert_eq(
      required_string(history[index + 2], "tool_call_id"),
      "read-\{index}",
    )
    if index == 2 {
      assert_eq(required_string(history[index + 2], "content"), "accepted")
      assert_eq(required_field(history[index + 2], "is_error"), boolean(false))
    } else {
      assert_eq(required_field(history[index + 2], "is_error"), boolean(true))
    }
  }
  assert_eq(restored.take_effects().length(), 0)
  let restored_again = Engine::new(test_tools())
  assert_eq(restored_again.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session(restored_again), state)
  assert_eq(restored_again.take_effects().length(), 0)
}

///|
test "restore rejects parallel IO when the configured tool policy is exclusive" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-a", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-b", "read", "{\"file_path\":\"b.txt\"}"),
        ]),
      ),
    ),
  )
  assert_eq(engine.take_effects().length(), 2)
  let tools = test_tools()
  tools[0] = fixture(
    "{\"name\":\"read\",\"description\":\"Read text\",\"input_schema\":{\"type\":\"object\",\"required\":[\"file_path\"],\"properties\":{\"file_path\":{\"type\":\"string\"}},\"additionalProperties\":false},\"effect\":\"write\"}",
  )
  let exclusive = Engine::new(tools)
  assert_true(exclusive.restore(engine.snapshot()) is Err(_))
  assert_eq(
    exclusive.snapshot(),
    object([
      ("schema", Json::string("dsh.mbt-session-v1")),
      ("next_session", integer(1)),
      ("next_effect", integer(1)),
      ("sessions", Json::array([])),
    ]),
  )
}

///|
test "restore rejects reads appended after an active write or shell effect" {
  let names = ["write", "bash"]
  let arguments = [
    "{\"file_path\":\"blocked.txt\",\"content\":\"blocked\"}", "{\"command\":\"echo blocked\"}",
  ]
  for index = 0; index < names.length(); index = index + 1 {
    let engine = engine_waiting_on_exclusive_call(
      names[index],
      arguments[index],
    )
    assert_eq(get_status(get_session(engine)), "awaiting_approval")
    ignore(
      success(
        engine.invoke(
          "tool_approve",
          fixture(
            "{\"session_id\":\"test\",\"call_id\":\"barrier\",\"approved\":true}",
          ),
        ),
      ),
    )
    let active = engine.take_effects()
    assert_eq(active.length(), 1)
    assert_eq(call_id_of(active[0]), "barrier")
    let forged = append_forged_read_dispatch(engine.snapshot())
    let destination = Engine::new(test_tools())
    assert_true(destination.restore(forged) is Err(_))
    assert_eq(
      destination.snapshot(),
      object([
        ("schema", Json::string("dsh.mbt-session-v1")),
        ("next_session", integer(1)),
        ("next_effect", integer(1)),
        ("sessions", Json::array([])),
      ]),
    )
  }
}

///|
test "restore rejects reads after called waiting and approved exclusive barriers" {
  let waiting = engine_waiting_on_exclusive_call(
    "write", "{\"file_path\":\"blocked.txt\",\"content\":\"blocked\"}",
  )
  assert_true(
    Engine::new(test_tools()).restore(
      append_forged_read_dispatch(waiting.snapshot()),
    )
    is Err(_),
  )

  let called = engine_waiting_on_exclusive_call(
    "write", "{\"file_path\":\"blocked.txt\",\"content\":\"blocked\"}",
  )
  let called_state = remove_last_snapshot_event(
    called.snapshot(),
    "tool/approval/requested",
    Some("running"),
  )
  assert_true(
    Engine::new(test_tools()).restore(append_forged_read_dispatch(called_state))
    is Err(_),
  )

  let approved = engine_waiting_on_exclusive_call(
    "write", "{\"file_path\":\"blocked.txt\",\"content\":\"blocked\"}",
  )
  ignore(
    success(
      approved.invoke(
        "tool_approve",
        fixture(
          "{\"session_id\":\"test\",\"call_id\":\"barrier\",\"approved\":true}",
        ),
      ),
    ),
  )
  let approved_state = remove_last_snapshot_event(
    approved.snapshot(),
    "tool/request",
    None,
  )
  assert_true(
    Engine::new(test_tools()).restore(
      append_forged_read_dispatch(approved_state),
    )
    is Err(_),
  )
}

///|
test "capacity closure keeps an admitted staged read and retires the group" {
  let (engine, llm) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(llm),
        calls_response([
          ("read-0", "read", "{\"file_path\":\"a.txt\"}"),
          ("read-1", "read", "{\"file_path\":\"b.txt\"}"),
          ("read-2", "read", "{\"file_path\":\"c.txt\"}"),
        ]),
      ),
    ),
  )
  let effects = engine.take_effects()
  assert_eq(effects.length(), 3)
  let large_success = object([
    ("ok", boolean(true)),
    ("content", Json::string("x".repeat(65536))),
  ])
  let read_one_fields = fields(large_success).copy()
  read_one_fields["additional_contexts"] = Json::array([
    Json::string("capacity context"),
  ])
  ignore(
    success(engine.complete(id_of(effects[1]), Json::object(read_one_fields))),
  )
  let closed = success(engine.complete(id_of(effects[2]), large_success))
  assert_eq(get_status(closed), "failed")
  let messages = array_value(
    required_field(closed, "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 6)
  assert_eq(required_string(messages[2], "tool_call_id"), "read-0")
  assert_eq(required_field(messages[2], "is_error"), boolean(true))
  assert_eq(required_string(messages[3], "tool_call_id"), "read-1")
  assert_eq(required_string(messages[3], "content").length(), 65536)
  assert_eq(required_field(messages[3], "is_error"), boolean(false))
  assert_eq(required_string(messages[4], "tool_call_id"), "read-2")
  assert_eq(required_field(messages[4], "is_error"), boolean(true))
  assert_eq(required_string(messages[5], "role"), "user")
  assert_eq(
    required_field(messages[5], "source"),
    Json::object({ "kind": "hooks-claude-code" }),
  )
  assert_eq(required_string(messages[5], "content"), "capacity context")
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), closed)
  let restored_again = Engine::new(test_tools())
  assert_eq(restored_again.restore(restored.snapshot()), Ok(()))
  assert_eq(get_session(restored_again), closed)
  assert_eq(restored_again.take_effects().length(), 0)
}

///|
test "busy send malformed input and malformed completions are atomic" {
  let (engine, llm) = started_engine()
  let before = engine.snapshot()
  assert_true(
    engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":\"overlap\"}"),
    )
    is Err(_),
  )
  assert_true(
    engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":7}"),
    )
    is Err(_),
  )
  assert_true(
    engine.invoke("session_create", fixture("{\"max_steps\":0}")) is Err(_),
  )
  assert_true(
    engine.invoke("session_get", fixture("{\"session_id\":\"missing\"}"))
    is Err(_),
  )
  assert_true(engine.invoke("unknown", object([])) is Err(_))
  assert_true(
    engine.complete(
      id_of(llm),
      fixture(
        "{\"ok\":true,\"content\":\"bad\",\"finish_reason\":\"tool_calls\",\"tool_calls\":[]}",
      ),
    )
    is Err(_),
  )
  assert_true(
    engine.complete(
      id_of(llm),
      fixture(
        "{\"ok\":true,\"content\":\"bad\",\"finish_reason\":\"stop\",\"usage\":{\"input_tokens\":-1}}",
      ),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_eq(
    get_status(success(engine.complete(id_of(llm), stop_response("valid")))),
    "completed",
  )
}

///|
test "duplicate model call IDs are rejected before committing an assistant" {
  let (engine, llm) = started_engine()
  let before = engine.snapshot()
  assert_true(
    engine.complete(
      id_of(llm),
      calls_response([("same", "read", "{}"), ("same", "read", "{}")]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
}

///|
test "provider failures are explicit attempts and resume without fabricated messages" {
  let (engine, llm) = started_engine()
  let failed = success(
    engine.complete(
      id_of(llm),
      fixture("{\"ok\":false,\"error\":\"HTTP 429\"}"),
    ),
  )
  assert_eq(get_status(failed), "failed")
  assert_eq(
    array_value(required_field(failed, "messages"), "messages", 100).length(),
    1,
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), failed)
}

///|
test "stream projections stay out of model context and survive failure and reopen" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  let writing = success(
    engine.project_stream(effect_id, "partial answer", "thinking"),
  )
  let messages = array_value(
    required_field(writing, "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 2)
  assert_eq(required_string(messages[1], "content"), "partial answer")
  assert_eq(required_string(messages[1], "reasoning"), "thinking")
  assert_true(
    bool_value(required_field(messages[1], "provisional"), "provisional"),
  )
  assert_eq(required_string(messages[1], "stream_status"), "writing")
  assert_eq(
    int_value(
      required_field(writing, "stream_revision"),
      "stream_revision",
      0,
      100,
    ),
    22,
  )

  let failed = success(
    engine.complete(
      effect_id,
      fixture("{\"ok\":false,\"error\":\"provider ended early\"}"),
    ),
  )
  let failed_messages = array_value(
    required_field(failed, "messages"),
    "messages",
    100,
  )
  assert_eq(required_string(failed_messages[1], "stream_status"), "partial")
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  let reopened = get_session(restored)
  assert_eq(
    required_string(
      array_value(required_field(reopened, "messages"), "messages", 100)[1],
      "content",
    ),
    "partial answer",
  )
  assert_eq(restored.take_effects().length(), 0)

  ignore(
    success(
      restored.invoke(
        "session_send",
        fixture(
          "{\"session_id\":\"test\",\"prompt\":\"continue without partial\"}",
        ),
      ),
    ),
  )
  let next_llm = restored.take_effects()[0]
  let next_messages = required_field(
    required_field(next_llm, "request"),
    "messages",
  )
  assert_false(next_messages.stringify().contains("partial answer"))
  assert_false(next_messages.stringify().contains("thinking"))
}

///|
test "stream completion must match its deltas and late deltas are fenced" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  ignore(success(engine.project_stream(effect_id, "visible", "reason")))
  let before = engine.snapshot()
  assert_true(engine.complete(effect_id, stop_response("different")) is Err(_))
  assert_eq(engine.snapshot(), before)
  let matching = fixture(
    "{\"ok\":true,\"content\":\"visible\",\"reasoning\":\"reason\",\"tool_calls\":[],\"finish_reason\":\"stop\"}",
  )
  let finished = success(engine.complete(effect_id, matching))
  let messages = array_value(
    required_field(finished, "messages"),
    "messages",
    100,
  )
  assert_eq(messages.length(), 2)
  assert_eq(required_string(messages[1], "content"), "visible")
  assert_true(fields(messages[1]).get("provisional") is None)
  assert_true(engine.project_stream(effect_id, "late", "") is Err(_))
  assert_eq(
    array_value(
      required_field(get_session(engine), "messages"),
      "messages",
      100,
    ).length(),
    2,
  )
}

///|
test "stream deltas are accepted only for the live LLM effect and restore rejects forged identity" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  assert_true(engine.project_stream("effect-999", "x", "") is Err(_))
  let waiting = success(
    engine.complete(
      effect_id,
      calls_response([("read-1", "read", "{\"file_path\":\"README.md\"}")]),
    ),
  )
  assert_eq(get_status(waiting), "running")
  let active_tool = engine.take_effects()[0]
  assert_eq(required_string(active_tool, "kind"), "tool")
  assert_true(engine.project_stream(effect_id, "tool noise", "") is Err(_))
}

///|
test "reopen closes an in-flight projected stream without replay and rejects a forged delta" {
  let (engine, llm) = started_engine()
  ignore(success(engine.project_stream(id_of(llm), "kept", "")))
  let valid = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(valid), Ok(()))
  let reopened = get_session(restored)
  assert_eq(get_status(reopened), "failed")
  assert_eq(
    required_string(
      array_value(required_field(reopened, "messages"), "messages", 100)[1],
      "content",
    ),
    "kept",
  )
  assert_eq(restored.take_effects().length(), 0)

  let forged = engine.snapshot()
  let sessions = array_value(required_field(forged, "sessions"), "sessions", 32)
  let events = array_value(required_field(sessions[0], "events"), "events", 100)
  let delta = events[events.length() - 1]
  fields(required_field(delta, "data")).set(
    "effect_id",
    Json::string("effect-999"),
  )
  let destination = Engine::new(test_tools())
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.order.length(), 0)
}

///|
test "stream capacity refusal keeps the last committed partial reloadable" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  let builder = StringBuilder()
  for _ in 0..<4096 {
    builder.write_string("x")
  }
  let batch = builder.to_string()
  let mut accepted = 0
  let mut refused = false
  while accepted < 100 && !refused {
    match engine.project_stream(effect_id, batch, "") {
      Ok(_) => accepted += 1
      Err(_) => refused = true
    }
  }
  assert_true(refused)
  assert_true(accepted > 1)
  let before_restore = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(before_restore), Ok(()))
  assert_eq(restored.take_effects().length(), 0)
  let reopened = get_session(restored)
  assert_eq(get_status(reopened), "failed")
  let partial = array_value(
      required_field(reopened, "messages"),
      "messages",
      100,
    )[1]
  assert_eq(required_string(partial, "stream_status"), "partial")
  assert_eq(
    required_string(partial, "content", max=262144).length(),
    accepted * 4096,
  )
}

///|
test "legacy v1 without stream revision restores and replay rejects stream tampering" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  ignore(success(engine.project_stream(effect_id, "partial", "")))
  let old = engine.snapshot()
  let old_session = array_value(required_field(old, "sessions"), "sessions", 32)[0]
  fields(old_session).remove("stream_revision")
  let compatible = Engine::new(test_tools())
  assert_eq(compatible.restore(old), Ok(()))
  assert_eq(get_status(get_session(compatible)), "failed")

  let wrong_coordinates = engine.snapshot()
  let session = array_value(
      required_field(wrong_coordinates, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  fields(events[events.length() - 1]).set("turn_id", integer(9))
  let rejected_coordinates = Engine::new(test_tools())
  assert_true(rejected_coordinates.restore(wrong_coordinates) is Err(_))

  let failed = Engine::new(test_tools())
  assert_eq(failed.restore(engine.snapshot()), Ok(()))
  let recovered = get_session(failed)
  let saved = failed.snapshot()
  // Tampering with the derived provisional message is rejected independently
  // of the immutable event projection check.
  let saved_session = array_value(
      required_field(saved, "sessions"),
      "sessions",
      32,
    )[0]
  let messages = array_value(
    required_field(saved_session, "messages"),
    "messages",
    100,
  )
  fields(messages[1]).set("content", Json::string("forged"))
  let rejected_message = Engine::new(test_tools())
  assert_true(rejected_message.restore(saved) is Err(_))
  assert_eq(get_status(recovered), "failed")
}

///|
test "replay rejects stream deltas after an attempt and a forged final message" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  ignore(success(engine.project_stream(effect_id, "visible", "")))
  ignore(
    success(
      engine.complete(
        effect_id,
        fixture("{\"ok\":false,\"error\":\"truncated\"}"),
      ),
    ),
  )
  let settled = engine.snapshot()
  let session = array_value(required_field(settled, "sessions"), "sessions", 32)[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  events.push(
    object([
      ("seq", integer(events.length())),
      ("type", Json::string("assistant/stream_delta")),
      ("turn_id", integer(1)),
      ("step", integer(1)),
      (
        "data",
        object([
          ("effect_id", Json::string(effect_id)),
          ("content", Json::string("late")),
          ("reasoning", Json::string("")),
        ]),
      ),
    ]),
  )
  let rejected_late = Engine::new(test_tools())
  assert_true(rejected_late.restore(settled) is Err(_))

  let (complete_engine, complete_llm) = started_engine()
  let complete_id = id_of(complete_llm)
  ignore(success(complete_engine.project_stream(complete_id, "visible", "")))
  ignore(
    success(complete_engine.complete(complete_id, stop_response("visible"))),
  )
  let forged_final = complete_engine.snapshot()
  let complete_session = array_value(
      required_field(forged_final, "sessions"),
      "sessions",
      32,
    )[0]
  let complete_events = array_value(
    required_field(complete_session, "events"),
    "events",
    100,
  )
  for event in complete_events {
    if required_string(event, "type") == "assistant/message" {
      let message = required_field(required_field(event, "data"), "message")
      fields(message).set("content", Json::string("forged final"))
    }
  }
  let rejected_final = Engine::new(test_tools())
  assert_true(rejected_final.restore(forged_final) is Err(_))
}

///|
test "public Json collections cannot mutate tool policy or durable history" {
  let inventory = test_tools()
  let engine = Engine::new(inventory)
  fields(inventory[0]).set("effect", Json::string("shell"))
  let create_input = fixture("{\"id\":\"test\",\"title\":\"original\"}")
  let created = success(engine.invoke("session_create", create_input))
  fields(create_input).set("title", Json::string("forged"))
  fields(created).set("title", Json::string("also forged"))
  assert_eq(required_string(get_session(engine), "title"), "original")
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"read\"}"),
      ),
    ),
  )
  let llm = engine.take_effects()[0]
  let request_tools = array_value(
    required_field(required_field(llm, "request"), "tools"),
    "tools",
    100,
  )
  fields(request_tools[0]).set("effect", Json::string("shell"))
  let state = success(
    engine.complete(
      id_of(llm),
      calls_response([("read-1", "read", "{\"file_path\":\"a\"}")]),
    ),
  )
  assert_eq(get_status(state), "running")
  assert_eq(required_string(engine.take_effects()[0], "kind"), "tool")
}

///|
test "restore rejects forged history atomically and never imports supplied messages" {
  let (source, llm) = started_engine()
  ignore(success(source.complete(id_of(llm), stop_response("saved answer"))))
  let destination = Engine::new(test_tools())
  ignore(
    success(destination.invoke("session_create", fixture("{\"id\":\"keep\"}"))),
  )
  let before = destination.snapshot()
  let forged = source.snapshot()
  let sessions = array_value(
    required_field(forged, "sessions"),
    "sessions",
    100,
  )
  fields(sessions[0]).set("messages", Json::array([]))
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
  let forged_event = source.snapshot()
  let session = array_value(
      required_field(forged_event, "sessions"),
      "sessions",
      100,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  fields(events[1]).set("type", Json::string("unknown/required"))
  assert_true(destination.restore(forged_event) is Err(_))
  assert_eq(destination.snapshot(), before)
  let forged_seq = source.snapshot()
  let session = array_value(
      required_field(forged_seq, "sessions"),
      "sessions",
      100,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  fields(events[1]).set("seq", integer(99))
  assert_true(destination.restore(forged_seq) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restore refuses to detach active work and invalid configuration fails closed" {
  let (engine, _) = started_engine()
  let before = engine.snapshot()
  assert_true(engine.restore(Engine::new([]).snapshot()) is Err(_))
  assert_eq(engine.snapshot(), before)
  let invalid = Engine::new([fixture("{\"name\":\"broken\"}")])
  assert_true(invalid.invoke("session_create", object([])) is Err(_))
  let duplicate = Engine::new([test_tools()[0], test_tools()[0]])
  assert_true(duplicate.invoke("session_create", object([])) is Err(_))
}

///|
test "public typed commands validate direct values before changing state" {
  let engine = Engine::new(test_tools())
  let before = engine.snapshot()
  assert_true(
    engine.apply(CreateSession(Some("../bad"), "", "", Some(0))) is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(
    engine.apply(SendPrompt(SessionId::new("valid-id").unwrap(), "")) is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(
    engine.apply(
      SendPromptWithContexts(SessionId::new("valid-id").unwrap(), "prompt", [
        "x".repeat(4097),
      ]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(engine.apply(ImportSession("x".repeat(262145))) is Err(_))
  assert_eq(engine.snapshot(), before)

  ignore(
    engine.apply(CreateSession(Some("direct-id"), "", "", Some(1))).unwrap(),
  )
  let saved = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(saved), Ok(()))
  assert_eq(restored.snapshot(), engine.snapshot())
}

///|
test "JSON depth and nonfinite numbers are rejected at the pure boundary" {
  let engine = Engine::new([])
  let cycle : Array[Json] = []
  cycle.push(Json::array(cycle))
  assert_true(
    engine.invoke("session_create", object([("cycle", Json::array(cycle))]))
    is Err(_),
  )
  assert_true(
    engine.invoke(
      "session_create",
      object([("max_steps", Json::number(0.0 / 0.0))]),
    )
    is Err(_),
  )
  assert_eq(success(engine.invoke("session_list", object([]))), Json::array([]))
}

///|
test "nine large completions stop at session capacity without stranded work" {
  let engine = Engine::new(test_tools())
  ignore(success(engine.invoke("session_create", fixture("{\"id\":\"test\"}"))))
  let text = "x".repeat(65000)
  let mut hit_capacity = false
  for attempt = 0; attempt < 9; attempt = attempt + 1 {
    let sent = engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":\"another answer\"}"),
    )
    match sent {
      Err(_) => {
        hit_capacity = true
        break
      }
      Ok(_) => ()
    }
    let llm = engine.take_effects()[0]
    let settled = success(engine.complete(id_of(llm), stop_response(text)))
    if get_status(settled) == "failed" {
      let events = array_value(required_field(settled, "events"), "events", 100)
      assert_eq(
        required_string(
          required_field(events[events.length() - 1], "data"),
          "reason",
        ),
        "session_capacity",
      )
      hit_capacity = true
      break
    }
  }
  assert_true(hit_capacity)
  assert_eq(engine.take_effects().length(), 0)
  assert_true(get_session(engine).stringify().length() <= 262144)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), get_session(engine))
}

///|
test "capacity refusal of send leaves the completed session unchanged" {
  let (engine, first) = started_engine()
  ignore(
    success(engine.complete(id_of(first), stop_response("x".repeat(60000)))),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string("test")),
          ("prompt", Json::string("q".repeat(16000))),
        ]),
      ),
    ),
  )
  let second = engine.take_effects()[0]
  let done = success(
    engine.complete(id_of(second), stop_response("y".repeat(50000))),
  )
  assert_eq(get_status(done), "completed")
  let before = engine.snapshot()
  assert_true(
    engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("q".repeat(16384))),
      ]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_eq(engine.take_effects().length(), 0)
}

///|
test "oversized model tool batch never publishes a candidate side effect" {
  let (engine, llm) = started_engine()
  let arguments = object([
    ("file_path", Json::string("a.txt")),
    ("content", Json::string("x".repeat(60000))),
  ]).stringify()
  let state = success(
    engine.complete(
      id_of(llm),
      calls_response([
        ("write-1", "write", arguments),
        ("write-2", "write", arguments),
        ("write-3", "write", arguments),
      ]),
    ),
  )
  assert_eq(get_status(state), "failed")
  assert_true(fields(state).get("pending_approval") is None)
  assert_eq(engine.take_effects().length(), 0)
  assert_eq(
    array_value(required_field(state, "messages"), "messages", 100).length(),
    1,
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
}

///|
test "large tool batch approval survives restore without interruption expansion" {
  let (engine, llm) = started_engine()
  let arguments = object([
    ("file_path", Json::string("a.txt")),
    ("content", Json::string("x".repeat(5500))),
  ]).stringify()
  let calls = []
  for index = 0; index < 16; index = index + 1 {
    calls.push(("write-\{index}", "write", arguments))
  }
  // This quiescent batch needs no synthetic interrupted results on restore.
  let state = success(engine.complete(id_of(llm), calls_response(calls)))
  assert_eq(get_status(state), "awaiting_approval")
  assert_true(fields(state).get("pending_approval") is Some(_))
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_status(get_session(restored)), "awaiting_approval")
  assert_true(get_session(restored).stringify().length() <= 262144)
}

///|
test "restore rejects oversized snapshot sessions before replacing state" {
  let (engine, llm) = started_engine()
  ignore(success(engine.complete(id_of(llm), stop_response("saved"))))
  let forged = engine.snapshot()
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  fields(session).set("extra", Json::string("x".repeat(262144)))
  let destination = Engine::new([])
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restored exhausted identity counters remain reloadable" {
  let engine = Engine::new([])
  let exhausted = fixture(
    "{\"schema\":\"dsh.mbt-session-v1\",\"next_session\":1000000000,\"next_effect\":1,\"sessions\":[]}",
  )
  assert_eq(engine.restore(exhausted), Ok(()))
  let before = engine.snapshot()
  assert_true(engine.invoke("session_create", object([])) is Err(_))
  assert_eq(engine.snapshot(), before)
  let exhausted_effects = fixture(
    "{\"schema\":\"dsh.mbt-session-v1\",\"next_session\":1,\"next_effect\":1000000000,\"sessions\":[]}",
  )
  assert_eq(engine.restore(exhausted_effects), Ok(()))
  ignore(success(engine.invoke("session_create", fixture("{\"id\":\"test\"}"))))
  let failed = success(
    engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":\"hello\"}"),
    ),
  )
  assert_eq(get_status(failed), "failed")
  assert_eq(engine.take_effects().length(), 0)
  let destination = Engine::new([])
  assert_eq(destination.restore(engine.snapshot()), Ok(()))
  assert_eq(destination.snapshot(), engine.snapshot())
}
