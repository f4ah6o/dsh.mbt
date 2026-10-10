///|
/// This is dsh.mbt's own bounded event format, not upstream Session v4. Effects
/// are deliberately absent: restoring interrupted work never repeats I/O.
pub fn Engine::snapshot(self : Engine) -> Json {
  object([
    ("schema", Json::string("dsh.mbt-session-v1")),
    ("next_session", integer(self.next_session)),
    ("next_effect", integer(self.next_effect)),
    (
      "sessions",
      Json::array(
        self.order.filter_map(id => self.sessions.get(id).map(Session::json)),
      ),
    ),
  ])
}

///|
/// Validate and replay an entire snapshot before replacing any live state.
/// Derived messages are checked against the log rather than trusted. Running
/// work is closed as interrupted; quiescent approval requests remain resumable.
fn Engine::restore_impl(self : Engine, snapshot : Json) -> Result[Unit, String] {
  try {
    match self.config_error {
      Some(message) => raise Invalid("Invalid tool configuration: \{message}")
      None => ()
    }
    // Replacing a live engine would detach host work without cancellation.
    if !self.effects.is_empty() ||
      self.order.any(id => self.lookup(id).is_busy()) {
      raise Invalid("Cannot restore while a session is busy")
    }
    let snapshot = checked_copy(snapshot)
    if required_string(snapshot, "schema", max=64) != "dsh.mbt-session-v1" {
      raise Invalid("Unsupported snapshot schema")
    }
    let next_session = int_value(
      required_field(snapshot, "next_session"),
      "next_session",
      1,
      1000000000,
    )
    let next_effect = int_value(
      required_field(snapshot, "next_effect"),
      "next_effect",
      1,
      1000000000,
    )
    let loaded : Map[String, Session] = Map([])
    let order : Array[String] = []
    let effect_ids : Map[String, Bool] = Map([])
    for
      value in array_value(required_field(snapshot, "sessions"), "sessions", 32) {
      let session = restore_session(value, self.tools, effect_ids, next_effect)
      if loaded.get(session.id) is Some(_) {
        raise Invalid("Duplicate snapshot session id")
      }
      loaded.set(session.id, session)
      order.push(session.id)
    }
    validate_fork_lineage(loaded, order)
    // All validation is complete. No operation below can fail or dispatch I/O.
    self.sessions.clear()
    self.order.clear()
    self.effects.clear()
    self.queued.clear()
    self.next_session = next_session
    self.next_effect = Int::max(next_effect, self.next_effect)
    for id in order {
      let session = loaded.get(id).unwrap()
      self.sessions.set(id, session)
      self.order.push(id)
      if session.status == Running {
        session.append(
          "session/interrupted",
          object([
            (
              "reason",
              Json::string(
                "Restored session had unfinished work; effects were not replayed",
              ),
            ),
          ]),
        )
        self.terminate(
          session,
          Failed,
          "interrupted",
          "Interrupted before durable completion; effect outcome is unknown",
        )
      }
    }
    Ok(())
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
fn effect_index(id : String) -> Int raise EngineError {
  if !id.has_prefix("effect-") || id.length() <= 7 || id.length() > 16 {
    raise Invalid("Invalid persisted effect id")
  }
  let mut result = 0
  let mut offset = 0
  for c in id {
    if offset >= 7 {
      if c < '0' || c > '9' {
        raise Invalid("Invalid persisted effect id")
      }
      result = result * 10 + c.to_int() - '0'.to_int()
    }
    offset += 1
  }
  if result < 1 {
    raise Invalid("Invalid persisted effect id")
  }
  result
}

///|
fn scheduled_call(session : Session) -> ToolCall raise EngineError {
  if session.schedule_cursor >= session.calls.length() {
    raise Invalid("Tool call event without an unadmitted call")
  }
  session.calls[session.schedule_cursor]
}

///|
fn result_call(session : Session) -> ToolCall raise EngineError {
  if session.cursor >= session.calls.length() {
    raise Invalid("Tool event without a pending call")
  }
  session.calls[session.cursor]
}

///|
fn expect_call_id(
  data : Json,
  key : String,
  call : ToolCall,
) -> Unit raise EngineError {
  if required_string(data, key, max=128) != call.id {
    raise Invalid("Mismatched tool call id in event log")
  }
}

///|
fn replay_tool(tools : Array[Tool], name : String) -> Tool? {
  for tool in tools {
    if tool.name == name {
      return Some(tool)
    }
  }
  None
}

///|
fn replay_is_session_tool(tools : Array[Tool], call : ToolCall) -> Bool {
  match replay_tool(tools, call.name) {
    Some(tool) => tool.effect == Session
    None => false
  }
}

///|
fn replay_arguments_are_valid(tool : Tool, call : ToolCall) -> Bool {
  if call.kind != FunctionCall {
    return false
  }
  try {
    validate_arguments(tool.input_schema, parse_arguments(call.arguments))
    true
  } catch {
    Invalid(_) => false
  }
}

///|
fn restore_session(
  value : Json,
  tools : Array[Tool],
  effect_ids : Map[String, Bool],
  next_effect : Int,
) -> Session raise EngineError {
  if json_field(value, "source_format") == Some("deepseek-session-v4".to_json()) {
    return restore_imported_session(value)
  }
  if session_capacity_length(value) > SESSION_CAPACITY {
    raise Invalid("Snapshot session exceeds the 262144-character capacity")
  }
  let id = identifier(required_string(value, "id", max=128), "session id")
  let title = required_string(value, "title", max=512)
  let system_prompt = required_string(value, "system_prompt", max=16384)
  let max_steps = int_value(
    required_field(value, "max_steps"),
    "max_steps",
    1,
    64,
  )
  let expected_status = required_string(value, "status", max=32)
  let expected_turn = int_value(
    required_field(value, "turn_id"),
    "turn_id",
    0,
    1000000,
  )
  let expected_step = int_value(required_field(value, "step"), "step", 0, 64)
  let events = array_value(required_field(value, "events"), "events", 32768)
  if events.is_empty() {
    raise Invalid("Snapshot session has no creation event")
  }
  let session = fresh_session(id, title, system_prompt, max_steps)
  let mut open_turn = false
  let mut admitted_user = false
  let mut assistant_recorded = false
  let mut pending_todo_call : String? = None
  let mut prompt_context_count = 0
  let mut prompt_context_length = 0
  let pending_post_tool_contexts : Array[(String, Json)] = []
  for index, raw in events {
    let seq = int_value(required_field(raw, "seq"), "event seq", 0, 32768)
    if seq != index {
      raise Invalid("Snapshot event sequence is not contiguous")
    }
    let kind = required_string(raw, "type", max=64)
    let turn_id = int_value(
      required_field(raw, "turn_id"),
      "event turn_id",
      0,
      1000000,
    )
    let step = int_value(required_field(raw, "step"), "event step", 0, 64)
    let data = required_field(raw, "data")
    ignore(fields(data))
    let expected_post_tool_context = pending_post_tool_contexts.get(0)
    if expected_post_tool_context is Some((call_id, expected)) {
      if kind != "user/message" || data != expected {
        raise Invalid(
          "PostToolUse context is missing, reordered, or differs from its completion",
        )
      }
      let call = match session.call_by_id(call_id) {
        Some(value) => value
        None => raise Invalid("PostToolUse context references an unknown call")
      }
      call.completed_contexts = []
      ignore(pending_post_tool_contexts.remove(0))
    }
    if index == 0 {
      if kind != "session/created" || turn_id != 0 || step != 0 {
        raise Invalid("Snapshot must begin with a creation event")
      }
      if required_string(data, "id", max=128) != id ||
        required_string(data, "title", max=512) != title ||
        required_string(data, "system_prompt", max=16384) != system_prompt ||
        int_value(required_field(data, "max_steps"), "max_steps", 1, 64) !=
        max_steps {
        raise Invalid("Creation event does not match session metadata")
      }
    } else if kind == "turn/start" {
      if open_turn || turn_id != session.turn_id + 1 || step != 0 {
        raise Invalid("Invalid turn boundary in snapshot")
      }
      session.turn_id = turn_id
      session.step = 0
      session.status = Running
      session.todos = None
      open_turn = true
      admitted_user = false
      assistant_recorded = false
      prompt_context_count = 0
      prompt_context_length = 0
    } else if kind == "step/start" {
      if !open_turn ||
        !admitted_user ||
        session.open_step ||
        turn_id != session.turn_id ||
        step != session.step + 1 ||
        step > max_steps {
        raise Invalid("Invalid step boundary in snapshot")
      }
      session.step = step
      session.open_step = true
      session.retry_count = 0
      session.retry_max_retries = None
      session.retry_initial_delay_ms = None
      session.retry_max_delay_ms = None
      session.pending_retry_id = None
      assistant_recorded = false
    } else {
      if turn_id != session.turn_id || step != session.step {
        raise Invalid("Event boundary metadata mismatch")
      }
      match kind {
        "user/message" =>
          match expected_post_tool_context {
            Some(_) => {
              if !open_turn ||
                !session.open_step ||
                session.cursor != session.calls.length() ||
                !assistant_recorded {
                raise Invalid(
                  "PostToolUse context outside completed tool results",
                )
              }
              if required_string(data, "role", max=16) != "user" {
                raise Invalid("Invalid PostToolUse context role")
              }
            }
            None =>
              match fields(data).get("source") {
                None => {
                  if !open_turn || session.step != 0 || admitted_user {
                    raise Invalid("User message outside turn admission")
                  }
                  if required_string(data, "role", max=16) != "user" ||
                    required_string(data, "content", max=16384).length() == 0 {
                    raise Invalid("Invalid user message")
                  }
                  admitted_user = true
                }
                Some(source) => {
                  if !open_turn ||
                    !admitted_user ||
                    session.step != 0 ||
                    session.open_step ||
                    assistant_recorded ||
                    required_string(data, "role", max=16) != "user" {
                    raise Invalid("Prompt context outside prompt admission")
                  }
                  let (context_count, context_length) = validate_hook_prompt_context(
                    data, source,
                  )
                  prompt_context_count += context_count
                  prompt_context_length += context_length
                  if prompt_context_count > 32 || prompt_context_length > 16384 {
                    raise Invalid("Prompt contexts exceed the configured limit")
                  }
                }
              }
          }
        "llm/request" | "tool/request" => {
          if !session.open_step {
            raise Invalid("Effect request outside an open step")
          }
          let effect_id = required_string(data, "effect_id", max=128)
          if effect_index(effect_id) >= next_effect ||
            effect_ids.get(effect_id) is Some(_) {
            raise Invalid("Invalid snapshot effect counter or duplicate id")
          }
          effect_ids.set(effect_id, true)
          if kind == "llm/request" {
            if session.active_effect is Some(_) ||
              session.active_tool_effect_count() > 0 ||
              assistant_recorded ||
              !session.calls.is_empty() {
              raise Invalid("Repeated LLM request in one step")
            }
            session.active_effect = Some(effect_id)
            session.active_kind = Some(Llm)
          } else {
            let call_id = required_string(data, "call_id", max=128)
            let call = match session.call_by_id(call_id) {
              Some(call) => call
              None => raise Invalid("Tool dispatch references an unknown call")
            }
            let tool = match replay_tool(tools, call.name) {
              Some(tool) => tool
              None =>
                raise Invalid("Unknown tool cannot have a dispatched effect")
            }
            if tool.effect == Session {
              raise Invalid("Session tools cannot have a host effect request")
            }
            if !replay_arguments_are_valid(tool, call) {
              raise Invalid(
                "Invalid tool arguments cannot have a dispatched effect",
              )
            }
            let call_index = session.call_index(call.id).unwrap()
            let eligible = if tool.effect == Read {
              call.stage == Called &&
              session.parallel_group &&
              session.active_tool_effect_count() < 4
            } else {
              call.stage == Approved &&
              session.active_tool_effect_count() == 0 &&
              session.cursor == call_index
            }
            if !assistant_recorded ||
              session.active_effect is Some(_) ||
              !eligible {
              raise Invalid("Tool dispatch without an admitted call")
            }
            expect_call_id(data, "call_id", call)
            call.stage = Dispatched
            call.effect_id = Some(effect_id)
            session.active_tool_effects.set(effect_id, call.id)
          }
        }
        "llm/retry" => {
          validate_retry_fields(data, [
            "retry_id", "effect_id", "turn", "step", "retry", "max_retries", "initial_delay_ms",
            "max_delay_ms", "delay_ms", "failure",
          ])
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) ||
            session.pending_retry_id is Some(_) {
            raise Invalid("Retry schedule without an available LLM request")
          }
          let effect_id = required_string(data, "effect_id", max=128)
          if session.active_effect != Some(effect_id) ||
            session.stream_projection(effect_id).0 {
            raise Invalid(
              "Retry schedule does not match an unprojected request",
            )
          }
          if int_value(required_field(data, "turn"), "retry turn", 1, 1000000) !=
            turn_id ||
            int_value(required_field(data, "step"), "retry step", 1, 64) != step {
            raise Invalid("Retry schedule coordinates differ from its event")
          }
          let retry = int_value(
            required_field(data, "retry"),
            "retry",
            1,
            MAX_PROVIDER_RETRIES,
          )
          let max_retries = int_value(
            required_field(data, "max_retries"),
            "max_retries",
            0,
            MAX_PROVIDER_RETRIES,
          )
          let initial_delay_ms = int_value(
            required_field(data, "initial_delay_ms"),
            "initial_delay_ms",
            0,
            MAX_PROVIDER_RETRY_DELAY_MS,
          )
          let max_delay_ms = int_value(
            required_field(data, "max_delay_ms"),
            "max_delay_ms",
            1,
            MAX_PROVIDER_RETRY_DELAY_MS,
          )
          let delay_ms = int_value(
            required_field(data, "delay_ms"),
            "delay_ms",
            0,
            MAX_PROVIDER_RETRY_DELAY_MS,
          )
          if retry != session.retry_count + 1 ||
            retry > max_retries ||
            initial_delay_ms > max_delay_ms ||
            (
              session.retry_max_retries is Some(previous) &&
              (
                previous != max_retries ||
                session.retry_initial_delay_ms != Some(initial_delay_ms) ||
                session.retry_max_delay_ms != Some(max_delay_ms)
              )
            ) {
            raise Invalid("Retry sequence or policy changed within a step")
          }
          let expected_retry_id = "retry-\{effect_id}-\{retry}"
          let retry_id = required_string(data, "retry_id", max=128)
          if retry_id != expected_retry_id {
            raise Invalid("Retry id does not match its effect and attempt")
          }
          let failure = required_field(data, "failure")
          validate_retry_fields(failure, [
            "code", "message", "status", "retry_after_ms", "request_id",
          ])
          validate_provider_request_id(fields(failure).get("request_id"))
          let code = required_string(failure, "code", max=32)
          ignore(required_string(failure, "message", max=512))
          if !retryable_provider_code(code) {
            raise Invalid("Retry failure code is not eligible")
          }
          match fields(failure).get("status") {
            Some(value) => ignore(int_value(value, "status", 100, 599))
            None => ()
          }
          let retry_after_ms = match fields(failure).get("retry_after_ms") {
            Some(value) =>
              Some(int_value(value, "retry_after_ms", 0, 2147483647))
            None => None
          }
          let expected_delay = match retry_after_ms {
            Some(delay) if delay > 0 => {
              if delay > max_delay_ms {
                raise Invalid("Retry-After exceeds the recorded delay limit")
              }
              delay
            }
            _ => {
              let mut exponential = initial_delay_ms
              for _ in 0..<(retry - 1) {
                exponential = Int::min(exponential * 2, max_delay_ms)
              }
              Int::min(exponential, max_delay_ms)
            }
          }
          if delay_ms != expected_delay {
            raise Invalid("Retry delay differs from its recorded policy")
          }
          session.retry_count = retry
          session.retry_max_retries = Some(max_retries)
          session.retry_initial_delay_ms = Some(initial_delay_ms)
          session.retry_max_delay_ms = Some(max_delay_ms)
          session.pending_retry_id = Some(retry_id)
        }
        "llm/retry-started" => {
          validate_retry_fields(data, [
            "retry_id", "effect_id", "turn", "step", "retry",
          ])
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) {
            raise Invalid("Retry start without an active provider request")
          }
          let effect_id = required_string(data, "effect_id", max=128)
          let retry_id = required_string(data, "retry_id", max=128)
          if session.active_effect != Some(effect_id) ||
            session.pending_retry_id != Some(retry_id) ||
            int_value(required_field(data, "turn"), "retry turn", 1, 1000000) !=
            turn_id ||
            int_value(required_field(data, "step"), "retry step", 1, 64) != step ||
            int_value(
              required_field(data, "retry"),
              "retry",
              1,
              MAX_PROVIDER_RETRIES,
            ) !=
            session.retry_count {
            raise Invalid("Retry start does not match its pending schedule")
          }
          session.pending_retry_id = None
        }
        "assistant/stream_delta" => {
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) ||
            session.pending_retry_id is Some(_) {
            raise Invalid("Stream delta without an active LLM request")
          }
          let effect_id = required_string(data, "effect_id", max=128)
          if session.active_effect != Some(effect_id) {
            raise Invalid("Stream delta references a stale LLM effect")
          }
          let content = required_string(
            data,
            "content",
            max=STREAM_DELTA_CAPACITY,
          )
          let reasoning = required_string(
            data,
            "reasoning",
            max=STREAM_DELTA_CAPACITY,
          )
          if (content.is_empty() && reasoning.is_empty()) ||
            content.length() + reasoning.length() > STREAM_DELTA_CAPACITY {
            raise Invalid("Invalid stream delta batch size")
          }
        }
        "assistant/message" => {
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) ||
            session.pending_retry_id is Some(_) {
            raise Invalid("Assistant message without an LLM request")
          }
          let message = required_field(data, "message")
          if required_string(message, "role", max=16) != "assistant" {
            raise Invalid("Invalid assistant message role")
          }
          let completion_data = fields(message).copy()
          completion_data.set(
            "finish_reason",
            required_field(data, "finish_reason"),
          )
          match fields(data).get("usage") {
            Some(usage) => completion_data.set("usage", usage)
            None => ()
          }
          let completion = parse_llm_completion(Json::object(completion_data))
          let effect_id = session.active_effect.unwrap()
          let (projected, streamed_content, streamed_reasoning) = session.stream_projection(
            effect_id,
          )
          if projected &&
            (
              completion.content != streamed_content ||
              completion.reasoning.unwrap_or("") != streamed_reasoning
            ) {
            raise Invalid("Assistant message differs from its projected stream")
          }
          for call in completion.calls {
            if session.used_calls.get(call.id) is Some(_) {
              raise Invalid("Duplicate recorded tool call id")
            }
            session.used_calls.set(call.id, true)
            session.calls.push(call)
          }
          assistant_recorded = true
          session.active_effect = None
          session.active_kind = None
          session.pending_retry_id = None
        }
        "assistant/attempt" => {
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) {
            raise Invalid("Assistant attempt without an LLM request")
          }
          ignore(required_string(data, "error"))
          assistant_recorded = true
          session.active_effect = None
          session.active_kind = None
          session.pending_retry_id = None
        }
        "tool/call" => {
          if !session.open_step || !assistant_recorded {
            raise Invalid("Tool call outside an assistant step")
          }
          let call = scheduled_call(session)
          if call.stage != Pending {
            raise Invalid("Duplicate tool call event")
          }
          let is_read = match replay_tool(tools, call.name) {
            Some(tool) =>
              replay_arguments_are_valid(tool, call) && tool.effect == Read
            None => false
          }
          if is_read {
            // A new read group may start only after every earlier call has
            // committed. An existing group can admit additional reads while
            // its effects settle, but it must not be reopened across a write,
            // shell, approval, or local-failure barrier.
            if !session.parallel_group &&
              (
                session.active_tool_effect_count() > 0 ||
                session.cursor != session.schedule_cursor
              ) {
              raise Invalid("Read call crossed an unsettled exclusive barrier")
            }
            if session.active_tool_effect_count() >= 4 {
              raise Invalid("Read pool exceeded its configured capacity")
            }
            session.parallel_group = true
          } else {
            if session.active_tool_effect_count() > 0 ||
              session.cursor != session.schedule_cursor {
              raise Invalid("Exclusive or invalid call crossed a read barrier")
            }
            session.parallel_group = false
          }
          expect_call_id(data, "id", call)
          if required_string(data, "name", max=128) != call.name ||
            required_string(data, "arguments") != call.arguments ||
            parse_tool_call_kind(data) != call.kind {
            raise Invalid("Tool call payload differs from the model message")
          }
          call.stage = Called
          session.schedule_cursor += 1
        }
        "todo/write" => {
          if !session.open_step ||
            !assistant_recorded ||
            pending_todo_call is Some(_) {
            raise Invalid("Todo write is outside its live tool call")
          }
          let data_fields = fields(data)
          if data_fields.length() != 2 ||
            data_fields.get("call_id") is None ||
            data_fields.get("todos") is None {
            raise Invalid("Todo write event has an invalid shape")
          }
          let call = result_call(session)
          let call_id = required_string(data, "call_id", max=128)
          if call.id != call_id ||
            call.kind != FunctionCall ||
            call.name != "todo_write" ||
            call.stage != Called {
            raise Invalid(
              "Todo write does not match the pending todo_write call",
            )
          }
          let tool = match replay_tool(tools, call.name) {
            Some(tool) if tool.effect == Session => tool
            _ => raise Invalid("Todo write tool is not in the session catalog")
          }
          let arguments = parse_arguments(call.arguments)
          validate_arguments(tool.input_schema, arguments)
          let items = normalize_todo_write(arguments)
          if required_field(data, "todos") != Json::array(items.map(detached)) {
            raise Invalid(
              "Todo write differs from its normalized tool arguments",
            )
          }
          session.todos = Some(items.map(detached))
          pending_todo_call = Some(call.id)
        }
        "tool/approval/requested" => {
          let call_id = required_string(data, "call_id", max=128)
          let call = match session.call_by_id(call_id) {
            Some(call) => call
            None => raise Invalid("Approval references an unknown call")
          }
          if call.stage != Called ||
            session.approval is Some(_) ||
            session.active_effect is Some(_) ||
            session.active_tool_effect_count() > 0 ||
            session.cursor >= session.calls.length() ||
            session.calls[session.cursor].id != call.id {
            raise Invalid("Invalid tool approval request")
          }
          expect_call_id(data, "call_id", call)
          if required_string(data, "name", max=128) != call.name {
            raise Invalid("Approval tool name mismatch")
          }
          let tool = match replay_tool(tools, call.name) {
            Some(tool) => tool
            None => raise Invalid("Unknown tool cannot require approval")
          }
          if tool.effect == Read ||
            tool.effect == Session ||
            !replay_arguments_are_valid(tool, call) {
            raise Invalid(
              "Read, session, or invalid call cannot request approval",
            )
          }
          let arguments = required_field(data, "arguments")
          if arguments != parse_arguments(call.arguments) {
            raise Invalid("Approval arguments differ from the model call")
          }
          call.stage = Waiting
          session.status = AwaitingApproval
          session.approval = Some({
            call_id: call.id,
            name: call.name,
            arguments,
          })
        }
        "tool/approval/resolved" => {
          let call_id = required_string(data, "call_id", max=128)
          let call = match session.call_by_id(call_id) {
            Some(call) => call
            None =>
              raise Invalid("Approval decision references an unknown call")
          }
          if call.stage != Waiting || session.approval is None {
            raise Invalid("Approval decision without a request")
          }
          if replay_is_session_tool(tools, call) {
            raise Invalid("Session tool cannot be approved")
          }
          expect_call_id(data, "call_id", call)
          call.stage = if bool_value(
              required_field(data, "approved"),
              "approved",
            ) {
            Approved
          } else {
            Denied
          }
          session.approval = None
          session.status = Running
        }
        "tool/completed" => {
          let call_id = required_string(data, "call_id", max=128)
          let call = match session.call_by_id(call_id) {
            Some(call) => call
            None => raise Invalid("Tool completion references an unknown call")
          }
          let source = required_string(data, "source", max=16)
          let content = required_string(data, "content")
          let is_error = bool_value(
            required_field(data, "is_error"),
            "is_error",
          )
          let additional_contexts = match
            fields(data).get("additional_contexts") {
            None => []
            Some(value) => {
              if source != "effect" {
                raise Invalid(
                  "Only completed PostToolUse results may contain additional contexts",
                )
              }
              let raw_contexts = array_value(
                value,
                "additional_contexts",
                MAX_POST_TOOL_CONTEXTS,
              )
              if raw_contexts.is_empty() {
                raise Invalid(
                  "Empty PostToolUse context arrays are not canonical",
                )
              }
              let parsed : Array[String] = []
              let mut total_length = 0
              for raw_context in raw_contexts {
                let context = string_value(
                  raw_context,
                  "additional_context",
                  max=MAX_POST_TOOL_CONTEXT_ITEM_LENGTH,
                )
                if context.is_empty() {
                  raise Invalid("Empty PostToolUse contexts are not canonical")
                }
                total_length += context.length()
                if total_length > MAX_POST_TOOL_CONTEXT_TOTAL_LENGTH {
                  raise Invalid(
                    "PostToolUse contexts exceed the aggregate length limit",
                  )
                }
                parsed.push(context)
              }
              parsed
            }
          }
          match source {
            "effect" => {
              if replay_is_session_tool(tools, call) {
                raise Invalid("Session tool cannot complete from a host effect")
              }
              let effect_id = required_string(data, "effect_id", max=128)
              if (call.stage != Dispatched && call.stage != OutcomeKnown) ||
                call.effect_id != Some(effect_id) ||
                session.active_tool_effects.get(effect_id) != Some(call.id) {
                raise Invalid(
                  "Tool completion does not match an active call effect",
                )
              }
              session.active_tool_effects.remove(effect_id)
              call.effect_id = None
            }
            "effect-known" => {
              if replay_is_session_tool(tools, call) {
                raise Invalid("Session tool cannot have a host-known outcome")
              }
              let effect_id = required_string(data, "effect_id", max=128)
              if call.stage != Dispatched ||
                call.effect_id != Some(effect_id) ||
                session.active_tool_effects.get(effect_id) != Some(call.id) {
                raise Invalid(
                  "Known tool outcome does not match an active call effect",
                )
              }
            }
            "interrupted" => {
              let is_session_tool = replay_is_session_tool(tools, call)
              if !is_error {
                raise Invalid("Interrupted tool result must be an error")
              }
              match fields(data).get("effect_id") {
                Some(raw_effect_id) => {
                  if is_session_tool {
                    raise Invalid(
                      "Session tool cannot be interrupted as a host effect",
                    )
                  }
                  let effect_id = string_value(
                    raw_effect_id,
                    "effect_id",
                    max=128,
                  )
                  if call.stage != Dispatched ||
                    call.effect_id != Some(effect_id) ||
                    session.active_tool_effects.get(effect_id) != Some(call.id) {
                    raise Invalid(
                      "Interrupted result does not match an active tool effect",
                    )
                  }
                  session.active_tool_effects.remove(effect_id)
                  call.effect_id = None
                }
                None =>
                  if is_session_tool {
                    if call.stage != Called {
                      raise Invalid(
                        "Unstarted session-tool interruption has no live call",
                      )
                    }
                  } else if call.stage != Called &&
                    call.stage != Waiting &&
                    call.stage != Approved {
                    raise Invalid("Unstarted interruption has no live call")
                  }
              }
            }
            "local" => {
              if fields(data).get("effect_id") is Some(_) {
                raise Invalid("Local tool completion cannot name an effect")
              }
              let local_failure = match replay_tool(tools, call.name) {
                None => true
                Some(tool) => !replay_arguments_are_valid(tool, call)
              }
              let legacy_unknown_todo = call.name == "todo_write" &&
                content == "Unknown tool: todo_write" &&
                call.stage == Called &&
                is_error
              if call.stage == Denied {
                if !is_error {
                  raise Invalid("Denied tool result must be an error")
                }
              } else if call.stage != Called ||
                (!local_failure && !legacy_unknown_todo) ||
                !is_error {
                raise Invalid("Local tool completion without a local failure")
              }
            }
            "session" => {
              let completion_fields = fields(data)
              if completion_fields.length() != 4 ||
                completion_fields.get("source") is None ||
                completion_fields.get("call_id") is None ||
                completion_fields.get("content") is None ||
                completion_fields.get("is_error") is None {
                raise Invalid("Session tool completion has an invalid shape")
              }
              let call_index = session.call_index(call.id).unwrap_or(-1)
              let tool = match replay_tool(tools, call.name) {
                Some(tool) if tool.effect == Session => tool
                _ =>
                  raise Invalid(
                    "Session completion references a non-session tool",
                  )
              }
              if call.name != "todo_write" ||
                call.kind != FunctionCall ||
                call.stage != Called ||
                call_index != session.cursor ||
                session.active_tool_effect_count() > 0 {
                raise Invalid(
                  "Session completion is outside the todo tool barrier",
                )
              }
              let arguments = parse_arguments(call.arguments)
              validate_arguments(tool.input_schema, arguments)
              match checked_todo_write(arguments) {
                Ok(items) =>
                  if pending_todo_call != Some(call.id) ||
                    session.todos != Some(items) ||
                    is_error ||
                    content != todo_write_summary(items) {
                    raise Invalid(
                      "Todo success is missing its exact write/result",
                    )
                  }
                Err(error) =>
                  if pending_todo_call is Some(_) ||
                    !is_error ||
                    content != "Invalid todo list: " + error {
                    raise Invalid(
                      "Todo failure differs from its validated arguments",
                    )
                  }
              }
            }
            _ => raise Invalid("Unknown tool completion source")
          }
          call.stage = if source == "effect-known" {
            OutcomeKnown
          } else {
            Completed
          }
          call.completed_content = Some(content)
          call.completed_error = Some(is_error)
          call.completed_contexts = additional_contexts
        }
        "tool/result" => {
          let call = result_call(session)
          if call.stage == Pending || call.stage == Settled {
            raise Invalid("Tool result without a started call")
          }
          expect_call_id(data, "tool_call_id", call)
          if required_string(data, "role", max=16) != "tool" {
            raise Invalid("Invalid tool result role")
          }
          let content = required_string(data, "content")
          let is_error = bool_value(
            required_field(data, "is_error"),
            "is_error",
          )
          let is_session_todo = call.kind == FunctionCall &&
            call.name == "todo_write" &&
            (match replay_tool(tools, call.name) {
              Some(tool) => tool.effect == Session
              None => false
            })
          if is_session_todo && call.stage != Completed {
            raise Invalid("Todo result lacks a successful internal completion")
          }
          if pending_todo_call is Some(pending_id) &&
            (pending_id != call.id || !is_session_todo || is_error) {
            raise Invalid(
              "Todo write is not paired with its successful tool result",
            )
          }
          if is_session_todo && !is_error && pending_todo_call != Some(call.id) {
            raise Invalid(
              "Successful todo result has no matching todo/write event",
            )
          }
          if call.stage == Completed {
            if call.completed_content != Some(content) ||
              call.completed_error != Some(is_error) {
              raise Invalid("Tool result differs from its durable completion")
            }
            call.completed_content = None
            call.completed_error = None
          } else if call.stage == OutcomeKnown {
            if call.completed_content != Some(content) ||
              call.completed_error != Some(is_error) {
              raise Invalid("Tool result differs from its known outcome")
            }
            let effect_id = match call.effect_id {
              Some(effect_id) => effect_id
              None => raise Invalid("Known tool result has no active effect")
            }
            if session.active_tool_effects.get(effect_id) != Some(call.id) {
              raise Invalid(
                "Known tool result does not match its active call effect",
              )
            }
            session.active_tool_effects.remove(effect_id)
            call.effect_id = None
            call.completed_content = None
            call.completed_error = None
          } else if call.stage == Dispatched {
            // Older snapshots wrote tool/result directly after tool/request.
            let effect_id = match call.effect_id {
              Some(effect_id) => effect_id
              None => raise Invalid("Legacy tool result has no active effect")
            }
            if session.active_tool_effects.get(effect_id) != Some(call.id) {
              raise Invalid(
                "Legacy tool result does not match its active effect",
              )
            }
            session.active_tool_effects.remove(effect_id)
            call.effect_id = None
          } else if call.stage != Called &&
            call.stage != Waiting &&
            call.stage != Approved &&
            call.stage != Denied {
            raise Invalid("Tool result without a completed call")
          }
          call.stage = Settled
          if pending_todo_call == Some(call.id) {
            pending_todo_call = None
          }
          session.cursor += 1
          session.active_effect = None
          session.active_kind = None
          session.pending_retry_id = None
          session.approval = None
          session.status = Running
          if session.cursor == session.calls.length() {
            for completed_call in session.calls {
              if !completed_call.completed_contexts.is_empty() {
                pending_post_tool_contexts.push(
                  (
                    completed_call.id,
                    hook_context_message(completed_call.completed_contexts),
                  ),
                )
              }
            }
          }
        }
        "tool/result/pruned" => session.validate_tool_result_prune(data)
        "step/end" => {
          if !session.open_step ||
            !assistant_recorded ||
            session.cursor != session.calls.length() ||
            session.schedule_cursor != session.calls.length() ||
            session.active_tool_effect_count() > 0 ||
            session.active_effect is Some(_) ||
            session.pending_retry_id is Some(_) {
            raise Invalid("Step ended with unsettled work")
          }
          ignore(required_string(data, "reason", max=64))
          session.calls.clear()
          session.cursor = 0
          session.schedule_cursor = 0
          session.parallel_group = false
          session.open_step = false
        }
        "turn/end" => {
          if !open_turn ||
            session.open_step ||
            session.active_effect is Some(_) ||
            session.active_tool_effect_count() > 0 ||
            session.approval is Some(_) ||
            session.pending_retry_id is Some(_) {
            raise Invalid("Turn ended with unsettled work")
          }
          session.status = match required_string(data, "reason", max=64) {
            "completed" => Completed
            "cancelled" => Cancelled
            "provider_error"
            | "max_steps"
            | "max_tokens"
            | "effect_limit"
            | "session_capacity"
            | "interrupted" => Failed
            _ => raise Invalid("Unknown turn ending")
          }
          open_turn = false
        }
        "session/cancelled" => {
          if open_turn || session.status != Idle {
            raise Invalid("Invalid idle cancellation")
          }
          session.status = Cancelled
        }
        "session/forked" =>
          session.restore_fork_marker(data, index, turn_id, step, open_turn)
        "session/interrupted" => {
          if !open_turn {
            raise Invalid("Interruption outside an open turn")
          }
          ignore(required_string(data, "reason"))
        }
        _ => raise Invalid("Unknown required snapshot event: \{kind}")
      }
    }
    session.events.push({
      seq,
      kind: EngineEventKind::from_wire(kind),
      turn_id,
      step,
      data,
    })
  }
  if pending_todo_call is Some(_) {
    raise Invalid("Snapshot ends before the todo write tool result")
  }
  if !pending_post_tool_contexts.is_empty() {
    raise Invalid("Snapshot ends before all PostToolUse context messages")
  }
  if status_text(session.status) != expected_status ||
    session.turn_id != expected_turn ||
    session.step != expected_step {
    raise Invalid("Snapshot state disagrees with its event log")
  }
  if required_field(value, "messages") != Json::array(session.messages()) {
    raise Invalid("Snapshot messages disagree with the event log")
  }
  let actual_todos = fields(session.json()).get("todos").unwrap_or(Json::null())
  match fields(value).get("todos") {
    Some(expected) if expected != actual_todos =>
      raise Invalid("Snapshot todo projection disagrees with its event log")
    None if session.events.any(event => event.kind == EngineEventKind::TodoWrite) =>
      raise Invalid("Snapshot with todo writes is missing its todo projection")
    _ => ()
  }
  match fields(value).get("stream_revision") {
    Some(revision) if revision != integer(session.stream_revision()) =>
      raise Invalid("Snapshot stream revision disagrees with the event log")
    _ => ()
  }
  let expected_approval = fields(value).get("pending_approval")
  let actual_approval = fields(session.json()).get("pending_approval")
  if fields(value).get("parent_session_id") !=
    fields(session.json()).get("parent_session_id") {
    raise Invalid("Snapshot fork lineage disagrees with its event log")
  }
  if expected_approval != actual_approval {
    raise Invalid("Snapshot approval disagrees with the event log")
  }
  if open_turn &&
    session.active_effect is None &&
    session.active_tool_effect_count() == 0 &&
    session.approval is None {
    raise Invalid("Snapshot captured an impossible in-between transition")
  }
  if open_turn && session.events.length() + 40 > 32768 {
    raise Invalid("Snapshot leaves no room to settle interrupted work")
  }
  session
}

///|
fn validate_hook_prompt_context(
  data : Json,
  source : Json,
) -> (Int, Int) raise EngineError {
  let source_fields = fields(source)
  if source_fields.length() != 1 ||
    source_fields.get("kind") != Some(Json::string("hooks-claude-code")) {
    raise Invalid("Unsupported prompt context provenance")
  }
  let blocks = match required_field(data, "content") {
    Json::Array(values) if values.length() > 0 && values.length() <= 32 =>
      values
    _ => raise Invalid("Hook prompt context must contain one to 32 text blocks")
  }
  let mut total_length = 0
  for block in blocks {
    let block_fields = fields(block)
    if block_fields.length() != 2 ||
      block_fields.get("type") != Some(Json::string("text")) {
      raise Invalid("Hook prompt context must contain only text blocks")
    }
    let text = required_string(block, "text", max=4096)
    if text.is_empty() {
      raise Invalid("Hook prompt context must not contain empty text")
    }
    total_length += text.length()
  }
  if total_length > 16384 {
    raise Invalid("Hook prompt context exceeds the aggregate length limit")
  }
  (blocks.length(), total_length)
}
