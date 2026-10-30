///|
fn provider_request_limit_reason(session : Json) -> String? raise EngineError {
  for event in array_value(required_field(session, "events"), "events", 32768) {
    if required_string(event, "type") == "turn/end" {
      match fields(required_field(event, "data")).get("reason") {
        Some(Json::String(reason)) => return Some(reason)
        _ => return None
      }
    }
  }
  None
}

///|
fn mutate_provider_turn_start_limit(
  snapshot : Json,
  value : Json,
) -> Json raise EngineError {
  let forged = json_copy(snapshot)
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  for event in array_value(required_field(session, "events"), "events", 32768) {
    if required_string(event, "type") == "turn/start" {
      let data = fields(required_field(event, "data")).copy()
      data.set("max_provider_request_utf8_bytes", value)
      fields(event).set("data", Json::object(data))
      return forged
    }
  }
  abort("Snapshot has no turn/start event")
}

///|
fn mutate_provider_turn_end_reason(
  snapshot : Json,
  reason : String,
) -> Json raise EngineError {
  let forged = json_copy(snapshot)
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  for event in array_value(required_field(session, "events"), "events", 32768) {
    if required_string(event, "type") == "turn/end" {
      let data = fields(required_field(event, "data")).copy()
      data.set("reason", Json::string(reason))
      fields(event).set("data", Json::object(data))
      return forged
    }
  }
  abort("Snapshot has no turn/end event")
}

///|
test "provider request byte ceiling accepts the exact measured boundary and rejects one byte less before dispatch" {
  let request = object([
    ("system", Json::string("s")),
    (
      "messages",
      Json::array([
        object([("role", Json::string("user")), ("content", Json::string("p"))]),
      ]),
    ),
    ("tools", Json::array([])),
  ])
  let maximum = provider_context_measure_request(request)
    .unwrap()
    .request_json_utf8_bytes()
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke("session_create", {
        "id": "exact-ceiling",
        "system_prompt": "s",
      }),
    ),
  )
  let command = EngineCommand::from_json("session_send", {
    "session_id": "exact-ceiling",
    "prompt": "p",
    "max_provider_request_utf8_bytes": maximum,
  }).unwrap()
  let accepted = success(engine.apply(command))
  assert_eq(get_status(accepted), "running")
  let effects = engine.take_effects()
  assert_eq(effects.length(), 1)
  assert_eq(
    @utf8.encode(required_field(effects[0], "request").stringify()).length(),
    maximum,
  )
  let cancelled = success(
    engine.invoke("session_cancel", { "session_id": "exact-ceiling" }),
  )
  assert_eq(get_status(cancelled), "cancelled")
  assert_true(engine.take_effects().is_empty())
  let before_late_completion = engine.snapshot()
  assert_true(
    engine.complete(id_of(effects[0]), stop_response("too late")) is Err(_),
  )
  assert_eq(engine.snapshot(), before_late_completion)
  let restored_cancel = Engine::new([])
  assert_eq(restored_cancel.restore(engine.snapshot()), Ok(()))
  let cancelled_after_restore = success(
    restored_cancel.invoke("session_get", { "session_id": "exact-ceiling" }),
  )
  assert_eq(get_status(cancelled_after_restore), "cancelled")
  assert_true(restored_cancel.take_effects().is_empty())

  let rejected = Engine::new([])
  ignore(
    success(
      rejected.invoke("session_create", {
        "id": "below-ceiling",
        "system_prompt": "s",
      }),
    ),
  )
  let command = EngineCommand::from_json("session_send", {
    "session_id": "below-ceiling",
    "prompt": "p",
    "max_provider_request_utf8_bytes": maximum - 1,
  }).unwrap()
  let refused = success(rejected.apply(command))
  assert_eq(get_status(refused), "failed")
  assert_eq(
    provider_request_limit_reason(refused),
    Some("provider_request_limit"),
  )
  assert_true(rejected.take_effects().is_empty())
  let turn_start = array_value(required_field(refused, "events"), "events", 32).filter(event => {
        required_string(event, "type") == "turn/start"
      },
    )[0]
  assert_eq(
    required_field(
      required_field(turn_start, "data"),
      "max_provider_request_utf8_bytes",
    ),
    integer(maximum - 1),
  )
}

///|
test "provider request ceiling commits known tool results and is retained through approval restore" {
  let engine = Engine::new(test_tools())
  ignore(success(engine.invoke("session_create", { "id": "bounded-tool" })))
  let send = EngineCommand::from_json("session_send", {
    "session_id": "bounded-tool",
    "prompt": "Run the approved write",
    "max_provider_request_utf8_bytes": 4096,
  }).unwrap()
  ignore(success(engine.apply(send)))
  let first = engine.take_effects()
  assert_eq(first.length(), 1)
  let pending = success(
    engine.complete(
      id_of(first[0]),
      calls_response([
        (
          "write-under-limit", "write", "{\"file_path\":\"out.txt\",\"content\":\"small\"}",
        ),
      ]),
    ),
  )
  assert_eq(get_status(pending), "awaiting_approval")
  assert_true(engine.take_effects().is_empty())

  // The durable turn/start setting must survive a quiescent approval restore.
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore(engine.snapshot()), Ok(()))
  let approve = EngineCommand::ApproveTool(
    SessionId::new("bounded-tool").unwrap(),
    ToolCallId::new("write-under-limit").unwrap(),
    true,
  )
  ignore(success(reopened.apply(approve)))
  let write_effects = reopened.take_effects()
  assert_eq(write_effects.length(), 1)
  let finished = success(
    reopened.complete(
      id_of(write_effects[0]),
      object([
        ("ok", boolean(true)),
        ("content", Json::string("x".repeat(6000))),
      ]),
    ),
  )
  assert_eq(get_status(finished), "failed")
  assert_eq(
    provider_request_limit_reason(finished),
    Some("provider_request_limit"),
  )
  assert_true(reopened.take_effects().is_empty())
  let events = array_value(required_field(finished, "events"), "events", 32768)
  assert_true(
    events.any(event => {
      if required_string(event, "type") != "tool/result" {
        return false
      }
      let data = required_field(event, "data")
      assert_eq(required_string(data, "tool_call_id"), "write-under-limit")
      assert_eq(required_string(data, "content"), "x".repeat(6000))
      assert_eq(required_field(data, "is_error"), boolean(false))
      true
    }),
  )
  let after_commit = reopened.snapshot()
  assert_true(
    reopened.complete(
      id_of(write_effects[0]),
      object([("ok", boolean(true)), ("content", Json::string("duplicate"))]),
    )
    is Err(_),
  )
  assert_eq(reopened.snapshot(), after_commit)
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(reopened.snapshot()), Ok(()))
  let restored_session = success(
    restored.invoke("session_get", { "session_id": "bounded-tool" }),
  )
  assert_eq(get_status(restored_session), "failed")
  let model_tool_result = only_tool_result(
    array_value(required_field(restored_session, "messages"), "messages", 64),
  )
  assert_eq(
    required_string(model_tool_result, "tool_call_id"),
    "write-under-limit",
  )
  assert_eq(required_string(model_tool_result, "content"), "x".repeat(6000))
  assert_eq(required_field(model_tool_result, "is_error"), boolean(false))
  assert_true(restored.take_effects().is_empty())
  let next_turn = success(
    restored.invoke("session_send", {
      "session_id": "bounded-tool",
      "prompt": "Start a new uncapped turn",
    }),
  )
  assert_eq(get_status(next_turn), "running")
  assert_eq(restored.take_effects().length(), 1)
}

///|
test "late SubagentStart byte-limit closure restores and cannot be forged as completed" {
  let engine = Engine::new(test_tools())
  ignore(success(engine.invoke("session_create", { "id": "bounded-hook" })))
  let send = EngineCommand::from_json("session_send", {
    "session_id": "bounded-hook",
    "prompt": "Start under the request ceiling",
    "max_provider_request_utf8_bytes": 4096,
  }).unwrap()
  ignore(success(engine.apply(send)))
  let first = engine.take_effects()
  assert_eq(first.length(), 1)
  assert_eq(
    engine.inject_hook_contexts("bounded-hook", ["L".repeat(4096)]),
    Ok(true),
  )
  let finished = success(
    engine.complete(id_of(first[0]), stop_response("first answer")),
  )
  assert_eq(get_status(finished), "failed")
  assert_eq(
    provider_request_limit_reason(finished),
    Some("provider_request_limit"),
  )
  assert_true(engine.take_effects().is_empty())

  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore(engine.snapshot()), Ok(()))
  assert_eq(
    get_status(
      success(reopened.invoke("session_get", { "session_id": "bounded-hook" })),
    ),
    "failed",
  )
  let forged = mutate_provider_turn_end_reason(engine.snapshot(), "completed")
  let untouched = Engine::new(test_tools())
  let before = untouched.snapshot()
  assert_true(untouched.restore(forged) is Err(_))
  assert_eq(untouched.snapshot(), before)
}

///|
test "provider request ceiling rejects malformed limits and unsupported limit endings on restore" {
  for
    value in [
      integer(0),
      integer(16777217),
      Json::number(1.5),
      Json::string("4"),
    ] {
    assert_true(
      EngineCommand::from_json("session_send", {
        "session_id": "bad-limit",
        "prompt": "question",
        "max_provider_request_utf8_bytes": value,
      })
      is Err(_),
    )
  }

  let capped = Engine::new([])
  ignore(success(capped.invoke("session_create", { "id": "tamper-cap" })))
  let send = EngineCommand::from_json("session_send", {
    "session_id": "tamper-cap",
    "prompt": "question",
    "max_provider_request_utf8_bytes": 1,
  }).unwrap()
  ignore(success(capped.apply(send)))
  assert_true(capped.take_effects().is_empty())
  for invalid in [integer(0), integer(16777217), Json::number(1.5)] {
    let forged = mutate_provider_turn_start_limit(capped.snapshot(), invalid)
    let target = Engine::new([])
    let before = target.snapshot()
    assert_true(target.restore(forged) is Err(_))
    assert_eq(target.snapshot(), before)
  }

  let ordinary = Engine::new([])
  ignore(success(ordinary.invoke("session_create", { "id": "uncapped" })))
  ignore(
    success(
      ordinary.invoke("session_send", {
        "session_id": "uncapped",
        "prompt": "question",
      }),
    ),
  )
  let first = ordinary.take_effects()[0]
  ignore(success(ordinary.complete(id_of(first), stop_response("done"))))
  let forged = mutate_provider_turn_end_reason(
    ordinary.snapshot(),
    "provider_request_limit",
  )
  let target = Engine::new([])
  let before = target.snapshot()
  assert_true(target.restore(forged) is Err(_))
  assert_eq(target.snapshot(), before)
}
