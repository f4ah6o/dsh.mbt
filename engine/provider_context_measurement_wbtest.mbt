///|
test "provider context measurement reads the exact request without draining effects" {
  let tools = [
    fixture(
      "{\"name\":\"read\",\"description\":\"Read 🌙\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"file_path\":{\"type\":\"string\"}},\"required\":[\"file_path\"],\"additionalProperties\":false},\"effect\":\"read\"}",
    ),
  ]
  let engine = Engine::new(tools)
  ignore(
    success(
      engine.invoke("session_create", {
        "id": "measure-context",
        "title": "Measurement",
        "system_prompt": "system 🌙",
      }),
    ),
  )
  ignore(
    success(
      engine.invoke("session_send", {
        "session_id": "measure-context",
        "prompt": "question 😀",
      }),
    ),
  )
  let session_id = SessionId::new("measure-context").unwrap()
  let before = engine.snapshot()
  let measurement = match engine.provider_context_measurement(session_id) {
    Ok(Some(value)) => value
    Ok(None) => abort("active provider request was not measured")
    Err(error) => abort(error)
  }
  assert_eq(engine.snapshot(), before)
  assert_eq(
    measurement.system_text_utf8_bytes(),
    @utf8.encode("system 🌙").length(),
  )
  assert_eq(measurement.system_text_utf8_bytes(), 11)
  assert_eq(
    measurement.system_text_code_points(),
    "system 🌙"[:].char_length(),
  )
  assert_eq(measurement.system_text_code_points(), 8)
  assert_eq(measurement.message_count(), 1)
  assert_eq(measurement.tool_count(), 1)

  let effects = engine.take_typed_effects()
  assert_eq(effects.length(), 1)
  let request = effects[0].request()
  assert_eq(
    measurement.request_json_utf8_bytes(),
    @utf8.encode(request.stringify()).length(),
  )
  assert_eq(
    measurement.messages_json_utf8_bytes(),
    @utf8.encode(required_field(request, "messages").stringify()).length(),
  )
  assert_eq(
    measurement.tools_json_utf8_bytes(),
    @utf8.encode(required_field(request, "tools").stringify()).length(),
  )

  // A drained dispatch remains inspectable until its matching completion.
  assert_true(engine.provider_context_measurement(session_id) is Ok(Some(_)))
  let still_queued = engine.take_typed_effects()
  assert_true(still_queued.is_empty())
}

///|
test "provider context measurement includes the active pruned message projection" {
  let engine = completed_engine_with_tool_result("x".repeat(9000))
  ignore(
    success(
      engine.invoke("session_send", {
        "session_id": "test",
        "prompt": "Continue with a measured projection",
        "auto_prune_tool_results": true,
      }),
    ),
  )
  let session_id = SessionId::new("test").unwrap()
  let measurement = engine
    .provider_context_measurement(session_id)
    .unwrap()
    .unwrap()
  let effects = engine.take_typed_effects()
  assert_eq(effects.length(), 1)
  let request = effects[0].request()
  let messages = required_field(request, "messages")
  assert_eq(
    measurement.messages_json_utf8_bytes(),
    @utf8.encode(messages.stringify()).length(),
  )
  assert_eq(
    required_string(
      only_tool_result(array_value(messages, "messages", 64)),
      "content",
    ),
    "x".repeat(DEFAULT_PRUNE_HEAD) +
    PRUNE_MARKER +
    "x".repeat(DEFAULT_PRUNE_TAIL),
  )
}

///|
test "provider context measurement reports no request after provider completion" {
  let (engine, request) = started_engine()
  let session_id = SessionId::new("test").unwrap()
  ignore(engine.take_effects())
  ignore(success(engine.complete(id_of(request), stop_response("done"))))
  assert_true(engine.provider_context_measurement(session_id) is Ok(None))
}

///|
test "provider context measurement rejects malformed and oversized request shapes" {
  assert_true(provider_context_measure_request({ "system": "x" }) is Err(_))
  assert_true(
    provider_context_measure_request({
      "system": "x",
      "messages": [],
      "tools": [],
      "extra": true,
    })
    is Err(_),
  )
  let boundary_system = "x".repeat(
    PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES - 38,
  )
  let exact_boundary = match
    provider_context_measure_request({
      "system": boundary_system,
      "messages": [],
      "tools": [],
    }) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  assert_eq(
    exact_boundary.request_json_utf8_bytes(),
    PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES,
  )
  assert_true(
    provider_context_measure_request({
      "system": boundary_system,
      "messages": [null],
      "tools": [],
    })
    is Err(_),
  )
  let escaped : Json = {
    "system": "x",
    "messages": [{ "role": "user", "content": "a\n\"\\\u0000" }],
    "tools": [],
  }
  let escaped_measurement = match provider_context_measure_request(escaped) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  assert_eq(
    escaped_measurement.messages_json_utf8_bytes(),
    @utf8.encode(required_field(escaped, "messages").stringify()).length(),
  )
  let unpaired : Json = {
    "system": Json::string(String::from_array([(0xD800).unsafe_to_char()])),
    "messages": Json::array([]),
    "tools": Json::array([]),
  }
  assert_true(provider_context_measure_request(unpaired) is Err(_))
}

///|
test "provider context byte walk matches JSON serialization across escapes and scalar widths" {
  let request : Json = {
    "system": "Aé漢😀\b\f\n\r\t\u001f\\\"",
    "messages": [true, false, null, Json::number(0.125), Json::number(1.0e20)],
    "tools": [{ "name": "tool", "input_schema": { "type": "object" } }],
  }
  let measurement = match provider_context_measure_request(request) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  assert_eq(
    measurement.request_json_utf8_bytes(),
    @utf8.encode(request.stringify()).length(),
  )
  assert_eq(
    measurement.messages_json_utf8_bytes(),
    @utf8.encode(required_field(request, "messages").stringify()).length(),
  )
  assert_eq(
    measurement.tools_json_utf8_bytes(),
    @utf8.encode(required_field(request, "tools").stringify()).length(),
  )
  let system = required_string(request, "system")
  assert_eq(measurement.system_text_utf8_bytes(), @utf8.encode(system).length())
  assert_eq(measurement.system_text_code_points(), system[:].char_length())
}
