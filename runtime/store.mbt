///|
/// Native persistence uses one versioned file for engine state, remote
/// receipts, and synchronization identity. A receipt can never commit apart
/// from the projection revision it acknowledges.
const NATIVE_ENVELOPE_SCHEMA : String = "dsh.native-host-v1"

///|
const SNAPSHOT_LIMIT : Int = 33554432

///|
/// ACP owns only the sessions it creates. This adjunct registry records the
/// canonical startup workspace and last ACP prompt time without changing the
/// native engine event schema.
priv struct NativeAcpStoredSession {
  session_id : String
  cwd : String
  updated_at : String?
}

///|
priv struct NativeState {
  engine : Json
  mut receipts : Array[Json]
  mut acp_sessions : Array[NativeAcpStoredSession]
  server_id : String
  workspace_id : String
  identity_key : String
  epoch : String
  revision : Int
  auth_revision : Int
  external_mcp_catalog_hash : String?
  lsp_catalog_hash : String?
}

///|
priv struct NativeStore {
  root : SafeRoot
  path : String
  token : String
  server_id : String
  workspace_id : String
  host_id : String
  mut version : FileVersion?
  mut closed : Bool
}

///|
fn parse_json(raw : String) -> Result[Json, String] {
  Ok(@json.parse(raw)) catch {
    _ => Err("invalid JSON")
  }
}

///|
fn object_field(value : Json, name : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn string_field(value : Json, name : String) -> String? {
  match object_field(value, name) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn int_field(value : Json, name : String) -> Int? {
  match object_field(value, name) {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => Some(number.to_int())
    _ => None
  }
}

///|
fn json_string(value : Json?) -> String {
  match value {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn json_int(value : Json?) -> Int {
  match value {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ => -1
  }
}

///|
fn native_acp_timestamp_digit(character : Char) -> Int {
  match character {
    '0' => 0
    '1' => 1
    '2' => 2
    '3' => 3
    '4' => 4
    '5' => 5
    '6' => 6
    '7' => 7
    '8' => 8
    '9' => 9
    _ => -1
  }
}

///|
fn native_acp_valid_timestamp(value : String) -> Bool {
  if value.length() != 20 {
    return false
  }
  let mut year = 0
  let mut month = 0
  let mut day = 0
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  for index, character in value {
    if index == 4 || index == 7 {
      if character != '-' {
        return false
      }
    } else if index == 10 {
      if character != 'T' {
        return false
      }
    } else if index == 13 || index == 16 {
      if character != ':' {
        return false
      }
    } else if index == 19 {
      if character != 'Z' {
        return false
      }
    } else {
      let digit = native_acp_timestamp_digit(character)
      if digit < 0 {
        return false
      }
      if index < 4 {
        year = year * 10 + digit
      } else if index < 7 {
        month = month * 10 + digit
      } else if index < 10 {
        day = day * 10 + digit
      } else if index < 13 {
        hour = hour * 10 + digit
      } else if index < 16 {
        minute = minute * 10 + digit
      } else {
        second = second * 10 + digit
      }
    }
  }
  let leap_year = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
  let days_in_month = match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 if leap_year => 29
    2 => 28
    _ => 0
  }
  day >= 1 && day <= days_in_month && hour <= 23 && minute <= 59 && second <= 59
}

///|
fn native_acp_stored_sessions_from_json(
  value : Json?,
) -> Result[Array[NativeAcpStoredSession], String] {
  let entries = match value {
    None | Some(Json::Null) => return Ok([])
    Some(Json::Array(values)) if values.length() <= 32 => values
    _ => return Err("native snapshot has an invalid ACP session registry")
  }
  let result : Array[NativeAcpStoredSession] = []
  let seen : Map[String, Bool] = Map([])
  for entry in entries {
    let session_id = match string_field(entry, "session_id") {
      Some(value) if !value.is_empty() && value.length() <= 128 => value
      _ => return Err("native snapshot has an invalid ACP session id")
    }
    if @engine.SessionId::new(session_id) is Err(_) ||
      seen.get(session_id) is Some(_) {
      return Err("native snapshot has a duplicate or invalid ACP session id")
    }
    let cwd = match string_field(entry, "cwd") {
      Some(value) if value.has_prefix("/") && value.length() <= 4096 => value
      _ => return Err("native snapshot has an invalid ACP session cwd")
    }
    let updated_at = match object_field(entry, "updated_at") {
      None | Some(Json::Null) => None
      Some(Json::String(value)) if native_acp_valid_timestamp(value) =>
        Some(value)
      _ => return Err("native snapshot has an invalid ACP session timestamp")
    }
    seen.set(session_id, true)
    result.push({ session_id, cwd, updated_at, })
  }
  Ok(result)
}

///|
fn native_acp_stored_sessions_json(
  sessions : Array[NativeAcpStoredSession],
) -> Json {
  Json::array(
    sessions.map(session => {
      let fields : Map[String, Json] = {
        "session_id": Json::string(session.session_id),
        "cwd": Json::string(session.cwd),
      }
      match session.updated_at {
        Some(value) => fields["updated_at"] = Json::string(value)
        None => ()
      }
      Json::object(fields)
    }),
  )
}

///|
fn random_hex(byte_count : Int) -> Result[String, String] {
  match @env.rand(byte_count) {
    None => Err("operating system secure random source is unavailable")
    Some(bytes) => {
      let output = StringBuilder()
      for byte in bytes {
        let value = byte.to_int()
        if value < 16 {
          output.write_char('0')
        }
        output.write_string(value.to_string(radix=16))
      }
      Ok(output.to_string())
    }
  }
}

///|
fn random_uuid() -> Result[String, String] {
  match @env.rand(16) {
    None => Err("operating system secure random source is unavailable")
    Some(random) => {
      let bytes = FixedArray::makei(16, index => random[index])
      bytes[6] = ((bytes[6].to_int() & 0x0F) | 0x40).to_byte()
      bytes[8] = ((bytes[8].to_int() & 0x3F) | 0x80).to_byte()
      let hex = StringBuilder()
      for index = 0; index < 16; index = index + 1 {
        if index == 4 || index == 6 || index == 8 || index == 10 {
          hex.write_char('-')
        }
        let value = bytes[index].to_int()
        if value < 16 {
          hex.write_char('0')
        }
        hex.write_string(value.to_string(radix=16))
      }
      Ok(hex.to_string())
    }
  }
}

///|
fn is_hex_digit(value : Char) -> Bool {
  (value >= '0' && value <= '9') ||
  (value >= 'a' && value <= 'f') ||
  (value >= 'A' && value <= 'F')
}

///|
fn host_id_char(value : String, index : Int) -> Char {
  value[index].to_char().unwrap_or('!')
}

///|
fn is_uuid_v4(value : String) -> Bool {
  if value.length() != 36 || host_id_char(value, 14) != '4' {
    return false
  }
  for index = 0; index < value.length(); index = index + 1 {
    let character = host_id_char(value, index)
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if character != '-' {
        return false
      }
    } else if !is_hex_digit(character) {
      return false
    }
  }
  let variant = host_id_char(value, 19)
  variant == '8' ||
  variant == '9' ||
  variant == 'a' ||
  variant == 'b' ||
  variant == 'A' ||
  variant == 'B'
}

///|
fn is_legacy_host_id(value : String) -> Bool {
  if value.length() != 48 {
    return false
  }
  for index = 0; index < value.length(); index = index + 1 {
    if !is_hex_digit(host_id_char(value, index)) {
      return false
    }
  }
  true
}

///|
fn stable_host_uuid(root : SafeRoot, file : String) -> Result[String, String] {
  match root.read_text_optional(file, max_bytes=128) {
    Err(error) => Err(error)
    Ok(Some((text, version))) => {
      let previous = text.trim().to_owned()
      if is_uuid_v4(previous) {
        Ok(previous)
      } else if is_legacy_host_id(previous) {
        match random_uuid() {
          Err(error) => Err(error)
          Ok(uuid) =>
            match
              root.write_atomic(file, uuid, expected=version, permission=0o600) {
              Ok(_) => Ok(uuid)
              Err(error) =>
                Err("cannot migrate the stable host identifier: " + error)
            }
        }
      } else {
        Err("invalid stable host identifier file")
      }
    }
    Ok(None) =>
      match random_uuid() {
        Err(error) => Err(error)
        Ok(uuid) =>
          match root.create_exclusive_code(file, uuid, permission=0o600) {
            Ok(_) => Ok(uuid)
            Err(17) => stable_host_uuid(root, file)
            Err(code) =>
              Err(
                "cannot persist stable host identifier (OS error " +
                code.to_string() +
                ")",
              )
          }
      }
  }
}

///|
fn stable_id(root : SafeRoot, file : String) -> Result[String, String] {
  match root.read_text_optional(file, max_bytes=128) {
    Err(error) => Err(error)
    Ok(Some((text, _))) => {
      let value = text.trim()
      if value.length() < 16 || value.length() > 64 {
        Err("invalid stable host identity file")
      } else {
        Ok(value.to_owned())
      }
    }
    Ok(None) =>
      match random_hex(24) {
        Err(error) => Err(error)
        Ok(value) =>
          match root.create_exclusive_code(file, value, permission=0o600) {
            Ok(_) => Ok(value)
            Err(17) =>
              match root.read_text(file, max_bytes=128) {
                Ok((text, _)) => Ok(text.trim().to_owned())
                Err(error) => Err(error)
              }
            Err(code) =>
              Err(
                "cannot persist stable host identity (OS error " +
                code.to_string() +
                ")",
              )
          }
      }
  }
}

///|
fn owner_json(token : String, hostname : String) -> Result[String, String] {
  match os_timestamp() {
    Err(error) => Err(error)
    Ok(created_at) =>
      Ok(
        Json::object({
          "pid": Json::number(os_pid().to_double()),
          "hostname": Json::string(hostname),
          "token": Json::string(token),
          "created_at": Json::string(created_at),
        }).stringify(),
      )
  }
}

///|
fn NativeStore::read_lock(root : SafeRoot) -> Result[Json, String] {
  match root.read_text("host.lock", max_bytes=4096) {
    Err(error) =>
      Err("data directory is locked or has an invalid host.lock: " + error)
    Ok((text, _)) =>
      match parse_json(text) {
        Ok(Json::Object(_) as value) => Ok(value)
        _ => Err("data directory has an invalid host.lock")
      }
  }
}

///|
fn NativeStore::acquire(
  root : SafeRoot,
  token : String,
  hostname : String,
) -> Result[Unit, String] {
  let owner = match owner_json(token, hostname) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match root.create_exclusive_code("host.lock", owner, permission=0o600) {
    Ok(_) => return Ok(())
    Err(17) => ()
    Err(code) =>
      return Err("cannot create host.lock (OS error " + code.to_string() + ")")
  }
  let previous = match NativeStore::read_lock(root) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let previous_pid = json_int(object_field(previous, "pid"))
  let previous_host = json_string(object_field(previous, "hostname"))
  let previous_token = json_string(object_field(previous, "token"))
  if previous_host != hostname || os_process_alive(previous_pid) {
    return Err(
      "another host owns this data directory (pid " +
      previous_pid.to_string() +
      ")",
    )
  }
  match root.create_exclusive_code("host.recovery", owner, permission=0o600) {
    Ok(_) => ()
    Err(17) =>
      return Err(
        "another host is acquiring or recovering the data directory; retry starting the host",
      )
    Err(code) =>
      return Err(
        "cannot create host recovery marker (OS error " + code.to_string() + ")",
      )
  }
  let current = match NativeStore::read_lock(root) {
    Ok(value) => value
    Err(error) => {
      ignore(root.unlink_missing_ok("host.recovery"))
      return Err(error)
    }
  }
  let current_pid = json_int(object_field(current, "pid"))
  let current_host = json_string(object_field(current, "hostname"))
  let current_token = json_string(object_field(current, "token"))
  if current_token != previous_token ||
    current_host != hostname ||
    os_process_alive(current_pid) {
    ignore(root.unlink_missing_ok("host.recovery"))
    return Err(
      "host lock changed during stale recovery; retry starting the host",
    )
  }
  if root.unlink("host.lock") is Err(error) {
    ignore(root.unlink_missing_ok("host.recovery"))
    return Err(error)
  }
  let recovery_result = match
    root.create_exclusive_code("host.lock", owner, permission=0o600) {
    Ok(_) => Ok(())
    Err(17) => Err("another host acquired the data directory during recovery")
    Err(code) =>
      Err(
        "cannot create host.lock after stale recovery (OS error " +
        code.to_string() +
        ")",
      )
  }
  ignore(root.unlink_missing_ok("host.recovery"))
  recovery_result
}

///|
async fn NativeStore::open(data_dir : String) -> Result[NativeStore, String] {
  let absolute = if data_dir.has_prefix("/") {
    data_dir
  } else {
    match @env.current_dir() {
      Some(current) => current + "/" + data_dir
      None => return Err("cannot determine current directory")
    }
  }
  @fs.mkdir(absolute, permission=0o700, recursive=true, allow_exist=true) catch {
    _ => return Err("cannot create native data directory")
  }
  let canonical = @fs.realpath(absolute) catch {
    _ => return Err("cannot resolve native data directory")
  }
  let root = match SafeRoot::open(canonical) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  match root.restrict_owner_only() {
    Ok(_) => ()
    Err(error) => {
      root.close()
      return Err(error)
    }
  }
  let token = match random_hex(24) {
    Ok(value) => value
    Err(error) => {
      root.close()
      return Err(error)
    }
  }
  let hostname = match os_hostname() {
    Ok(value) => value
    Err(error) => {
      root.close()
      return Err(error)
    }
  }
  match NativeStore::acquire(root, token, hostname) {
    Err(error) => {
      root.close()
      Err(error)
    }
    Ok(_) => {
      let server_id = stable_id(root, "server-id")
      let workspace_id = stable_id(root, "workspace-id")
      let host_id = stable_host_uuid(root, "host-id")
      match (server_id, workspace_id, host_id) {
        (Ok(server_id), Ok(workspace_id), Ok(host_id)) =>
          Ok({
            root,
            path: canonical,
            token,
            server_id,
            workspace_id,
            host_id,
            version: None,
            closed: false,
          })
        _ => {
          ignore(root.unlink_missing_ok("host.lock"))
          root.close()
          Err("cannot initialize native host identity")
        }
      }
    }
  }
}

///|
fn NativeStore::load(self : NativeStore) -> Result[NativeState, String] {
  match
    self.root.read_text_optional("sessions.json", max_bytes=SNAPSHOT_LIMIT) {
    Err(error) => return Err(error)
    Ok(None) => {
      self.version = None
      return Ok({
        engine: Json::null(),
        receipts: [],
        acp_sessions: [],
        server_id: self.server_id,
        workspace_id: self.workspace_id,
        identity_key: "local:" + @env.get_env_var("USER").unwrap_or("owner"),
        epoch: "",
        revision: 0,
        auth_revision: 0,
        external_mcp_catalog_hash: None,
        lsp_catalog_hash: None,
      })
    }
    Ok(Some((text, version))) => {
      self.version = Some(version)
      let raw = match parse_json(text) {
        Ok(value) => value
        Err(_) => return Err("native snapshot is not valid JSON")
      }
      match string_field(raw, "schema") {
        Some(schema) if schema == NATIVE_ENVELOPE_SCHEMA => {
          if int_field(raw, "format_version") != Some(1) {
            return Err("unsupported native snapshot format version")
          }
          let engine = match object_field(raw, "engine") {
            Some(value) => value
            None => return Err("native snapshot is missing engine state")
          }
          let receipts = match object_field(raw, "receipts") {
            Some(Json::Array(values)) => values
            _ => return Err("native snapshot is missing command receipts")
          }
          let external_mcp_catalog_hash = match
            object_field(raw, "external_mcp_catalog_hash") {
            None | Some(Json::Null) => None
            Some(Json::String(value)) if native_mcp_valid_fingerprint(value) =>
              Some(value)
            _ =>
              return Err(
                "native snapshot has an invalid external MCP catalog fingerprint",
              )
          }
          let lsp_catalog_hash = match object_field(raw, "lsp_catalog_hash") {
            None | Some(Json::Null) => None
            Some(Json::String(value)) if native_mcp_valid_fingerprint(value) =>
              Some(value)
            _ =>
              return Err(
                "native snapshot has an invalid LSP catalog fingerprint",
              )
          }
          let acp_sessions = match
            native_acp_stored_sessions_from_json(
              object_field(raw, "acp_sessions"),
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          Ok({
            engine,
            receipts,
            acp_sessions,
            server_id: string_field(raw, "server_id").unwrap_or(self.server_id),
            workspace_id: string_field(raw, "workspace_id").unwrap_or(
              self.workspace_id,
            ),
            identity_key: string_field(raw, "identity_key").unwrap_or(
              "local:owner",
            ),
            epoch: string_field(raw, "epoch").unwrap_or(""),
            revision: int_field(raw, "revision").unwrap_or(0),
            auth_revision: int_field(raw, "auth_revision").unwrap_or(0),
            external_mcp_catalog_hash,
            lsp_catalog_hash,
          })
        }
        Some("dsh.mbt-session-v1") | Some("deepseek-session-v4") =>
          Ok({
            engine: raw,
            receipts: [],
            acp_sessions: [],
            server_id: self.server_id,
            workspace_id: self.workspace_id,
            identity_key: "local:" + @env.get_env_var("USER").unwrap_or("owner"),
            epoch: "",
            revision: 0,
            auth_revision: 0,
            external_mcp_catalog_hash: None,
            lsp_catalog_hash: None,
          })
        _ => Err("native host cannot load this snapshot format")
      }
    }
  }
}

///|
fn NativeStore::save(
  self : NativeStore,
  state : NativeState,
) -> Result[Unit, String] {
  if self.closed {
    return Err("native persistence is closed")
  }
  let fields : Map[String, Json] = {
    "schema": Json::string(NATIVE_ENVELOPE_SCHEMA),
    "format_version": Json::number(1.0),
    "server_id": Json::string(state.server_id),
    "workspace_id": Json::string(state.workspace_id),
    "identity_key": Json::string(state.identity_key),
    "epoch": Json::string(state.epoch),
    "revision": Json::number(state.revision.to_double()),
    "auth_revision": Json::number(state.auth_revision.to_double()),
    "engine": state.engine,
    "receipts": Json::array(state.receipts),
    "acp_sessions": native_acp_stored_sessions_json(state.acp_sessions),
  }
  match state.external_mcp_catalog_hash {
    Some(value) => fields["external_mcp_catalog_hash"] = Json::string(value)
    None => ()
  }
  match state.lsp_catalog_hash {
    Some(value) => fields["lsp_catalog_hash"] = Json::string(value)
    None => ()
  }
  let value = Json::object(fields)
  let raw = value.stringify()
  if @utf8.encode(raw).length() > SNAPSHOT_LIMIT {
    return Err("native snapshot exceeds the 32 MiB persistence limit")
  }
  let write_result = match self.version {
    Some(version) =>
      self.root.write_atomic_bounded(
        "sessions.json",
        raw,
        SNAPSHOT_LIMIT,
        expected=version,
        permission=0o600,
      )
    None =>
      self.root.write_atomic_bounded(
        "sessions.json",
        raw,
        SNAPSHOT_LIMIT,
        permission=0o600,
      )
  }
  match write_result {
    Err(error) => Err("native checkpoint failed: " + error)
    Ok(_) =>
      match self.root.read_text("sessions.json", max_bytes=SNAPSHOT_LIMIT) {
        Err(error) =>
          Err(
            "native checkpoint committed but version verification failed: " +
            error,
          )
        Ok((_, version)) => {
          self.version = Some(version)
          Ok(())
        }
      }
  }
}

///|
fn NativeStore::close(self : NativeStore) -> Result[Unit, String] {
  if self.closed {
    return Ok(())
  }
  self.closed = true
  let lock = match NativeStore::read_lock(self.root) {
    Ok(value) => value
    Err(error) => {
      self.root.close()
      return Err(error)
    }
  }
  if string_field(lock, "token") != Some(self.token) {
    self.root.close()
    return Err(
      "host lock ownership changed; refusing to remove another owner's lock",
    )
  }
  let result = self.root.unlink("host.lock")
  self.root.close()
  result
}

///|
fn NativeStore::path(self : NativeStore) -> String {
  self.path
}

///|
fn NativeStore::host_id(self : NativeStore) -> String {
  "urn:uuid:" + self.host_id
}
