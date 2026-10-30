///|
fn completed_engine_with_tool_result(content : String) -> Engine {
  let (engine, first_request) = started_engine()
  ignore(
    success(
      engine.complete(
        id_of(first_request),
        calls_response([("read-long", "read", "{\"file_path\":\"large.txt\"}")]),
      ),
    ),
  )
  let read_effects = engine.take_effects()
  if read_effects.length() != 1 {
    abort("Expected one read effect")
  }
  ignore(
    success(
      engine.complete(
        id_of(read_effects[0]),
        object([("ok", boolean(true)), ("content", Json::string(content))]),
      ),
    ),
  )
  let followup = engine.take_effects()
  if followup.length() != 1 {
    abort("Expected one follow-up request")
  }
  ignore(
    success(
      engine.complete(id_of(followup[0]), stop_response("First turn complete")),
    ),
  )
  engine
}

///|
fn pruning_input(
  threshold_chars? : Int32,
  head_chars? : Int32,
  tail_chars? : Int32,
) -> Json {
  let values = Map::from_array([("session_id", Json::string("test"))])
  match threshold_chars {
    Some(value) => values.set("threshold_chars", integer(value))
    None => ()
  }
  match head_chars {
    Some(value) => values.set("head_chars", integer(value))
    None => ()
  }
  match tail_chars {
    Some(value) => values.set("tail_chars", integer(value))
    None => ()
  }
  Json::object(values)
}

///|
fn prune_response_session(response : Json) -> Json {
  required_field(response, "session") catch {
    _ => abort("Pruning response is missing its session")
  }
}

///|
fn only_tool_result(messages : Array[Json]) -> Json {
  let matches = messages.filter(message => {
    match message {
      Json::Object(data) => data.get("role") == Some(Json::string("tool"))
      _ => false
    }
  })
  if matches.length() > 0 {
    matches[0]
  } else {
    abort("Expected a tool result message")
  }
}

///|
fn json_copy(value : Json) -> Json {
  @json.parse(value.stringify()) catch {
    _ => abort("Could not copy JSON fixture")
  }
}

///|
test "tool-result pruning uses upstream code-point budgets and converges at the marker limit" {
  assert_eq(PRUNE_MARKER, "\n\n[... tool result middle pruned ...]\n\n")
  assert_eq(DEFAULT_PRUNE_THRESHOLD, 8192)
  assert_eq(DEFAULT_PRUNE_HEAD, 4096)
  assert_eq(DEFAULT_PRUNE_TAIL, 1024)
  assert_eq(code_point_length("a😀b"), 3)

  let default_config = checked_prune_config(
    DEFAULT_PRUNE_THRESHOLD,
    DEFAULT_PRUNE_HEAD,
    DEFAULT_PRUNE_TAIL,
  ) catch {
    _ => abort("Upstream defaults must satisfy their own output budget")
  }
  let long_ascii = StringView::repeat("x"[:], 8193).to_owned()
  let default_result = prune_text(long_ascii, default_config).unwrap()
  assert_eq(
    default_result,
    StringView::repeat("x"[:], 4096).to_owned() +
    PRUNE_MARKER +
    StringView::repeat("x"[:], 1024).to_owned(),
  )
  assert_eq(
    code_point_length(default_result),
    DEFAULT_PRUNE_HEAD + code_point_length(PRUNE_MARKER) + DEFAULT_PRUNE_TAIL,
  )

  let marker_only = checked_prune_config(code_point_length(PRUNE_MARKER), 0, 0) catch {
    _ => abort("The marker-only budget must be valid")
  }
  assert_eq(
    prune_text(
      "😀"[:].repeat(code_point_length(PRUNE_MARKER) + 5).to_owned(),
      marker_only,
    ),
    Some(PRUNE_MARKER),
  )
}

///|
test "manual pruning keeps original transcript and reloads an idempotent provider projection" {
  let original = "😀"[:].repeat(60).to_owned()
  let engine = completed_engine_with_tool_result(original)
  let threshold = code_point_length(PRUNE_MARKER) + 7
  let policy = pruning_input(
    threshold_chars=threshold,
    head_chars=4,
    tail_chars=3,
  )
  let outcome = success(engine.invoke("session_prune_tool_results", policy))
  let session = prune_response_session(outcome)
  let replacements = array_value(
    required_field(outcome, "pruned"),
    "pruned",
    16,
  ) catch {
    _ => abort("Pruning response has invalid replacements")
  }
  assert_eq(replacements.length(), 1)
  assert_eq(required_field(outcome, "chars_removed"), integer(60 - threshold))
  assert_eq(required_string(outcome, "chars_unit"), "unicode_code_points")

  let transcript = array_value(
    required_field(session, "messages"),
    "messages",
    32768,
  ) catch {
    _ => abort("Session has invalid transcript messages")
  }
  let transcript_result = only_tool_result(transcript)
  assert_eq(required_string(transcript_result, "tool_call_id"), "read-long")
  assert_eq(required_string(transcript_result, "content"), original)

  let events = array_value(required_field(session, "events"), "events", 32768) catch {
    _ => abort("Session has invalid events")
  }
  let original_seq = int_value(
    required_field(replacements[0], "original_seq"),
    "original_seq",
    0,
    32767,
  ) catch {
    _ => abort("Missing original event sequence")
  }
  let replacement_seq = int_value(
    required_field(replacements[0], "replacement_seq"),
    "replacement_seq",
    0,
    32767,
  ) catch {
    _ => abort("Missing pruning event sequence")
  }
  assert_eq(
    required_string(required_field(events[original_seq], "data"), "content"),
    original,
  )
  assert_eq(
    required_string(events[replacement_seq], "type"),
    "tool/result/pruned",
  )
  assert_eq(
    required_string(required_field(events[replacement_seq], "data"), "call_id"),
    "read-long",
  )

  // A reload reconstructs the provider-only projection from validated prune
  // events, while exposing the exact same raw transcript to the caller.
  let snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_true(restored.restore(snapshot) is Ok(_))
  assert_eq(
    required_field(
      success(
        restored.invoke("session_get", fixture("{\"session_id\":\"test\"}")),
      ),
      "messages",
    ),
    required_field(session, "messages"),
  )
  assert_eq(restored.take_effects().length(), 0)
  let repeated = success(restored.invoke("session_prune_tool_results", policy))
  assert_eq(
    array_value(required_field(repeated, "pruned"), "pruned", 16).length(),
    0,
  )
  assert_eq(restored.snapshot().stringify(), snapshot.stringify())

  // Transcript history remains full fidelity; the provider-only projection is
  // built from the validated pruning event when the next turn is admitted.
  ignore(
    success(
      restored.invoke(
        "session_send",
        fixture(
          "{\"session_id\":\"test\",\"prompt\":\"Continue after pruning\"}",
        ),
      ),
    ),
  )
  let request_effects = restored.take_effects()
  let request_messages = array_value(
    required_field(required_field(request_effects[0], "request"), "messages"),
    "messages",
    32768,
  ) catch {
    _ => abort("Provider request has invalid messages")
  }
  let projected = only_tool_result(request_messages)
  assert_eq(
    required_string(projected, "content"),
    "😀"[:].repeat(4).to_owned() +
    PRUNE_MARKER +
    "😀"[:].repeat(3).to_owned(),
  )
  assert_eq(required_string(projected, "tool_call_id"), "read-long")
  assert_eq(required_field(projected, "is_error"), boolean(false))
}

///|
test "automatic pruning is opt-in, Unicode-safe, and retained across restore" {
  let original = "😀"[:].repeat(DEFAULT_PRUNE_THRESHOLD + 1).to_owned()
  let source = completed_engine_with_tool_result(original)
  let base = source.snapshot()

  // Omitting the flag preserves the existing full provider context.
  let default_engine = Engine::new(test_tools())
  assert_true(default_engine.restore(json_copy(base)) is Ok(_))
  let default_session = success(
    default_engine.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":\"Continue\"}"),
    ),
  )
  let default_events = array_value(
    required_field(default_session, "events"),
    "events",
    32768,
  )
  assert_false(
    default_events.any(event => {
      required_string(event, "type") == "tool/result/pruned"
    }),
  )
  let default_effects = default_engine.take_effects()
  assert_eq(default_effects.length(), 1)
  let default_messages = array_value(
    required_field(required_field(default_effects[0], "request"), "messages"),
    "messages",
    32768,
  )
  assert_eq(
    required_string(only_tool_result(default_messages), "content"),
    original,
  )

  let preview_engine = Engine::new(test_tools())
  assert_true(preview_engine.restore(json_copy(base)) is Ok(_))
  let preview_before = preview_engine.snapshot().stringify()
  let preview_command = EngineCommand::from_json(
    "session_send",
    object([
      ("session_id", Json::string("test")),
      ("prompt", Json::string("Preview with pruning")),
      ("auto_prune_tool_results", boolean(true)),
    ]),
  ).unwrap()
  assert_true(preview_engine.preview(preview_command) is Ok(_))
  assert_eq(preview_engine.snapshot().stringify(), preview_before)
  assert_eq(preview_engine.take_effects().length(), 0)

  let engine = Engine::new(test_tools())
  assert_true(engine.restore(json_copy(base)) is Ok(_))
  let sent = success(
    engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("Continue with pruning")),
        ("auto_prune_tool_results", boolean(true)),
      ]),
    ),
  )
  let messages = array_value(
    required_field(sent, "messages"),
    "messages",
    32768,
  )
  assert_eq(required_string(only_tool_result(messages), "content"), original)
  let events = array_value(required_field(sent, "events"), "events", 32768)
  let result_event = events.filter(event => {
      required_string(event, "type") == "tool/result"
    })[0]
  let prune_events = events.filter(event => {
    required_string(event, "type") == "tool/result/pruned"
  })
  assert_eq(prune_events.length(), 1)
  let prune_event = prune_events[0]
  let prune_data = required_field(prune_event, "data")
  assert_eq(
    required_field(prune_data, "result_seq"),
    required_field(result_event, "seq"),
  )
  assert_eq(
    required_field(prune_data, "source_seq"),
    required_field(result_event, "seq"),
  )
  assert_eq(required_string(prune_data, "call_id"), "read-long")
  assert_eq(
    required_string(prune_data, "content"),
    "😀"[:].repeat(DEFAULT_PRUNE_HEAD).to_owned() +
    PRUNE_MARKER +
    "😀"[:].repeat(DEFAULT_PRUNE_TAIL).to_owned(),
  )
  let starts = events.filter(event => {
    required_string(event, "type") == "turn/start"
  })
  assert_eq(starts.length(), 2)
  assert_true(
    int_value(required_field(prune_event, "seq"), "seq", 0, 32767) <
    int_value(required_field(starts[1], "seq"), "seq", 0, 32767),
  )

  let effects = engine.take_effects()
  assert_eq(effects.length(), 1)
  let request_messages = array_value(
    required_field(required_field(effects[0], "request"), "messages"),
    "messages",
    32768,
  )
  let projected = only_tool_result(request_messages)
  let projected_content = required_string(projected, "content")
  assert_eq(
    projected_content,
    "😀"[:].repeat(DEFAULT_PRUNE_HEAD).to_owned() +
    PRUNE_MARKER +
    "😀"[:].repeat(DEFAULT_PRUNE_TAIL).to_owned(),
  )
  assert_eq(required_string(projected, "tool_call_id"), "read-long")
  assert_eq(required_field(projected, "is_error"), boolean(false))

  ignore(
    success(engine.complete(id_of(effects[0]), stop_response("Continued"))),
  )
  assert_eq(engine.take_effects().length(), 0)
  let saved = engine.snapshot()
  let reopened = Engine::new(test_tools())
  assert_true(reopened.restore(saved) is Ok(_))
  assert_eq(reopened.take_effects().length(), 0)
  let repeated = success(
    reopened.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("Prune once more")),
        ("auto_prune_tool_results", boolean(true)),
      ]),
    ),
  )
  let repeated_events = array_value(
    required_field(repeated, "events"),
    "events",
    32768,
  )
  assert_eq(
    repeated_events
    .filter(event => required_string(event, "type") == "tool/result/pruned")
    .length(),
    1,
  )
  let repeated_effects = reopened.take_effects()
  assert_eq(repeated_effects.length(), 1)
  let repeated_request_messages = array_value(
    required_field(required_field(repeated_effects[0], "request"), "messages"),
    "messages",
    32768,
  )
  assert_eq(
    required_string(only_tool_result(repeated_request_messages), "content"),
    projected_content,
  )
  ignore(
    success(
      reopened.complete(
        id_of(repeated_effects[0]),
        stop_response("Pruned projection still fits"),
      ),
    ),
  )
  assert_eq(reopened.take_effects().length(), 0)
  let following = success(
    reopened.invoke(
      "session_send",
      fixture("{\"session_id\":\"test\",\"prompt\":\"After restore\"}"),
    ),
  )
  let reopened_effects = reopened.take_effects()
  assert_eq(reopened_effects.length(), 1)
  let reopened_request_messages = array_value(
    required_field(required_field(reopened_effects[0], "request"), "messages"),
    "messages",
    32768,
  )
  assert_eq(
    required_string(only_tool_result(reopened_request_messages), "content"),
    projected_content,
  )
  assert_eq(
    required_string(
      only_tool_result(
        array_value(required_field(following, "messages"), "messages", 32768),
      ),
      "content",
    ),
    original,
  )
}

///|
test "automatic pruning accepts settled cancelled sessions that can continue" {
  let engine = completed_engine_with_tool_result(
    "x"[:].repeat(DEFAULT_PRUNE_THRESHOLD + 1).to_owned(),
  )
  ignore(
    success(
      engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Will be cancelled\"}"),
      ),
    ),
  )
  assert_eq(engine.take_effects().length(), 1)
  let cancelled = success(
    engine.invoke("session_cancel", fixture("{\"session_id\":\"test\"}")),
  )
  assert_eq(get_status(cancelled), "cancelled")

  let sent = success(
    engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("Continue after cancellation")),
        ("auto_prune_tool_results", boolean(true)),
      ]),
    ),
  )
  assert_eq(get_status(sent), "running")
  assert_true(
    array_value(required_field(sent, "events"), "events", 32768).any(event => {
      required_string(event, "type") == "tool/result/pruned"
    }),
  )

  // Restore validates the prune event at its original cancelled-turn boundary
  // without replaying the provider request.
  let reopened = Engine::new(test_tools())
  assert_true(reopened.restore(engine.snapshot()) is Ok(_))
  assert_eq(reopened.take_effects().length(), 0)

  let failed_engine = completed_engine_with_tool_result(
    "y"[:].repeat(DEFAULT_PRUNE_THRESHOLD + 1).to_owned(),
  )
  ignore(
    success(
      failed_engine.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Will fail\"}"),
      ),
    ),
  )
  let failed_effects = failed_engine.take_effects()
  assert_eq(failed_effects.length(), 1)
  let failed = success(
    failed_engine.complete(
      id_of(failed_effects[0]),
      object([
        ("ok", boolean(false)),
        ("error", Json::string("provider unavailable")),
      ]),
    ),
  )
  assert_eq(get_status(failed), "failed")
  let continued = success(
    failed_engine.invoke(
      "session_send",
      object([
        ("session_id", Json::string("test")),
        ("prompt", Json::string("Continue after failure")),
        ("auto_prune_tool_results", boolean(true)),
      ]),
    ),
  )
  assert_eq(get_status(continued), "running")
  let failed_reopen = Engine::new(test_tools())
  assert_true(failed_reopen.restore(failed_engine.snapshot()) is Ok(_))
  assert_eq(failed_reopen.take_effects().length(), 0)
}

///|
test "automatic pruning rolls back its event and provider effect on capacity refusal" {
  // The original result is represented in the completed-tool event, result
  // event, and public transcript. A default prune event would exceed the
  // remaining serialized-session budget even though an ordinary short send
  // still fits.
  let base = completed_engine_with_tool_result("\n"[:].repeat(42000).to_owned())
  let saved = base.snapshot()
  let control = Engine::new(test_tools())
  assert_true(control.restore(json_copy(saved)) is Ok(_))
  ignore(
    success(
      control.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"Continue\"}"),
      ),
    ),
  )
  assert_eq(control.take_effects().length(), 1)

  let engine = Engine::new(test_tools())
  assert_true(engine.restore(json_copy(saved)) is Ok(_))
  let before = engine.snapshot().stringify()
  let automatic = engine.invoke(
    "session_send",
    object([
      ("session_id", Json::string("test")),
      ("prompt", Json::string("Continue")),
      ("auto_prune_tool_results", boolean(true)),
    ]),
  )
  assert_true(automatic is Err(_))
  assert_eq(engine.snapshot().stringify(), before)
  assert_eq(engine.take_effects().length(), 0)
}

///|
test "a tighter later policy chains from the current projection and restore rejects forged pruning" {
  let original = "😀"[:].repeat(60).to_owned()
  let engine = completed_engine_with_tool_result(original)
  let first_threshold = code_point_length(PRUNE_MARKER) + 7
  let first = success(
    engine.invoke(
      "session_prune_tool_results",
      pruning_input(threshold_chars=first_threshold, head_chars=4, tail_chars=3),
    ),
  )
  let first_replacement = array_value(
      required_field(first, "pruned"),
      "pruned",
      16,
    )[0]
  let first_seq = int_value(
    required_field(first_replacement, "replacement_seq"),
    "replacement_seq",
    0,
    32767,
  )
  let tighter_threshold = code_point_length(PRUNE_MARKER) + 2
  let second = success(
    engine.invoke(
      "session_prune_tool_results",
      pruning_input(
        threshold_chars=tighter_threshold,
        head_chars=1,
        tail_chars=1,
      ),
    ),
  )
  let second_replacement = array_value(
      required_field(second, "pruned"),
      "pruned",
      16,
    )[0]
  assert_eq(
    required_field(second_replacement, "source_seq"),
    integer(first_seq),
  )
  assert_eq(
    required_field(second_replacement, "chars_before"),
    integer(first_threshold),
  )
  assert_eq(
    required_field(second_replacement, "chars_after"),
    integer(tighter_threshold),
  )
  let second_session = prune_response_session(second)
  let raw_result = only_tool_result(
    array_value(required_field(second_session, "messages"), "messages", 32768),
  )
  assert_eq(required_string(raw_result, "content"), original)

  let saved = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_true(restored.restore(saved) is Ok(_))
  let same_policy = success(
    restored.invoke(
      "session_prune_tool_results",
      pruning_input(
        threshold_chars=tighter_threshold,
        head_chars=1,
        tail_chars=1,
      ),
    ),
  )
  assert_eq(
    array_value(required_field(same_policy, "pruned"), "pruned", 16).length(),
    0,
  )
  assert_eq(restored.snapshot().stringify(), saved.stringify())

  let pristine = Engine::new(test_tools())
  let empty_before = pristine.snapshot().stringify()
  let corrupted = json_copy(saved)
  let session = array_value(
      required_field(corrupted, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  let last = events[events.length() - 1]
  fields(required_field(last, "data")).set(
    "call_id",
    Json::string("wrong-call"),
  )
  assert_true(pristine.restore(corrupted) is Err(_))
  assert_eq(pristine.snapshot().stringify(), empty_before)

  let forged_forward = json_copy(saved)
  let forward_session = array_value(
      required_field(forged_forward, "sessions"),
      "sessions",
      32,
    )[0]
  let forward_events = array_value(
    required_field(forward_session, "events"),
    "events",
    32768,
  )
  let forward_last = forward_events[forward_events.length() - 1]
  fields(required_field(forward_last, "data")).set(
    "source_seq",
    integer(forward_events.length()),
  )
  assert_true(Engine::new(test_tools()).restore(forged_forward) is Err(_))

  let forged_content = json_copy(saved)
  let content_session = array_value(
      required_field(forged_content, "sessions"),
      "sessions",
      32,
    )[0]
  let content_events = array_value(
    required_field(content_session, "events"),
    "events",
    32768,
  )
  let content_last = content_events[content_events.length() - 1]
  fields(required_field(content_last, "data")).set(
    "content",
    Json::string("forged"),
  )
  assert_true(Engine::new(test_tools()).restore(forged_content) is Err(_))

  let forged_result_ref = json_copy(saved)
  let result_session = array_value(
      required_field(forged_result_ref, "sessions"),
      "sessions",
      32,
    )[0]
  let result_events = array_value(
    required_field(result_session, "events"),
    "events",
    32768,
  )
  fields(required_field(result_events[result_events.length() - 1], "data")).set(
    "result_seq",
    integer(0),
  )
  assert_true(Engine::new(test_tools()).restore(forged_result_ref) is Err(_))

  let forged_count = json_copy(saved)
  let count_session = array_value(
      required_field(forged_count, "sessions"),
      "sessions",
      32,
    )[0]
  let count_events = array_value(
    required_field(count_session, "events"),
    "events",
    32768,
  )
  fields(required_field(count_events[count_events.length() - 1], "data")).set(
    "chars_before",
    integer(999),
  )
  assert_true(Engine::new(test_tools()).restore(forged_count) is Err(_))

  let forged_budget = json_copy(saved)
  let budget_session = array_value(
      required_field(forged_budget, "sessions"),
      "sessions",
      32,
    )[0]
  let budget_events = array_value(
    required_field(budget_session, "events"),
    "events",
    32768,
  )
  fields(required_field(budget_events[budget_events.length() - 1], "data")).set(
    "threshold_chars",
    integer(code_point_length(PRUNE_MARKER) - 1),
  )
  assert_true(Engine::new(test_tools()).restore(forged_budget) is Err(_))

  let duplicate = json_copy(saved)
  let duplicate_session = array_value(
      required_field(duplicate, "sessions"),
      "sessions",
      32,
    )[0]
  let duplicate_events = array_value(
    required_field(duplicate_session, "events"),
    "events",
    32768,
  )
  let duplicate_event = json_copy(
    duplicate_events[duplicate_events.length() - 1],
  )
  fields(duplicate_event).set("seq", integer(duplicate_events.length()))
  fields(required_field(duplicate_event, "data")).set(
    "source_seq",
    integer(duplicate_events.length() - 1),
  )
  duplicate_events.push(duplicate_event)
  assert_true(Engine::new(test_tools()).restore(duplicate) is Err(_))
}

///|
test "invalid, busy, and capacity-rejected pruning leaves the live snapshot and effect queue unchanged" {
  let engine = completed_engine_with_tool_result(
    "large output"[:].repeat(100).to_owned(),
  )
  let before = engine.snapshot().stringify()
  let invalid_inputs = [
    fixture("{\"session_id\":\"test\",\"threshold\":10}"),
    object([
      ("session_id", Json::string("test")),
      ("threshold_chars", Json::number(10.5)),
    ]),
    object([
      ("session_id", Json::string("test")),
      ("threshold_chars", integer(code_point_length(PRUNE_MARKER))),
      ("head_chars", integer(1)),
      ("tail_chars", integer(0)),
    ]),
    object([
      ("session_id", Json::string("test")),
      ("threshold_chars", Json::null()),
    ]),
  ]
  for input in invalid_inputs {
    assert_true(engine.invoke("session_prune_tool_results", input) is Err(_))
    assert_eq(engine.snapshot().stringify(), before)
  }

  let busy = Engine::new(test_tools())
  ignore(
    success(
      busy.invoke("session_create", object([("id", Json::string("test"))])),
    ),
  )
  ignore(
    success(
      busy.invoke(
        "session_send",
        fixture("{\"session_id\":\"test\",\"prompt\":\"working\"}"),
      ),
    ),
  )
  let busy_before = busy.snapshot().stringify()
  assert_true(
    busy.invoke("session_prune_tool_results", pruning_input()) is Err(_),
  )
  assert_eq(busy.snapshot().stringify(), busy_before)
  assert_eq(busy.take_effects().length(), 1)

  // Three durable copies of escaped newline-heavy output fit before pruning,
  // while retaining nearly the whole result in a new event would exceed the
  // existing 262144-unit session cap. The operation must be all-or-nothing.
  let near_capacity_text = "\n"[:].repeat(40000).to_owned()
  let near_capacity = completed_engine_with_tool_result(near_capacity_text)
  let near_before = near_capacity.snapshot().stringify()
  assert_true(near_before.length() < SESSION_CAPACITY)
  assert_true(
    near_capacity.invoke(
      "session_prune_tool_results",
      pruning_input(threshold_chars=39000, head_chars=38000, tail_chars=500),
    )
    is Err(_),
  )
  assert_eq(near_capacity.snapshot().stringify(), near_before)
  assert_eq(near_capacity.take_effects().length(), 0)
}
