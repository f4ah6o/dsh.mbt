///|
/// The initial port publishes complete session views through a bounded API.
/// Keep the canonical serialized session below 256 Ki UTF-16 code units; a
/// maximum of 32 sessions also keeps complete snapshots below host limits.
const SESSION_CAPACITY : Int = 262144

///|
/// `todos: null` is fixed presentation metadata introduced after v1 snapshots
/// were already allowed up to SESSION_CAPACITY. Exclude only that optional
/// 13-unit serialized field from admission accounting; actual todo arrays count
/// in full and public/storage serialization is unchanged.
fn session_capacity_length(value : Json) -> Int {
  match value {
    Json::Object(items) =>
      match items.get("todos") {
        Some(Json::Null) => {
          let measured = items.copy()
          ignore(measured.remove("todos"))
          Json::object(measured).stringify().length()
        }
        _ => value.stringify().length()
      }
    _ => value.stringify().length()
  }
}

///|
/// Maximum text/reasoning carried by one durable provider flush event.
const STREAM_DELTA_CAPACITY : Int = 4096

///|
const MAX_PROVIDER_RETRIES : Int = 5

///|
const MAX_PROVIDER_RETRY_DELAY_MS : Int = 10000

///|
const CAPACITY_ERROR : String = "Session capacity reached; create a new session"

///|
fn Session::copy_state(self : Session) -> Session {
  {
    id: self.id,
    title: self.title,
    system_prompt: self.system_prompt,
    max_steps: self.max_steps,
    imported: self.imported,
    fork_source: self.fork_source.map(source => {
      parent_session_id: source.parent_session_id,
      source_event_count: source.source_event_count,
      source_status: source.source_status,
      source_turn_id: source.source_turn_id,
      source_step: source.source_step,
      effect_map: source.effect_map.copy(),
    }),
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
      kind: call.kind,
      stage: call.stage,
      effect_id: call.effect_id,
      completed_content: call.completed_content,
      completed_error: call.completed_error,
      completed_contexts: call.completed_contexts.copy(),
    }),
    used_calls: self.used_calls.copy(),
    cursor: self.cursor,
    schedule_cursor: self.schedule_cursor,
    parallel_group: self.parallel_group,
    active_tool_effects: self.active_tool_effects.copy(),
    approval: self.approval,
    active_effect: self.active_effect,
    active_kind: self.active_kind,
    open_step: self.open_step,
    todos: self.todos.map(items => items.map(detached)),
    retry_count: self.retry_count,
    retry_max_retries: self.retry_max_retries,
    retry_initial_delay_ms: self.retry_initial_delay_ms,
    retry_max_delay_ms: self.retry_max_delay_ms,
    pending_retry_id: self.pending_retry_id,
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
    if session_capacity_length(session.json()) > SESSION_CAPACITY {
      return false
    }
  }
  // A durable retry schedule must also have room for its future start marker.
  // Other admitted operations preserve this reservation while the wait is
  // pending, so the host cannot be stranded after recording `llm/retry`.
  let starting = self.copy_state()
  for id in starting.order.copy() {
    let pending = match starting.sessions.get(id) {
      Some(session) => (session.active_effect, session.pending_retry_id)
      None => (None, None)
    }
    match pending {
      (Some(effect_id), Some(retry_id)) =>
        match starting.start_retry_impl(effect_id, retry_id) {
          Ok(_) => ()
          Err(_) => return false
        }
      _ => ()
    }
  }
  for _, session in starting.sessions {
    if session_capacity_length(session.json()) > SESSION_CAPACITY {
      return false
    }
  }
  let closed = starting.copy_state()
  for _, session in closed.sessions {
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
      closed.terminate(
        session,
        Failed,
        "interrupted",
        "Interrupted before durable completion; effect outcome is unknown",
      )
      if session_capacity_length(session.json()) > SESSION_CAPACITY {
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
  match EngineCommand::from_json(operation, input) {
    Err(error) => Err(error)
    Ok(command) => self.apply(command)
  }
}

///|
/// Validate and apply a command to an isolated candidate without adopting its
/// state or exposing effects. Native carriers use this to reject a prompt
/// before running a configured UserPromptSubmit command.
pub fn Engine::preview(
  self : Engine,
  command : EngineCommand,
) -> Result[Json, String] {
  match command.validate() {
    Err(error) => Err(error)
    Ok(_) => {
      let candidate = self.copy_state()
      match candidate.apply_command_impl(command) {
        Err(error) => Err(error)
        Ok(result) =>
          if candidate.within_capacity() {
            Ok(result)
          } else {
            Err(CAPACITY_ERROR)
          }
      }
    }
  }
}

///|
/// Apply one validated typed command atomically. String operation names and
/// JSON inputs enter through invoke at the compatibility boundary only.
pub fn Engine::apply(
  self : Engine,
  command : EngineCommand,
) -> Result[Json, String] {
  match command.validate() {
    Err(error) => Err(error)
    Ok(_) =>
      match command {
        ListSessions | GetSession(_) => self.apply_command_impl(command)
        _ => {
          let candidate = self.copy_state()
          match candidate.apply_command_impl(command) {
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
/// Durably record a known host tool outcome while keeping its effect active.
/// Native hosts use this before advisory PostToolUse work so cancellation can
/// settle the actual outcome without replaying the tool.
pub fn Engine::record_effect_outcome(
  self : Engine,
  effect_id : String,
  result : Json,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  match candidate.record_effect_outcome_impl(effect_id, result) {
    Err(error) => Err(error)
    Ok(value) =>
      if candidate.within_capacity() {
        self.adopt(candidate)
        Ok(value)
      } else {
        let effect = self.effects.get(effect_id).unwrap()
        let session = self.sessions.get(effect.session_id).unwrap()
        self.terminate(session, Failed, "session_capacity", CAPACITY_ERROR)
        Ok(session.json())
      }
  }
}

///|
/// Typed counterpart for native runtimes that already hold an effect value.
pub fn Engine::complete_effect(
  self : Engine,
  effect_id : EffectId,
  result : Json,
) -> Result[Json, String] {
  self.complete(effect_id.as_string(), result)
}

///|
/// Record a bounded provider retry before the host waits. The engine owns the
/// retry budget and only accepts transient, unprojected failures.
pub fn Engine::schedule_retry(
  self : Engine,
  effect_id : String,
  policy : Json,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  match candidate.schedule_retry_impl(effect_id, policy) {
    Err(error) => Err(error)
    Ok(value) =>
      if candidate.within_capacity() {
        self.adopt(candidate)
        Ok(value)
      } else {
        // Decline retry admission without changing the active effect. The host
        // can then complete it through the normal per-session capacity path.
        Ok(object([("scheduled", boolean(false))]))
      }
  }
}

///|
pub fn Engine::schedule_effect_retry(
  self : Engine,
  effect_id : EffectId,
  policy : Json,
) -> Result[Json, String] {
  self.schedule_retry(effect_id.as_string(), policy)
}

///|
/// Mark a completed retry wait before the host issues the next provider call.
pub fn Engine::start_retry(
  self : Engine,
  effect_id : String,
  retry_id : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  match candidate.start_retry_impl(effect_id, retry_id) {
    Err(error) => Err(error)
    Ok(value) =>
      if candidate.within_capacity() {
        self.adopt(candidate)
        Ok(value)
      } else {
        // The schedule was already durable. If state changed enough to defeat
        // the reserved start marker, fail just this turn and prevent the host
        // from launching another provider request.
        let effect = self.effects.get(effect_id).unwrap()
        let failed = self.copy_state()
        let session = failed.sessions.get(effect.session_id).unwrap()
        failed.terminate(session, Failed, "session_capacity", CAPACITY_ERROR)
        let result = session.json()
        self.adopt(failed)
        Ok(result)
      }
  }
}

///|
pub fn Engine::start_effect_retry(
  self : Engine,
  effect_id : EffectId,
  retry_id : String,
) -> Result[Json, String] {
  self.start_retry(effect_id.as_string(), retry_id)
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
