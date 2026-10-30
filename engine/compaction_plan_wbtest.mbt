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
fn compaction_summary_commit(
  engine : Engine,
  session_id : String,
  plan : Json,
  summary : String,
  retain_recent_turns~ : Int32 = 1,
) -> Json {
  success(
    engine.invoke(
      "session_compact_summary",
      object([
        ("session_id", Json::string(session_id)),
        ("plan", plan),
        ("summary", Json::string(summary)),
        ("retain_recent_turns", integer(retain_recent_turns)),
        ("max_source_event_json_utf8_bytes", integer(1048576)),
        ("max_source_messages_json_utf8_bytes", integer(1048576)),
        ("max_summary_json_utf8_bytes", integer(1048576)),
      ]),
    ),
  )
}

///|
fn compaction_summary_snapshot_event(snapshot : Json) -> Json raise EngineError {
  let session = array_value(
      required_field(snapshot, "sessions"),
      "sessions",
      32,
    )[0]
  let events = array_value(required_field(session, "events"), "events", 32768)
  for event in events {
    if required_string(event, "type") == "compaction/summary" {
      return event
    }
  }
  abort("Compaction summary event is missing from snapshot")
}

///|
fn compaction_summary_restore_rejects_atomically(snapshot : Json) -> Bool {
  let pristine = Engine::new([])
  let before = pristine.snapshot()
  let restore_failed = pristine.restore(snapshot) is Err(_)
  restore_failed &&
  pristine.snapshot() == before &&
  pristine.take_effects().is_empty()
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
  let original_events = session.events.copy()
  let original_messages = session.messages()
  ignore(
    success(
      engine.invoke("session_compact_summary", {
        "session_id": "plan-approved-turn",
        "plan": plan,
        "summary": "The user approved the write and the correlated tool call completed.",
        "retain_recent_turns": 1,
        "max_source_event_json_utf8_bytes": 1048576,
        "max_source_messages_json_utf8_bytes": 1048576,
        "max_summary_json_utf8_bytes": 1048576,
      }),
    ),
  )
  let compacted = engine.sessions.get("plan-approved-turn").unwrap()
  assert_eq(compacted.messages(), original_messages)
  for seq = 0; seq < original_events.length(); seq = seq + 1 {
    assert_eq(compacted.events[seq].json(), original_events[seq].json())
  }
  assert_eq(compacted.model_messages().length(), 3)
  assert_true(engine.take_effects().is_empty())
  let reopened = Engine::new(test_tools())
  assert_eq(reopened.restore(engine.snapshot()), Ok(()))
  assert_true(reopened.take_effects().is_empty())
}

///|
test "committed compaction summary is durable assistant context and preserves original history" {
  let engine = Engine::new([])
  ignore(
    success(
      engine.invoke(
        "session_create",
        object([("id", Json::string("summary-commit"))]),
      ),
    ),
  )
  compaction_plan_complete_turn(
    engine, "summary-commit", "old one", "answer one",
  )
  compaction_plan_complete_turn(
    engine, "summary-commit", "old two", "answer two",
  )
  compaction_plan_complete_turn(
    engine, "summary-commit", "recent one", "answer three",
  )

  let first_plan = compaction_plan_required(
    engine, "summary-commit", 1, 1048576, 1048576,
  )
  let first_start = compaction_plan_field(first_plan, "source_first_seq")
  let first_end = compaction_plan_field(first_plan, "source_last_seq")
  let session_before = engine.sessions.get("summary-commit").unwrap()
  let original_events = session_before.events.copy()
  let original_messages = session_before.messages()
  let original_effects = engine.take_effects()
  assert_true(original_effects.is_empty())
  let commit = engine
    .invoke(
      "session_compact_summary",
      object([
        ("session_id", Json::string("summary-commit")),
        ("plan", first_plan),
        (
          "summary",
          Json::string("The first two turns chose the safe approach."),
        ),
        ("retain_recent_turns", integer(1)),
        ("max_source_event_json_utf8_bytes", integer(1048576)),
        ("max_source_messages_json_utf8_bytes", integer(1048576)),
        ("max_summary_json_utf8_bytes", integer(1048576)),
      ]),
    )
    .unwrap()
  let session = engine.sessions.get("summary-commit").unwrap()
  assert_eq(session.events.length(), original_events.length() + 1)
  for seq = 0; seq < original_events.length(); seq = seq + 1 {
    assert_eq(session.events[seq].json(), original_events[seq].json())
  }
  assert_eq(session.messages(), original_messages)
  assert_true(engine.take_effects().is_empty())
  assert_eq(
    required_string(session.events[original_events.length()].json(), "type"),
    "compaction/summary",
  )
  assert_eq(
    required_string(session.events[original_events.length()].data, "origin"),
    "caller-supplied",
  )
  assert_eq(
    required_string(
      session.events[original_events.length()].data,
      "context_role",
    ),
    "assistant",
  )
  assert_eq(commit, session.json())

  let projected = session.model_messages()
  assert_eq(projected.length(), 3)
  assert_eq(required_string(projected[0], "role"), "assistant")
  let summary_context = required_string(projected[0], "content")
  assert_true(summary_context.contains("Caller-supplied historical summary"))
  assert_true(
    summary_context.contains("The first two turns chose the safe approach."),
  )
  assert_true(fields(projected[0]).get("tool_calls") is None)
  assert_true(fields(projected[0]).get("reasoning") is None)
  assert_eq(required_string(projected[1], "content"), "recent one")
  assert_eq(required_string(projected[2], "content"), "answer three")
  assert_true(first_end - first_start + 1 > 0)

  let snapshot = engine.snapshot()
  let reopened = Engine::new([])
  assert_eq(reopened.restore(snapshot), Ok(()))
  assert_true(reopened.take_effects().is_empty())
  assert_eq(reopened.lookup("summary-commit").model_messages(), projected)
  assert_eq(reopened.lookup("summary-commit").messages(), original_messages)

  compaction_plan_complete_turn(
    reopened, "summary-commit", "recent two", "answer four",
  )
  let second_plan = compaction_plan_required(
    reopened, "summary-commit", 1, 1048576, 1048576,
  )
  assert_eq(compaction_plan_field(second_plan, "source_first_turn"), 3)
  assert_eq(compaction_plan_field(second_plan, "source_turn_count"), 1)
  assert_true(
    compaction_plan_field(second_plan, "source_first_seq") >
    compaction_plan_field(first_plan, "source_last_seq"),
  )
  ignore(
    success(
      reopened.invoke(
        "session_compact_summary",
        object([
          ("session_id", Json::string("summary-commit")),
          ("plan", second_plan),
          ("summary", Json::string("The third turn completed the follow-up.")),
          ("retain_recent_turns", integer(1)),
          ("max_source_event_json_utf8_bytes", integer(1048576)),
          ("max_source_messages_json_utf8_bytes", integer(1048576)),
          ("max_summary_json_utf8_bytes", integer(1048576)),
        ]),
      ),
    ),
  )
  let second_projection = reopened.lookup("summary-commit").model_messages()
  assert_eq(second_projection.length(), 4)
  assert_true(
    required_string(second_projection[0], "content").contains(
      "The first two turns chose the safe approach.",
    ),
  )
  assert_true(
    required_string(second_projection[1], "content").contains(
      "The third turn completed the follow-up.",
    ),
  )
  assert_eq(required_string(second_projection[2], "content"), "recent two")
  assert_eq(required_string(second_projection[3], "content"), "answer four")
  assert_true(reopened.take_effects().is_empty())
  let reopened_twice = Engine::new([])
  assert_eq(reopened_twice.restore(reopened.snapshot()), Ok(()))
  assert_eq(
    reopened_twice.lookup("summary-commit").model_messages(),
    second_projection,
  )
  assert_true(reopened_twice.take_effects().is_empty())
  let before_fork = reopened_twice.snapshot()
  assert_true(
    reopened_twice.invoke("session_fork", {
      "session_id": "summary-commit",
      "id": "summary-fork",
    })
    is Err(_),
  )
  assert_eq(reopened_twice.snapshot(), before_fork)
  assert_true(reopened_twice.take_effects().is_empty())
}

///|
test "summary restore rejects changed fingerprints provenance ranges and byte metadata atomically" {
  let engine = Engine::new([])
  ignore(success(engine.invoke("session_create", { "id": "summary-tamper" })))
  compaction_plan_complete_turn(
    engine, "summary-tamper", "old one", "answer one",
  )
  compaction_plan_complete_turn(
    engine, "summary-tamper", "old two", "answer two",
  )
  compaction_plan_complete_turn(
    engine, "summary-tamper", "recent", "answer three",
  )
  let plan = compaction_plan_required(
    engine, "summary-tamper", 1, 1048576, 1048576,
  )
  ignore(
    compaction_summary_commit(
      engine, "summary-tamper", plan, "A caller-supplied summary with enough bytes.",
    ),
  )
  let saved = engine.snapshot()

  // Each forgery is independently rejected. A failed restore leaves the
  // target engine byte-for-byte unchanged and never creates host effects.
  for mutation = 0; mutation < 10; mutation = mutation + 1 {
    let corrupted = json_copy(saved)
    let summary_event = compaction_summary_snapshot_event(corrupted)
    let data = required_field(summary_event, "data")
    let plan_fields = fields(required_field(data, "plan"))
    match mutation {
      0 => plan_fields.set("source_events_sha256", Json::string("0".repeat(64)))
      1 =>
        plan_fields.set("source_messages_sha256", Json::string("0".repeat(64)))
      2 => fields(data).set("origin", Json::string("model-generated"))
      3 => fields(data).set("context_role", Json::string("system"))
      4 => fields(data).set("summary", Json::string("tampered summary body"))
      5 =>
        fields(data).set(
          "summary_json_utf8_bytes",
          integer(compaction_plan_field(data, "summary_json_utf8_bytes") + 1),
        )
      6 => fields(data).set("max_summary_json_utf8_bytes", integer(1))
      7 =>
        fields(data).set(
          "plan_options",
          compaction_plan_replace_field(
            required_field(data, "plan_options"),
            "retain_recent_turns",
            integer(2),
          ),
        )
      8 =>
        plan_fields.set(
          "source_first_seq",
          integer(
            compaction_plan_field(
              required_field(data, "plan"),
              "source_first_seq",
            ) +
            1,
          ),
        )
      9 =>
        plan_fields.set(
          "source_last_seq",
          integer(
            compaction_plan_field(
              required_field(data, "plan"),
              "source_last_seq",
            ) +
            1,
          ),
        )
      _ => ()
    }
    assert_true(compaction_summary_restore_rejects_atomically(corrupted))
  }
}

///|
test "summary commit refuses stale plans, active work, and session-capacity overflow atomically" {
  let engine = Engine::new([])
  ignore(success(engine.invoke("session_create", { "id": "summary-fail" })))
  compaction_plan_complete_turn(engine, "summary-fail", "old", "answer")
  compaction_plan_complete_turn(engine, "summary-fail", "recent", "answer")
  let stale = compaction_plan_required(
    engine, "summary-fail", 1, 1048576, 1048576,
  )
  compaction_plan_complete_turn(engine, "summary-fail", "newer", "answer")
  let before_stale = engine.snapshot()
  assert_true(
    engine.invoke("session_compact_summary", {
      "session_id": "summary-fail",
      "plan": stale,
      "summary": "stale",
      "retain_recent_turns": 1,
      "max_source_event_json_utf8_bytes": 1048576,
      "max_source_messages_json_utf8_bytes": 1048576,
      "max_summary_json_utf8_bytes": 1048576,
    })
    is Err(_),
  )
  assert_eq(engine.snapshot(), before_stale)
  assert_true(engine.take_effects().is_empty())

  let current = compaction_plan_required(
    engine, "summary-fail", 1, 1048576, 1048576,
  )
  let busy = engine.invoke("session_send", {
    "session_id": "summary-fail",
    "prompt": "continue",
  })
  ignore(success(busy))
  let live_effects = engine.take_effects()
  assert_eq(live_effects.length(), 1)
  let before_busy = engine.snapshot()
  assert_true(
    engine.invoke("session_compact_summary", {
      "session_id": "summary-fail",
      "plan": current,
      "summary": "must refuse a live session",
      "retain_recent_turns": 1,
      "max_source_event_json_utf8_bytes": 1048576,
      "max_source_messages_json_utf8_bytes": 1048576,
      "max_summary_json_utf8_bytes": 1048576,
    })
    is Err(_),
  )
  assert_eq(engine.snapshot(), before_busy)
  assert_true(engine.take_effects().is_empty())
  ignore(
    success(engine.invoke("session_cancel", { "session_id": "summary-fail" })),
  )
  let cancelled_snapshot = engine.snapshot()
  let reopened = Engine::new([])
  assert_eq(reopened.restore(cancelled_snapshot), Ok(()))
  assert_true(reopened.take_effects().is_empty())
  assert_true(
    reopened.plan_compaction_prefix(
      SessionId::from_validated("summary-fail"),
      1,
      1048576,
      1048576,
    )
    is Err(_),
  )

  let capacity = Engine::new([])
  ignore(success(capacity.invoke("session_create", { "id": "summary-cap" })))
  compaction_plan_complete_turn(capacity, "summary-cap", "old", "answer")
  compaction_plan_complete_turn(capacity, "summary-cap", "recent", "answer")
  let capacity_session = capacity.sessions.get("summary-cap").unwrap()
  while capacity_session.events.length() < 32768 {
    capacity_session.append("hook/invoked", Json::object(Map([])))
  }
  let capacity_plan = compaction_plan_required(
    capacity, "summary-cap", 1, 1048576, 1048576,
  )
  let before_capacity = capacity.snapshot()
  let before_capacity_effects = capacity.take_effects()
  assert_true(before_capacity_effects.is_empty())
  assert_true(
    capacity.invoke("session_compact_summary", {
      "session_id": "summary-cap",
      "plan": capacity_plan,
      "summary": "The event quota is already full.",
      "retain_recent_turns": 1,
      "max_source_event_json_utf8_bytes": 1048576,
      "max_source_messages_json_utf8_bytes": 1048576,
      "max_summary_json_utf8_bytes": 1048576,
    })
    is Err(_),
  )
  assert_eq(capacity.snapshot(), before_capacity)
  assert_true(capacity.take_effects().is_empty())

  let serialized_capacity = Engine::new([])
  ignore(
    success(
      serialized_capacity.invoke("session_create", { "id": "summary-bytes-cap" }),
    ),
  )
  compaction_plan_complete_turn(
    serialized_capacity, "summary-bytes-cap", "old", "answer",
  )
  compaction_plan_complete_turn(
    serialized_capacity, "summary-bytes-cap", "recent", "answer",
  )
  let serialized_plan = compaction_plan_required(
    serialized_capacity, "summary-bytes-cap", 1, 1048576, 1048576,
  )
  let near_capacity_summary = "x".repeat(262000)
  assert_true(
    provider_context_measure_json_bytes(Json::string(near_capacity_summary)).unwrap() <
    1048576,
  )
  let before_serialized_capacity = serialized_capacity.snapshot()
  assert_true(
    serialized_capacity.invoke("session_compact_summary", {
      "session_id": "summary-bytes-cap",
      "plan": serialized_plan,
      "summary": near_capacity_summary,
      "retain_recent_turns": 1,
      "max_source_event_json_utf8_bytes": 1048576,
      "max_source_messages_json_utf8_bytes": 1048576,
      "max_summary_json_utf8_bytes": 1048576,
    })
    is Err(_),
  )
  assert_eq(serialized_capacity.snapshot(), before_serialized_capacity)
  assert_true(serialized_capacity.take_effects().is_empty())
}
