///|
fn replay_v4_event(
  replay : V4Replay,
  record : Json,
  source_seq : Int,
  line_number : Int,
) -> (Int, Int) raise EngineError {
  let kind = required_string(record, "type", max=128)
  let data = required_field(record, "data")
  let values = fields(data)
  if replay.terminal_step_without_assistant && kind != "turn/end" {
    raise Invalid(
      "An assistant-less Session v4 step must be followed by its terminal turn/end",
    )
  }
  if replay.fork_closing &&
    kind != "tool/result" &&
    kind != "step/end" &&
    kind != "turn/end" {
    raise Invalid(
      "Session v4 fork closure contains an unrelated branch event on line \{line_number}",
    )
  }
  let mut turn = replay.turn
  let mut step = replay.step
  match kind {
    "turn/start" => {
      if replay.open_turn ||
        replay.open_step ||
        !replay.inbox.claimed_turn.is_empty() ||
        !replay.inbox.claimed_step.is_empty() {
        raise Invalid(
          "Invalid Session v4 turn/start boundary on line \{line_number}",
        )
      }
      turn = int_value(required_field(data, "turn"), "turn", 1, 1000000)
      if turn != replay.turn + 1 {
        raise Invalid("Session v4 turn numbers must be contiguous")
      }
      replay.turn = turn
      replay.step = 0
      replay.open_turn = true
      replay.status = Running
      replay.admitted_prompt = false
      replay.assistant_seen = false
      replay.terminal_step_without_assistant = false
      replay.request_header = None
      replay.request_context_seen = false
      step = 0
    }
    "step/start" => {
      if !replay.open_turn || replay.open_step {
        raise Invalid(
          "Invalid Session v4 step/start boundary on line \{line_number}",
        )
      }
      turn = int_value(required_field(data, "turn"), "turn", 1, 1000000)
      step = int_value(required_field(data, "step"), "step", 1, 64)
      if turn != replay.turn || step != replay.step + 1 {
        raise Invalid(
          "Session v4 step numbers must be contiguous within a turn",
        )
      }
      replay.step = step
      replay.open_step = true
      replay.assistant_seen = false
      replay.terminal_step_without_assistant = false
    }
    "step/end" => {
      if !replay.open_turn || !replay.open_step {
        raise Invalid(
          "Invalid Session v4 step/end boundary on line \{line_number}",
        )
      }
      validate_turn_step(data, replay.turn, replay.step)
      if !replay.assistant_seen && !replay.fork_closing {
        replay.terminal_step_without_assistant = true
      } else if !replay.inbox.claimed_step.is_empty() {
        raise Invalid(
          "Session v4 step ended before assistant completion or inbox admission",
        )
      }
      require_v4_calls_settled(replay, replay.turn, replay.step)
      replay.open_step = false
    }
    "turn/end" => {
      if !replay.open_turn || replay.open_step {
        raise Invalid(
          "Invalid Session v4 turn/end boundary on line \{line_number}",
        )
      }
      turn = int_value(required_field(data, "turn"), "turn", 1, 1000000)
      if turn != replay.turn {
        raise Invalid("Session v4 turn/end names a different turn")
      }
      let reason = required_field(data, "reason")
      let end_kind = v4_end_kind(reason)
      let assistantless_terminal = replay.terminal_step_without_assistant &&
        end_kind != "completed"
      let empty_turn = replay.step == 0 && !replay.assistant_seen
      if replay.terminal_step_without_assistant && !assistantless_terminal {
        raise Invalid(
          "Session v4 cannot successfully end a step without an assistant completion",
        )
      }
      if !replay.admitted_prompt &&
        !replay.fork_closing &&
        !assistantless_terminal &&
        !empty_turn {
        raise Invalid("Session v4 turn ended without an admitted user prompt")
      }
      let has_claimed_inbox = !replay.inbox.claimed_turn.is_empty() ||
        !replay.inbox.claimed_step.is_empty()
      if has_claimed_inbox &&
        (end_kind == "completed" || (!assistantless_terminal && !empty_turn)) {
        raise Invalid(
          "Session v4 turn ended before removed inbox messages were admitted",
        )
      }
      if has_claimed_inbox {
        archive_v4_inbox_claims(replay.inbox)
      }
      require_v4_calls_settled(replay, replay.turn, replay.step)
      if replay.fork_closing && end_kind != "forked" {
        raise Invalid(
          "Session v4 fork closure must end with reason.kind=forked",
        )
      }
      replay.status = v4_end_status(reason)
      replay.open_turn = false
      replay.terminal_step_without_assistant = false
      if end_kind == "forked" {
        if !replay.fork_closing {
          raise Invalid(
            "Forked Session v4 turn-end is outside branch-owned closure",
          )
        }
        replay.fork_closing = false
      }
    }
    "assistant/message" => {
      if !replay.open_step {
        raise Invalid("Session v4 assistant/message is outside an open step")
      }
      validate_turn_step(data, replay.turn, replay.step)
      if !replay.request_context_seen {
        raise Invalid(
          "Session v4 assistant/message has no validated request/context",
        )
      }
      if replay.assistant_seen {
        raise Invalid("Session v4 step contains multiple assistant completions")
      }
      if !replay.inbox.claimed_turn.is_empty() ||
        !replay.inbox.claimed_step.is_empty() {
        raise Invalid(
          "Session v4 assistant ran before removed inbox messages were admitted",
        )
      }
      let message = required_field(data, "message")
      if required_string(message, "role", max=16) != "assistant" {
        raise Invalid("Session v4 assistant/message has a non-assistant role")
      }
      let content = project_v4_content(
        required_field(message, "content"),
        true,
        line_number,
      )
      for call_json in content.calls {
        let id = required_string(call_json, "id", max=128)
        if id.length() == 0 ||
          required_string(call_json, "name", max=128).length() == 0 ||
          replay.calls.get(id) is Some(_) {
          raise Invalid("Duplicate Session v4 tool call id: \{id}")
        }
        replay.calls.set(id, {
          turn: replay.turn,
          step: replay.step,
          name: required_string(call_json, "name", max=128),
          arguments: required_string(call_json, "arguments"),
          call_seq: None,
          started: false,
          settled: false,
        })
        replay.call_order.push(id)
      }
      validate_v4_message_source(message, "assistant", replay.message_ids)
      validate_optional_usage(values.get("usage"))
      replay.assistant_seen = true
    }
    "assistant/attempt" =>
      raise Invalid(
        "Session v4 assistant/attempt retry semantics are unsupported on line \{line_number}",
      )
    "tool/call" => {
      if !replay.open_step {
        raise Invalid("Session v4 tool/call is outside an open step")
      }
      validate_turn_step(data, replay.turn, replay.step)
      let id = required_string(data, "callId", max=128)
      let call = match replay.calls.get(id) {
        Some(call) => call
        None =>
          raise Invalid(
            "Session v4 tool/call has no advertised assistant call: \{id}",
          )
      }
      if call.started ||
        required_string(data, "name", max=128) != call.name ||
        required_string(data, "arguments") != call.arguments {
        raise Invalid(
          "Session v4 tool/call differs from the assistant tool-call block",
        )
      }
      call.started = true
      call.call_seq = Some(source_seq)
    }
    "tool/result" => {
      if !replay.open_step {
        raise Invalid("Session v4 tool/result is outside an open step")
      }
      validate_turn_step(data, replay.turn, replay.step)
      let message = required_field(data, "message")
      if required_string(message, "role", max=16) != "tool" {
        raise Invalid("Session v4 tool/result has a non-tool role")
      }
      let id = required_string(message, "toolCallId", max=128)
      let call = match replay.calls.get(id) {
        Some(call) => call
        None =>
          raise Invalid(
            "Session v4 tool/result has no matching tool/call: \{id}",
          )
      }
      match fields(record).get("sourceEventSeqs") {
        None => ()
        Some(encoded) => {
          let refs = v4_source_sequences(encoded, source_seq)
          match call.call_seq {
            Some(call_seq) =>
              if refs.length() != 1 || refs[0] != call_seq {
                raise Invalid(
                  "Session v4 tool/result sourceEventSeqs does not cite its matching tool/call",
                )
              }
            None =>
              raise Invalid(
                "Session v4 tool/result sourceEventSeqs has no started tool call",
              )
          }
        }
      }
      let error = fields(data).get("error")
      if call.settled || (!call.started && !replay.fork_closing) {
        raise Invalid(
          "Session v4 tool/result is duplicated or precedes tool/call",
        )
      }
      if replay.fork_closing {
        validate_v4_fork_result(record, message, error, call, id, source_seq)
      } else if is_fork_not_started_result(error) {
        raise Invalid(
          "Session v4 TOOL_NOT_STARTED result is only supported in a fork closure",
        )
      }
      validate_v4_tool_result_source(message, id, replay.message_ids)
      match error {
        None => ()
        Some(error_value) => {
          ignore(fields(error_value))
          match fields(message).get("isError") {
            Some(Json::True) => ()
            _ =>
              raise Invalid(
                "Session v4 errored tool result must set isError=true",
              )
          }
        }
      }
      call.settled = true
      let content = project_v4_content(
        required_field(message, "content"),
        false,
        line_number,
      )
      ignore(content)
      match fields(message).get("isError") {
        Some(value) => ignore(bool_value(value, "isError"))
        None => ()
      }
    }
    "user/message" => {
      let role = required_string(data, "role", max=16)
      if role != "user" {
        raise Invalid("Session v4 user/message has a non-user role")
      }
      if !replay.open_turn {
        raise Invalid("Session v4 user/message is outside an open turn")
      }
      if !replay.open_step || replay.assistant_seen {
        raise Invalid("Session v4 user/message is outside prompt admission")
      }
      match fields(required_field(data, "source")).get("kind") {
        Some(Json::String("user")) => replay.admitted_prompt = true
        Some(Json::String("runtime-context"))
        | Some(Json::String("repeat-tool-reminder")) => ()
        _ => raise Invalid("Unsupported Session v4 user message provenance")
      }
      validate_v4_message_source(data, "user", replay.message_ids)
      let human = required_string(
          required_field(data, "source"),
          "kind",
          max=64,
        ) ==
        "user"
      replay.user_messages[source_seq] = human
      ignore(
        project_v4_content(required_field(data, "content"), false, line_number),
      )
      validate_claimed_message(replay, data, line_number)
      if replay.open_turn {
        match (values.get("turn"), values.get("step")) {
          (Some(_), Some(_)) =>
            validate_turn_step(data, replay.turn, replay.step)
          (None, None) => ()
          _ =>
            raise Invalid(
              "Session v4 user/message has incomplete turn/step metadata",
            )
        }
      }
    }
    "system/message" | "developer/message" => {
      if !replay.open_step {
        raise Invalid(
          "Session v4 system/developer message is outside an open step",
        )
      }
      validate_turn_step(data, replay.turn, replay.step)
      let message = required_field(data, "message")
      let expected_role = if kind == "system/message" {
        "system"
      } else {
        "developer"
      }
      if required_string(message, "role", max=16) != expected_role {
        raise Invalid("Session v4 \{kind} role mismatch")
      }
      validate_v4_message_source(message, expected_role, replay.message_ids)
      ignore(
        project_v4_content(
          required_field(message, "content"),
          false,
          line_number,
        ),
      )
      if kind == "developer/message" {
        match fields(data).get("headerSeq") {
          Some(header_seq) => {
            let seq = int_value(header_seq, "headerSeq", 0, source_seq)
            if seq >= source_seq ||
              replay.source_types.get(seq) != Some("request/header") {
              raise Invalid(
                "Session v4 developer headerSeq must bind an earlier request/header",
              )
            }
          }
          None => ()
        }
      }
    }
    "request/header" => {
      if !replay.open_step {
        raise Invalid("Session v4 request/header is outside an open step")
      }
      validate_v4_request_header(replay, data)
    }
    "request/context" => {
      if !replay.open_step || replay.request_context_seen {
        raise Invalid(
          "Session v4 request/context is outside its request header",
        )
      }
      let provider = required_string(data, "provider", max=256)
      let model = required_string(data, "model", max=256)
      let header = match replay.request_header {
        Some(header) => header
        None =>
          raise Invalid(
            "Session v4 request/context has no preceding request/header",
          )
      }
      let config = required_field(header, "config")
      if provider != required_string(config, "provider", max=256) ||
        model != required_string(config, "model", max=256) {
        raise Invalid(
          "Session v4 request/context disagrees with the request header",
        )
      }
      replay.request_context_seen = true
    }
    "agent/inbox/spliced" =>
      replay_inbox_splice(
        replay.inbox,
        data,
        replay.open_turn,
        replay.open_step,
        line_number,
      )
    "session/end-seed" =>
      match fields(data).get("inherited") {
        Some(Json::True) => {
          if !replay.seeded {
            raise Invalid(
              "Unseeded Session v4 archive has an inherited end-seed marker",
            )
          }
          if replay.seed_marker is Some(_) {
            raise Invalid("Nested Session v4 forks are not supported yet")
          }
          replay.seed_marker = Some(source_seq)
          replay.fork_closing = replay.open_turn || replay.open_step
        }
        Some(_) =>
          raise Invalid("Session v4 inherited seed marker must be true")
        None => ()
      }
    "session/title" =>
      replay.title = validate_v4_title(data, source_seq, replay.user_messages)
    _ =>
      // Metadata and extension rows remain verbatim in the source archive.
      // An explicitly ignorable unknown row has no reconstruction semantics.
      if !known_v4_event(kind) && fields(record).get("ignorable") is None {
        raise Invalid(
          "Unknown required Session v4 event on line \{line_number}: \{kind}",
        )
      }
  }
  (turn, step)
}

///|
fn validate_v4_references(
  record : Json,
  source_seq : Int,
  prior_types : Map[Int, String],
) -> Unit raise EngineError {
  match fields(record).get("sourceEventSeqs") {
    None => ()
    Some(encoded) =>
      for seq in v4_source_sequences(encoded, source_seq) {
        match prior_types.get(seq) {
          Some(kind) =>
            if kind != "tool/call" &&
              kind != "user/message" &&
              kind != "system/message" &&
              kind != "developer/message" {
              raise Invalid(
                "Session v4 sourceEventSeqs references a non-message source",
              )
            }
          None =>
            raise Invalid(
              "Session v4 sourceEventSeqs references a missing source",
            )
        }
      }
  }
}

///|
fn require_v4_calls_settled(
  replay : V4Replay,
  turn : Int,
  step : Int,
) -> Unit raise EngineError {
  for id in replay.call_order {
    match replay.calls.get(id) {
      Some(call) =>
        if call.turn == turn && call.step == step && !call.settled {
          raise Invalid(
            "Session v4 step ended with an advertised tool call unresolved: \{id}",
          )
        }
      None => raise Invalid("Session v4 call index is inconsistent")
    }
  }
}

///|
fn validate_v4_message_source(
  message : Json,
  role : String,
  ids : Map[String, Bool],
) -> Unit raise EngineError {
  let id = required_string(message, "id", max=128)
  if id.length() == 0 || ids.get(id) is Some(_) {
    raise Invalid("Session v4 message id must be nonempty and unique")
  }
  let source = required_field(message, "source")
  let source_kind = required_string(source, "kind", max=64)
  match (role, source_kind) {
    ("user", "user")
    | ("user", "runtime-context")
    | ("user", "repeat-tool-reminder") => ()
    ("system", "system-prompt") => ()
    ("developer", "tool-registry") => ()
    ("assistant", "model") =>
      if required_string(source, "provider", max=256).length() == 0 ||
        required_string(source, "model", max=256).length() == 0 {
        raise Invalid("Session v4 model source requires provider and model")
      }
    _ => raise Invalid("Session v4 message source does not match role \{role}")
  }
  ids.set(id, true)
}

///|
fn validate_v4_tool_result_source(
  message : Json,
  call_id : String,
  ids : Map[String, Bool],
) -> Unit raise EngineError {
  let id = required_string(message, "id", max=128)
  if id.length() == 0 || ids.get(id) is Some(_) {
    raise Invalid("Session v4 tool result id must be nonempty and unique")
  }
  let source = required_field(message, "source")
  if required_string(source, "kind", max=64) != "tool" ||
    required_string(source, "callId", max=128) != call_id {
    raise Invalid("Session v4 tool result source does not match toolCallId")
  }
  ids.set(id, true)
}

///|
fn is_fork_not_started_result(error : Json?) -> Bool {
  match error {
    Some(Json::Object(items)) =>
      match items.get("code") {
        Some(Json::String(code)) => code == "TOOL_NOT_STARTED"
        _ => false
      }
    _ => false
  }
}

///|
fn validate_v4_fork_result(
  record : Json,
  message : Json,
  error : Json?,
  call : ImportedCall,
  call_id : String,
  source_seq : Int,
) -> Unit raise EngineError {
  let encoded_refs = fields(record).get("sourceEventSeqs")
  let content = array_value(
    required_field(message, "content"),
    "fork result content",
    8,
  )
  if content.length() != 1 ||
    required_string(content[0], "type", max=16) != "text" {
    raise Invalid("Session v4 fork result must have exactly one text block")
  }
  ignore(required_string(content[0], "text"))
  let is_error = match fields(message).get("isError") {
    Some(Json::True) => true
    _ => false
  }
  if required_string(message, "role", max=16) != "tool" ||
    required_string(message, "toolCallId", max=128) != call_id ||
    !is_error {
    raise Invalid("Session v4 fork result has invalid tool ownership")
  }
  let error_fields = match error {
    Some(error) => fields(error)
    None => raise Invalid("Session v4 fork result requires an error record")
  }
  if error_fields.length() != 2 {
    raise Invalid("Session v4 fork result error record is malformed")
  }
  if !call.started {
    if required_string(message, "id", max=128) !=
      "forked-tool-result-\{call_id}-\{source_seq}" ||
      required_string(error.unwrap(), "name", max=64) != "ToolNotStartedError" ||
      required_string(error.unwrap(), "code", max=64) != "TOOL_NOT_STARTED" ||
      encoded_refs is Some(_) ||
      required_string(content[0], "text") == "" {
      raise Invalid("Session v4 fork TOOL_NOT_STARTED result is not canonical")
    }
  } else {
    let call_seq = call.call_seq.unwrap()
    let refs = match encoded_refs {
      Some(value) => v4_source_sequences(value, source_seq)
      None =>
        raise Invalid(
          "Session v4 fork outcome-unknown result must cite its tool/call",
        )
    }
    if refs.length() != 1 ||
      refs[0] != call_seq ||
      required_string(error.unwrap(), "name", max=64) !=
      "ToolOutcomeUnknownError" ||
      required_string(error.unwrap(), "code", max=64) != "TOOL_OUTCOME_UNKNOWN" {
      raise Invalid(
        "Session v4 fork TOOL_OUTCOME_UNKNOWN result is not canonical",
      )
    }
  }
}

///|
fn validate_v4_request_header(
  replay : V4Replay,
  data : Json,
) -> Unit raise EngineError {
  let reason = required_string(data, "reason", max=32)
  if reason != "initial" &&
    reason != "resume" &&
    reason != "change" &&
    reason != "series" {
    raise Invalid("Unknown Session v4 request/header reason")
  }
  for key, _ in fields(data) {
    if key != "reason" && key != "header" && key != "startsSeries" {
      raise Invalid("Unsupported Session v4 request/header field: {key}")
    }
  }
  match fields(data).get("startsSeries") {
    None => ()
    Some(value) =>
      if reason != "series" || !bool_value(value, "startsSeries") {
        raise Invalid("Session v4 startsSeries requires a series header")
      }
  }
  let header = required_field(data, "header")
  for key, _ in fields(header) {
    if key != "config" && key != "adapterDefaults" && key != "tools" {
      raise Invalid("Unsupported Session v4 request header field: {key}")
    }
  }
  let config = required_field(header, "config")
  for key, _ in fields(config) {
    if key != "provider" &&
      key != "model" &&
      key != "maxTokens" &&
      key != "reasoningEffort" {
      raise Invalid("Unsupported Session v4 model configuration field: {key}")
    }
  }
  if required_string(config, "provider", max=256).length() == 0 ||
    required_string(config, "model", max=256).length() == 0 {
    raise Invalid("Session v4 request header requires provider and model")
  }
  match fields(config).get("maxTokens") {
    None => ()
    Some(value) => ignore(int_value(value, "maxTokens", 1, 10000000))
  }
  match fields(config).get("reasoningEffort") {
    None => ()
    Some(value) => ignore(string_value(value, "reasoningEffort", max=32))
  }
  match fields(header).get("tools") {
    None => ()
    Some(Json::String("{{tools}}")) => ()
    Some(Json::String(_)) =>
      raise Invalid(
        "Session v4 request header tools string is not a snapshot placeholder",
      )
    Some(Json::Array(tools)) =>
      for tool in tools {
        validate_v4_tool_definition(tool)
      }
    Some(_) => raise Invalid("Session v4 request header tools must be an array")
  }
  match fields(header).get("adapterDefaults") {
    None => ()
    Some(defaults) => ignore(fields(defaults))
  }
  replay.request_header = Some(header)
  replay.request_context_seen = false
}

///|
fn validate_v4_tool_definition(tool : Json) -> Unit raise EngineError {
  if required_string(tool, "name", max=256).length() == 0 {
    raise Invalid("Session v4 request tool name must not be empty")
  }
  ignore(
    string_value(
      required_field(tool, "description"),
      "tool description",
      max=16384,
    ),
  )
  ignore(fields(required_field(tool, "parameters")))
  match fields(tool).get("deferLoading") {
    None => ()
    Some(Json::True) => ()
    Some(_) =>
      raise Invalid("Session v4 tool deferLoading must be true when present")
  }
}

///|
fn validate_v4_title(
  data : Json,
  before_seq : Int,
  user_messages : Map[Int, Bool],
) -> String raise EngineError {
  for key, _ in fields(data) {
    if key != "title" && key != "messageSeqs" && key != "source" {
      raise Invalid("Unsupported Session v4 title field: {key}")
    }
  }
  let title = required_string(data, "title", max=512)
  let encoded = required_field(data, "messageSeqs")
  let references = array_value(encoded, "title messageSeqs", 128)
  let source = required_field(data, "source")
  let kind = required_string(source, "kind", max=32)
  if kind != "user" && kind != "fallback" && kind != "model" {
    raise Invalid("Unknown Session v4 title source")
  }
  if references.is_empty() != (kind == "user") {
    raise Invalid(
      "Session v4 title citations must be empty exactly for a user title",
    )
  }
  let mut previous = -1
  for item in references {
    let seq = int_value(item, "title messageSeqs member", 0, before_seq)
    if seq >= before_seq ||
      seq <= previous ||
      user_messages.get(seq) != Some(true) {
      raise Invalid(
        "Session v4 title citations must name distinct earlier human user messages",
      )
    }
    previous = seq
  }
  title
}

///|
fn validate_turn_step(
  data : Json,
  expected_turn : Int,
  expected_step : Int,
) -> Unit raise EngineError {
  if int_value(required_field(data, "turn"), "turn", 1, 1000000) !=
    expected_turn ||
    int_value(required_field(data, "step"), "step", 1, 64) != expected_step {
    raise Invalid("Session v4 event turn/step does not match its open boundary")
  }
}

///|
fn v4_end_kind(reason : Json) -> String raise EngineError {
  let kind = required_string(reason, "kind", max=32)
  if kind == "completed" ||
    kind == "blocked" ||
    kind == "max-tokens" ||
    kind == "interrupted" ||
    kind == "forked" {
    return kind
  }
  if kind == "error" {
    ignore(fields(required_field(reason, "error")))
    return kind
  }
  if kind == "aborted" {
    let cause = required_field(reason, "reason")
    let cause_kind = required_string(cause, "kind", max=32)
    if cause_kind != "user" &&
      cause_kind != "parent" &&
      cause_kind != "hook" &&
      cause_kind != "disposed" &&
      cause_kind != "legacy" {
      raise Invalid("Unknown Session v4 abort cause")
    }
    if cause_kind == "hook" {
      ignore(required_string(cause, "reason"))
    }
    return kind
  }
  raise Invalid("Unknown Session v4 turn ending: \{kind}")
}

///|
fn v4_end_status(reason : Json) -> Status raise EngineError {
  match v4_end_kind(reason) {
    "completed" => Completed
    "aborted" => Cancelled
    "blocked" | "error" | "max-tokens" | "interrupted" | "forked" => Failed
    _ => raise Invalid("Unknown Session v4 turn ending")
  }
}

///|
fn validate_v4_replay_end(
  replay : V4Replay,
  header : Json,
) -> Unit raise EngineError {
  let seeded = bool_value(required_field(header, "isSeeded"), "isSeeded")
  if seeded != replay.seeded || seeded != (replay.seed_marker is Some(_)) {
    raise Invalid(
      "Session v4 seed header and inherited end-seed marker disagree",
    )
  }
  if replay.fork_closing {
    raise Invalid("Session v4 fork tail has no complete branch-owned closure")
  }
  if replay.open_turn || replay.open_step {
    // A valid EOF can interrupt a turn. Do not synthesize a tool result or a
    // turn-end record; the unmatched source calls remain visible as unknown.
    replay.status = Failed
    if !replay.inbox.claimed_turn.is_empty() ||
      !replay.inbox.claimed_step.is_empty() {
      archive_v4_inbox_claims(replay.inbox)
    }
  } else if !replay.inbox.claimed_turn.is_empty() ||
    !replay.inbox.claimed_step.is_empty() {
    raise Invalid("Session v4 inbox messages were removed but never admitted")
  }
  if replay.status == Idle && replay.turn > 0 {
    raise Invalid("Session v4 replay ended in an invalid idle state")
  }
}

///|
fn validate_optional_usage(value : Json?) -> Unit raise EngineError {
  match value {
    None => ()
    Some(usage) =>
      for key, amount in fields(usage) {
        ignore(int_value(amount, "usage.\{key}", 0, 1000000000))
      }
  }
}
