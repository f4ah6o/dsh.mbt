///|
/// An older v1 snapshot stored empty system/developer/assistant messages even
/// when the source content array was empty. Only use that projection when the
/// source archive is within the original append-only importer subset.
fn v4_legacy_projection_supported(events : Array[Event]) -> Bool {
  try {
    let prior_types : Map[Int, String] = Map([])
    let prior_records : Map[Int, Json] = Map([])
    let mut open_turn = false
    let mut open_step = false
    let mut has_request_header = false
    let mut has_request_context = false
    for event in events {
      match imported_record(event) {
        None => ()
        Some(record) => {
          let kind = required_string(record, "type", max=128)
          let source_seq = int_value(
            required_field(event.data, "source_seq"),
            "source_seq",
            0,
            32767,
          )
          if kind == "developer/message" ||
            kind == "assistant/attempt" ||
            kind == "compaction/start" ||
            kind == "compaction/summary" ||
            kind == "compaction/prune" ||
            kind == "compaction/end" {
            return false
          }
          if !v4_legacy_known_event(kind) &&
            fields(record).get("ignorable") is None {
            return false
          }
          if is_v4_surface_event(kind) &&
            fields(record).get("surfaceOp") != Some("append".to_json()) {
            return false
          }
          match fields(record).get("sourceEventSeqs") {
            None => ()
            Some(encoded) => {
              let refs = v4_source_sequences(encoded, source_seq)
              let mut previous = -1
              for seq in refs {
                if seq <= previous {
                  return false
                }
                match prior_types.get(seq) {
                  Some("tool/call" | "user/message" | "system/message") => ()
                  _ => return false
                }
                previous = seq
              }
              if kind == "tool/result" {
                if refs.length() != 1 {
                  return false
                }
                let call_record = match prior_records.get(refs[0]) {
                  Some(value) => value
                  None => return false
                }
                let call_id = required_string(
                  required_field(required_field(record, "data"), "message"),
                  "toolCallId",
                  max=128,
                )
                if required_string(
                    required_field(call_record, "data"),
                    "callId",
                    max=128,
                  ) !=
                  call_id {
                  return false
                }
              }
            }
          }
          match kind {
            "request/header" => {
              if !open_turn || !open_step || !v4_legacy_header_supported(record) {
                return false
              }
              has_request_header = true
              has_request_context = false
            }
            "request/context" => {
              if !open_turn ||
                !open_step ||
                !has_request_header ||
                has_request_context {
                return false
              }
              has_request_context = true
            }
            "assistant/message" =>
              if !open_turn || !open_step || !has_request_context {
                return false
              }
            _ => ()
          }
          match kind {
            "turn/start" => {
              open_turn = true
              open_step = false
              has_request_header = false
              has_request_context = false
            }
            "step/start" => open_step = true
            "step/end" => open_step = false
            "turn/end" => {
              open_turn = false
              open_step = false
            }
            _ => ()
          }
          prior_types[source_seq] = kind
          prior_records[source_seq] = record
        }
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
fn v4_legacy_known_event(kind : String) -> Bool {
  [
    "agent/inbox/spliced", "approval/policy", "assistant/message", "permission/preset",
    "request/context", "request/header", "sandbox/mode", "session/end-seed", "session/title",
    "step/end", "step/start", "system/message", "tool/call", "tool/result", "turn/end",
    "turn/start", "user/message",
  ].contains(kind)
}

///|
fn v4_legacy_header_supported(record : Json) -> Bool raise EngineError {
  let data = required_field(record, "data")
  let reason = required_string(data, "reason", max=32)
  match fields(data).get("startsSeries") {
    None => ()
    Some(Json::True) if reason == "series" => ()
    _ => return false
  }
  let header = required_field(data, "header")
  match fields(header).get("tools") {
    None => true
    Some(Json::String("{{tools}}")) => true
    Some(Json::Array(tools)) => {
      for tool in tools {
        match tool {
          Json::Object(_) => ()
          _ => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn v4_legacy_imported_messages(events : Array[Event]) -> Array[Json] {
  let messages : Array[Json] = []
  for event in events {
    match imported_record(event) {
      None => ()
      Some(record) =>
        match
          (json_field(record, "type"), json_field(event.data, "source_seq")) {
          (Some(Json::String(kind)), Some(Json::Number(seq, ..))) =>
            match
              project_v4_message(
                kind,
                record,
                seq.to_int(),
                preserve_empty_source_arrays=true,
              ) {
              Some(message) => messages.push(message)
              None => ()
            }
          _ => ()
        }
    }
  }
  messages
}
