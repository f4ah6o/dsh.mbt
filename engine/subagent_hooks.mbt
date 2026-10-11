///|
fn engine_hook_context_join(contexts : Array[String]) -> String {
  contexts.join("")
}

///|
fn engine_subagent_hook_context_length(contexts : Array[String]) -> Int {
  let mut total = 0
  for context in contexts {
    total += engine_hook_context_utf16_units(context)
  }
  total
}

///|
fn engine_validate_hook_contexts(
  contexts : Array[String],
) -> Int raise EngineError {
  if contexts.length() > 32 {
    raise Invalid("hook contexts exceed the 32-item limit")
  }
  let mut total = 0
  for context in contexts {
    let units = engine_hook_context_utf16_units(context)
    if context.is_empty() || units > 4096 {
      raise Invalid("hook context must contain 1 to 4096 UTF-16 code units")
    }
    total += units
    if total > 16384 {
      raise Invalid("hook contexts exceed the aggregate length limit")
    }
  }
  total
}

///|
fn engine_subagent_hook_checkpoint(
  session : Session,
) -> NativeSubagentPromptHookCheckpoint {
  let prompt = if session.subagent_prompt_hook_initial {
    engine_hook_context_join(session.subagent_prompt_hook_contexts) +
    session.subagent_prompt_hook_prompt.unwrap_or("")
  } else {
    engine_hook_context_join(session.subagent_prompt_hook_contexts)
  }
  {
    session_id: session.id,
    turn_id: session.turn_id,
    step: session.step,
    generation: session.subagent_prompt_hook_generation,
    initial: session.subagent_prompt_hook_initial,
    prompt,
    contexts: session.subagent_prompt_hook_contexts.copy(),
  }
}

///|
pub fn NativeSubagentPromptHookCheckpoint::prompt(
  self : NativeSubagentPromptHookCheckpoint,
) -> String {
  self.prompt
}

///|
pub fn NativeSubagentPromptHookCheckpoint::contexts(
  self : NativeSubagentPromptHookCheckpoint,
) -> Array[String] {
  self.contexts.copy()
}

///|
pub fn NativeSubagentPromptHookCheckpoint::is_initial(
  self : NativeSubagentPromptHookCheckpoint,
) -> Bool {
  self.initial
}

///|
/// Stage a one-shot child turn and claim its current SubagentStart inbox batch
/// before UserPromptSubmit runs. Arrivals after this call remain queued.
pub fn Engine::begin_subagent_prompt_hook(
  self : Engine,
  session_id : String,
  prompt : String,
  admit_later_contexts : Bool,
) -> Result[NativeSubagentPromptHookCheckpoint, String] {
  let candidate = self.copy_state()
  let checkpoint = try {
    let session = candidate.lookup(session_id)
    if session.imported ||
      session.status != Idle ||
      session.subagent_prompt_hook_active {
      raise Invalid("Subagent prompt hook requires an idle child session")
    }
    ignore(engine_validate_hook_contexts(session.pending_hook_contexts))
    session.subagent_prompt_hook_admission = admit_later_contexts
    session.subagent_prompt_hook_active = true
    session.subagent_prompt_hook_initial = true
    session.subagent_prompt_hook_generation += 1
    session.subagent_prompt_hook_contexts = session.pending_hook_contexts.copy()
    session.pending_hook_contexts.clear()
    session.subagent_prompt_hook_prompt = Some(prompt)
    engine_subagent_hook_checkpoint(session)
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
/// Return the claimed child inbox batch while its prompt hook is running.
pub fn Engine::pending_subagent_prompt_hook(
  self : Engine,
  session_id : String,
) -> NativeSubagentPromptHookCheckpoint? {
  match self.sessions.get(session_id) {
    Some(session) if session.subagent_prompt_hook_active =>
      Some(engine_subagent_hook_checkpoint(session))
    _ => None
  }
}

///|
fn Session::validate_subagent_prompt_hook(
  self : Session,
  checkpoint : NativeSubagentPromptHookCheckpoint,
) -> Unit raise EngineError {
  if !self.subagent_prompt_hook_active ||
    self.id != checkpoint.session_id ||
    self.turn_id != checkpoint.turn_id ||
    self.step != checkpoint.step ||
    self.subagent_prompt_hook_generation != checkpoint.generation ||
    self.subagent_prompt_hook_initial != checkpoint.initial ||
    self.subagent_prompt_hook_contexts != checkpoint.contexts {
    raise Invalid("Stale or misplaced Subagent prompt-hook checkpoint")
  }
  if checkpoint.initial {
    if self.status != Idle ||
      self.turn_id >= 1000000 ||
      self.subagent_prompt_hook_prompt is None {
      raise Invalid(
        "Stale or misplaced initial Subagent prompt-hook checkpoint",
      )
    }
  } else if self.status != Running ||
    self.open_step ||
    self.active_effect is Some(_) ||
    self.active_tool_effect_count() > 0 ||
    self.approval is Some(_) ||
    self.pending_retry_id is Some(_) ||
    self.stop_hook_pending {
    raise Invalid("Stale or misplaced Subagent prompt-hook checkpoint")
  }
}

///|
fn Session::clear_subagent_prompt_hook(self : Session) -> Unit {
  self.subagent_prompt_hook_active = false
  self.subagent_prompt_hook_initial = false
  self.subagent_prompt_hook_contexts.clear()
  self.subagent_prompt_hook_prompt = None
}

///|
/// Admit exactly the claimed Start batch, followed by UserPromptSubmit
/// additionalContext. Context arriving during the async hook remains queued.
pub fn Engine::accept_subagent_prompt_hook(
  self : Engine,
  checkpoint : NativeSubagentPromptHookCheckpoint,
  contexts : Array[String],
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.lookup(checkpoint.session_id)
    session.validate_subagent_prompt_hook(checkpoint)
    let all_contexts = session.subagent_prompt_hook_contexts.copy()
    for context in contexts {
      all_contexts.push(context)
    }
    for context in session.pending_hook_contexts {
      all_contexts.push(context)
    }
    ignore(engine_validate_hook_contexts(all_contexts))
    if checkpoint.initial {
      let prompt = session.subagent_prompt_hook_prompt.unwrap()
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
      session.sticky_max_tokens = false
      session.stop_hook_pending = false
      session.stop_hook_event_seq = None
      session.stop_continuation_text = None
      session.stop_continuation_hook_contexts.clear()
      session.stop_continuation_admitted = false
      session.stop_prompt_context_count = 0
      session.stop_prompt_context_length = 0
      session.todos = None
      session.append("turn/start", object([]))
      if !session.subagent_prompt_hook_contexts.is_empty() {
        session.append(
          "hook/subagent-start-context",
          object([
            (
              "context_count",
              integer(session.subagent_prompt_hook_contexts.length()),
            ),
            (
              "context_length",
              integer(
                engine_subagent_hook_context_length(
                  session.subagent_prompt_hook_contexts,
                ),
              ),
            ),
          ]),
        )
        session.append(
          "user/message",
          hook_context_message(session.subagent_prompt_hook_contexts),
        )
      }
      session.append(
        "user/message",
        object([
          ("role", Json::string("user")),
          ("content", Json::string(prompt)),
        ]),
      )
      if !contexts.is_empty() {
        session.append("user/message", hook_context_message(contexts))
      }
    } else {
      if !session.subagent_prompt_hook_contexts.is_empty() {
        let context_length = engine_subagent_hook_context_length(
          session.subagent_prompt_hook_contexts,
        )
        session.append(
          "hook/subagent-start-context",
          object([
            (
              "context_count",
              integer(session.subagent_prompt_hook_contexts.length()),
            ),
            ("context_length", integer(context_length)),
          ]),
        )
        session.append(
          "user/message",
          hook_context_message(session.subagent_prompt_hook_contexts),
        )
      }
      if !contexts.is_empty() {
        session.append("user/message", hook_context_message(contexts))
      }
    }
    session.clear_subagent_prompt_hook()
    candidate.start_step(session, skip_pending_hook_contexts=true)
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

///|
/// Reject a claimed prompt input. Initial rejection leaves the unused child
/// idle for its caller to report; later rejection closes the turn without
/// changing the already committed assistant answer.
pub fn Engine::block_subagent_prompt_hook(
  self : Engine,
  checkpoint : NativeSubagentPromptHookCheckpoint,
  reason : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.lookup(checkpoint.session_id)
    session.validate_subagent_prompt_hook(checkpoint)
    session.clear_subagent_prompt_hook()
    session.pending_hook_contexts.clear()
    if checkpoint.initial {
      Ok(session.json())
    } else {
      let prefix = "UserPromptSubmit hook blocked the SubagentStart context"
      let separator = ": "
      let remaining = Int::max(
        0,
        8192 - engine_hook_context_utf16_units(prefix + separator),
      )
      let bounded = native_engine_hook_prefix(reason, remaining)
      let error = if bounded.is_empty() {
        prefix
      } else {
        prefix + separator + bounded
      }
      candidate.terminate(session, Failed, "blocked", error)
      Ok(session.json())
    }
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

///|
fn native_engine_hook_prefix(value : String, maximum : Int) -> String {
  let output = StringBuilder()
  let mut units = 0
  for character in value {
    let width = if character.to_int() > 0xFFFF { 2 } else { 1 }
    if units + width > maximum {
      break
    }
    output.write_char(character)
    units += width
  }
  output.to_string()
}
