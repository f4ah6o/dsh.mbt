///|
/// A bounded source range selected for a later compaction operation. Planning
/// never changes the session or starts a provider request.
const COMPACTION_PLAN_MAX_SOURCE_BYTES : Int32 = 1048576

///|
/// Maximum serialized summary string size accepted for an in-memory candidate.
const COMPACTION_CANDIDATE_MAX_SUMMARY_BYTES : Int32 = 1048576

///|
/// Select an oldest contiguous prefix of complete turns for a later summary.
/// The source event range and digest let a future transaction reject a stale
/// plan before it archives or replaces any history.
pub fn Engine::plan_compaction_prefix(
  self : Engine,
  session_id : SessionId,
  retain_recent_turns : Int32,
  max_source_event_json_utf8_bytes : Int32,
  max_source_messages_json_utf8_bytes : Int32,
) -> Result[Json?, String] {
  try {
    if retain_recent_turns < 1 || retain_recent_turns > 1000000 {
      raise Invalid("retain_recent_turns must be between 1 and 1000000")
    }
    if max_source_event_json_utf8_bytes < 1 ||
      max_source_event_json_utf8_bytes > COMPACTION_PLAN_MAX_SOURCE_BYTES {
      raise Invalid(
        "max_source_event_json_utf8_bytes must be between 1 and 1048576",
      )
    }
    if max_source_messages_json_utf8_bytes < 1 ||
      max_source_messages_json_utf8_bytes > COMPACTION_PLAN_MAX_SOURCE_BYTES {
      raise Invalid(
        "max_source_messages_json_utf8_bytes must be between 1 and 1048576",
      )
    }
    let session = self.lookup(session_id.as_string())
    if self.session_has_unsettled_archive_state(session) {
      raise Invalid("Compaction planning requires a settled closed session")
    }
    if self.session_is_fork_related(session) {
      raise Invalid(
        "Compaction planning does not support fork-related sessions",
      )
    }
    ignore(validate_compaction_summary_events(session))
    Ok(
      compaction_build_plan(
        session.id,
        session.events,
        retain_recent_turns,
        max_source_event_json_utf8_bytes,
        max_source_messages_json_utf8_bytes,
      ),
    )
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Bind supplied summary text to a current whole-turn prefix plan.
///
/// This method re-plans the session with the same selection inputs and compares
/// every plan field, including both source fingerprints. It returns an
/// in-memory candidate and does not persist, replace, or archive session history.
///
/// @param session_id - session the plan was made for.
/// @param plan - the earlier result from `plan_compaction_prefix`.
/// @param summary - caller-supplied summary text.
/// @param retain_recent_turns - recent whole turns the plan must retain.
/// @param max_source_event_json_utf8_bytes - source-event array byte budget.
/// @param max_source_messages_json_utf8_bytes - projected-message array byte budget.
/// @param max_summary_json_utf8_bytes - serialized JSON-string byte limit for the summary.
/// @returns an in-memory candidate, or an error when the plan is stale or the
///   summary exceeds its explicit limit.
pub fn Engine::prepare_compaction_summary_candidate(
  self : Engine,
  session_id : SessionId,
  plan : Json,
  summary : String,
  retain_recent_turns : Int32,
  max_source_event_json_utf8_bytes : Int32,
  max_source_messages_json_utf8_bytes : Int32,
  max_summary_json_utf8_bytes : Int32,
) -> Result[Json, String] {
  try {
    if max_summary_json_utf8_bytes < 1 ||
      max_summary_json_utf8_bytes > COMPACTION_CANDIDATE_MAX_SUMMARY_BYTES {
      raise Invalid("max_summary_json_utf8_bytes must be between 1 and 1048576")
    }
    if summary.is_empty() {
      raise Invalid("Compaction candidate summary must not be empty")
    }
    let summary_json = Json::string(summary)
    let summary_bytes = match
      provider_context_measure_json_bytes(summary_json) {
      Ok(value) => value
      Err(error) => raise Invalid(error)
    }
    if summary_bytes > max_summary_json_utf8_bytes {
      raise Invalid("Compaction candidate summary exceeds its byte limit")
    }
    let current_plan = match
      self.plan_compaction_prefix(
        session_id, retain_recent_turns, max_source_event_json_utf8_bytes, max_source_messages_json_utf8_bytes,
      ) {
      Ok(Some(value)) => value
      Ok(None) => raise Invalid("Compaction plan has no current prefix")
      Err(error) => raise Invalid(error)
    }
    if !compaction_prefix_plan_equal(plan, current_plan) {
      raise Invalid("Compaction plan is stale or belongs to another session")
    }
    Ok(
      object([
        ("schema", Json::string("dsh.compaction-summary-candidate-v1")),
        ("plan", detached(current_plan)),
        (
          "plan_options",
          object([
            ("retain_recent_turns", integer(retain_recent_turns)),
            (
              "max_source_event_json_utf8_bytes",
              integer(max_source_event_json_utf8_bytes),
            ),
            (
              "max_source_messages_json_utf8_bytes",
              integer(max_source_messages_json_utf8_bytes),
            ),
          ]),
        ),
        ("summary", summary_json),
        ("summary_json_utf8_bytes", integer(summary_bytes)),
        ("max_summary_json_utf8_bytes", integer(max_summary_json_utf8_bytes)),
        ("unit", Json::string("serialized_utf8_bytes")),
      ]),
    )
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Build the same plan from an exact event prefix. Restore calls this with the
/// events that existed before a summary event, so later pruning never changes
/// the historical digest it validates.
fn compaction_build_plan(
  session_id : String,
  events : Array[Event],
  retain_recent_turns : Int32,
  max_source_event_json_utf8_bytes : Int32,
  max_source_messages_json_utf8_bytes : Int32,
) -> Json? raise EngineError {
  let turns = compaction_completed_turn_ranges(events)
  let already_summarized_turns = compaction_summarized_turn_count(events)
  if already_summarized_turns > turns.length() {
    raise Invalid("Compaction summary spans exceed completed history")
  }
  if turns.length() - already_summarized_turns <= retain_recent_turns {
    return None
  }
  let (content_by_result, _) = tool_result_pruning_state_for_events(events)
  let mut selected_turn_count = 0
  let mut selected_last_turn = 0
  let mut selected_last_seq = 0
  let mut selected_event_item_bytes = 0
  let mut selected_event_item_count = 0
  let mut selected_message_item_bytes = 0
  let mut selected_message_count = 0
  let selected_messages : Array[Json] = []
  let selected_events : Array[Json] = []
  let end_turn_index = turns.length() - retain_recent_turns

  for turn_index = already_summarized_turns
      turn_index < end_turn_index
      turn_index = turn_index + 1 {
    let turn = turns[turn_index]
    let turn_messages : Array[Json] = []
    let turn_events : Array[Json] = []
    let mut turn_event_item_bytes = 0
    let mut turn_message_item_bytes = 0
    for seq = turn.start_seq; seq <= turn.end_seq; seq = seq + 1 {
      let event = events[seq]
      let event_json = event.json()
      turn_event_item_bytes += match
        provider_context_measure_json_bytes(event_json) {
        Ok(value) => value
        Err(error) => raise Invalid(error)
      }
      turn_events.push(event_json)
      match compaction_source_message(event, content_by_result) {
        Some(message) => {
          turn_message_item_bytes += match
            provider_context_measure_json_bytes(message) {
            Ok(value) => value
            Err(error) => raise Invalid(error)
          }
          turn_messages.push(message)
        }
        None => ()
      }
    }
    let candidate_event_item_count = selected_event_item_count +
      turn_events.length()
    let candidate_event_item_bytes = selected_event_item_bytes +
      turn_event_item_bytes
    let event_bytes = 2 +
      candidate_event_item_bytes +
      (if candidate_event_item_count > 0 {
        candidate_event_item_count - 1
      } else {
        0
      })
    let candidate_message_count = selected_message_count +
      turn_messages.length()
    let candidate_message_item_bytes = selected_message_item_bytes +
      turn_message_item_bytes
    let message_bytes = 2 +
      candidate_message_item_bytes +
      (if candidate_message_count > 0 {
        candidate_message_count - 1
      } else {
        0
      })
    if event_bytes > max_source_event_json_utf8_bytes ||
      message_bytes > max_source_messages_json_utf8_bytes {
      break
    }
    selected_turn_count += 1
    selected_last_turn = turn.turn_id
    selected_last_seq = turn.end_seq
    selected_event_item_count = candidate_event_item_count
    selected_event_item_bytes = candidate_event_item_bytes
    selected_message_count = candidate_message_count
    selected_message_item_bytes = candidate_message_item_bytes
    for event in turn_events {
      selected_events.push(event)
    }
    for message in turn_messages {
      selected_messages.push(message)
    }
  }

  if selected_turn_count == 0 {
    return None
  }
  let source_first_seq = turns[already_summarized_turns].start_seq
  let source_event_bytes = 2 +
    selected_event_item_bytes +
    (if selected_event_item_count > 0 {
      selected_event_item_count - 1
    } else {
      0
    })
  let source_message_bytes = 2 +
    selected_message_item_bytes +
    (if selected_message_count > 0 { selected_message_count - 1 } else { 0 })
  let source_events_json = Json::array(selected_events)
  let source_digest = archive_sha256(source_events_json.stringify())
  let source_messages_json = Json::array(selected_messages)
  let source_messages_digest = archive_sha256(source_messages_json.stringify())
  let source_event_count = selected_last_seq - source_first_seq + 1
  let retained_turn_count = turns.length() -
    already_summarized_turns -
    selected_turn_count
  Some(
    object([
      ("session_id", Json::string(session_id)),
      ("expected_event_count", integer(events.length())),
      ("source_first_seq", integer(source_first_seq)),
      ("source_last_seq", integer(selected_last_seq)),
      ("source_first_turn", integer(turns[already_summarized_turns].turn_id)),
      ("source_last_turn", integer(selected_last_turn)),
      ("source_turn_count", integer(selected_turn_count)),
      ("retained_turn_count", integer(retained_turn_count)),
      ("source_event_count", integer(source_event_count)),
      ("source_event_json_utf8_bytes", integer(source_event_bytes)),
      ("source_message_count", integer(selected_messages.length())),
      ("source_messages_json_utf8_bytes", integer(source_message_bytes)),
      ("source_events_sha256", Json::string(source_digest)),
      ("source_messages_sha256", Json::string(source_messages_digest)),
      ("unit", Json::string("serialized_utf8_bytes")),
    ]),
  )
}

///|
fn compaction_summarized_turn_count(
  events : Array[Event],
) -> Int32 raise EngineError {
  let mut result = 0
  for event in events {
    if event.kind != EngineEventKind::CompactionSummary {
      continue
    }
    let plan = required_field(event.data, "plan")
    result += int_value(
      required_field(plan, "source_turn_count"),
      "source_turn_count",
      1,
      1000000,
    )
  }
  result
}

///|
fn compaction_event_prefix(
  events : Array[Event],
  count : Int32,
) -> Array[Event] {
  let result : Array[Event] = []
  for index = 0; index < count; index = index + 1 {
    result.push(events[index])
  }
  result
}

///|
/// Validate each summary at its historical append point. The source range is
/// re-planned from exactly the prefix before that event, including then-current
/// pruning projection and earlier non-overlapping summary spans.
fn validate_compaction_summary_events(
  session : Session,
) -> Unit raise EngineError {
  let record_fields = [
    "schema", "plan", "plan_options", "summary", "summary_json_utf8_bytes", "max_summary_json_utf8_bytes",
    "origin", "context_role",
  ]
  if session.events.any(event => {
      event.kind == EngineEventKind::CompactionSummary
    }) &&
    session_has_archived_tool_results(session) {
    raise Invalid(
      "Compaction summaries cannot coexist with archived tool results",
    )
  }
  let option_fields = [
    "retain_recent_turns", "max_source_event_json_utf8_bytes", "max_source_messages_json_utf8_bytes",
  ]
  for index = 0; index < session.events.length(); index = index + 1 {
    let event = session.events[index]
    if event.kind != EngineEventKind::CompactionSummary {
      continue
    }
    if event.seq != index || session.imported || session.fork_source is Some(_) {
      raise Invalid("Compaction summary is outside a native source history")
    }
    if session.status != Idle && session.status != Completed {
      // A live later turn may follow a valid summary. The event itself must
      // still have been appended at a settled boundary, proven by its prefix.
      ()
    }
    let data = fields(event.data)
    if data.length() != record_fields.length() {
      raise Invalid("Compaction summary record has missing or unknown fields")
    }
    for key, _ in data {
      if !record_fields.contains(key) {
        raise Invalid("Compaction summary record has missing or unknown fields")
      }
    }
    if required_string(event.data, "schema", max=64) !=
      "dsh.compaction-summary-record-v1" ||
      required_string(event.data, "origin", max=32) != "caller-supplied" ||
      required_string(event.data, "context_role", max=16) != "assistant" {
      raise Invalid("Compaction summary provenance is invalid")
    }
    let summary = required_string(event.data, "summary", max=1048576)
    if summary.is_empty() {
      raise Invalid("Compaction summary is empty")
    }
    let summary_limit = int_value(
      required_field(event.data, "max_summary_json_utf8_bytes"),
      "max_summary_json_utf8_bytes",
      1,
      COMPACTION_CANDIDATE_MAX_SUMMARY_BYTES,
    )
    let summary_bytes = match
      provider_context_measure_json_bytes(Json::string(summary)) {
      Ok(value) => value
      Err(error) => raise Invalid(error)
    }
    if int_value(
        required_field(event.data, "summary_json_utf8_bytes"),
        "summary_json_utf8_bytes",
        1,
        COMPACTION_CANDIDATE_MAX_SUMMARY_BYTES,
      ) !=
      summary_bytes ||
      summary_bytes > summary_limit {
      raise Invalid("Compaction summary byte metadata is invalid")
    }
    let options = required_field(event.data, "plan_options")
    let options_map = fields(options)
    if options_map.length() != option_fields.length() {
      raise Invalid("Compaction summary options have missing or unknown fields")
    }
    for key, _ in options_map {
      if !option_fields.contains(key) {
        raise Invalid(
          "Compaction summary options have missing or unknown fields",
        )
      }
    }
    let retain = int_value(
      required_field(options, "retain_recent_turns"),
      "retain_recent_turns",
      1,
      1000000,
    )
    let event_budget = int_value(
      required_field(options, "max_source_event_json_utf8_bytes"),
      "max_source_event_json_utf8_bytes",
      1,
      COMPACTION_PLAN_MAX_SOURCE_BYTES,
    )
    let message_budget = int_value(
      required_field(options, "max_source_messages_json_utf8_bytes"),
      "max_source_messages_json_utf8_bytes",
      1,
      COMPACTION_PLAN_MAX_SOURCE_BYTES,
    )
    let prior_events = compaction_event_prefix(session.events, index)
    let expected_plan = compaction_build_plan(
      session.id,
      prior_events,
      retain,
      event_budget,
      message_budget,
    )
    match (expected_plan, fields(event.data).get("plan")) {
      (Some(expected), Some(actual)) if compaction_prefix_plan_equal(
          actual, expected,
        ) => ()
      _ =>
        raise Invalid("Compaction summary plan differs from its source prefix")
    }
    if compaction_summarized_turn_count(prior_events) >
      compaction_completed_turn_ranges(prior_events).length() {
      raise Invalid("Compaction summary spans overlap or exceed history")
    }
  }
}

///|
fn Engine::record_compaction_summary(
  self : Engine,
  session_id : SessionId,
  plan : Json,
  summary : String,
  retain_recent_turns : Int32,
  max_source_event_json_utf8_bytes : Int32,
  max_source_messages_json_utf8_bytes : Int32,
  max_summary_json_utf8_bytes : Int32,
) -> Json raise EngineError {
  let session = self.lookup(session_id.as_string())
  if session_has_archived_tool_results(session) {
    raise Invalid(
      "Cannot apply a summary to history with archived tool results",
    )
  }
  let candidate = match
    self.prepare_compaction_summary_candidate(
      session_id, plan, summary, retain_recent_turns, max_source_event_json_utf8_bytes,
      max_source_messages_json_utf8_bytes, max_summary_json_utf8_bytes,
    ) {
    Ok(value) => value
    Err(error) => raise Invalid(error)
  }
  if session.events.length() >= 32768 {
    raise Invalid("Session event limit reached; create a new session")
  }
  session.append(
    "compaction/summary",
    object([
      ("schema", Json::string("dsh.compaction-summary-record-v1")),
      ("plan", detached(required_field(candidate, "plan"))),
      ("plan_options", detached(required_field(candidate, "plan_options"))),
      ("summary", detached(required_field(candidate, "summary"))),
      (
        "summary_json_utf8_bytes",
        detached(required_field(candidate, "summary_json_utf8_bytes")),
      ),
      (
        "max_summary_json_utf8_bytes",
        detached(required_field(candidate, "max_summary_json_utf8_bytes")),
      ),
      ("origin", Json::string("caller-supplied")),
      ("context_role", Json::string("assistant")),
    ]),
  )
  ignore(validate_compaction_summary_events(session))
  ignore(self)
  session.json()
}

///|
/// Compare every field emitted by the current prefix planner.
fn compaction_prefix_plan_equal(left : Json, right : Json) -> Bool {
  let keys = [
    "session_id", "expected_event_count", "source_first_seq", "source_last_seq",
    "source_first_turn", "source_last_turn", "source_turn_count", "retained_turn_count",
    "source_event_count", "source_event_json_utf8_bytes", "source_message_count",
    "source_messages_json_utf8_bytes", "source_events_sha256", "source_messages_sha256",
    "unit",
  ]
  match (left, right) {
    (Json::Object(left_fields), Json::Object(right_fields)) => {
      if left_fields.length() != keys.length() ||
        right_fields.length() != keys.length() {
        return false
      }
      for key in keys {
        if left_fields.get(key) != right_fields.get(key) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Collect the source-message projection for one event without exposing the
/// event log or changing the session.
fn compaction_source_message(
  event : Event,
  content_by_result : Map[Int32, String],
) -> Json? {
  match event.kind {
    UserMessage => Some(detached(event.data))
    ToolResult => Some(projected_tool_result(event, content_by_result))
    AssistantMessage =>
      match event.data {
        Json::Object(data) => data.get("message").map(detached)
        _ => None
      }
    _ => None
  }
}

///|
/// A completed turn and the contiguous event range that belongs to it.
priv struct CompactionTurnRange {
  turn_id : Int32
  start_seq : Int32
  end_seq : Int32
}

///|
fn compaction_completed_turn_ranges(
  events : Array[Event],
) -> Array[CompactionTurnRange] raise EngineError {
  let ranges : Array[CompactionTurnRange] = []
  let mut active_turn : Int32? = None
  let mut active_start = 0
  for event in events {
    if event.kind == TurnStarted {
      if active_turn is Some(_) {
        raise Invalid("Compaction planning found overlapping turns")
      }
      active_turn = Some(event.turn_id)
      active_start = event.seq
    } else if event.kind == TurnEnded {
      if active_turn != Some(event.turn_id) {
        raise Invalid("Compaction planning found an unmatched turn end")
      }
      ranges.push({
        turn_id: event.turn_id,
        start_seq: active_start,
        end_seq: event.seq,
      })
      active_turn = None
    }
  }
  if active_turn is Some(_) {
    raise Invalid("Compaction planning requires every turn to be closed")
  }
  for index = 0; index < ranges.length(); index = index + 1 {
    let end_seq = if index + 1 < ranges.length() {
      ranges[index + 1].start_seq - 1
    } else {
      events.length() - 1
    }
    ranges[index] = {
      turn_id: ranges[index].turn_id,
      start_seq: ranges[index].start_seq,
      end_seq,
    }
  }
  ranges
}
