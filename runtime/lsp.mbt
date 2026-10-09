///|
const NATIVE_LSP_CONFIG_LIMIT : Int = 1048576

///|
const NATIVE_LSP_MAX_SERVERS : Int = 8

///|
const NATIVE_LSP_MAX_EXTENSIONS : Int = 128

///|
const NATIVE_LSP_MAX_MESSAGE_BYTES : Int = 4194304

///|
const NATIVE_LSP_MAX_HEADER_BYTES : Int = 65536

///|
const NATIVE_LSP_MAX_DOCUMENT_BYTES : Int = 4194304

///|
const NATIVE_LSP_MAX_NOTIFICATIONS : Int = 64

///|
const NATIVE_LSP_MAX_QUEUED_MESSAGES : Int = 64

///|
const NATIVE_LSP_MAX_RESULT_CHARS : Int = 16000

///|
const NATIVE_LSP_MAX_LOCATIONS : Int = 100

///|
const NATIVE_LSP_STARTUP_TIMEOUT_MS : Int = 10000

///|
const NATIVE_LSP_DEFAULT_TOOL_TIMEOUT_MS : Int = 60000

///|
const NATIVE_LSP_SHUTDOWN_TIMEOUT_MS : Int = 2000

///|
const NATIVE_LSP_CPU_LIMIT_SECONDS : Int = 3600

///|
const NATIVE_LSP_MEMORY_LIMIT_MIB : Int = 8192

///|
priv struct NativeLspServerConfig {
  id : String
  command : String
  args : Array[String]
  env : Array[(String, String)]
  extension_to_language : Map[String, String]
  initialization_options : Json
  configuration : Json
  settings_revision : String?
  tool_timeout_ms : Int
}

///|
priv struct NativeLspRoute {
  server_index : Int
  language_id : String
}

///|
priv struct NativeLspPool {
  configs : Array[NativeLspServerConfig]
  routes : Map[String, NativeLspRoute]
  workspace : String
  workspace_uri : String
  workspace_device : Int64
  workspace_inode : Int64
  worker_launcher : String
  config_gates : Array[@async.Mutex]
  descriptor : Json?
  catalog_hash : String?
  gate : @async.Mutex
  servers : Map[String, NativeLspServer]
  mut closed : Bool
}

///|
fn native_lsp_json_object(value : Json) -> Map[String, Json]? {
  match value {
    Json::Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn native_lsp_json_string(value : Json?) -> String? {
  match value {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn native_lsp_json_depth_bounded(text : String, limit : Int) -> Bool {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for character in text {
    if in_string {
      if escaped {
        escaped = false
      } else if character == '\\' {
        escaped = true
      } else if character == '"' {
        in_string = false
      }
    } else if character == '"' {
      in_string = true
    } else if character == '{' || character == '[' {
      depth += 1
      if depth > limit {
        return false
      }
    } else if character == '}' || character == ']' {
      depth -= 1
      if depth < 0 {
        return false
      }
    }
  }
  depth == 0 && !in_string
}

///|
fn native_lsp_valid_identifier(value : String, maximum : Int) -> Bool {
  if value.is_empty() || value.length() > maximum {
    return false
  }
  for character in value {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' ||
      character == '.') {
      return false
    }
  }
  true
}

///|
fn native_lsp_valid_env_name(value : String) -> Bool {
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
fn native_lsp_ascii_lower(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character >= 'A' && character <= 'Z' {
      builder.write_char((character.to_int() + 32).unsafe_to_char())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn native_lsp_parse_extension_map(
  value : Json?,
) -> Result[Map[String, String], String] {
  let mappings = match value {
    Some(Json::Object(fields)) if fields.length() > 0 &&
      fields.length() <= NATIVE_LSP_MAX_EXTENSIONS => fields
    _ =>
      return Err(
        "LSP extensionToLanguage must be a nonempty object of at most 128 entries",
      )
  }
  let result : Map[String, String] = Map([])
  for (raw_extension, raw_language) in mappings {
    let extension = native_lsp_ascii_lower(raw_extension)
    let language = match raw_language {
      Json::String(text) if native_lsp_valid_identifier(text, 64) => text
      _ => return Err("LSP language ids must use letters, digits, _, -, or .")
    }
    if extension.length() < 2 ||
      extension.length() > 32 ||
      !extension.has_prefix(".") {
      return Err(
        "LSP extensions must begin with a dot and contain 1..31 characters",
      )
    }
    for character in extension[1:] {
      if !((character >= 'a' && character <= 'z') ||
        (character >= '0' && character <= '9') ||
        character == '.' ||
        character == '_' ||
        character == '-' ||
        character == '+') {
        return Err("LSP extensions contain an unsupported character")
      }
    }
    if result.get(extension) is Some(_) {
      return Err("LSP extension mappings contain a duplicate extension")
    }
    result[extension] = language
  }
  Ok(result)
}

///|
fn native_lsp_bounded_json(
  value : Json,
  depth : Int,
  budget : NativeMcpSchemaBudget,
) -> Result[Json, String] {
  if depth > 24 {
    return Err("LSP configuration JSON exceeds the 24-level depth limit")
  }
  budget.nodes -= 1
  if budget.nodes < 0 {
    return Err("LSP configuration JSON exceeds its node limit")
  }
  match value {
    Json::Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for (key, item) in fields {
        budget.chars -= key.length()
        if budget.chars < 0 {
          return Err("LSP configuration JSON exceeds its text limit")
        }
        copied[key] = match native_lsp_bounded_json(item, depth + 1, budget) {
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
          match native_lsp_bounded_json(item, depth + 1, budget) {
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
        Err("LSP configuration JSON exceeds its text limit")
      } else {
        Ok(Json::string(text))
      }
    }
    _ => Ok(value)
  }
}

///|
fn native_lsp_config_json_field(
  fields : Map[String, Json],
  name : String,
) -> Result[Json, String] {
  match fields.get(name) {
    None => Ok(Json::null())
    Some(value) =>
      native_lsp_bounded_json(value, 0, {
        nodes: 65536,
        chars: NATIVE_LSP_CONFIG_LIMIT,
      })
  }
}

///|
fn native_lsp_parse_server(
  id : String,
  value : Json,
) -> Result[NativeLspServerConfig, String] {
  let fields = match native_lsp_json_object(value) {
    Some(value) => value
    None => return Err("LSP server config must be an object")
  }
  for key, _ in fields {
    if ![
        "command", "args", "env", "extensionToLanguage", "initializationOptions",
        "configuration", "settingsRevision", "toolCallTimeoutMs",
      ].contains(key) {
      return Err("unknown LSP server config field: " + key)
    }
  }
  let command = match native_lsp_json_string(fields.get("command")) {
    Some(value) if !value.trim().is_empty() &&
      value.length() <= 4096 &&
      !value.contains("\u0000") => value
    _ =>
      return Err(
        "LSP server command must be a nonempty string of at most 4096 characters",
      )
  }
  let mut total_argument_bytes = 0
  let args = match fields.get("args") {
    None => []
    Some(Json::Array(values)) if values.length() <= 128 => {
      let result : Array[String] = []
      for value in values {
        match value {
          Json::String(text) if text.length() <= 4096 &&
            !text.contains("\u0000") => {
            total_argument_bytes += @utf8.encode(text).length()
            if total_argument_bytes > 32768 {
              return Err("LSP server args exceed the 32 KiB limit")
            }
            result.push(text)
          }
          _ =>
            return Err(
              "LSP server args must be strings of at most 4096 characters",
            )
        }
      }
      result
    }
    _ => return Err("LSP server args must be an array of at most 128 strings")
  }
  let env = match fields.get("env") {
    None => []
    Some(Json::Object(values)) if values.length() <= 64 => {
      let result : Array[(String, String)] = []
      for (target, source) in values {
        let source_name = match source {
          Json::String(text) if native_lsp_valid_env_name(target) &&
            native_lsp_valid_env_name(text) => text
          _ =>
            return Err(
              "LSP env must map valid child variable names to host variable names",
            )
        }
        result.push((target, source_name))
      }
      result
    }
    _ => return Err("LSP env must be an object of at most 64 variable mappings")
  }
  let extension_to_language = match
    native_lsp_parse_extension_map(fields.get("extensionToLanguage")) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let initialization_options = match
    native_lsp_config_json_field(fields, "initializationOptions") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let configuration = match
    native_lsp_config_json_field(fields, "configuration") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let settings_revision = match fields.get("settingsRevision") {
    None => None
    Some(Json::String(value)) if native_lsp_valid_identifier(value, 128) =>
      Some(value)
    _ =>
      return Err("LSP settingsRevision must be a stable nonsecret identifier")
  }
  if (initialization_options != Json::null() || configuration != Json::null()) &&
    settings_revision is None {
    return Err(
      "LSP settingsRevision is required when initializationOptions or configuration is set",
    )
  }
  let tool_timeout_ms = match fields.get("toolCallTimeoutMs") {
    None => NATIVE_LSP_DEFAULT_TOOL_TIMEOUT_MS
    Some(Json::Number(value, ..)) if value >= 100.0 &&
      value <= 300000.0 &&
      value.to_int().to_double() == value => value.to_int()
    _ =>
      return Err(
        "LSP toolCallTimeoutMs must be an integer between 100 and 300000",
      )
  }
  Ok({
    id,
    command,
    args,
    env,
    extension_to_language,
    initialization_options,
    configuration,
    settings_revision,
    tool_timeout_ms,
  })
}

///|
fn native_lsp_config_hash(
  configs : Array[NativeLspServerConfig],
) -> Result[String, String] {
  let servers : Array[Json] = []
  let sorted_configs : Array[NativeLspServerConfig] = configs.map(value => value)
  sorted_configs.sort_by((left, right) => {
    native_mcp_string_compare(left.id, right.id)
  })
  for config in sorted_configs {
    let extensions : Map[String, Json] = Map([])
    for (extension, language) in config.extension_to_language {
      extensions[extension] = Json::string(language)
    }
    let env : Map[String, Json] = Map([])
    for (target, source) in config.env {
      env[target] = Json::string(source)
    }
    servers.push({
      "id": Json::string(config.id),
      "command": Json::string(config.command),
      "args": Json::array(config.args.map(Json::string)),
      "env_sources": Json::object(env),
      "extensions": Json::object(extensions),
      "tool_timeout_ms": Json::number(config.tool_timeout_ms.to_double()),
      "memory_limit_mib": Json::number(NATIVE_LSP_MEMORY_LIMIT_MIB.to_double()),
      // Option payloads can contain secrets. Their presence is enough to mark
      // catalog shape without persisting values or a guessable secret digest.
      "has_initialization_options": Json::boolean(
        config.initialization_options != Json::null(),
      ),
      "has_configuration": Json::boolean(config.configuration != Json::null()),
      // Settings payloads may contain credentials. A caller supplies a stable
      // nonsecret revision to bind those values without persisting them.
      "settings_revision": config.settings_revision
      .map(Json::string)
      .unwrap_or(Json::null()),
    })
  }
  let canonical = native_mcp_canonical_json(Json::array(servers))
  native_mcp_sha256_hex(canonical)
}

///|
async fn native_lsp_read_config(
  path : String,
) -> Result[Array[NativeLspServerConfig], String] {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch {
    _ => return Err("cannot read LSP config")
  }
  defer file.close()
  if file.kind() != @fs.Regular {
    return Err("LSP config must be a regular file")
  }
  let size = file.size() catch {
    _ => return Err("cannot determine LSP config size")
  }
  if size < 0L || size > NATIVE_LSP_CONFIG_LIMIT.to_int64() {
    return Err("LSP config exceeds the 1 MiB limit")
  }
  let bytes : Array[Byte] = []
  while true {
    let chunk = file.read_some(max_len=8192) catch {
      _ => return Err("cannot read LSP config")
    }
    match chunk {
      None => break
      Some(chunk) =>
        for byte in chunk {
          if bytes.length() >= NATIVE_LSP_CONFIG_LIMIT {
            return Err("LSP config exceeds the 1 MiB limit")
          }
          bytes.push(byte)
        }
    }
  }
  let text = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("LSP config is not valid UTF-8")
  }
  if !native_lsp_json_depth_bounded(text, 32) {
    return Err("LSP config exceeds the 32-level JSON nesting limit")
  }
  let document = @json.parse(text) catch {
    _ => return Err("LSP config is not valid JSON")
  }
  let root = match native_lsp_json_object(document) {
    Some(fields) => fields
    None => return Err("LSP config must be a JSON object")
  }
  for key, _ in root {
    if key != "servers" {
      return Err("unknown LSP config field: " + key)
    }
  }
  let entries = match root.get("servers") {
    Some(Json::Object(values)) if values.length() > 0 &&
      values.length() <= NATIVE_LSP_MAX_SERVERS => values
    _ => return Err("LSP config servers must contain 1..8 server entries")
  }
  let configs : Array[NativeLspServerConfig] = []
  let seen_extensions : Map[String, Bool] = Map([])
  let mut total_extensions = 0
  for (id, value) in entries {
    if !native_lsp_valid_identifier(id, 32) {
      return Err("LSP server ids must use 1..32 letters, digits, _, -, or .")
    }
    let config = match native_lsp_parse_server(id, value) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    total_extensions += config.extension_to_language.length()
    if total_extensions > NATIVE_LSP_MAX_EXTENSIONS {
      return Err("LSP config exceeds the 128-extension limit")
    }
    for extension, _ in config.extension_to_language {
      if seen_extensions.get(extension) is Some(_) {
        return Err("LSP extension is assigned to more than one server")
      }
      seen_extensions[extension] = true
    }
    configs.push(config)
  }
  configs.sort_by((left, right) => native_mcp_string_compare(left.id, right.id))
  Ok(configs)
}

///|
async fn NativeLspPool::open(
  config_path : String?,
  worker_launcher : String,
  workspace : String,
  workspace_device : Int64,
  workspace_inode : Int64,
) -> Result[NativeLspPool, String] {
  let configs = match config_path {
    None => []
    Some(path) =>
      match native_lsp_read_config(path) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  let routes : Map[String, NativeLspRoute] = Map([])
  let config_gates : Array[@async.Mutex] = []
  for server_index, config in configs {
    config_gates.push(@async.Mutex::Mutex())
    for (extension, language_id) in config.extension_to_language {
      routes[extension] = { server_index, language_id, }
    }
  }
  let catalog_hash = if configs.is_empty() {
    None
  } else {
    match native_lsp_config_hash(configs) {
      Ok(value) => Some(value)
      Err(error) => return Err(error)
    }
  }
  Ok({
    configs,
    routes,
    workspace,
    workspace_uri: native_lsp_file_uri(workspace),
    workspace_device,
    workspace_inode,
    worker_launcher,
    config_gates,
    descriptor: if configs.is_empty() {
      None
    } else {
      Some(@plugins.lsp_tool())
    },
    catalog_hash,
    gate: @async.Mutex::Mutex(),
    servers: Map([]),
    closed: false,
  })
}

///|
async fn NativeLspPool::server(
  self : NativeLspPool,
  route : NativeLspRoute,
) -> Result[NativeLspServer, String] {
  if self.closed {
    return Err("LSP is disabled or the native runtime is closed")
  }
  if route.server_index < 0 || route.server_index >= self.configs.length() {
    return Err("LSP server mapping is unavailable")
  }
  let config = self.configs[route.server_index]
  match self.servers.get(config.id) {
    Some(server) if !server.closed && !server.poisoned => return Ok(server)
    Some(server) => {
      self.servers.remove(config.id)
      if !server.closed {
        server.shutdown()
      }
    }
    None => ()
  }
  let server = match
    NativeLspServer::start(
      config,
      self.worker_launcher,
      self.workspace,
      self.workspace_uri,
      self.workspace_device,
      self.workspace_inode,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.servers[config.id] = server
  Ok(server)
}

///|
fn native_lsp_tool_arguments(request : Json) -> Result[Json, String] {
  let arguments = match string_field(request, "arguments") {
    Some(raw) =>
      match parse_json(raw) {
        Ok(value) => value
        Err(_) => return Err("LSP tool arguments are invalid JSON")
      }
    None =>
      match object_field(request, "arguments") {
        Some(value) => value
        None => return Err("LSP tool arguments are missing")
      }
  }
  match arguments {
    Json::Object(_) => Ok(arguments)
    _ => Err("LSP tool arguments must be an object")
  }
}

///|
fn native_lsp_extension(path : String) -> String? {
  let components = path.split("/").to_array()
  if components.is_empty() {
    return None
  }
  let name = components[components.length() - 1].to_owned()
  let parts = name.split(".").to_array()
  if parts.length() < 2 || parts[parts.length() - 1].is_empty() {
    None
  } else {
    Some("." + native_lsp_ascii_lower(parts[parts.length() - 1].to_owned()))
  }
}

///|
fn native_lsp_position(
  document : String,
  one_based_line : Int,
  one_based_character : Int,
) -> Result[(Int, Int), String] {
  let lines = document.split("\n").to_array()
  let line_index = one_based_line - 1
  if line_index < 0 || line_index >= lines.length() {
    return Err("LSP line is outside the source file")
  }
  let raw_line = lines[line_index].to_owned()
  let chars = raw_line.to_array()
  let line_length = if chars.length() > 0 && chars[chars.length() - 1] == '\r' {
    chars.length() - 1
  } else {
    chars.length()
  }
  let target_units = one_based_character - 1
  let mut units = 0
  for index in 0..<line_length {
    if units == target_units {
      return Ok((line_index, units))
    }
    let width = if chars[index].to_int() > 0xFFFF { 2 } else { 1 }
    if target_units < units + width {
      return Err("LSP character splits a UTF-16 surrogate pair")
    }
    units += width
  }
  if units == target_units {
    Ok((line_index, units))
  } else {
    Err("LSP character is outside the source line")
  }
}

///|
async fn NativeLspPool::execute(
  self : NativeLspPool,
  tools : NativeTools,
  request : Json,
) -> Json {
  let args = match native_lsp_tool_arguments(request) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let operation = match tool_arg_string(args, "operation", maximum=32) {
    Ok(value) if [
        "goToDefinition", "findReferences", "goToImplementation", "hover",
      ].contains(value) => value
    Ok(_) =>
      return tool_error(
        "operation must be goToDefinition, findReferences, goToImplementation, or hover",
      )
    Err(error) => return tool_error(error)
  }
  let raw_path = match tool_arg_string(args, "file_path", maximum=4096) {
    Ok(value) if !value.trim().is_empty() => value
    Ok(_) =>
      return tool_error("file_path must be a non-empty workspace-relative path")
    Err(error) => return tool_error(error)
  }
  let line = match tool_arg_int(args, "line", 0, 1, 1000000) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let character = match tool_arg_int(args, "character", 0, 1, 1000000) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let path = match tools.resolve_path(raw_path) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let extension = match native_lsp_extension(path) {
    Some(value) => value
    None =>
      return tool_error(
        "LSP does not support source files without an extension",
      )
  }
  let route = match self.routes.get(extension) {
    Some(value) => value
    None =>
      return tool_error("no configured LSP server handles this file extension")
  }
  if route.server_index < 0 || route.server_index >= self.config_gates.length() {
    return tool_error("LSP server mapping is unavailable")
  }
  let timeout_ms = self.configs[route.server_index].tool_timeout_ms
  let outcome = @async.handle_cancellation(() => {
    @async.with_timeout_opt(timeout_ms, () => {
      self.execute_routed(tools, operation, path, line, character, route)
    })
  })
  match outcome {
    None => tool_error("LSP request was cancelled; no request was replayed")
    Some(None) =>
      tool_error(
        "LSP request timed out before completion; no request was replayed",
      )
    Some(Some(result)) => result
  }
}

///|
async fn NativeLspPool::execute_routed(
  self : NativeLspPool,
  tools : NativeTools,
  operation : String,
  path : String,
  line : Int,
  character : Int,
  route : NativeLspRoute,
) -> Json {
  let route_gate = self.config_gates[route.server_index]
  route_gate.acquire()
  defer route_gate.release()
  let (document, _) = match
    tools.root.read_text(path, max_bytes=NATIVE_LSP_MAX_DOCUMENT_BYTES) {
    Ok(value) => value
    Err(_) =>
      return tool_error(
        "LSP source must be a readable UTF-8 regular file within the workspace",
      )
  }
  let position = match native_lsp_position(document, line, character) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  // Every argument, workspace boundary, file read, and UTF-16 cursor check is
  // complete before the trusted configured server is first started.
  let server_outcome = {
    self.gate.acquire()
    defer self.gate.release()
    self.server(route)
  }
  let server = match server_outcome {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let uri = native_lsp_file_uri(self.workspace + "/" + path)
  match
    server.query(
      operation,
      uri,
      document,
      route.language_id,
      position.0,
      position.1,
      tools.root,
      tools.blocked_path,
      self.configs[route.server_index].tool_timeout_ms,
    ) {
    Ok(value) => tool_success(value)
    Err(error) => tool_error(error)
  }
}

///|
async fn NativeLspPool::close(self : NativeLspPool) -> Unit {
  @async.protect_from_cancel(async fn() {
    self.gate.acquire()
    if self.closed {
      self.gate.release()
      return
    }
    self.closed = true
    let servers : Array[NativeLspServer] = []
    for _, server in self.servers {
      servers.push(server)
    }
    self.servers.clear()
    self.gate.release()
    for server in servers {
      server.shutdown()
    }
  })
}

///|
fn native_lsp_catalog_matches_stored(
  stored_hash : String?,
  configured_hash : String?,
  snapshot : Json,
) -> Bool {
  let has_lsp_calls = native_lsp_snapshot_has_calls(snapshot)
  match (stored_hash, configured_hash) {
    (Some(stored), Some(configured)) => stored == configured
    (Some(_), None) => false
    (None, None) => true
    (None, Some(_)) => !has_lsp_calls
  }
}

///|
fn native_lsp_snapshot_has_calls(snapshot : Json) -> Bool {
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
      if string_field(event, "type") == Some("tool/call") &&
        string_field(
          object_field(event, "data").unwrap_or(Json::null()),
          "name",
        ) ==
        Some("lsp") {
        return true
      }
      if string_field(event, "type") == Some("assistant/message") {
        let message = object_field(
          object_field(event, "data").unwrap_or(Json::null()),
          "message",
        ).unwrap_or(Json::null())
        match object_field(message, "tool_calls") {
          Some(Json::Array(calls)) =>
            for call in calls {
              if string_field(call, "name") == Some("lsp") {
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
