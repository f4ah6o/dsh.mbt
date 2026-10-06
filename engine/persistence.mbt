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
/// Derived messages are checked against the log rather than trusted. Active
/// work is closed as interrupted, with paired errors for unfinished tools.
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
      let session = restore_session(value, effect_ids, next_effect)
      if loaded.get(session.id) is Some(_) {
        raise Invalid("Duplicate snapshot session id")
      }
      loaded.set(session.id, session)
      order.push(session.id)
    }
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
      if session.is_busy() {
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
fn current_call(session : Session) -> ToolCall raise EngineError {
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
fn restore_session(
  value : Json,
  effect_ids : Map[String, Bool],
  next_effect : Int,
) -> Session raise EngineError {
  if value.stringify().length() > SESSION_CAPACITY {
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
      open_turn = true
      admitted_user = false
      assistant_recorded = false
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
      assistant_recorded = false
    } else {
      if turn_id != session.turn_id || step != session.step {
        raise Invalid("Event boundary metadata mismatch")
      }
      match kind {
        "user/message" => {
          if !open_turn || session.step != 0 || admitted_user {
            raise Invalid("User message outside turn admission")
          }
          if required_string(data, "role", max=16) != "user" ||
            required_string(data, "content", max=16384).length() == 0 {
            raise Invalid("Invalid user message")
          }
          admitted_user = true
        }
        "llm/request" | "tool/request" => {
          if !session.open_step || session.active_effect is Some(_) {
            raise Invalid("Overlapping or misplaced effect request")
          }
          let effect_id = required_string(data, "effect_id", max=128)
          if effect_index(effect_id) >= next_effect ||
            effect_ids.get(effect_id) is Some(_) {
            raise Invalid("Invalid snapshot effect counter or duplicate id")
          }
          effect_ids.set(effect_id, true)
          session.active_effect = Some(effect_id)
          if kind == "llm/request" {
            if assistant_recorded || !session.calls.is_empty() {
              raise Invalid("Repeated LLM request in one step")
            }
            session.active_kind = Some(Llm)
          } else {
            let call = current_call(session)
            if call.stage != Called {
              raise Invalid("Tool dispatch without an admitted call")
            }
            expect_call_id(data, "call_id", call)
            call.stage = Dispatched
            session.active_kind = Some(ToolExecution)
          }
        }
        "assistant/message" => {
          if !session.open_step ||
            assistant_recorded ||
            session.active_kind != Some(Llm) {
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
        }
        "tool/call" => {
          if !session.open_step || !assistant_recorded {
            raise Invalid("Tool call outside an assistant step")
          }
          let call = current_call(session)
          if call.stage != Pending {
            raise Invalid("Duplicate tool call event")
          }
          expect_call_id(data, "id", call)
          if required_string(data, "name", max=128) != call.name ||
            required_string(data, "arguments") != call.arguments {
            raise Invalid("Tool call payload differs from the model message")
          }
          call.stage = Called
        }
        "tool/approval/requested" => {
          let call = current_call(session)
          if call.stage != Called ||
            session.approval is Some(_) ||
            session.active_effect is Some(_) {
            raise Invalid("Invalid tool approval request")
          }
          expect_call_id(data, "call_id", call)
          if required_string(data, "name", max=128) != call.name {
            raise Invalid("Approval tool name mismatch")
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
          let call = current_call(session)
          if call.stage != Waiting || session.approval is None {
            raise Invalid("Approval decision without a request")
          }
          expect_call_id(data, "call_id", call)
          ignore(bool_value(required_field(data, "approved"), "approved"))
          call.stage = Called
          session.approval = None
          session.status = Running
        }
        "tool/result" => {
          let call = current_call(session)
          if call.stage == Pending || call.stage == Settled {
            raise Invalid("Tool result without a started call")
          }
          expect_call_id(data, "tool_call_id", call)
          if required_string(data, "role", max=16) != "tool" {
            raise Invalid("Invalid tool result role")
          }
          ignore(required_string(data, "content"))
          ignore(bool_value(required_field(data, "is_error"), "is_error"))
          call.stage = Settled
          session.cursor += 1
          session.active_effect = None
          session.active_kind = None
          session.approval = None
          session.status = Running
        }
        "step/end" => {
          if !session.open_step ||
            !assistant_recorded ||
            session.cursor != session.calls.length() ||
            session.active_effect is Some(_) {
            raise Invalid("Step ended with unsettled work")
          }
          ignore(required_string(data, "reason", max=64))
          session.calls.clear()
          session.cursor = 0
          session.open_step = false
        }
        "turn/end" => {
          if !open_turn ||
            session.open_step ||
            session.active_effect is Some(_) ||
            session.approval is Some(_) {
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
        "session/interrupted" => {
          if !open_turn {
            raise Invalid("Interruption outside an open turn")
          }
          ignore(required_string(data, "reason"))
        }
        _ => raise Invalid("Unknown required snapshot event: \{kind}")
      }
    }
    session.events.push({ seq, kind, turn_id, step, data, })
  }
  if status_text(session.status) != expected_status ||
    session.turn_id != expected_turn ||
    session.step != expected_step {
    raise Invalid("Snapshot state disagrees with its event log")
  }
  if required_field(value, "messages") != Json::array(session.messages()) {
    raise Invalid("Snapshot messages disagree with the event log")
  }
  let expected_approval = fields(value).get("pending_approval")
  let actual_approval = fields(session.json()).get("pending_approval")
  if expected_approval != actual_approval {
    raise Invalid("Snapshot approval disagrees with the event log")
  }
  if open_turn && session.active_effect is None && session.approval is None {
    raise Invalid("Snapshot captured an impossible in-between transition")
  }
  if open_turn && session.events.length() + 40 > 32768 {
    raise Invalid("Snapshot leaves no room to settle interrupted work")
  }
  session
}
