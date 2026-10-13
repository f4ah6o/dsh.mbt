///|
/// gpui owns the operation descriptors, validation, invocation paths, and MCP
/// transport. Both the browser and the local HTTP/CLI carrier use this object.
pub struct HarnessApi {
  priv owner : @core.App
  priv engine : @engine.Engine
  priv registry : @capability.Registry
  priv protocol : @mcp.ProtocolServer
  priv operations : Map[String, @capability.TypedCapability[Json, Json]]
  priv profiler : @hotpath.Profiler
  priv native_prompt_contexts : Ref[Array[String]]
  priv native_session_start_contexts : Ref[Array[String]]
  priv native_hook_context_source_kind : Ref[String]
  priv preview_session_send : Ref[Bool]
}

///|
priv suberror InitError {
  InitError(String)
}

///|
fn error_text(error : @diagnostics.FrameworkError) -> String {
  error.code().label() + ": " + error.message().unwrap_or(error.operation())
}

///|
fn[T] checked(
  value : Result[T, @diagnostics.FrameworkError],
) -> T raise InitError {
  match value {
    Ok(value) => value
    Err(error) => raise InitError(error_text(error))
  }
}

///|
fn domain_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="dsh",
    message~,
  )
}

///|
fn field(
  name : String,
  schema : @capability.Schema,
  required : Bool,
) -> @capability.SchemaField raise InitError {
  checked(@capability.SchemaField::new(name, schema, required))
}

///|
fn operation_schema(operation : String) -> @capability.Schema raise InitError {
  let string = @capability.Schema::string()
  let session = field("session_id", string, true)
  let fields = match operation {
    "session_create" =>
      [
        field("id", string, false),
        field("title", string, false),
        field("system_prompt", string, false),
        field("max_steps", @capability.Schema::int(), false),
      ]
    "session_fork" =>
      [session, field("id", string, false), field("title", string, false)]
    "session_import" => [field("jsonl", string, true)]
    "session_get" | "session_cancel" => [session]
    "session_send" => [session, field("prompt", string, true)]
    "session_prune_tool_results" =>
      [
        session,
        field("threshold_chars", @capability.Schema::int(), false),
        field("head_chars", @capability.Schema::int(), false),
        field("tail_chars", @capability.Schema::int(), false),
      ]
    "tool_approve" =>
      [
        session,
        field("call_id", string, true),
        field("approved", @capability.Schema::bool(), true),
      ]
    _ => []
  }
  checked(@capability.Schema::record(fields))
}

///|
fn json_to_value(value : Json) -> @capability.Value {
  match value {
    Null => @capability.Value::unit()
    True => @capability.Value::bool(true)
    False => @capability.Value::bool(false)
    String(value) => @capability.Value::string(value)
    Number(value, ..) =>
      if value >= -2147483648.0 &&
        value <= 2147483647.0 &&
        value.to_int().to_double() == value {
        @capability.Value::int(value.to_int())
      } else {
        @capability.Value::number(value)
      }
    Array(values) => @capability.Value::array(values.map(json_to_value))
    Object(values) => {
      let result : Array[(String, @capability.Value)] = []
      for key, value in values {
        result.push((key, json_to_value(value)))
      }
      @capability.Value::object(result)
    }
  }
}

///|
// Use the pinned parser's explicit depth guard for the capability transport.
#warnings("-deprecated")
fn value_to_json(
  value : @capability.Value,
) -> Result[Json, @diagnostics.FrameworkError] {
  match value.try_canonical_json() {
    Err(error) => Err(error)
    Ok(raw) =>
      Ok(@json.parse(raw, max_nesting_depth=32)) catch {
        _ => Err(domain_error("decode", "capability value is not valid JSON"))
      }
  }
}

///|
fn session_summaries(value : Json) -> Json {
  match value {
    Array(sessions) =>
      Json::array(
        sessions.map(session => {
          let summary : Map[String, Json] = Map([])
          if session is Object(fields) {
            for
              key in [
                "id", "title", "status", "turn_id", "step", "parent_session_id",
              ] {
              if fields.get(key) is Some(value) {
                summary[key] = value
              }
            }
          }
          Json::object(summary)
        }),
      )
    _ => Json::array([])
  }
}

///|
fn create_api(
  external_mcp_tools : Array[Json],
  skill_tool : Json?,
  lsp_tool : Json?,
  subagent_tool : Json?,
) -> HarnessApi raise InitError {
  let owner = checked(@core.App::new())
  checked(owner.start())
  let registry = checked(@capability.Registry::new_owned(owner))
  let plugins = match @plugins.defaults() {
    Ok(plugins) => plugins
    Err(error) => raise InitError(error)
  }
  if external_mcp_tools.length() > 0 {
    match
      plugins.mount("tools.external-mcp", ["agent-loop"], external_mcp_tools) {
      Ok(_) => ()
      Err(error) => raise InitError(error)
    }
  }
  match skill_tool {
    Some(tool) =>
      match plugins.mount("tools.skills", ["agent-loop"], [tool]) {
        Ok(_) => ()
        Err(error) => raise InitError(error)
      }
    None => ()
  }
  match lsp_tool {
    Some(tool) =>
      match plugins.mount("tools.lsp", ["agent-loop"], [tool]) {
        Ok(_) => ()
        Err(error) => raise InitError(error)
      }
    None => ()
  }
  match subagent_tool {
    Some(tool) =>
      match plugins.mount("tools.subagent", ["agent-loop"], [tool]) {
        Ok(_) => ()
        Err(error) => raise InitError(error)
      }
    None => ()
  }
  let engine = @engine.Engine::new(plugins.tools())
  let profiler = @hotpath.Profiler::new()
  let native_prompt_contexts : Ref[Array[String]] = Ref([])
  let native_session_start_contexts : Ref[Array[String]] = Ref([])
  let native_hook_context_source_kind = Ref("hooks-claude-code")
  let preview_session_send = Ref(false)
  let operations : Map[String, @capability.TypedCapability[Json, Json]] = Map([])
  for
    (name, title, description, is_read_only) in [
      (
        "session_create", "Create session", "Create a conversation with an append-only MoonBit event log.",
        false,
      ),
      (
        "session_fork", "Fork conversation", "Create an independent conversation from a settled session history.",
        false,
      ),
      (
        "session_list", "List sessions", "Read the current sessions and their execution states.",
        true,
      ),
      (
        "session_import", "Import Session v4", "Validate and import a DeepSeek Session v4 JSONL archive as a read-only history. Import never replays external effects.",
        false,
      ),
      (
        "session_get", "Read session", "Read a session, its transcript, events, and pending tool approval.",
        true,
      ),
      (
        "session_send", "Send prompt", "Begin a turn. Returns immediately; query the session until it settles.",
        false,
      ),
      (
        "session_prune_tool_results", "Trim tool results", "Durably project oversized tool results to bounded head and tail text for future provider requests. The full original results remain in session history.",
        false,
      ),
      (
        "session_cancel", "Cancel turn", "Stop an active turn and reject late provider or tool settlements.",
        false,
      ),
      (
        "tool_approve", "Decide tool approval", "Approve or deny exactly the pending tool call in this session.",
        false,
      ),
      (
        "plugin_list", "List plugins", "Read the mounted MoonBit startup composition and tool ownership.",
        true,
      ),
      (
        "profile_stats", "Read profiler", "Read hotpath.mbt aggregate timings for capability invocations.",
        true,
      ),
    ] {
    let descriptor = checked(
      @capability.Descriptor::new(
        "dsh." + name,
        title,
        description +
        " The output is a JSON-encoded string; the HTTP carrier decodes that same value.",
        if is_read_only {
          @capability.Query
        } else {
          @capability.Command
        },
        operation_schema(name),
        @capability.Schema::string(),
        if is_read_only {
          @capability.ReadOnly
        } else if name == "session_send" || name == "tool_approve" {
          @capability.ExternalSideEffect
        } else {
          @capability.StateChange
        },
        is_read_only,
        @capability.External,
        Some(name),
        1,
      ),
    )
    let input_schema = operation_schema(name)
    let capability = @capability.TypedCapability::new_with_validation(
      descriptor,
      value_to_json,
      (output : Json) => Ok(@capability.Value::string(output.stringify())),
      input => {
        if input_schema.accepts(json_to_value(input)) {
          Ok(())
        } else {
          Err(domain_error(name, "input does not match the operation schema"))
        }
      },
      _output => Ok(()),
      input => {
        profiler.measure("api." + name, () => {
          match name {
            "plugin_list" => Ok(plugins.manifest())
            "profile_stats" => Ok(Json::string(profiler.render_text()))
            "session_send" =>
              match @engine.EngineCommand::from_json("session_send", input) {
                Ok(@engine.EngineCommand::SendPrompt(session_id, prompt)) => {
                  let command_result = if !native_session_start_contexts.val.is_empty() ||
                    !native_prompt_contexts.val.is_empty() {
                    engine.apply_session_send_with_hook_contexts(
                      session_id,
                      prompt,
                      native_session_start_contexts.val,
                      native_prompt_contexts.val,
                      source_kind=native_hook_context_source_kind.val,
                    )
                  } else {
                    let command = @engine.EngineCommand::SendPrompt(
                      session_id, prompt,
                    )
                    if preview_session_send.val {
                      engine.preview(command)
                    } else {
                      engine.apply(command)
                    }
                  }
                  match command_result {
                    Ok(value) => Ok(value)
                    Err(error) => Err(domain_error(name, error))
                  }
                }
                Ok(command) =>
                  if preview_session_send.val {
                    match engine.preview(command) {
                      Ok(value) => Ok(value)
                      Err(error) => Err(domain_error(name, error))
                    }
                  } else {
                    match engine.apply(command) {
                      Ok(value) => Ok(value)
                      Err(error) => Err(domain_error(name, error))
                    }
                  }
                Err(error) => Err(domain_error(name, error))
              }
            _ if preview_session_send.val =>
              Err(domain_error(name, "preview accepts only session_send"))
            _ =>
              match engine.invoke(name, input) {
                Ok(value) =>
                  Ok(
                    if name == "session_list" {
                      session_summaries(value)
                    } else {
                      value
                    },
                  )
                Err(error) => Err(domain_error(name, error))
              }
          }
        })
      },
      () => {
        if registry.is_alive() {
          Ok(())
        } else {
          Err(domain_error(name, "application is closed"))
        }
      },
      _origin => Ok(()),
    )
    checked(registry.register(capability))
    operations[name] = capability
  }
  let protocol = @mcp.ProtocolServer::new_with_identity(
    @mcp.Adapter::new(registry),
    "dsh.mbt",
    "0.1.0",
  )
  {
    owner,
    engine,
    registry,
    protocol,
    operations,
    profiler,
    native_prompt_contexts,
    native_session_start_contexts,
    native_hook_context_source_kind,
    preview_session_send,
  }
}

///|
pub fn HarnessApi::new(
  external_mcp_tools? : Array[Json] = [],
  skill_tool? : Json? = None,
  lsp_tool? : Json? = None,
  subagent_tool? : Json? = None,
) -> Result[HarnessApi, String] {
  Ok(create_api(external_mcp_tools, skill_tool, lsp_tool, subagent_tool)) catch {
    InitError(error) => Err(error)
  }
}

///|
/// All direct and GUI calls pass gpui's typed input validation.
pub fn HarnessApi::invoke(
  self : HarnessApi,
  operation : String,
  input : Json,
  origin? : @capability.InvocationOrigin = @capability.Direct,
) -> Result[Json, String] {
  let capability = match self.operations.get(operation) {
    None => return Err("Unknown operation: " + operation)
    Some(capability) => capability
  }
  // Validate the input through Registry, including the same shape used by MCP.
  // GUI binding is also public for an in-process MoonBit UI.
  let result = if origin == @capability.Gui {
    match
      self.registry.invoke("dsh." + operation, origin, json_to_value(input)) {
      Ok(value) => Ok(value)
      Err(error) => Err(error)
    }
  } else {
    self.registry.invoke(
      capability.descriptor().id(),
      origin,
      json_to_value(input),
    )
  }
  match result {
    Err(error) => Err(error_text(error))
    Ok(value) =>
      match value.as_string() {
        Err(error) => Err(error_text(error))
        Ok(raw) =>
          Ok(@json.parse(raw)) catch {
            _ => Err("invalid capability output")
          }
      }
  }
}

///|
/// Check the ordinary closed session_send schema and engine admission rules
/// without adopting state or exposing effects. Native runtimes call this before
/// running a UserPromptSubmit command.
pub fn HarnessApi::preview_session_send(
  self : HarnessApi,
  input : Json,
) -> Result[Json, String] {
  let previous_preview = self.preview_session_send.val
  let previous_contexts = self.native_prompt_contexts.val
  let previous_session_start_contexts = self.native_session_start_contexts.val
  self.preview_session_send.val = true
  self.native_prompt_contexts.val = []
  self.native_session_start_contexts.val = []
  defer {
    self.preview_session_send.val = previous_preview
    self.native_prompt_contexts.val = previous_contexts
    self.native_session_start_contexts.val = previous_session_start_contexts
  }
  self.invoke("session_send", input)
}

///|
/// Dispatch a prompt with trusted native hook context while keeping the
/// external session_send input schema closed.
pub fn HarnessApi::invoke_session_send_with_prompt_contexts(
  self : HarnessApi,
  input : Json,
  contexts : Array[String],
) -> Result[Json, String] {
  self.invoke_session_send_with_hook_contexts(input, [], contexts)
}

///|
/// Dispatch a prompt with source-ordered native hook contexts while keeping
/// the external session_send input schema closed.
pub fn HarnessApi::invoke_session_send_with_hook_contexts(
  self : HarnessApi,
  input : Json,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
  source_kind? : String = "hooks-claude-code",
) -> Result[Json, String] {
  let previous = self.native_prompt_contexts.val
  let previous_session_start = self.native_session_start_contexts.val
  let previous_source_kind = self.native_hook_context_source_kind.val
  self.native_prompt_contexts.val = prompt_contexts
  self.native_session_start_contexts.val = session_start_contexts
  self.native_hook_context_source_kind.val = source_kind
  defer {
    self.native_prompt_contexts.val = previous
    self.native_session_start_contexts.val = previous_session_start
    self.native_hook_context_source_kind.val = previous_source_kind
  }
  self.invoke("session_send", input)
}

///|
/// Run MCP protocol validation and session_send engine admission on an isolated
/// candidate. The returned wire response has the same success/error shape as
/// ordinary MCP dispatch.
pub fn HarnessApi::preview_mcp_handle(
  self : HarnessApi,
  line : String,
) -> String? {
  let previous_preview = self.preview_session_send.val
  let previous_contexts = self.native_prompt_contexts.val
  let previous_session_start_contexts = self.native_session_start_contexts.val
  self.preview_session_send.val = true
  self.native_prompt_contexts.val = []
  self.native_session_start_contexts.val = []
  defer {
    self.preview_session_send.val = previous_preview
    self.native_prompt_contexts.val = previous_contexts
    self.native_session_start_contexts.val = previous_session_start_contexts
  }
  self.protocol.handle_line(line)
}

///|
/// Dispatch an unchanged, validated MCP request while attaching context only
/// inside the native session_send capability handler.
pub fn HarnessApi::mcp_handle_with_prompt_contexts(
  self : HarnessApi,
  line : String,
  contexts : Array[String],
) -> String? {
  self.mcp_handle_with_hook_contexts(line, [], contexts)
}

///|
/// Dispatch an unchanged MCP request with source-ordered native prompt hook
/// contexts attached only inside the native session_send capability handler.
pub fn HarnessApi::mcp_handle_with_hook_contexts(
  self : HarnessApi,
  line : String,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
  source_kind? : String = "hooks-claude-code",
) -> String? {
  let previous = self.native_prompt_contexts.val
  let previous_session_start = self.native_session_start_contexts.val
  let previous_source_kind = self.native_hook_context_source_kind.val
  self.native_prompt_contexts.val = prompt_contexts
  self.native_session_start_contexts.val = session_start_contexts
  self.native_hook_context_source_kind.val = source_kind
  defer {
    self.native_prompt_contexts.val = previous
    self.native_session_start_contexts.val = previous_session_start
    self.native_hook_context_source_kind.val = previous_source_kind
  }
  self.protocol.handle_line(line)
}

///|
pub fn HarnessApi::gui_binding(
  self : HarnessApi,
  operation : String,
) -> @capability.GuiBinding[Json, Json]? {
  self.operations.get(operation).map(capability => capability.gui_binding())
}

///|
pub fn HarnessApi::mcp_handle(self : HarnessApi, line : String) -> String? {
  self.protocol.handle_line(line)
}

///|
pub fn HarnessApi::manifest(self : HarnessApi) -> String {
  self.registry.external_manifest_json()
}

///|
pub fn HarnessApi::take_effects(self : HarnessApi) -> Array[Json] {
  if self.registry.is_alive() {
    self.engine.take_effects()
  } else {
    []
  }
}

///|
/// Drain host work as typed engine effects for native in-process runtimes.
pub fn HarnessApi::take_typed_effects(
  self : HarnessApi,
) -> Array[@engine.EngineEffect] {
  if self.registry.is_alive() {
    self.engine.take_typed_effects()
  } else {
    []
  }
}

///|
pub fn HarnessApi::complete(
  self : HarnessApi,
  id : String,
  result : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.complete", () => {
    self.engine.complete(id, result)
  })
}

///|
/// Typed effect settlement for native runtimes that retain the effect identity.
pub fn HarnessApi::complete_effect(
  self : HarnessApi,
  id : @engine.EffectId,
  result : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.complete", () => {
    self.engine.complete_effect(id, result)
  })
}

///|
/// Native-runtime completion that pauses a final provider outcome for the
/// configured Stop-hook command before it may finish or continue the turn.
pub fn HarnessApi::complete_effect_with_stop_hook(
  self : HarnessApi,
  id : @engine.EffectId,
  result : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.complete", () => {
    self.engine.complete_effect_with_stop_hook(id, result)
  })
}

///|
/// Native tool completion that pauses a committed PostToolUse inbox batch for
/// UserPromptSubmit before the next provider request is released.
pub fn HarnessApi::complete_effect_with_post_tool_prompt_hook(
  self : HarnessApi,
  id : @engine.EffectId,
  result : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.complete", () => {
    self.engine.complete_effect_with_post_tool_prompt_hook(id, result)
  })
}

///|
pub fn HarnessApi::pending_post_tool_prompt_hook(
  self : HarnessApi,
  session_id : @engine.SessionId,
) -> @engine.NativePostToolPromptHookCheckpoint? {
  if self.registry.is_alive() {
    self.engine.pending_post_tool_prompt_hook(session_id)
  } else {
    None
  }
}

///|
pub fn HarnessApi::accept_post_tool_prompt_hook(
  self : HarnessApi,
  checkpoint : @engine.NativePostToolPromptHookCheckpoint,
  contexts : Array[String],
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.post_tool_prompt_hook_accept", () => {
    self.engine.accept_post_tool_prompt_hook(checkpoint, contexts)
  })
}

///|
pub fn HarnessApi::block_post_tool_prompt_hook(
  self : HarnessApi,
  checkpoint : @engine.NativePostToolPromptHookCheckpoint,
  reason : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.post_tool_prompt_hook_block", () => {
    self.engine.block_post_tool_prompt_hook(checkpoint, reason)
  })
}

///|
pub fn HarnessApi::pending_stop_hook(
  self : HarnessApi,
  session_id : @engine.SessionId,
) -> @engine.NativeStopHookCheckpoint? {
  if self.registry.is_alive() {
    self.engine.pending_stop_hook(session_id)
  } else {
    None
  }
}

///|
pub fn HarnessApi::prepare_stop_continuation(
  self : HarnessApi,
  checkpoint : @engine.NativeStopHookCheckpoint,
  text : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.stop_hook_prepare", () => {
    self.engine.prepare_stop_continuation(checkpoint, text)
  })
}

///|
pub fn HarnessApi::finish_stop_hook(
  self : HarnessApi,
  checkpoint : @engine.NativeStopHookCheckpoint,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.stop_hook_finish", () => {
    self.engine.finish_stop_hook(checkpoint)
  })
}

///|
pub fn HarnessApi::continue_stop_hook(
  self : HarnessApi,
  checkpoint : @engine.NativeStopHookCheckpoint,
  contexts : Array[String],
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.stop_hook_continue", () => {
    self.engine.continue_stop_hook(checkpoint, contexts)
  })
}

///|
pub fn HarnessApi::block_stop_continuation(
  self : HarnessApi,
  checkpoint : @engine.NativeStopHookCheckpoint,
  denial_reason : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.stop_hook_block", () => {
    self.engine.block_stop_continuation(checkpoint, denial_reason)
  })
}

///|
/// Record a known host tool outcome without retiring its effect. Native hosts
/// use this to protect completed side effects while they run post-tool hooks.
pub fn HarnessApi::record_effect_outcome(
  self : HarnessApi,
  id : @engine.EffectId,
  result : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.record_effect_outcome", () => {
    self.engine.record_effect_outcome(id.as_string(), result)
  })
}

///|
pub fn HarnessApi::schedule_retry(
  self : HarnessApi,
  id : String,
  policy : Json,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.schedule_retry", () => {
    self.engine.schedule_retry(id, policy)
  })
}

///|
pub fn HarnessApi::start_retry(
  self : HarnessApi,
  id : String,
  retry_id : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.start_retry", () => {
    self.engine.start_retry(id, retry_id)
  })
}

///|
/// Admit provider text/reasoning progress under the active LLM effect identity.
pub fn HarnessApi::project_stream(
  self : HarnessApi,
  effect_id : String,
  content : String,
  reasoning : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.project_stream", () => {
    self.engine.project_stream(effect_id, content, reasoning)
  })
}

///|
/// Typed stream projection for hosts holding an admitted provider effect.
pub fn HarnessApi::project_effect_stream(
  self : HarnessApi,
  effect_id : @engine.EffectId,
  content : String,
  reasoning : String,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.profiler.measure("engine.project_stream", () => {
    self.engine.project_effect_stream(effect_id, content, reasoning)
  })
}

///|
/// Typed append-only event view for in-process native consumers.
pub fn HarnessApi::event_log(
  self : HarnessApi,
  session_id : @engine.SessionId,
) -> Result[Array[@engine.EngineEvent], String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.engine.event_log(session_id)
}

///|
/// Durably admit a native hook invocation before its command process starts.
pub fn HarnessApi::record_native_hook_invoked(
  self : HarnessApi,
  session_id : String,
  point : String,
  handler_id : String,
  matcher : String?,
  dialect? : String = "claude-code",
) -> Result[@engine.NativeHookInvocationCheckpoint, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.engine.record_native_hook_invoked(
    session_id,
    point,
    handler_id,
    matcher,
    dialect~,
  )
}

///|
/// Record the completed native hook outcome for its exact invocation.
pub fn HarnessApi::record_native_hook_result(
  self : HarnessApi,
  checkpoint : @engine.NativeHookInvocationCheckpoint,
  decision : String,
  exit_code : Int?,
  stderr_summary : String?,
  duration_ms : Int,
) -> Result[Json, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.engine.record_native_hook_result(
    checkpoint, decision, exit_code, stderr_summary, duration_ms,
  )
}

///|
pub fn HarnessApi::snapshot(self : HarnessApi) -> Json {
  self.engine.snapshot()
}

///|
pub fn HarnessApi::restore(
  self : HarnessApi,
  snapshot : Json,
) -> Result[Unit, String] {
  if !self.registry.is_alive() {
    return Err("application is closed")
  }
  self.engine.restore(snapshot)
}

///|
pub fn HarnessApi::close(self : HarnessApi) -> Unit {
  if !self.registry.is_alive() {
    return
  }
  match self.engine.invoke("session_list", Json::empty_object()) {
    Ok(Array(sessions)) =>
      for session in sessions {
        if session is { "id": String(id), "status": String(status), .. } {
          if status == "running" {
            self.engine.invoke("session_cancel", { "session_id": id.to_json() })
            |> ignore
          }
        }
      }
    _ => ()
  }
  self.protocol.close()
  self.registry.teardown()
  self.owner.request_stop() |> ignore
}
