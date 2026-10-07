///|
/// Effect IDs are engine-global. A fork receives fresh IDs for its copied
/// history so two sessions can retain the same tool/provider transcript without
/// claiming ownership of the same durable effect.
priv struct EffectIdRekey {
  mut next_effect : Int
  old_to_new : Map[String, String]
  pairs : Array[(String, String)]
}

///|
fn EffectIdRekey::rewrite(
  self : EffectIdRekey,
  source_id : String,
) -> String raise EngineError {
  match self.old_to_new.get(source_id) {
    Some(fork_id) => fork_id
    None => {
      ignore(effect_index(source_id))
      if self.next_effect >= 1000000000 {
        raise Invalid("Effect identifier limit reached while forking session")
      }
      let fork_id = "effect-\{self.next_effect}"
      self.next_effect += 1
      self.old_to_new[source_id] = fork_id
      self.pairs.push((source_id, fork_id))
      fork_id
    }
  }
}

///|
fn EffectIdRekey::rewrite_event_data(
  self : EffectIdRekey,
  event : Event,
) -> Json raise EngineError {
  if event.kind != EngineEventKind::LlmRequest &&
    event.kind != EngineEventKind::ToolRequest &&
    event.kind != EngineEventKind::ToolCompleted &&
    event.kind != EngineEventKind::AssistantStreamDelta &&
    event.kind != EngineEventKind::LlmRetry &&
    event.kind != EngineEventKind::LlmRetryStarted {
    return detached(event.data)
  }
  let source_id = match event_effect_id(event) {
    Some(value) => value
    None if event.kind == EngineEventKind::ToolCompleted =>
      return detached(event.data)
    None => raise Invalid("Source effect event is missing its effect id")
  }
  match event.data {
    Json::Object(values) => {
      let result = values.copy()
      let fork_id = self.rewrite(source_id)
      result.set("effect_id", Json::string(fork_id))
      if event.kind == EngineEventKind::LlmRetry ||
        event.kind == EngineEventKind::LlmRetryStarted {
        let retry = int_value(
          required_field(event.data, "retry"),
          "retry",
          1,
          MAX_PROVIDER_RETRIES,
        )
        let expected = "retry-\{source_id}-\{retry}"
        if required_string(event.data, "retry_id", max=128) != expected {
          raise Invalid("Source retry identity is not canonical")
        }
        result.set("retry_id", Json::string("retry-\{fork_id}-\{retry}"))
      }
      Json::object(result)
    }
    _ => raise Invalid("Source effect event data must be an object")
  }
}

///|
fn Engine::fork_session(
  self : Engine,
  source_id : String,
  requested_id : String?,
  requested_title : String?,
) -> Session raise EngineError {
  let source = self.lookup(source_id)
  if source.imported {
    raise Invalid("Imported Session v4 histories cannot be forked")
  }
  if source.status != Idle &&
    source.status != Completed &&
    source.status != Failed &&
    source.status != Cancelled {
    raise Invalid("Only a settled session can be forked")
  }
  if source.open_step ||
    source.active_effect is Some(_) ||
    source.active_kind is Some(_) ||
    source.active_tool_effect_count() > 0 ||
    source.approval is Some(_) ||
    source.pending_retry_id is Some(_) ||
    !source.calls.is_empty() ||
    source.cursor != 0 ||
    source.schedule_cursor != 0 {
    raise Invalid("Session still has unsettled execution state")
  }
  for _, effect in self.effects {
    if effect.session_id == source.id {
      raise Invalid("Session still has unsettled execution state")
    }
  }
  if source.events.length() == 0 || source.events.length() >= 32768 {
    raise Invalid("Session event limit reached; cannot fork this history")
  }
  if self.order.length() >= 32 {
    raise Invalid("Session count limit reached")
  }

  let mut next = self.next_session
  let child_id = match requested_id {
    Some(value) => value
    None => {
      while self.sessions.get("session-\{next}") is Some(_) {
        next += 1
      }
      "session-\{next}"
    }
  }
  if next >= 1000000000 {
    raise Invalid("Session identifier limit reached")
  }
  if self.sessions.get(child_id) is Some(_) {
    raise Invalid("Session already exists: \{child_id}")
  }
  let title = match requested_title {
    Some(value) => value
    None if source.title.length() <= 504 => "Fork of " + source.title
    None => "Fork of previous conversation"
  }

  let rekey = { next_effect: self.next_effect, old_to_new: Map([]), pairs: [], }
  let child = fresh_session(
    child_id,
    title,
    source.system_prompt,
    source.max_steps,
  )
  child.append(
    "session/created",
    object([
      ("id", Json::string(child_id)),
      ("title", Json::string(title)),
      ("system_prompt", Json::string(source.system_prompt)),
      ("max_steps", integer(source.max_steps)),
    ]),
  )
  for index in 1..<source.events.length() {
    let event = source.events[index]
    child.events.push({
      seq: event.seq,
      kind: event.kind,
      turn_id: event.turn_id,
      step: event.step,
      data: rekey.rewrite_event_data(event),
    })
  }
  for call_id, _ in source.used_calls {
    child.used_calls[call_id] = true
  }
  child.turn_id = source.turn_id
  child.step = source.step
  child.append(
    "session/forked",
    object([
      ("parent_session_id", Json::string(source.id)),
      ("source_event_count", integer(source.events.length())),
      ("source_status", Json::string(status_text(source.status))),
      ("source_turn_id", integer(source.turn_id)),
      ("source_step", integer(source.step)),
      (
        "effect_map",
        Json::array(
          rekey.pairs.map(pair => {
            object([
              ("source_id", Json::string(pair.0)),
              ("fork_id", Json::string(pair.1)),
            ])
          }),
        ),
      ),
    ]),
  )
  child.fork_source = Some({
    parent_session_id: source.id,
    source_event_count: source.events.length(),
    source_status: status_text(source.status),
    source_turn_id: source.turn_id,
    source_step: source.step,
    effect_map: rekey.pairs.copy(),
  })
  // The child keeps the verified source transcript but begins a new turn
  // lifecycle. No active effect, approval, or retry is inherited.
  child.status = Idle
  self.next_session = next + 1
  self.next_effect = rekey.next_effect
  self.sessions.set(child_id, child)
  self.order.push(child_id)
  child
}

///|
fn Session::fork_parent_id(self : Session) -> String? {
  self.fork_source.map(source => source.parent_session_id)
}

///|
