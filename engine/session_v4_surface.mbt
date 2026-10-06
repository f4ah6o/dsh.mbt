///|
fn is_v4_surface_event(kind : String) -> Bool {
  kind == "system/message" ||
  kind == "developer/message" ||
  kind == "user/message" ||
  kind == "assistant/message" ||
  kind == "tool/result"
}

///|
fn v4_surface_position(surface : Array[Int], seq : Int) -> Int? {
  for index in 0..<surface.length() {
    if surface[index] == seq {
      return Some(index)
    }
  }
  None
}

///|
fn v4_surface_replacement_indices(
  surface : Array[Int],
  start_seq : Int,
  end_seq : Int,
) -> (Int, Int)? {
  let start = v4_surface_position(surface, start_seq)
  let end = v4_surface_position(surface, end_seq)
  match (start, end) {
    (Some(first), Some(last)) if first <= last => Some((first, last))
    _ => None
  }
}

///|
fn v4_json_fields_equal_except(
  left : Json,
  right : Json,
  omitted_key : String,
) -> Bool {
  match (left, right) {
    (Json::Object(left_fields), Json::Object(right_fields)) => {
      for key, value in left_fields {
        if key != omitted_key && right_fields.get(key) != Some(value) {
          return false
        }
      }
      for key, _ in right_fields {
        if key != omitted_key && left_fields.get(key) is None {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn validate_v4_tool_result_replacement(
  replay : V4Replay,
  record : Json,
  removed : Array[Int],
) -> Unit raise EngineError {
  if removed.length() != 1 ||
    replay.source_types.get(removed[0]) != Some("tool/result") {
    raise Invalid(
      "Session v4 tool/result replacement must shadow one tool result",
    )
  }
  let previous = match replay.source_records.get(removed[0]) {
    Some(previous) => previous
    None =>
      raise Invalid("Session v4 tool/result replacement source is missing")
  }
  let old_data = required_field(previous, "data")
  let new_data = required_field(record, "data")
  if !v4_json_fields_equal_except(old_data, new_data, "message") {
    raise Invalid(
      "Session v4 tool/result replacement changed data outside message content",
    )
  }
  let old_message = required_field(old_data, "message")
  let new_message = required_field(new_data, "message")
  if !v4_json_fields_equal_except(old_message, new_message, "content") {
    raise Invalid(
      "Session v4 tool/result replacement changed message fields outside content",
    )
  }
}

///|
fn validate_v4_compact_checkpoint(
  replay : V4Replay,
  record : Json,
  data : Json,
  source_seq : Int,
  replacing : Bool,
  removed : Array[Int],
) -> Unit raise EngineError {
  let source = required_field(data, "source")
  if required_string(source, "kind", max=64) != "compact-checkpoint" {
    return
  }
  if !replacing {
    raise Invalid(
      "Session v4 compact checkpoint must replace its shadowed surface span",
    )
  }
  let compaction = match replay.compaction {
    Some(compaction) => compaction
    None =>
      raise Invalid("Session v4 compact checkpoint has no open compaction")
  }
  if required_string(source, "compactionId", max=128) != compaction.id ||
    fields(source).get("sourceCommandId") != compaction.command {
    raise Invalid("Session v4 compact checkpoint does not match its compaction")
  }
  if !replacing || removed != compaction.summary_span {
    raise Invalid(
      "Session v4 compact checkpoint must replace the compaction summary span",
    )
  }
  let summary_seq = match compaction.summary_seq {
    Some(seq) => seq
    None =>
      raise Invalid("Session v4 compact checkpoint has no matching summary")
  }
  let refs = v4_source_sequences(
    required_field(record, "sourceEventSeqs"),
    source_seq,
  )
  if !refs.contains(summary_seq) {
    raise Invalid("Session v4 compact checkpoint does not cite its summary")
  }
}

///|
fn apply_v4_surface(
  replay : V4Replay,
  record : Json,
  kind : String,
  source_seq : Int,
) -> Unit raise EngineError {
  if !is_v4_surface_event(kind) {
    return
  }
  let operation = required_field(record, "surfaceOp")
  match operation {
    Json::String("append") => {
      if kind == "tool/result" && replay.pending_prune is Some(_) {
        raise Invalid(
          "Session v4 compaction/prune must precede a tool-result replacement",
        )
      }
      if kind == "system/message" {
        if replay.surface.is_empty() {
          replay.protected_head = Some(source_seq)
        } else if replay.protected_head is None {
          raise Invalid(
            "Session v4 system/message has no protected first surface head",
          )
        }
      }
      if kind == "user/message" {
        validate_v4_compact_checkpoint(
          replay,
          record,
          required_field(record, "data"),
          source_seq,
          false,
          [],
        )
      }
      replay.surface.push(source_seq)
    }
    Json::Object(fields) => {
      let start_seq = int_value(
        required_field(Json::object(fields), "startSeq"),
        "replacement startSeq",
        0,
        source_seq,
      )
      let end_seq = int_value(
        required_field(Json::object(fields), "endSeq"),
        "replacement endSeq",
        0,
        source_seq,
      )
      let (first, last) = match
        v4_surface_replacement_indices(replay.surface, start_seq, end_seq) {
        Some(indices) => indices
        None =>
          raise Invalid(
            "Session v4 replacement range is not on the current surface",
          )
      }
      let removed : Array[Int] = []
      for index in first..<=last {
        removed.push(replay.surface[index])
      }
      let refs = v4_source_sequences(
        required_field(record, "sourceEventSeqs"),
        source_seq,
      )
      for seq in removed {
        if !refs.contains(seq) {
          raise Invalid(
            "Session v4 replacement sourceEventSeqs omit a shadowed surface node",
          )
        }
      }
      if replay.protected_head is Some(head) && removed.contains(head) {
        if kind != "system/message" ||
          removed.length() != 1 ||
          removed[0] != head {
          raise Invalid(
            "Session v4 replacement cannot shadow the protected system head",
          )
        }
        replay.protected_head = Some(source_seq)
      }
      if kind == "tool/result" {
        validate_v4_tool_result_replacement(replay, record, removed)
        match replay.pending_prune {
          Some(pruned) if pruned != removed =>
            raise Invalid(
              "Session v4 tool-result replacement differs from its compaction/prune span",
            )
          _ => ()
        }
      }
      if kind == "user/message" {
        validate_v4_compact_checkpoint(
          replay,
          record,
          required_field(record, "data"),
          source_seq,
          true,
          removed,
        )
      }
      let updated : Array[Int] = []
      for index in 0..<first {
        updated.push(replay.surface[index])
      }
      updated.push(source_seq)
      for index in (last + 1)..<replay.surface.length() {
        updated.push(replay.surface[index])
      }
      replay.surface = updated
      if kind == "tool/result" && replay.pending_prune is Some(_) {
        replay.pending_prune = None
      }
      if kind == "user/message" {
        let source = required_field(required_field(record, "data"), "source")
        if required_string(source, "kind", max=64) == "compact-checkpoint" {
          match replay.compaction {
            Some(compaction) => compaction.checkpoint_seq = Some(source_seq)
            None => ()
          }
        }
      }
    }
    _ => raise Invalid("Invalid Session v4 surface operation")
  }
}
