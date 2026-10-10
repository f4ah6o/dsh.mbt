///|
fn native_hook_payload(
  event : String,
  project_dir : String,
  session_id : String,
  tool_name : String,
  call_id : String,
  tool_input : Json,
  tool_response : String?,
) -> Result[String, String] {
  let fields : Map[String, Json] = Map::from_array([
    ("session_id", Json::string(session_id)),
    ("transcript_path", Json::string("")),
    ("cwd", Json::string(project_dir)),
    ("hook_event_name", Json::string(event)),
    ("tool_name", Json::string(tool_name)),
    ("tool_input", tool_input),
    ("tool_use_id", Json::string(call_id)),
  ])
  match tool_response {
    Some(value) => fields.set("tool_response", Json::string(value))
    None => ()
  }
  let text = Json::object(fields).stringify() + "\n"
  if @utf8.encode(text).length() > NATIVE_HOOK_STDIN_LIMIT {
    Err("hooks stdin exceeds the 64 KiB limit")
  } else {
    Ok(text)
  }
}

///|
fn NativeHooks::has_post_tool_match(
  self : NativeHooks,
  tool_name : String,
) -> Bool {
  self.post_tool.any(group => native_hook_matches(group.matcher, tool_name))
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
) -> Result[NativeHookOutcome, String] {
  let blocked_reasons : Array[String] = []
  let additional_contexts : Array[String] = []
  let mut unsupported_error : String? = None
  for group in groups {
    if !native_hook_matches(group.matcher, tool_name) {
      continue
    }
    for hook in group.commands {
      let payload = match
        native_hook_payload(
          event,
          self.project_dir,
          session_id,
          tool_name,
          call_id,
          tool_input,
          tool_response,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let capture = match native_run_hook_command(tools, hook, payload) {
        Ok(value) => value
        Err(_) =>
          // Spawn/timeout errors are nonblocking in Claude Code. The child is
          // still cancelled and reaped before this path returns.
          continue
      }
      let outcome = match native_hook_result_decision(capture, event) {
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
        additional_contexts,
      })
    None => Ok({ action: NativeHookAction::Continue, additional_contexts, })
  }
}

///|
async fn NativeHooks::before_tool(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  request : Json,
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
  )
}

///|
async fn NativeHooks::after_tool(
  self : NativeHooks,
  tools : NativeTools,
  session_id : String,
  request : Json,
  result : Json,
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
  )
}
