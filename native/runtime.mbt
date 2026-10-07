///|
/// Native runtime boundary. All HarnessApi changes and durable checkpoints are
/// serialized by `gate`; effects are returned only after the matching snapshot
/// has reached stable storage.
struct NativeRuntime {
  api : @api.HarnessApi
  store : NativeStore
  auth : NativeAuth
  provider_config : NativeProviderConfig
  tools : NativeTools
  scheduler : NativeScheduler
  gate : @async.Mutex
  mut state : NativeState
  mut stopped : Bool
  mut closed : Bool
}

///|
/// Immutable host-level provider settings. API-key bytes are read into an
/// effect-local value immediately before dispatch and never stored here.
struct NativeProviderConfig {
  protocol : NativeProtocol
  auth_mode : NativeAuthMode
  model : String
  base_url : String?
  generation : String
  demo_provider : Bool
}

///|
fn native_provider_config(
  demo_provider : Bool,
) -> Result[NativeProviderConfig, String] {
  let mode = @env.get_env_var("DSH_MODE").unwrap_or("deepseek")
  let protocol = match mode {
    "deepseek" => NativeProtocol::DeepSeekMessages
    "openai" => NativeProtocol::OpenAIChatCompletions
    "openai-responses" => NativeProtocol::OpenAIResponses
    _ => return Err("DSH_MODE must be deepseek, openai, or openai-responses")
  }
  let auth = @env.get_env_var("DSH_AUTH").unwrap_or("api-key")
  let auth_mode = match auth {
    "api-key" => NativeAuthMode::ApiKey
    "chatgpt" => NativeAuthMode::ChatGPT
    _ => return Err("DSH_AUTH must be api-key or chatgpt")
  }
  if auth_mode == NativeAuthMode::ChatGPT &&
    protocol != NativeProtocol::OpenAIResponses {
    return Err("DSH_AUTH=chatgpt requires DSH_MODE=openai-responses")
  }
  let fallback_model = match protocol {
    NativeProtocol::DeepSeekMessages => "deepseek-flash"
    NativeProtocol::OpenAIChatCompletions => "offline-demo"
    NativeProtocol::OpenAIResponses => "offline-demo"
  }
  let model = @env.get_env_var("DSH_MODEL").unwrap_or(fallback_model)
  let base_url = @env.get_env_var("DSH_BASE_URL")
  let generation = match random_uuid() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if auth_mode == NativeAuthMode::ApiKey {
    match
      NativeProviderSelection::api_key(protocol, model, base_url, generation) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok({ protocol, auth_mode, model, base_url, generation, demo_provider, })
}

///|
async fn NativeRuntime::open(
  data_dir : String,
  workspace : String,
  allow_shell : Bool,
  demo_provider : Bool,
) -> Result[NativeRuntime, String] {
  let provider_config = match native_provider_config(demo_provider) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let workspace_path = @fs.realpath(workspace) catch {
    _ => return Err("cannot resolve workspace directory")
  }
  let workspace_root = match SafeRoot::open(workspace_path) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  let (workspace_device, workspace_inode) = match workspace_root.identity() {
    Ok(identity) => identity
    Err(error) => {
      workspace_root.close()
      return Err(error)
    }
  }
  let process_args = @env.args()
  if process_args.length() == 0 {
    workspace_root.close()
    return Err("cannot locate native worker executable")
  }
  let worker_path = @env.get_env_var("DSH_NATIVE_WORKER_BIN").unwrap_or(
    process_args[0],
  )
  let worker_launcher = @fs.realpath(worker_path) catch {
    _ => {
      workspace_root.close()
      return Err("cannot resolve native worker executable")
    }
  }
  let store = match NativeStore::open(data_dir) {
    Ok(store) => store
    Err(error) => {
      workspace_root.close()
      return Err(error)
    }
  }
  let loaded = match store.load() {
    Ok(state) => state
    Err(error) => {
      ignore(store.close())
      workspace_root.close()
      return Err(error)
    }
  }
  if store.path() == workspace_path {
    ignore(store.close())
    workspace_root.close()
    return Err("host data directory must be separate from the workspace root")
  }
  let recovered_receipts = native_mark_unfinished_receipts_uncertain(
    loaded.receipts,
  )
  let api = match @api.HarnessApi::new() {
    Ok(api) => api
    Err(error) => {
      ignore(store.close())
      workspace_root.close()
      return Err(error)
    }
  }
  match loaded.engine {
    Json::Null => ()
    engine_snapshot =>
      match api.restore(engine_snapshot) {
        Ok(_) => ()
        Err(error) => {
          api.close()
          ignore(store.close())
          workspace_root.close()
          return Err("cannot restore native engine snapshot: " + error)
        }
      }
  }
  let epoch = match random_uuid() {
    Ok(value) => value
    Err(error) => {
      api.close()
      ignore(store.close())
      workspace_root.close()
      return Err(error)
    }
  }
  let identity_key = match service_tailnet_config_from_env() {
    Err(error) => {
      api.close()
      ignore(store.close())
      workspace_root.close()
      return Err(error)
    }
    Ok(Some((_, login, _))) => "tailscale:" + login
    Ok(None) => "local:" + @env.get_env_var("USER").unwrap_or("owner")
  }
  let auth_revision = if identity_key == loaded.identity_key {
    loaded.auth_revision
  } else {
    loaded.auth_revision + 1
  }
  let blocked_path = if store.path().has_prefix(workspace_path + "/") {
    Some(store.path()[workspace_path.length() + 1:].to_owned())
  } else {
    None
  }
  let auth = match NativeAuth::open(store) {
    Ok(value) => value
    Err(error) => {
      api.close()
      ignore(store.close())
      workspace_root.close()
      return Err(error)
    }
  }
  let runtime = {
    api,
    store,
    auth,
    provider_config,
    scheduler: NativeScheduler::new(),
    tools: NativeTools::new(
      workspace_root, workspace_path, blocked_path, allow_shell, worker_launcher,
      workspace_device, workspace_inode,
    ),
    gate: @async.Mutex::Mutex(),
    state: {
      engine: api.snapshot(),
      receipts: recovered_receipts,
      server_id: loaded.server_id,
      workspace_id: loaded.workspace_id,
      identity_key,
      epoch,
      revision: loaded.revision + 1,
      auth_revision,
    },
    stopped: false,
    closed: false,
  }
  match store.save(runtime.state) {
    Ok(_) => Ok(runtime)
    Err(error) => {
      runtime.stopped = true
      api.close()
      auth.close()
      ignore(store.close())
      workspace_root.close()
      Err(error)
    }
  }
}

///|
fn NativeRuntime::checkpoint_locked(
  self : NativeRuntime,
) -> Result[Unit, String] {
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let next = {
    engine: self.api.snapshot(),
    receipts: self.state.receipts,
    server_id: self.state.server_id,
    workspace_id: self.state.workspace_id,
    identity_key: self.state.identity_key,
    epoch: self.state.epoch,
    revision: self.state.revision + 1,
    auth_revision: self.state.auth_revision,
  }
  match self.store.save(next) {
    Ok(_) => {
      self.state = next
      Ok(())
    }
    Err(error) => {
      // The in-memory mutation is intentionally not rolled back. A callback
      // may already be outstanding, so rolling back could resurrect it.
      self.stopped = true
      Err(error)
    }
  }
}

///|
/// Apply an operation and make the state durable before returning effects to
/// the caller. A read operation is checkpointed too, keeping this boundary
/// simple until the HTTP dispatcher classifies projections separately.
async fn NativeRuntime::invoke(
  self : NativeRuntime,
  operation : String,
  input : Json,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let result = match self.api.invoke(operation, input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.checkpoint_locked() {
    Err(error) => Err(error)
    Ok(_) => Ok((result, self.api.take_typed_effects()))
  }
}

///|
/// Advance the shared projection revision after a provider-auth change. The
/// provider's account generation is deliberately separate from tailnet
/// authorization scope (`auth_revision`).
async fn NativeRuntime::touch_projection(
  self : NativeRuntime,
) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  self.checkpoint_locked()
}

///|
fn native_digest_hex(_root : SafeRoot, text : String) -> Result[String, String] {
  let digest = match SafeRoot::sha256(@utf8.encode(text)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let output = StringBuilder()
  for byte in digest {
    let value = byte.to_int()
    if value < 16 {
      output.write_char('0')
    }
    output.write_string(value.to_string(radix=16))
  }
  Ok(output.to_string())
}

///|
fn native_remote_cursor(
  state : NativeState,
  root : SafeRoot,
  identity_key : String,
) -> Result[String, String] {
  let scope = identity_key +
    "\n" +
    state.workspace_id +
    "\n" +
    state.auth_revision.to_string()
  match native_digest_hex(root, scope) {
    Ok(scope_hash) =>
      Ok(scope_hash + ":" + state.epoch + ":" + state.revision.to_string())
    Err(error) => Err(error)
  }
}

///|
fn native_safe_session(value : Json) -> Json {
  let allowed = [
    "id", "title", "status", "turn_id", "step", "messages", "stream_revision", "pending_approval",
    "source_format", "parent_session_id",
  ]
  let result : Map[String, Json] = Map([])
  match value {
    Json::Object(fields) =>
      for key in allowed {
        if fields.get(key) is Some(field) {
          result[key] = field
        }
      }
    _ => ()
  }
  let pending_call_id = match object_field(value, "pending_approval") {
    Some(pending) => string_field(pending, "call_id")
    None => None
  }
  let mut approval_revision : Int? = None
  let safe_events : Array[Json] = []
  match object_field(value, "events") {
    Some(Json::Array(events)) =>
      for event in events {
        let kind = string_field(event, "type").unwrap_or("")
        let seq = int_field(event, "seq")
        let data = object_field(event, "data").unwrap_or(Json::null())
        if kind == "tool/approval/requested" &&
          seq is Some(revision) &&
          pending_call_id is Some(call_id) &&
          string_field(data, "call_id") == Some(call_id) {
          approval_revision = Some(revision)
        }
        if kind == "tool/result/pruned" {
          safe_events.push({
            "type": kind.to_json(),
            "turn_id": object_field(event, "turn_id").unwrap_or(Json::null()),
            "data": {
              "call_id": string_field(data, "call_id").unwrap_or("").to_json(),
            },
          })
        } else if string_field(data, "error") is Some(error) &&
          error.length() <= 512 {
          safe_events.push({
            "type": kind.to_json(),
            "turn_id": object_field(event, "turn_id").unwrap_or(Json::null()),
            "data": { "error": error.to_json() },
          })
        }
      }
    _ => ()
  }
  if approval_revision is Some(revision) {
    result["approval_revision"] = revision.to_json()
  }
  result["events"] = Json::array(safe_events)
  Json::object(result)
}

///|
async fn NativeRuntime::remote_snapshot(
  self : NativeRuntime,
  identity_key : String,
  selected_session? : String? = None,
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  if identity_key != self.state.identity_key {
    return Err("caller identity is no longer authorized")
  }
  let sessions = match self.api.invoke("session_list", {}) {
    Ok(Json::Array(values)) => values
    Ok(_) => return Err("session projection is invalid")
    Err(error) => return Err(error)
  }
  let summaries : Array[Json] = []
  for summary in sessions {
    let session_id = string_field(summary, "id").unwrap_or("")
    if session_id.is_empty() {
      continue
    }
    let detail = match
      self.api.invoke("session_get", { "session_id": session_id.to_json() }) {
      Ok(value) => native_safe_session(value)
      Err(_) => continue
    }
    summaries.push(detail)
  }
  let cursor = match
    native_remote_cursor(self.state, self.store.root, identity_key) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let selected = match selected_session {
    Some(session_id) =>
      match
        self.api.invoke("session_get", { "session_id": session_id.to_json() }) {
        Ok(value) if string_field(value, "id") == Some(session_id) =>
          native_safe_session(value)
        _ => Json::null()
      }
    None => Json::null()
  }
  Ok({
    "protocol_version": 1,
    "server_id": self.state.server_id.to_json(),
    "workspace_id": self.state.workspace_id.to_json(),
    "identity_key": identity_key.to_json(),
    "auth_revision": self.state.auth_revision.to_json(),
    "epoch": self.state.epoch.to_json(),
    "revision": self.state.revision.to_json(),
    "cursor": cursor.to_json(),
    "auth": self.auth.status(),
    "projection": {
      "sessions": Json::array(summaries),
      "selected_session": selected,
    },
  })
}

///|
async fn NativeRuntime::remote_session(
  self : NativeRuntime,
  session_id : String,
  identity_key : String,
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  if identity_key != self.state.identity_key {
    return Err("caller identity is no longer authorized")
  }
  let detail = match
    self.api.invoke("session_get", { "session_id": session_id.to_json() }) {
    Ok(value) => native_safe_session(value)
    Err(error) => return Err(error)
  }
  if string_field(detail, "id") != Some(session_id) {
    return Err("session not found")
  }
  let cursor = match
    native_remote_cursor(self.state, self.store.root, identity_key) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    "protocol_version": 1,
    "workspace_id": self.state.workspace_id.to_json(),
    "identity_key": identity_key.to_json(),
    "auth_revision": self.state.auth_revision.to_json(),
    "epoch": self.state.epoch.to_json(),
    "revision": self.state.revision.to_json(),
    "cursor": cursor.to_json(),
    "projection": { "session": detail },
  })
}

///|
fn native_receipt(
  workspace_id : String,
  command_id : String,
  fingerprint : String,
  status : String,
  accepted_revision : Int?,
  result : Json?,
  error : String?,
) -> Json {
  {
    "protocol_version": 1,
    "workspace_id": workspace_id.to_json(),
    "command_id": command_id.to_json(),
    "payload_fingerprint": fingerprint.to_json(),
    "status": status.to_json(),
    "accepted_revision": match accepted_revision {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "result": result.unwrap_or(Json::null()),
    "error": match error {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
}

///|
fn native_json_true(value : Json?) -> Bool {
  match value {
    Some(Json::True) => true
    _ => false
  }
}

///|
fn native_receipt_owner(receipt : Json) -> String {
  string_field(receipt, "owner_identity_key").unwrap_or(
    "local:" + @env.get_env_var("USER").unwrap_or("owner"),
  )
}

///|
fn native_receipt_with_owner(receipt : Json, identity_key : String) -> Json {
  match receipt {
    Json::Object(fields) => {
      fields["owner_identity_key"] = identity_key.to_json()
      Json::object(fields)
    }
    _ => receipt
  }
}

///|
/// A durable accepted receipt has no live job after process restart. Preserve
/// its identity and fingerprint, but make the outcome explicitly uncertain so
/// a retry can observe the outcome without dispatching the effect again.
fn native_mark_unfinished_receipts_uncertain(
  receipts : Array[Json],
) -> Array[Json] {
  let recovered : Array[Json] = []
  for receipt in receipts {
    if string_field(receipt, "status") == Some("accepted") {
      match receipt {
        Json::Object(fields) => {
          fields["status"] = "uncertain".to_json()
          fields["error"] = "host restarted before the accepted command had a durable outcome".to_json()
          recovered.push(Json::object(fields))
        }
        _ => recovered.push(receipt)
      }
    } else {
      recovered.push(receipt)
    }
  }
  recovered
}

///|
fn native_public_receipt(receipt : Json) -> Json {
  match receipt {
    Json::Object(fields) => {
      let output : Map[String, Json] = Map([])
      for (key, value) in fields.iter() {
        if key != "owner_identity_key" {
          output[key] = value
        }
      }
      Json::object(output)
    }
    _ => receipt
  }
}

///|
fn native_replace_receipt(
  receipts : Array[Json],
  command_id : String,
  replacement : Json,
) -> Array[Json] {
  let output : Array[Json] = []
  for receipt in receipts {
    if string_field(receipt, "command_id") == Some(command_id) {
      output.push(replacement)
    } else {
      output.push(receipt)
    }
  }
  output
}

///|
/// Return a replay or command-ID conflict receipt for an already-seen command.
/// The caller holds the runtime gate so receipt state stays coherent.
fn NativeRuntime::existing_command_receipt_locked(
  self : NativeRuntime,
  command : @protocol.RemoteCommand,
  identity_key : String,
  fingerprint : String,
) -> Json? {
  for previous in self.state.receipts {
    if native_receipt_owner(previous) == identity_key &&
      string_field(previous, "command_id") == Some(command.command_id) {
      if string_field(previous, "payload_fingerprint") == Some(fingerprint) {
        return Some(native_public_receipt(previous))
      }
      return Some(
        native_receipt(
          self.state.workspace_id,
          command.command_id,
          fingerprint,
          "rejected",
          None,
          None,
          Some("command ID was already used with a different payload"),
        ),
      )
    }
  }
  None
}

///|
/// Authenticate and inspect the receipt ledger before waiting for an active
/// effect job. Duplicate retries must replay their authoritative receipt even
/// while the original command is still running.
async fn NativeRuntime::preflight_existing_command(
  self : NativeRuntime,
  command : @protocol.RemoteCommand,
  identity_key : String,
) -> Result[(String, Json?), String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  if identity_key != self.state.identity_key {
    return Err("caller identity is no longer authorized")
  }
  if command.workspace_id != self.state.workspace_id {
    return Err("command belongs to another workspace")
  }
  if !@protocol.validate_uuid_v7_command_id_time(
      command.command_id,
      native_auth_now().to_int64() * 1000L,
      604800000L,
      300000L,
    ) {
    return Err("command ID is outside the allowed retry window")
  }
  let fingerprint = match
    native_digest_hex(
      self.store.root,
      @protocol.canonical_command_payload(command),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    (
      fingerprint,
      self.existing_command_receipt_locked(command, identity_key, fingerprint),
    ),
  )
}

///|
async fn NativeRuntime::accept_remote_command(
  self : NativeRuntime,
  command : @protocol.RemoteCommand,
  identity_key : String,
) -> Result[(Json, Array[@engine.EngineEffect], Bool), String] {
  let fingerprint = match
    self.preflight_existing_command(command, identity_key) {
    Err(error) => return Err(error)
    Ok((_, Some(receipt))) => return Ok((receipt, [], false))
    Ok((fingerprint, None)) => fingerprint
  }
  if command.operation != "session_cancel" {
    match command.session_id {
      Some(session_id) =>
        match self.scheduler.await_idle(session_id) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      None => ()
    }
  }
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  if identity_key != self.state.identity_key {
    return Err("caller identity is no longer authorized")
  }
  if command.workspace_id != self.state.workspace_id {
    return Err("command belongs to another workspace")
  }
  if !@protocol.validate_uuid_v7_command_id_time(
      command.command_id,
      native_auth_now().to_int64() * 1000L,
      604800000L,
      300000L,
    ) {
    return Err("command ID is outside the allowed retry window")
  }
  match
    self.existing_command_receipt_locked(command, identity_key, fingerprint) {
    Some(receipt) => return Ok((receipt, [], false))
    None => ()
  }
  let retained : Array[Json] = []
  for previous in self.state.receipts {
    let previous_id = string_field(previous, "command_id").unwrap_or("")
    let is_expired = match @protocol.uuid_v7_command_timestamp_ms(previous_id) {
      Some(timestamp) =>
        native_auth_now().to_int64() * 1000L - timestamp > 604800000L
      None => true
    }
    if !is_expired {
      retained.push(previous)
    }
  }
  if retained.length() >= 10000 {
    return Err("command receipt store is full")
  }
  let input_fields = match command.input {
    Json::Object(fields) => fields
    _ => return Err("command input must be an object")
  }
  if command.session_id is Some(session_id) {
    if [
        "tool_approve", "session_send", "session_cancel", "session_prune_tool_results",
        "session_fork",
      ].contains(command.operation) {
      input_fields["session_id"] = session_id.to_json()
    }
  }
  let input = Json::object(input_fields)
  let allowed = [
    "session_create", "session_import", "session_send", "session_cancel", "session_prune_tool_results",
    "session_fork", "tool_approve",
  ]
  let mut status = "accepted"
  let mut error_message : String? = None
  let mut result : Json? = None
  let mut effects : Array[@engine.EngineEffect] = []
  if !allowed.contains(command.operation) {
    status = "rejected"
    error_message = Some("operation is not available through remote commands")
  } else if command.operation == "tool_approve" &&
    !self.approval_matches_locked(command, input) {
    status = "rejected"
    error_message = Some(
      "approval is stale or does not match the pending tool call",
    )
  } else {
    match self.api.invoke(command.operation, input) {
      Err(error) => {
        status = "rejected"
        error_message = Some(bounded_tool_text(error))
      }
      Ok(value) => {
        result = Some(value)
        effects = self.api.take_typed_effects()
      }
    }
  }
  let accepted_revision = self.state.revision + 1
  let receipt = native_receipt(
    self.state.workspace_id,
    command.command_id,
    fingerprint,
    status,
    if status == "accepted" {
      Some(accepted_revision)
    } else {
      None
    },
    result,
    error_message,
  )
  retained.push(native_receipt_with_owner(receipt, identity_key))
  self.state.receipts = retained
  match self.checkpoint_locked() {
    Err(error) => Err(error)
    Ok(_) => {
      if status == "accepted" && command.operation == "session_cancel" {
        match command.session_id {
          Some(session_id) =>
            self.scheduler.cancel_through(session_id, accepted_revision)
          None => ()
        }
      }
      Ok((receipt, effects, status == "accepted"))
    }
  }
}

///|
fn NativeRuntime::approval_matches_locked(
  self : NativeRuntime,
  command : @protocol.RemoteCommand,
  input : Json,
) -> Bool {
  let session_id = match command.session_id {
    Some(value) => value
    None => return false
  }
  let approval_revision = match command.approval_revision {
    Some(value) => value
    None => return false
  }
  let current = match
    self.api.invoke("session_get", { "session_id": session_id.to_json() }) {
    Ok(value) => value
    Err(_) => return false
  }
  let pending = match object_field(current, "pending_approval") {
    Some(value) => value
    None => return false
  }
  let requested_call = string_field(pending, "call_id")
  if requested_call == None || requested_call != string_field(input, "call_id") {
    return false
  }
  let mut current_revision : Int? = None
  match object_field(current, "events") {
    Some(Json::Array(events)) =>
      for event in events {
        if string_field(event, "type") == Some("tool/approval/requested") &&
          string_field(
            object_field(event, "data").unwrap_or(Json::null()),
            "call_id",
          ) ==
          requested_call {
          current_revision = int_field(event, "seq")
        }
      }
    _ => ()
  }
  current_revision == Some(approval_revision)
}

///|
async fn NativeRuntime::find_receipt(
  self : NativeRuntime,
  command_id : String,
  identity_key : String,
) -> Result[Json?, String] {
  self.gate.acquire()
  defer self.gate.release()
  if identity_key != self.state.identity_key {
    return Err("caller identity is no longer authorized")
  }
  for receipt in self.state.receipts {
    if native_receipt_owner(receipt) == identity_key &&
      string_field(receipt, "command_id") == Some(command_id) {
      return Ok(Some(native_public_receipt(receipt)))
    }
  }
  Ok(None)
}

///|
async fn NativeRuntime::finish_receipt(
  self : NativeRuntime,
  command_id : String,
  identity_key : String,
  status : String,
  error : String?,
) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  for previous in self.state.receipts {
    if native_receipt_owner(previous) == identity_key &&
      string_field(previous, "command_id") == Some(command_id) {
      let replacement = match previous {
        Json::Object(fields) => {
          fields["status"] = status.to_json()
          fields["error"] = error
            .map(value => value.to_json())
            .unwrap_or(Json::null())
          Json::object(fields)
        }
        _ => previous
      }
      self.state.receipts = native_replace_receipt(
        self.state.receipts,
        command_id,
        replacement,
      )
      return self.checkpoint_locked()
    }
  }
  Err("command receipt disappeared before settlement")
}

///|
async fn NativeRuntime::schedule_retry(
  self : NativeRuntime,
  effect_id : String,
  failure : Json,
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let scheduled = match
    self.api.schedule_retry(effect_id, {
      "failure": failure,
      "max_retries": 5,
      "initial_delay_ms": 500,
      "max_delay_ms": 10000,
    }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.checkpoint_locked() {
    Ok(_) => Ok(scheduled)
    Err(error) => Err(error)
  }
}

///|
async fn NativeRuntime::start_retry(
  self : NativeRuntime,
  effect_id : String,
  retry_id : String,
) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  match self.api.start_retry(effect_id, retry_id) {
    Err(error) => Err(error)
    Ok(_) => self.checkpoint_locked()
  }
}

///|
fn native_provider_failure(error : String) -> Json {
  let prefix = match error.split_once(":") {
    Some((code, _)) => code.to_owned()
    None => "PROVIDER_ERROR"
  }
  let code = match prefix {
    "PROVIDER_TRANSPORT" | "PROVIDER_TIMEOUT" => "TRANSPORT"
    "PROVIDER_EMPTY_RESPONSE" => "EMPTY_RESPONSE"
    "PROVIDER_RATE_LIMIT" => "RATE_LIMIT"
    "PROVIDER_SERVER" => "SERVER"
    _ => prefix
  }
  let message = if error.length() > 512 {
    error[:512].to_owned()
  } else {
    error
  }
  let failure = { "code": code.to_json(), "message": message.to_json() }
  { "ok": false, "error": message.to_json(), "failure": failure }
}

///|
fn native_failure_is_retryable(result : Json) -> Json? {
  let failed = match object_field(result, "ok") {
    Some(Json::False) => true
    _ => false
  }
  if !failed {
    return None
  }
  match object_field(result, "failure") {
    Some(Json::Object(fields)) => Some(Json::object(fields))
    _ => None
  }
}

///|
const NATIVE_PROVIDER_STREAM_DELTA_CAPACITY : Int = 4096

///|
fn native_provider_utf16_units(value : String) -> Int {
  let mut units = 0
  for character in value {
    units += if character.to_int() > 0xFFFF { 2 } else { 1 }
  }
  units
}

///|
fn native_provider_split_stream_delta(value : String) -> Array[String] {
  let chunks : Array[String] = []
  let mut chunk = StringBuilder()
  let mut units = 0
  for character in value {
    let width = if character.to_int() > 0xFFFF { 2 } else { 1 }
    if units + width > NATIVE_PROVIDER_STREAM_DELTA_CAPACITY {
      chunks.push(chunk.to_string())
      chunk = StringBuilder()
      units = 0
    }
    chunk.write_char(character)
    units += width
  }
  if units > 0 {
    chunks.push(chunk.to_string())
  }
  chunks
}

///|
async fn NativeRuntime::project_provider_stream_batch(
  self : NativeRuntime,
  effect_id : @engine.EffectId,
  text : String,
  reasoning : String,
) -> Result[Unit, String] {
  match self.project(effect_id, text, reasoning) {
    Ok(next_effects) if next_effects.is_empty() => Ok(())
    Ok(_) => Err("provider stream projection produced new effects")
    Err(error) => Err(error)
  }
}

///|
async fn NativeRuntime::project_provider_delta(
  self : NativeRuntime,
  effect_id : @engine.EffectId,
  text : String,
  reasoning : String,
) -> Result[Unit, String] {
  if text.is_empty() && reasoning.is_empty() {
    return Ok(())
  }
  if native_provider_utf16_units(text) + native_provider_utf16_units(reasoning) <=
    NATIVE_PROVIDER_STREAM_DELTA_CAPACITY {
    return self.project_provider_stream_batch(effect_id, text, reasoning)
  }
  for chunk in native_provider_split_stream_delta(text) {
    match self.project_provider_stream_batch(effect_id, chunk, "") {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  for chunk in native_provider_split_stream_delta(reasoning) {
    match self.project_provider_stream_batch(effect_id, "", chunk) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn NativeRuntime::run_provider_effect(
  self : NativeRuntime,
  effect : @engine.EngineEffect,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  if effect.kind() != @engine.EffectType::Provider {
    return Err("effect is not a provider request")
  }
  let request = effect.request()
  let mut final_result : Json? = None
  // Bind every retry to the account, model, and generation selected for this
  // effect. A sign-out, re-login, or model switch during backoff must make the
  // old effect fail instead of silently sending it under a new identity.
  let selection = if self.provider_config.demo_provider {
    match
      NativeProviderSelection::api_key(
        NativeProtocol::OpenAIChatCompletions,
        "offline-demo",
        None,
        self.provider_config.generation,
      ) {
      Ok(value) => value
      Err(error) =>
        return self.complete(effect.id(), native_provider_failure(error))
    }
  } else if self.provider_config.auth_mode == NativeAuthMode::ChatGPT {
    match self.auth.provider_selection() {
      Ok(value) => value
      Err(error) =>
        return self.complete(effect.id(), native_provider_failure(error))
    }
  } else {
    match
      NativeProviderSelection::api_key(
        self.provider_config.protocol,
        self.provider_config.model,
        self.provider_config.base_url,
        self.provider_config.generation,
      ) {
      Ok(value) => value
      Err(error) =>
        return self.complete(effect.id(), native_provider_failure(error))
    }
  }
  let api_key = if self.provider_config.demo_provider {
    None
  } else if selection.auth_mode() == NativeAuthMode::ApiKey {
    let key_name = if selection.protocol() == NativeProtocol::DeepSeekMessages {
      "DEEPSEEK_API_KEY"
    } else {
      "OPENAI_API_KEY"
    }
    let value = @env.get_env_var("DSH_API_KEY").unwrap_or(
      @env.get_env_var(key_name).unwrap_or(""),
    )
    if value.is_empty() {
      return self.complete(
        effect.id(),
        native_provider_failure(
          "AUTH_REQUIRED: provider API key is not configured",
        ),
      )
    }
    Some(value)
  } else {
    None
  }
  while final_result is None {
    let result : Result[Json, String] = if self.provider_config.demo_provider {
      Ok(native_demo_provider_response(request))
    } else if selection.auth_mode() == NativeAuthMode::ChatGPT {
      self.auth.run_responses(selection, request, async fn(
        event,
      ) -> Result[Unit, String] {
        let (text, why) : (String, String) = match event {
          @provider.ResponsesEvent::TextDelta(value) => (value, "")
          @provider.ResponsesEvent::ReasoningDelta(value) => ("", value)
          _ => ("", "")
        }
        self.project_provider_delta(effect.id(), text, why)
      })
    } else {
      native_run_api_key(selection, request, api_key.unwrap(), async fn(
        text,
        why,
      ) -> Result[Unit, String] {
        self.project_provider_delta(effect.id(), text, why)
      })
    }
    match result {
      Ok(value) => {
        let failed = match object_field(value, "ok") {
          Some(Json::False) => true
          _ => false
        }
        if failed {
          let failure = native_failure_is_retryable(value)
          match failure {
            Some(policy_failure) => {
              let scheduled = match
                self.schedule_retry(effect.id().as_string(), policy_failure) {
                Ok(value) => value
                Err(error) => return Err(error)
              }
              if native_json_true(object_field(scheduled, "scheduled")) {
                let delay = int_field(scheduled, "delay_ms").unwrap_or(0)
                let retry_id = string_field(scheduled, "retry_id").unwrap_or("")
                @async.sleep(delay)
                match self.start_retry(effect.id().as_string(), retry_id) {
                  Ok(_) => ()
                  Err(error) => return Err(error)
                }
                continue
              }
            }
            None => ()
          }
        }
        final_result = Some(value)
      }
      Err(error) => {
        let failure = native_provider_failure(error)
        let failure_json = native_failure_is_retryable(failure)
        match failure_json {
          Some(policy_failure) => {
            let scheduled = match
              self.schedule_retry(effect.id().as_string(), policy_failure) {
              Ok(value) => value
              Err(schedule_error) => return Err(schedule_error)
            }
            if native_json_true(object_field(scheduled, "scheduled")) {
              let delay = int_field(scheduled, "delay_ms").unwrap_or(0)
              let retry_id = string_field(scheduled, "retry_id").unwrap_or("")
              @async.sleep(delay)
              match self.start_retry(effect.id().as_string(), retry_id) {
                Ok(_) => ()
                Err(start_error) => return Err(start_error)
              }
              continue
            }
          }
          None => ()
        }
        final_result = Some(failure)
      }
    }
  }
  self.complete(effect.id(), final_result.unwrap())
}

///|
async fn NativeRuntime::run_effects(
  self : NativeRuntime,
  effects : Array[@engine.EngineEffect],
  command_id : String,
  accepted_revision : Int,
) -> Result[Unit, String] {
  if effects.is_empty() {
    return Ok(())
  }
  let session_id = effects[0].session_id().as_string()
  for effect in effects {
    if effect.session_id().as_string() != session_id {
      return Err("one native command produced effects for multiple sessions")
    }
  }
  let control = match
    self.scheduler.begin(session_id, command_id, accepted_revision) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let outcome = @async.handle_cancellation(async fn() {
    @async.with_task_group() <| workers => {
      let task = workers.spawn(no_wait=true, async fn() {
        match
          @async.handle_cancellation(async fn() {
            native_drive_effects(self.scheduler, effects, control, async fn(
              effect,
            ) {
              match effect.kind() {
                @engine.EffectType::Tool => self.run_tool_effect(effect)
                @engine.EffectType::Provider => self.run_provider_effect(effect)
              }
            })
          }) {
          None => Err("native command was cancelled")
          Some(result) => result
        }
      })
      self.scheduler.attach_task(control, task)
      task.wait()
    }
  })
  @async.protect_from_cancel(async fn() { self.scheduler.finish(control) })
  match outcome {
    None => Err("native command was cancelled")
    Some(value) => value
  }
}

///|
async fn NativeRuntime::run_command_job(
  self : NativeRuntime,
  command_id : String,
  identity_key : String,
  accepted_revision : Int,
  effects : Array[@engine.EngineEffect],
) -> Unit {
  let outcome = @async.handle_cancellation(async fn() {
    self.run_effects(effects, command_id, accepted_revision)
  })
  @async.protect_from_cancel(async fn() {
    match outcome {
      None =>
        ignore(
          self.finish_receipt(
            command_id,
            identity_key,
            "uncertain",
            Some("accepted command was cancelled"),
          ),
        )
      Some(Ok(_)) =>
        ignore(self.finish_receipt(command_id, identity_key, "completed", None))
      Some(Err(error)) => {
        let bounded = if error.length() > 512 {
          error[:512].to_owned()
        } else {
          error
        }
        ignore(
          self.finish_receipt(
            command_id,
            identity_key,
            "uncertain",
            Some(bounded),
          ),
        )
      }
    }
  })
}

///|
async fn NativeRuntime::project(
  self : NativeRuntime,
  effect_id : @engine.EffectId,
  content : String,
  reasoning : String,
) -> Result[Array[@engine.EngineEffect], String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  match self.api.project_effect_stream(effect_id, content, reasoning) {
    Err(error) => Err(error)
    Ok(_) =>
      match self.checkpoint_locked() {
        Err(error) => Err(error)
        Ok(_) => Ok(self.api.take_typed_effects())
      }
  }
}

///|
async fn NativeRuntime::complete(
  self : NativeRuntime,
  effect_id : @engine.EffectId,
  result : Json,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let completion = match self.api.complete_effect(effect_id, result) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.checkpoint_locked() {
    Err(error) => Err(error)
    Ok(_) => Ok((completion, self.api.take_typed_effects()))
  }
}

///|
async fn NativeRuntime::run_tool_effect(
  self : NativeRuntime,
  effect : @engine.EngineEffect,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  if effect.kind() != @engine.EffectType::Tool {
    return Err("effect is not a tool")
  }
  let tool_result = self.tools.execute(effect.request())
  self.complete(effect.id(), tool_result)
}

///|
async fn NativeRuntime::close(self : NativeRuntime) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed {
    return Ok(())
  }
  self.api.close()
  let checkpoint = self.checkpoint_locked()
  self.closed = true
  self.auth.close()
  self.tools.root.close()
  let close_result = self.store.close()
  match checkpoint {
    Err(error) => Err(error)
    Ok(_) => close_result
  }
}

///|
fn native_effect_by_kind(
  effects : Array[@engine.EngineEffect],
  kind : @engine.EffectType,
) -> @engine.EngineEffect? {
  for effect in effects {
    if effect.kind() == kind {
      return Some(effect)
    }
  }
  None
}

///|
fn native_demo_response(content : String) -> Json {
  {
    "ok": true,
    "content": content,
    "reasoning": "",
    "tool_calls": [],
    "finish_reason": "stop",
    "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
  }
}

///|
fn native_demo_tool_response() -> Json {
  {
    "ok": true,
    "content": "",
    "reasoning": "",
    "tool_calls": [
      {
        "id": "demo-write-call",
        "name": "write",
        "arguments": "{\"file_path\":\"native-demo.txt\",\"content\":\"durable native tool result\"}",
      },
    ],
    "finish_reason": "tool_calls",
    "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
  }
}

///|
fn native_demo_provider_response(request : Json) -> Json {
  if request.stringify().contains("durable native tool result") {
    native_demo_response(
      "Offline demo finished after the approved workspace write.",
    )
  } else {
    native_demo_tool_response()
  }
}

///|
async fn NativeRuntime::run_demo(
  self : NativeRuntime,
) -> Result[String, String] {
  let demo_id = match random_uuid() {
    Ok(value) => "native-demo-" + value
    Err(error) => return Err(error)
  }
  match
    self.invoke("session_create", {
      "id": demo_id,
      "title": "Native runtime demo",
    }) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let (sent, initial_effects) = match
    self.invoke("session_send", {
      "session_id": demo_id,
      "prompt": "Create and verify a durable file.",
    }) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  ignore(sent)
  let initial_provider = match
    native_effect_by_kind(initial_effects, @engine.EffectType::Provider) {
    Some(effect) => effect
    None => return Err("demo did not produce the initial provider effect")
  }
  let (_, approval_effects) = match
    self.complete(initial_provider.id(), native_demo_tool_response()) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  if approval_effects.length() != 0 {
    return Err("demo write was dispatched before explicit approval")
  }
  let (approval, _) = match
    self.invoke("session_get", { "session_id": demo_id }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pending_call_id = match object_field(approval, "pending_approval") {
    Some(pending) => string_field(pending, "call_id")
    None => None
  }
  let call_id = match pending_call_id {
    Some(value) => value
    None => return Err("demo provider call did not enter approval state")
  }
  let (_, write_effects) = match
    self.invoke("tool_approve", {
      "session_id": demo_id,
      "call_id": call_id,
      "approved": true,
    }) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  let write_effect = match
    native_effect_by_kind(write_effects, @engine.EffectType::Tool) {
    Some(effect) => effect
    None => return Err("approved write did not produce a tool effect")
  }
  let (_, second_provider_effects) = match self.run_tool_effect(write_effect) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  let second_provider = match
    native_effect_by_kind(second_provider_effects, @engine.EffectType::Provider) {
    Some(effect) => effect
    None => return Err("tool completion did not produce a provider effect")
  }
  if !second_provider
    .request()
    .stringify()
    .contains("durable native tool result") {
    return Err("tool result was not included in the next model context")
  }
  let (_, trailing) = match
    self.complete(
      second_provider.id(),
      native_demo_response("The file was created and verified."),
    ) {
    Err(error) => return Err(error)
    Ok(result) => result
  }
  if !trailing.is_empty() {
    return Err("demo produced unexpected trailing effects")
  }
  match self.tools.root.read_text("native-demo.txt") {
    Err(error) => return Err(error)
    Ok((content, _)) if content == "durable native tool result" => ()
    Ok(_) => return Err("native tool wrote unexpected file content")
  }
  let grep_result = self.tools.execute({
    "name": "grep",
    "arguments": {
      "pattern": "durable native tool result",
      "path": "native-demo.txt",
    },
  })
  if os_hard_worker_memory_supported() {
    if !string_field(grep_result, "content")
      .unwrap_or("")
      .contains("durable native tool result") {
      return Err("isolated grep worker failed to find the demo tool output")
    }
  } else {
    if string_field(grep_result, "error") !=
      Some(
        "grep is disabled because this host cannot enforce a hard worker memory limit",
      ) {
      return Err(
        "native demo expected grep to be explicitly disabled on this host",
      )
    }
    println(
      "native runtime demo note: grep unsupported on this host (no hard worker memory limit)",
    )
  }
  Ok(demo_id)
}

///|
async fn verify_native_demo_reload(
  data_dir : String,
  workspace : String,
  demo_id : String,
) -> Result[Unit, String] {
  let runtime = match NativeRuntime::open(data_dir, workspace, false, false) {
    Ok(runtime) => runtime
    Err(error) => return Err("cannot reopen native demo state: " + error)
  }
  let (session, effects) = match
    runtime.invoke("session_get", { "session_id": demo_id }) {
    Ok(result) => result
    Err(error) => {
      ignore(runtime.close())
      return Err("cannot read reloaded demo session: " + error)
    }
  }
  if !effects.is_empty() ||
    !session.stringify().contains("The file was created and verified.") {
    ignore(runtime.close())
    return Err("completed demo transcript did not survive native reload")
  }
  match runtime.tools.root.read_text("native-demo.txt") {
    Err(error) => {
      ignore(runtime.close())
      return Err("cannot read reloaded demo workspace file: " + error)
    }
    Ok((content, _)) if content != "durable native tool result" => {
      ignore(runtime.close())
      return Err("reloaded demo workspace file has different content")
    }
    Ok(_) => ()
  }
  runtime.close()
}
