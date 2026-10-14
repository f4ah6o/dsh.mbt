///|
const NATIVE_HOOK_RESULT_SUMMARY_MAX_UNITS : Int32 = 501

///|
const NATIVE_HOOK_EVENT_CLOSURE_RESERVE : Int32 = 40

///|
priv struct PendingNativeHookInvocation {
  turn_id : Int32
  point : String
  dialect : String
  handler_id : String
  event_seq : Int32
}

///|
fn native_hook_invocation_key(
  turn_id : Int32,
  point : String,
  handler_id : String,
) -> String {
  "\{turn_id}/\{point}/\{handler_id}"
}

///|
fn native_hook_pending_invocations(
  session : Session,
) -> Array[PendingNativeHookInvocation] {
  let pending : Map[String, PendingNativeHookInvocation] = Map([])
  for event in session.events {
    if event.kind == EngineEventKind::TurnStarted {
      pending.clear()
    } else if event.kind == EngineEventKind::TurnEnded {
      let reason = match event.data {
        Json::Object(data) => data.get("reason")
        _ => None
      }
      if reason == Some(Json::string("cancelled")) ||
        reason == Some(Json::string("interrupted")) {
        pending.clear()
      }
    } else if event.kind == EngineEventKind::HookInvoked {
      match event.data {
        Json::Object(data) =>
          match
            (
              data.get("turn"),
              data.get("point"),
              data.get("dialect"),
              data.get("handlerId"),
            ) {
            (
              Some(Json::Number(turn, ..)),
              Some(Json::String(point)),
              Some(Json::String(dialect)),
              Some(Json::String(handler_id)),
            ) =>
              if turn.to_int().to_double() == turn &&
                ["claude-code", "codex"].contains(dialect) {
                let turn_id = turn.to_int()
                pending[native_hook_invocation_key(turn_id, point, handler_id)] = {
                  turn_id,
                  point,
                  dialect,
                  handler_id,
                  event_seq: event.seq,
                }
              }
            _ => ()
          }
        _ => ()
      }
    } else if event.kind == EngineEventKind::HookResult {
      match event.data {
        Json::Object(data) =>
          match (data.get("turn"), data.get("point"), data.get("handlerId")) {
            (
              Some(Json::Number(turn, ..)),
              Some(Json::String(point)),
              Some(Json::String(handler_id)),
            ) =>
              if turn.to_int().to_double() == turn {
                ignore(
                  pending.remove(
                    native_hook_invocation_key(turn.to_int(), point, handler_id),
                  ),
                )
              }
            _ => ()
          }
        _ => ()
      }
    }
  }
  let result : Array[PendingNativeHookInvocation] = []
  for _, invocation in pending {
    result.push(invocation)
  }
  result
}

///|
fn native_hook_result_capacity_projection(session : Session) -> Session {
  let projected = session.copy_state()
  let maximum_summary = "\u0000".repeat(NATIVE_HOOK_RESULT_SUMMARY_MAX_UNITS)
  for invocation in native_hook_pending_invocations(session) {
    projected.append(
      "hook/result",
      object([
        ("turn", integer(invocation.turn_id)),
        ("point", Json::string(invocation.point)),
        ("handlerId", Json::string(invocation.handler_id)),
        ("decision", Json::string("approve")),
        ("exitCode", integer(-2147483648)),
        ("stderrSummary", Json::string(maximum_summary)),
        ("durationMs", integer(2147483647)),
      ]),
    )
  }
  projected
}

///|
fn native_hook_valid_point(point : String) -> Bool {
  ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"].contains(point)
}

///|
fn native_hook_valid_handler_id(
  handler_id : String,
  point : String,
  dialect~ : String = "claude-code",
) -> Bool {
  let prefix = "\{dialect}:\{point}:"
  if !handler_id.has_prefix(prefix) || handler_id.length() > 128 {
    return false
  }
  let suffix = handler_id[prefix.length():]
  if suffix.is_empty() {
    return false
  }
  for character in suffix {
    if character < '0' || character > '9' {
      return false
    }
  }
  true
}

///|
/// Append the invocation checkpoint before a native hook command can run.
/// The candidate reserves a maximum-size result and the normal interruption
/// closure before adopting the invocation event.
pub fn Engine::record_native_hook_invoked(
  self : Engine,
  session_id : String,
  point : String,
  handler_id : String,
  matcher : String?,
  dialect~ : String = "claude-code",
) -> Result[NativeHookInvocationCheckpoint, String] {
  if !native_hook_valid_point(point) ||
    !["claude-code", "codex"].contains(dialect) ||
    !native_hook_valid_handler_id(handler_id, point, dialect~) ||
    (
      matcher is Some(value) &&
      (value.length() > 128 || value.contains("\u0000"))
    ) {
    return Err("invalid native hook invocation identity")
  }
  let candidate = self.copy_state()
  let checkpoint = try {
    let session = candidate.lookup(session_id)
    if session.imported || session.status != Running {
      raise Invalid("Native hook invocation requires an open turn")
    }
    let key = native_hook_invocation_key(session.turn_id, point, handler_id)
    if native_hook_pending_invocations(session).any(invocation => {
        native_hook_invocation_key(
          invocation.turn_id,
          invocation.point,
          invocation.handler_id,
        ) ==
        key
      }) {
      raise Invalid("Native hook handler id is already pending")
    }
    let event_seq = session.events.length()
    let data : Map[String, Json] = {
      "turn": integer(session.turn_id),
      "point": Json::string(point),
      "dialect": Json::string(dialect),
      "handlerId": Json::string(handler_id),
    }
    match matcher {
      Some(value) => data.set("matcher", Json::string(value))
      None => ()
    }
    session.append("hook/invoked", Json::object(data))
    session.native_hook_context_source_kind = if dialect == "codex" {
      "hooks-codex"
    } else {
      "hooks-claude-code"
    }
    { session_id, turn_id: session.turn_id, point, handler_id, event_seq, }
  } catch {
    Invalid(message) => return Err(message)
  }
  if !candidate.within_capacity() {
    return Err(CAPACITY_ERROR)
  }
  self.adopt(candidate)
  Ok(checkpoint)
}

///|
/// Append the result for the exact still-open invocation. Completed handler
/// IDs may be reused by a later process; sequence and turn identity keep the
/// pair unambiguous.
pub fn Engine::record_native_hook_result(
  self : Engine,
  checkpoint : NativeHookInvocationCheckpoint,
  decision : String,
  exit_code : Int32?,
  stderr_summary : String?,
  duration_ms : Int32,
) -> Result[Json, String] {
  if !["approve", "allow", "block", "deny", "ask", "stop", "pass"].contains(
      decision,
    ) ||
    duration_ms < 0 ||
    (
      stderr_summary is Some(value) &&
      (
        value.is_empty() ||
        engine_hook_context_utf16_units(value) >
        NATIVE_HOOK_RESULT_SUMMARY_MAX_UNITS
      )
    ) {
    return Err("invalid native hook result")
  }
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.lookup(checkpoint.session_id)
    if session.imported ||
      session.status != Running ||
      session.turn_id != checkpoint.turn_id {
      raise Invalid("Native hook result is outside its open turn")
    }
    let invoked = session.events.get(checkpoint.event_seq)
    match invoked {
      Some(event) if event.kind == EngineEventKind::HookInvoked =>
        match event.data {
          Json::Object(data) if data.get("turn") ==
            Some(integer(checkpoint.turn_id)) &&
            data.get("point") == Some(Json::string(checkpoint.point)) &&
            data.get("handlerId") == Some(Json::string(checkpoint.handler_id)) =>
            match data.get("dialect") {
              Some(Json::String(dialect)) if ["claude-code", "codex"].contains(
                  dialect,
                ) &&
                native_hook_valid_handler_id(
                  checkpoint.handler_id,
                  checkpoint.point,
                  dialect~,
                ) => ()
              _ => raise Invalid("Native hook invocation checkpoint is corrupt")
            }
          _ => raise Invalid("Native hook invocation checkpoint is corrupt")
        }
      _ => raise Invalid("Native hook invocation checkpoint is stale")
    }
    let pending = native_hook_pending_invocations(session)
    if !pending.any(invocation => invocation.event_seq == checkpoint.event_seq) {
      raise Invalid("Native hook invocation already has a result")
    }
    let data : Map[String, Json] = {
      "turn": integer(checkpoint.turn_id),
      "point": Json::string(checkpoint.point),
      "handlerId": Json::string(checkpoint.handler_id),
      "decision": Json::string(decision),
      "durationMs": integer(duration_ms),
    }
    match exit_code {
      Some(value) => data.set("exitCode", integer(value))
      None => ()
    }
    match stderr_summary {
      Some(value) => data.set("stderrSummary", Json::string(value))
      None => ()
    }
    session.append("hook/result", Json::object(data))
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(value) =>
      if candidate.within_capacity() {
        self.adopt(candidate)
        Ok(value)
      } else {
        Err(CAPACITY_ERROR)
      }
  }
}
