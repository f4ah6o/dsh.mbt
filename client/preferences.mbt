///|
fn ClientState::set_scroll_anchor(
  self : ClientState,
  value : String?,
) -> Unit {
  self.scroll_anchor = value
}

///|
fn ClientState::set_follow_latest(self : ClientState, value : Bool) -> Unit {
  self.follow_latest = value
}

///|
fn ClientState::set_text_view(self : ClientState, value : Bool) -> Unit {
  self.text_view = value
}

///|
fn ClientState::scope_key(self : ClientState) -> String? {
  self.scope.map(scope => scope.storage_key())
}

///|
/// Preferences contain only the user's draft, selection, scroll anchor,
/// cursor, and unresolved command identifiers/fingerprints. They never include
/// a session snapshot, auth claims, or a command body.
fn ClientState::preferences_json(self : ClientState) -> Json {
  let commands : Array[Json] = []
  for command_id, pending in self.pending_commands {
    commands.push(
      Json::object({
        "command_id": Json::string(command_id),
        "payload_fingerprint": preferences_optional_string_json(
          pending.payload_fingerprint,
        ),
        "status": Json::string(pending.status),
      }),
    )
  }
  Json::object({
    "schema_version": Json::number(1.0),
    "scope_key": Json::string(self.scope_key().unwrap_or("")),
    "draft": Json::string(self.draft),
    "selected_session": preferences_optional_string_json(self.selected_session),
    "scroll_anchor": preferences_optional_string_json(self.scroll_anchor),
    "cursor": preferences_optional_string_json(self.scope.map(_ => self.cursor)),
    "commands": Json::array(commands),
    "follow_latest": Json::boolean(self.follow_latest),
    "text_view": Json::boolean(self.text_view),
  })
}

///|
#warnings("-deprecated")
fn ClientState::restore_preferences(
  self : ClientState,
  raw : String,
) -> Bool {
  let expected = self.scope_key()
  if expected is None || raw.length() > 2_097_152 {
    self.clear_identity_state()
    return false
  }
  let prefs = @json.parse(raw, max_nesting_depth=16) catch {
    _ => {
      self.clear_identity_state()
      return false
    }
  }
  if json_int_field(prefs, "schema_version") != 1 ||
    json_string_field(prefs, "scope_key") != expected.unwrap() {
    self.clear_identity_state()
    return false
  }
  self.draft = json_string_field(prefs, "draft")
  self.selected_session = json_optional_string_field(prefs, "selected_session")
  self.scroll_anchor = json_optional_string_field(prefs, "scroll_anchor")
  self.restored_cursor = json_optional_string_field(prefs, "cursor")
  self.follow_latest = json_bool_field(prefs, "follow_latest").unwrap_or(true)
  self.text_view = json_bool_field(prefs, "text_view").unwrap_or(false)
  self.pending_commands.clear()
  match json_array_field(prefs, "commands") {
    Some(commands) =>
      for command in commands {
        let command_id = json_string_field(command, "command_id")
        if @protocol.is_uuid_v7_command_id(command_id) {
          let status = json_string_field(command, "status")
          self.pending_commands[command_id] = {
            payload_fingerprint: json_optional_string_field(
              command, "payload_fingerprint",
            ),
            status: if status == "completed" ||
              status == "rejected" ||
              status == "expired" {
              status
            } else {
              "needs_receipt_check"
            },
            canonical_payload: None,
            request: None,
          }
        }
      }
    None => ()
  }
  self.prune_invalid_selection()
  true
}

///|
fn ClientState::pending_command_ids(self : ClientState) -> Array[String] {
  let ids : Array[String] = []
  for command_id, _ in self.pending_commands {
    ids.push(command_id)
  }
  ids.sort()
  ids
}

///|
fn ClientState::clear_identity_state(self : ClientState) -> Unit {
  self.draft = ""
  self.selected_session = None
  self.scroll_anchor = None
  self.follow_latest = true
  self.text_view = false
  self.pending_commands.clear()
  self.restored_cursor = None
  self.selected_session_projection = None
}

///|
fn ClientState::prune_invalid_selection(self : ClientState) -> Unit {
  match self.selected_session {
    Some(id) if !projection_has_session(self.projection, id) => {
      self.selected_session = None
      self.selected_session_projection = None
    }
    _ => ()
  }
}

///|
fn ClientState::accept_embedded_selected_session(
  self : ClientState,
  projection : Json,
) -> Unit {
  let selected = match self.selected_session {
    Some(value) => value
    None => return
  }
  match json_field(projection, "selected_session") {
    Some(session) if json_string_field(session, "id") == selected =>
      self.selected_session_projection = Some(session)
    _ => self.selected_session_projection = None
  }
}

///|
fn same_scope(
  left : @protocol.ClientScope,
  right : @protocol.ClientScope,
) -> Bool {
  left.server_id == right.server_id &&
  left.identity_key == right.identity_key &&
  left.workspace_id == right.workspace_id &&
  left.auth_revision == right.auth_revision
}

///|
fn projection_has_session(projection : Json?, session_id : String) -> Bool {
  match projection {
    Some(Json::Object(fields)) =>
      match fields.get("sessions") {
        Some(Json::Array(sessions)) =>
          sessions.any(session => json_string_field(session, "id") == session_id)
        _ => false
      }
    _ => false
  }
}
