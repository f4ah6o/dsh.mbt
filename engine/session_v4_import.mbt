///|
/// archives are admitted; no provider or tool effect is created by this path.
fn Engine::import_upstream_v4(
  self : Engine,
  jsonl : String,
) -> Session raise EngineError {
  if self.order.length() >= 32 {
    raise Invalid("Session count limit reached")
  }
  let lines = v4_lines(jsonl)
  if lines.length() < 1 {
    raise Invalid("Session v4 JSONL is empty")
  }
  if lines.length() > 32767 {
    raise Invalid("Session v4 JSONL exceeds the 32766 event limit")
  }
  let header = v4_parse_line(lines[0], 1)
  validate_v4_header(header)
  let source_id = required_string(header, "id", max=128)
  let mut next = self.next_session
  while self.sessions.get("session-\{next}") is Some(_) {
    next += 1
  }
  if next >= 1000000000 {
    raise Invalid("Session identifier limit reached")
  }
  let id = "session-\{next}"
  let mut title = "Imported " + source_id
  let replay : V4Replay = {
    turn: 0,
    step: 0,
    status: Idle,
    open_turn: false,
    open_step: false,
    seeded: bool_value(required_field(header, "isSeeded"), "isSeeded"),
    title,
    seed_marker: None,
    fork_closing: false,
    request_header: None,
    request_context_seen: false,
    admitted_prompt: false,
    assistant_seen: false,
    terminal_step_without_assistant: false,
    source_types: Map([]),
    user_messages: Map([]),
    message_ids: Map([]),
    calls: Map([]),
    call_order: [],
    inbox: {
      next_turn: [],
      next_step: [],
      claimed_turn: [],
      claimed_step: [],
      used_ids: Map([]),
    },
  }
  let records : Array[Json] = []
  let physical = if lines.length() > 1 {
    has_v4_physical_envelope(v4_parse_line(lines[1], 2))
  } else {
    true
  }
  for index in 1..<lines.length() {
    let line_number = index + 1
    let record = v4_parse_line(lines[index], line_number)
    validate_v4_event_envelope(record, index - 1, physical, line_number)
    let kind = required_string(record, "type", max=128)
    validate_v4_references(record, index - 1, replay.source_types)
    let coordinates = replay_v4_event(replay, record, index - 1, line_number)
    let event_turn = coordinates.0
    let event_step = coordinates.1
    if kind == "session/title" {
      replay.title = required_string(
        required_field(record, "data"),
        "title",
        max=512,
      )
    }
    records.push({
      "source_seq": integer(index - 1),
      "turn_id": integer(event_turn),
      "step": integer(event_step),
      "record": record,
      "raw": lines[index],
    })
    replay.source_types[index - 1] = kind
  }
  validate_v4_replay_end(replay, header)
  title = replay.title
  let session = fresh_session(id, title, "", 64)
  session.imported = true
  session.append(
    "session/created",
    object([
      ("id", Json::string(id)),
      ("title", Json::string(title)),
      ("system_prompt", Json::string("")),
      ("max_steps", integer(64)),
    ]),
  )
  session.append("upstream/header", {
    "source_seq": 0,
    "record": header,
    "raw": lines[0],
  })
  // Rewrite the importer event envelopes with their replay-derived coordinates.
  for wrapped in records {
    session.turn_id = int_value(
      required_field(wrapped, "turn_id"),
      "turn_id",
      0,
      1000000,
    )
    session.step = int_value(required_field(wrapped, "step"), "step", 0, 64)
    session.append("upstream/event", wrapped)
  }
  // Source rows carry their own replay-derived coordinates. Creation and
  // header records remain at the local session's initial 0/0 boundary.
  session.turn_id = replay.turn
  session.step = replay.step
  session.status = replay.status
  if self.sessions.get(id) is Some(_) {
    raise Invalid("Session already exists: \{id}")
  }
  if session.json().stringify().length() > SESSION_CAPACITY {
    raise Invalid(
      "Imported Session v4 exceeds the 262144-character session capacity",
    )
  }
  self.next_session = next + 1
  self.sessions.set(id, session)
  self.order.push(id)
  session
}
