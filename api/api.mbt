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
            for key in ["id", "title", "status", "turn_id", "step"] {
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
fn create_api() -> HarnessApi raise InitError {
  let owner = checked(@core.App::new())
  checked(owner.start())
  let registry = checked(@capability.Registry::new_owned(owner))
  let plugins = match @plugins.defaults() {
    Ok(plugins) => plugins
    Err(error) => raise InitError(error)
  }
  let engine = @engine.Engine::new(plugins.tools())
  let profiler = @hotpath.Profiler::new()
  let operations : Map[String, @capability.TypedCapability[Json, Json]] = Map([])
  for
    (name, title, description, is_read_only) in [
      (
        "session_create", "Create session", "Create a conversation with an append-only MoonBit event log.",
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
  { owner, engine, registry, protocol, operations, profiler, }
}

///|
pub fn HarnessApi::new() -> Result[HarnessApi, String] {
  Ok(create_api()) catch {
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
          if status == "running" || status == "awaiting_approval" {
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
