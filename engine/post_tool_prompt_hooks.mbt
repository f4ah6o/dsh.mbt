///|
fn post_tool_prompt_hook_checkpoint(
  session : Session,
) -> NativePostToolPromptHookCheckpoint {
  {
    session_id: session.id,
    turn_id: session.turn_id,
    step: session.step,
    generation: session.post_tool_prompt_hook_generation,
    event_seq: session.post_tool_prompt_hook_event_seq.unwrap(),
    contexts: session.post_tool_prompt_hook_contexts.copy(),
  }
}

///|
pub fn NativePostToolPromptHookCheckpoint::contexts(
  self : NativePostToolPromptHookCheckpoint,
) -> Array[String] {
  self.contexts.copy()
}

///|
pub fn NativePostToolPromptHookCheckpoint::prompt(
  self : NativePostToolPromptHookCheckpoint,
) -> String {
  self.contexts.join("")
}

///|
/// Return the claimed PostToolUse batch only at its exact next-step boundary.
pub fn Engine::pending_post_tool_prompt_hook(
  self : Engine,
  session_id : SessionId,
) -> NativePostToolPromptHookCheckpoint? {
  match self.sessions.get(session_id.as_string()) {
    Some(session) if session.status == Running &&
      session.post_tool_prompt_hook_active =>
      session.post_tool_prompt_hook_event_seq.map(_ => {
        post_tool_prompt_hook_checkpoint(session)
      })
    _ => None
  }
}

///|
fn Engine::post_tool_prompt_hook_session(
  self : Engine,
  checkpoint : NativePostToolPromptHookCheckpoint,
) -> Session raise EngineError {
  let session = self.lookup(checkpoint.session_id)
  if !session.post_tool_prompt_hook_active ||
    session.id != checkpoint.session_id ||
    session.turn_id != checkpoint.turn_id ||
    session.step != checkpoint.step ||
    session.post_tool_prompt_hook_generation != checkpoint.generation ||
    session.post_tool_prompt_hook_event_seq != Some(checkpoint.event_seq) ||
    session.post_tool_prompt_hook_contexts != checkpoint.contexts ||
    session.status != Running ||
    session.open_step ||
    session.active_effect is Some(_) ||
    session.active_tool_effect_count() > 0 ||
    session.approval is Some(_) ||
    session.pending_retry_id is Some(_) ||
    session.stop_hook_pending {
    raise Invalid("Stale or misplaced PostToolUse prompt-hook checkpoint")
  }
  session
}

///|
fn Session::clear_post_tool_prompt_hook(self : Session) -> Unit {
  self.post_tool_prompt_hook_admission = false
  self.post_tool_prompt_hook_active = false
  self.post_tool_prompt_hook_event_seq = None
  self.post_tool_prompt_hook_contexts.clear()
  self.post_tool_prompt_hook_messages.clear()
}

///|
fn Engine::settle_post_tool_prompt_candidate(
  self : Engine,
  candidate : Engine,
  session_id : String,
) -> Result[Json, String] {
  if candidate.within_capacity() {
    self.adopt(candidate)
    Ok(self.sessions.get(session_id).unwrap().json())
  } else {
    let session = self.sessions.get(session_id).unwrap()
    if !native_hook_pending_invocations(session).is_empty() {
      return Err(CAPACITY_ERROR)
    }
    self.terminate(session, Failed, "session_capacity", CAPACITY_ERROR)
    Ok(session.json())
  }
}

///|
/// Admit the exact claimed PostToolUse messages, followed by the hook's own
/// additionalContext. No user-message event is emitted before this succeeds.
pub fn Engine::accept_post_tool_prompt_hook(
  self : Engine,
  checkpoint : NativePostToolPromptHookCheckpoint,
  contexts : Array[String],
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.post_tool_prompt_hook_session(checkpoint)
    let all_contexts = session.post_tool_prompt_hook_contexts.copy()
    for context in contexts {
      all_contexts.push(context)
    }
    for context in session.pending_hook_contexts {
      all_contexts.push(context)
    }
    let total_length = engine_validate_hook_contexts(all_contexts)
    session.append(
      "hook/post-tool-prompt-admitted",
      object([
        ("context_count", integer(all_contexts.length())),
        ("context_length", integer(total_length)),
        (
          "additional_contexts",
          Json::array(contexts.map(context => Json::string(context))),
        ),
      ]),
    )
    for message in session.post_tool_prompt_hook_messages {
      session.append("user/message", message)
    }
    if !contexts.is_empty() {
      session.append("user/message", hook_context_message(contexts))
    }
    session.clear_post_tool_prompt_hook()
    candidate.start_step(session, skip_pending_hook_contexts=true)
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) =>
      self.settle_post_tool_prompt_candidate(candidate, checkpoint.session_id)
  }
}

///|
/// Reject the claimed batch without admitting any of its sourced messages.
pub fn Engine::block_post_tool_prompt_hook(
  self : Engine,
  checkpoint : NativePostToolPromptHookCheckpoint,
  reason : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.post_tool_prompt_hook_session(checkpoint)
    if !native_hook_pending_invocations(session).is_empty() {
      raise Invalid("Cannot close a turn with pending native hook results")
    }
    let error = if reason.is_empty() {
      "UserPromptSubmit hook rejected the PostToolUse context"
    } else {
      reason
    }
    if error.length() > 8192 {
      raise Invalid(
        "PostToolUse prompt-hook rejection exceeds the length limit",
      )
    }
    session.append(
      "hook/post-tool-prompt-rejected",
      object([("error", Json::string(error))]),
    )
    session.clear_post_tool_prompt_hook()
    session.pending_hook_contexts.clear()
    candidate.terminate(session, Failed, "blocked", error)
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) =>
      self.settle_post_tool_prompt_candidate(candidate, checkpoint.session_id)
  }
}
