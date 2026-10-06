///|
fn session_v4_portable_fixture() -> String {
  "{\"type\":\"session\",\"version\":4,\"id\":\"fixture-v4\",\"createdAt\":1,\"isSeeded\":false,\"delegationDepth\":0}\n" +
  "{\"type\":\"turn/start\",\"data\":{\"turn\":1}}\n" +
  "{\"type\":\"step/start\",\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"user/message\",\"data\":{\"role\":\"user\",\"id\":\"user-1\",\"source\":{\"kind\":\"user\"},\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"request/header\",\"data\":{\"reason\":\"initial\",\"header\":{\"config\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}}}\n" +
  "{\"type\":\"request/context\",\"data\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}\n" +
  "{\"type\":\"assistant/message\",\"data\":{\"turn\":1,\"step\":1,\"message\":{\"role\":\"assistant\",\"id\":\"assistant-1\",\"source\":{\"kind\":\"model\",\"provider\":\"fixture\",\"model\":\"fixture-model\"},\"content\":[{\"type\":\"text\",\"text\":\"hello back\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"step/end\",\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"turn/end\",\"data\":{\"turn\":1,\"reason\":{\"kind\":\"completed\"}}}\n" +
  "{\"type\":\"agent/inbox/spliced\",\"data\":{\"target\":\"next-turn\",\"start\":0,\"inserted\":[{\"role\":\"user\",\"id\":\"queued-1\",\"source\":{\"kind\":\"user\"},\"content\":[{\"type\":\"text\",\"text\":\"queued prompt\"}]}]}}"
}

///|
test "Session v4 import is inert, read-only, atomic, and restorable" {
  let engine = Engine::new(test_tools())
  let imported = success(
    engine.invoke(
      "session_import",
      object([("jsonl", Json::string(session_v4_portable_fixture()))]),
    ),
  )
  assert_eq(get_status(imported), "completed")
  assert_eq(required_string(imported, "source_format"), "deepseek-session-v4")
  let messages = array_value(
    required_field(imported, "messages"),
    "messages",
    16,
  )
  assert_eq(messages.length(), 2)
  assert_eq(required_string(messages[0], "content"), "hello")
  assert_eq(required_string(messages[1], "content"), "hello back")
  let pending_inbox = required_field(imported, "pending_inbox")
  let queued = array_value(
    required_field(pending_inbox, "next_turn"),
    "next_turn",
    8,
  )
  assert_eq(queued.length(), 1)
  let queued_content = array_value(
    required_field(queued[0], "content"),
    "queued content",
    8,
  )
  fields(queued_content[0]).set("text", Json::string("forged response alias"))
  let unchanged = success(
    engine.invoke("session_get", fixture("{\"session_id\":\"session-1\"}")),
  )
  let unchanged_inbox = required_field(unchanged, "pending_inbox")
  let unchanged_queue = array_value(
    required_field(unchanged_inbox, "next_turn"),
    "next_turn",
    8,
  )
  let unchanged_content = array_value(
    required_field(unchanged_queue[0], "content"),
    "queued content",
    8,
  )
  assert_eq(required_string(unchanged_content[0], "text"), "queued prompt")
  assert_true(engine.take_effects().is_empty())

  let before = engine.snapshot()
  assert_true(
    engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"session-1\",\"prompt\":\"continue\"}"),
    )
    is Err(_),
  )
  assert_true(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"session-1\"}"))
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)

  let malformed = "{\"type\":\"session\",\"version\":4,\"id\":\"bad\",\"createdAt\":1,\"isSeeded\":false,\"delegationDepth\":0}\n{\"type\":\"unknown/required\",\"data\":{}}"
  assert_true(
    engine.invoke(
      "session_import",
      object([("jsonl", Json::string(malformed))]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)

  let restored = Engine::new(test_tools())
  assert_true(restored.restore(before) is Ok(_))
  assert_eq(
    success(
      restored.invoke("session_get", fixture("{\"session_id\":\"session-1\"}")),
    ),
    unchanged,
  )
  assert_true(restored.take_effects().is_empty())

  let forged = engine.snapshot()
  let sessions = array_value(required_field(forged, "sessions"), "sessions", 8)
  fields(sessions[0]).set("messages", Json::array([]))
  let untouched = Engine::new([])
  let empty = untouched.snapshot()
  let forged_creation = engine.snapshot()
  let forged_sessions = array_value(
    required_field(forged_creation, "sessions"),
    "sessions",
    8,
  )
  let forged_events = array_value(
    required_field(forged_sessions[0], "events"),
    "events",
    32,
  )
  fields(forged_events[0]).set("seq", integer(99))
  assert_true(untouched.restore(forged_creation) is Err(_))
  assert_eq(untouched.snapshot(), empty)
  let extra_creation = engine.snapshot()
  let extra_sessions = array_value(
    required_field(extra_creation, "sessions"),
    "sessions",
    8,
  )
  let extra_events = array_value(
    required_field(extra_sessions[0], "events"),
    "events",
    32,
  )
  fields(extra_events[0]).set("forged", Json::boolean(true))
  assert_true(untouched.restore(extra_creation) is Err(_))
  assert_eq(untouched.snapshot(), empty)
  assert_true(untouched.restore(forged) is Err(_))
  assert_eq(untouched.snapshot(), empty)
}

///|
test "Session v4 replacements follow current surface positions and preserve result identity" {
  let surface = [7, 19, 13, 15]
  match v4_surface_replacement_indices(surface, 19, 15) {
    Some((1, 3)) => ()
    _ => assert_true(false)
  }
  assert_true(v4_surface_replacement_indices(surface, 15, 19) is None)
  assert_true(v4_surface_replacement_indices(surface, 19, 999) is None)

  let old_message = object([
    ("role", Json::string("tool")),
    ("id", Json::string("result-1")),
    ("toolCallId", Json::string("call-1")),
    ("isError", Json::boolean(false)),
    ("content", Json::array([Json::string("large output")])),
  ])
  let new_message = object([
    ("role", Json::string("tool")),
    ("id", Json::string("result-1")),
    ("toolCallId", Json::string("call-1")),
    ("isError", Json::boolean(false)),
    ("content", Json::array([Json::string("pruned output")])),
  ])
  assert_true(v4_json_fields_equal_except(old_message, new_message, "content"))
  let changed_id = object([
    ("role", Json::string("tool")),
    ("id", Json::string("different-result")),
    ("toolCallId", Json::string("call-1")),
    ("isError", Json::boolean(false)),
    ("content", Json::array([Json::string("pruned output")])),
  ])
  assert_true(!v4_json_fields_equal_except(old_message, changed_id, "content"))

  let old_data = object([
    ("turn", integer(1)),
    ("step", integer(1)),
    ("message", old_message),
  ])
  let new_data = object([
    ("turn", integer(1)),
    ("step", integer(1)),
    ("message", new_message),
  ])
  assert_true(v4_json_fields_equal_except(old_data, new_data, "message"))
  let changed_turn = object([
    ("turn", integer(2)),
    ("step", integer(1)),
    ("message", new_message),
  ])
  assert_true(!v4_json_fields_equal_except(old_data, changed_turn, "message"))
}
