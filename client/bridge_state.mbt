///|
/// A handle table lets a native host own several windows/client lifetimes and
/// makes callbacks after disposal a checked error. Handles are monotonic and
/// are never reused within a process.
let client_handles : Map[Int, ClientState] = Map([])

///|
let next_client_handle : Ref[Int] = Ref(1)

///|
fn get_client(handle : Int) -> ClientState? {
  client_handles.get(handle)
}

///|
fn connection_name(state : ConnectionState) -> String {
  match state {
    Offline => "offline"
    Connecting => "connecting"
    Synced => "synced"
    NeedsResync => "needs_resync"
  }
}

///|
fn snapshot_decision_name(decision : SnapshotDecision) -> String {
  match decision {
    SnapshotAccepted => "accepted"
    SnapshotStale => "stale"
    SnapshotIdentityChanged => "identity_changed"
    SnapshotEpochChanged => "epoch_changed"
  }
}

///|
fn event_decision_name(decision : EventDecision) -> String {
  match decision {
    EventApplied => "applied"
    EventDuplicate => "duplicate"
    EventGap => "gap"
    EventWrongWorkspace => "wrong_workspace"
    EventIdentityChanged => "identity_changed"
    EventEpochChanged => "epoch_changed"
    EventRequiresSnapshot => "requires_snapshot"
    EventCursorMismatch => "cursor_mismatch"
  }
}

///|
fn client_state_json(state : ClientState) -> Json {
  let pending : Array[Json] = []
  for command_id in state.pending_command_ids() {
    match state.pending_commands.get(command_id) {
      Some(command) =>
        pending.push(
          Json::object({
            "command_id": Json::string(command_id),
            "payload_fingerprint": optional_string_json(
              command.payload_fingerprint,
            ),
            "status": Json::string(command.status),
          }),
        )
      None => ()
    }
  }
  Json::object({
    "connection": Json::string(connection_name(state.connection)),
    "scope_key": optional_string_json(state.scope_key()),
    "server_id": optional_string_json(state.scope.map(scope => scope.server_id)),
    "identity_key": optional_string_json(
      state.scope.map(scope => scope.identity_key),
    ),
    "workspace_id": optional_string_json(
      state.scope.map(scope => scope.workspace_id),
    ),
    "epoch": Json::string(state.epoch),
    "revision": Json::number(state.revision.to_double()),
    "cursor": Json::string(state.cursor),
    "restored_cursor": optional_string_json(state.restored_cursor),
    "auth": match state.auth {
      Some(auth) => auth.json()
      None => Json::null()
    },
    "projection": state.projection.unwrap_or(Json::null()),
    "selected_session_projection": state.selected_session_projection.unwrap_or(
      Json::null(),
    ),
    "draft": Json::string(state.draft),
    "selected_session": optional_string_json(state.selected_session),
    "scroll_anchor": optional_string_json(state.scroll_anchor),
    "follow_latest": Json::boolean(state.follow_latest),
    "text_view": Json::boolean(state.text_view),
    "pending_commands": Json::array(pending),
  })
}

///|
fn client_result(
  state : ClientState?,
  ok : Bool,
  status : String,
  error : String?,
) -> String {
  Json::object({
    "ok": Json::boolean(ok),
    "status": Json::string(status),
    "error": optional_string_json(error),
    "state": match state {
      Some(value) => client_state_json(value)
      None => Json::null()
    },
  }).stringify()
}

///|
/// Create an independent client lifetime and return its opaque integer handle.
#export_name("client_init")
pub fn client_init() -> Int {
  if next_client_handle.val >= 2147483647 {
    return -1
  }
  let handle = next_client_handle.val
  next_client_handle.val += 1
  client_handles[handle] = ClientState::new()
  handle
}

///|
/// Create an RFC 9562 UUIDv7 command ID using host clock and CSPRNG entropy.
/// `now_ms` is decimal Unix milliseconds; `entropy_hex` is 16 random bytes.
#export_name("client_new_command_id")
pub fn client_new_command_id(now_ms : String, entropy_hex : String) -> String {
  match parse_timestamp_ms(now_ms) {
    None => ""
    Some(timestamp) =>
      match @protocol.uuid_v7_command_id_from_entropy(timestamp, entropy_hex) {
        Ok(command_id) => command_id
        Err(_) => ""
      }
  }
}

///|
#export_name("client_dispose")
pub fn client_dispose(handle : Int) -> Bool {
  match get_client(handle) {
    Some(_) => {
      client_handles.remove(handle)
      true
    }
    None => false
  }
}

///|
#export_name("client_state")
pub fn client_state(handle : Int) -> String {
  match get_client(handle) {
    Some(state) => client_state_json(state).stringify()
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_begin_connect")
pub fn client_begin_connect(handle : Int) -> String {
  match get_client(handle) {
    Some(state) => {
      state.begin_connect()
      client_result(Some(state), true, "connecting", None)
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_connection_failed")
pub fn client_connection_failed(handle : Int) -> String {
  match get_client(handle) {
    Some(state) => {
      state.connection_failed()
      client_result(Some(state), true, "offline", None)
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_connection_restored")
pub fn client_connection_restored(handle : Int) -> String {
  match get_client(handle) {
    Some(state) => {
      state.connection_restored()
      client_result(Some(state), true, connection_name(state.connection), None)
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_accept_snapshot")
pub fn client_accept_snapshot(handle : Int, raw : String) -> String {
  match get_client(handle) {
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
    Some(state) =>
      match @protocol.RemoteSnapshot::parse(raw) {
        Ok(snapshot) => {
          let decision = state.accept_snapshot(snapshot)
          client_result(
            Some(state),
            true,
            snapshot_decision_name(decision),
            None,
          )
        }
        Err(error) =>
          client_result(Some(state), false, "invalid_snapshot", Some(error))
      }
  }
}

///|
#export_name("client_accept_session")
pub fn client_accept_session(handle : Int, raw : String) -> String {
  match get_client(handle) {
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
    Some(state) =>
      match @protocol.RemoteSessionProjection::parse(raw) {
        Ok(session) => {
          let result = state.accept_session(session)
          client_result(
            Some(state),
            result.0,
            result.1,
            if result.0 {
              None
            } else {
              Some(result.1)
            },
          )
        }
        Err(error) =>
          client_result(Some(state), false, "invalid_session", Some(error))
      }
  }
}

///|
#export_name("client_accept_event")
pub fn client_accept_event(
  handle : Int,
  raw : String,
  event_id : String,
) -> String {
  match get_client(handle) {
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
    Some(state) =>
      match @protocol.ProjectionEvent::parse(raw) {
        Ok(event) => {
          let decision = if event.cursor == event_id {
            state.accept_event(event)
          } else {
            state.connection = NeedsResync
            EventCursorMismatch
          }
          client_result(Some(state), true, event_decision_name(decision), None)
        }
        Err(error) =>
          client_result(Some(state), false, "invalid_event", Some(error))
      }
  }
}
