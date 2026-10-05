///|
/// Build an isolated engine with a fixed tool inventory. Invalid or duplicate
/// descriptors fail closed: invoke returns a configuration error.
pub fn Engine::new(tools : Array[Json]) -> Engine {
  let parsed : Array[Tool] = []
  let mut config_error : String? = None
  try {
    if tools.length() > 128 {
      raise Invalid("Too many tools")
    }
    let names : Map[String, Bool] = Map([])
    for raw in tools {
      let tool = parse_tool(checked_copy(raw))
      if names.get(tool.name) is Some(_) {
        raise Invalid("Duplicate tool: \{tool.name}")
      }
      names.set(tool.name, true)
      parsed.push(tool)
    }
  } catch {
    Invalid(message) => config_error = Some(message)
  }
  {
    tools: parsed,
    sessions: Map([]),
    order: [],
    effects: Map([]),
    queued: [],
    next_session: 1,
    next_effect: 1,
    config_error,
  }
}

///|
/// Invoke one semantic session operation. Invalid input and busy-session
/// conflicts leave the existing state untouched.
fn Engine::invoke_impl(
  self : Engine,
  operation : String,
  input : Json,
) -> Result[Json, String] {
  try {
    match self.config_error {
      Some(message) => raise Invalid("Invalid tool configuration: \{message}")
      None => ()
    }
    let input = checked_copy(input)
    ignore(fields(input))
    let value = match operation {
      "session_create" => self.create_session(input).json()
      "session_list" =>
        Json::array(self.order.map(id => self.lookup(id).json()))
      "session_get" => self.input_session(input).json()
      "session_send" => {
        let session = self.input_session(input)
        let prompt = required_string(input, "prompt", max=16384)
        if prompt.length() == 0 {
          raise Invalid("prompt must not be empty")
        }
        if session.is_busy() {
          raise Invalid("Session is busy")
        }
        if session.turn_id >= 1000000 {
          raise Invalid("Session turn limit reached")
        }
        // Reserve enough event slots for a full worst-case admitted turn,
        // including denied calls and cancellation closure.
        if session.events.length() + session.max_steps * 112 + 16 > 32768 {
          raise Invalid("Session event limit reached; create a new session")
        }
        session.turn_id += 1
        session.step = 0
        session.status = Running
        session.calls.clear()
        session.cursor = 0
        session.append("turn/start", object([]))
        session.append(
          "user/message",
          object([
            ("role", Json::string("user")),
            ("content", Json::string(prompt)),
          ]),
        )
        self.start_step(session)
        session.json()
      }
      "session_cancel" => {
        let session = self.input_session(input)
        if session.is_busy() {
          self.terminate(session, Cancelled, "cancelled", "Cancelled by user")
        } else if session.status == Idle {
          session.status = Cancelled
          session.append("session/cancelled", object([]))
        }
        session.json()
      }
      "tool_approve" => {
        let session = self.input_session(input)
        let call_id = required_string(input, "call_id", max=128)
        let approved = bool_value(required_field(input, "approved"), "approved")
        let approval = match session.approval {
          Some(approval) => approval
          None => raise Invalid("Session has no pending approval")
        }
        if session.status != AwaitingApproval || call_id != approval.call_id {
          raise Invalid("Approval does not match the pending call")
        }
        let call = session.calls[session.cursor]
        session.append(
          "tool/approval/resolved",
          object([
            ("call_id", Json::string(call_id)),
            ("approved", boolean(approved)),
          ]),
        )
        session.approval = None
        session.status = Running
        call.stage = Called
        if approved {
          self.dispatch_tool(session, call, approval.arguments)
        } else {
          session.tool_result(call, "Tool execution denied by user", true)
          self.advance_tools(session)
        }
        session.json()
      }
      _ => raise Invalid("Unknown operation: \{operation}")
    }
    Ok(value)
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
fn Engine::lookup(self : Engine, id : String) -> Session raise EngineError {
  match self.sessions.get(id) {
    Some(session) => session
    None => raise Invalid("Session not found: \{id}")
  }
}

///|
fn Engine::input_session(
  self : Engine,
  input : Json,
) -> Session raise EngineError {
  self.lookup(
    identifier(required_string(input, "session_id", max=128), "session_id"),
  )
}

///|
fn Engine::create_session(
  self : Engine,
  input : Json,
) -> Session raise EngineError {
  if self.order.length() >= 32 {
    raise Invalid("Session count limit reached")
  }
  let title = optional_string(input, "title", "New session", max=512)
  let system_prompt = optional_string(
    input,
    "system_prompt",
    "You are a helpful coding assistant.",
    max=16384,
  )
  let max_steps = match fields(input).get("max_steps") {
    None => 16
    Some(value) => int_value(value, "max_steps", 1, 64)
  }
  let mut next = self.next_session
  let id = match fields(input).get("id") {
    Some(value) => identifier(string_value(value, "id", max=128), "id")
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
  if self.sessions.get(id) is Some(_) {
    raise Invalid("Session already exists: \{id}")
  }
  let session = fresh_session(id, title, system_prompt, max_steps)
  session.append(
    "session/created",
    object([
      ("id", Json::string(id)),
      ("title", Json::string(title)),
      ("system_prompt", Json::string(system_prompt)),
      ("max_steps", integer(max_steps)),
    ]),
  )
  self.next_session = next + 1
  self.sessions.set(id, session)
  self.order.push(id)
  session
}

///|
fn Session::append(self : Session, kind : String, data : Json) -> Unit {
  self.events.push({
    seq: self.events.length(),
    kind,
    turn_id: self.turn_id,
    step: self.step,
    data,
  })
}

///|
fn Session::messages(self : Session) -> Array[Json] {
  self.events.filter_map(event => {
    match event.kind {
      "user/message" | "tool/result" => Some(detached(event.data))
      "assistant/message" =>
        match event.data {
          Json::Object(data) => data.get("message").map(detached)
          _ => None
        }
      _ => None
    }
  })
}

///|
fn Event::json(self : Event) -> Json {
  object([
    ("seq", integer(self.seq)),
    ("type", Json::string(self.kind)),
    ("turn_id", integer(self.turn_id)),
    ("step", integer(self.step)),
    ("data", detached(self.data)),
  ])
}

///|
fn Session::json(self : Session) -> Json {
  let value = Map::from_array([
    ("id", Json::string(self.id)),
    ("title", Json::string(self.title)),
    ("system_prompt", Json::string(self.system_prompt)),
    ("max_steps", integer(self.max_steps)),
    ("status", Json::string(status_text(self.status))),
    ("turn_id", integer(self.turn_id)),
    ("step", integer(self.step)),
    ("events", Json::array(self.events.map(Event::json))),
    ("messages", Json::array(self.messages())),
  ])
  match self.approval {
    Some(approval) =>
      value.set(
        "pending_approval",
        object([
          ("call_id", Json::string(approval.call_id)),
          ("name", Json::string(approval.name)),
          ("arguments", detached(approval.arguments)),
        ]),
      )
    None => ()
  }
  Json::object(value)
}

///|
fn Engine::emit_effect(
  self : Engine,
  session : Session,
  kind : EffectKind,
  request : Json,
) -> Unit {
  let id = "effect-\{self.next_effect}"
  self.next_effect += 1
  let effect = {
    id,
    kind,
    session_id: session.id,
    turn_id: session.turn_id,
    step: session.step,
    request,
  }
  self.effects.set(id, effect)
  self.queued.push(id)
  session.active_effect = Some(id)
  session.active_kind = Some(kind)
  let kind_name = match kind {
    Llm => "llm/request"
    ToolExecution => "tool/request"
  }
  let data = Map::from_array([("effect_id", Json::string(id))])
  if kind == ToolExecution {
    data.set("call_id", Json::string(session.calls[session.cursor].id))
  }
  session.append(kind_name, Json::object(data))
}

///|
fn Engine::start_step(self : Engine, session : Session) -> Unit {
  if session.step >= session.max_steps {
    self.terminate(session, Failed, "max_steps", "Maximum model steps reached")
    return
  }
  if self.next_effect >= 1000000000 {
    self.terminate(
      session,
      Failed,
      "effect_limit",
      "Effect identifier limit reached",
    )
    return
  }
  session.step += 1
  session.open_step = true
  session.status = Running
  session.append("step/start", object([]))
  self.emit_effect(
    session,
    Llm,
    object([
      ("system", Json::string(session.system_prompt)),
      ("messages", Json::array(session.messages())),
      ("tools", Json::array(self.tools.map(Tool::json))),
    ]),
  )
}

///|
fn Engine::find_tool(self : Engine, name : String) -> Tool? {
  for tool in self.tools {
    if tool.name == name {
      return Some(tool)
    }
  }
  None
}

///|
fn ToolCall::json(self : ToolCall) -> Json {
  object([
    ("id", Json::string(self.id)),
    ("name", Json::string(self.name)),
    ("arguments", Json::string(self.arguments)),
  ])
}

///|
fn Session::begin_tool(self : Session, call : ToolCall) -> Unit {
  call.stage = Called
  self.append("tool/call", call.json())
}

///|
fn Session::tool_result(
  self : Session,
  call : ToolCall,
  content : String,
  is_error : Bool,
) -> Unit {
  self.append(
    "tool/result",
    object([
      ("role", Json::string("tool")),
      ("tool_call_id", Json::string(call.id)),
      ("content", Json::string(content)),
      ("is_error", boolean(is_error)),
    ]),
  )
  call.stage = Settled
  self.cursor += 1
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
  self.emit_effect(
    session,
    ToolExecution,
    object([
      ("name", Json::string(call.name)),
      ("arguments", detached(arguments)),
      ("call_id", Json::string(call.id)),
    ]),
  )
}

///|
fn Engine::advance_tools(self : Engine, session : Session) -> Unit {
  while session.cursor < session.calls.length() {
    let call = session.calls[session.cursor]
    session.begin_tool(call)
    let tool = match self.find_tool(call.name) {
      Some(tool) => tool
      None => {
        session.tool_result(call, "Unknown tool: \{call.name}", true)
        continue
      }
    }
    let arguments = try {
      let arguments = parse_arguments(call.arguments)
      validate_arguments(tool.input_schema, arguments)
      arguments
    } catch {
      Invalid(message) => {
        session.tool_result(call, "Invalid tool arguments: \{message}", true)
        continue
      }
    }
    if tool.effect == Read {
      self.dispatch_tool(session, call, arguments)
    } else {
      call.stage = Waiting
      session.approval = Some({ call_id: call.id, name: call.name, arguments, })
      session.status = AwaitingApproval
      session.append(
        "tool/approval/requested",
        object([
          ("call_id", Json::string(call.id)),
          ("name", Json::string(call.name)),
          ("arguments", detached(arguments)),
        ]),
      )
    }
    return
  }
  session.calls.clear()
  session.cursor = 0
  session.append("step/end", object([("reason", Json::string("tool_calls"))]))
  session.open_step = false
  self.start_step(session)
}

///|
fn Engine::retire_effect(self : Engine, session : Session) -> Unit {
  match session.active_effect {
    Some(id) => self.effects.remove(id)
    None => ()
  }
  session.active_effect = None
  session.active_kind = None
  let kept = self.queued.filter(id => self.effects.get(id) is Some(_))
  self.queued.clear()
  for id in kept {
    self.queued.push(id)
  }
}

///|
fn Engine::terminate(
  self : Engine,
  session : Session,
  status : Status,
  reason : String,
  error : String,
) -> Unit {
  if session.active_kind == Some(Llm) {
    session.append(
      "assistant/attempt",
      object([("error", Json::string(error))]),
    )
  }
  self.retire_effect(session)
  session.approval = None
  while session.cursor < session.calls.length() {
    let call = session.calls[session.cursor]
    if call.stage == Pending {
      session.begin_tool(call)
    }
    session.tool_result(call, error, true)
  }
  session.calls.clear()
  session.cursor = 0
  if session.open_step {
    session.append("step/end", object([("reason", Json::string(reason))]))
    session.open_step = false
  }
  session.status = status
  session.append(
    "turn/end",
    object([("reason", Json::string(reason)), ("error", Json::string(error))]),
  )
}

///|
/// Drain newly queued effects exactly once. A taken effect remains outstanding
/// until complete/cancel; repeated calls do not start duplicate work.
pub fn Engine::take_effects(self : Engine) -> Array[Json] {
  let result = self.queued.filter_map(id => {
    self.effects
    .get(id)
    .map(effect => {
      object([
        ("id", Json::string(effect.id)),
        (
          "kind",
          Json::string(
            match effect.kind {
              Llm => "llm"
              ToolExecution => "tool"
            },
          ),
        ),
        ("session_id", Json::string(effect.session_id)),
        ("request", detached(effect.request)),
      ])
    })
  })
  self.queued.clear()
  result
}

///|
/// Settle one outstanding host effect. Unknown, stale, duplicate, and malformed
/// completions return Err without committing any partial result.
fn Engine::complete_impl(
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
    if session.status != Running ||
      session.active_effect != Some(effect_id) ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step {
      raise Invalid("Stale effect completion")
    }
    let result = checked_copy(result)
    let ok = bool_value(required_field(result, "ok"), "ok")
    if !ok {
      let error = required_string(result, "error")
      match effect.kind {
        Llm =>
          // terminate still sees the live LLM effect and logs its failed attempt.
          self.terminate(session, Failed, "provider_error", error)
        ToolExecution => {
          self.retire_effect(session)
          session.tool_result(session.calls[session.cursor], error, true)
          self.advance_tools(session)
        }
      }
    } else {
      match effect.kind {
        Llm => {
          let completion = parse_llm_completion(result)
          for call in completion.calls {
            if session.used_calls.get(call.id) is Some(_) {
              raise Invalid("Duplicate tool call id: \{call.id}")
            }
          }
          self.retire_effect(session)
          let message = Map::from_array([
            ("role", Json::string("assistant")),
            ("content", Json::string(completion.content)),
          ])
          match completion.reasoning {
            Some(text) => message.set("reasoning", Json::string(text))
            None => ()
          }
          if !completion.calls.is_empty() {
            message.set(
              "tool_calls",
              Json::array(completion.calls.map(ToolCall::json)),
            )
          }
          let data = Map::from_array([
            ("message", Json::object(message)),
            ("finish_reason", Json::string(completion.finish_reason)),
          ])
          match completion.usage {
            Some(usage) => data.set("usage", usage)
            None => ()
          }
          session.append("assistant/message", Json::object(data))
          for call in completion.calls {
            session.used_calls.set(call.id, true)
            session.calls.push(call)
          }
          if completion.finish_reason == "length" {
            self.terminate(
              session,
              Failed,
              "max_tokens",
              "Model output reached its token limit",
            )
          } else if completion.calls.is_empty() {
            session.append(
              "step/end",
              object([("reason", Json::string("stop"))]),
            )
            session.open_step = false
            session.status = Completed
            session.append(
              "turn/end",
              object([("reason", Json::string("completed"))]),
            )
          } else {
            self.advance_tools(session)
          }
        }
        ToolExecution => {
          let content = required_string(result, "content")
          self.retire_effect(session)
          session.tool_result(session.calls[session.cursor], content, false)
          self.advance_tools(session)
        }
      }
    }
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
fn parse_calls(value : Json) -> Array[ToolCall] raise EngineError {
  let calls = array_value(value, "tool_calls", 16)
  let seen : Map[String, Bool] = Map([])
  calls.map(raw => {
    let id = identifier(required_string(raw, "id", max=128), "call id")
    let name = identifier(required_string(raw, "name", max=128), "tool name")
    let arguments = required_string(raw, "arguments")
    if seen.get(id) is Some(_) {
      raise Invalid("Duplicate tool call id: \{id}")
    }
    seen.set(id, true)
    { id, name, arguments, stage: Pending, }
  })
}

///|
fn parse_llm_completion(value : Json) -> LlmCompletion raise EngineError {
  let content = required_string(value, "content")
  let reasoning = match fields(value).get("reasoning") {
    Some(value) => Some(string_value(value, "reasoning"))
    None => None
  }
  let calls = match fields(value).get("tool_calls") {
    Some(value) => parse_calls(value)
    None => []
  }
  let finish_reason = required_string(value, "finish_reason", max=16)
  if finish_reason != "stop" &&
    finish_reason != "tool_calls" &&
    finish_reason != "length" {
    raise Invalid("Unsupported finish_reason")
  }
  if (finish_reason == "tool_calls") != !calls.is_empty() {
    raise Invalid("finish_reason does not match tool_calls")
  }
  let usage = fields(value).get("usage")
  match usage {
    Some(usage) =>
      for key, count in fields(usage) {
        ignore(int_value(count, "usage.\{key}", 0, 1000000000))
      }
    None => ()
  }
  { content, reasoning, calls, finish_reason, usage, }
}
