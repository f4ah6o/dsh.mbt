///|
fn restore_imported_session(value : Json) -> Session raise EngineError {
  if value.stringify().length() > SESSION_CAPACITY {
    raise Invalid("Snapshot session exceeds the 262144-character capacity")
  }
  for key, _ in fields(value) {
    if key != "id" &&
      key != "title" &&
      key != "system_prompt" &&
      key != "max_steps" &&
      key != "status" &&
      key != "turn_id" &&
      key != "step" &&
      key != "events" &&
      key != "messages" &&
      key != "source_format" &&
      key != "pending_tool_calls" &&
      key != "pending_inbox" {
      raise Invalid("Unexpected imported Session v4 snapshot field: {key}")
    }
  }
  let id = identifier(required_string(value, "id", max=128), "session id")
  let title = required_string(value, "title", max=512)
  if required_string(value, "system_prompt", max=16384) != "" ||
    int_value(required_field(value, "max_steps"), "max_steps", 1, 64) != 64 {
    raise Invalid("Imported Session v4 snapshot metadata is invalid")
  }
  let expected_status = required_string(value, "status", max=32)
  let expected_turn = int_value(
    required_field(value, "turn_id"),
    "turn_id",
    0,
    1000000,
  )
  let expected_step = int_value(required_field(value, "step"), "step", 0, 64)
  let raw_events = array_value(required_field(value, "events"), "events", 32768)
  if raw_events.length() < 2 {
    raise Invalid("Imported Session v4 snapshot has no source archive")
  }
  let created = raw_events[0]
  let expected_creation = object([
    ("seq", integer(0)),
    ("type", Json::string("session/created")),
    ("turn_id", integer(0)),
    ("step", integer(0)),
    (
      "data",
      object([
        ("id", Json::string(id)),
        ("title", Json::string(title)),
        ("system_prompt", Json::string("")),
        ("max_steps", integer(64)),
      ]),
    ),
  ])
  if created != expected_creation {
    raise Invalid("Imported Session v4 local creation event is not canonical")
  }
  let source_lines : Array[String] = []
  for index in 1..<raw_events.length() {
    let event = raw_events[index]
    let kind = required_string(event, "type", max=64)
    let data = required_field(event, "data")
    let expected_kind = if index == 1 {
      "upstream/header"
    } else {
      "upstream/event"
    }
    if kind != expected_kind {
      raise Invalid(
        "Imported Session v4 snapshot source rows are reordered or missing",
      )
    }
    let source_seq = int_value(
      required_field(data, "source_seq"),
      "source_seq",
      0,
      32767,
    )
    let expected_seq = if index == 1 { 0 } else { index - 2 }
    if source_seq != expected_seq {
      raise Invalid("Imported Session v4 source sequence is not contiguous")
    }
    source_lines.push(required_string(data, "raw", max=SESSION_CAPACITY))
  }
  let mut jsonl = ""
  for index, line in source_lines {
    if index > 0 {
      jsonl += "\n"
    }
    jsonl += line
  }
  let replayed = Engine::new([]).import_upstream_v4(jsonl)
  if replayed.title != title ||
    status_text(replayed.status) != expected_status ||
    replayed.turn_id != expected_turn ||
    replayed.step != expected_step {
    raise Invalid(
      "Imported Session v4 snapshot state disagrees with its source archive",
    )
  }
  if raw_events.length() != replayed.events.length() {
    raise Invalid(
      "Imported Session v4 snapshot source rows disagree with the archive",
    )
  }
  for index in 1..<raw_events.length() {
    if raw_events[index] != replayed.events[index].json() {
      raise Invalid(
        "Imported Session v4 source envelope or replay coordinates were modified",
      )
    }
  }
  if required_field(value, "messages") != Json::array(replayed.messages()) {
    raise Invalid(
      "Imported Session v4 message projection disagrees with the source archive",
    )
  }
  let replayed_json = replayed.json()
  if required_field(value, "pending_tool_calls") !=
    required_field(replayed_json, "pending_tool_calls") ||
    required_field(value, "pending_inbox") !=
    required_field(replayed_json, "pending_inbox") {
    raise Invalid(
      "Imported Session v4 pending state disagrees with the source archive",
    )
  }
  let restored = fresh_session(id, title, "", 64)
  restored.imported = true
  restored.append(
    "session/created",
    object([
      ("id", Json::string(id)),
      ("title", Json::string(title)),
      ("system_prompt", Json::string("")),
      ("max_steps", integer(64)),
    ]),
  )
  for index in 1..<replayed.events.length() {
    let event = replayed.events[index]
    restored.turn_id = event.turn_id
    restored.step = event.step
    restored.append(event.kind, detached(event.data))
  }
  restored.turn_id = replayed.turn_id
  restored.step = replayed.step
  restored.status = replayed.status
  restored
}
