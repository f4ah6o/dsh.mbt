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
fn session_v4_metadata_fixture() -> String {
  "{\"type\":\"session\",\"version\":4,\"id\":\"metadata-fixture\",\"createdAt\":1,\"isSeeded\":false,\"delegationDepth\":0}\n" +
  "{\"type\":\"turn/start\",\"data\":{\"turn\":1}}\n" +
  "{\"type\":\"step/start\",\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"user/message\",\"data\":{\"role\":\"user\",\"id\":\"user-1\",\"source\":{\"kind\":\"user\"},\"content\":[{\"type\":\"text\",\"text\":\"inspect inert metadata\"}]},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"request/header\",\"data\":{\"reason\":\"initial\",\"header\":{\"config\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}}}\n" +
  "{\"type\":\"request/context\",\"data\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}\n" +
  "{\"type\":\"assistant/message\",\"data\":{\"turn\":1,\"step\":1,\"message\":{\"role\":\"assistant\",\"id\":\"assistant-ptc\",\"source\":{\"kind\":\"model\",\"provider\":\"fixture\",\"model\":\"fixture-model\"},\"content\":[{\"type\":\"tool-call\",\"id\":\"root-call\",\"name\":\"run_code\",\"arguments\":\"{}\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"tool/call\",\"data\":{\"turn\":1,\"step\":1,\"callId\":\"root-call\",\"name\":\"run_code\",\"arguments\":\"{}\"}}\n" +
  "{\"type\":\"tool/ptc-dispatch-start\",\"data\":{\"rootCallId\":\"root-call\",\"parentCallId\":\"root-call\",\"subCallId\":\"nested-call\",\"name\":\"read\",\"arguments\":{\"path\":\"note.txt\"}}}\n" +
  "{\"type\":\"tool/ptc-dispatch\",\"data\":{\"rootCallId\":\"root-call\",\"parentCallId\":\"root-call\",\"subCallId\":\"nested-call\",\"name\":\"read\",\"arguments\":{\"path\":\"note.txt\"},\"isError\":false,\"content\":[{\"type\":\"text\",\"text\":\"nested result\"}]}}\n" +
  "{\"type\":\"tool/result\",\"data\":{\"turn\":1,\"step\":1,\"message\":{\"role\":\"tool\",\"id\":\"result-ptc\",\"source\":{\"kind\":\"tool\",\"callId\":\"root-call\"},\"toolCallId\":\"root-call\",\"isError\":false,\"content\":[{\"type\":\"text\",\"text\":\"outer result\"},{\"type\":\"image\",\"attachment\":{\"attachmentId\":\"opaque-image-id\",\"mediaType\":\"image/png\",\"width\":1,\"height\":2,\"bytes\":8}}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"step/end\",\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"step/start\",\"data\":{\"turn\":1,\"step\":2}}\n" +
  "{\"type\":\"request/header\",\"data\":{\"reason\":\"resume\",\"header\":{\"config\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}}}\n" +
  "{\"type\":\"request/context\",\"data\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}\n" +
  "{\"type\":\"assistant/message\",\"data\":{\"turn\":1,\"step\":2,\"message\":{\"role\":\"assistant\",\"id\":\"assistant-workflow\",\"source\":{\"kind\":\"model\",\"provider\":\"fixture\",\"model\":\"fixture-model\"},\"content\":[{\"type\":\"tool-call\",\"id\":\"workflow-call\",\"name\":\"workflow\",\"arguments\":\"{\\\"meta\\\":{\\\"name\\\":\\\"sample workflow\\\"}}\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"tool/call\",\"data\":{\"turn\":1,\"step\":2,\"callId\":\"workflow-call\",\"name\":\"workflow\",\"arguments\":\"{\\\"meta\\\":{\\\"name\\\":\\\"sample workflow\\\"}}\"}}\n" +
  "{\"type\":\"tool-workflow/run-start\",\"data\":{\"runId\":\"workflow-run\",\"name\":\"sample workflow\"}}\n" +
  "{\"type\":\"subagent/catalog\",\"data\":{\"version\":0,\"childId\":\"child-session\",\"childCreatedAt\":2,\"mode\":\"one-shot\"}}\n" +
  "{\"type\":\"tool-workflow/agent-start\",\"data\":{\"runId\":\"workflow-run\",\"seq\":1,\"label\":\"worker\",\"childId\":\"child-session\"}}\n" +
  "{\"type\":\"tool-workflow/agent-end\",\"data\":{\"runId\":\"workflow-run\",\"seq\":1,\"outcome\":\"completed\"}}\n" +
  "{\"type\":\"tool-workflow/run-end\",\"data\":{\"runId\":\"workflow-run\",\"stopReason\":\"completed\"}}\n" +
  "{\"type\":\"tool/result\",\"data\":{\"turn\":1,\"step\":2,\"message\":{\"role\":\"tool\",\"id\":\"result-workflow\",\"source\":{\"kind\":\"tool\",\"callId\":\"workflow-call\"},\"toolCallId\":\"workflow-call\",\"isError\":false,\"content\":[{\"type\":\"text\",\"text\":\"workflow result\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"step/end\",\"data\":{\"turn\":1,\"step\":2}}\n" +
  "{\"type\":\"step/start\",\"data\":{\"turn\":1,\"step\":3}}\n" +
  "{\"type\":\"request/header\",\"data\":{\"reason\":\"resume\",\"header\":{\"config\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}}}\n" +
  "{\"type\":\"request/context\",\"data\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}\n" +
  "{\"type\":\"assistant/message\",\"data\":{\"turn\":1,\"step\":3,\"message\":{\"role\":\"assistant\",\"id\":\"assistant-final\",\"source\":{\"kind\":\"model\",\"provider\":\"fixture\",\"model\":\"fixture-model\"},\"content\":[{\"type\":\"text\",\"text\":\"done\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"step/end\",\"data\":{\"turn\":1,\"step\":3}}\n" +
  "{\"type\":\"turn/end\",\"data\":{\"turn\":1,\"reason\":{\"kind\":\"completed\"}}}"
}

///|
fn session_v4_retry_portable_fixture() -> String {
  "{\"type\":\"session\",\"version\":4,\"id\":\"retry-portable\",\"createdAt\":1,\"cwd\":\"/workspace\",\"isSeeded\":false,\"delegationDepth\":0}\n" +
  "{\"type\":\"turn/start\",\"seq\":0,\"time\":1,\"data\":{\"turn\":1}}\n" +
  "{\"type\":\"step/start\",\"seq\":1,\"time\":2,\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"user/message\",\"seq\":2,\"time\":3,\"data\":{\"role\":\"user\",\"id\":\"retry-user\",\"source\":{\"kind\":\"user\"},\"content\":[{\"type\":\"text\",\"text\":\"Retry a provider request.\"}]},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"request/header\",\"seq\":3,\"time\":4,\"data\":{\"reason\":\"initial\",\"header\":{\"config\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}}}\n" +
  "{\"type\":\"request/context\",\"seq\":4,\"time\":5,\"data\":{\"provider\":\"fixture\",\"model\":\"fixture-model\"}}\n" +
  "{\"type\":\"assistant/attempt\",\"seq\":5,\"time\":6,\"data\":{\"turn\":1,\"step\":1,\"stream\":[{\"type\":\"chunk\",\"time\":0,\"chunk\":{\"type\":\"finish\",\"reason\":{\"kind\":\"error\",\"failure\":{\"message\":\"provider busy\",\"code\":\"RATE_LIMIT\"}}}}]}}\n" +
  "{\"type\":\"llm/retry\",\"seq\":6,\"time\":7,\"data\":{\"retryId\":\"retry-portable-chain\",\"turn\":1,\"step\":1,\"provider\":\"fixture\",\"mode\":\"normal\",\"policyKey\":\"policy-portable\",\"retry\":1,\"maxRetries\":2,\"delayMs\":10000.5,\"failure\":{\"message\":\"provider busy\",\"code\":\"RATE_LIMIT\",\"status\":429,\"providerRetryAfterMs\":250.5,\"requestId\":\"req-1\"}}}\n" +
  "{\"type\":\"llm/retry-started\",\"seq\":7,\"time\":8,\"data\":{\"retryId\":\"retry-portable-chain\",\"turn\":1,\"step\":1,\"retry\":1}}\n" +
  "{\"type\":\"llm/retry\",\"seq\":8,\"time\":9,\"data\":{\"retryId\":\"retry-portable-chain\",\"turn\":1,\"step\":1,\"provider\":\"fixture\",\"mode\":\"normal\",\"policyKey\":\"policy-portable\",\"retry\":2,\"maxRetries\":2,\"delayMs\":0.25,\"failure\":{\"message\":\"empty response\",\"code\":\"EMPTY_RESPONSE\"}}}\n" +
  "{\"type\":\"llm/retry-started\",\"seq\":9,\"time\":10,\"data\":{\"retryId\":\"retry-portable-chain\",\"turn\":1,\"step\":1,\"retry\":2}}\n" +
  "{\"type\":\"assistant/message\",\"seq\":10,\"time\":11,\"data\":{\"turn\":1,\"step\":1,\"message\":{\"role\":\"assistant\",\"id\":\"retry-assistant\",\"source\":{\"kind\":\"model\",\"provider\":\"fixture\",\"model\":\"fixture-model\"},\"content\":[{\"type\":\"text\",\"text\":\"Recovered.\"}]}},\"surfaceOp\":\"append\"}\n" +
  "{\"type\":\"step/end\",\"seq\":11,\"time\":12,\"data\":{\"turn\":1,\"step\":1}}\n" +
  "{\"type\":\"turn/end\",\"seq\":12,\"time\":13,\"data\":{\"turn\":1,\"reason\":{\"kind\":\"completed\"}}}"
}

///|
test "Session v4 retry import validates correlations and preserves diagnostics" {
  let engine = Engine::new(test_tools())
  let jsonl = session_v4_retry_portable_fixture()
  let imported = success(
    engine.invoke("session_import", object([("jsonl", Json::string(jsonl))])),
  )
  assert_eq(get_status(imported), "completed")
  let messages = array_value(
    required_field(imported, "messages"),
    "messages",
    8,
  )
  assert_eq(messages.length(), 2)
  assert_eq(required_string(messages[1], "content"), "Recovered.")
  let events = array_value(required_field(imported, "events"), "events", 32)
  let mut schedules = 0
  let mut starts = 0
  let mut diagnostics = 0
  for event in events {
    if required_string(event, "type", max=64) != "upstream/event" {
      continue
    }
    let data = required_field(event, "data")
    let record = required_field(data, "record")
    match required_string(record, "type", max=128) {
      "assistant/attempt" => diagnostics += 1
      "llm/retry" => {
        schedules += 1
        let retry = required_field(record, "data")
        let failure = required_field(retry, "failure")
        assert_eq(
          required_string(retry, "policyKey", max=128),
          "policy-portable",
        )
        if schedules == 1 {
          assert_eq(required_string(failure, "code", max=64), "RATE_LIMIT")
          match required_field(retry, "delayMs") {
            Json::Number(delay, ..) => assert_eq(delay, 10000.5)
            _ => panic()
          }
        } else {
          assert_eq(required_string(failure, "code", max=64), "EMPTY_RESPONSE")
        }
      }
      "llm/retry-started" => starts += 1
      _ => ()
    }
  }
  assert_eq(schedules, 2)
  assert_eq(starts, 2)
  assert_eq(diagnostics, 1)
  assert_true(engine.take_effects().is_empty())

  let malformed = jsonl.replace_all(
    old="\"retry\":1,\"maxRetries\":2",
    new="\"retry\":3,\"maxRetries\":3",
  )
  let before = engine.snapshot()
  assert_true(
    engine.invoke(
      "session_import",
      object([("jsonl", Json::string(malformed))]),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(engine.take_effects().is_empty())
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
  assert_eq(required_field(imported, "todos"), Json::null())
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
  let forged_todo_projection = checked_copy(before)
  let forged_todo_sessions = array_value(
    required_field(forged_todo_projection, "sessions"),
    "sessions",
    8,
  )
  fields(forged_todo_sessions[0]).set(
    "todos",
    Json::array([
      { "content": "Forged native projection", "status": "completed" },
    ]),
  )
  let rejects_todos = Engine::new([])
  let empty_todo_engine = rejects_todos.snapshot()
  assert_true(rejects_todos.restore(forged_todo_projection) is Err(_))
  assert_eq(rejects_todos.snapshot(), empty_todo_engine)
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
test "Session v4 catalog metadata and unresolved image references remain inert" {
  let engine = Engine::new(test_tools())
  let imported = success(
    engine.invoke(
      "session_import",
      object([("jsonl", Json::string(session_v4_metadata_fixture()))]),
    ),
  )
  assert_eq(get_status(imported), "completed")
  let messages = array_value(
    required_field(imported, "messages"),
    "messages",
    16,
  )
  assert_eq(messages.length(), 6)
  assert_true(
    required_string(messages[2], "content").contains(
      "[unresolved image attachment opaque-image-id (image/png, 1x2, 8 bytes; image data is not present in JSONL)]",
    ),
  )
  let events = array_value(required_field(imported, "events"), "events", 64)
  let mut ptc_starts = 0
  for event in events {
    if required_string(event, "type", max=64) == "upstream/event" {
      let record = required_field(required_field(event, "data"), "record")
      if required_string(record, "type", max=128) == "tool/ptc-dispatch-start" {
        ptc_starts += 1
      }
    }
  }
  assert_eq(ptc_starts, 1)
  assert_true(engine.take_effects().is_empty())

  let restored = Engine::new(test_tools())
  assert_true(restored.restore(engine.snapshot()) is Ok(_))
  assert_eq(
    success(
      restored.invoke("session_get", fixture("{\"session_id\":\"session-1\"}")),
    ),
    imported,
  )
  assert_true(restored.take_effects().is_empty())
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
