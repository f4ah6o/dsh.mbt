///|
priv enum NativeHookEventSink {
  Root(NativeRuntime, String, NativeJobControl?)
  Child(@engine.Engine, String)
}

///|
priv enum NativeHookExecution {
  Completed(NativeHookCapture)
  Failed(String)
}

///|
const NATIVE_HOOK_DIAGNOSTIC_ERROR_PREFIX : String = "native hook diagnostic checkpoint failed: "

///|
async fn NativeHookEventSink::record_invoked(
  self : NativeHookEventSink,
  point : String,
  handler_id : String,
  matcher : String?,
  dialect : String,
) -> Result[@engine.NativeHookInvocationCheckpoint, String] {
  let recorded = match self {
    Root(runtime, session_id, control) =>
      runtime.record_native_hook_invoked(
        session_id,
        point,
        handler_id,
        matcher,
        dialect~,
        control~,
      )
    Child(engine, session_id) =>
      engine.record_native_hook_invoked(
        session_id,
        point,
        handler_id,
        matcher,
        dialect~,
      )
  }
  match recorded {
    Ok(value) => Ok(value)
    Err(error) => Err(NATIVE_HOOK_DIAGNOSTIC_ERROR_PREFIX + error)
  }
}

///|
async fn NativeHookEventSink::record_result(
  self : NativeHookEventSink,
  checkpoint : @engine.NativeHookInvocationCheckpoint,
  decision : String,
  exit_code : Int?,
  stderr_summary : String?,
  duration_ms : Int,
) -> Result[Unit, String] {
  let recorded = match self {
    Root(runtime, _, _) =>
      runtime.record_native_hook_result(
        checkpoint, decision, exit_code, stderr_summary, duration_ms,
      )
    Child(engine, _) =>
      engine
      .record_native_hook_result(
        checkpoint, decision, exit_code, stderr_summary, duration_ms,
      )
      .map(_ => ())
  }
  match recorded {
    Ok(_) => Ok(())
    Err(error) => Err(NATIVE_HOOK_DIAGNOSTIC_ERROR_PREFIX + error)
  }
}

///|
fn NativeHooks::next_handler_id(self : NativeHooks, point : String) -> String {
  self.handler_counter += 1
  "\{self.dialect}:\{point}:\{self.handler_counter}"
}

///|
fn NativeHooks::context_source_kind(self : NativeHooks) -> String {
  if self.dialect == "codex" {
    "hooks-codex"
  } else {
    "hooks-claude-code"
  }
}

///|
async fn native_run_hook_diagnostic(
  tools : NativeTools,
  hook : NativeHookCommand,
  payload : String,
  event : String,
  handler_id : String,
  matcher : String?,
  dialect : String,
  sink : NativeHookEventSink?,
) -> Result[NativeHookExecution, String] {
  let checkpoint = match sink {
    Some(value) =>
      match value.record_invoked(event, handler_id, matcher, dialect) {
        Ok(checkpoint) => Some(checkpoint)
        Err(error) => return Err(error)
      }
    None => None
  }
  let started = @async.now()
  let capture = native_run_hook_command(tools, hook, payload, dialect~)
  let duration_ms = Int::max(0, (@async.now() - started).to_int())
  let execution = match capture {
    Ok(value) => Completed(value)
    Err(error) => Failed(error)
  }
  match execution {
    Failed(_) if @async.is_being_cancelled() =>
      return Err("hook process was interrupted before a result was available")
    _ => ()
  }
  match (sink, checkpoint, execution) {
    (Some(event_sink), Some(invocation), Completed(value)) => {
      let decision = if dialect == "codex" {
        native_hook_codex_diagnostic_decision(value, event)
      } else {
        native_hook_diagnostic_decision(value, event)
      }
      let summary = native_hook_stderr_summary(value.stderr)
      let exit_code : Int? = if value.exit_code < 0 {
        None
      } else {
        Some(value.exit_code)
      }
      match
        @async.protect_from_cancel(async fn() {
          event_sink.record_result(
            invocation, decision, exit_code, summary, duration_ms,
          )
        }) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      if @async.is_being_cancelled() {
        @async.pause()
      }
    }
    (Some(event_sink), Some(invocation), Failed(error)) => {
      let summary = native_hook_stderr_summary(error)
      match
        @async.protect_from_cancel(async fn() {
          event_sink.record_result(
            invocation,
            "pass",
            None,
            summary,
            duration_ms,
          )
        }) {
        Ok(_) => ()
        Err(checkpoint_error) => return Err(checkpoint_error)
      }
      if @async.is_being_cancelled() {
        @async.pause()
      }
    }
    _ => ()
  }
  Ok(execution)
}

///|
fn native_hook_payload(
  dialect : String,
  model : String,
  turn_id : Int,
  event : String,
  project_dir : String,
  session_id : String,
  tool_name : String,
  call_id : String,
  tool_input : Json,
  tool_response : String?,
) -> Result[String, String] {
  let fields : Map[String, Json] = if dialect == "codex" {
    Map::from_array([
      ("session_id", Json::string(session_id)),
      ("transcript_path", Json::null()),
      ("cwd", Json::string(project_dir)),
      ("hook_event_name", Json::string(event)),
      ("model", Json::string(model)),
      ("permission_mode", Json::string("default")),
      ("turn_id", Json::string(turn_id.to_string())),
      ("tool_name", Json::string(tool_name)),
      (
        "tool_input",
        Json::object({
          "command": Json::string(native_hook_codex_command(tool_input)),
        }),
      ),
      ("tool_use_id", Json::string(call_id)),
    ])
  } else {
    Map::from_array([
      ("session_id", Json::string(session_id)),
      ("transcript_path", Json::string("")),
      ("cwd", Json::string(project_dir)),
      ("hook_event_name", Json::string(event)),
      ("tool_name", Json::string(tool_name)),
      ("tool_input", tool_input),
      ("tool_use_id", Json::string(call_id)),
    ])
  }
  match tool_response {
    Some(value) => fields.set("tool_response", Json::string(value))
    None => ()
  }
  let suffix = if dialect == "codex" { "" } else { "\n" }
  let text = Json::object(fields).stringify() + suffix
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
fn native_hook_codex_command(input : Json) -> String {
  match object_field(input, "command") {
    Some(Json::String(value)) => value
    _ => ""
  }
}

///|
fn native_user_prompt_payload(
  dialect : String,
  model : String,
  turn_id : Int,
  project_dir : String,
  session_id : String,
  prompt : String,
) -> Result[String, String] {
  let fields : Map[String, Json] = Map::from_array([
    ("session_id", Json::string(session_id)),
    (
      "transcript_path",
      if dialect == "codex" {
        Json::null()
      } else {
        Json::string("")
      },
    ),
    ("cwd", Json::string(project_dir)),
    ("hook_event_name", Json::string("UserPromptSubmit")),
    ("prompt", Json::string(prompt)),
  ])
  if dialect == "codex" {
    fields["model"] = Json::string(model)
    fields["permission_mode"] = Json::string("default")
    fields["turn_id"] = Json::string(turn_id.to_string())
  }
  let suffix = if dialect == "codex" { "" } else { "\n" }
  let text = Json::object(fields).stringify() + suffix
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
fn native_session_start_payload(
  dialect : String,
  model : String,
  project_dir : String,
  session_id : String,
  source : String,
) -> Result[String, String] {
  let fields : Map[String, Json] = Map::from_array([
    ("session_id", Json::string(session_id)),
    (
      "transcript_path",
      if dialect == "codex" {
        Json::null()
      } else {
        Json::string("")
      },
    ),
    ("cwd", Json::string(project_dir)),
    ("hook_event_name", Json::string("SessionStart")),
    ("source", Json::string(source)),
  ])
  if dialect == "codex" {
    fields["model"] = Json::string(model)
    fields["permission_mode"] = Json::string("default")
  }
  let suffix = if dialect == "codex" { "" } else { "\n" }
  let text = Json::object(fields).stringify() + suffix
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
fn NativeHooks::has_session_start(self : NativeHooks) -> Bool {
  !self.session_start.is_empty()
}

///|
fn NativeHooks::has_post_tool_match(
  self : NativeHooks,
  tool_name : String,
) -> Bool {
  self.post_tool.any(group => {
    native_hook_group_matches(group, tool_name, self.dialect)
  })
}

///|
fn NativeHooks::has_user_prompt_submit(self : NativeHooks) -> Bool {
  !self.user_prompt_submit.is_empty()
}

///|
/// Run matching context-only SessionStart commands in configuration order.
/// This follows the pinned Claude bridge's JSON-only additionalContext path;
/// decisions, plain stdout, and other controls are intentionally ignored.
async fn NativeHooks::before_session_start(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  source : String,
) -> Array[String] {
  let payload = match
    native_session_start_payload(
      self.dialect,
      self.model,
      self.project_dir,
      session_id,
      source,
    ) {
    Ok(value) => value
    Err(_) => return []
  }
  let contexts : Array[String] = []
  let mut overflow = false
  for group in self.session_start {
    if !native_hook_group_matches(group, source, self.dialect) {
      continue
    }
    for hook in group.commands {
      ignore(self.next_handler_id("SessionStart"))
      let capture = match
        native_run_hook_command(tools, hook, payload, dialect=self.dialect) {
        Ok(value) => value
        Err(_) => continue
      }
      if overflow {
        continue
      }
      match native_hook_session_start_context(capture, self.dialect) {
        Some(context) =>
          match native_hook_add_context(contexts, context) {
            Ok(_) => ()
            Err(_) => overflow = true
          }
        None => ()
      }
    }
  }
  if overflow {
    []
  } else {
    contexts
  }
}

///|
fn NativeHooks::has_stop(self : NativeHooks) -> Bool {
  !self.stop.is_empty()
}

///|
fn NativeHooks::has_subagent_start(self : NativeHooks) -> Bool {
  !self.subagent_start.is_empty()
}

///|
fn NativeHooks::has_subagent_stop(self : NativeHooks) -> Bool {
  !self.subagent_stop.is_empty()
}

///|
fn native_subagent_hook_payload(
  event : String,
  project_dir : String,
  child_session_id : String,
) -> Result[String, String] {
  let fields = Map::from_array([
    ("session_id", Json::string(child_session_id)),
    ("transcript_path", Json::string("")),
    ("cwd", Json::string(project_dir)),
    ("hook_event_name", Json::string(event)),
    ("agent_id", Json::string(child_session_id)),
    ("agent_type", Json::string("general-purpose")),
  ])
  if event == "SubagentStop" {
    fields.set("stop_hook_active", Json::boolean(false))
  }
  let text = Json::object(fields).stringify() + "\n"
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
/// Run matching Start commands as lifecycle work. Only matching-event
/// additionalContext is returned; hook decisions never admit or deny a child.
async fn NativeHooks::before_subagent_start(
  self : NativeHooks,
  tools : NativeTools,
  child_session_id : String,
) -> Array[String] {
  let payload = match
    native_subagent_hook_payload(
      "SubagentStart",
      self.project_dir,
      child_session_id,
    ) {
    Ok(value) => value
    Err(_) => return []
  }
  let contexts : Array[String] = []
  for group in self.subagent_start {
    if !native_hook_matches(group.matcher, "general-purpose") {
      continue
    }
    for hook in group.commands {
      ignore(self.next_handler_id("SubagentStart"))
      let capture = match
        native_run_hook_command(tools, hook, payload, dialect=self.dialect) {
        Ok(value) => value
        Err(_) => continue
      }
      for context in native_hook_subagent_start_context(capture) {
        ignore(native_hook_add_context(contexts, context))
      }
    }
  }
  contexts
}

///|
/// Run matching Stop commands after child settlement and discard all output.
async fn NativeHooks::after_subagent_stop(
  self : NativeHooks,
  tools : NativeTools,
  child_session_id : String,
) -> Unit {
  let payload = match
    native_subagent_hook_payload(
      "SubagentStop",
      self.project_dir,
      child_session_id,
    ) {
    Ok(value) => value
    Err(_) => return
  }
  for group in self.subagent_stop {
    if !native_hook_matches(group.matcher, "general-purpose") {
      continue
    }
    for hook in group.commands {
      ignore(self.next_handler_id("SubagentStop"))
      ignore(native_run_hook_command(tools, hook, payload))
    }
  }
}

///|
fn native_hook_prompt_input(input : Json, contexts : Array[String]) -> Json {
  let fields = match input {
    Json::Object(value) => value.copy()
    _ => return input
  }
  ignore(fields.remove("additional_contexts"))
  if !contexts.is_empty() {
    fields.set(
      "additional_contexts",
      Json::array(contexts.map(context => Json::string(context))),
    )
  }
  Json::object(fields)
}

///|
fn native_hook_combine_contexts(
  first : Array[String],
  second : Array[String],
) -> Result[Array[String], String] {
  let combined = first.copy()
  for context in second {
    match native_hook_add_context(combined, context) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(combined)
}

///|
async fn NativeHooks::run_point(
  self : NativeHooks,
  tools : NativeTools,
  groups : Array[NativeHookGroup],
  event : String,
  session_id : String,
  tool_name : String,
  call_id : String,
  tool_input : Json,
  tool_response : String?,
  turn_id : Int,
  sink? : NativeHookEventSink? = None,
) -> Result[NativeHookOutcome, String] {
  let blocked_reasons : Array[String] = []
  let additional_contexts : Array[String] = []
  let mut unsupported_error : String? = None
  for group in groups {
    if !native_hook_group_matches(group, tool_name, self.dialect) {
      continue
    }
    for hook in group.commands {
      let payload_result = if event == "UserPromptSubmit" {
        native_user_prompt_payload(
          self.dialect,
          self.model,
          turn_id,
          self.project_dir,
          session_id,
          match tool_input {
            Json::String(prompt) => prompt
            _ => ""
          },
        )
      } else {
        native_hook_payload(
          self.dialect,
          self.model,
          turn_id,
          event,
          self.project_dir,
          session_id,
          tool_name,
          call_id,
          tool_input,
          tool_response,
        )
      }
      let payload = match payload_result {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let handler_id = self.next_handler_id(event)
      let execution = match
        native_run_hook_diagnostic(
          tools,
          hook,
          payload,
          event,
          handler_id,
          group.matcher,
          self.dialect,
          sink,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let capture = match execution {
        Completed(value) => value
        Failed(_) =>
          // Spawn/timeout errors are nonblocking in Claude Code. The child is
          // still cancelled and reaped before this path returns.
          continue
      }
      let outcome_result = if self.dialect == "codex" {
        Ok(native_hook_codex_result_decision(capture, event))
      } else if event == "UserPromptSubmit" {
        native_hook_prompt_result_decision(capture)
      } else {
        native_hook_result_decision(capture, event)
      }
      let outcome = match outcome_result {
        Ok(value) => value
        Err(error) => {
          if unsupported_error is None {
            unsupported_error = Some(error)
          }
          continue
        }
      }
      let mut context_error : String? = None
      for context in outcome.additional_contexts {
        match native_hook_add_context(additional_contexts, context) {
          Ok(_) => ()
          Err(error) => {
            context_error = Some(error)
            break
          }
        }
      }
      match context_error {
        Some(error) => {
          if unsupported_error is None {
            unsupported_error = Some(error)
          }
          continue
        }
        None => ()
      }
      match outcome.action {
        NativeHookAction::Continue => ()
        NativeHookAction::Deny(reason) => blocked_reasons.push(reason)
      }
    }
  }
  match unsupported_error {
    Some(error) => Err(error)
    None if !blocked_reasons.is_empty() =>
      Ok({
        action: NativeHookAction::Deny(blocked_reasons.join("\n\n")),
        additional_contexts: if event == "UserPromptSubmit" {
          []
        } else {
          additional_contexts
        },
      })
    None => Ok({ action: NativeHookAction::Continue, additional_contexts, })
  }
}

///|
async fn NativeHooks::before_user_prompt(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  prompt : String,
  turn_id? : Int = 0,
  sink? : NativeHookEventSink? = None,
) -> Result[NativeHookOutcome, String] {
  self.run_point(
    tools,
    self.user_prompt_submit,
    "UserPromptSubmit",
    session_id,
    "",
    "",
    Json::string(prompt),
    None,
    turn_id,
    sink~,
  )
}

///|
fn native_stop_payload(
  dialect : String,
  model : String,
  turn_id : Int,
  project_dir : String,
  session_id : String,
) -> Result[String, String] {
  let fields : Map[String, Json] = Map::from_array([
    ("session_id", Json::string(session_id)),
    (
      "transcript_path",
      if dialect == "codex" {
        Json::null()
      } else {
        Json::string("")
      },
    ),
    ("cwd", Json::string(project_dir)),
    ("hook_event_name", Json::string("Stop")),
    ("stop_hook_active", Json::boolean(false)),
  ])
  if dialect == "codex" {
    fields["model"] = Json::string(model)
    fields["permission_mode"] = Json::string("default")
    fields["turn_id"] = Json::string(turn_id.to_string())
    fields["last_assistant_message"] = Json::null()
  }
  let suffix = if dialect == "codex" { "" } else { "\n" }
  let text = Json::object(fields).stringify() + suffix
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
/// Run every configured Stop command in configuration order. Stop matchers
/// have no subject in the pinned bridge and are deliberately ignored.
async fn NativeHooks::before_stop(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  turn_id? : Int = 0,
  sink? : NativeHookEventSink? = None,
) -> Result[NativeHookOutcome, String] {
  let payload = match
    native_stop_payload(
      self.dialect,
      self.model,
      turn_id,
      self.project_dir,
      session_id,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut winning_rank = 0
  let reasons : Array[String] = []
  for group in self.stop {
    for hook in group.commands {
      let handler_id = self.next_handler_id("Stop")
      let execution = match
        native_run_hook_diagnostic(
          tools,
          hook,
          payload,
          "Stop",
          handler_id,
          None,
          self.dialect,
          sink,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let capture = match execution {
        Completed(value) => value
        Failed(_) => continue
      }
      let outcome = if self.dialect == "codex" {
        let decoded = native_hook_codex_result_decision(capture, "Stop")
        match decoded.action {
          NativeHookAction::Deny(reason) => { rank: 3, reason: Some(reason), }
          NativeHookAction::Continue => { rank: 0, reason: None, }
        }
      } else {
        native_hook_stop_result_decision(capture)
      }
      if outcome.rank > winning_rank {
        winning_rank = outcome.rank
        reasons.clear()
      }
      if outcome.rank == winning_rank && outcome.rank >= 2 {
        match outcome.reason {
          Some(reason) if !reason.is_empty() => reasons.push(reason)
          _ => ()
        }
      }
    }
  }
  if winning_rank == 3 {
    Ok({
      action: NativeHookAction::Deny(reasons.join("\n\n")),
      additional_contexts: [],
    })
  } else {
    Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
}

///|
async fn NativeHooks::before_tool(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  request : Json,
  turn_id? : Int = 0,
  sink? : NativeHookEventSink? = None,
) -> Result[NativeHookOutcome, String] {
  let tool_name = string_field(request, "name").unwrap_or("")
  let call_id = string_field(request, "call_id").unwrap_or("")
  let tool_input = object_field(request, "arguments").unwrap_or(Json::null())
  self.run_point(
    tools,
    self.pre_tool,
    "PreToolUse",
    session_id,
    tool_name,
    call_id,
    tool_input,
    None,
    turn_id,
    sink~,
  )
}

///|
async fn NativeHooks::after_tool(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  request : Json,
  result : Json,
  turn_id? : Int = 0,
  sink? : NativeHookEventSink? = None,
) -> Result[NativeHookOutcome, String] {
  let tool_name = string_field(request, "name").unwrap_or("")
  let call_id = string_field(request, "call_id").unwrap_or("")
  let tool_input = object_field(request, "arguments").unwrap_or(Json::null())
  let tool_response = match string_field(result, "content") {
    Some(value) => Some(value)
    None => string_field(result, "error")
  }
  self.run_point(
    tools,
    self.post_tool,
    "PostToolUse",
    session_id,
    tool_name,
    call_id,
    tool_input,
    tool_response,
    turn_id,
    sink~,
  )
}
