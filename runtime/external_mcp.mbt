///|
const NATIVE_EXTERNAL_MCP_CONFIG_LIMIT : Int = 1048576

///|
const NATIVE_EXTERNAL_MCP_MAX_SERVERS : Int = 8

///|
const NATIVE_EXTERNAL_MCP_MAX_TOOLS : Int = 64

///|
const NATIVE_EXTERNAL_MCP_MAX_PAGES : Int = 16

///|
const NATIVE_EXTERNAL_MCP_STARTUP_TIMEOUT_MS : Int = 10000

///|
const NATIVE_EXTERNAL_MCP_DEFAULT_TOOL_TIMEOUT_MS : Int = 60000

///|
const NATIVE_EXTERNAL_MCP_MAX_NOTIFICATIONS : Int = 64

///|

///|
const NATIVE_EXTERNAL_MCP_CATALOG_LIMIT : Int = 1048576

///|
priv struct NativeMcpServerConfig {
  name : String
  command : String
  args : Array[String]
  cwd : String?
  env : Array[(String, String)]
  tool_timeout_ms : Int
}

///|
priv struct NativeMcpTool {
  name : String
  server_name : String
  raw_name : String
  description : String
  input_schema : Json
}

///|
priv struct NativeMcpRoute {
  server_index : Int
  raw_name : String
}

///|
priv struct NativeMcpRpcResponse {
  result : Json?
  remote_error : Bool
}

///|
priv struct NativeMcpServer {
  name : String
  tool_timeout_ms : Int
  pid : Int
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  gate : @async.Mutex
  close_gate : @async.Mutex
  framer : NativeMcpFramer
  mut queued_frames : Array[NativeMcpFrame]
  mut next_id : Int
  mut poisoned : Bool
  mut closed : Bool
}

///|
priv struct NativeMcpPool {
  servers : Array[NativeMcpServer]
  descriptors : Array[Json]
  routes : Map[String, NativeMcpRoute]
  catalog_hash : String?
  mut closed : Bool
}

///|
fn native_mcp_catalog_capacity(existing : Int, incoming : Int) -> Bool {
  existing >= 0 &&
  incoming >= 0 &&
  existing + incoming <= NATIVE_EXTERNAL_MCP_MAX_TOOLS
}

///|
priv struct NativeMcpSchemaBudget {
  mut nodes : Int
  mut chars : Int
}

///|
fn native_mcp_json_object(value : Json) -> Map[String, Json]? {
  match value {
    Json::Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn native_mcp_json_string(value : Json?) -> String? {
  match value {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|

///|
fn native_mcp_valid_env_name(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  let mut index = 0
  for character in value {
    let valid = if index == 0 {
      (character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      character == '_'
    } else {
      (character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_'
    }
    if !valid {
      return false
    }
    index += 1
  }
  true
}

///|
fn native_mcp_valid_server_name(value : String) -> Bool {
  if value.is_empty() || value.length() > 32 {
    return false
  }
  for character in value {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-') {
      return false
    }
  }
  true
}

///|
fn native_mcp_config_string(
  value : Json,
  key : String,
  required : Bool,
) -> Result[String?, String] {
  match native_mcp_json_object(value) {
    None => Err("external MCP server config must be an object")
    Some(fields) =>
      match fields.get(key) {
        Some(Json::String(text)) if !text.contains("\u0000") => Ok(Some(text))
        Some(_) => Err("external MCP config field must be a string: " + key)
        None if required => Err("external MCP config is missing: " + key)
        None => Ok(None)
      }
  }
}

///|
fn native_mcp_parse_server_config(
  value : Json,
) -> Result[NativeMcpServerConfig, String] {
  let fields = match native_mcp_json_object(value) {
    Some(fields) => fields
    None => return Err("external MCP server config must be an object")
  }
  for key, _ in fields {
    if !["name", "command", "args", "cwd", "env", "toolCallTimeoutMs"].contains(
        key,
      ) {
      return Err("unknown external MCP server config field: " + key)
    }
  }
  let name = match native_mcp_config_string(value, "name", true) {
    Ok(Some(value)) if native_mcp_valid_server_name(value) => value
    _ =>
      return Err(
        "external MCP server name must use 1..32 letters, digits, _ or -",
      )
  }
  let command = match native_mcp_config_string(value, "command", true) {
    Ok(Some(value)) if !value.trim().is_empty() && value.length() <= 4096 =>
      value
    _ =>
      return Err(
        "external MCP server command must be a nonempty string of at most 4096 characters",
      )
  }
  let cwd = match native_mcp_config_string(value, "cwd", false) {
    Ok(Some(value)) if !value.is_empty() && value.length() <= 4096 =>
      Some(value)
    Ok(None) => None
    _ =>
      return Err(
        "external MCP server cwd must be a nonempty string of at most 4096 characters",
      )
  }
  let tool_timeout_ms = match fields.get("toolCallTimeoutMs") {
    None => NATIVE_EXTERNAL_MCP_DEFAULT_TOOL_TIMEOUT_MS
    Some(Json::Number(number, ..)) if number >= 100.0 &&
      number <= 300000.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ =>
      return Err(
        "external MCP toolCallTimeoutMs must be an integer between 100 and 300000",
      )
  }
  let args = match fields.get("args") {
    None => []
    Some(Json::Array(values)) if values.length() <= 256 => {
      let result : Array[String] = []
      let mut total_bytes = 0
      for value in values {
        match value {
          Json::String(argument) if !argument.contains("\u0000") &&
            argument.length() <= 4096 => {
            total_bytes += @utf8.encode(argument).length()
            if total_bytes > 65536 {
              return Err(
                "external MCP server args exceed the 64 KiB config limit",
              )
            }
            result.push(argument)
          }
          _ =>
            return Err("external MCP server args must be strings without NUL")
        }
      }
      result
    }
    Some(_) =>
      return Err(
        "external MCP server args must be an array of at most 256 strings",
      )
  }
  let env = match fields.get("env") {
    None => []
    Some(Json::Object(entries)) if entries.length() <= 64 => {
      let result : Array[(String, String)] = []
      for target, source in entries {
        if !native_mcp_valid_env_name(target) {
          return Err(
            "external MCP child environment names must be valid variable names",
          )
        }
        match source {
          Json::String(source_name) if native_mcp_valid_env_name(source_name) =>
            result.push((target, source_name))
          _ =>
            return Err(
              "external MCP env values must name host environment variables",
            )
        }
      }
      result
    }
    Some(_) =>
      return Err("external MCP env must be an object with at most 64 entries")
  }
  Ok({ name, command, args, cwd, env, tool_timeout_ms, })
}

///|
async fn native_mcp_read_config(
  path : String,
) -> Result[Array[NativeMcpServerConfig], String] {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch {
    _ => return Err("cannot read external MCP config")
  }
  defer file.close()
  if file.kind() != @fs.Regular {
    return Err("external MCP config must be a regular file")
  }
  let size = file.size() catch {
    _ => return Err("cannot determine external MCP config size")
  }
  if size < 0L || size > NATIVE_EXTERNAL_MCP_CONFIG_LIMIT.to_int64() {
    return Err("external MCP config exceeds the 1 MiB limit")
  }
  let bytes : Array[Byte] = []
  while true {
    let chunk = file.read_some(max_len=8192) catch {
      _ => return Err("cannot read external MCP config")
    }
    match chunk {
      None => break
      Some(chunk) =>
        for byte in chunk {
          if bytes.length() >= NATIVE_EXTERNAL_MCP_CONFIG_LIMIT {
            return Err("external MCP config exceeds the 1 MiB limit")
          }
          bytes.push(byte)
        }
    }
  }
  let text = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("external MCP config is not valid UTF-8")
  }
  let document = @json.parse(text) catch {
    _ => return Err("external MCP config is not valid JSON")
  }
  let root = match native_mcp_json_object(document) {
    Some(fields) => fields
    None => return Err("external MCP config must be a JSON object")
  }
  for key, _ in root {
    if key != "servers" {
      return Err("unknown external MCP config field: " + key)
    }
  }
  let values = match root.get("servers") {
    Some(Json::Array(values)) if values.length() <=
      NATIVE_EXTERNAL_MCP_MAX_SERVERS => values
    _ =>
      return Err(
        "external MCP config servers must be an array of at most 8 entries",
      )
  }
  let result : Array[NativeMcpServerConfig] = []
  let names : Map[String, Bool] = Map([])
  for value in values {
    let config = match native_mcp_parse_server_config(value) {
      Ok(config) => config
      Err(error) => return Err(error)
    }
    if names.get(config.name) is Some(_) {
      return Err("external MCP server names must be unique")
    }
    names[config.name] = true
    result.push(config)
  }
  Ok(result)
}

///|
fn native_mcp_annotation_key(key : String) -> Bool {
  [
    "$schema", "$id", "title", "description", "default", "examples", "deprecated",
    "readOnly", "writeOnly",
  ].contains(key)
}

///|
fn native_mcp_normalize_schema(
  schema : Json,
  depth : Int,
  budget : NativeMcpSchemaBudget,
) -> Result[Json, String] {
  if depth > 24 {
    return Err("external MCP input schema exceeds the 24-level depth limit")
  }
  budget.nodes -= 1
  if budget.nodes < 0 {
    return Err("external MCP input schema exceeds its node limit")
  }
  let fields = match native_mcp_json_object(schema) {
    Some(fields) => fields
    None => return Err("external MCP input schema must be a JSON object")
  }
  let normalized : Map[String, Json] = Map([])
  for key, value in fields {
    budget.chars -= key.length()
    if budget.chars < 0 {
      return Err("external MCP input schema exceeds its text limit")
    }
    if ![
        "type", "properties", "required", "additionalProperties", "items", "enum",
      ].contains(key) &&
      !native_mcp_annotation_key(key) {
      return Err(
        "external MCP input schema uses an unsupported JSON Schema keyword",
      )
    }
    match key {
      "type" =>
        match value {
          Json::String(kind) =>
            if [
                "object", "array", "string", "integer", "number", "boolean", "null",
              ].contains(kind) {
              budget.nodes -= 1
              budget.chars -= kind.length()
              if budget.nodes < 0 || budget.chars < 0 {
                return Err("external MCP input schema exceeds its budget")
              }
              normalized[key] = value
            } else {
              return Err("external MCP input schema has an unsupported type")
            }
          _ => return Err("external MCP input schema type must be a string")
        }
      "properties" =>
        match native_mcp_json_object(value) {
          Some(properties) if properties.length() <= 128 => {
            budget.nodes -= 1
            if budget.nodes < 0 {
              return Err("external MCP input schema exceeds its node limit")
            }
            let next : Map[String, Json] = Map([])
            for property_name, property_schema in properties {
              if property_name.length() > 128 {
                return Err("external MCP schema property name is too long")
              }
              budget.chars -= property_name.length()
              if budget.chars < 0 {
                return Err("external MCP input schema exceeds its text limit")
              }
              next[property_name] = match
                native_mcp_normalize_schema(property_schema, depth + 1, budget) {
                Ok(value) => value
                Err(error) => return Err(error)
              }
            }
            normalized[key] = Json::object(next)
          }
          _ =>
            return Err(
              "external MCP input schema properties must be an object of at most 128 fields",
            )
        }
      "required" =>
        match value {
          Json::Array(required) if required.length() <= 128 => {
            budget.nodes -= 1
            if budget.nodes < 0 {
              return Err("external MCP input schema exceeds its node limit")
            }
            let next : Array[Json] = []
            let seen : Map[String, Bool] = Map([])
            for name in required {
              match name {
                Json::String(text) if text.length() <= 128 => {
                  budget.nodes -= 1
                  budget.chars -= text.length()
                  if budget.nodes < 0 || budget.chars < 0 {
                    return Err("external MCP input schema exceeds its budget")
                  }
                  if seen.get(text) is Some(_) {
                    return Err(
                      "external MCP input schema required list has duplicates",
                    )
                  }
                  seen[text] = true
                  next.push(name)
                }
                _ =>
                  return Err(
                    "external MCP input schema required entries must be strings",
                  )
              }
            }
            normalized[key] = Json::array(next)
          }
          _ =>
            return Err(
              "external MCP input schema required must be an array of at most 128 strings",
            )
        }
      "additionalProperties" =>
        match value {
          Json::True | Json::False => {
            budget.nodes -= 1
            if budget.nodes < 0 {
              return Err("external MCP input schema exceeds its node limit")
            }
            normalized[key] = value
          }
          _ =>
            return Err(
              "external MCP input schema additionalProperties must be boolean",
            )
        }
      "items" =>
        normalized[key] = match
          native_mcp_normalize_schema(value, depth + 1, budget) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      "enum" =>
        match value {
          Json::Array(items) if items.length() > 0 && items.length() <= 256 => {
            let copied : Array[Json] = []
            for item in items {
              copied.push(
                match native_mcp_copy_bounded_json(item, depth + 1, budget) {
                  Ok(value) => value
                  Err(error) => return Err(error)
                },
              )
            }
            normalized[key] = Json::array(copied)
          }
          _ =>
            return Err(
              "external MCP input schema enum must contain 1..256 values",
            )
        }
      _ =>
        normalized[key] = match
          native_mcp_copy_bounded_json(value, depth + 1, budget) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
    }
  }
  Ok(Json::object(normalized))
}

///|
fn native_mcp_copy_bounded_json(
  value : Json,
  depth : Int,
  budget : NativeMcpSchemaBudget,
) -> Result[Json, String] {
  if depth > 24 {
    return Err("external MCP schema annotation exceeds the depth limit")
  }
  budget.nodes -= 1
  if budget.nodes < 0 {
    return Err("external MCP input schema exceeds its node limit")
  }
  match value {
    Json::Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, item in fields {
        budget.chars -= key.length()
        if budget.chars < 0 {
          return Err("external MCP input schema exceeds its text limit")
        }
        copied[key] = match
          native_mcp_copy_bounded_json(item, depth + 1, budget) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      }
      Ok(Json::object(copied))
    }
    Json::Array(items) => {
      let copied : Array[Json] = []
      for item in items {
        copied.push(
          match native_mcp_copy_bounded_json(item, depth + 1, budget) {
            Ok(value) => value
            Err(error) => return Err(error)
          },
        )
      }
      Ok(Json::array(copied))
    }
    Json::String(text) => {
      budget.chars -= text.length()
      if budget.chars < 0 {
        return Err("external MCP input schema exceeds its text limit")
      }
      Ok(Json::string(text))
    }
    Json::Number(number, ..) if !number.is_inf() && !number.is_nan() =>
      Ok(Json::number(number))
    Json::Number(_, ..) =>
      Err("external MCP input schema contains a non-finite number")
    Json::True => Ok(Json::boolean(true))
    Json::False => Ok(Json::boolean(false))
    Json::Null => Ok(Json::null())
  }
}

///|
fn native_mcp_name_safe(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 || value.contains("\u0000") {
    return false
  }
  true
}

///|
fn native_mcp_valid_fingerprint(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for character in value {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn native_mcp_sha256_hex(value : String) -> Result[String, String] {
  let bytes = @utf8.encode(value)
  let digest : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  if c_sha256(bytes, bytes.length(), digest) == 0 {
    return Err("native SHA-256 is unavailable")
  }
  let hex = StringBuilder()
  for byte in digest {
    let item = byte.to_int()
    if item < 16 {
      hex.write_char('0')
    }
    hex.write_string(item.to_string(radix=16))
  }
  Ok(hex.to_string())
}

///|
fn native_mcp_sanitize_name(value : String) -> String {
  let result = StringBuilder()
  for character in value {
    if (character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' {
      result.write_char(character)
    } else {
      result.write_char('_')
    }
  }
  result.to_string()
}

///|
fn native_mcp_public_tool_name(
  server_name : String,
  raw_name : String,
) -> Result[String, String] {
  if !native_mcp_name_safe(raw_name) {
    return Err("external MCP tool name is empty, too long, or contains NUL")
  }
  let joined = "mcp__" + server_name + "__" + raw_name
  let normalized = native_mcp_sanitize_name(joined)
  let name = if normalized == joined && joined.length() <= 64 {
    joined
  } else {
    let hash = match native_mcp_sha256_hex(server_name + "\u0000" + raw_name) {
      Ok(value) => value[:12].to_owned()
      Err(error) => return Err(error)
    }
    let prefix_length = Int::min(51, normalized.length())
    normalized[:prefix_length].to_owned() + "_" + hash
  }
  Ok(name)
}

///|
fn native_mcp_parse_tool(
  server_index : Int,
  server_name : String,
  value : Json,
) -> Result[(NativeMcpTool, Json, NativeMcpRoute), String] {
  let fields = match native_mcp_json_object(value) {
    Some(fields) => fields
    None =>
      return Err("external MCP server returned an invalid tool definition")
  }
  let raw_name = match native_mcp_json_string(fields.get("name")) {
    Some(name) if native_mcp_name_safe(name) => name
    _ => return Err("external MCP server returned an invalid tool name")
  }
  let description = match fields.get("description") {
    None => ""
    Some(Json::String(text)) if text.length() <= 4096 => text
    _ => return Err("external MCP server returned an invalid tool description")
  }
  match fields.get("execution") {
    Some(Json::Object(execution)) if execution.get("taskSupport") ==
      Some(Json::string("required")) =>
      return Err("external MCP tool requires unsupported task-based execution")
    _ => ()
  }
  let schema_budget = {
    nodes: 65536,
    chars: NATIVE_EXTERNAL_MCP_CATALOG_LIMIT,
  }
  let input_schema = match fields.get("inputSchema") {
    Some(value) =>
      match native_mcp_normalize_schema(value, 0, schema_budget) {
        Ok(schema) => schema
        Err(_) =>
          return Err("external MCP server returned an unsupported input schema")
      }
    None => return Err("external MCP server omitted a tool input schema")
  }
  match native_mcp_json_string(object_field(input_schema, "type")) {
    Some("object") => ()
    _ => return Err("external MCP tool input schema must describe an object")
  }
  let public_name = match native_mcp_public_tool_name(server_name, raw_name) {
    Ok(name) => name
    Err(_) =>
      return Err(
        "external MCP server returned a tool name that cannot be exposed",
      )
  }
  let tool = {
    name: public_name,
    server_name,
    raw_name,
    description,
    input_schema,
  }
  let descriptor : Json = {
    "name": Json::string(tool.name),
    "description": Json::string(tool.description),
    "effect": Json::string("write"),
    "input_schema": tool.input_schema,
  }
  let route = { server_index, raw_name: tool.raw_name, }
  Ok((tool, descriptor, route))
}

///|
fn native_mcp_catalog_hash(
  tools : Array[NativeMcpTool],
) -> Result[String, String] {
  let canonical : Array[Json] = []
  let sorted : Array[NativeMcpTool] = []
  for tool in tools {
    sorted.push(tool)
  }
  sorted.sort_by((left, right) => {
    native_mcp_string_compare(
      left.server_name + "\u0000" + left.raw_name,
      right.server_name + "\u0000" + right.raw_name,
    )
  })
  for tool in sorted {
    canonical.push({
      "server": Json::string(tool.server_name),
      "raw_name": Json::string(tool.raw_name),
      "name": Json::string(tool.name),
      "description": Json::string(tool.description),
      "input_schema": tool.input_schema,
    })
  }
  native_mcp_sha256_hex(native_mcp_canonical_json(Json::array(canonical)))
}

///|
/// Older native snapshots predate the MCP catalog fingerprint. They can adopt
/// a first catalog only when their history contains no namespaced MCP calls.
fn native_mcp_catalog_matches_stored(
  stored_hash : String?,
  configured_hash : String?,
  snapshot : Json,
) -> Bool {
  let has_legacy_mcp_calls = native_mcp_snapshot_has_mcp_calls(snapshot)
  match (stored_hash, configured_hash) {
    (Some(stored), Some(configured)) => stored == configured
    (Some(_), None) => false
    (None, None) => true
    (None, Some(_)) => !has_legacy_mcp_calls
  }
}

///|
fn native_mcp_snapshot_has_mcp_calls(snapshot : Json) -> Bool {
  let sessions = match object_field(snapshot, "sessions") {
    Some(Json::Array(values)) => values
    _ => return false
  }
  for session in sessions {
    let events = match object_field(session, "events") {
      Some(Json::Array(values)) => values
      _ => continue
    }
    for event in events {
      let event_type = string_field(event, "type").unwrap_or("")
      let data = object_field(event, "data").unwrap_or(Json::null())
      if event_type == "tool/call" &&
        string_field(data, "name").unwrap_or("").has_prefix("mcp__") {
        return true
      }
      if event_type == "assistant/message" {
        let message = object_field(data, "message").unwrap_or(Json::null())
        match object_field(message, "tool_calls") {
          Some(Json::Array(calls)) =>
            for call in calls {
              if string_field(call, "name").unwrap_or("").has_prefix("mcp__") {
                return true
              }
            }
          _ => ()
        }
        match object_field(message, "content") {
          Some(Json::Array(blocks)) =>
            for block in blocks {
              if string_field(block, "type") == Some("tool-call") &&
                string_field(block, "name").unwrap_or("").has_prefix("mcp__") {
                return true
              }
            }
          _ => ()
        }
      }
    }
  }
  false
}

///|
fn native_mcp_canonical_json(value : Json) -> String {
  match value {
    Json::Array(items) =>
      "[" + items.map(native_mcp_canonical_json).join(",") + "]"
    Json::Object(fields) => {
      let keys : Array[String] = []
      for key in fields.keys() {
        keys.push(key)
      }
      keys.sort_by((left, right) => native_mcp_string_compare(left, right))
      let members : Array[String] = []
      for key in keys {
        match fields.get(key) {
          Some(item) =>
            members.push(
              Json::string(key).stringify() +
              ":" +
              native_mcp_canonical_json(item),
            )
          None => ()
        }
      }
      "{" + members.join(",") + "}"
    }
    _ => value.stringify()
  }
}

///|
fn native_mcp_string_compare(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let limit = Int::min(left_chars.length(), right_chars.length())
  for index in 0..<limit {
    if left_chars[index] < right_chars[index] {
      return -1
    }
    if left_chars[index] > right_chars[index] {
      return 1
    }
  }
  if left_chars.length() < right_chars.length() {
    -1
  } else if left_chars.length() > right_chars.length() {
    1
  } else {
    0
  }
}
