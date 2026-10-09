///|
/// Read-only calls may overlap only within this bounded rolling pool. Writes
/// and shell effects remain single-call barriers.
const MAX_PARALLEL_TOOL_EFFECTS : Int = 4

///|
fn Session::active_tool_effect_count(self : Session) -> Int {
  let mut count = 0
  for _, _ in self.active_tool_effects {
    count += 1
  }
  count
}

///|
fn Session::call_by_id(self : Session, id : String) -> ToolCall? {
  for call in self.calls {
    if call.id == id {
      return Some(call)
    }
  }
  None
}

///|
fn Session::call_index(self : Session, id : String) -> Int? {
  let mut index = 0
  for call in self.calls {
    if call.id == id {
      return Some(index)
    }
    index += 1
  }
  None
}

///|
fn Session::stage_local_tool_result(
  self : Session,
  call : ToolCall,
  content : String,
  is_error : Bool,
) -> Unit {
  call.stage = Completed
  call.effect_id = None
  call.completed_content = Some(content)
  call.completed_error = Some(is_error)
  self.append(
    "tool/completed",
    object([
      ("source", Json::string("local")),
      ("call_id", Json::string(call.id)),
      ("content", Json::string(content)),
      ("is_error", boolean(is_error)),
    ]),
  )
}

///|
fn Session::stage_interrupted_tool_result(
  self : Session,
  call : ToolCall,
  effect_id : String?,
  content : String,
) -> Unit {
  call.stage = Completed
  call.effect_id = None
  call.completed_content = Some(content)
  call.completed_error = Some(true)
  let data = Map::from_array([
    ("source", Json::string("interrupted")),
    ("call_id", Json::string(call.id)),
    ("content", Json::string(content)),
    ("is_error", boolean(true)),
  ])
  match effect_id {
    Some(id) => data.set("effect_id", Json::string(id))
    None => ()
  }
  self.append("tool/completed", Json::object(data))
}

///|
fn Session::commit_completed_tool_result(
  self : Session,
  call : ToolCall,
) -> Unit {
  if self.cursor >= self.calls.length() ||
    self.calls[self.cursor].id != call.id ||
    call.stage != Completed {
    abort("Tool result commit is not at the model-order cursor")
  }
  self.append(
    "tool/result",
    object([
      ("role", Json::string("tool")),
      ("tool_call_id", Json::string(call.id)),
      ("content", Json::string(call.completed_content.unwrap())),
      ("is_error", boolean(call.completed_error.unwrap())),
    ]),
  )
  call.stage = Settled
  call.effect_id = None
  call.completed_content = None
  call.completed_error = None
  self.cursor += 1
}

///|
fn Session::commit_ready_tool_results(self : Session) -> Unit {
  while self.cursor < self.calls.length() {
    let call = self.calls[self.cursor]
    if call.stage != Completed {
      return
    }
    self.commit_completed_tool_result(call)
  }
}

///|
fn Engine::retire_tool_effect(
  self : Engine,
  session : Session,
  effect_id : String,
) -> Unit {
  self.effects.remove(effect_id)
  session.active_tool_effects.remove(effect_id)
  let kept = self.queued.filter(id => self.effects.get(id) is Some(_))
  self.queued.clear()
  for id in kept {
    self.queued.push(id)
  }
}

///|
fn Engine::dispatch_tool(
  self : Engine,
  session : Session,
  call : ToolCall,
  arguments : Json,
) -> Unit {
  if self.next_effect >= 1000000000 {
    self.terminate(
      session,
      Failed,
      "effect_limit",
      "Effect identifier limit reached",
    )
    return
  }
  call.stage = Dispatched
  let effect_id = self.emit_effect(
    session,
    ToolExecution,
    object([
      ("name", Json::string(call.name)),
      ("arguments", detached(arguments)),
      ("call_id", Json::string(call.id)),
    ]),
    Some(call.id),
  )
  call.effect_id = Some(effect_id)
}

///|
fn Engine::stage_host_tool_result(
  self : Engine,
  session : Session,
  call : ToolCall,
  effect_id : String,
  content : String,
  is_error : Bool,
) -> Unit {
  self.retire_tool_effect(session, effect_id)
  call.stage = Completed
  call.effect_id = None
  call.completed_content = Some(content)
  call.completed_error = Some(is_error)
  session.append(
    "tool/completed",
    object([
      ("source", Json::string("effect")),
      ("call_id", Json::string(call.id)),
      ("effect_id", Json::string(effect_id)),
      ("content", Json::string(content)),
      ("is_error", boolean(is_error)),
    ]),
  )
  session.commit_ready_tool_results()
  self.advance_tools(session)
}

///|
/// Record that the host effect succeeded before running advisory post-tool
/// hooks. The active effect stays fenced until the host supplies its final
/// hook-adjusted result or the session is cancelled/restored.
fn Session::stage_host_tool_outcome(
  self : Session,
  call : ToolCall,
  effect_id : String,
  content : String,
  is_error : Bool,
) -> Unit {
  call.stage = OutcomeKnown
  call.completed_content = Some(content)
  call.completed_error = Some(is_error)
  self.append(
    "tool/completed",
    object([
      ("source", Json::string("effect-known")),
      ("call_id", Json::string(call.id)),
      ("effect_id", Json::string(effect_id)),
      ("content", Json::string(content)),
      ("is_error", boolean(is_error)),
    ]),
  )
}

///|
fn Engine::complete_tool_effect(
  self : Engine,
  session : Session,
  effect : Effect,
  effect_id : String,
  result : Json,
) -> Unit raise EngineError {
  let call_id = match effect.call_id {
    Some(call_id) => call_id
    None => raise Invalid("Tool effect has no call identity")
  }
  if session.active_tool_effects.get(effect_id) != Some(call_id) {
    raise Invalid("Tool effect is no longer active for this session")
  }
  let call = match session.call_by_id(call_id) {
    Some(call) => call
    None => raise Invalid("Tool effect call is missing")
  }
  if (call.stage != Dispatched && call.stage != OutcomeKnown) ||
    call.effect_id != Some(effect_id) {
    raise Invalid("Tool effect no longer matches its call")
  }
  let is_error = !bool_value(required_field(result, "ok"), "ok")
  let content = if is_error {
    required_string(result, "error")
  } else {
    required_string(result, "content")
  }
  self.stage_host_tool_result(session, call, effect_id, content, is_error)
}

///|
fn Engine::record_effect_outcome_impl(
  self : Engine,
  effect_id : String,
  result : Json,
) -> Result[Json, String] {
  try {
    let effect = match self.effects.get(effect_id) {
      Some(effect) => effect
      None => raise Invalid("Unknown or settled effect: \{effect_id}")
    }
    let session = self.lookup(effect.session_id)
    let call_id = match effect.call_id {
      Some(call_id) => call_id
      None => raise Invalid("Tool effect has no call identity")
    }
    if effect.kind != ToolExecution ||
      session.status != Running ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step ||
      session.active_tool_effects.get(effect_id) != Some(call_id) {
      raise Invalid("Tool effect is no longer active for this session")
    }
    let call = match session.call_by_id(call_id) {
      Some(call) => call
      None => raise Invalid("Tool effect call is missing")
    }
    if call.stage != Dispatched || call.effect_id != Some(effect_id) {
      raise Invalid("Tool effect no longer matches its call")
    }
    let is_error = !bool_value(required_field(result, "ok"), "ok")
    let content = if is_error {
      required_string(result, "error")
    } else {
      required_string(result, "content")
    }
    session.stage_host_tool_outcome(call, effect_id, content, is_error)
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
fn Engine::start_approved_tool(
  self : Engine,
  session : Session,
  call : ToolCall,
  arguments : Json,
) -> Unit {
  if self.next_effect >= 1000000000 {
    self.terminate(
      session,
      Failed,
      "effect_limit",
      "Effect identifier limit reached",
    )
    return
  }
  self.dispatch_tool(session, call, arguments)
}

///|
fn Engine::advance_tools(self : Engine, session : Session) -> Unit {
  if session.status != Running || session.active_effect is Some(_) {
    return
  }
  while session.schedule_cursor < session.calls.length() {
    let call = session.calls[session.schedule_cursor]
    if call.kind == CustomCall {
      // The current capability registry accepts JSON-schema function calls.
      // Preserve custom text calls in the transcript, but never coerce their
      // input into a function argument object or dispatch by a colliding name.
      if session.active_tool_effect_count() > 0 {
        return
      }
      session.parallel_group = false
      session.begin_tool(call)
      session.schedule_cursor += 1
      session.stage_local_tool_result(
        call, "Unsupported custom tool input: local custom-tool execution is not configured for {call.name}",
        true,
      )
      session.commit_ready_tool_results()
      continue
    }
    if session.parallel_group {
      if session.active_tool_effect_count() >= MAX_PARALLEL_TOOL_EFFECTS {
        return
      }
      let call = session.calls[session.schedule_cursor]
      let tool = match self.find_tool(call.name) {
        Some(tool) => Some(tool)
        None => None
      }
      match tool {
        None => {
          if session.active_tool_effect_count() > 0 {
            return
          }
          session.parallel_group = false
        }
        Some(tool) => {
          let arguments = try {
            let arguments = parse_arguments(call.arguments)
            validate_arguments(tool.input_schema, arguments)
            Some(arguments)
          } catch {
            Invalid(_) => {
              if session.active_tool_effect_count() > 0 {
                return
              }
              session.parallel_group = false
              None
            }
          }
          match arguments {
            None => ()
            Some(arguments) if tool.effect == Read => {
              session.begin_tool(call)
              session.schedule_cursor += 1
              self.dispatch_tool(session, call, arguments)
              if session.status != Running {
                return
              }
            }
            Some(_) => {
              if session.active_tool_effect_count() > 0 {
                return
              }
              session.parallel_group = false
            }
          }
        }
      }
      continue
    }

    let call = session.calls[session.schedule_cursor]
    session.begin_tool(call)
    session.schedule_cursor += 1
    let tool = match self.find_tool(call.name) {
      Some(tool) => Some(tool)
      None => None
    }
    match tool {
      None => {
        session.stage_local_tool_result(
          call,
          "Unknown tool: \{call.name}",
          true,
        )
        session.commit_ready_tool_results()
      }
      Some(tool) => {
        let arguments = try {
          let arguments = parse_arguments(call.arguments)
          validate_arguments(tool.input_schema, arguments)
          Some(arguments)
        } catch {
          Invalid(message) => {
            session.stage_local_tool_result(
              call,
              "Invalid tool arguments: \{message}",
              true,
            )
            session.commit_ready_tool_results()
            None
          }
        }
        match arguments {
          None => ()
          Some(arguments) if tool.effect == Read => {
            session.parallel_group = true
            self.dispatch_tool(session, call, arguments)
            if session.status != Running {
              return
            }
          }
          Some(arguments) => {
            call.stage = Waiting
            session.approval = Some({
              call_id: call.id,
              name: call.name,
              arguments,
            })
            session.status = AwaitingApproval
            session.append(
              "tool/approval/requested",
              object([
                ("call_id", Json::string(call.id)),
                ("name", Json::string(call.name)),
                ("arguments", detached(arguments)),
              ]),
            )
            return
          }
        }
      }
    }
  }

  if session.active_tool_effect_count() > 0 {
    return
  }
  if session.cursor == session.calls.length() {
    session.calls.clear()
    session.cursor = 0
    session.schedule_cursor = 0
    session.parallel_group = false
    session.append("step/end", object([("reason", Json::string("tool_calls"))]))
    session.open_step = false
    self.start_step(session)
  }
}
