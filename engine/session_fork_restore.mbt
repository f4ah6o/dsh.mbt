///|
fn Session::restore_fork_marker(
  self : Session,
  data : Json,
  event_index : Int,
  turn_id : Int,
  step : Int,
  open_turn : Bool,
) -> Unit raise EngineError {
  if open_turn ||
    self.open_step ||
    self.active_effect is Some(_) ||
    self.active_kind is Some(_) ||
    self.active_tool_effect_count() > 0 ||
    self.approval is Some(_) ||
    self.pending_retry_id is Some(_) ||
    !self.calls.is_empty() ||
    self.cursor != 0 ||
    self.schedule_cursor != 0 ||
    (
      self.status != Idle &&
      self.status != Completed &&
      self.status != Failed &&
      self.status != Cancelled
    ) {
    raise Invalid("Fork marker follows unsettled execution state")
  }
  let parent_id = identifier(
    required_string(data, "parent_session_id", max=128),
    "parent_session_id",
  )
  let source_event_count = int_value(
    required_field(data, "source_event_count"),
    "source_event_count",
    1,
    32767,
  )
  let source_status = required_string(data, "source_status", max=32)
  if source_event_count != event_index ||
    source_status != status_text(self.status) ||
    int_value(
      required_field(data, "source_turn_id"),
      "source_turn_id",
      0,
      1000000,
    ) !=
    turn_id ||
    int_value(required_field(data, "source_step"), "source_step", 0, 64) != step ||
    self.turn_id != turn_id ||
    self.step != step {
    raise Invalid("Fork marker does not match its settled history boundary")
  }
  let effect_map : Array[(String, String)] = []
  let sources : Map[String, Bool] = Map([])
  let targets : Map[String, Bool] = Map([])
  for
    pair in array_value(
      required_field(data, "effect_map"),
      "fork effect map",
      32768,
    ) {
    let source_id = required_string(pair, "source_id", max=128)
    let fork_id = required_string(pair, "fork_id", max=128)
    ignore(effect_index(source_id))
    ignore(effect_index(fork_id))
    if sources.get(source_id) is Some(_) || targets.get(fork_id) is Some(_) {
      raise Invalid("Fork effect map contains duplicate identities")
    }
    sources[source_id] = true
    targets[fork_id] = true
    effect_map.push((source_id, fork_id))
  }
  self.fork_source = Some({
    parent_session_id: parent_id,
    source_event_count,
    source_status,
    source_turn_id: turn_id,
    source_step: step,
    effect_map,
  })
  self.status = Idle
  self.retry_count = 0
  self.retry_max_retries = None
  self.retry_initial_delay_ms = None
  self.retry_max_delay_ms = None
  self.pending_retry_id = None
}

///|
fn event_effect_id(event : Event) -> String? {
  if event.kind != EngineEventKind::LlmRequest &&
    event.kind != EngineEventKind::ToolRequest &&
    event.kind != EngineEventKind::ToolCompleted &&
    event.kind != EngineEventKind::AssistantStreamDelta &&
    event.kind != EngineEventKind::LlmRetry &&
    event.kind != EngineEventKind::LlmRetryStarted {
    return None
  }
  match event.data {
    Json::Object(data) =>
      match data.get("effect_id") {
        Some(Json::String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn remap_inherited_event_data(
  event : Event,
  mapping : Map[String, String],
) -> Json raise EngineError {
  match event_effect_id(event) {
    None => detached(event.data)
    Some(source_id) => {
      let fork_id = match mapping.get(source_id) {
        Some(value) => value
        None => raise Invalid("Fork effect map omits a source effect")
      }
      match event.data {
        Json::Object(values) => {
          let result = values.copy()
          result.set("effect_id", Json::string(fork_id))
          if event.kind == EngineEventKind::LlmRetry ||
            event.kind == EngineEventKind::LlmRetryStarted {
            let retry = int_value(
              required_field(event.data, "retry"),
              "retry",
              1,
              MAX_PROVIDER_RETRIES,
            )
            if required_string(event.data, "retry_id", max=128) !=
              "retry-\{source_id}-\{retry}" {
              raise Invalid("Source retry identity is not canonical")
            }
            result.set("retry_id", Json::string("retry-\{fork_id}-\{retry}"))
          }
          Json::object(result)
        }
        _ => raise Invalid("Source effect event data must be an object")
      }
    }
  }
}

///|
fn validate_fork_lineage(
  sessions : Map[String, Session],
  order : Array[String],
) -> Unit raise EngineError {
  for child_id in order {
    let child = sessions.get(child_id).unwrap()
    match child.fork_source {
      None => ()
      Some(source) => {
        if source.parent_session_id == child_id {
          raise Invalid("Session cannot be its own fork parent")
        }
        let parent = match sessions.get(source.parent_session_id) {
          Some(value) => value
          None => raise Invalid("Fork parent is missing from the snapshot")
        }
        if parent.imported {
          raise Invalid("Fork parent cannot be an imported history")
        }
        if child.system_prompt != parent.system_prompt ||
          child.max_steps != parent.max_steps {
          raise Invalid("Fork creation settings differ from its parent")
        }
        if source.source_event_count > parent.events.length() ||
          source.source_event_count >= child.events.length() ||
          child.events[source.source_event_count].kind !=
          EngineEventKind::SessionForked {
          raise Invalid("Fork marker does not match its source prefix")
        }
        if child.events[source.source_event_count].seq !=
          source.source_event_count ||
          child.events[source.source_event_count].turn_id !=
          source.source_turn_id ||
          child.events[source.source_event_count].step != source.source_step ||
          parent.events[source.source_event_count - 1].turn_id !=
          source.source_turn_id ||
          parent.events[source.source_event_count - 1].step !=
          source.source_step {
          raise Invalid("Fork source prefix has a different boundary")
        }
        let mapping : Map[String, String] = Map([])
        let targets : Map[String, Bool] = Map([])
        for (source_id, fork_id) in source.effect_map {
          if mapping.get(source_id) is Some(_) ||
            targets.get(fork_id) is Some(_) {
            raise Invalid("Fork effect map contains duplicate identities")
          }
          ignore(effect_index(source_id))
          ignore(effect_index(fork_id))
          mapping[source_id] = fork_id
          targets[fork_id] = true
        }
        let source_effects : Map[String, Bool] = Map([])
        for index in 1..<source.source_event_count {
          let inherited = parent.events[index]
          match event_effect_id(inherited) {
            Some(effect_id) => {
              ignore(effect_index(effect_id))
              source_effects[effect_id] = true
            }
            None => ()
          }
          let copied = child.events[index]
          if copied.seq != inherited.seq ||
            copied.kind != inherited.kind ||
            copied.turn_id != inherited.turn_id ||
            copied.step != inherited.step ||
            copied.data != remap_inherited_event_data(inherited, mapping) {
            raise Invalid(
              "Fork history differs from its validated parent prefix",
            )
          }
        }
        if mapping.length() != source_effects.length() {
          raise Invalid("Fork effect map does not match its source prefix")
        }
        for effect_id, _ in source_effects {
          if mapping.get(effect_id) is None {
            raise Invalid("Fork effect map omits a source effect")
          }
        }
      }
    }
  }
  for start in order {
    let seen : Map[String, Bool] = Map([])
    let mut current : String? = Some(start)
    while current is Some(id) {
      if seen.get(id) is Some(_) {
        raise Invalid("Fork lineage contains a cycle")
      }
      seen[id] = true
      let session = match sessions.get(id) {
        Some(value) => value
        None => raise Invalid("Fork lineage references a missing session")
      }
      current = session.fork_source.map(source => source.parent_session_id)
    }
  }
}
