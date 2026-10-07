///|
priv enum ConnectionState {
  Offline
  Connecting
  Synced
  NeedsResync
}

///|
priv struct PendingCommand {
  mut payload_fingerprint : String?
  mut status : String
  canonical_payload : String?
  mut request : @protocol.RemoteCommand?
}

///|
/// In-memory state shared by browser and native clients. The client accepts
/// display projections and command receipts only; server authorization remains
/// authoritative on every request.
priv struct ClientState {
  mut scope : @protocol.ClientScope?
  mut epoch : String
  mut revision : Int
  mut cursor : String
  mut projection : Json?
  mut selected_session_projection : Json?
  mut auth : @protocol.AuthProjection?
  mut connection : ConnectionState
  mut draft : String
  mut selected_session : String?
  mut scroll_anchor : String?
  mut follow_latest : Bool
  mut text_view : Bool
  pending_commands : Map[String, PendingCommand]
  mut restored_cursor : String?
}

///|
priv enum SnapshotDecision {
  SnapshotAccepted
  SnapshotStale
  SnapshotIdentityChanged
  SnapshotEpochChanged
}

///|
priv enum EventDecision {
  EventApplied
  EventDuplicate
  EventGap
  EventWrongWorkspace
  EventIdentityChanged
  EventEpochChanged
  EventRequiresSnapshot
  EventCursorMismatch
}

///|
fn ClientState::new() -> ClientState {
  {
    scope: None,
    epoch: "",
    revision: 0,
    cursor: "",
    projection: None,
    selected_session_projection: None,
    auth: None,
    connection: Offline,
    draft: "",
    selected_session: None,
    scroll_anchor: None,
    follow_latest: true,
    text_view: false,
    pending_commands: Map([]),
    restored_cursor: None,
  }
}

///|
fn ClientState::begin_connect(self : ClientState) -> Unit {
  self.connection = Connecting
}

///|
fn ClientState::connection_failed(self : ClientState) -> Unit {
  self.connection = Offline
}

///|
/// Mark an EventSource/socket as restored only when no resync is pending.
fn ClientState::connection_restored(self : ClientState) -> Unit {
  if self.scope is Some(_) {
    match self.connection {
      NeedsResync => ()
      _ => self.connection = Synced
    }
  }
}

///|
fn ClientState::accept_snapshot(
  self : ClientState,
  snapshot : @protocol.RemoteSnapshot,
) -> SnapshotDecision {
  if self.scope is Some(old_scope) && !same_scope(old_scope, snapshot.scope) {
    self.scope = Some(snapshot.scope)
    self.auth = Some(snapshot.auth)
    self.epoch = snapshot.epoch
    self.revision = snapshot.revision
    self.cursor = snapshot.cursor
    self.projection = Some(snapshot.projection)
    self.selected_session_projection = None
    self.connection = Synced
    self.clear_identity_state()
    return SnapshotIdentityChanged
  }
  if self.scope is Some(_) &&
    self.epoch == snapshot.epoch &&
    snapshot.revision < self.revision {
    self.connection = Synced
    return SnapshotStale
  }
  let epoch_changed = self.scope is Some(_) && self.epoch != snapshot.epoch
  self.scope = Some(snapshot.scope)
  self.auth = Some(snapshot.auth)
  self.epoch = snapshot.epoch
  self.revision = snapshot.revision
  self.cursor = snapshot.cursor
  self.projection = Some(snapshot.projection)
  self.selected_session_projection = None
  self.connection = Synced
  self.prune_invalid_selection()
  if epoch_changed {
    SnapshotEpochChanged
  } else {
    SnapshotAccepted
  }
}

///|
fn ClientState::accept_event(
  self : ClientState,
  event : @protocol.ProjectionEvent,
) -> EventDecision {
  if self.scope is None {
    self.connection = NeedsResync
    return EventRequiresSnapshot
  }
  let scope = self.scope.unwrap()
  if event.workspace_id != scope.workspace_id {
    self.connection = NeedsResync
    return EventWrongWorkspace
  }
  if event.identity_key != scope.identity_key ||
    event.auth_revision != scope.auth_revision {
    self.connection = NeedsResync
    return EventIdentityChanged
  }
  if event.epoch != self.epoch {
    self.connection = NeedsResync
    return EventEpochChanged
  }
  if event.kind == "resync" {
    if event.projection is Some(projection) {
      self.projection = Some(projection)
      self.accept_embedded_selected_session(projection)
      self.revision = event.revision
      self.cursor = event.cursor
      self.prune_invalid_selection()
    }
    self.connection = NeedsResync
    return EventRequiresSnapshot
  }
  if event.revision <= self.revision {
    return EventDuplicate
  }
  if event.revision != self.revision + 1 {
    self.connection = NeedsResync
    return EventGap
  }
  match event.projection {
    Some(projection) => {
      self.projection = Some(projection)
      self.accept_embedded_selected_session(projection)
    }
    None => {
      self.connection = NeedsResync
      return EventRequiresSnapshot
    }
  }
  self.revision = event.revision
  self.cursor = event.cursor
  self.connection = Synced
  self.prune_invalid_selection()
  EventApplied
}

///|
fn ClientState::queue_command(
  self : ClientState,
  command_id : String,
  operation : String,
  session_id : String?,
  input : Json,
  approval_revision : Int?,
) -> Result[@protocol.RemoteCommand, String] {
  match self.connection {
    Synced => ()
    _ =>
      return Err("commands can only be sent after a current snapshot is loaded")
  }
  if !@protocol.is_uuid_v7_command_id(command_id) || operation == "" {
    return Err("a UUIDv7 command ID and operation are required")
  }
  let scope = match self.scope {
    Some(value) => value
    None => return Err("no authorized workspace is selected")
  }
  if operation == "tool_approve" {
    let call_id = json_string_field(input, "call_id")
    if call_id == "" {
      return Err("approval requires the pending call ID")
    }
    let session_id = match session_id {
      Some(value) => value
      None => return Err("approval requires its session ID")
    }
    let revision = match approval_revision {
      Some(value) => value
      None => return Err("approval requires the pending approval revision")
    }
    if self.approval_revision_for(session_id, call_id) != Some(revision) {
      return Err("approval changed; load the latest session before deciding")
    }
  } else if approval_revision is Some(_) {
    return Err("only approval commands may contain an approval revision")
  }
  let command = @protocol.RemoteCommand::{
    protocol_version: @protocol.PROTOCOL_VERSION,
    workspace_id: scope.workspace_id,
    command_id,
    session_id,
    operation,
    input,
    approval_revision,
  }
  let canonical = @protocol.canonical_command_payload(command)
  match self.pending_commands.get(command_id) {
    Some(existing) if existing.canonical_payload != Some(canonical) =>
      Err("command ID is already bound to a different payload")
    Some(existing) =>
      match existing.request {
        Some(request) => Ok(request)
        None =>
          Err(
            "command was restored without its payload; query its receipt first",
          )
      }
    None => {
      self.pending_commands[command_id] = {
        payload_fingerprint: None,
        status: "prepared",
        canonical_payload: Some(canonical),
        request: Some(command),
      }
      Ok(command)
    }
  }
}

///|
fn ClientState::mark_command_sent(
  self : ClientState,
  command_id : String,
) -> Bool {
  match self.pending_commands.get(command_id) {
    Some(pending) => {
      if pending.status == "prepared" {
        pending.status = "submitted"
      }
      true
    }
    None => false
  }
}

///|
fn ClientState::mark_command_uncertain(
  self : ClientState,
  command_id : String,
) -> Bool {
  match self.pending_commands.get(command_id) {
    Some(pending) => {
      pending.status = "uncertain"
      pending.request = None
      true
    }
    None => false
  }
}

///|
fn ClientState::apply_receipt(
  self : ClientState,
  receipt : @protocol.CommandReceipt,
) -> Result[Bool, String] {
  let scope = match self.scope {
    Some(value) => value
    None => return Err("no authorized workspace is selected")
  }
  if receipt.workspace_id != scope.workspace_id {
    return Err("receipt belongs to another workspace")
  }
  match self.pending_commands.get(receipt.command_id) {
    None => Err("receipt does not match an outstanding command")
    Some(pending) => {
      if pending.payload_fingerprint is Some(expected) &&
        expected != receipt.payload_fingerprint {
        return Err("receipt fingerprint does not match the original command")
      }
      pending.payload_fingerprint = Some(receipt.payload_fingerprint)
      pending.status = receipt.status
      pending.request = None
      if receipt.status == "completed" ||
        receipt.status == "rejected" ||
        receipt.status == "expired" {
        self.pending_commands.remove(receipt.command_id)
      }
      Ok(true)
    }
  }
}

///|
fn ClientState::mark_receipt_missing(
  self : ClientState,
  command_id : String,
) -> Bool {
  match self.pending_commands.get(command_id) {
    Some(pending) => {
      pending.status = "unconfirmed"
      pending.request = None
      true
    }
    None => false
  }
}

///|
fn ClientState::set_draft(self : ClientState, value : String) -> Unit {
  self.draft = value
}

///|
fn ClientState::set_selected_session(
  self : ClientState,
  value : String?,
) -> Unit {
  if self.selected_session != value {
    self.selected_session_projection = None
  }
  self.selected_session = value
}

///|
fn ClientState::accept_session(
  self : ClientState,
  session : @protocol.RemoteSessionProjection,
) -> (Bool, String) {
  let scope = match self.scope {
    Some(value) => value
    None => return (false, "snapshot_required")
  }
  if session.workspace_id != scope.workspace_id {
    return (false, "wrong_workspace")
  }
  if session.identity_key != scope.identity_key ||
    session.auth_revision != scope.auth_revision {
    self.connection = NeedsResync
    return (false, "identity_changed")
  }
  if session.epoch != self.epoch {
    self.connection = NeedsResync
    return (false, "epoch_changed")
  }
  if session.revision < self.revision {
    return (false, "stale")
  }
  if session.revision > self.revision {
    self.connection = NeedsResync
    return (false, "snapshot_required")
  }
  let session_id = json_string_field(session.session, "id")
  if session_id == "" ||
    (self.selected_session is Some(selected) && session_id != selected) {
    return (false, "wrong_session")
  }
  self.selected_session = Some(session_id)
  self.selected_session_projection = Some(session.session)
  (true, "accepted")
}

///|
fn ClientState::approval_revision_for(
  self : ClientState,
  session_id : String,
  call_id : String,
) -> Int? {
  let sessions = match self.projection {
    Some(Json::Object(fields)) =>
      match fields.get("sessions") {
        Some(Json::Array(items)) => items
        _ => return None
      }
    _ => return None
  }
  for session in sessions {
    if json_string_field(session, "id") == session_id {
      let pending = match json_field(session, "pending_approval") {
        Some(value) => value
        None => return None
      }
      if json_string_field(pending, "call_id") != call_id {
        return None
      }
      return json_optional_int_field(session, "approval_revision")
    }
  }
  None
}
