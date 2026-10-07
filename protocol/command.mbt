///|
/// A request is retried with the same command ID and identical payload after
/// an interrupted connection. The server scopes deduplication to its verified
/// principal and workspace, and computes the receipt fingerprint.
pub(all) struct RemoteCommand {
  protocol_version : Int
  workspace_id : String
  command_id : String
  session_id : String?
  operation : String
  input : Json
  approval_revision : Int?
}

///|
/// Parse a command sent to the v1 endpoint. The exact key set is required so
/// an older or newer client cannot accidentally omit an approval anchor or
/// smuggle host-only fields through the portable transport.
pub fn RemoteCommand::parse(raw : String) -> Result[RemoteCommand, String] {
  let root = parse_json(raw) catch { _ => return Err("invalid command JSON") }
  let fields = match root {
    Json::Object(fields) => fields
    _ => return Err("command must be an object")
  }
  if !has_exact_keys(fields, [
      "protocol_version", "workspace_id", "command_id", "session_id", "operation",
      "input", "approval_revision",
    ]) {
    return Err("command must contain exactly the v1 fields")
  }
  let protocol_version = int_field(root, "protocol_version")
  if protocol_version != PROTOCOL_VERSION {
    return Err("unsupported remote protocol version")
  }
  let workspace_id = string_field(root, "workspace_id")
  let command_id = string_field(root, "command_id")
  let operation = string_field(root, "operation")
  if workspace_id == "" || operation == "" || !is_uuid_v7_command_id(command_id) {
    return Err("command is missing a valid workspace, operation, or UUIDv7 ID")
  }
  let session_id = match optional_field(root, "session_id") {
    Some(Json::Null) => None
    Some(Json::String(value)) if value != "" => Some(value)
    _ => return Err("session_id must be a nonempty string or null")
  }
  let input = match optional_field(root, "input") {
    Some(value) => value
    None => return Err("command is missing its input")
  }
  let approval_revision = match optional_field(root, "approval_revision") {
    Some(Json::Null) => None
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => Some(number.to_int())
    _ => return Err("approval_revision must be a nonnegative integer or null")
  }
  Ok({
    protocol_version,
    workspace_id,
    command_id,
    session_id,
    operation,
    input,
    approval_revision,
  })
}

///|
/// True for a canonical UUID textual form using RFC 9562 version-7 and
/// variant bits. Timestamp freshness is checked separately at the HTTP edge.
pub fn is_uuid_v7_command_id(command_id : String) -> Bool {
  let chars = command_id.to_array()
  if chars.length() != 36 ||
    chars[8] != '-' ||
    chars[13] != '-' ||
    chars[18] != '-' ||
    chars[23] != '-' ||
    !lower_hex_range(chars, 0, 8) ||
    !lower_hex_range(chars, 9, 13) ||
    chars[14] != '7' ||
    !lower_hex_range(chars, 15, 18) ||
    !variant_char(chars[19]) ||
    !lower_hex_range(chars, 20, 23) ||
    !lower_hex_range(chars, 24, 36) {
    return false
  }
  true
}

///|
/// Extract the millisecond timestamp encoded by a UUIDv7 command ID.
pub fn uuid_v7_command_timestamp_ms(command_id : String) -> Int64? {
  if !is_uuid_v7_command_id(command_id) {
    return None
  }
  let chars = command_id.to_array()
  let mut timestamp = 0L
  for index in 0..<12 {
    let source_index = if index < 8 { index } else { index + 1 }
    let digit = hex_value(chars[source_index]).unwrap_or(0)
    timestamp = timestamp * 16L + digit.to_int64()
  }
  Some(timestamp)
}

///|
/// Reject command IDs outside the configured retry/receipt retention window.
/// The caller supplies clock time and bounds so transport tests are stable.
pub fn validate_uuid_v7_command_id_time(
  command_id : String,
  now_ms : Int64,
  max_age_ms : Int64,
  max_future_skew_ms : Int64,
) -> Bool {
  if now_ms < 0L || max_age_ms < 0L || max_future_skew_ms < 0L {
    return false
  }
  match uuid_v7_command_timestamp_ms(command_id) {
    None => false
    Some(timestamp) if timestamp > now_ms =>
      timestamp - now_ms <= max_future_skew_ms
    Some(timestamp) => now_ms - timestamp <= max_age_ms
  }
}

///|
/// Build a UUIDv7 ID from the supplied clock and 128 bits of host-generated
/// cryptographic entropy (32 hexadecimal digits). The portable package never
/// sources randomness itself; browser/native hosts inject platform CSPRNG bytes.
pub fn uuid_v7_command_id_from_entropy(
  now_ms : Int64,
  entropy_hex : String,
) -> Result[String, String] {
  let entropy = entropy_hex.to_array()
  if now_ms < 0L ||
    now_ms > 281474976710655L ||
    entropy.length() != 32 ||
    !hex_range(entropy, 0, 32) {
    return Err(
      "UUIDv7 needs a 48-bit timestamp and 128 hexadecimal entropy bits",
    )
  }
  let timestamp_chars : Array[Char] = []
  for _index in 0..<12 {
    timestamp_chars.push('0')
  }
  let mut timestamp = now_ms
  for index in 0..<12 {
    let digit = (timestamp % 16L).to_int()
    timestamp = timestamp / 16L
    timestamp_chars[11 - index] = hex_char(digit)
  }
  let timestamp_text = String::from_array(timestamp_chars)
  let rand_a = "7" + lowercase_hex(entropy, 0, 3)
  let variant = hex_char(8 + (hex_value(entropy[3]).unwrap_or(0) & 3))
  let rand_b = String::from_array([variant]) + lowercase_hex(entropy, 4, 19)
  let id = timestamp_text[0:8].to_owned() +
    "-" +
    timestamp_text[8:12].to_owned() +
    "-" +
    rand_a +
    "-" +
    rand_b[0:4].to_owned() +
    "-" +
    rand_b[4:].to_owned()
  if is_uuid_v7_command_id(id) {
    Ok(id)
  } else {
    Err("failed to construct UUIDv7 command ID")
  }
}

///|
/// Fingerprint input has fixed envelope fields and recursively sorted object
/// keys. Arrays keep their order. Both client and server call this function
/// before SHA-256, so JSON object construction order cannot change a receipt.
pub fn canonical_command_payload(command : RemoteCommand) -> String {
  let payload : Json = Json::object({
    "approval_revision": match command.approval_revision {
      Some(revision) => Json::number(revision.to_double())
      None => Json::null()
    },
    "input": command.input,
    "operation": Json::string(command.operation),
    "protocol_version": Json::number(command.protocol_version.to_double()),
    "session_id": match command.session_id {
      Some(session_id) => Json::string(session_id)
      None => Json::null()
    },
    "workspace_id": Json::string(command.workspace_id),
  })
  canonical_json(payload)
}

///|
fn canonical_json(value : Json) -> String {
  match value {
    Json::Array(items) => "[" + items.map(canonical_json).join(",") + "]"
    Json::Object(fields) => {
      let keys : Array[String] = []
      for key in fields.keys() {
        keys.push(key)
      }
      keys.sort_by((left, right) => lexical_string_compare(left, right))
      let members : Array[String] = []
      for key in keys {
        match fields.get(key) {
          Some(item) =>
            members.push(
              Json::string(key).stringify() + ":" + canonical_json(item),
            )
          None => ()
        }
      }
      "{" + members.join(",") + "}"
    }
    Json::Number(number, ..) => Json::number(number).stringify()
    _ => value.stringify()
  }
}

///|
pub fn RemoteCommand::json(self : RemoteCommand) -> Json {
  Json::object({
    "protocol_version": Json::number(self.protocol_version.to_double()),
    "workspace_id": Json::string(self.workspace_id),
    "command_id": Json::string(self.command_id),
    "session_id": match self.session_id {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "operation": Json::string(self.operation),
    "input": self.input,
    "approval_revision": match self.approval_revision {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
  })
}
