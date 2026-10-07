///|
fn v4_lines(jsonl : String) -> Array[String] raise EngineError {
  if jsonl.length() == 0 || jsonl.length() > SESSION_CAPACITY {
    raise Invalid("Session v4 JSONL must contain 1 to 262144 characters")
  }
  let normalized = jsonl.replace_all(old="\r\n", new="\n")
  let lines : Array[String] = []
  let mut start = 0
  for index in 0..<normalized.length() {
    if normalized[index].to_int() == 10 {
      if index == start {
        raise Invalid("Session v4 JSONL contains an empty line")
      }
      lines.push(normalized[start:index].to_owned())
      start = index + 1
    }
  }
  if start < normalized.length() {
    lines.push(normalized[start:].to_owned())
  }
  lines
}

///|
#warnings("-deprecated")
fn v4_parse_line(line : String, line_number : Int) -> Json raise EngineError {
  let parsed = @json.parse(line, max_nesting_depth=20) catch {
    _ => raise Invalid("Invalid JSON in Session v4 line \{line_number}")
  }
  checked_copy(parsed)
}

///|
fn has_v4_physical_envelope(record : Json) -> Bool raise EngineError {
  let values = fields(record)
  values.get("seq") is Some(_) || values.get("time") is Some(_)
}

///|
fn validate_v4_header(header : Json) -> Unit raise EngineError {
  let values = fields(header)
  for key, _ in values {
    if ![
        "type", "version", "id", "createdAt", "cwd", "parentSession", "isSeeded",
        "origin", "delegationDepth", "agentPreset",
      ].contains(key) {
      raise Invalid("Unsupported Session v4 header field: \{key}")
    }
  }
  if required_string(header, "type", max=16) != "session" {
    raise Invalid("Session v4 JSONL must begin with a session header")
  }
  let version = int_value(required_field(header, "version"), "version", 0, 100)
  if version != 4 {
    raise Invalid(
      "Unsupported upstream Session format v\{version}; only v4 is supported",
    )
  }
  if required_string(header, "id", max=128).length() == 0 {
    raise Invalid("Session v4 header id must not be empty")
  }
  validate_safe_number(required_field(header, "createdAt"), "createdAt")
  ignore(bool_value(required_field(header, "isSeeded"), "isSeeded"))
  match values.get("delegationDepth") {
    Some(depth) => ignore(int_value(depth, "delegationDepth", 0, 64))
    None => raise Invalid("Session v4 header is missing delegationDepth")
  }
  match values.get("cwd") {
    Some(cwd) => ignore(string_value(cwd, "cwd", max=4096))
    None => ()
  }
  let parent_session = match values.get("parentSession") {
    Some(parent) =>
      if string_value(parent, "parentSession", max=128).length() == 0 {
        raise Invalid("Session v4 parentSession must not be empty")
      } else {
        true
      }
    None => false
  }
  match values.get("origin") {
    Some(Json::String("subagent")) => ()
    Some(_) => raise Invalid("Session v4 origin must be subagent")
    None => ()
  }
  match values.get("agentPreset") {
    Some(preset) => ignore(string_value(preset, "agentPreset", max=256))
    None => ()
  }
  let seeded = bool_value(required_field(header, "isSeeded"), "isSeeded")
  if seeded != parent_session {
    raise Invalid("Session v4 isSeeded and parentSession must appear together")
  }
}

///|
fn validate_safe_number(value : Json, label : String) -> Unit raise EngineError {
  match value {
    Json::Number(number, ..) =>
      if number.is_inf() ||
        number.is_nan() ||
        number < 0.0 ||
        number > 9007199254740991.0 ||
        number % 1.0 != 0.0 {
        raise Invalid("\{label} must be a non-negative safe integer")
      }
    _ => raise Invalid("\{label} must be a non-negative safe integer")
  }
}

///|
fn validate_v4_event_envelope(
  record : Json,
  expected_seq : Int,
  physical : Bool,
  line_number : Int,
) -> Unit raise EngineError {
  let values = fields(record)
  for key, _ in values {
    if ![
        "type", "seq", "time", "data", "ignorable", "sourceEventSeqs", "surfaceOp",
      ].contains(key) {
      raise Invalid(
        "Unexpected Session v4 field on line \{line_number}: \{key}",
      )
    }
  }
  let kind = required_string(record, "type", max=128)
  if kind.length() == 0 {
    raise Invalid("Session v4 event type is empty on line \{line_number}")
  }
  if physical {
    if int_value(required_field(record, "seq"), "event seq", 0, 32767) !=
      expected_seq {
      raise Invalid(
        "Session v4 event sequence is not contiguous on line \{line_number}",
      )
    }
    validate_safe_number(required_field(record, "time"), "event time")
  } else if values.get("seq") is Some(_) || values.get("time") is Some(_) {
    raise Invalid(
      "Session v4 snapshot rows cannot mix physical seq/time fields",
    )
  }
  match required_field(record, "data") {
    Json::Object(_) => ()
    _ =>
      raise Invalid(
        "Session v4 event data must be an object on line \{line_number}",
      )
  }
  match values.get("ignorable") {
    Some(Json::True) => ()
    Some(_) => raise Invalid("Session v4 ignorable must be true when present")
    None => ()
  }
  validate_v4_surface(record, kind, expected_seq)
  if !known_v4_event(kind) && values.get("ignorable") is None {
    raise Invalid(
      "Unknown required Session v4 event on line \{line_number}: \{kind}",
    )
  }
  validate_supported_v4_event(kind, line_number)
}

///|
fn known_v4_event(kind : String) -> Bool {
  [
    "agent/inbox/spliced", "approval/policy", "assistant/attempt", "assistant/message",
    "compaction/end", "compaction/prune", "compaction/start", "compaction/summary",
    "developer/message", "permission/preset", "request/context", "request/header",
    "llm/retry", "llm/retry-started", "sandbox/mode", "session/end-seed", "session/title",
    "step/end", "step/start", "subagent/catalog", "system/message", "tool-workflow/agent-end",
    "tool-workflow/agent-start", "tool-workflow/run-end", "tool-workflow/run-start",
    "tool/call", "tool/ptc-dispatch", "tool/ptc-dispatch-start", "tool/result", "turn/end",
    "turn/start", "user/message",
  ].contains(kind)
}

///|
fn validate_supported_v4_event(
  kind : String,
  line_number : Int,
) -> Unit raise EngineError {
  if kind == "image/offload" ||
    kind == "feedback/message-put" ||
    kind == "feedback/message-delete" {
    raise Invalid(
      "Unsupported Session v4 projection event on line \{line_number}: \{kind}",
    )
  }
  if (
      kind.has_prefix("tool/ptc-") ||
      kind.has_prefix("tool-workflow/") ||
      kind.has_prefix("subagent/") ||
      kind.has_prefix("team/")
    ) &&
    ![
      "subagent/catalog", "tool/ptc-dispatch", "tool/ptc-dispatch-start", "tool-workflow/agent-end",
      "tool-workflow/agent-start", "tool-workflow/run-end", "tool-workflow/run-start",
    ].contains(kind) {
    // These execution families are opt-in allowlists. `ignorable` cannot
    // silently turn a new lifecycle record into inert source history.
    raise Invalid(
      "Unsupported Session v4 execution correlation on line \{line_number}: \{kind}",
    )
  }
}

///|
fn validate_v4_surface(
  record : Json,
  kind : String,
  expected_seq : Int,
) -> Unit raise EngineError {
  let values = fields(record)
  let surface = kind == "system/message" ||
    kind == "developer/message" ||
    kind == "user/message" ||
    kind == "assistant/message" ||
    kind == "tool/result"
  if kind == "assistant/message" && values.get("sourceEventSeqs") is Some(_) {
    raise Invalid("Session v4 assistant/message cannot carry sourceEventSeqs")
  }
  match values.get("surfaceOp") {
    None =>
      if surface {
        raise Invalid("Session v4 message event is missing surfaceOp")
      } else if values.get("sourceEventSeqs") is Some(_) {
        raise Invalid(
          "Session v4 non-message event cannot cite surface sources",
        )
      }
    Some(Json::String("append")) => {
      if !surface {
        raise Invalid("Session v4 non-message event cannot have surfaceOp")
      }
      match values.get("sourceEventSeqs") {
        None => ()
        Some(sources) => {
          let expanded = v4_source_sequences(sources, expected_seq)
          if expanded.is_empty() {
            raise Invalid("Session v4 sourceEventSeqs must not be empty")
          }
        }
      }
    }
    Some(Json::Object(operation)) => {
      if !surface ||
        operation.length() != 3 ||
        operation.get("op") != Some("replace".to_json()) ||
        operation.get("startSeq") is None ||
        operation.get("endSeq") is None {
        raise Invalid("Session v4 surfaceOp replacement is malformed")
      }
      ignore(
        int_value(
          operation.get("startSeq").unwrap(),
          "replacement startSeq",
          0,
          expected_seq,
        ),
      )
      ignore(
        int_value(
          operation.get("endSeq").unwrap(),
          "replacement endSeq",
          0,
          expected_seq,
        ),
      )
      let sources = match values.get("sourceEventSeqs") {
        Some(sources) => v4_source_sequences(sources, expected_seq)
        None =>
          raise Invalid("Session v4 replacement is missing sourceEventSeqs")
      }
      if sources.is_empty() {
        raise Invalid(
          "Session v4 replacement sourceEventSeqs must not be empty",
        )
      }
    }
    Some(_) => raise Invalid("Invalid Session v4 surfaceOp")
  }
}

///|
fn v4_source_sequences(
  value : Json,
  before : Int,
) -> Array[Int] raise EngineError {
  let encoded = array_value(value, "sourceEventSeqs", 32768)
  let expanded : Array[Int] = []
  let seen : Map[Int, Bool] = Map([])
  for item in encoded {
    match item {
      Json::Array(range) => {
        if range.length() != 2 {
          raise Invalid("Session v4 sourceEventSeqs range must be [start, end]")
        }
        let start = int_value(
          range[0],
          "sourceEventSeqs range start",
          0,
          before,
        )
        let end = int_value(
          range[1],
          "sourceEventSeqs range end",
          start,
          before,
        )
        if end >= before || end - start + 1 > 32768 - expanded.length() {
          raise Invalid(
            "Session v4 sourceEventSeqs range is not earlier than this event",
          )
        }
        for seq in start..<=end {
          if seq >= before || seen.get(seq) is Some(_) {
            raise Invalid(
              "Session v4 sourceEventSeqs must be unique earlier sequences",
            )
          }
          expanded.push(seq)
          seen.set(seq, true)
        }
      }
      _ => {
        let seq = int_value(item, "sourceEventSeqs member", 0, before)
        if seq >= before || seen.get(seq) is Some(_) {
          raise Invalid(
            "Session v4 sourceEventSeqs must be unique earlier sequences",
          )
        }
        expanded.push(seq)
        seen.set(seq, true)
      }
    }
  }
  expanded
}

///|
