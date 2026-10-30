///|
fn native_subagent_audit_valid_child_id(child_id : String) -> Bool {
  if !child_id.has_prefix("subagent-") || child_id.length() != 45 {
    return false
  }
  is_uuid_v4(child_id[9:].to_owned())
}

///|
fn native_subagent_audit_child_id_from_filename(
  name : String,
) -> Result[String?, String] {
  if !name.has_prefix("subagent-") ||
    name.length() <= 5 ||
    name[name.length() - 5:].to_owned() != ".json" {
    return Ok(None)
  }
  let child_id = name[:name.length() - 5].to_owned()
  if !native_subagent_audit_valid_child_id(child_id) {
    return Err("subagent audit filename is invalid")
  }
  Ok(Some(child_id))
}

///|
fn native_subagent_audit_inspection_check_data_root(
  data_root : SafeRoot,
) -> Result[Unit, String] {
  let root_version = match data_root.directory_version() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if root_version.owner_uid() != os_uid() || root_version.permission() != 0o700 {
    return Err(
      "native data directory must be owned by the current user with mode 0700",
    )
  }
  Ok(())
}

///|
fn native_subagent_audit_inspection_workspace_id(
  data_root : SafeRoot,
) -> Result[String, String] {
  let text = match
    data_root.read_protected_text("workspace-id", max_bytes=128) {
    Ok(Some(value)) => value
    Ok(None) => return Err("native data directory has no workspace identity")
    Err(error) => return Err("cannot read native workspace identity: " + error)
  }
  let workspace_id = text.trim().to_owned()
  if workspace_id.length() < 16 || workspace_id.length() > 64 {
    return Err("native data directory has an invalid workspace identity")
  }
  Ok(workspace_id)
}

///|
fn native_subagent_audit_inspection_bound_entries(
  data_root : SafeRoot,
  entries : Array[(String, String)],
) -> Result[Unit, String] {
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
    let version = match data_root.file_version("subagent-audits/" + name) {
      Ok(value) => value
      Err(error) => return Err("cannot inspect subagent audit entry: " + error)
    }
    if version.owner_uid() != os_uid() || version.permission() != 0o600 {
      return Err("subagent audit entry must be owner-only with mode 0600")
    }
    let size = version.size()
    if size < 0L {
      return Err("subagent audit entry has an invalid logical size")
    }
    if !native_subagent_audit_inspection_byte_add_fits(total_bytes, size) {
      return Err("subagent audit directory exceeds its byte limit")
    }
    total_bytes += size
  }
  Ok(())
}

///|
fn native_subagent_audit_inspection_byte_add_fits(
  current_bytes : Int64,
  added_bytes : Int64,
) -> Bool {
  current_bytes >= 0L &&
  current_bytes <= NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES &&
  added_bytes >= 0L &&
  added_bytes <= NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES - current_bytes
}

///|
fn native_subagent_audit_inspection_read(
  data_root : SafeRoot,
  child_id : String,
) -> Result[Json, String] {
  if !native_subagent_audit_valid_child_id(child_id) {
    return Err("subagent audit child ID is invalid")
  }
  let name = child_id + ".json"
  let raw = match
    data_root.read_protected_text(
      "subagent-audits/" + name,
      max_bytes=NATIVE_SUBAGENT_AUDIT_MAX_BYTES,
    ) {
    Ok(Some(value)) => value
    Ok(None) =>
      return Err("subagent audit was not found for this parent session")
    Err(error) => return Err("cannot read subagent audit: " + error)
  }
  let record = match native_subagent_audit_decode(raw) {
    Ok(value) => value
    Err(error) => return Err("subagent audit is invalid: " + error)
  }
  if string_field(record, "child_id") != Some(child_id) {
    return Err("subagent audit filename does not match its child identity")
  }
  Ok(record)
}

///|
/// Read only bounded, inert records from an existing current-user data
/// directory. The stored workspace ID and requested parent ID are filters for
/// record correlation; they do not authorize execution or adoption.
fn native_subagent_audit_inspect_data_dir(
  data_dir : String,
  parent_session_id : String,
  child_id : String?,
) -> Result[Json, String] {
  if @engine.SessionId::new(parent_session_id) is Err(_) {
    return Err("subagent audit parent session ID is invalid")
  }
  let absolute_data_dir = if native_path_is_absolute(data_dir) {
    native_path_normalize(data_dir)
  } else {
    let current = match @env.current_dir() {
      Some(value) => value
      None => return Err("cannot determine the current directory")
    }
    native_path_normalize(current + "/" + data_dir)
  }
  if !native_path_is_absolute(absolute_data_dir) ||
    absolute_data_dir.contains("\u0000") {
    return Err("native data directory path is invalid")
  }
  let data_root = match SafeRoot::open(absolute_data_dir) {
    Ok(value) => value
    Err(error) => return Err("cannot open native data directory: " + error)
  }
  defer data_root.close()
  match native_subagent_audit_inspection_check_data_root(data_root) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let audit_directory_kind = match data_root.entry_kind("subagent-audits") {
    Ok(value) => value
    Err(error) => return Err("cannot inspect subagent audit path: " + error)
  }
  match audit_directory_kind {
    None =>
      return match child_id {
        Some(_) => Err("subagent audit was not found for this parent session")
        None =>
          Ok({
            "kind": "subagent-audits",
            "parent_session_id": parent_session_id,
            "audits": [],
          })
      }
    Some("directory") => ()
    Some(_) => return Err("subagent audit path is not a regular directory")
  }
  let audit_directory_version = match
    data_root.directory_version_at("subagent-audits") {
    Ok(value) => value
    Err(error) =>
      return Err("cannot inspect subagent audit directory: " + error)
  }
  if audit_directory_version.owner_uid() != os_uid() ||
    audit_directory_version.permission() != 0o700 {
    return Err(
      "subagent audit directory must be owned by the current user with mode 0700",
    )
  }
  let workspace_id = match
    native_subagent_audit_inspection_workspace_id(data_root) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let entries = match data_root.list_directory("subagent-audits") {
    Ok(value) => value
    Err(error) => return Err("cannot list subagent audits: " + error)
  }
  match native_subagent_audit_inspection_bound_entries(data_root, entries) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match child_id {
    Some(selected_child_id) => {
      let record = match
        native_subagent_audit_inspection_read(data_root, selected_child_id) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if string_field(record, "parent_session_id") != Some(parent_session_id) ||
        string_field(record, "workspace_id") != Some(workspace_id) {
        return Err("subagent audit was not found for this parent session")
      }
      Ok({ "kind": "subagent-audit", "audit": record })
    }
    None => {
      let audits : Array[Json] = []
      for (name, kind) in entries {
        ignore(kind)
        let candidate = match
          native_subagent_audit_child_id_from_filename(name) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        match candidate {
          None => ()
          Some(candidate_id) => {
            let record = match
              native_subagent_audit_inspection_read(data_root, candidate_id) {
              Ok(value) => value
              Err(error) => return Err(error)
            }
            if string_field(record, "parent_session_id") ==
              Some(parent_session_id) &&
              string_field(record, "workspace_id") == Some(workspace_id) {
              audits.push({
                "child_id": candidate_id,
                "child_status": string_field(record, "child_status").unwrap_or(
                  "unknown",
                ),
                "parent_turn_id": object_field(record, "parent_turn_id").unwrap_or(
                  Json::null(),
                ),
                "parent_effect_id": string_field(record, "parent_effect_id").unwrap_or(
                  "",
                ),
                "parent_tool_call_id": string_field(
                  record, "parent_tool_call_id",
                ).unwrap_or(""),
              })
            }
          }
        }
      }
      Ok({
        "kind": "subagent-audits",
        "parent_session_id": parent_session_id,
        "audits": Json::array(audits),
      })
    }
  }
}

///|
fn native_cli_subagent_audit_action(
  args : Array[String],
) -> Result[Json, String] {
  let parent_session_id = match native_option(args, "--session") {
    Some(value) => value
    None => return Err("--session PARENT_SESSION_ID is required")
  }
  let positionals = native_cli_positionals(args)
  let child_id = match positionals {
    ["list"] => None
    ["show", value] => Some(value)
    _ => return Err("use subagent-audits list or subagent-audits show CHILD_ID")
  }
  let (data_dir, _) = match native_cli_paths(args) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  native_subagent_audit_inspect_data_dir(data_dir, parent_session_id, child_id)
}
