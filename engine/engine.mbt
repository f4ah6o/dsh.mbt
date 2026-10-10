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
fn Engine::apply_command_impl(
  self : Engine,
  command : EngineCommand,
) -> Result[Json, String] {
  try {
    match self.config_error {
      Some(message) => raise Invalid("Invalid tool configuration: \{message}")
      None => ()
    }
    let value = match command {
      CreateSession(id, title, system_prompt, max_steps) =>
        self.create_session(id, title, system_prompt, max_steps).json()
      ListSessions => Json::array(self.order.map(id => self.lookup(id).json()))
      ImportSession(jsonl) => self.import_upstream_v4(jsonl).json()
      GetSession(id) => self.lookup(id.as_string()).json()
      ForkSession(id, child_id, title) =>
        self.fork_session(id.as_string(), child_id, title).json()
      SendPrompt(id, prompt) => {
        let session = self.lookup(id.as_string())
        if session.imported {
          raise Invalid(
            "Imported Session v4 histories are read-only and cannot be continued",
          )
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
        session.schedule_cursor = 0
        session.parallel_group = false
        session.active_tool_effects.clear()
        session.todos = None
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
      CancelSession(id) => {
        let session = self.lookup(id.as_string())
        if session.imported {
          raise Invalid(
            "Imported Session v4 histories are read-only and cannot be cancelled",
          )
        }
        if session.is_busy() {
          self.terminate(session, Cancelled, "cancelled", "Cancelled by user")
        } else if session.status == Idle {
          session.status = Cancelled
          session.append("session/cancelled", object([]))
        }
        session.json()
      }
      PruneToolResults(id, config) =>
        self.prune_session_tool_results(id, config)
      ApproveTool(id, typed_call_id, approved) => {
        let session = self.lookup(id.as_string())
        let call_id = typed_call_id.as_string()
        let approval = match session.approval {
          Some(approval) => approval
          None => raise Invalid("Session has no pending approval")
        }
        if session.status != AwaitingApproval || call_id != approval.call_id {
          raise Invalid("Approval does not match the pending call")
        }
        let call = match session.call_by_id(approval.call_id) {
          Some(call) => call
          None => raise Invalid("Pending approval call is missing")
        }
        session.append(
          "tool/approval/resolved",
          object([
            ("call_id", Json::string(call_id)),
            ("approved", boolean(approved)),
          ]),
        )
        session.approval = None
        session.status = Running
        if approved {
          call.stage = Approved
          self.start_approved_tool(session, call, approval.arguments)
        } else {
          call.stage = Denied
          session.stage_local_tool_result(
            call, "Tool execution denied by user", true,
          )
          session.commit_ready_tool_results()
          self.advance_tools(session)
        }
        session.json()
      }
    }
    Ok(value)
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Commit a bounded text/reasoning delta only while its exact LLM effect is
/// current. Provisional content is durable but excluded from model context.
pub fn Engine::project_stream(
  self : Engine,
  effect_id : String,
  content : String,
  reasoning : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  match candidate.project_stream_impl(effect_id, content, reasoning) {
    Err(error) => Err(error)
    Ok(value) => {
      if !candidate.within_capacity() {
        return Err(CAPACITY_ERROR)
      }
      self.adopt(candidate)
      Ok(value)
    }
  }
}

///|
pub fn Engine::project_effect_stream(
  self : Engine,
  effect_id : EffectId,
  content : String,
  reasoning : String,
) -> Result[Json, String] {
  self.project_stream(effect_id.as_string(), content, reasoning)
}

///|
fn Engine::project_stream_impl(
  self : Engine,
  effect_id : String,
  content : String,
  reasoning : String,
) -> Result[Json, String] {
  try {
    let effect = match self.effects.get(effect_id) {
      Some(effect) => effect
      None => raise Invalid("Unknown or settled stream effect")
    }
    let session = self.lookup(effect.session_id)
    if session.imported ||
      session.status != Running ||
      session.active_effect != Some(effect_id) ||
      session.active_kind != Some(Llm) ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step ||
      !session.open_step {
      raise Invalid("Stale or misplaced stream delta")
    }
    if content.is_empty() && reasoning.is_empty() {
      raise Invalid("Stream delta must contain text or reasoning")
    }
    if session.pending_retry_id is Some(_) {
      raise Invalid("Stream delta arrived while a retry was waiting")
    }
    if content.length() + reasoning.length() > STREAM_DELTA_CAPACITY {
      raise Invalid("Stream delta batch exceeds its 4096-character limit")
    }
    if session.events.length() + session.max_steps * 112 + 16 > 32768 {
      raise Invalid("Session event limit reached; create a new session")
    }
    session.append(
      "assistant/stream_delta",
      object([
        ("effect_id", Json::string(effect_id)),
        ("content", Json::string(content)),
        ("reasoning", Json::string(reasoning)),
      ]),
    )
    Ok(session.json())
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
fn Engine::create_session(
  self : Engine,
  requested_id : String?,
  title : String,
  system_prompt : String,
  requested_max_steps : Int?,
) -> Session raise EngineError {
  if self.order.length() >= 32 {
    raise Invalid("Session count limit reached")
  }
  let max_steps = requested_max_steps.unwrap_or(16)
  let mut next = self.next_session
  let id = match requested_id {
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
    kind: EngineEventKind::from_wire(kind),
    turn_id: self.turn_id,
    step: self.step,
    data,
  })
}

///|
fn transcript_user_message(data : Json) -> Json {
  let values = match data {
    Json::Object(fields) => fields.copy()
    _ => return detached(data)
  }
  let is_hook_context = match values.get("source") {
    Some(Json::Object(source)) =>
      source.length() == 1 &&
      source.get("kind") == Some(Json::string("hooks-claude-code"))
    _ => false
  }
  if !is_hook_context {
    return Json::object(values)
  }
  let blocks = match values.get("content") {
    Some(Json::Array(blocks)) => blocks
    _ => return Json::object(values)
  }
  let text = StringBuilder()
  for index, block in blocks {
    let block_text = match block {
      Json::Object(fields) => fields.get("text")
      _ => None
    }
    match block_text {
      Some(Json::String(value)) => {
        if index > 0 {
          text.write_string("\n")
        }
        text.write_string(value)
      }
      _ => ()
    }
  }
  values["content"] = Json::string(text.to_string())
  values["display_label"] = Json::string("フック補足")
  Json::object(values)
}

///|
fn Session::messages(self : Session) -> Array[Json] {
  if self.imported {
    return imported_messages(self.events)
  }
  let finalized : Map[String, Bool] = Map([])
  let failed_streams : Map[String, Bool] = Map([])
  for event in self.events {
    let key = "\{event.turn_id}/\{event.step}"
    if event.kind == EngineEventKind::AssistantMessage {
      finalized.set(key, true)
    } else if event.kind == EngineEventKind::AssistantAttempt {
      failed_streams.set(key, true)
    }
  }
  let provisional : Map[String, Json] = Map([])
  let provisional_content : Map[String, StringBuilder] = Map([])
  let provisional_reasoning : Map[String, StringBuilder] = Map([])
  let result : Array[Json] = []
  for event in self.events {
    match event.kind {
      UserMessage => result.push(transcript_user_message(event.data))
      ToolResult => result.push(detached(event.data))
      AssistantMessage =>
        match event.data {
          Json::Object(data) =>
            match data.get("message") {
              Some(message) => result.push(detached(message))
              None => ()
            }
          _ => ()
        }
      AssistantStreamDelta => {
        let key = "\{event.turn_id}/\{event.step}"
        if finalized.get(key) is Some(_) {
          continue
        }
        match provisional.get(key) {
          Some(_) => ()
          None => {
            let values = Map::from_array([
              ("role", Json::string("assistant")),
              ("content", Json::string("")),
              ("provisional", boolean(true)),
              (
                "stream_status",
                Json::string(
                  if failed_streams.get(key) is Some(_) {
                    "partial"
                  } else {
                    "writing"
                  },
                ),
              ),
              ("turn_id", integer(event.turn_id)),
              ("step", integer(event.step)),
            ])
            let message = Json::object(values)
            provisional.set(key, message)
            result.push(message)
          }
        }
        let (content, reasoning) = match event.data {
          Json::Object(data) =>
            (
              match data.get("content") {
                Some(Json::String(value)) => value
                _ => ""
              },
              match data.get("reasoning") {
                Some(Json::String(value)) => value
                _ => ""
              },
            )
          _ => ("", "")
        }
        if !content.is_empty() {
          let builder = match provisional_content.get(key) {
            Some(builder) => builder
            None => {
              let builder = StringBuilder()
              provisional_content.set(key, builder)
              builder
            }
          }
          builder.write_string(content)
        }
        if !reasoning.is_empty() {
          let builder = match provisional_reasoning.get(key) {
            Some(builder) => builder
            None => {
              let builder = StringBuilder()
              provisional_reasoning.set(key, builder)
              builder
            }
          }
          builder.write_string(reasoning)
        }
      }
      _ => ()
    }
  }
  for key, message in provisional {
    match message {
      Json::Object(values) => {
        match provisional_content.get(key) {
          Some(builder) =>
            values.set("content", Json::string(builder.to_string()))
          None => ()
        }
        match provisional_reasoning.get(key) {
          Some(builder) =>
            values.set("reasoning", Json::string(builder.to_string()))
          None => ()
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Build only completed conversational context. Provisional stream rows are
/// transcript diagnostics until a final assistant/message replaces them.
fn Session::model_messages(self : Session) -> Array[Json] {
  if self.imported {
    return imported_messages(self.events)
  }
  let (content_by_result, _) = self.tool_result_pruning_state()
  self.events.filter_map(event => {
    match event.kind {
      UserMessage => Some(detached(event.data))
      ToolResult => Some(projected_tool_result(event, content_by_result))
      AssistantMessage =>
        match event.data {
          Json::Object(data) => data.get("message").map(detached)
          _ => None
        }
      _ => None
    }
  })
}

///|
fn Session::stream_revision(self : Session) -> Int {
  let mut result = 0
  for event in self.events {
    if event.kind == EngineEventKind::AssistantStreamDelta {
      match event.data {
        Json::Object(data) => {
          match data.get("content") {
            Some(Json::String(text)) => result += text.length()
            _ => ()
          }
          match data.get("reasoning") {
            Some(Json::String(text)) => result += text.length()
            _ => ()
          }
        }
        _ => ()
      }
    }
  }
  result
}

///|
fn Session::stream_projection(
  self : Session,
  effect_id : String,
) -> (Bool, String, String) {
  let content = StringBuilder()
  let reasoning = StringBuilder()
  let mut found = false
  for event in self.events {
    if event.kind != EngineEventKind::AssistantStreamDelta {
      continue
    }
    match event.data {
      Json::Object(data) if data.get("effect_id") == Some(effect_id.to_json()) => {
        found = true
        match data.get("content") {
          Some(Json::String(text)) => content.write_string(text)
          _ => ()
        }
        match data.get("reasoning") {
          Some(Json::String(text)) => reasoning.write_string(text)
          _ => ()
        }
      }
      _ => ()
    }
  }
  (found, content.to_string(), reasoning.to_string())
}

///|
fn Event::json(self : Event) -> Json {
  self.typed().json()
}

///|
fn Event::typed(self : Event) -> EngineEvent {
  {
    seq: self.seq,
    kind: self.kind,
    turn_id: self.turn_id,
    step: self.step,
    data: detached(self.data),
  }
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
    (
      "todos",
      match self.todos {
        Some(items) => Json::array(items.map(detached))
        None => Json::null()
      },
    ),
  ])
  if self.imported {
    value.set("source_format", Json::string("deepseek-session-v4"))
    value.set(
      "pending_tool_calls",
      Json::array(imported_pending_calls(self.events)),
    )
    value.set("pending_inbox", imported_pending_inbox(self.events))
  } else {
    value.set("stream_revision", integer(self.stream_revision()))
  }
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
  match self.fork_parent_id() {
    Some(parent_id) => value.set("parent_session_id", Json::string(parent_id))
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
  call_id : String?,
) -> String {
  let id = "effect-\{self.next_effect}"
  self.next_effect += 1
  let effect = {
    id,
    kind,
    session_id: session.id,
    turn_id: session.turn_id,
    step: session.step,
    call_id,
    request,
  }
  self.effects.set(id, effect)
  self.queued.push(id)
  match kind {
    Llm => {
      session.active_effect = Some(id)
      session.active_kind = Some(kind)
    }
    ToolExecution =>
      match call_id {
        Some(call_id) => session.active_tool_effects.set(id, call_id)
        None => abort("Tool effect is missing its call identity")
      }
  }
  let kind_name = match kind {
    Llm => "llm/request"
    ToolExecution => "tool/request"
  }
  let data = Map::from_array([("effect_id", Json::string(id))])
  if kind == ToolExecution {
    data.set("call_id", Json::string(call_id.unwrap()))
  }
  session.append(kind_name, Json::object(data))
  id
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
  session.retry_count = 0
  session.retry_max_retries = None
  session.retry_initial_delay_ms = None
  session.retry_max_delay_ms = None
  session.pending_retry_id = None
  session.status = Running
  session.append("step/start", object([]))
  ignore(
    self.emit_effect(
      session,
      Llm,
      object([
        ("system", Json::string(session.system_prompt)),
        ("messages", Json::array(session.model_messages())),
        ("tools", Json::array(self.tools.map(Tool::json))),
      ]),
      None,
    ),
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
  let fields = Map::from_array([
    ("id", Json::string(self.id)),
    ("name", Json::string(self.name)),
    ("arguments", Json::string(self.arguments)),
  ])
  match self.kind {
    FunctionCall => ()
    CustomCall => fields.set("kind", Json::string("custom"))
  }
  Json::object(fields)
}

///|
fn Session::begin_tool(self : Session, call : ToolCall) -> Unit {
  call.stage = Called
  self.append("tool/call", call.json())
}

///|

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
fn Engine::retire_tool_effects(self : Engine, session : Session) -> Unit {
  for effect_id, _ in session.active_tool_effects {
    self.effects.remove(effect_id)
  }
  session.active_tool_effects.clear()
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
  self.retire_tool_effects(session)
  session.pending_retry_id = None
  session.approval = None
  while session.cursor < session.calls.length() {
    let call = session.calls[session.cursor]
    if call.stage == Pending {
      session.begin_tool(call)
      session.schedule_cursor = Int::max(
        session.schedule_cursor,
        session.cursor + 1,
      )
    }
    if call.stage == OutcomeKnown {
      call.stage = Completed
      call.effect_id = None
      session.commit_completed_tool_result(call)
    } else if call.stage == Completed {
      session.commit_completed_tool_result(call)
    } else {
      if call.stage == Dispatched {
        let effect_id = match call.effect_id {
          Some(effect_id) => effect_id
          None => abort("Dispatched tool call is missing its effect identity")
        }
        session.stage_interrupted_tool_result(call, Some(effect_id), error)
      } else {
        session.stage_interrupted_tool_result(call, None, error)
      }
      session.commit_completed_tool_result(call)
    }
  }
  session.calls.clear()
  session.cursor = 0
  session.schedule_cursor = 0
  session.parallel_group = false
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
/// Drain newly queued typed effects exactly once. A taken effect remains
/// outstanding until complete/cancel; repeated calls do not duplicate work.
pub fn Engine::take_typed_effects(self : Engine) -> Array[EngineEffect] {
  let result = self.queued.filter_map(id => {
    self.effects
    .get(id)
    .map(effect => EngineEffect::{
      id: EffectId::from_validated(effect.id),
      session_id: SessionId::from_validated(effect.session_id),
      kind: match effect.kind {
        Llm => EffectType::Provider
        ToolExecution => EffectType::Tool
      },
      request: detached(effect.request),
    })
  })
  self.queued.clear()
  result
}

///|
/// JSON compatibility adapter for existing hosts and JavaScript exports.
pub fn Engine::take_effects(self : Engine) -> Array[Json] {
  self.take_typed_effects().map(EngineEffect::json)
}

///|
/// Typed durable event view for native consumers.
pub fn Engine::event_log(
  self : Engine,
  session_id : SessionId,
) -> Result[Array[EngineEvent], String] {
  try {
    let session = self.lookup(session_id.as_string())
    Ok(session.events.map(Event::typed))
  } catch {
    Invalid(message) => Err(message)
  }
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
    let live_effect = match effect.kind {
      Llm => session.active_effect == Some(effect_id)
      ToolExecution =>
        match effect.call_id {
          Some(call_id) =>
            session.active_tool_effects.get(effect_id) == Some(call_id)
          None => false
        }
    }
    if session.status != Running ||
      !live_effect ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step {
      raise Invalid("Stale effect completion")
    }
    if effect.kind == Llm && session.pending_retry_id is Some(_) {
      raise Invalid("Provider effect completed while a retry was waiting")
    }
    let result = checked_copy(result)
    let ok = bool_value(required_field(result, "ok"), "ok")
    if !ok {
      let error = required_string(result, "error")
      match effect.kind {
        Llm =>
          // terminate still sees the live LLM effect and logs its failed attempt.
          self.terminate(session, Failed, "provider_error", error)
        ToolExecution =>
          self.complete_tool_effect(session, effect, effect_id, result)
      }
    } else {
      match effect.kind {
        Llm => {
          let completion = parse_llm_completion(result)
          let (projected, content, reasoning) = session.stream_projection(
            effect_id,
          )
          if projected &&
            (
              completion.content != content ||
              completion.reasoning.unwrap_or("") != reasoning
            ) {
            raise Invalid("Provider completion differs from projected stream")
          }
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
        ToolExecution =>
          self.complete_tool_effect(session, effect, effect_id, result)
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
    let kind = parse_tool_call_kind(raw)
    if kind == CustomCall && arguments.length() > 65536 {
      raise Invalid("Custom tool input exceeds the length limit")
    }
    if seen.get(id) is Some(_) {
      raise Invalid("Duplicate tool call id: \{id}")
    }
    seen.set(id, true)
    {
      id,
      name,
      arguments,
      kind,
      stage: Pending,
      effect_id: None,
      completed_content: None,
      completed_error: None,
      completed_contexts: [],
    }
  })
}

///|
fn parse_tool_call_kind(value : Json) -> ToolCallKind raise EngineError {
  match fields(value).get("kind") {
    None | Some(Json::String("function")) => FunctionCall
    Some(Json::String("custom")) => CustomCall
    _ => raise Invalid("Unsupported tool call kind")
  }
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
