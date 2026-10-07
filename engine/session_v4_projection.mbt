///|
fn project_v4_content(
  value : Json,
  allow_tool_calls : Bool,
  allow_tool_changes : Bool,
  line_number : Int,
) -> ProjectedContent raise EngineError {
  let output : ProjectedContent = {
    text: "",
    reasoning: "",
    calls: [],
    changes: [],
  }
  match value {
    Json::String(_) =>
      raise Invalid("Session v4 native message content must be a block array")
    Json::Array(blocks) =>
      for block in blocks {
        let kind = required_string(block, "type", max=64)
        match kind {
          "text" => output.text += required_string(block, "text")
          "reasoning" => output.reasoning += required_string(block, "text")
          "tool-call" if allow_tool_calls =>
            output.calls.push(
              object([
                ("id", Json::string(required_string(block, "id", max=128))),
                ("name", Json::string(required_string(block, "name", max=128))),
                ("arguments", Json::string(required_string(block, "arguments"))),
              ]),
            )
          "tool-call" =>
            raise Invalid(
              "Session v4 tool-call block is only valid in assistant messages",
            )
          "tool-addition" | "tool-removal" if allow_tool_changes => {
            let name = required_string(block, "toolName", max=256)
            if name.length() == 0 {
              raise Invalid("Session v4 developer tool change requires a name")
            }
            if kind == "tool-addition" && fields(block).get("tool") is Some(_) {
              raise Invalid(
                "Session v4 tool-addition must omit inline tool definitions",
              )
            }
            output.changes.push(
              object([
                ("type", Json::string(kind)),
                ("tool_name", Json::string(name)),
              ]),
            )
          }
          "tool-addition" | "tool-removal" =>
            raise Invalid(
              "Session v4 tool change blocks are only valid in developer messages",
            )
          "image" => output.text += v4_image_reference_text(block, line_number)
          _ =>
            raise Invalid(
              "Unsupported Session v4 attachment/content block on line \{line_number}: \{kind}",
            )
        }
      }
    _ => raise Invalid("Session v4 message content must be a block array")
  }
  output
}

///|
fn replay_inbox_splice(
  inbox : InboxReplay,
  data : Json,
  open_turn : Bool,
  _open_step : Bool,
  line_number : Int,
) -> Unit raise EngineError {
  let target = required_string(data, "target", max=32)
  if target != "next-turn" && target != "next-step" {
    raise Invalid("Unknown Session v4 inbox target on line \{line_number}")
  }
  if target == "next-step" && !open_turn {
    raise Invalid("Session v4 inbox target is invalid at this boundary")
  }
  let start = int_value(required_field(data, "start"), "inbox start", 0, 32768)
  let removed = match fields(data).get("removedCount") {
    None => 0
    Some(value) => int_value(value, "removedCount", 0, 32768)
  }
  let inserted = array_value(
    required_field(data, "inserted"),
    "inbox inserted",
    4096,
  )
  let queue = if target == "next-turn" {
    inbox.next_turn
  } else {
    inbox.next_step
  }
  if start > queue.length() || removed > queue.length() - start {
    raise Invalid("Session v4 inbox splice is outside the pending queue")
  }
  let outcome = match fields(data).get("outcome") {
    None => ""
    Some(Json::String("canceled")) => "canceled"
    Some(_) => raise Invalid("Unknown Session v4 inbox splice outcome")
  }
  for message in inserted {
    validate_inbox_message(message, inbox, line_number)
  }
  let removed_messages : Array[Json] = []
  for index in start..<(start + removed) {
    removed_messages.push(queue[index])
  }
  if outcome == "canceled" {
    if removed == 0 {
      raise Invalid("Session v4 canceled inbox splice removes no messages")
    }
  } else if target == "next-turn" {
    for message in removed_messages {
      inbox.claimed_turn.push(message)
    }
  } else {
    for message in removed_messages {
      inbox.claimed_step.push(message)
    }
  }
  let next_queue = splice_v4_array(queue, start, removed, inserted)
  if target == "next-turn" {
    inbox.next_turn = next_queue
  } else {
    inbox.next_step = next_queue
  }
}

///|
fn archive_v4_inbox_claims(inbox : InboxReplay) -> Unit {
  inbox.claimed_turn = []
  inbox.claimed_step = []
}

///|
fn splice_v4_array(
  queue : Array[Json],
  start : Int,
  removed : Int,
  inserted : Array[Json],
) -> Array[Json] {
  let result : Array[Json] = []
  for index in 0..<start {
    result.push(queue[index])
  }
  for message in inserted {
    result.push(message)
  }
  for index in (start + removed)..<queue.length() {
    result.push(queue[index])
  }
  result
}

///|
fn validate_inbox_message(
  message : Json,
  inbox : InboxReplay,
  line_number : Int,
) -> Unit raise EngineError {
  if required_string(message, "role", max=16) != "user" {
    raise Invalid("Session v4 inbox contains a non-user message")
  }
  let id = required_string(message, "id", max=128)
  if id.length() == 0 || inbox.used_ids.get(id) is Some(_) {
    raise Invalid("Duplicate or empty Session v4 inbox message id")
  }
  let source = required_field(message, "source")
  let source_kind = required_string(source, "kind", max=64)
  if source_kind != "user" && source_kind != "repeat-tool-reminder" {
    raise Invalid("Session v4 inbox messages require user provenance")
  }
  ignore(
    project_v4_content(
      required_field(message, "content"),
      false,
      false,
      line_number,
    ),
  )
  inbox.used_ids.set(id, true)
}

///|
fn validate_claimed_message(
  replay : V4Replay,
  data : Json,
  _line_number : Int,
) -> Unit raise EngineError {
  let inbox = replay.inbox
  let id = required_string(data, "id", max=128)
  let mut found = false
  let claimed_step : Array[Json] = []
  for message in inbox.claimed_step {
    if !found && required_string(message, "id", max=128) == id {
      if message != data && !validate_v4_inbox_mod_append(message, data) {
        raise Invalid("Admitted user/message differs from its inbox entry")
      }
      found = true
    } else {
      claimed_step.push(message)
    }
  }
  if found {
    inbox.claimed_step = claimed_step
    return
  }
  let claimed_turn : Array[Json] = []
  for message in inbox.claimed_turn {
    if !found && required_string(message, "id", max=128) == id {
      if message != data && !validate_v4_inbox_mod_append(message, data) {
        raise Invalid("Admitted user/message differs from its inbox entry")
      }
      found = true
    } else {
      claimed_turn.push(message)
    }
  }
  if found {
    inbox.claimed_turn = claimed_turn
  } else {
    let source_kind = required_string(
      required_field(data, "source"),
      "kind",
      max=64,
    )
    if (source_kind == "user" || source_kind == "repeat-tool-reminder") &&
      (!inbox.claimed_step.is_empty() || !inbox.claimed_turn.is_empty()) {
      raise Invalid(
        "Session v4 inbox message does not match the admitted queue",
      )
    }
  }
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(items) => items.get(key)
    _ => None
  }
}

///|
fn imported_record(event : Event) -> Json? {
  if event.kind != EngineEventKind::UpstreamEvent {
    return None
  }
  match json_field(event.data, "record") {
    Some(record) => Some(record)
    None => None
  }
}

///|
fn project_v4_message(
  kind : String,
  record : Json,
  source_seq : Int,
  preserve_empty_source_arrays? : Bool = false,
) -> Json? {
  try {
    let data = required_field(record, "data")
    let message = match kind {
      "user/message" => data
      "system/message"
      | "developer/message"
      | "assistant/message"
      | "tool/result" => required_field(data, "message")
      _ => return None
    }
    let role = required_string(message, "role", max=16)
    let source_content = required_field(message, "content")
    let has_source_blocks = match source_content {
      Json::Array(blocks) => !blocks.is_empty()
      _ => false
    }
    let content = project_v4_content(
      source_content,
      role == "assistant",
      role == "developer",
      source_seq + 2,
    )
    let output : Map[String, Json] = Map::from_array([
      ("role", Json::string(role)),
      ("content", Json::string(content.text)),
    ])
    if content.reasoning != "" {
      output.set("reasoning", Json::string(content.reasoning))
    }
    if !content.calls.is_empty() {
      output.set("tool_calls", Json::array(content.calls))
    }
    if !content.changes.is_empty() {
      output.set("tool_changes", Json::array(content.changes))
    }
    if role == "tool" {
      match json_field(message, "toolCallId") {
        Some(value) => output.set("tool_call_id", detached(value))
        None => ()
      }
      match json_field(message, "isError") {
        Some(value) => output.set("is_error", detached(value))
        None => ()
      }
    }
    match json_field(message, "id") {
      Some(value) => output.set("source_message_id", detached(value))
      None => ()
    }
    if (role == "system" || role == "developer" || role == "assistant") &&
      !has_source_blocks &&
      !preserve_empty_source_arrays {
      return None
    }
    output.set("source_event_seq", integer(source_seq))
    Some(Json::object(output))
  } catch {
    _ => None
  }
}

///|
fn imported_messages(events : Array[Event]) -> Array[Json] {
  let surface : Array[Int] = []
  let records : Map[Int, Json] = Map([])
  for event in events {
    match imported_record(event) {
      None => ()
      Some(record) =>
        match
          (json_field(record, "type"), json_field(event.data, "source_seq")) {
          (Some(Json::String(kind)), Some(Json::Number(seq, ..))) =>
            if is_v4_surface_event(kind) {
              let source_seq = seq.to_int()
              records.set(source_seq, record)
              match json_field(record, "surfaceOp") {
                Some(Json::String("append")) => surface.push(source_seq)
                Some(Json::Object(operation)) =>
                  try {
                    let start_seq = int_value(
                      required_field(Json::object(operation), "startSeq"),
                      "replacement startSeq",
                      0,
                      source_seq,
                    )
                    let end_seq = int_value(
                      required_field(Json::object(operation), "endSeq"),
                      "replacement endSeq",
                      0,
                      source_seq,
                    )
                    match
                      v4_surface_replacement_indices(
                        surface, start_seq, end_seq,
                      ) {
                      Some((first, last)) => {
                        let updated : Array[Int] = []
                        for index in 0..<first {
                          updated.push(surface[index])
                        }
                        updated.push(source_seq)
                        for index in (last + 1)..<surface.length() {
                          updated.push(surface[index])
                        }
                        surface.clear()
                        for seq in updated {
                          surface.push(seq)
                        }
                      }
                      None => ()
                    }
                  } catch {
                    _ => ()
                  }
                _ => ()
              }
            }
          _ => ()
        }
    }
  }
  let projected : Array[Json] = []
  for source_seq in surface {
    match records.get(source_seq) {
      None => ()
      Some(record) =>
        match json_field(record, "type") {
          Some(Json::String(kind)) =>
            match project_v4_message(kind, record, source_seq) {
              Some(message) => projected.push(message)
              None => ()
            }
          _ => ()
        }
    }
  }
  projected
}

///|
fn imported_pending_calls(events : Array[Event]) -> Array[Json] {
  let calls : Map[String, Json] = Map([])
  let call_order : Array[String] = []
  let started : Map[String, Bool] = Map([])
  let settled : Map[String, Bool] = Map([])
  for event in events {
    match imported_record(event) {
      None => ()
      Some(record) =>
        match json_field(record, "type") {
          Some(Json::String("assistant/message")) =>
            match json_field(record, "data") {
              Some(data) =>
                match json_field(data, "message") {
                  Some(message) =>
                    match json_field(message, "content") {
                      Some(Json::Array(blocks)) =>
                        for block in blocks {
                          match json_field(block, "type") {
                            Some(Json::String("tool-call")) =>
                              match json_field(block, "id") {
                                Some(Json::String(id)) =>
                                  if calls.get(id) is None {
                                    let call = Map::from_array([
                                      ("id", Json::string(id)),
                                      (
                                        "name",
                                        json_field(block, "name").unwrap_or(
                                          Json::string(""),
                                        ),
                                      ),
                                      (
                                        "arguments",
                                        json_field(block, "arguments").unwrap_or(
                                          Json::string(""),
                                        ),
                                      ),
                                    ])
                                    calls.set(id, Json::object(call))
                                    call_order.push(id)
                                  }
                                _ => ()
                              }
                            _ => ()
                          }
                        }
                      _ => ()
                    }
                  _ => ()
                }
              _ => ()
            }
          Some(Json::String("tool/call")) =>
            match json_field(record, "data") {
              Some(data) =>
                match json_field(data, "callId") {
                  Some(Json::String(id)) => started.set(id, true)
                  _ => ()
                }
              _ => ()
            }
          Some(Json::String("tool/result")) =>
            match json_field(record, "data") {
              Some(data) =>
                match json_field(data, "message") {
                  Some(message) =>
                    match json_field(message, "toolCallId") {
                      Some(Json::String(id)) => settled.set(id, true)
                      _ => ()
                    }
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
    }
  }
  let result : Array[Json] = []
  for id in call_order {
    if settled.get(id) is None {
      match calls.get(id) {
        Some(Json::Object(items)) => {
          let value = items.copy()
          value.set(
            "state",
            Json::string(
              if started.get(id) is Some(true) {
                "outcome_unknown"
              } else {
                "not_started"
              },
            ),
          )
          result.push(Json::object(value))
        }
        _ => ()
      }
    }
  }
  result
}

///|
fn imported_pending_inbox(events : Array[Event]) -> Json {
  let mut next_turn : Array[Json] = []
  let mut next_step : Array[Json] = []
  let mut claimed_turn : Array[Json] = []
  let mut claimed_step : Array[Json] = []
  let unadmitted_turn : Array[Json] = []
  let unadmitted_step : Array[Json] = []
  for event in events {
    match imported_record(event) {
      Some(record) =>
        match json_field(record, "type") {
          Some(Json::String("agent/inbox/spliced")) =>
            match json_field(record, "data") {
              Some(data) =>
                match json_field(data, "target") {
                  Some(Json::String(target)) => {
                    let queue = if target == "next-turn" {
                      next_turn
                    } else {
                      next_step
                    }
                    let start = match json_field(data, "start") {
                      Some(Json::Number(number, ..)) => number.to_int()
                      _ => queue.length()
                    }
                    let removed = match json_field(data, "removedCount") {
                      Some(Json::Number(number, ..)) => number.to_int()
                      _ => 0
                    }
                    let inserted = match json_field(data, "inserted") {
                      Some(Json::Array(messages)) => messages
                      _ => []
                    }
                    if start >= 0 &&
                      start <= queue.length() &&
                      removed >= 0 &&
                      removed <= queue.length() - start {
                      if json_field(data, "outcome") !=
                        Some("canceled".to_json()) {
                        for index in start..<(start + removed) {
                          if target == "next-turn" {
                            claimed_turn.push(queue[index])
                          } else {
                            claimed_step.push(queue[index])
                          }
                        }
                      }
                      let updated = splice_v4_array(
                        queue, start, removed, inserted,
                      )
                      if target == "next-turn" {
                        next_turn = updated
                      } else if target == "next-step" {
                        next_step = updated
                      }
                    }
                  }
                  _ => ()
                }
              _ => ()
            }
          Some(Json::String("user/message")) =>
            match json_field(record, "data") {
              Some(data) =>
                match json_field(data, "id") {
                  Some(Json::String(id)) => {
                    let previous_step_count = claimed_step.length()
                    claimed_step = remove_v4_claim(claimed_step, id)
                    if claimed_step.length() == previous_step_count {
                      claimed_turn = remove_v4_claim(claimed_turn, id)
                    }
                  }
                  _ => ()
                }
              _ => ()
            }
          Some(Json::String("turn/end")) => {
            for message in claimed_turn {
              unadmitted_turn.push(message)
            }
            for message in claimed_step {
              unadmitted_step.push(message)
            }
            claimed_turn = []
            claimed_step = []
          }
          _ => ()
        }
      _ => ()
    }
  }
  for message in claimed_turn {
    unadmitted_turn.push(message)
  }
  for message in claimed_step {
    unadmitted_step.push(message)
  }
  Json::object(
    Map::from_array([
      ("next_turn", Json::array(next_turn.map(detached))),
      ("next_step", Json::array(next_step.map(detached))),
      ("unadmitted_turn", Json::array(unadmitted_turn.map(detached))),
      ("unadmitted_step", Json::array(unadmitted_step.map(detached))),
    ]),
  )
}

///|
fn remove_v4_claim(messages : Array[Json], id : String) -> Array[Json] {
  let result : Array[Json] = []
  let mut removed = false
  for message in messages {
    if !removed && json_field(message, "id") == Some(Json::string(id)) {
      removed = true
    } else {
      result.push(message)
    }
  }
  result
}

///|
