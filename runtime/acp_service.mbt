///|
const NATIVE_ACP_AGENT_VERSION : String = "0.1.11"

///|
priv struct NativeAcpRpcError {
  code : Int
  message : String
}

///|
priv struct NativeAcpPendingPermission {
  id : Json
  key : String
  session_id : String
  native_session_id : String
  call_id : String
  generation : Int
  revision : Int
  response : Ref[Json?]
  resolved : Ref[Bool]
  ready : @async.Semaphore
}

///|
priv struct NativeAcpSession {
  session_id : String
  native_session_id : String
  event_gate : @async.Mutex
  mut last_event_seq : Int
  mut prompt_generation : Int
  mut prompt_active : Bool
  mut resuming : Bool
  mut cancelled : Bool
  mut closing : Bool
  mut closed : Bool
  mut cancel_required : Bool
  mut cancel_sent : Bool
  mut prompt_done : NativeAcpCompletion?
  mut pending_permission : NativeAcpPendingPermission?
}

///|
priv struct NativeAcpCompletion {
  mut completed : Bool
  mut waiters : Array[@async.Semaphore]
}

///|
fn NativeAcpCompletion::new() -> NativeAcpCompletion {
  { completed: false, waiters: [], }
}

///|
async fn NativeAcpCompletion::wait(self : NativeAcpCompletion) -> Unit {
  if self.completed {
    return
  }
  let waiter = @async.Semaphore::Semaphore(1, initial_value=0)
  self.waiters.push(waiter)
  waiter.acquire()
}

///|
fn NativeAcpCompletion::resolve(self : NativeAcpCompletion) -> Unit {
  if self.completed {
    return
  }
  self.completed = true
  let waiters = self.waiters
  self.waiters = []
  for waiter in waiters {
    waiter.release()
  }
}

///|
priv struct NativeAcpService {
  runtime : NativeRuntime
  workspace : String
  sink : async (String) -> Result[Unit, String]
  write_gate : @async.Mutex
  sessions : Map[String, NativeAcpSession]
  pending_permissions : Map[String, NativeAcpPendingPermission]
  model_allowlist : Array[String]
  model_config_error : String?
  mut next_request_id : Int
  mut initialized : Bool
  mut closed : Bool
}

///|
priv struct NativeAcpPreparedPrompt {
  session : NativeAcpSession
  text : String
  generation : Int
  done : NativeAcpCompletion
}

///|
priv enum NativeAcpPermissionDecision {
  AllowOnce
  RejectOnce
  Cancelled
}

///|
fn NativeAcpService::new(
  runtime : NativeRuntime,
  sink : async (String) -> Result[Unit, String],
) -> NativeAcpService {
  NativeAcpService::new_with_model_config(
    runtime,
    sink,
    native_acp_parse_model_allowlist(@env.get_env_var("DSH_ACP_MODELS")),
  )
}

///|
fn NativeAcpService::new_with_model_config(
  runtime : NativeRuntime,
  sink : async (String) -> Result[Unit, String],
  model_config : Result[Array[String], String],
) -> NativeAcpService {
  let (model_allowlist, model_config_error) = match model_config {
    Ok(value) => (value, None)
    Err(error) => ([], Some(error))
  }
  {
    runtime,
    workspace: runtime.tools.workspace,
    sink,
    write_gate: @async.Mutex::Mutex(),
    sessions: Map([]),
    pending_permissions: Map([]),
    model_allowlist,
    model_config_error,
    next_request_id: 1,
    initialized: false,
    closed: false,
  }
}

///|
async fn NativeAcpService::write_json(
  self : NativeAcpService,
  value : Json,
) -> Result[Unit, String] {
  let line = value.stringify()
  if @utf8.encode(line).length() > NATIVE_ACP_LINE_LIMIT {
    return Err("ACP JSON-RPC output exceeds the 1 MiB limit")
  }
  self.write_gate.acquire()
  defer self.write_gate.release()
  (self.sink)(line)
}

///|
async fn NativeAcpService::write_response(
  self : NativeAcpService,
  id : Json,
  result : Json,
) -> Result[Unit, String] {
  self.write_json(@json.parse(native_acp_rpc_success(id, result)))
}

///|
async fn NativeAcpService::write_error(
  self : NativeAcpService,
  id : Json,
  error : NativeAcpRpcError,
) -> Result[Unit, String] {
  self.write_json(
    @json.parse(native_acp_rpc_error(id, error.code, error.message)),
  )
}

///|
async fn NativeAcpService::write_notification(
  self : NativeAcpService,
  method_name : String,
  params : Json,
) -> Result[Unit, String] {
  self.write_json({ "jsonrpc": "2.0", "method": method_name, "params": params })
}

///|
fn native_acp_invalid_params(message : String) -> NativeAcpRpcError {
  { code: -32602, message, }
}

///|
fn native_acp_internal_error(message : String) -> NativeAcpRpcError {
  { code: -32603, message, }
}

///|
fn NativeAcpService::require_initialized(
  self : NativeAcpService,
) -> Result[Unit, NativeAcpRpcError] {
  if self.closed {
    Err(native_acp_internal_error("ACP connection is closed"))
  } else if !self.initialized {
    Err({
      code: -32002,
      message: "initialize must be called before this method",
    })
  } else {
    Ok(())
  }
}

///|
async fn NativeAcpService::handle_request(
  self : NativeAcpService,
  method_name : String,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  match method_name {
    "initialize" => self.initialize(params)
    "authenticate" =>
      match self.require_initialized() {
        Ok(_) => Ok(Json::empty_object())
        Err(error) => Err(error)
      }
    "session/new" => self.new_session(params)
    "session/list" => self.list_sessions(params)
    "session/resume" => self.resume_session(params)
    "session/close" => self.close_session(params)
    "session/set_config_option" => self.set_config_option(params)
    "session/prompt" => self.prompt(params)
    "session/cancel" => {
      match self.require_initialized() {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let session_id = native_acp_required_session_id(params)
      match session_id {
        Err(error) => Err(error)
        Ok(id) =>
          match self.cancel_session(id, false) {
            Ok(_) => Ok(Json::empty_object())
            Err(error) => Err(error)
          }
      }
    }
    _ => Err({ code: -32601, message: "method not found", })
  }
}

///|
fn NativeAcpService::initialize(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  if self.initialized {
    return Err({ code: -32600, message: "initialize may only be called once", })
  }
  match object_field(params, "protocolVersion") {
    Some(Json::Number(value, ..)) if native_acp_safe_integer(value) &&
      value == NATIVE_ACP_PROTOCOL_VERSION.to_double() => ()
    Some(Json::Number(_, ..)) =>
      return Err(
        native_acp_invalid_params("only ACP protocol version 1 is supported"),
      )
    _ =>
      return Err(
        native_acp_invalid_params("protocolVersion must be an integer"),
      )
  }
  match self.model_config_error {
    Some(error) => return Err(native_acp_internal_error(error))
    None => ()
  }
  self.initialized = true
  Ok({
    "protocolVersion": NATIVE_ACP_PROTOCOL_VERSION,
    "agentInfo": {
      "name": "deepseek-harness-acp",
      "version": NATIVE_ACP_AGENT_VERSION,
    },
    "agentCapabilities": {
      "promptCapabilities": {
        "image": false,
        "audio": false,
        "embeddedContext": false,
      },
      "sessionCapabilities": { "list": {}, "resume": {}, "close": {} },
    },
    "authMethods": [],
  })
}

///|
async fn NativeAcpService::new_session(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  match self.require_initialized() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match native_acp_validate_new_session(params, self.workspace) {
    Ok(_) => ()
    Err(error) => return Err(native_acp_invalid_params(error))
  }
  let default_model = self.runtime.acp_default_model()
  let route = match self.runtime.acp_route_id() {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let config_options = match
    self.runtime.acp_model_options(default_model, self.model_allowlist) {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let random = match random_uuid() {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let native_session_id = "acp-" + random
  let created = match
    self.runtime.create_acp_session(
      native_session_id,
      self.workspace,
      default_model,
      route,
    ) {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let session_id = match string_field(created, "id") {
    Some(value) => value
    None =>
      return Err(
        native_acp_internal_error("native session creation returned no id"),
      )
  }
  let session : NativeAcpSession = {
    session_id,
    native_session_id,
    event_gate: @async.Mutex::Mutex(),
    last_event_seq: 0,
    prompt_generation: 0,
    prompt_active: false,
    resuming: false,
    cancelled: false,
    closing: false,
    closed: false,
    cancel_required: false,
    cancel_sent: false,
    prompt_done: None,
    pending_permission: None,
  }
  self.sessions.set(session_id, session)
  Ok({ "sessionId": Json::string(session_id), "configOptions": config_options })
}

///|
async fn NativeAcpService::set_config_option(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  match self.require_initialized() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let session_id = match native_acp_required_session_id(params) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let session = match self.find_session(session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if session.closing || session.resuming || session.prompt_active {
    return Err(native_acp_invalid_params("session is active or busy"))
  }
  match string_field(params, "configId") {
    Some(NATIVE_ACP_MODEL_CONFIG_ID) => ()
    _ => return Err(native_acp_invalid_params("unknown session config option"))
  }
  let value = match object_field(params, "value") {
    Some(Json::String(text)) => Json::string(text)
    _ => return Err(native_acp_invalid_params("model requires a select value"))
  }
  let model = match
    self.runtime.acp_model_from_value(value, self.model_allowlist) {
    Ok(value) => value
    Err(error) => return Err(native_acp_invalid_params(error))
  }
  let (state, record) = match self.runtime.read_acp_session(session_id) {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  if record is None {
    return Err(native_acp_invalid_params("session is not registered for ACP"))
  }
  let route = match self.runtime.acp_route_id() {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  match string_field(state, "status") {
    Some("idle") | Some("completed") | Some("failed") | Some("cancelled") => ()
    Some("running") | Some("awaiting_approval") =>
      return Err(native_acp_invalid_params("session is active or busy"))
    _ =>
      return Err(native_acp_invalid_params("session has an unsupported state"))
  }
  match self.runtime.set_acp_session_model(session_id, Some(model), route) {
    Ok(_) => ()
    Err(error) if error == "ACP session is active or busy" =>
      return Err(native_acp_invalid_params(error))
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let config_options = match
    self.runtime.acp_model_options(Some(model), self.model_allowlist) {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  match
    self.write_notification(
      "session/update",
      Json::object({
        "sessionId": Json::string(session_id),
        "update": Json::object({
          "sessionUpdate": Json::string("config_option_update"),
          "configOptions": config_options,
        }),
      }),
    ) {
    Ok(_) => ()
    Err(error) => return Err(native_acp_internal_error(error))
  }
  Ok({ "configOptions": config_options })
}

///|
async fn native_acp_validate_new_session(
  params : Json,
  workspace : String,
) -> Result[Unit, String] {
  let requested_cwd = match string_field(params, "cwd") {
    Some(value) if !value.is_empty() && value.length() <= 4096 => value
    _ => return Err("cwd must be a nonempty absolute path")
  }
  if !requested_cwd.has_prefix("/") {
    return Err("cwd must be an absolute path")
  }
  let canonical_cwd = @fs.realpath(requested_cwd) catch {
    _ => return Err("cwd must identify the configured workspace")
  }
  if canonical_cwd != workspace {
    return Err("ACP sessions are limited to the configured workspace")
  }
  match object_field(params, "additionalDirectories") {
    None | Some(Json::Null) => ()
    Some(Json::Array(values)) if values.length() == 0 => ()
    Some(_) => return Err("additionalDirectories is not supported")
  }
  match object_field(params, "mcpServers") {
    Some(Json::Array(values)) if values.length() == 0 => ()
    Some(Json::Array(_)) =>
      return Err("ACP session MCP server mounts are not supported")
    _ => return Err("mcpServers must be an array")
  }
  Ok(())
}

///|
fn native_acp_required_session_id(
  params : Json,
) -> Result[String, NativeAcpRpcError] {
  match string_field(params, "sessionId") {
    Some(value) if !value.is_empty() && value.length() <= 128 => Ok(value)
    _ => Err(native_acp_invalid_params("sessionId must be a nonempty string"))
  }
}

///|
fn NativeAcpService::find_session(
  self : NativeAcpService,
  session_id : String,
) -> Result[NativeAcpSession, NativeAcpRpcError] {
  match self.sessions.get(session_id) {
    Some(session) if !session.closed => Ok(session)
    None => Err(native_acp_invalid_params("unknown session: " + session_id))
    Some(_) => Err(native_acp_invalid_params("unknown session: " + session_id))
  }
}

///|
fn native_acp_prompt_text(params : Json) -> Result[String, String] {
  let blocks = match object_field(params, "prompt") {
    Some(Json::Array(values)) if values.length() > 0 && values.length() <= 64 =>
      values
    Some(Json::Array(_)) =>
      return Err("prompt must contain 1 to 64 content blocks")
    _ => return Err("prompt must be an array of content blocks")
  }
  let prompt = StringBuilder()
  let mut length = 0
  for block in blocks {
    match string_field(block, "type") {
      Some("text") => {
        let text = match string_field(block, "text") {
          Some(value) if value.length() <= NATIVE_ACP_MAX_PROMPT_CHARS => value
          _ =>
            return Err(
              "text content block is missing text or exceeds its limit",
            )
        }
        length += text.length()
        if length > NATIVE_ACP_MAX_PROMPT_CHARS {
          return Err("prompt exceeds the 16 KiB character limit")
        }
        prompt.write_string(text)
      }
      Some("resource_link") => {
        let name = match string_field(block, "name") {
          Some(value) if !value.is_empty() && value.length() <= 1024 => value
          _ => return Err("resource_link name must be a nonempty string")
        }
        let uri = match string_field(block, "uri") {
          Some(value) if !value.is_empty() && value.length() <= 4096 => value
          _ => return Err("resource_link uri must be a nonempty string")
        }
        let rendered = "[resource_link name=" + name + " uri=" + uri + "]"
        length += rendered.length()
        if length > NATIVE_ACP_MAX_PROMPT_CHARS {
          return Err("prompt exceeds the 16 KiB character limit")
        }
        prompt.write_string(rendered)
      }
      Some(_) =>
        return Err("only text and resource_link prompt blocks are supported")
      None => return Err("prompt content block is missing type")
    }
  }
  let result = prompt.to_string()
  if result.trim().is_empty() {
    Err("prompt must not be empty")
  } else {
    Ok(result)
  }
}

///|
fn NativeAcpService::prepare_prompt(
  self : NativeAcpService,
  params : Json,
) -> Result[NativeAcpPreparedPrompt, NativeAcpRpcError] {
  match self.require_initialized() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let session_id = match native_acp_required_session_id(params) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let session = match self.find_session(session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if session.closing {
    return Err(native_acp_invalid_params("session is closing"))
  }
  if session.resuming {
    return Err(native_acp_invalid_params("session resume is still in progress"))
  }
  if session.prompt_active {
    return Err(
      native_acp_invalid_params(
        "a prompt is already in flight for this session",
      ),
    )
  }
  let text = match native_acp_prompt_text(params) {
    Ok(value) => value
    Err(error) => return Err(native_acp_invalid_params(error))
  }
  session.prompt_generation += 1
  session.prompt_active = true
  session.cancelled = false
  session.cancel_required = false
  session.cancel_sent = false
  let done = NativeAcpCompletion::new()
  session.prompt_done = Some(done)
  Ok({ session, text, generation: session.prompt_generation, done, })
}

///|
async fn NativeAcpService::prompt(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  let prepared = match self.prepare_prompt(params) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.execute_prompt(prepared)
}

///|
async fn NativeAcpService::execute_prompt(
  self : NativeAcpService,
  prepared : NativeAcpPreparedPrompt,
) -> Result[Json, NativeAcpRpcError] {
  let outcome = self.run_prompt_turn(prepared)
  prepared.session.pending_permission = None
  prepared.session.prompt_active = false
  prepared.session.prompt_done = None
  prepared.done.resolve()
  let activity = self.runtime.record_acp_activity(
    prepared.session.native_session_id,
  )
  match (outcome, activity) {
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(native_acp_internal_error(error))
    (Ok(value), Ok(_)) => Ok(value)
  }
}

///|
async fn NativeAcpService::run_prompt_turn(
  self : NativeAcpService,
  prepared : NativeAcpPreparedPrompt,
) -> Result[Json, NativeAcpRpcError] {
  let session = prepared.session
  let send = match
    native_cli_command(
      self.runtime,
      Some(session.native_session_id),
      "session_send",
      { "prompt": Json::string(prepared.text) },
      None,
      acp_activity_session_id=session.native_session_id,
    ) {
    Ok(value) => value
    Err(error) => {
      if session.cancelled {
        return Ok({ "stopReason": "cancelled" })
      }
      return Err(native_acp_internal_error(error))
    }
  }
  if string_field(send, "status") != Some("completed") {
    if session.cancelled ||
      self.closed ||
      session.closing ||
      session.prompt_generation != prepared.generation {
      return Ok({ "stopReason": "cancelled" })
    }
    return Err(
      native_acp_internal_error("native prompt was not durably accepted"),
    )
  }
  let mut current = match self.native_session(session) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.emit_committed_events(session, current) {
    Ok(_) => ()
    Err(error) => return Err(native_acp_internal_error(error))
  }
  while string_field(current, "status") == Some("awaiting_approval") {
    if session.cancelled ||
      self.closed ||
      session.closing ||
      session.prompt_generation != prepared.generation {
      return Ok({ "stopReason": "cancelled" })
    }
    let pending = match object_field(current, "pending_approval") {
      Some(value) => value
      None =>
        return Err(
          native_acp_internal_error("native approval state has no pending call"),
        )
    }
    let call_id = match string_field(pending, "call_id") {
      Some(value) => value
      None =>
        return Err(
          native_acp_internal_error("native approval state has no call id"),
        )
    }
    let revision = match native_cli_approval_revision_number(current) {
      Some(value) => value
      None =>
        return Err(
          native_acp_internal_error("native approval has no durable revision"),
        )
    }
    let (decision, permission) = match
      self.request_permission(
        session,
        pending,
        call_id,
        revision,
        prepared.generation,
      ) {
      Ok(value) => value
      Err(error) => {
        if session.cancelled || self.closed || session.closing {
          return Ok({ "stopReason": "cancelled" })
        }
        return Err(native_acp_internal_error(error))
      }
    }
    if session.cancelled ||
      self.closed ||
      session.closing ||
      session.prompt_generation != prepared.generation {
      return Ok({ "stopReason": "cancelled" })
    }
    if !native_acp_permission_matches(
        session,
        permission,
        current,
        prepared.generation,
      ) {
      if session.cancelled || self.closed || session.closing {
        return Ok({ "stopReason": "cancelled" })
      }
      return Err(
        native_acp_internal_error(
          "permission response no longer matches the pending native call",
        ),
      )
    }
    session.pending_permission = None
    let approved = match decision {
      NativeAcpPermissionDecision::AllowOnce => true
      NativeAcpPermissionDecision::RejectOnce => false
      NativeAcpPermissionDecision::Cancelled => {
        match self.cancel_session(session.session_id, false) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        return Ok({ "stopReason": "cancelled" })
      }
    }
    let approval = match
      native_cli_command(
        self.runtime,
        Some(session.native_session_id),
        "tool_approve",
        { "call_id": call_id.to_json(), "approved": approved.to_json() },
        Some(revision),
        acp_activity_session_id=session.native_session_id,
      ) {
      Ok(value) => value
      Err(error) => {
        if session.cancelled {
          return Ok({ "stopReason": "cancelled" })
        }
        return Err(native_acp_internal_error(error))
      }
    }
    if string_field(approval, "status") != Some("completed") {
      if session.cancelled {
        return Ok({ "stopReason": "cancelled" })
      }
      return Err(
        native_acp_internal_error(
          "native tool approval was not durably settled",
        ),
      )
    }
    current = match self.native_session(session) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match self.emit_committed_events(session, current) {
      Ok(_) => ()
      Err(error) => return Err(native_acp_internal_error(error))
    }
  }
  if session.cancelled ||
    self.closed ||
    session.closing ||
    session.prompt_generation != prepared.generation {
    Ok({ "stopReason": "cancelled" })
  } else {
    match native_acp_stop_reason(current) {
      Ok(reason) => Ok({ "stopReason": reason })
      Err(error) => Err(native_acp_internal_error(error))
    }
  }
}

///|
async fn NativeAcpService::native_session(
  self : NativeAcpService,
  session : NativeAcpSession,
) -> Result[Json, NativeAcpRpcError] {
  match self.runtime.read_acp_session(session.native_session_id) {
    Ok((value, _)) => Ok(value)
    Err(error) => Err(native_acp_internal_error(error))
  }
}

///|
fn native_acp_stop_reason(session : Json) -> Result[String, String] {
  if string_field(session, "status") == Some("cancelled") {
    return Ok("cancelled")
  }
  let events = match object_field(session, "events") {
    Some(Json::Array(values)) => values
    _ if string_field(session, "status") == Some("failed") =>
      return Err("native provider turn failed")
    _ => return Ok("end_turn")
  }
  let turn_id = int_field(session, "turn_id").unwrap_or(-1)
  for index = events.length() - 1; index >= 0; index = index - 1 {
    let event = events[index]
    if string_field(event, "type") == Some("turn/end") &&
      int_field(event, "turn_id").unwrap_or(-2) == turn_id {
      let data = object_field(event, "data").unwrap_or(Json::null())
      match string_field(data, "reason") {
        Some("max_tokens") => return Ok("max_tokens")
        Some("refusal") => return Ok("refusal")
        _ if string_field(session, "status") == Some("failed") =>
          return Err("native provider turn failed")
        _ => return Ok("end_turn")
      }
    }
  }
  if string_field(session, "status") == Some("failed") {
    Err("native provider turn failed")
  } else {
    Ok("end_turn")
  }
}

///|
async fn NativeAcpService::emit_committed_events(
  self : NativeAcpService,
  session : NativeAcpSession,
  state : Json,
) -> Result[Unit, String] {
  session.event_gate.acquire()
  defer session.event_gate.release()
  let events = match object_field(state, "events") {
    Some(Json::Array(values)) => values
    _ => return Err("native session event projection is malformed")
  }
  for event in events {
    let seq = int_field(event, "seq").unwrap_or(-1)
    if seq <= session.last_event_seq {
      continue
    }
    let event_type = string_field(event, "type").unwrap_or("")
    let data = object_field(event, "data").unwrap_or(Json::null())
    match event_type {
      "assistant/message" => {
        let message = object_field(data, "message").unwrap_or(Json::null())
        let message_id = "dsh-" + seq.to_string()
        let thought = match string_field(message, "reasoning") {
          Some(text) if !text.is_empty() =>
            self.send_text_chunks(
              session.session_id,
              "agent_thought_chunk",
              message_id,
              text,
            )
          _ => Ok(())
        }
        match thought {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        let content = match string_field(message, "content") {
          Some(text) if !text.is_empty() =>
            self.send_text_chunks(
              session.session_id,
              "agent_message_chunk",
              message_id,
              text,
            )
          _ => Ok(())
        }
        match content {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      "tool/call" => {
        let call_id = string_field(data, "id").unwrap_or("")
        let name = string_field(data, "name").unwrap_or("tool")
        let update = Map::from_array([
          ("sessionUpdate", Json::string("tool_call")),
          ("toolCallId", Json::string(call_id)),
          ("title", Json::string(name)),
          ("kind", Json::string("other")),
          ("status", Json::string("in_progress")),
        ])
        match string_field(data, "arguments") {
          Some(arguments) =>
            match native_acp_parse_tool_arguments(arguments) {
              Some(value) => update.set("rawInput", value)
              None => ()
            }
          None => ()
        }
        match
          self.write_notification(
            "session/update",
            Json::object({
              "sessionId": Json::string(session.session_id),
              "update": Json::object(update),
            }),
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      "tool/result" => {
        let call_id = string_field(data, "tool_call_id").unwrap_or("")
        let text = string_field(data, "content").unwrap_or("")
        let status = if native_json_true(object_field(data, "is_error")) {
          "failed"
        } else {
          "completed"
        }
        let content : Array[Json] = []
        for chunk in native_acp_split_text(text) {
          content.push({
            "type": "content",
            "content": { "type": "text", "text": chunk },
          })
        }
        match
          self.write_notification(
            "session/update",
            Json::object({
              "sessionId": Json::string(session.session_id),
              "update": Json::object({
                "sessionUpdate": "tool_call_update",
                "toolCallId": call_id,
                "status": status,
                "content": Json::array(content),
              }),
            }),
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      _ => ()
    }
    session.last_event_seq = seq
  }
  Ok(())
}

///|
async fn NativeAcpService::send_text_chunks(
  self : NativeAcpService,
  session_id : String,
  update_kind : String,
  message_id : String,
  text : String,
) -> Result[Unit, String] {
  for chunk in native_acp_split_text(text) {
    match
      self.write_notification(
        "session/update",
        Json::object({
          "sessionId": Json::string(session_id),
          "update": Json::object({
            "sessionUpdate": Json::string(update_kind),
            "messageId": Json::string(message_id),
            "content": { "type": "text", "text": Json::string(chunk) },
          }),
        }),
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn NativeAcpService::request_permission(
  self : NativeAcpService,
  session : NativeAcpSession,
  approval : Json,
  call_id : String,
  revision : Int,
  generation : Int,
) -> Result[(NativeAcpPermissionDecision, NativeAcpPendingPermission), String] {
  let id = Json::number(self.next_request_id.to_double())
  let key = native_acp_id_key(id).unwrap()
  self.next_request_id += 1
  let pending : NativeAcpPendingPermission = {
    id,
    key,
    session_id: session.session_id,
    native_session_id: session.native_session_id,
    call_id,
    generation,
    revision,
    response: Ref(None),
    resolved: Ref(false),
    ready: @async.Semaphore::Semaphore(1, initial_value=0),
  }
  self.pending_permissions.set(key, pending)
  session.pending_permission = Some(pending)
  let name = string_field(approval, "name").unwrap_or("tool")
  let arguments = object_field(approval, "arguments").unwrap_or(
    Json::empty_object(),
  )
  let tool_call : Map[String, Json] = Map::from_array([
    ("toolCallId", Json::string(call_id)),
    ("title", Json::string(name)),
    ("kind", Json::string("other")),
    ("status", Json::string("pending")),
  ])
  match native_acp_parse_tool_arguments(arguments.stringify()) {
    Some(value) => tool_call.set("rawInput", value)
    None => ()
  }
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "method": Json::string("session/request_permission"),
    "params": Json::object({
      "sessionId": Json::string(session.session_id),
      "toolCall": Json::object(tool_call),
      "options": Json::array([
        Json::object({
          "optionId": Json::string("allow-once"),
          "name": Json::string("Allow once"),
          "kind": Json::string("allow_once"),
        }),
        Json::object({
          "optionId": Json::string("reject-once"),
          "name": Json::string("Reject"),
          "kind": Json::string("reject_once"),
        }),
      ]),
    }),
  })
  match self.write_json(request) {
    Ok(_) => ()
    Err(error) => {
      self.pending_permissions.remove(key)
      session.pending_permission = None
      return Err(error)
    }
  }
  pending.ready.acquire()
  let response = pending.response.val
  if self.pending_permissions.get(key) is Some(_) {
    self.pending_permissions.remove(key)
  }
  if session.cancelled ||
    session.closing ||
    self.closed ||
    session.prompt_generation != generation {
    return Ok((NativeAcpPermissionDecision::Cancelled, pending))
  }
  Ok((native_acp_permission_decision(response), pending))
}

///|
/// Tie an ACP answer to the exact still-pending durable approval and prompt.
fn native_acp_permission_matches(
  session : NativeAcpSession,
  pending : NativeAcpPendingPermission,
  state : Json,
  generation : Int,
) -> Bool {
  if pending.native_session_id != session.native_session_id ||
    pending.session_id != session.session_id ||
    pending.generation != generation ||
    session.prompt_generation != generation {
    return false
  }
  match session.pending_permission {
    Some(current) if current.key == pending.key && current.id == pending.id =>
      ()
    _ => return false
  }
  if string_field(state, "status") != Some("awaiting_approval") ||
    native_cli_approval_revision_number(state) != Some(pending.revision) {
    return false
  }
  match object_field(state, "pending_approval") {
    Some(approval) => string_field(approval, "call_id") == Some(pending.call_id)
    None => false
  }
}

///|
fn native_acp_permission_decision(
  response : Json?,
) -> NativeAcpPermissionDecision {
  let message = match response {
    Some(Json::Object(_)) => response.unwrap()
    _ => return NativeAcpPermissionDecision::RejectOnce
  }
  if object_field(message, "error") is Some(_) {
    return NativeAcpPermissionDecision::RejectOnce
  }
  let result = match object_field(message, "result") {
    Some(Json::Object(_)) => object_field(message, "result").unwrap()
    _ => return NativeAcpPermissionDecision::RejectOnce
  }
  let outcome = object_field(result, "outcome").unwrap_or(Json::null())
  match string_field(outcome, "outcome") {
    Some("cancelled") => NativeAcpPermissionDecision::Cancelled
    Some("selected") =>
      match string_field(outcome, "optionId") {
        Some("allow-once") => NativeAcpPermissionDecision::AllowOnce
        _ => NativeAcpPermissionDecision::RejectOnce
      }
    _ => NativeAcpPermissionDecision::RejectOnce
  }
}

///|
fn native_acp_resolve_permission(
  pending : NativeAcpPendingPermission,
  response : Json,
) -> Unit {
  if !pending.resolved.val {
    pending.response.val = Some(response)
    pending.resolved.val = true
    pending.ready.release()
  }
}

///|
fn NativeAcpService::resolve_client_response(
  self : NativeAcpService,
  message : NativeAcpRpcMessage,
  raw : Json,
) -> Unit {
  match message.id {
    Some(id) =>
      match native_acp_id_key(id) {
        Some(key) =>
          match self.pending_permissions.get(key) {
            Some(pending) if pending.id == id =>
              native_acp_resolve_permission(pending, raw)
            _ => ()
          }
        None => ()
      }
    None => ()
  }
}

///|
/// Fail a malformed response for a live permission request without answering
/// the client response as a second JSON-RPC response.
fn NativeAcpService::reject_malformed_client_response(
  self : NativeAcpService,
  raw : Json,
) -> Unit {
  match object_field(raw, "id") {
    Some(id) =>
      match native_acp_id_key(id) {
        Some(key) =>
          match self.pending_permissions.get(key) {
            Some(pending) if pending.id == id =>
              native_acp_resolve_permission(
                pending,
                Json::object({
                  "jsonrpc": Json::string("2.0"),
                  "id": pending.id,
                  "error": Json::object({
                    "code": Json::number(-32600.0),
                    "message": Json::string("malformed ACP permission response"),
                  }),
                }),
              )
            _ => ()
          }
        None => ()
      }
    None => ()
  }
}

///|
fn NativeAcpService::begin_cancel(
  self : NativeAcpService,
  session_id : String,
  closing : Bool,
) -> Result[NativeAcpSession, NativeAcpRpcError] {
  let session = match self.sessions.get(session_id) {
    Some(value) if !value.closed => value
    Some(value) if closing => return Ok(value)
    _ => return Err(native_acp_invalid_params("unknown session: " + session_id))
  }
  if session.resuming && !closing {
    return Err(native_acp_invalid_params("session resume is still in progress"))
  }
  if closing {
    session.closing = true
  }
  if session.prompt_active {
    session.cancelled = true
    session.cancel_required = true
  }
  Ok(session)
}

///|
async fn NativeAcpService::apply_cancel(
  self : NativeAcpService,
  session : NativeAcpSession,
) -> Result[Unit, NativeAcpRpcError] {
  if !session.cancel_required || session.cancel_sent {
    return Ok(())
  }
  session.cancel_sent = true
  let result = match
    native_cli_command(
      self.runtime,
      Some(session.native_session_id),
      "session_cancel",
      Json::empty_object(),
      None,
      acp_activity_session_id=session.native_session_id,
    ) {
    Ok(receipt) if string_field(receipt, "status") == Some("completed") =>
      Ok(())
    Ok(_) =>
      Err(
        native_acp_internal_error(
          "native session cancellation was not committed",
        ),
      )
    Err(error) => Err(native_acp_internal_error(error))
  }
  let result = match result {
    Err(error) => Err(error)
    Ok(_) =>
      match self.native_session(session) {
        Err(error) => Err(error)
        Ok(state) =>
          match self.emit_committed_events(session, state) {
            Ok(_) => Ok(())
            Err(error) => Err(native_acp_internal_error(error))
          }
      }
  }
  match session.pending_permission {
    Some(pending) =>
      native_acp_resolve_permission(
        pending,
        Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": pending.id,
          "result": Json::object({
            "outcome": Json::object({ "outcome": Json::string("cancelled") }),
          }),
        }),
      )
    None => ()
  }
  result
}

///|
async fn NativeAcpService::cancel_session(
  self : NativeAcpService,
  session_id : String,
  wait : Bool,
) -> Result[Unit, NativeAcpRpcError] {
  let session = match self.begin_cancel(session_id, false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.apply_cancel(session) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if wait && session.prompt_active {
    match session.prompt_done {
      Some(done) => done.wait()
      None => ()
    }
  }
  Ok(())
}

///|
async fn NativeAcpService::close_session(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  match self.require_initialized() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let session_id = match native_acp_required_session_id(params) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let session = match self.begin_cancel(session_id, true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.finish_close(session)
}

///|
async fn NativeAcpService::finish_close(
  self : NativeAcpService,
  session : NativeAcpSession,
) -> Result[Json, NativeAcpRpcError] {
  if session.closed {
    return Ok(Json::empty_object())
  }
  let cancel_result = self.apply_cancel(session)
  if session.prompt_active {
    match session.prompt_done {
      Some(done) => done.wait()
      None => ()
    }
  }
  match self.runtime.record_acp_activity(session.native_session_id) {
    Ok(_) => ()
    Err(error) => return Err(native_acp_internal_error(error))
  }
  session.closed = true
  match cancel_result {
    Ok(_) => Ok(Json::empty_object())
    Err(error) => Err(error)
  }
}

///|
async fn NativeAcpService::shutdown(
  self : NativeAcpService,
) -> Result[Unit, String] {
  if self.closed {
    return Ok(())
  }
  self.closed = true
  let active : Array[NativeAcpSession] = []
  for _, session in self.sessions {
    if session.prompt_active {
      session.cancelled = true
      session.closing = true
      session.cancel_required = true
      active.push(session)
    }
  }
  let mut first_error : String? = None
  // Fence all sessions before waiting for any one cancellation to settle.
  for session in active {
    if session.cancel_required && !session.cancel_sent {
      session.cancel_sent = true
      let result : Result[Unit, String] = match
        native_cli_command(
          self.runtime,
          Some(session.native_session_id),
          "session_cancel",
          Json::empty_object(),
          None,
          acp_activity_session_id=session.native_session_id,
        ) {
        Ok(receipt) if string_field(receipt, "status") == Some("completed") =>
          Ok(())
        Ok(_) => Err("native session cancellation was not committed")
        Err(error) => Err(error)
      }
      match result {
        Ok(_) => ()
        Err(error) => if first_error is None { first_error = Some(error) }
      }
    }
  }
  // Only after every durable cancellation has been accepted do we drain the
  // resulting committed updates and wake permission waiters.
  for session in active {
    match self.native_session(session) {
      Ok(state) =>
        match self.emit_committed_events(session, state) {
          Ok(_) => ()
          Err(error) => if first_error is None { first_error = Some(error) }
        }
      Err(error) => if first_error is None { first_error = Some(error.message) }
    }
    match session.pending_permission {
      Some(pending) =>
        native_acp_resolve_permission(
          pending,
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": pending.id,
            "result": Json::object({
              "outcome": Json::object({ "outcome": Json::string("cancelled") }),
            }),
          }),
        )
      None => ()
    }
  }
  for session in active {
    match session.prompt_done {
      Some(done) => done.wait()
      None => ()
    }
  }
  match first_error {
    Some(error) => Err(error)
    None => Ok(())
  }
}
