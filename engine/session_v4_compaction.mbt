///|
fn v4_compaction_turn(data : Json) -> Int? raise EngineError {
  match required_field(data, "turn") {
    Json::Null => None
    value => Some(int_value(value, "compaction turn", 1, 1000000))
  }
}

///|
fn validate_v4_compaction_owner_turn(
  replay : V4Replay,
  turn : Int?,
  label : String,
) -> Unit raise EngineError {
  match turn {
    None =>
      if replay.open_turn {
        raise Invalid(
          "Session v4 \{label} with turn=null is inside an open turn",
        )
      }
    Some(value) =>
      if !replay.open_turn || replay.turn != value {
        raise Invalid("Session v4 \{label} does not match the open turn")
      }
  }
}

///|
fn validate_v4_compaction_span(
  replay : V4Replay,
  data : Json,
  source_seq : Int,
  label : String,
) -> Array[Int] raise EngineError {
  let range = required_field(data, "shadowedRange")
  for key, _ in fields(range) {
    if key != "start" && key != "end" {
      raise Invalid("Unsupported Session v4 compaction range field: {key}")
    }
  }
  let start_seq = int_value(
    required_field(range, "start"),
    "compaction range start",
    0,
    source_seq,
  )
  let end_seq = int_value(
    required_field(range, "end"),
    "compaction range end",
    0,
    source_seq,
  )
  let (first, last) = match
    v4_surface_replacement_indices(replay.surface, start_seq, end_seq) {
    Some(indices) => indices
    None =>
      raise Invalid(
        "Session v4 \{label} range is not an ordered current surface span",
      )
  }
  let seqs = array_value(
    required_field(data, "shadowedSeqs"),
    "compaction shadowedSeqs",
    32768,
  )
  if seqs.length() != last - first + 1 {
    raise Invalid(
      "Session v4 \{label} shadowedSeqs do not name an exact current surface span",
    )
  }
  let expected : Array[Int] = []
  for index in first..<=last {
    let seq = replay.surface[index]
    if int_value(
        seqs[index - first],
        "compaction shadowedSeqs member",
        0,
        source_seq,
      ) !=
      seq {
      raise Invalid(
        "Session v4 \{label} shadowedSeqs do not name an exact current surface span",
      )
    }
    expected.push(seq)
  }
  if expected.is_empty() ||
    expected[0] != start_seq ||
    expected[expected.length() - 1] != end_seq {
    raise Invalid(
      "Session v4 \{label} shadowedRange endpoints disagree with shadowedSeqs",
    )
  }
  if replay.protected_head is Some(head) && expected.contains(head) {
    raise Invalid(
      "Session v4 compaction cannot shadow the protected system head",
    )
  }
  ignore(
    int_value(
      required_field(data, "shadowedTokenCount"),
      "compaction shadowedTokenCount",
      0,
      1000000000,
    ),
  )
  expected
}

///|
fn validate_v4_compaction_fields(
  data : Json,
  kind : String,
) -> Unit raise EngineError {
  for key, _ in fields(data) {
    let allowed = match kind {
      "compaction/start" =>
        ["compactionId", "sourceCommandId", "turn"].contains(key)
      "compaction/end" =>
        ["compactionId", "sourceCommandId", "turn", "error"].contains(key)
      "compaction/prune" =>
        ["shadowedRange", "shadowedSeqs", "shadowedTokenCount"].contains(key)
      _ =>
        [
          "compactionId", "sourceCommandId", "summary", "shadowedRange", "shadowedSeqs",
          "shadowedTokenCount", "provider", "model", "maxTokens", "usage", "rawOutput",
          "llmStreamCall",
        ].contains(key)
    }
    if !allowed {
      raise Invalid("Unsupported Session v4 \{kind} field: \{key}")
    }
  }
}

///|
fn replay_v4_compaction(
  replay : V4Replay,
  _record : Json,
  kind : String,
  data : Json,
  source_seq : Int,
  line_number : Int,
) -> Unit raise EngineError {
  validate_v4_compaction_fields(data, kind)
  if kind == "compaction/prune" {
    if replay.pending_prune is Some(_) {
      raise Invalid(
        "Session v4 compaction/prune overlaps an unfinished replacement",
      )
    }
    replay.pending_prune = Some(
      validate_v4_compaction_span(replay, data, source_seq, kind),
    )
    return
  }
  let id = required_string(data, "compactionId", max=128)
  if id.length() == 0 {
    raise Invalid("Session v4 compactionId must not be empty")
  }
  let command = match fields(data).get("sourceCommandId") {
    None => None
    Some(value) => {
      if string_value(value, "sourceCommandId", max=128).length() == 0 {
        raise Invalid("Session v4 sourceCommandId must not be empty")
      }
      Some(value)
    }
  }
  match kind {
    "compaction/start" => {
      if replay.compaction is Some(_) {
        raise Invalid("Session v4 compaction/start overlaps an open compaction")
      }
      let turn = v4_compaction_turn(data)
      validate_v4_compaction_owner_turn(replay, turn, kind)
      replay.compaction = Some({
        id,
        command,
        turn,
        summary_seq: None,
        summary_span: [],
        checkpoint_seq: None,
      })
    }
    "compaction/summary" => {
      let compaction = match replay.compaction {
        Some(compaction) => compaction
        None =>
          raise Invalid("Session v4 compaction/summary has no matching start")
      }
      if compaction.id != id || compaction.command != command {
        raise Invalid("Session v4 compaction/summary does not match its start")
      }
      validate_v4_compaction_owner_turn(replay, compaction.turn, kind)
      if compaction.summary_seq is Some(_) {
        raise Invalid("Session v4 compaction/summary repeats")
      }
      let summary_span = validate_v4_compaction_span(
        replay, data, source_seq, kind,
      )
      ignore(
        project_v4_content(
          required_field(data, "summary"),
          false,
          false,
          line_number,
        ),
      )
      match fields(data).get("rawOutput") {
        None => ()
        Some(value) =>
          ignore(project_v4_content(value, false, false, line_number))
      }
      match fields(data).get("llmStreamCall") {
        None => ()
        Some(Json::True) =>
          if fields(data).get("rawOutput") is None {
            raise Invalid("Session v4 llmStreamCall summary requires rawOutput")
          }
        Some(_) =>
          raise Invalid("Session v4 llmStreamCall must be true when present")
      }
      ignore(required_string(data, "provider", max=256))
      ignore(required_string(data, "model", max=256))
      match fields(data).get("maxTokens") {
        None => ()
        Some(value) =>
          ignore(int_value(value, "compaction maxTokens", 0, 1000000000))
      }
      validate_optional_usage(fields(data).get("usage"))
      compaction.summary_seq = Some(source_seq)
      compaction.summary_span = summary_span
    }
    "compaction/end" => {
      let compaction = match replay.compaction {
        Some(compaction) => compaction
        None => raise Invalid("Session v4 compaction/end has no matching start")
      }
      if compaction.id != id ||
        compaction.command != command ||
        v4_compaction_turn(data) != compaction.turn {
        raise Invalid("Session v4 compaction/end does not match its start")
      }
      validate_v4_compaction_owner_turn(replay, compaction.turn, kind)
      match fields(data).get("error") {
        None =>
          if compaction.summary_seq is None {
            raise Invalid(
              "Successful Session v4 compaction/end requires a summary",
            )
          }
        Some(value) =>
          ignore(string_value(value, "compaction error", max=16384))
      }
      if fields(data).get("error") is None && compaction.checkpoint_seq is None {
        raise Invalid(
          "Successful Session v4 compaction/end requires a replacement checkpoint",
        )
      }
      replay.compaction = None
    }
    _ => raise Invalid("Invalid Session v4 compaction event")
  }
}
