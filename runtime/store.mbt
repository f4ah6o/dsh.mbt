///|
/// Native persistence uses one versioned file for engine state, remote
/// receipts, and synchronization identity. A receipt can never commit apart
/// from the projection revision it acknowledges.
const NATIVE_ENVELOPE_SCHEMA : String = "dsh.native-host-v1"

///|
const SNAPSHOT_LIMIT : Int32 = 33554432

///|
const NATIVE_ARCHIVE_DIRECTORY : String = "tool-result-archives"

///|
const NATIVE_ARCHIVE_STORAGE_QUOTA : Int64 = 67108864L

///|
const NATIVE_ARCHIVE_INVENTORY_ENTRY_LIMIT : Int32 = 2048

///|
/// ACP owns only the sessions it creates. This adjunct registry records the
/// canonical startup workspace and last ACP prompt time without changing the
/// native engine event schema.
priv struct NativeAcpStoredSession {
  session_id : String
  cwd : String
  updated_at : String?
  model : String?
  route : String?
}

///|
/// Storage locator kept beside the compact engine manifest in the native
/// envelope. Names are random per publication; object IDs remain content
/// digests and are never treated as filesystem paths.
priv struct NativeArchiveLocator {
  object_id : String
  file_name : String
}

///|
priv struct NativeState {
  engine : Json
  archive_objects : Array[NativeArchiveLocator]
  archive_sources : Array[@engine.ToolResultArchiveSource]
  mut receipts : Array[Json]
  mut acp_sessions : Array[NativeAcpStoredSession]
  server_id : String
  workspace_id : String
  identity_key : String
  epoch : String
  revision : Int32
  auth_revision : Int32
  external_mcp_catalog_hash : String?
  lsp_catalog_hash : String?
}

///|
priv struct NativeStore {
  root : SafeRoot
  archive_root : SafeRoot
  path : String
  token : String
  server_id : String
  workspace_id : String
  host_id : String
  mut version : FileVersion?
  mut closed : Bool
}

///|
fn native_archive_bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn native_archive_reservation_allowed(
  stored_bytes : Int64,
  entry_count : Int32,
  object_bytes : Int32,
) -> Bool {
  stored_bytes >= 0L &&
  entry_count >= 0 &&
  object_bytes > 0 &&
  object_bytes <= 1048576 &&
  stored_bytes + object_bytes.to_int64() * 2L <= NATIVE_ARCHIVE_STORAGE_QUOTA &&
  entry_count + 2 <= NATIVE_ARCHIVE_INVENTORY_ENTRY_LIMIT
}

///|
/// Inventory every name before reading object contents. Strict listing rejects
/// symlinks and special files; directories are rejected by the archive layout.
fn NativeStore::archive_inventory(
  self : NativeStore,
) -> Result[(Int64, Int32), String] {
  let entries = match self.archive_root.list_directory_strict(".") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if entries.length() > NATIVE_ARCHIVE_INVENTORY_ENTRY_LIMIT {
    return Err("archive storage inventory exceeds its entry limit")
  }
  let mut total_bytes = 0L
  for (name, kind) in entries {
    if kind != "file" {
      return Err("archive storage contains an unsupported directory entry")
    }
    let version = match self.archive_root.file_version(name) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if version.owner_uid() != os_uid() || version.permission() != 0o600 {
      return Err("archive object or temporary file has unsafe permissions")
    }
    total_bytes += version.size()
    if total_bytes > NATIVE_ARCHIVE_STORAGE_QUOTA {
      return Err("archive storage exceeds its protected 64 MiB quota")
    }
  }
  Ok((total_bytes, entries.length()))
}

///|
/// Reserve the worst-case temporary plus final directory entries for a whole
/// candidate batch before publishing its first object. Per-object publication
/// repeats its inventory check to fail closed if the directory changes.
fn NativeStore::check_archive_batch_reservation(
  self : NativeStore,
  objects : Array[NativeToolResultArchiveObject],
) -> Result[Unit, String] {
  let (stored_bytes, entry_count) = match self.archive_inventory() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut reserved_bytes = 0L
  let mut reserved_entries = 0
  for object in objects {
    let object_bytes = @utf8.encode(object.encoded_object()).length()
    if object_bytes <= 0 || object_bytes > 1048576 {
      return Err("archive object exceeds its encoded 1 MiB bound")
    }
    reserved_bytes += object_bytes.to_int64() * 2L
    reserved_entries += 2
    if stored_bytes + reserved_bytes > NATIVE_ARCHIVE_STORAGE_QUOTA ||
      entry_count + reserved_entries > NATIVE_ARCHIVE_INVENTORY_ENTRY_LIMIT {
      return Err("archive batch exceeds the protected storage quota")
    }
  }
  Ok(())
}

///|
/// Publish one verified immutable object under a fresh random storage name.
/// Only a successful no-replace call is KnownSuccess. Name collisions and
/// ambiguous publication outcomes are errors and are never adopted.
fn NativeStore::publish_archive_object_with(
  self : NativeStore,
  object : NativeToolResultArchiveObject,
  file_name : String,
  create : (SafeRoot, String, String, Int32) -> Result[
    Unit,
    AtomicCreateNoReplaceError,
  ],
) -> Result[NativeArchiveLocator, String] {
  let reference = object.reference()
  let raw = object.encoded_object()
  let verified = match NativeToolResultArchiveObject::verify(raw, reference) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if verified.original_content() != object.original_content() ||
    verified.pruned_content() != object.pruned_content() {
    return Err("archive object changed before immutable publication")
  }
  let raw_bytes = @utf8.encode(raw)
  if raw_bytes.length() <= 0 || raw_bytes.length() > 1048576 {
    return Err("archive object exceeds its encoded 1 MiB bound")
  }
  let (stored_bytes, entry_count) = match self.archive_inventory() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  // Reserve the temporary and final names even on filesystems where atomic
  // publication briefly exposes both directory entries.
  if !native_archive_reservation_allowed(
      stored_bytes,
      entry_count,
      raw_bytes.length(),
    ) {
    return Err("archive object exceeds the protected storage quota")
  }
  if !native_archive_locator_name_valid(file_name) {
    return Err("archive storage filename is invalid")
  }
  match create(self.archive_root, file_name, raw, 1048576) {
    Err(AtomicCreateNoReplaceError::Exists) =>
      return Err("archive object storage name collided; refusing to adopt it")
    Err(AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
      return Err("archive object publication outcome is unknown: " + error)
    Err(AtomicCreateNoReplaceError::Failed(error)) =>
      return Err("archive object publication failed: " + error)
    Ok(_) => ()
  }
  let (published_bytes, version) = match
    self.archive_root.read_bytes(file_name, max_bytes=1048576) {
    Ok(value) => value
    Err(error) =>
      return Err("published archive object cannot be verified: " + error)
  }
  if !native_archive_bytes_equal(published_bytes, raw_bytes) ||
    version.owner_uid() != os_uid() ||
    version.permission() != 0o600 {
    return Err("published archive object differs from its verified bytes")
  }
  let (final_bytes, _) = match self.archive_inventory() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if final_bytes > NATIVE_ARCHIVE_STORAGE_QUOTA {
    return Err("archive publication exceeded the protected storage quota")
  }
  Ok({ object_id: reference.object_id(), file_name, })
}

///|
fn NativeStore::publish_archive_object(
  self : NativeStore,
  object : NativeToolResultArchiveObject,
  file_name : String,
) -> Result[NativeArchiveLocator, String] {
  self.publish_archive_object_with(object, file_name, (
    root,
    name,
    raw,
    max_bytes,
  ) => root.create_atomic_no_replace(name, raw, max_bytes, permission=0o600))
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
fn int_field(value : Json, name : String) -> Int32? {
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
fn json_int(value : Json?) -> Int32 {
  match value {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ => -1
  }
}

///|
fn native_acp_timestamp_digit(character : Char) -> Int32 {
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
    let model = match object_field(entry, "model") {
      None | Some(Json::Null) => None
      Some(Json::String(value)) if !value.is_empty() && value.length() <= 256 =>
        Some(value)
      _ => return Err("native snapshot has an invalid ACP session model")
    }
    let route = match object_field(entry, "route") {
      None | Some(Json::Null) => None
      Some(Json::String(value)) if !value.is_empty() && value.length() <= 64 =>
        Some(value)
      _ =>
        return Err("native snapshot has an invalid ACP session provider route")
    }
    if model is Some(_) && route is None {
      return Err("native snapshot has an ACP model without its provider route")
    }
    seen.set(session_id, true)
    result.push({ session_id, cwd, updated_at, model, route, })
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
      match session.model {
        Some(value) => fields["model"] = Json::string(value)
        None => ()
      }
      match session.route {
        Some(value) => fields["route"] = Json::string(value)
        None => ()
      }
      Json::object(fields)
    }),
  )
}

///|
fn native_archive_locators_json(locators : Array[NativeArchiveLocator]) -> Json {
  Json::array(
    locators.map(locator => {
      Json::object({
        "object_id": Json::string(locator.object_id),
        "file_name": Json::string(locator.file_name),
      })
    }),
  )
}

///|
fn native_archive_snapshot_refs(
  engine_snapshot : Json,
) -> Result[Array[@engine.ToolResultArchiveRef], String] {
  let raw_refs = match object_field(engine_snapshot, "archives") {
    None => return Ok([])
    Some(Json::Array(values)) if values.length() <= 256 => values
    _ => return Err("engine archive manifest has an invalid shape")
  }
  let refs : Array[@engine.ToolResultArchiveRef] = []
  let seen : Map[String, Bool] = Map([])
  for raw in raw_refs {
    let reference = match @engine.ToolResultArchiveRef::from_json(raw) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let object_id = reference.object_id()
    if seen.get(object_id) is Some(_) {
      return Err("engine archive manifest contains a duplicate object id")
    }
    seen.set(object_id, true)
    refs.push(reference)
  }
  Ok(refs)
}

///|
fn native_archive_locator_name_valid(value : String) -> Bool {
  if value.length() != 53 || !value.has_suffix(".json") {
    return false
  }
  let stem = value[:48].to_owned()
  for character in stem {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return false
    }
  }
  true
}

///|
fn native_archive_hex_digest_valid(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for character in value {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return false
    }
  }
  true
}

///|
fn native_archive_locator_array(
  value : Json?,
) -> Result[Array[NativeArchiveLocator], String] {
  let entries = match value {
    Some(Json::Array(values)) if values.length() <= 256 => values
    _ => return Err("native snapshot has an invalid archive object map")
  }
  let result : Array[NativeArchiveLocator] = []
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for entry in entries {
    match entry {
      Json::Object(fields) if fields.length() == 2 => ()
      _ => return Err("native snapshot has an invalid archive locator")
    }
    let object_id = match string_field(entry, "object_id") {
      Some(value) if native_archive_hex_digest_valid(value) => value
      _ => return Err("native snapshot has an invalid archive object id")
    }
    let file_name = match string_field(entry, "file_name") {
      Some(value) if native_archive_locator_name_valid(value) => value
      _ => return Err("native snapshot has an invalid archive object filename")
    }
    if ids.get(object_id) is Some(_) || names.get(file_name) is Some(_) {
      return Err("native snapshot has a duplicate archive locator")
    }
    ids.set(object_id, true)
    names.set(file_name, true)
    result.push({ object_id, file_name, })
  }
  Ok(result)
}

///|
fn native_archive_validate_coverage(
  engine_snapshot : Json,
  locators : Array[NativeArchiveLocator],
  sources : Array[@engine.ToolResultArchiveSource],
) -> Result[Unit, String] {
  let refs = match native_archive_snapshot_refs(engine_snapshot) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match native_archive_manifest_within_limits(refs) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if refs.length() != locators.length() || refs.length() != sources.length() {
    return Err("archive manifest, storage map, and verified sources differ")
  }
  let reference_ids : Map[String, Json] = Map([])
  for reference in refs {
    reference_ids.set(reference.object_id(), reference.json())
  }
  let locator_ids : Map[String, Bool] = Map([])
  for locator in locators {
    if reference_ids.get(locator.object_id) is None ||
      locator_ids.get(locator.object_id) is Some(_) {
      return Err("archive storage map has an unreferenced or duplicate object")
    }
    if !native_archive_locator_name_valid(locator.file_name) {
      return Err("archive storage map has an invalid object filename")
    }
    locator_ids.set(locator.object_id, true)
  }
  let source_ids : Map[String, Bool] = Map([])
  for source in sources {
    let object_id = source.reference().object_id()
    let expected_reference = match reference_ids.get(object_id) {
      Some(value) => value
      None =>
        return Err("verified archive sources have missing or duplicate objects")
    }
    if expected_reference != source.reference().json() ||
      source_ids.get(object_id) is Some(_) {
      return Err("verified archive sources have missing or duplicate objects")
    }
    source_ids.set(object_id, true)
  }
  Ok(())
}

///|
fn native_archive_manifest_within_limits(
  refs : Array[@engine.ToolResultArchiveRef],
) -> Result[Unit, String] {
  if refs.length() > 256 {
    return Err("archive manifest exceeds its 256 object limit")
  }
  let mut original_bytes = 0
  let mut projection_bytes = 0
  let mut hydration_expansion = 0
  for reference in refs {
    let raw = reference.json()
    let content_bytes = match int_field(raw, "content_bytes") {
      Some(value) => value
      None => return Err("archive reference has no validated content size")
    }
    let pruned_bytes = match int_field(raw, "pruned_bytes") {
      Some(value) => value
      None => return Err("archive reference has no validated projection size")
    }
    original_bytes += content_bytes
    projection_bytes += pruned_bytes
    hydration_expansion += Int32::max(content_bytes - pruned_bytes, 0) * 3
    if original_bytes > 16777216 || projection_bytes > 16777216 {
      return Err("archive manifest exceeds its 16 MiB content quota")
    }
    if hydration_expansion > 7340032 {
      return Err("archive manifest exceeds its 7 MiB hydration budget")
    }
    if (content_bytes + pruned_bytes) * 6 + 8192 > 1048576 {
      return Err("archive reference exceeds its encoded object bound")
    }
  }
  Ok(())
}

///|
fn random_hex(byte_count : Int32) -> Result[String, String] {
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
fn host_id_char(value : String, index : Int32) -> Char {
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
      "data directory is locked; recorded owner: host " +
      previous_host +
      " (pid " +
      previous_pid.to_string() +
      "). Verify and stop the owning dsh instance on that host before retrying, or use --data-dir PATH for a separate instance. " +
      "The lock was left unchanged because its owner cannot be confirmed dead.",
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
  let absolute = if native_path_is_absolute(data_dir) {
    native_path_normalize(data_dir)
  } else {
    match @env.current_dir() {
      Some(current) => native_path_normalize(current + "/" + data_dir)
      None => return Err("cannot determine current directory")
    }
  }
  @fs.mkdir(absolute, permission=0o700, recursive=true, allow_exist=true) catch {
    _ => return Err("cannot create native data directory")
  }
  let canonical = native_path_normalize(
    @fs.realpath(absolute) catch {
      _ => return Err("cannot resolve native data directory")
    },
  )
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
  let archive_path = canonical + "/" + NATIVE_ARCHIVE_DIRECTORY
  @fs.mkdir(archive_path, permission=0o700, recursive=false, allow_exist=true) catch {
    _ => {
      root.close()
      return Err("cannot create native archive object directory")
    }
  }
  let archive_root = match SafeRoot::open(archive_path) {
    Ok(value) => value
    Err(error) => {
      root.close()
      return Err("cannot open native archive object directory: " + error)
    }
  }
  match archive_root.restrict_owner_only() {
    Ok(_) => ()
    Err(error) => {
      archive_root.close()
      root.close()
      return Err(error)
    }
  }
  let token = match random_hex(24) {
    Ok(value) => value
    Err(error) => {
      archive_root.close()
      root.close()
      return Err(error)
    }
  }
  let hostname = match os_hostname() {
    Ok(value) => value
    Err(error) => {
      archive_root.close()
      root.close()
      return Err(error)
    }
  }
  match NativeStore::acquire(root, token, hostname) {
    Err(error) => {
      archive_root.close()
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
            archive_root,
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
          archive_root.close()
          root.close()
          Err("cannot initialize native host identity")
        }
      }
    }
  }
}

///|
fn native_archive_find_locator(
  locators : Array[NativeArchiveLocator],
  object_id : String,
) -> NativeArchiveLocator? {
  for locator in locators {
    if locator.object_id == object_id {
      return Some(locator)
    }
  }
  None
}

///|
fn NativeStore::load_archive_sources(
  self : NativeStore,
  engine_snapshot : Json,
  locators : Array[NativeArchiveLocator],
) -> Result[Array[@engine.ToolResultArchiveSource], String] {
  match self.archive_inventory() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let refs = match native_archive_snapshot_refs(engine_snapshot) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if refs.is_empty() || refs.length() != locators.length() {
    return Err("v2 archive manifest and storage map have different coverage")
  }
  match native_archive_manifest_within_limits(refs) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let seen_names : Map[String, Bool] = Map([])
  let sources : Array[@engine.ToolResultArchiveSource] = []
  for reference in refs {
    let locator = match
      native_archive_find_locator(locators, reference.object_id()) {
      Some(value) => value
      None => return Err("archive manifest references a missing object locator")
    }
    if seen_names.get(locator.file_name) is Some(_) {
      return Err("archive storage map reuses one object filename")
    }
    seen_names.set(locator.file_name, true)
    let version = match self.archive_root.file_version(locator.file_name) {
      Ok(value) => value
      Err(error) => return Err("archive object is missing or unsafe: " + error)
    }
    if version.size() <= 0L || version.size() > 1048576L {
      return Err("archive object exceeds its 1 MiB encoded byte limit")
    }
    if version.owner_uid() != os_uid() || version.permission() != 0o600 {
      return Err("archive object has unsafe ownership or permissions")
    }
    let (raw_bytes, observed) = match
      self.archive_root.read_bytes(locator.file_name, max_bytes=1048576) {
      Ok(value) => value
      Err(error) => return Err("cannot read archive object: " + error)
    }
    if !version.same(observed) {
      return Err("archive object changed between inventory and read")
    }
    let raw = @utf8.decode(raw_bytes) catch {
      _ => return Err("archive object bytes are not valid UTF-8")
    }
    if !native_archive_bytes_equal(raw_bytes, @utf8.encode(raw)) {
      return Err("archive object bytes do not round-trip through UTF-8")
    }
    let native_reference = match
      NativeToolResultArchiveRef::from_json(reference.json()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let object = match
      NativeToolResultArchiveObject::verify(raw, native_reference) {
      Ok(value) => value
      Err(error) => return Err("archive object failed validation: " + error)
    }
    if object.reference().object_id() != locator.object_id {
      return Err("archive object id differs from its storage locator")
    }
    let source = match
      @engine.ToolResultArchiveSource::from_object_text(reference, raw) {
      Ok(value) => value
      Err(error) =>
        return Err("archive object source failed validation: " + error)
    }
    sources.push(source)
  }
  match native_archive_validate_coverage(engine_snapshot, locators, sources) {
    Ok(_) => Ok(sources)
    Err(error) => Err(error)
  }
}

///|
/// Read one original on explicit history access. This rechecks the immutable
/// bytes and metadata from disk; a previously loaded source is not sufficient
/// evidence if the file has since changed or disappeared.
fn NativeStore::read_archive_object(
  self : NativeStore,
  locator : NativeArchiveLocator,
  reference : NativeToolResultArchiveRef,
) -> Result[NativeToolResultArchiveObject, String] {
  if locator.object_id != reference.object_id() ||
    !native_archive_locator_name_valid(locator.file_name) {
    return Err("archive locator does not match the requested reference")
  }
  match self.archive_inventory() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let before = match self.archive_root.file_version(locator.file_name) {
    Ok(value) => value
    Err(error) => return Err("archive object is missing or unsafe: " + error)
  }
  if before.size() <= 0L ||
    before.size() > 1048576L ||
    before.owner_uid() != os_uid() ||
    before.permission() != 0o600 {
    return Err("archive object has invalid size, ownership, or permissions")
  }
  let (raw_bytes, observed) = match
    self.archive_root.read_bytes(locator.file_name, max_bytes=1048576) {
    Ok(value) => value
    Err(error) => return Err("cannot read archive object: " + error)
  }
  if !before.same(observed) {
    return Err("archive object changed while being retrieved")
  }
  let raw = @utf8.decode(raw_bytes) catch {
    _ => return Err("archive object bytes are not valid UTF-8")
  }
  if !native_archive_bytes_equal(raw_bytes, @utf8.encode(raw)) {
    return Err("archive object bytes do not round-trip through UTF-8")
  }
  match NativeToolResultArchiveObject::verify(raw, reference) {
    Ok(value) => Ok(value)
    Err(error) => Err("archive object failed validation: " + error)
  }
}

///|
fn NativeStore::load(self : NativeStore) -> Result[NativeState, String] {
  match self.archive_inventory() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    self.root.read_text_optional("sessions.json", max_bytes=SNAPSHOT_LIMIT) {
    Err(error) => return Err(error)
    Ok(None) => {
      self.version = None
      return Ok({
        engine: Json::null(),
        archive_objects: [],
        archive_sources: [],
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
          let format_version = int_field(raw, "format_version")
          if format_version != Some(1) && format_version != Some(2) {
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
          let (archive_objects, archive_sources) = match format_version {
            Some(1) => {
              if object_field(raw, "archive_objects") is Some(_) {
                return Err("native v1 snapshot cannot contain archive locators")
              }
              let refs = match native_archive_snapshot_refs(engine) {
                Ok(value) => value
                Err(error) => return Err(error)
              }
              if !refs.is_empty() {
                return Err("native v1 snapshot cannot restore archived history")
              }
              ([], [])
            }
            Some(2) => {
              let locators = match
                native_archive_locator_array(
                  object_field(raw, "archive_objects"),
                ) {
                Ok(value) => value
                Err(error) => return Err(error)
              }
              let sources = match self.load_archive_sources(engine, locators) {
                Ok(value) => value
                Err(error) => return Err(error)
              }
              (locators, sources)
            }
            _ => return Err("unsupported native snapshot format version")
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
            archive_objects,
            archive_sources,
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
        Some("dsh.mbt-session-v1") | Some("deepseek-session-v4") => {
          let refs = match native_archive_snapshot_refs(raw) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          if !refs.is_empty() {
            return Err(
              "legacy native snapshots cannot restore archived history",
            )
          }
          Ok({
            engine: raw,
            archive_objects: [],
            archive_sources: [],
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
        _ => Err("native host cannot load this snapshot format")
      }
    }
  }
}

///|
fn native_store_encode_state(state : NativeState) -> Result[String, String] {
  match
    native_archive_validate_coverage(
      state.engine,
      state.archive_objects,
      state.archive_sources,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let fields : Map[String, Json] = {
    "schema": Json::string(NATIVE_ENVELOPE_SCHEMA),
    "format_version": Json::number(
      if state.archive_objects.is_empty() {
        1.0
      } else {
        2.0
      },
    ),
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
  if !state.archive_objects.is_empty() {
    fields["archive_objects"] = native_archive_locators_json(
      state.archive_objects,
    )
  }
  let value = Json::object(fields)
  let raw = value.stringify()
  if @utf8.encode(raw).length() > SNAPSHOT_LIMIT {
    return Err("native snapshot exceeds the 32 MiB persistence limit")
  }
  Ok(raw)
}

///|
/// Validate the exact final envelope before publishing immutable archive
/// objects. Save repeats this validation immediately before the CAS.
fn NativeStore::admit_state(
  self : NativeStore,
  state : NativeState,
) -> Result[Unit, String] {
  if self.closed {
    return Err("native persistence is closed")
  }
  match native_store_encode_state(state) {
    Ok(_) => Ok(())
    Err(error) => Err(error)
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
  let raw = match native_store_encode_state(state) {
    Ok(value) => value
    Err(error) => return Err(error)
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
      self.archive_root.close()
      self.root.close()
      return Err(error)
    }
  }
  if string_field(lock, "token") != Some(self.token) {
    self.archive_root.close()
    self.root.close()
    return Err(
      "host lock ownership changed; refusing to remove another owner's lock",
    )
  }
  let result = self.root.unlink("host.lock")
  self.archive_root.close()
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
