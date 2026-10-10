///|
const NATIVE_ACP_SESSION_PAGE_SIZE : Int = 16

///|
fn native_acp_timestamp() -> String? {
  match os_timestamp() {
    Ok(value) if native_acp_valid_timestamp(value) => Some(value)
    _ => None
  }
}

///|
fn native_acp_move_session_to_front(
  sessions : Array[NativeAcpStoredSession],
  session_id : String,
  updated_at : String?,
) -> Result[Array[NativeAcpStoredSession], String] {
  let mut current : NativeAcpStoredSession? = None
  for session in sessions {
    if session.session_id == session_id {
      current = Some(session)
    }
  }
  let record = match current {
    Some(value) => { ..value, updated_at, }
    None => return Err("ACP session is not registered for this data directory")
  }
  let next : Array[NativeAcpStoredSession] = [record]
  for session in sessions {
    if session.session_id != session_id {
      next.push(session)
    }
  }
  Ok(next)
}

///|
fn native_acp_update_session_model(
  sessions : Array[NativeAcpStoredSession],
  session_id : String,
  model : String?,
  route : String,
  updated_at : String?,
) -> Result[Array[NativeAcpStoredSession], String] {
  let mut current : NativeAcpStoredSession? = None
  for session in sessions {
    if session.session_id == session_id {
      current = Some(session)
    }
  }
  let record = match current {
    Some(value) => { ..value, updated_at, model, route: Some(route), }
    None => return Err("ACP session is not registered for this data directory")
  }
  let next : Array[NativeAcpStoredSession] = [record]
  for session in sessions {
    if session.session_id != session_id {
      next.push(session)
    }
  }
  Ok(next)
}

///|
fn native_acp_validate_registry(
  snapshot : Json,
  registry : Array[NativeAcpStoredSession],
  workspace : String,
) -> Result[Unit, String] {
  if registry.length() > 32 {
    return Err("native snapshot has too many registered ACP sessions")
  }
  let sessions = match object_field(snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => return Err("native snapshot has no session list for the ACP registry")
  }
  let by_id : Map[String, Json] = Map([])
  for session in sessions {
    let session_id = match string_field(session, "id") {
      Some(value) => value
      None => return Err("native snapshot contains a session without an id")
    }
    if by_id.get(session_id) is Some(_) {
      return Err("native snapshot contains duplicate session ids")
    }
    by_id.set(session_id, session)
  }
  let seen : Map[String, Bool] = Map([])
  for record in registry {
    if record.cwd != workspace {
      return Err("stored ACP session belongs to a different startup workspace")
    }
    if seen.get(record.session_id) is Some(_) {
      return Err("native snapshot has duplicate ACP session metadata")
    }
    let session = match by_id.get(record.session_id) {
      Some(value) => value
      None => return Err("ACP registry references a missing native session")
    }
    if object_field(session, "source_format") is Some(_) {
      return Err("ACP registry cannot reference an imported native session")
    }
    if object_field(session, "parent_session_id") is Some(_) {
      return Err("ACP registry cannot reference a forked native session")
    }
    seen.set(record.session_id, true)
  }
  Ok(())
}

///|
async fn NativeRuntime::create_acp_session(
  self : NativeRuntime,
  session_id : String,
  cwd : String,
  model : String?,
  route : String,
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  if cwd != self.tools.workspace {
    return Err("ACP session cwd differs from the configured workspace")
  }
  if self.state.acp_sessions.any(session => session.session_id == session_id) {
    return Err("ACP session id is already registered")
  }
  let created = match
    self.api.invoke("session_create", {
      "id": Json::string(session_id),
      "title": Json::string("ACP session"),
    }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if string_field(created, "id") != Some(session_id) {
    return Err("native session creation returned a different id")
  }
  let record : NativeAcpStoredSession = {
    session_id,
    cwd,
    updated_at: native_acp_timestamp(),
    model,
    route: Some(route),
  }
  self.state.acp_sessions = [record, ..self.state.acp_sessions]
  match self.checkpoint_locked() {
    Ok(_) => Ok(created)
    Err(error) => Err(error)
  }
}

///|
/// Read the model pinned to an ACP-owned native session. The ACP registry is
/// protected by the same gate as checkpoints and config changes.
async fn NativeRuntime::acp_model_for_session(
  self : NativeRuntime,
  session_id : String,
) -> Result[String?, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  for record in self.state.acp_sessions {
    if record.session_id == session_id {
      return Ok(record.model)
    }
  }
  Ok(None)
}

///|
/// Persist a non-secret ACP model selection only while the underlying native
/// session is idle. A prompt admitted by ACP also fences this operation at
/// the connection layer before the provider effect is created.
async fn NativeRuntime::set_acp_session_model(
  self : NativeRuntime,
  session_id : String,
  model : String?,
  route : String,
) -> Result[Unit, String] {
  if (
      model is Some(value) &&
      (value.is_empty() || value.length() > NATIVE_ACP_MODEL_NAME_LIMIT)
    ) ||
    route.is_empty() ||
    route.length() > 64 {
    return Err("ACP model name is invalid")
  }
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let state = match
    self.api.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match string_field(state, "status") {
    Some("idle") | Some("completed") | Some("failed") | Some("cancelled") => ()
    Some("running") | Some("awaiting_approval") =>
      return Err("ACP session is active or busy")
    _ => return Err("ACP native session has an unsupported state")
  }
  let next = match
    native_acp_update_session_model(
      self.state.acp_sessions,
      session_id,
      model,
      route,
      native_acp_timestamp(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.state.acp_sessions = next
  self.checkpoint_locked()
}

///|
/// Read the native projection and ACP metadata under the runtime gate without
/// advancing the durable revision or restoring any session.
async fn NativeRuntime::read_acp_sessions(
  self : NativeRuntime,
) -> Result[(Json, Array[NativeAcpStoredSession], Int), String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let sessions = match self.api.invoke("session_list", Json::empty_object()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    (
      sessions,
      self.state.acp_sessions.map(session => session),
      self.state.revision,
    ),
  )
}

///|
/// Read one native session and its ACP provenance without making a checkpoint.
async fn NativeRuntime::read_acp_session(
  self : NativeRuntime,
  session_id : String,
) -> Result[(Json, NativeAcpStoredSession?), String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let session = match
    self.api.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut record : NativeAcpStoredSession? = None
  for candidate in self.state.acp_sessions {
    if candidate.session_id == session_id {
      record = Some(candidate)
    }
  }
  Ok((session, record))
}

///|
/// The caller holds the runtime gate. The updated order and timestamp are
/// committed with the engine mutation by the same native snapshot write.
fn NativeRuntime::record_acp_activity_locked(
  self : NativeRuntime,
  session_id : String,
) -> Result[Unit, String] {
  let next = match
    native_acp_move_session_to_front(
      self.state.acp_sessions,
      session_id,
      native_acp_timestamp(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.state.acp_sessions = next
  Ok(())
}

///|
async fn NativeRuntime::record_acp_activity(
  self : NativeRuntime,
  session_id : String,
) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  match self.record_acp_activity_locked(session_id) {
    Err(error) => return Err(error)
    Ok(_) => self.checkpoint_locked()
  }
}

///|
fn native_acp_list_cursor(offset : Int, cwd : String, revision : Int) -> String {
  native_base64url_encode(
    @utf8.encode(
      Json::object({
        "version": Json::number(1.0),
        "offset": Json::number(offset.to_double()),
        "cwd": Json::string(cwd),
        "revision": Json::number(revision.to_double()),
      }).stringify(),
    ),
  )
}

///|
fn native_acp_parse_list_cursor(
  cursor : String,
  cwd : String,
  revision : Int,
) -> Result[Int, String] {
  let bytes = match native_base64url_decode(cursor, limit=8192) {
    Ok(value) => value
    Err(_) => return Err("cursor is invalid")
  }
  let text = @utf8.decode(bytes) catch { _ => return Err("cursor is invalid") }
  let value = @json.parse(text) catch { _ => return Err("cursor is invalid") }
  if int_field(value, "version") != Some(1) ||
    string_field(value, "cwd") != Some(cwd) ||
    int_field(value, "revision") != Some(revision) {
    return Err("cursor is invalid or stale")
  }
  match object_field(value, "offset") {
    Some(Json::Number(number, ..)) if native_acp_safe_integer(number) &&
      number >= 0.0 &&
      number <= 32.0 => Ok(number.to_int())
    _ => Err("cursor is invalid")
  }
}

///|
async fn native_acp_list_cwd(
  params : Json,
  workspace : String,
) -> Result[String, NativeAcpRpcError] {
  match object_field(params, "cwd") {
    None | Some(Json::Null) => Ok(workspace)
    Some(Json::String(value)) if value.has_prefix("/") && value.length() <= 4096 => {
      let canonical = @fs.realpath(value) catch { _ => value }
      Ok(canonical)
    }
    _ => Err(native_acp_invalid_params("cwd must be an absolute path"))
  }
}

///|
async fn NativeAcpService::list_sessions(
  self : NativeAcpService,
  params : Json,
) -> Result[Json, NativeAcpRpcError] {
  match self.require_initialized() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let cwd = match native_acp_list_cwd(params, self.workspace) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let cursor : String? = match object_field(params, "cursor") {
    None | Some(Json::Null) => None
    Some(Json::String(value)) =>
      if !value.is_empty() && value.length() <= 8192 {
        Some(value)
      } else {
        return Err(native_acp_invalid_params("cursor is invalid"))
      }
    _ => return Err(native_acp_invalid_params("cursor is invalid"))
  }
  let (native_sessions, registry, revision) = match
    self.runtime.read_acp_sessions() {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  let offset = match cursor {
    None => 0
    Some(cursor) =>
      match native_acp_parse_list_cursor(cursor, cwd, revision) {
        Ok(value) => value
        Err(error) => return Err(native_acp_invalid_params(error))
      }
  }
  let summaries : Map[String, Json] = Map([])
  match native_sessions {
    Json::Array(values) =>
      for session in values {
        match string_field(session, "id") {
          Some(id) => summaries.set(id, session)
          None => ()
        }
      }
    _ =>
      return Err(native_acp_internal_error("native session list is malformed"))
  }
  let matches : Array[(NativeAcpStoredSession, Json)] = []
  for record in registry {
    if record.cwd != cwd {
      continue
    }
    match summaries.get(record.session_id) {
      Some(summary) if object_field(summary, "parent_session_id") is None =>
        matches.push((record, summary))
      _ => ()
    }
  }
  if offset > matches.length() || (offset != 0 && offset == matches.length()) {
    return Err(native_acp_invalid_params("cursor is invalid or stale"))
  }
  let sessions : Array[Json] = []
  let end = Int::min(offset + NATIVE_ACP_SESSION_PAGE_SIZE, matches.length())
  for index in offset..<end {
    let (record, summary) = matches[index]
    let info : Map[String, Json] = {
      "sessionId": Json::string(record.session_id),
      "cwd": Json::string(record.cwd),
    }
    match string_field(summary, "title") {
      Some(title) => info["title"] = Json::string(title)
      None => ()
    }
    match record.updated_at {
      Some(value) => info["updatedAt"] = Json::string(value)
      None => ()
    }
    sessions.push(Json::object(info))
  }
  let result : Map[String, Json] = { "sessions": Json::array(sessions) }
  if end < matches.length() {
    result["nextCursor"] = Json::string(
      native_acp_list_cursor(end, cwd, revision),
    )
  }
  Ok(Json::object(result))
}

///|
async fn NativeAcpService::resume_session(
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
  let session_id = match native_acp_required_session_id(params) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.sessions.get(session_id) {
    Some(session) if session.closed => ()
    Some(session) if session.resuming ||
      session.prompt_active ||
      session.closing =>
      return Err(native_acp_invalid_params("session is active or busy"))
    Some(session) if !session.closed =>
      return Err(
        native_acp_invalid_params(
          "session is already attached to this ACP connection",
        ),
      )
    _ => ()
  }
  let placeholder : NativeAcpSession = {
    session_id,
    native_session_id: session_id,
    event_gate: @async.Mutex::Mutex(),
    last_event_seq: 0,
    prompt_generation: 0,
    prompt_active: false,
    resuming: true,
    cancelled: false,
    closing: false,
    closed: false,
    cancel_required: false,
    cancel_sent: false,
    prompt_done: None,
    pending_permission: None,
  }
  self.sessions.set(session_id, placeholder)
  let (state, record) = match self.runtime.read_acp_session(session_id) {
    Ok(value) => value
    Err(_) => {
      self.sessions.remove(session_id)
      return Err(native_acp_invalid_params("unknown session: " + session_id))
    }
  }
  if placeholder.closed || placeholder.closing {
    self.sessions.remove(session_id)
    return Err(native_acp_invalid_params("session resume was interrupted"))
  }
  let record = match record {
    Some(value) => value
    None => {
      self.sessions.remove(session_id)
      if object_field(state, "source_format") is Some(_) {
        return Err(
          native_acp_invalid_params("imported sessions cannot be resumed"),
        )
      }
      return Err(
        native_acp_invalid_params("session is not registered for ACP resume"),
      )
    }
  }
  if record.cwd != self.workspace {
    self.sessions.remove(session_id)
    return Err(
      native_acp_invalid_params("session belongs to a different workspace"),
    )
  }
  let current_route = match self.runtime.acp_route_id() {
    Ok(value) => value
    Err(error) => return Err(native_acp_internal_error(error))
  }
  match record.route {
    Some(route) if route != current_route => {
      self.sessions.remove(session_id)
      return Err(
        native_acp_invalid_params(
          "session provider route differs from the current startup configuration",
        ),
      )
    }
    _ => ()
  }
  if object_field(state, "source_format") is Some(_) {
    self.sessions.remove(session_id)
    return Err(native_acp_invalid_params("imported sessions cannot be resumed"))
  }
  if object_field(state, "parent_session_id") is Some(_) {
    self.sessions.remove(session_id)
    return Err(
      native_acp_invalid_params("forked sessions cannot be resumed through ACP"),
    )
  }
  match string_field(state, "status") {
    Some("running") | Some("awaiting_approval") => {
      self.sessions.remove(session_id)
      return Err(native_acp_invalid_params("session is active or busy"))
    }
    Some("idle") | Some("completed") | Some("failed") | Some("cancelled") => ()
    _ => {
      self.sessions.remove(session_id)
      return Err(native_acp_invalid_params("session has an unsupported state"))
    }
  }
  let event_count = match object_field(state, "events") {
    Some(Json::Array(events)) => events.length()
    _ => {
      self.sessions.remove(session_id)
      return Err(
        native_acp_internal_error("native session history is malformed"),
      )
    }
  }
  placeholder.last_event_seq = event_count - 1
  let model = match record.model {
    Some(value) => Some(value)
    None => self.runtime.acp_default_model()
  }
  let config_options = match
    self.runtime.acp_model_options(model, self.model_allowlist) {
    Ok(value) => value
    Err(error) => {
      self.sessions.remove(session_id)
      return Err(native_acp_invalid_params(error))
    }
  }
  let activity = if record.route is None ||
    (record.model is None && model is Some(_)) {
    self.runtime.set_acp_session_model(session_id, model, current_route)
  } else {
    self.runtime.record_acp_activity(session_id)
  }
  match activity {
    Ok(_) => ()
    Err(error) => {
      self.sessions.remove(session_id)
      return Err(native_acp_internal_error(error))
    }
  }
  if placeholder.closed || placeholder.closing {
    self.sessions.remove(session_id)
    return Err(native_acp_invalid_params("session resume was interrupted"))
  }
  placeholder.resuming = false
  Ok({ "configOptions": config_options })
}
