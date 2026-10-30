///|
const NATIVE_SUBAGENT_AUDIT_MAX_ENTRIES : Int32 = 32

///|
const NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES : Int64 = 134217728L

///|
fn native_subagent_audit_reservation_fits(
  entry_count : Int32,
  current_bytes : Int64,
  candidate_bytes : Int32,
) -> Bool {
  candidate_bytes >= 0 &&
  candidate_bytes <= NATIVE_SUBAGENT_AUDIT_MAX_BYTES &&
  entry_count >= 0 &&
  entry_count + 2 <= NATIVE_SUBAGENT_AUDIT_MAX_ENTRIES &&
  current_bytes >= 0L &&
  current_bytes + candidate_bytes.to_int64() * 2L <=
  NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES
}

///|
priv enum NativeSubagentAuditPublishOutcome {
  Published
  Fatal(String)
  Abandoned(String)
}

///|
/// Deterministic failure points for native publication tests. This enum is
/// accepted only by private runtime methods and has no CLI or protocol surface.
#warnings("-unused_constructor")
priv enum NativeSubagentAuditAtomicFault {
  Exists
  Failed
  OutcomeUnknown
  OutcomeUnknownAfterWrite
}

///|
fn native_subagent_audit_check_quota(
  root : SafeRoot,
  candidate_bytes : Int32,
) -> Result[Unit, String] {
  if candidate_bytes < 0 || candidate_bytes > NATIVE_SUBAGENT_AUDIT_MAX_BYTES {
    return Err("subagent audit record exceeds its byte limit")
  }
  let entries = match root.list_directory(".") {
    Ok(value) => value
    Err(error) => return Err("cannot enumerate subagent audits: " + error)
  }
  if entries.length() > NATIVE_SUBAGENT_AUDIT_MAX_ENTRIES {
    return Err("subagent audit directory exceeds its entry limit")
  }
  let mut total_bytes = 0L
  for (name, kind) in entries {
    if kind == "directory" {
      return Err("subagent audit directory contains a nested directory")
    }
    if kind != "file" {
      return Err("subagent audit directory contains an uncountable entry")
    }
    let version = match root.file_version(name) {
      Ok(value) => value
      Err(error) =>
        return Err("cannot account for subagent audit file: " + error)
    }
    let size = version.size()
    if size < 0L {
      return Err("subagent audit file has an invalid logical size")
    }
    total_bytes += size
    if total_bytes > NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES {
      return Err("subagent audit directory exceeds its byte limit")
    }
  }
  if !native_subagent_audit_reservation_fits(
      entries.length(),
      total_bytes,
      candidate_bytes,
    ) {
    return Err("subagent audit record cannot reserve its destination and temp")
  }
  Ok(())
}

///|
fn native_subagent_audit_atomic_outcome(
  result : Result[Unit, AtomicCreateNoReplaceError],
) -> NativeSubagentAuditPublishOutcome {
  match result {
    Ok(_) => NativeSubagentAuditPublishOutcome::Published
    Err(AtomicCreateNoReplaceError::Exists) =>
      NativeSubagentAuditPublishOutcome::Fatal(
        "subagent audit destination already exists",
      )
    Err(AtomicCreateNoReplaceError::Failed(error)) =>
      NativeSubagentAuditPublishOutcome::Fatal(
        "subagent audit was not published: " + error,
      )
    Err(AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
      NativeSubagentAuditPublishOutcome::Fatal(
        "subagent audit publication outcome is unknown: " + error,
      )
  }
}

///|
fn native_subagent_audit_atomic_create(
  root : SafeRoot,
  relative_path : String,
  encoded : String,
  fault : NativeSubagentAuditAtomicFault?,
) -> Result[Unit, AtomicCreateNoReplaceError] {
  match fault {
    Some(NativeSubagentAuditAtomicFault::Exists) =>
      match root.create_exclusive(relative_path, "injected existing audit") {
        Ok(_) => Err(AtomicCreateNoReplaceError::Exists)
        Err(error) =>
          Err(
            AtomicCreateNoReplaceError::Failed(
              "cannot inject existing audit destination: " + error,
            ),
          )
      }
    Some(NativeSubagentAuditAtomicFault::Failed) =>
      Err(AtomicCreateNoReplaceError::Failed("injected atomic create failure"))
    Some(NativeSubagentAuditAtomicFault::OutcomeUnknown) =>
      Err(
        AtomicCreateNoReplaceError::OutcomeUnknown(
          "injected pre-publication uncertainty",
        ),
      )
    Some(NativeSubagentAuditAtomicFault::OutcomeUnknownAfterWrite) =>
      match
        root.create_atomic_no_replace(
          relative_path,
          encoded,
          NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
          permission=0o600,
        ) {
        Ok(_) =>
          Err(
            AtomicCreateNoReplaceError::OutcomeUnknown(
              "injected uncertainty after atomic publication",
            ),
          )
        Err(error) => Err(error)
      }
    None =>
      root.create_atomic_no_replace(
        relative_path,
        encoded,
        NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
        permission=0o600,
      )
  }
}

///|
async fn NativeRuntime::open_subagent_audit_root(
  self : NativeRuntime,
) -> Result[SafeRoot, String] {
  let directory_path = native_path_normalize(
    self.store.path() + "/subagent-audits",
  )
  @fs.mkdir(directory_path, permission=0o700, allow_exist=true) catch {
    _ => return Err("cannot create subagent audit directory")
  }
  let resolved_path = native_path_normalize(
    @fs.realpath(directory_path) catch {
      _ => return Err("cannot resolve subagent audit directory")
    },
  )
  if resolved_path != directory_path {
    return Err("subagent audit directory does not match its expected path")
  }
  let root = match SafeRoot::open(directory_path) {
    Ok(value) => value
    Err(error) => return Err("cannot open subagent audit directory: " + error)
  }
  match root.restrict_owner_only() {
    Ok(_) => Ok(root)
    Err(error) => {
      root.close()
      Err("cannot protect subagent audit directory: " + error)
    }
  }
}

///|
async fn NativeRuntime::publish_subagent_audit(
  self : NativeRuntime,
  effect : @engine.EngineEffect,
  parent_turn_id~ : Int32,
  parent_call_id : String,
  child_id : String,
  child_status : String,
  child_snapshot : Json,
  control : NativeJobControl?,
  fault~ : NativeSubagentAuditAtomicFault? = None,
) -> NativeSubagentAuditPublishOutcome {
  let root = match self.open_subagent_audit_root() {
    Ok(value) => value
    Err(error) => return NativeSubagentAuditPublishOutcome::Fatal(error)
  }
  defer root.close()
  self.gate.acquire()
  defer self.gate.release()
  if @async.is_being_cancelled() {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "child audit publication was cancelled",
    )
  }
  if self.stopped || self.closed {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "native runtime stopped before child audit publication",
    )
  }
  if (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "child audit publication was cancelled",
    )
  }
  let parent_session_id = effect.session_id().as_string()
  let effect_id = effect.id()
  let session_id = match @engine.SessionId::new(parent_session_id) {
    Ok(value) => value
    Err(error) =>
      return NativeSubagentAuditPublishOutcome::Fatal(
        "parent session identity is invalid: " + error,
      )
  }
  let call_id = match @engine.ToolCallId::new(parent_call_id) {
    Ok(value) => value
    Err(error) =>
      return NativeSubagentAuditPublishOutcome::Fatal(
        "parent tool call identity is invalid: " + error,
      )
  }
  if !self.api.owns_pending_tool_effect(effect_id, session_id, call_id) {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "parent tool effect no longer owns the child audit outcome",
    )
  }
  let parent_session = match
    self.api.invoke("session_get", { "session_id": parent_session_id }) {
    Ok(value) => value
    Err(error) =>
      return NativeSubagentAuditPublishOutcome::Abandoned(
        "cannot inspect parent before child audit publication: " + error,
      )
  }
  if string_field(parent_session, "status") != Some("running") ||
    int_field(parent_session, "turn_id") != Some(parent_turn_id) {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "parent turn settled before child audit publication",
    )
  }
  let record : Json = {
    "schema": NATIVE_SUBAGENT_AUDIT_SCHEMA,
    "parent_session_id": parent_session_id,
    "parent_turn_id": parent_turn_id,
    "parent_effect_id": effect_id.as_string(),
    "parent_tool_call_id": parent_call_id,
    "child_id": child_id,
    "workspace_id": self.state.workspace_id,
    "child_status": child_status,
    "engine_snapshot": child_snapshot,
  }
  let encoded = match native_subagent_audit_encode(record) {
    Ok(value) => value
    Err(error) =>
      return NativeSubagentAuditPublishOutcome::Fatal(
        "cannot encode settled child audit: " + error,
      )
  }
  let candidate_bytes = @utf8.encode(encoded).length()
  if (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "child audit publication was cancelled",
    )
  }
  match native_subagent_audit_check_quota(root, candidate_bytes) {
    Ok(_) => ()
    Err(error) => return NativeSubagentAuditPublishOutcome::Fatal(error)
  }
  if (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return NativeSubagentAuditPublishOutcome::Abandoned(
      "child audit publication was cancelled",
    )
  }
  let relative_path = child_id + ".json"
  native_subagent_audit_atomic_outcome(
    native_subagent_audit_atomic_create(root, relative_path, encoded, fault),
  )
}

///|
async fn NativeRuntime::interrupt_for_subagent_audit_failure(
  self : NativeRuntime,
  effect : @engine.EngineEffect,
  parent_turn_id : Int32,
  parent_call_id : String,
  control : NativeJobControl?,
) -> Result[Bool, String] {
  self.gate.acquire()
  defer self.gate.release()
  if @async.is_being_cancelled() {
    return Ok(false)
  }
  if self.stopped || self.closed {
    return Ok(false)
  }
  if (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return Ok(false)
  }
  let session_id_text = effect.session_id().as_string()
  let session_id = match @engine.SessionId::new(session_id_text) {
    Ok(value) => value
    Err(_) => return Ok(false)
  }
  let call_id = match @engine.ToolCallId::new(parent_call_id) {
    Ok(value) => value
    Err(_) => return Ok(false)
  }
  if !self.api.owns_pending_tool_effect(effect.id(), session_id, call_id) {
    return Ok(false)
  }
  let session = match
    self.api.invoke("session_get", { "session_id": session_id_text }) {
    Ok(value) => value
    Err(_) => return Ok(false)
  }
  if string_field(session, "status") != Some("running") ||
    int_field(session, "turn_id") != Some(parent_turn_id) {
    return Ok(false)
  }
  if (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return Ok(false)
  }
  match self.api.interrupt_owned_tool_effect(effect.id(), session_id, call_id) {
    Ok(false) => Ok(false)
    Ok(true) =>
      match self.checkpoint_locked() {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    Err(error) => {
      // The engine leaves the candidate unadopted on this error. Stop this
      // runtime so the same in-memory effect cannot run after an
      // unrecordable fatal child outcome. Restore will close the unfinished
      // effect without replay if the prior checkpoint is still readable.
      self.stopped = true
      Err("cannot record fatal child interruption: " + error)
    }
  }
}

///|
async fn NativeRuntime::confirm_subagent_audit_publication(
  self : NativeRuntime,
  effect : @engine.EngineEffect,
  parent_turn_id : Int32,
  parent_call_id : String,
  control : NativeJobControl?,
) -> Bool {
  self.gate.acquire()
  defer self.gate.release()
  if self.stopped ||
    self.closed ||
    (control is Some(value) && value.cancelled.val) ||
    @async.is_being_cancelled() {
    return false
  }
  let session_id_text = effect.session_id().as_string()
  let session_id = match @engine.SessionId::new(session_id_text) {
    Ok(value) => value
    Err(_) => return false
  }
  let call_id = match @engine.ToolCallId::new(parent_call_id) {
    Ok(value) => value
    Err(_) => return false
  }
  if !self.api.owns_pending_tool_effect(effect.id(), session_id, call_id) {
    return false
  }
  let session = match
    self.api.invoke("session_get", { "session_id": session_id_text }) {
    Ok(value) => value
    Err(_) => return false
  }
  string_field(session, "status") == Some("running") &&
  int_field(session, "turn_id") == Some(parent_turn_id)
}
