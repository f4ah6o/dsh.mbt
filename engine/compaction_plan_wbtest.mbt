///|
fn compaction_plan_complete_turn(
  engine : Engine,
  session_id : String,
  prompt : String,
  answer : String,
) -> Unit {
  ignore(
    success(
      engine.invoke(
        "session_send",
        object([
          ("session_id", Json::string(session_id)),
          ("prompt", Json::string(prompt)),
        ]),
      ),
    ),
  )
  let effects = engine.take_effects()
  if effects.length() != 1 {
    abort("Compaction planner fixture expected one provider effect")
  }
  ignore(success(engine.complete(id_of(effects[0]), stop_response(answer))))
}

///|
fn compaction_plan_field(value : Json, key : String) -> Int32 {
  int_value(required_field(value, key), key, 0, 1048576) catch {
    Invalid(message) => abort(message)
  }
}

///|
fn compaction_plan_required(
  engine : Engine,
  session_id : String,
  retain_recent_turns : Int32,
  max_events_bytes : Int32,
  max_messages_bytes : Int32,
) -> Json {
  match
    engine.plan_compaction_prefix(
      SessionId::from_validated(session_id),
      retain_recent_turns,
      max_events_bytes,
      max_messages_bytes,
    ) {
    Ok(Some(plan)) => plan
    Ok(None) => abort("Compaction planner fixture expected a prefix")
    Err(error) => abort(error)
  }
}

///|
fn compaction_plan_replace_field(
  value : Json,
  key : String,
  replacement : Json,
) -> Json {
  match value {
    Json::Object(items) => {
      let copy = items.copy()
      copy.set(key, replacement)
      Json::object(copy)
    }
    _ => abort("Compaction planner fixture expected an object")
  }
}

///|
fn compaction_candidate_required(
  engine : Engine,
  session_id : String,
  plan : Json,
  summary : String,
  max_summary_bytes : Int32,
) -> Json {
  match
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated(session_id),
      plan,
      summary,
      1,
      1048576,
      1048576,
      max_summary_bytes,
    ) {
    Ok(candidate) => candidate
    Err(error) => abort(error)
  }
}

///|
test "compaction prefix planning selects whole old turns without mutation" {
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("plan-history"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(
    engine, "plan-history", "old 😀\n\"", "answer one",
  )
  compaction_plan_complete_turn(engine, "plan-history", "middle", "answer two")
  compaction_plan_complete_turn(
    engine, "plan-history", "recent", "answer three",
  )

  let session_id = SessionId::from_validated("plan-history")
  let before = engine.snapshot()
  let plan = compaction_plan_required(
    engine, "plan-history", 1, 1048576, 1048576,
  )
  assert_eq(engine.snapshot(), before)
  assert_eq(engine.take_effects().length(), 0)
  assert_eq(compaction_plan_field(plan, "source_first_turn"), 1)
  assert_eq(compaction_plan_field(plan, "source_last_turn"), 2)
  assert_eq(compaction_plan_field(plan, "source_turn_count"), 2)
  assert_eq(compaction_plan_field(plan, "retained_turn_count"), 1)
  assert_eq(compaction_plan_field(plan, "source_message_count"), 4)
  assert_eq(
    compaction_plan_field(plan, "expected_event_count"),
    engine.event_log(session_id).unwrap().length(),
  )
  assert_eq(required_string(plan, "unit"), "serialized_utf8_bytes")

  let session = engine.sessions.get("plan-history").unwrap()
  let first_seq = compaction_plan_field(plan, "source_first_seq")
  let last_seq = compaction_plan_field(plan, "source_last_seq")
  let (content_by_result, _) = session.tool_result_pruning_state()
  let source_messages : Array[Json] = []
  let source_events : Array[Json] = []
  for event in session.events {
    if event.seq >= first_seq && event.seq <= last_seq {
      source_events.push(event.json())
      match compaction_source_message(event, content_by_result) {
        Some(message) => source_messages.push(message)
        None => ()
      }
    }
  }
  assert_eq(
    compaction_plan_field(plan, "source_messages_json_utf8_bytes"),
    @utf8.encode(Json::array(source_messages).stringify()).length(),
  )
  assert_eq(
    compaction_plan_field(plan, "source_event_json_utf8_bytes"),
    @utf8.encode(Json::array(source_events).stringify()).length(),
  )
  assert_eq(
    required_string(plan, "source_events_sha256"),
    archive_sha256(Json::array(source_events).stringify()),
  )
  assert_eq(
    required_string(plan, "source_messages_sha256"),
    archive_sha256(Json::array(source_messages).stringify()),
  )
}

///|
test "compaction prefix planning keeps a recent turn and respects both byte bounds" {
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("plan-bounds"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(engine, "plan-bounds", "old 🌙", "answer")
  compaction_plan_complete_turn(engine, "plan-bounds", "recent", "answer")

  assert_true(
    engine.plan_compaction_prefix(
      SessionId::from_validated("plan-bounds"),
      0,
      1048576,
      1048576,
    )
    is Err(_),
  )
  assert_true(
    engine.plan_compaction_prefix(
      SessionId::from_validated("plan-bounds"),
      1,
      0,
      1048576,
    )
    is Err(_),
  )
  assert_true(
    engine.plan_compaction_prefix(
      SessionId::from_validated("plan-bounds"),
      1,
      1048576,
      1,
    )
    is Ok(None),
  )
  let plan = compaction_plan_required(engine, "plan-bounds", 1, 1048576, 4096)
  assert_eq(compaction_plan_field(plan, "source_turn_count"), 1)
  assert_true(
    compaction_plan_field(plan, "source_messages_json_utf8_bytes") <= 4096,
  )

  let one_turn = Engine::new([])
  ignore(
    success(
      one_turn.invoke(
        "session_create",
        object([("id", Json::string("one-turn"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(one_turn, "one-turn", "only", "answer")
  assert_true(
    one_turn.plan_compaction_prefix(
      SessionId::from_validated("one-turn"),
      1,
      1048576,
      1048576,
    )
    is Ok(None),
  )
}

///|
test "compaction prefix plan rejects unsettled and fork-related sessions" {
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("plan-busy"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(engine, "plan-busy", "old", "answer")
  compaction_plan_complete_turn(engine, "plan-busy", "recent", "answer")
  let session_id = SessionId::from_validated("plan-busy")

  let fork_engine = Engine::new([])
  ignore(
    success(
      fork_engine.invoke(
        "session_create",
        object([("id", Json::string("plan-fork"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(fork_engine, "plan-fork", "old", "answer")
  compaction_plan_complete_turn(fork_engine, "plan-fork", "recent", "answer")
  ignore(
    success(
      fork_engine.invoke("session_fork", {
        "session_id": "plan-fork",
        "id": "plan-child",
      }),
    ),
  )
  assert_true(
    fork_engine.plan_compaction_prefix(
      SessionId::from_validated("plan-fork"),
      1,
      1048576,
      1048576,
    )
    is Err(_),
  )

  ignore(
    success(
      engine.invoke("session_send", {
        "session_id": "plan-busy",
        "prompt": "active",
      }),
    ),
  )
  let before = engine.snapshot()
  assert_true(
    engine.plan_compaction_prefix(session_id, 1, 1048576, 1048576) is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_eq(engine.take_effects().length(), 1)

  let approval_engine = Engine::new(test_tools())
  ignore(
    success(
      approval_engine.invoke(
        "session_create",
        object([("id", Json::string("plan-approval"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(
    approval_engine, "plan-approval", "old", "answer",
  )
  ignore(
    success(
      approval_engine.invoke("session_send", {
        "session_id": "plan-approval",
        "prompt": "write",
      }),
    ),
  )
  let approval_request = approval_engine.take_effects()
  ignore(
    success(
      approval_engine.complete(
        id_of(approval_request[0]),
        calls_response([
          ("write-call", "write", "{\"file_path\":\"note\",\"content\":\"x\"}"),
        ]),
      ),
    ),
  )
  assert_eq(
    get_status(
      success(
        approval_engine.invoke("session_get", { "session_id": "plan-approval" }),
      ),
    ),
    "awaiting_approval",
  )
  assert_true(
    approval_engine.plan_compaction_prefix(
      SessionId::from_validated("plan-approval"),
      1,
      1048576,
      1048576,
    )
    is Err(_),
  )

  let imported_engine = Engine::new(test_tools())
  let imported = success(
    imported_engine.invoke(
      "session_import",
      object([("jsonl", Json::string(session_v4_retry_portable_fixture()))]),
    ),
  )
  assert_true(
    imported_engine.plan_compaction_prefix(
      SessionId::from_validated(required_string(imported, "id")),
      1,
      1048576,
      1048576,
    )
    is Err(_),
  )
}

///|
test "compaction prefix fingerprint detects same-count archive projection changes" {
  let original = "x".repeat(96)
  let (engine, result_seq) = archive_plan_fixture(original)
  compaction_plan_complete_turn(engine, "test", "recent", "answer")
  let plan = engine
    .plan_tool_result_archive(SessionId::from_validated("test"), result_seq)
    .unwrap()
  let prune_event = engine.sessions.get("test").unwrap().events[plan.pruned_sequence()]
  let projection = required_string(prune_event.data, "content")
  let config = prune_config_from_event(prune_event.data) catch {
    Invalid(message) => abort(message)
  }
  let source = archive_test_object_source(plan, original, projection, config)

  let compact_before = compaction_plan_required(
    engine, "test", 1, 1048576, 1048576,
  )
  let event_count = compaction_plan_field(
    compact_before, "expected_event_count",
  )
  ignore(engine.commit_tool_result_archive(plan, source))
  let compact_after = compaction_plan_required(
    engine, "test", 1, 1048576, 1048576,
  )
  assert_eq(
    compaction_plan_field(compact_after, "expected_event_count"),
    event_count,
  )
  assert_true(
    required_string(compact_before, "source_events_sha256") !=
    required_string(compact_after, "source_events_sha256"),
  )
}

///|
test "compaction summary candidate binds a bounded summary without mutation" {
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("candidate-history"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(engine, "candidate-history", "old", "answer")
  compaction_plan_complete_turn(
    engine, "candidate-history", "recent", "recent answer",
  )
  let plan = compaction_plan_required(
    engine, "candidate-history", 1, 1048576, 1048576,
  )
  let summary = "Keep the old decision 🌙 and quote \"the source\"."
  let summary_bytes = @utf8.encode(Json::string(summary).stringify()).length()
  assert_eq(
    provider_context_measure_json_bytes(Json::string(summary)).unwrap(),
    summary_bytes,
  )
  let before = engine.snapshot()
  let candidate = compaction_candidate_required(
    engine, "candidate-history", plan, summary, summary_bytes,
  )

  assert_eq(engine.snapshot(), before)
  assert_true(engine.take_effects().is_empty())
  assert_eq(
    required_string(candidate, "schema"),
    "dsh.compaction-summary-candidate-v1",
  )
  assert_eq(required_field(candidate, "plan"), plan)
  assert_eq(required_string(candidate, "summary"), summary)
  assert_eq(
    compaction_plan_field(candidate, "summary_json_utf8_bytes"),
    summary_bytes,
  )
  assert_eq(required_string(candidate, "unit"), "serialized_utf8_bytes")
  assert_eq(
    required_string(required_field(candidate, "plan"), "source_events_sha256"),
    required_string(plan, "source_events_sha256"),
  )
  assert_eq(
    required_string(required_field(candidate, "plan"), "source_messages_sha256"),
    required_string(plan, "source_messages_sha256"),
  )

  let forged_event_fingerprint = compaction_plan_replace_field(
    plan,
    "source_events_sha256",
    Json::string("0".repeat(64)),
  )
  let forged_message_fingerprint = compaction_plan_replace_field(
    plan,
    "source_messages_sha256",
    Json::string("0".repeat(64)),
  )
  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("candidate-history"),
      Json::string("not a plan"),
      summary,
      1,
      1048576,
      1048576,
      1048576,
    )
    is Err(_),
  )
  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("candidate-history"),
      forged_event_fingerprint,
      summary,
      1,
      1048576,
      1048576,
      1048576,
    )
    is Err(_),
  )
  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("candidate-history"),
      forged_message_fingerprint,
      summary,
      1,
      1048576,
      1048576,
      1048576,
    )
    is Err(_),
  )

  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("candidate-history"),
      plan,
      summary,
      1,
      1048576,
      1048576,
      summary_bytes - 1,
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before)
  assert_true(engine.take_effects().is_empty())
}

///|
test "compaction summary candidate rejects changed source event fingerprint" {
  let original = "x".repeat(96)
  let (engine, result_seq) = archive_plan_fixture(original)
  compaction_plan_complete_turn(engine, "test", "recent", "answer")
  let plan = compaction_plan_required(engine, "test", 1, 1048576, 1048576)
  let archive = engine
    .plan_tool_result_archive(SessionId::from_validated("test"), result_seq)
    .unwrap()
  let prune_event = engine.sessions.get("test").unwrap().events[archive.pruned_sequence()]
  let projection = required_string(prune_event.data, "content")
  let config = prune_config_from_event(prune_event.data) catch {
    Invalid(message) => abort(message)
  }
  let source = archive_test_object_source(archive, original, projection, config)
  ignore(engine.commit_tool_result_archive(archive, source))
  let current = compaction_plan_required(engine, "test", 1, 1048576, 1048576)
  assert_eq(
    compaction_plan_field(plan, "expected_event_count"),
    compaction_plan_field(current, "expected_event_count"),
  )
  assert_true(
    required_string(plan, "source_events_sha256") !=
    required_string(current, "source_events_sha256"),
  )
  let before_candidate = engine.snapshot()

  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("test"),
      plan,
      "summary",
      1,
      1048576,
      1048576,
      1048576,
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), before_candidate)
  assert_true(engine.take_effects().is_empty())
}

///|
test "compaction prefix message digest tracks pruning dependencies in retained turns" {
  let engine = completed_engine_with_tool_result(
    "a".repeat(48) + "b".repeat(48),
  )
  compaction_plan_complete_turn(engine, "test", "recent", "answer")
  let before = compaction_plan_required(engine, "test", 1, 1048576, 1048576)
  let before_event_count = compaction_plan_field(before, "expected_event_count")

  ignore(
    success(
      engine.invoke(
        "session_prune_tool_results",
        pruning_input(
          threshold_chars=code_point_length(PRUNE_MARKER) + 7,
          head_chars=4,
          tail_chars=3,
        ),
      ),
    ),
  )

  let after = compaction_plan_required(engine, "test", 1, 1048576, 1048576)
  assert_true(
    compaction_plan_field(after, "expected_event_count") > before_event_count,
  )
  assert_eq(
    required_string(before, "source_events_sha256"),
    required_string(after, "source_events_sha256"),
  )
  assert_true(
    required_string(before, "source_messages_sha256") !=
    required_string(after, "source_messages_sha256"),
  )

  // Change a valid pruning policy on an event outside the selected range while
  // keeping its projected text the same byte length.
  let session = engine.sessions.get("test").unwrap()
  let prune_seq = session.events.length() - 1
  let prune_event = session.events[prune_seq]
  let result_seq = compaction_plan_field(prune_event.data, "result_seq")
  let original = required_string(session.events[result_seq].data, "content")
  let old_projection = required_string(prune_event.data, "content")
  let config = ToolResultPruneConfig::new(
    code_point_length(PRUNE_MARKER) + 7,
    5,
    2,
  ).unwrap()
  let new_projection = prune_text(original, config).unwrap()
  assert_true(old_projection != new_projection)
  assert_eq(
    @utf8.encode(old_projection).length(),
    @utf8.encode(new_projection).length(),
  )
  assert_true(prune_seq > compaction_plan_field(after, "source_last_seq"))
  archive_replace_event_field(
    session,
    prune_seq,
    "content",
    Json::string(new_projection),
  )
  archive_replace_event_field(session, prune_seq, "head_chars", integer(5))
  archive_replace_event_field(session, prune_seq, "tail_chars", integer(2))

  let after_same_count_change = compaction_plan_required(
    engine, "test", 1, 1048576, 1048576,
  )
  assert_eq(
    compaction_plan_field(after, "expected_event_count"),
    compaction_plan_field(after_same_count_change, "expected_event_count"),
  )
  assert_eq(
    required_string(after, "source_events_sha256"),
    required_string(after_same_count_change, "source_events_sha256"),
  )
  assert_true(
    required_string(after, "source_messages_sha256") !=
    required_string(after_same_count_change, "source_messages_sha256"),
  )
  let current_snapshot = engine.snapshot()
  let restored = Engine::new(test_tools())
  assert_true(restored.restore(current_snapshot) is Ok(_))
  assert_true(restored.take_effects().is_empty())
  assert_true(
    engine.prepare_compaction_summary_candidate(
      SessionId::from_validated("test"),
      after,
      "summary",
      1,
      1048576,
      1048576,
      1048576,
    )
    is Err(_),
  )
  assert_eq(engine.snapshot(), current_snapshot)
  assert_true(engine.take_effects().is_empty())
}

///|
test "compaction prefix keeps completed approval and tool correlation together" {
  let engine = Engine::new(test_tools())
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("plan-approved-turn"))]),
      ),
    ),
  )
  ignore(
    success(
      engine.invoke("session_send", {
        "session_id": "plan-approved-turn",
        "prompt": "write a file",
      }),
    ),
  )
  let llm = engine.take_effects()
  assert_eq(llm.length(), 1)
  ignore(
    success(
      engine.complete(
        id_of(llm[0]),
        calls_response([
          (
            "approved-write", "write", "{\"file_path\":\"note.txt\",\"content\":\"saved\"}",
          ),
        ]),
      ),
    ),
  )
  assert_eq(
    get_status(
      success(
        engine.invoke("session_get", { "session_id": "plan-approved-turn" }),
      ),
    ),
    "awaiting_approval",
  )
  ignore(
    success(
      engine.invoke("tool_approve", {
        "session_id": "plan-approved-turn",
        "call_id": "approved-write",
        "approved": true,
      }),
    ),
  )
  let write = engine.take_effects()
  assert_eq(write.length(), 1)
  assert_eq(call_id_of(write[0]), "approved-write")
  ignore(
    success(
      engine.complete(
        id_of(write[0]),
        fixture("{\"ok\":true,\"content\":\"saved\"}"),
      ),
    ),
  )
  let followup = engine.take_effects()
  assert_eq(followup.length(), 1)
  ignore(success(engine.complete(id_of(followup[0]), stop_response("done"))))
  compaction_plan_complete_turn(
    engine, "plan-approved-turn", "recent turn", "recent answer",
  )

  let plan = compaction_plan_required(
    engine, "plan-approved-turn", 1, 1048576, 1048576,
  )
  let before_candidate = engine.snapshot()
  let candidate = compaction_candidate_required(
    engine, "plan-approved-turn", plan, "The approved write was completed and correlated with its result.",
    1048576,
  )
  assert_eq(engine.snapshot(), before_candidate)
  assert_true(engine.take_effects().is_empty())
  assert_eq(
    required_string(required_field(candidate, "plan"), "source_events_sha256"),
    required_string(plan, "source_events_sha256"),
  )
  let session = engine.sessions.get("plan-approved-turn").unwrap()
  let first_seq = compaction_plan_field(plan, "source_first_seq")
  let last_seq = compaction_plan_field(plan, "source_last_seq")
  assert_true(session.events[first_seq].kind == EngineEventKind::TurnStarted)
  assert_true(session.events[last_seq].kind == EngineEventKind::TurnEnded)

  let mut calls = 0
  let mut approval_requests = 0
  let mut approval_resolutions = 0
  let mut tool_requests = 0
  let mut completions = 0
  let mut results = 0
  for event in session.events {
    if event.seq >= first_seq && event.seq <= last_seq {
      match event.kind {
        ToolCall => {
          calls += 1
          assert_eq(required_string(event.data, "id"), "approved-write")
        }
        ToolApprovalRequested => {
          approval_requests += 1
          assert_eq(required_string(event.data, "call_id"), "approved-write")
        }
        ToolApprovalResolved => {
          approval_resolutions += 1
          assert_eq(required_string(event.data, "call_id"), "approved-write")
        }
        ToolRequest => {
          tool_requests += 1
          assert_eq(required_string(event.data, "call_id"), "approved-write")
        }
        ToolCompleted => {
          completions += 1
          assert_eq(required_string(event.data, "call_id"), "approved-write")
        }
        ToolResult => {
          results += 1
          assert_eq(
            required_string(event.data, "tool_call_id"),
            "approved-write",
          )
        }
        _ => ()
      }
    }
  }
  assert_eq(calls, 1)
  assert_eq(approval_requests, 1)
  assert_eq(approval_resolutions, 1)
  assert_eq(tool_requests, 1)
  assert_eq(completions, 1)
  assert_eq(results, 1)
}
