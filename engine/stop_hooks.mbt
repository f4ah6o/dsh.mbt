///|
/// The process capture cap is 16 KiB per stream and config admits at most 32
/// Stop commands. Keep their joined UTF-16 reason within that input envelope;
/// the stricter serialized session bound is enforced by transaction admission.
const STOP_HOOK_MERGED_REASON_MAX_UNITS : Int = 524350

///|
fn stop_hook_utf16_units(value : String) -> Int {
  let mut units = 0
  for character in value {
    units += if character.to_int() > 0xFFFF { 2 } else { 1 }
  }
  units
}

///|
fn stop_hook_prefix_utf16(value : String, maximum : Int) -> String {
  let output = StringBuilder()
  let mut units = 0
  for character in value {
    let character_units = if character.to_int() > 0xFFFF { 2 } else { 1 }
    if units + character_units > maximum {
      break
    }
    output.write_char(character)
    units += character_units
  }
  output.to_string()
}

///|
fn Session::clear_stop_continuation_state(self : Session) -> Unit {
  self.stop_hook_pending = false
  self.stop_hook_event_seq = None
  self.stop_continuation_text = None
  self.stop_continuation_admitted = false
  self.stop_prompt_context_count = 0
  self.stop_prompt_context_length = 0
}

///|
fn Session::clear_stop_hook_state(self : Session) -> Unit {
  self.sticky_max_tokens = false
  self.clear_stop_continuation_state()
}

///|
fn Session::mark_stop_hook_pending(self : Session, reason : String) -> Unit {
  self.sticky_max_tokens = self.sticky_max_tokens || reason == "max_tokens"
  self.stop_hook_pending = true
  self.stop_hook_event_seq = Some(self.events.length())
  self.stop_continuation_text = None
  self.stop_continuation_admitted = false
  self.stop_prompt_context_count = 0
  self.stop_prompt_context_length = 0
  self.append(
    "hook/stop-pending",
    object([("reason", Json::string(reason))]),
  )
}

///|
fn Engine::stop_hook_session(
  self : Engine,
  checkpoint : NativeStopHookCheckpoint,
) -> Session raise EngineError {
  let session = self.lookup(checkpoint.session_id)
  if session.status != Running ||
    !session.stop_hook_pending ||
    session.turn_id != checkpoint.turn_id ||
    session.stop_hook_event_seq != Some(checkpoint.event_seq) ||
    session.open_step ||
    session.active_effect is Some(_) ||
    session.active_tool_effect_count() > 0 ||
    session.approval is Some(_) ||
    session.pending_retry_id is Some(_) {
    raise Invalid("Stale or misplaced Stop-hook checkpoint")
  }
  session
}

///|
fn Engine::settle_stop_candidate(
  self : Engine,
  candidate : Engine,
  session_id : String,
  capacity_reason? : String = "session_capacity",
) -> Json {
  if candidate.within_capacity() {
    self.adopt(candidate)
    self.sessions.get(session_id).unwrap().json()
  } else {
    let session = self.sessions.get(session_id).unwrap()
    self.terminate(session, Failed, capacity_reason, CAPACITY_ERROR)
    session.json()
  }
}

///|
/// Return the opaque continuation capability only while the exact durable
/// stopping boundary remains current.
pub fn Engine::pending_stop_hook(
  self : Engine,
  session_id : SessionId,
) -> NativeStopHookCheckpoint? {
  let session = match self.sessions.get(session_id.as_string()) {
    Some(value) => value
    None => return None
  }
  if session.status != Running || !session.stop_hook_pending {
    return None
  }
  match session.stop_hook_event_seq {
    Some(event_seq) => Some({
      session_id: session.id,
      turn_id: session.turn_id,
      event_seq,
    })
    None => None
  }
}

///|
/// Durably stage the Stop denial as the next-step UserPromptSubmit input. The
/// hook process runs only after this state has been admitted and checkpointed.
pub fn Engine::prepare_stop_continuation(
  self : Engine,
  checkpoint : NativeStopHookCheckpoint,
  text : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.stop_hook_session(checkpoint)
    if session.stop_continuation_text is Some(_) {
      raise Invalid("Stop continuation is already staged")
    }
    if text.is_empty() {
      raise Invalid("Stop continuation reason exceeds the merged reason limit")
    }
    if stop_hook_utf16_units(text) > STOP_HOOK_MERGED_REASON_MAX_UNITS {
      // This native guard is above any realistic captured hook output. If
      // reached, close the pending boundary rather than strand a busy session
      // that can neither be steered nor safely replayed.
      candidate.terminate(session, Failed, "session_capacity", CAPACITY_ERROR)
    } else {
      session.stop_continuation_text = Some(text)
      session.stop_prompt_context_count = 0
      session.stop_prompt_context_length = 0
      session.stop_continuation_admitted = false
      session.append(
        "hook/stop-continuation-pending",
        object([("text", Json::string(text))]),
      )
    }
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) => Ok(self.settle_stop_candidate(candidate, checkpoint.session_id))
  }
}

///|
/// Finish an allowed Stop hook. A provider max-token ending remains sticky
/// across any denied continuation attempts in the same turn.
pub fn Engine::finish_stop_hook(
  self : Engine,
  checkpoint : NativeStopHookCheckpoint,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.stop_hook_session(checkpoint)
    if session.stop_continuation_text is Some(_) {
      raise Invalid("Cannot finish Stop while a continuation is staged")
    }
    if session.sticky_max_tokens {
      candidate.terminate(
        session,
        Failed,
        "max_tokens",
        "Model output reached its token limit",
      )
    } else {
      session.status = Completed
      session.append("turn/end", object([("reason", Json::string("completed"))]))
      session.clear_stop_hook_state()
    }
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) => Ok(self.settle_stop_candidate(candidate, checkpoint.session_id))
  }
}

///|
/// Admit a Stop reason and UserPromptSubmit context as source-tagged messages,
/// then start the bounded next step in the same turn.
pub fn Engine::continue_stop_hook(
  self : Engine,
  checkpoint : NativeStopHookCheckpoint,
  contexts : Array[String],
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.stop_hook_session(checkpoint)
    let reason = match session.stop_continuation_text {
      Some(text) => text
      None => raise Invalid("Stop continuation was not staged")
    }
    let mut total_length = 0
    for context in contexts {
      if context.is_empty() || stop_hook_utf16_units(context) > 4096 {
        raise Invalid("UserPromptSubmit contexts must contain 1 to 4096 code units")
      }
      total_length += stop_hook_utf16_units(context)
      if total_length > MAX_POST_TOOL_CONTEXT_TOTAL_LENGTH {
        raise Invalid("UserPromptSubmit contexts exceed the aggregate length limit")
      }
    }
    if contexts.length() > MAX_POST_TOOL_CONTEXTS ||
      stop_hook_utf16_units(reason) > STOP_HOOK_MERGED_REASON_MAX_UNITS {
      raise Invalid("Stop continuation exceeds its context limits")
    }
    if session.step >= session.max_steps {
      candidate.terminate(
        session,
        Failed,
        "max_steps",
        "Maximum model steps reached",
      )
    } else if candidate.next_effect >= 1000000000 {
      candidate.terminate(
        session,
        Failed,
        "effect_limit",
        "Effect identifier limit reached",
      )
    } else {
      session.append("user/message", hook_context_message([reason]))
      if !contexts.is_empty() {
        session.append("user/message", hook_context_message(contexts))
      }
      session.stop_prompt_context_count = contexts.length()
      session.stop_prompt_context_length = total_length
      session.stop_continuation_admitted = true
      session.append(
        "hook/stop-continuation-admitted",
        object([
          ("context_count", integer(contexts.length())),
          ("context_length", integer(total_length)),
        ]),
      )
      session.clear_stop_continuation_state()
      candidate.start_step(session)
    }
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) => Ok(self.settle_stop_candidate(candidate, checkpoint.session_id))
  }
}

///|
/// Close a staged continuation when UserPromptSubmit denies it. The completed
/// assistant answer stays in the transcript and the turn reports a policy
/// rejection through the existing Failed status.
pub fn Engine::block_stop_continuation(
  self : Engine,
  checkpoint : NativeStopHookCheckpoint,
  denial_reason : String,
) -> Result[Json, String] {
  let candidate = self.copy_state()
  let changed = try {
    let session = candidate.stop_hook_session(checkpoint)
    if session.stop_continuation_text is None ||
      session.stop_prompt_context_count != 0 ||
      session.stop_prompt_context_length != 0 {
      raise Invalid("Cannot block an unstaged or already admitted continuation")
    }
    let prefix = "UserPromptSubmit hook blocked the Stop continuation"
    let error = if denial_reason.is_empty() {
      prefix
    } else {
      let separator = ": "
      let remaining = Int::max(
        0,
        8192 - stop_hook_utf16_units(prefix + separator),
      )
      prefix + separator + stop_hook_prefix_utf16(denial_reason, remaining)
    }
    session.append(
      "hook/stop-continuation-rejected",
      object([("error", Json::string(error))]),
    )
    candidate.terminate(session, Failed, "blocked", error)
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
  match changed {
    Err(message) => Err(message)
    Ok(_) => Ok(self.settle_stop_candidate(candidate, checkpoint.session_id))
  }
}
