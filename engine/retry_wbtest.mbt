///|
fn retry_policy(
  code? : String = "SERVER",
  max_retries? : Int = 2,
  initial_delay_ms? : Int = 5,
  max_delay_ms? : Int = 50,
  retry_after_ms? : Int? = None,
  request_id? : String? = None,
) -> Json {
  let failure = Map::from_array([
    ("code", Json::string(code)),
    ("message", Json::string("Provider HTTP 503")),
    ("status", integer(503)),
  ])
  match retry_after_ms {
    Some(delay) => failure.set("retry_after_ms", integer(delay))
    None => ()
  }
  match request_id {
    Some(value) => failure.set("request_id", Json::string(value))
    None => ()
  }
  object([
    ("failure", Json::object(failure)),
    ("max_retries", integer(max_retries)),
    ("initial_delay_ms", integer(initial_delay_ms)),
    ("max_delay_ms", integer(max_delay_ms)),
  ])
}

///|
test "provider retry is durable before the wait and starts on the same step" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  let scheduled = success(
    engine.schedule_retry(
      effect_id,
      retry_policy(request_id=Some("req_fixture")),
    ),
  )
  assert_eq(required_field(scheduled, "scheduled"), boolean(true))
  assert_eq(required_string(scheduled, "retry_id"), "retry-\{effect_id}-1")
  assert_eq(int_value(required_field(scheduled, "delay_ms"), "delay", 0, 50), 5)
  let pending = get_session(engine)
  let events = array_value(required_field(pending, "events"), "events", 100)
  assert_eq(required_string(events[events.length() - 1], "type"), "llm/retry")
  assert_eq(
    required_string(
      required_field(
        required_field(events[events.length() - 1], "data"),
        "failure",
      ),
      "request_id",
    ),
    "req_fixture",
  )
  assert_eq(engine.take_effects().length(), 0)
  assert_true(engine.start_retry(effect_id, "wrong-retry-id") is Err(_))
  assert_eq(
    required_string(
      array_value(required_field(get_session(engine), "events"), "events", 100)[events.length() -
      1],
      "type",
    ),
    "llm/retry",
  )
  ignore(
    success(
      engine.start_retry(effect_id, required_string(scheduled, "retry_id")),
    ),
  )
  let completed = success(
    engine.complete(effect_id, stop_response("recovered")),
  )
  assert_eq(get_status(completed), "completed")
  let final_events = array_value(
    required_field(completed, "events"),
    "events",
    100,
  )
  assert_eq(
    final_events
    .filter(event => required_string(event, "type") == "llm/request")
    .length(),
    1,
  )
  assert_eq(
    final_events
    .filter(event => required_string(event, "type") == "llm/retry")
    .length(),
    1,
  )
  assert_eq(
    final_events
    .filter(event => required_string(event, "type") == "llm/retry-started")
    .length(),
    1,
  )
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(engine.snapshot()), Ok(()))
  assert_eq(get_session(restored), completed)
  assert_eq(restored.take_effects().length(), 0)
}

///|
test "retry budget is enforced by MoonBit and retry never follows accepted deltas" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  ignore(
    success(
      engine.schedule_retry(
        effect_id,
        retry_policy(max_retries=1, initial_delay_ms=0),
      ),
    ),
  )
  ignore(success(engine.start_retry(effect_id, "retry-\{effect_id}-1")))
  assert_eq(
    required_field(
      success(
        engine.schedule_retry(
          effect_id,
          retry_policy(max_retries=1, initial_delay_ms=0),
        ),
      ),
      "scheduled",
    ),
    boolean(false),
  )
  ignore(
    success(
      engine.complete(
        effect_id,
        object([
          ("ok", boolean(false)),
          ("error", Json::string("Provider HTTP 503")),
        ]),
      ),
    ),
  )
  let ended = get_session(engine)
  assert_eq(get_status(ended), "failed")
  let ended_events = array_value(required_field(ended, "events"), "events", 100)
  assert_eq(
    ended_events
    .filter(event => required_string(event, "type") == "llm/retry")
    .length(),
    1,
  )
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore(engine.snapshot()), Ok(()))
  assert_eq(reopened.take_effects().length(), 0)

  let (streaming, stream_effect) = started_engine()
  let stream_id = id_of(stream_effect)
  ignore(success(streaming.project_stream(stream_id, "visible partial", "")))
  let refused = success(streaming.schedule_retry(stream_id, retry_policy()))
  assert_eq(required_field(refused, "scheduled"), boolean(false))
  let failed = success(
    streaming.complete(
      stream_id,
      object([
        ("ok", boolean(false)),
        ("error", Json::string("Provider transport failed")),
      ]),
    ),
  )
  assert_eq(get_status(failed), "failed")
  assert_eq(
    required_string(
      array_value(required_field(failed, "messages"), "messages", 100)[1],
      "stream_status",
    ),
    "partial",
  )
  assert_eq(
    array_value(required_field(failed, "events"), "events", 100)
    .filter(event => required_string(event, "type") == "llm/retry")
    .length(),
    0,
  )
}

///|
test "retry restore rejects forged event identity and interrupts a pending wait without replay" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  ignore(success(engine.schedule_retry(effect_id, retry_policy())))
  let pending_snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_eq(restored.restore(pending_snapshot), Ok(()))
  assert_eq(get_status(get_session(restored)), "failed")
  assert_eq(restored.take_effects().length(), 0)
  let restored_events = array_value(
    required_field(get_session(restored), "events"),
    "events",
    100,
  )
  assert_true(
    restored_events.any(event => required_string(event, "type") == "llm/retry"),
  )
  assert_true(
    restored_events.any(event => {
      required_string(event, "type") == "session/interrupted"
    }),
  )
  assert_true(
    !restored_events.any(event => {
      required_string(event, "type") == "llm/retry-started"
    }),
  )

  let forged = engine.snapshot()
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  let retry_event = events[events.length() - 1]
  fields(required_field(retry_event, "data")).set(
    "retry_id",
    Json::string("retry-forged"),
  )
  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "restore rejects a stream delta before the durable retry start atomically" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  let scheduled = success(engine.schedule_retry(effect_id, retry_policy()))
  ignore(
    success(
      engine.start_retry(effect_id, required_string(scheduled, "retry_id")),
    ),
  )
  ignore(success(engine.project_stream(effect_id, "accepted", "")))

  let forged = engine.snapshot()
  let session = array_value(required_field(forged, "sessions"), "sessions", 32)[0]
  let events = array_value(required_field(session, "events"), "events", 100)
  let rewritten = []
  for event in events {
    if required_string(event, "type") != "llm/retry-started" {
      fields(event).set("seq", integer(rewritten.length()))
      rewritten.push(event)
    }
  }
  assert_true(
    rewritten.any(event => {
      required_string(event, "type") == "assistant/stream_delta"
    }),
  )
  assert_true(
    !rewritten.any(event => {
      required_string(event, "type") == "llm/retry-started"
    }),
  )
  fields(session).set("events", Json::array(rewritten))

  let destination = Engine::new(test_tools())
  let before = destination.snapshot()
  assert_true(destination.restore(forged) is Err(_))
  assert_eq(destination.snapshot(), before)
}

///|
test "retry policy stays fixed and restored retry identity and budget are strict" {
  let (engine, llm) = started_engine()
  let effect_id = id_of(llm)
  let first = success(engine.schedule_retry(effect_id, retry_policy()))
  let retry_id = required_string(first, "retry_id")
  ignore(success(engine.start_retry(effect_id, retry_id)))
  let before_changed_policy = engine.snapshot()
  assert_true(
    engine.schedule_retry(
      effect_id,
      retry_policy(max_retries=3, initial_delay_ms=5, max_delay_ms=50),
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before_changed_policy)
  let second = success(engine.schedule_retry(effect_id, retry_policy()))
  assert_eq(required_field(second, "scheduled"), boolean(true))
  assert_eq(int_value(required_field(second, "delay_ms"), "delay", 0, 50), 10)

  let forged_budget = engine.snapshot()
  let budget_session = array_value(
      required_field(forged_budget, "sessions"),
      "sessions",
      32,
    )[0]
  let budget_events = array_value(
    required_field(budget_session, "events"),
    "events",
    100,
  )
  let second_schedule = budget_events[budget_events.length() - 1]
  fields(required_field(second_schedule, "data")).set("max_retries", integer(1))
  let rejected_budget = Engine::new(test_tools())
  assert_true(rejected_budget.restore(forged_budget) is Err(_))

  let forged_start = before_changed_policy
  let started_session = array_value(
      required_field(forged_start, "sessions"),
      "sessions",
      32,
    )[0]
  let started_events = array_value(
    required_field(started_session, "events"),
    "events",
    100,
  )
  let started_event = started_events[started_events.length() - 1]
  assert_eq(required_string(started_event, "type"), "llm/retry-started")
  fields(required_field(started_event, "data")).set(
    "effect_id",
    Json::string("effect-forged"),
  )
  let rejected_start = Engine::new(test_tools())
  assert_true(rejected_start.restore(forged_start) is Err(_))
}

///|
test "retry-after stays within the recorded cap and unsafe errors never schedule" {
  let (advised, advised_llm) = started_engine()
  let advised_result = success(
    advised.schedule_retry(
      id_of(advised_llm),
      retry_policy(retry_after_ms=Some(18)),
    ),
  )
  assert_eq(
    int_value(required_field(advised_result, "delay_ms"), "delay", 0, 50),
    18,
  )

  let (too_long, too_long_llm) = started_engine()
  let refused_delay = success(
    too_long.schedule_retry(
      id_of(too_long_llm),
      retry_policy(retry_after_ms=Some(51)),
    ),
  )
  assert_eq(required_field(refused_delay, "scheduled"), boolean(false))
  let unchanged_events = array_value(
    required_field(get_session(too_long), "events"),
    "events",
    100,
  )
  assert_eq(
    required_string(unchanged_events[unchanged_events.length() - 1], "type"),
    "llm/request",
  )

  let (auth, auth_llm) = started_engine()
  assert_eq(
    required_field(
      success(auth.schedule_retry(id_of(auth_llm), retry_policy(code="AUTH"))),
      "scheduled",
    ),
    boolean(false),
  )
  let (malformed, malformed_llm) = started_engine()
  assert_eq(
    required_field(
      success(
        malformed.schedule_retry(
          id_of(malformed_llm),
          retry_policy(code="MALFORMED"),
        ),
      ),
      "scheduled",
    ),
    boolean(false),
  )
}
