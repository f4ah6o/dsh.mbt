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
test "sequential read calls preserve order and tool-call identity" {
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
  assert_eq(first.length(), 1)
  assert_eq(
    required_string(required_field(first[0], "request"), "call_id"),
    "first",
  )
  assert_eq(engine.take_effects().length(), 0)
  ignore(
    success(
      engine.complete(
        id_of(first[0]),
        fixture("{\"ok\":true,\"content\":\"one\"}"),
      ),
    ),
  )
  let second = engine.take_effects()[0]
  assert_eq(
    required_string(required_field(second, "request"), "call_id"),
    "second",
  )
  ignore(
    success(
      engine.complete(
        id_of(second),
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
  assert_eq(required_string(messages[3], "tool_call_id"), "second")
  assert_eq(required_field(messages[3], "is_error"), boolean(true))
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
test "tool batch reserves room for every interrupted result before approval" {
  let (engine, llm) = started_engine()
  let arguments = object([
    ("file_path", Json::string("a.txt")),
    ("content", Json::string("x".repeat(5500))),
  ]).stringify()
  let calls = []
  for index = 0; index < 16; index = index + 1 {
    calls.push(("write-\{index}", "write", arguments))
  }
  // The assistant call list and one pending approval fit individually; closing
  // all sixteen unfinished calls would overflow the canonical session budget.
  let state = success(engine.complete(id_of(llm), calls_response(calls)))
  assert_eq(get_status(state), "failed")
  assert_true(fields(state).get("pending_approval") is None)
  assert_eq(engine.take_effects().length(), 0)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
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
