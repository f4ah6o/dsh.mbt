///|
fn typed_test_command(
  operation : String,
  input : Json,
) -> @engine.EngineCommand {
  match @engine.EngineCommand::from_json(operation, input) {
    Ok(command) => command
    Err(error) => abort(error)
  }
}

///|
fn typed_test_json(result : Result[Json, String]) -> Json {
  match result {
    Ok(value) => value
    Err(error) => abort(error)
  }
}

///|
fn typed_test_stop_response(text : String) -> Json {
  Json::object(
    Map::from_array([
      ("ok", Json::boolean(true)),
      ("content", Json::string(text)),
      ("tool_calls", Json::array([])),
      ("finish_reason", Json::string("stop")),
    ]),
  )
}

///|
test "typed identifiers reject malformed session and effect identities" {
  assert_true(@engine.SessionId::new("session:good-1") is Ok(_))
  assert_true(@engine.SessionId::new("invalid id") is Err(_))
  assert_true(@engine.EffectId::new("effect-17") is Ok(_))
  assert_true(@engine.EffectId::new("effect-x") is Err(_))
  assert_true(@engine.ToolCallId::new("call_1") is Ok(_))
  assert_true(@engine.ToolCallId::new("call/id") is Err(_))
}

///|
test "typed commands drive the engine and typed effects/events match compatibility JSON" {
  let engine = @engine.Engine::new([])
  ignore(
    typed_test_json(
      engine.apply(
        typed_test_command("session_create", {
          "id": "typed-session",
          "title": "Typed",
          "max_steps": 3,
        }),
      ),
    ),
  )
  ignore(
    typed_test_json(
      engine.apply(
        typed_test_command("session_send", {
          "session_id": "typed-session",
          "prompt": "Hello",
        }),
      ),
    ),
  )
  let typed_effects = engine.take_typed_effects()
  assert_true(typed_effects.length() == 1)
  let effect = typed_effects[0]
  assert_true(effect.kind() == @engine.EffectType::Provider)
  assert_true(effect.id().as_string() == "effect-1")
  assert_true(effect.session_id().as_string() == "typed-session")
  let request = effect.request()
  assert_true(request is { "messages": Array(_), "tools": Array(_), .. })
  ignore(engine.project_effect_stream(effect.id(), "Hi", ""))
  ignore(
    typed_test_json(
      engine.complete_effect(effect.id(), typed_test_stop_response("Hi")),
    ),
  )

  let session_id = match @engine.SessionId::new("typed-session") {
    Ok(value) => value
    Err(error) => abort(error)
  }
  let events = match engine.event_log(session_id) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(
    events.any(event => event.kind() == @engine.EngineEventKind::TurnStarted),
  )
  assert_true(
    events.any(event => {
      event.kind() == @engine.EngineEventKind::AssistantMessage
    }),
  )
  let legacy_session = typed_test_json(
    engine.invoke("session_get", { "session_id": "typed-session" }),
  )
  assert_true(
    match legacy_session {
      Object(fields) =>
        match fields.get("events") {
          Some(value) =>
            value == Json::array(events.map(@engine.EngineEvent::json))
          None => false
        }
      _ => false
    },
  )
}

///|
test "typed command boundary rejects invalid identifiers without mutation" {
  let engine = @engine.Engine::new([])
  assert_true(
    @engine.EngineCommand::from_json("session_send", {
      "session_id": "bad/id",
      "prompt": "Hello",
    })
    is Err(_),
  )
  assert_true(
    engine.apply(typed_test_command("session_create", { "id": "stable" }))
    is Ok(_),
  )
  assert_true(
    engine.invoke("session_send", { "session_id": "bad/id", "prompt": "Hello" })
    is Err(_),
  )
  let sessions = typed_test_json(engine.invoke("session_list", {}))
  assert_true(
    match sessions {
      Array(values) => values.length() == 1
      _ => false
    },
  )
}

///|
test "custom tool calls retain kind and settle as explicit errors without dispatch" {
  let engine = @engine.Engine::new([
    {
      "name": "run_text",
      "description": "A JSON function with a deliberately colliding name",
      "input_schema": {
        "type": "object",
        "required": ["command"],
        "properties": { "command": { "type": "string" } },
      },
      "effect": "shell",
    },
  ])
  ignore(
    typed_test_json(
      engine.apply(
        typed_test_command("session_create", { "id": "custom-kind" }),
      ),
    ),
  )
  ignore(
    typed_test_json(
      engine.apply(
        typed_test_command("session_send", {
          "session_id": "custom-kind",
          "prompt": "Run the custom text tool",
        }),
      ),
    ),
  )
  let request = engine.take_typed_effects()
  assert_true(request.length() == 1)
  let response : Json = {
    "ok": true,
    "content": "",
    "tool_calls": [
      {
        "id": "custom_1",
        "name": "run_text",
        "kind": "custom",
        "arguments": "delete important files",
      },
    ],
    "finish_reason": "tool_calls",
  }
  ignore(typed_test_json(engine.complete_effect(request[0].id(), response)))

  let follow_up = engine.take_typed_effects()
  assert_true(follow_up.length() == 1)
  assert_true(follow_up[0].kind() == @engine.EffectType::Provider)
  let history = match follow_up[0].request() {
    Object(fields) =>
      match fields.get("messages") {
        Some(Array(messages)) => messages
        _ => fail("custom call should produce follow-up history")
      }
    _ => fail("provider request should be an object")
  }
  let assistant = history[1]
  let serialized_call = match assistant {
    Object(fields) =>
      match fields.get("tool_calls") {
        Some(Array(calls)) => calls[0]
        _ => fail("assistant call must remain in history")
      }
    _ => fail("assistant message should be an object")
  }
  assert_true(
    match serialized_call {
      Object(fields) => fields.get("kind") == Some("custom".to_json())
      _ => false
    },
  )
  let result = history[2]
  assert_true(
    match result {
      Object(fields) =>
        match fields.get("content") {
          Some(String(content)) =>
            content.contains("local custom-tool execution is not configured")
          _ => false
        }
      _ => false
    },
  )
  assert_true(
    match result {
      Object(fields) => fields.get("is_error") == Some(true.to_json())
      _ => false
    },
  )

  ignore(
    typed_test_json(
      engine.complete_effect(
        follow_up[0].id(),
        typed_test_stop_response("Safe"),
      ),
    ),
  )
  let snapshot = engine.snapshot()
  let restored = @engine.Engine::new([
    {
      "name": "run_text",
      "description": "A JSON function with a deliberately colliding name",
      "input_schema": {
        "type": "object",
        "required": ["command"],
        "properties": { "command": { "type": "string" } },
      },
      "effect": "shell",
    },
  ])
  assert_true(restored.restore(snapshot) is Ok(_))
  let restored_session = typed_test_json(
    restored.invoke("session_get", { "session_id": "custom-kind" }),
  )
  assert_true(
    match restored_session {
      Object(fields) => fields.get("status") == Some("completed".to_json())
      _ => false
    },
  )
}

///|
test "event kind compatibility preserves imported and future wire tags" {
  assert_true(
    @engine.EngineEventKind::from_wire("turn/start").wire() == "turn/start",
  )
  assert_true(
    @engine.EngineEventKind::from_wire("future/event").wire() == "future/event",
  )
}

///|
test "QuickCheck verifies repeated typed send and settlement operation sequences" {
  @quickcheck.check(
    (sample : Int) => {
      let turns = Int::abs(sample % 8) + 1
      let engine = @engine.Engine::new([])
      if engine.apply(
          typed_test_command("session_create", { "id": "quickcheck" }),
        )
        is Err(_) {
        return false
      }
      let mut valid = true
      for turn = 0; turn < turns && valid; turn = turn + 1 {
        if engine.apply(
            typed_test_command("session_send", {
              "session_id": "quickcheck",
              "prompt": "question-{turn}",
            }),
          )
          is Err(_) {
          valid = false
        } else {
          let effects = engine.take_typed_effects()
          if effects.length() != 1 ||
            effects[0].kind() != @engine.EffectType::Provider {
            valid = false
          } else {
            valid = engine.complete_effect(
                effects[0].id(),
                typed_test_stop_response("answer-{turn}"),
              )
              is Ok(_)
          }
        }
      }
      match engine.invoke("session_get", { "session_id": "quickcheck" }) {
        Ok(Object(fields)) =>
          valid &&
          fields.get("turn_id") == Some(turns.to_json()) &&
          fields.get("status") == Some("completed".to_json())
        _ => false
      }
    },
    count=80U,
    seed=20261007,
  )
}
