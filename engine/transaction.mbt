///|
/// The initial port publishes complete session views through a bounded API.
/// Keep the canonical serialized session below 256 Ki UTF-16 code units; a
/// maximum of 32 sessions also keeps complete snapshots below host limits.
const SESSION_CAPACITY : Int = 262144

///|
const CAPACITY_ERROR : String = "Session capacity reached; create a new session"

///|
fn Session::copy_state(self : Session) -> Session {
  {
    id: self.id,
    title: self.title,
    system_prompt: self.system_prompt,
    max_steps: self.max_steps,
    status: self.status,
    turn_id: self.turn_id,
    step: self.step,
    // Committed event data is immutable inside the engine. Copy its container;
    // mutable call stages and registries must be copied independently.
    events: self.events.copy(),
    calls: self.calls.map(call => {
      id: call.id,
      name: call.name,
      arguments: call.arguments,
      stage: call.stage,
    }),
    used_calls: self.used_calls.copy(),
    cursor: self.cursor,
    approval: self.approval,
    active_effect: self.active_effect,
    active_kind: self.active_kind,
    open_step: self.open_step,
  }
}

///|
fn Engine::copy_state(self : Engine) -> Engine {
  let sessions = Map([])
  for id, session in self.sessions {
    sessions.set(id, session.copy_state())
  }
  {
    tools: self.tools,
    sessions,
    order: self.order.copy(),
    effects: self.effects.copy(),
    queued: self.queued.copy(),
    next_session: self.next_session,
    next_effect: self.next_effect,
    config_error: self.config_error,
  }
}

///|
fn Engine::adopt(self : Engine, candidate : Engine) -> Unit {
  self.sessions.clear()
  for id, session in candidate.sessions {
    self.sessions.set(id, session)
  }
  self.order.clear()
  for id in candidate.order {
    self.order.push(id)
  }
  self.effects.clear()
  for id, effect in candidate.effects {
    self.effects.set(id, effect)
  }
  self.queued.clear()
  for id in candidate.queued {
    self.queued.push(id)
  }
  self.next_session = candidate.next_session
  self.next_effect = candidate.next_effect
}

///|
/// Reserve the exact larger interrupted-restore closure as well as the current
/// view. Cancellation and capacity failure use shorter closures. A later large
/// provider/tool error itself goes through this admission transaction.
fn Engine::within_capacity(self : Engine) -> Bool {
  for _, session in self.sessions {
    if session.json().stringify().length() > SESSION_CAPACITY {
      return false
    }
  }
  let closed = self.copy_state()
  for _, session in closed.sessions {
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
      closed.terminate(
        session,
        Failed,
        "interrupted",
        "Interrupted before durable completion; effect outcome is unknown",
      )
      if session.json().stringify().length() > SESSION_CAPACITY {
        return false
      }
    }
  }
  true
}

///|
/// Atomic state admission. A capacity refusal never leaves a newly running
/// session or tool effect behind an API error.
pub fn Engine::invoke(
  self : Engine,
  operation : String,
  input : Json,
) -> Result[Json, String] {
  if operation == "session_get" || operation == "session_list" {
    return self.invoke_impl(operation, input)
  }
  let candidate = self.copy_state()
  match candidate.invoke_impl(operation, input) {
    Err(error) => Err(error)
    Ok(result) => {
      if !candidate.within_capacity() {
        return Err(CAPACITY_ERROR)
      }
      self.adopt(candidate)
      Ok(result)
    }
  }
}

///|
/// Settle one host effect atomically. An oversized result closes the original
/// admitted step explicitly without publishing candidate effects or tools.
pub fn Engine::complete(
  self : Engine,
  effect_id : String,
  result : Json,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  match candidate.complete_impl(effect_id, result) {
    Err(error) => Err(error)
    Ok(value) =>
      if candidate.within_capacity() {
        self.adopt(candidate)
        Ok(value)
      } else {
        // complete_impl succeeded, so the original effect and session exist.
        // Their interruption closure was reserved by the prior admission.
        let effect = self.effects.get(effect_id).unwrap()
        let session = self.sessions.get(effect.session_id).unwrap()
        self.terminate(session, Failed, "session_capacity", CAPACITY_ERROR)
        Ok(session.json())
      }
  }
}

///|
/// Import only a completely validated, bounded candidate; failure preserves the
/// original engine, including all session identities and effect counters.
pub fn Engine::restore(self : Engine, snapshot : Json) -> Result[Unit, String] {
  let candidate = self.copy_state()
  match candidate.restore_impl(snapshot) {
    Err(error) => Err(error)
    Ok(_) => {
      if !candidate.within_capacity() {
        return Err(CAPACITY_ERROR)
      }
      self.adopt(candidate)
      Ok(())
    }
  }
}
