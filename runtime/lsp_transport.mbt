///|
priv struct NativeLspFramer {
  max_message_bytes : Int
  mut buffered : Array[Byte]
  mut separator_state : Int
  mut body_start : Int?
  mut body_length : Int
}

///|
fn NativeLspFramer::new(max_message_bytes : Int) -> NativeLspFramer {
  {
    max_message_bytes,
    buffered: [],
    separator_state: 0,
    body_start: None,
    body_length: 0,
  }
}

///|
fn native_lsp_hex_value(character : Char) -> Int? {
  if character >= '0' && character <= '9' {
    Some(character.to_int() - '0'.to_int())
  } else if character >= 'a' && character <= 'f' {
    Some(character.to_int() - 'a'.to_int() + 10)
  } else if character >= 'A' && character <= 'F' {
    Some(character.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn native_lsp_parse_content_length(header : Array[Byte]) -> Result[Int, String] {
  for byte in header {
    if byte.to_int() > 127 {
      return Err("LSP header contains non-ASCII bytes")
    }
  }
  let text = @utf8.decode(Bytes::from_array(header[:])) catch {
    _ => return Err("LSP header is not valid ASCII")
  }
  let mut found : Int? = None
  for line in text.split("\r\n") {
    let parts = line.split(":").to_array()
    if parts.length() < 2 {
      return Err("LSP header contains a malformed field")
    }
    if native_lsp_ascii_lower(parts[0].trim().to_owned()) == "content-length" {
      if found is Some(_) {
        return Err("LSP header contains duplicate Content-Length fields")
      }
      let value_text = parts[1:].join(":").trim().to_owned()
      if value_text.length() > 7 {
        return Err("LSP Content-Length exceeds the 4 MiB limit")
      }
      let length = match service_parse_int(value_text) {
        Some(value) => value
        None =>
          return Err("LSP Content-Length is not a nonnegative decimal integer")
      }
      if length > NATIVE_LSP_MAX_MESSAGE_BYTES {
        return Err("LSP message exceeds the 4 MiB limit")
      }
      found = Some(length)
    }
  }
  match found {
    Some(value) => Ok(value)
    None => Err("LSP header is missing Content-Length")
  }
}

///|
fn NativeLspFramer::feed(
  self : NativeLspFramer,
  chunk : Bytes,
) -> Result[Array[Json], String] {
  let messages : Array[Json] = []
  for byte in chunk {
    self.buffered.push(byte)
    match self.body_start {
      Some(start) =>
        if self.buffered.length() == start + self.body_length {
          let body = Bytes::from_array(self.buffered[start:].to_owned())
          let text = @utf8.decode(body) catch {
            _ => return Err("LSP message body is not valid UTF-8")
          }
          if !native_lsp_json_depth_bounded(text, 32) {
            return Err("LSP message exceeds the 32-level JSON nesting limit")
          }
          let message = @json.parse(text) catch {
            _ => return Err("LSP message body is not valid JSON")
          }
          messages.push(message)
          self.buffered = []
          self.separator_state = 0
          self.body_start = None
          self.body_length = 0
        }
      None => {
        let last = byte
        self.separator_state = match (self.separator_state, last) {
          (0, b'\r') => 1
          (1, b'\n') => 2
          (1, b'\r') => 1
          (2, b'\r') => 3
          (3, b'\n') => 4
          (3, b'\r') => 1
          _ => 0
        }
        if self.separator_state == 4 {
          let header_length = self.buffered.length() - 4
          if header_length > NATIVE_LSP_MAX_HEADER_BYTES {
            return Err("LSP header exceeds the 64 KiB limit")
          }
          let header = self.buffered[:header_length].to_owned()
          let length = match native_lsp_parse_content_length(header) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          if length > self.max_message_bytes {
            return Err("LSP message exceeds the configured size limit")
          }
          self.body_start = Some(self.buffered.length())
          self.body_length = length
          self.separator_state = 0
          if length == 0 {
            return Err("LSP message body is empty")
          }
        } else if self.buffered.length() > NATIVE_LSP_MAX_HEADER_BYTES + 4 {
          return Err("LSP header exceeds the 64 KiB limit")
        }
      }
    }
  }
  Ok(messages)
}

///|
fn native_lsp_encode_message(message : Json) -> Bytes {
  let body = @utf8.encode(message.stringify())
  let header = @utf8.encode(
    "Content-Length: " + body.length().to_string() + "\r\n\r\n",
  )
  let bytes : Array[Byte] = []
  for byte in header {
    bytes.push(byte)
  }
  for byte in body {
    bytes.push(byte)
  }
  Bytes::from_array(bytes[:])
}

///|
priv struct NativeLspRpcResponse {
  result : Json?
  remote_error : Bool
}

///|
priv struct NativeLspServer {
  config : NativeLspServerConfig
  workspace : String
  workspace_uri : String
  pid : Int
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  gate : @async.Mutex
  close_gate : @async.Mutex
  framer : NativeLspFramer
  mut queued_messages : Array[Json]
  mut next_id : Int
  mut capabilities : Json
  mut initialized : Bool
  mut poisoned : Bool
  mut closed : Bool
}

///|
fn native_lsp_response_id_matches(value : Json?, expected : Int) -> Bool {
  match value {
    Some(Json::Number(number, ..)) =>
      number == expected.to_double() && number.to_int().to_double() == number
    _ => false
  }
}

///|
async fn NativeLspServer::write_message(
  self : NativeLspServer,
  message : Json,
) -> Result[Unit, String] {
  if self.closed || self.poisoned {
    return Err("LSP server is unavailable")
  }
  self.writer.write(native_lsp_encode_message(message)) catch {
    _ => return Err("LSP request could not be written")
  }
  Ok(())
}

///|
async fn NativeLspServer::notify(
  self : NativeLspServer,
  rpc_method : String,
  params : Json,
) -> Result[Unit, String] {
  let message : Map[String, Json] = Map([
    ("jsonrpc", Json::string("2.0")),
    ("method", Json::string(rpc_method)),
  ])
  if params != Json::null() {
    message["params"] = params
  }
  self.write_message(Json::object(message))
}

///|
async fn NativeLspServer::answer_server_request(
  self : NativeLspServer,
  id : Json,
  rpc_method : String,
  params : Json,
) -> Result[Unit, String] {
  let result = match rpc_method {
    "workspace/configuration" =>
      match native_lsp_configuration_response(self.config, params) {
        Ok(value) =>
          self.write_message({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": value,
          })
        Err(_) =>
          self.write_message({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "error": {
              "code": Json::number(-32602.0),
              "message": Json::string("invalid workspace/configuration request"),
            },
          })
      }
    "workspace/workspaceFolders" =>
      self.write_message({
        "jsonrpc": Json::string("2.0"),
        "id": id,
        "result": Json::array([
          {
            "uri": Json::string(self.workspace_uri),
            "name": Json::string(native_lsp_basename(self.workspace)),
          },
        ]),
      })
    "client/registerCapability"
    | "client/unregisterCapability"
    | "window/workDoneProgress/create" =>
      self.write_message({
        "jsonrpc": Json::string("2.0"),
        "id": id,
        "result": Json::null(),
      })
    _ =>
      // In particular, workspace/applyEdit and workspace/executeCommand are
      // rejected. The host never applies server edits or runs server commands.
      self.write_message({
        "jsonrpc": Json::string("2.0"),
        "id": id,
        "error": {
          "code": Json::number(-32601.0),
          "message": Json::string(
            "server request is not supported by this host",
          ),
        },
      })
  }
  result
}

///|
fn native_lsp_configuration_response(
  config : NativeLspServerConfig,
  params : Json,
) -> Result[Json, String] {
  let items = match object_field(params, "items") {
    Some(Json::Array(values)) if values.length() <= 64 => values
    _ =>
      return Err(
        "workspace/configuration items must be an array of at most 64 entries",
      )
  }
  Ok(Json::array(items.map(_ => config.configuration)))
}

///|
async fn NativeLspServer::read_response(
  self : NativeLspServer,
  expected_id : Int,
) -> Result[NativeLspRpcResponse, String] {
  let mut notifications = 0
  while true {
    if self.queued_messages.is_empty() {
      let chunk = self.reader.read_some(max_len=8192) catch {
        _ => return Err("LSP server output could not be read")
      }
      match chunk {
        None => return Err("LSP server closed its output")
        Some(bytes) => {
          let messages = match self.framer.feed(bytes) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          if messages.length() + self.queued_messages.length() >
            NATIVE_LSP_MAX_QUEUED_MESSAGES {
            return Err("LSP server exceeded the 64-message queue limit")
          }
          for message in messages {
            self.queued_messages.push(message)
          }
          if self.queued_messages.is_empty() {
            continue
          }
        }
      }
    }
    let message = self.queued_messages[0]
    self.queued_messages = self.queued_messages[1:].to_owned()
    let fields = match native_lsp_json_object(message) {
      Some(value) => value
      None => return Err("LSP server sent a non-object JSON-RPC message")
    }
    if native_lsp_json_string(fields.get("jsonrpc")) != Some("2.0") {
      return Err("LSP server sent an invalid JSON-RPC version")
    }
    let rpc_method = native_lsp_json_string(fields.get("method"))
    let id = fields.get("id")
    match (id, rpc_method) {
      (Some(id), Some(rpc_method)) => {
        notifications += 1
        if notifications > NATIVE_LSP_MAX_NOTIFICATIONS {
          return Err("LSP server exceeded the 64-notification limit")
        }
        match
          self.answer_server_request(
            id,
            rpc_method,
            fields.get("params").unwrap_or(Json::null()),
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      (None, Some(_)) => {
        notifications += 1
        if notifications > NATIVE_LSP_MAX_NOTIFICATIONS {
          return Err("LSP server exceeded the 64-notification limit")
        }
      }
      (Some(id), None) => {
        if !native_lsp_response_id_matches(Some(id), expected_id) {
          return Err("LSP server returned an unexpected response id")
        }
        let result = fields.get("result")
        let error = fields.get("error")
        if result is Some(_) && error is Some(_) {
          return Err("LSP server returned both result and error")
        }
        if error is Some(value) {
          ignore(value)
          return Ok({ result: None, remote_error: true, })
        }
        match result {
          Some(value) =>
            return Ok({ result: Some(value), remote_error: false, })
          None => return Err("LSP server returned an empty JSON-RPC response")
        }
      }
      _ =>
        return Err("LSP server sent a message without a method or response id")
    }
  }
  Err("LSP server response is unavailable")
}

///|
async fn NativeLspServer::rpc_once(
  self : NativeLspServer,
  id : Int,
  rpc_method : String,
  params : Json,
) -> Result[NativeLspRpcResponse, String] {
  let message : Map[String, Json] = Map([
    ("jsonrpc", Json::string("2.0")),
    ("id", Json::number(id.to_double())),
    ("method", Json::string(rpc_method)),
  ])
  if params != Json::null() {
    message["params"] = params
  }
  match self.write_message(Json::object(message)) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  self.read_response(id)
}

///|
async fn NativeLspServer::request(
  self : NativeLspServer,
  rpc_method : String,
  params : Json,
  timeout_ms : Int,
) -> Result[Json, String] {
  if self.closed || self.poisoned {
    return Err("LSP server is unavailable")
  }
  let id = self.next_id
  self.next_id = if id >= 2147483646 { 1 } else { id + 1 }
  let outcome = @async.handle_cancellation(() => {
    @async.with_timeout_opt(timeout_ms, () => {
      self.rpc_once(id, rpc_method, params)
    })
  })
  match outcome {
    None => {
      self.poisoned = true
      self.close_protected()
      Err("LSP request was cancelled; the server was stopped without replay")
    }
    Some(None) => {
      self.poisoned = true
      self.close_protected()
      Err("LSP request timed out; the server was stopped without replay")
    }
    Some(Some(Err(error))) => {
      self.poisoned = true
      self.close_protected()
      Err(error)
    }
    Some(Some(Ok(response))) =>
      if response.remote_error {
        self.poisoned = true
        self.close_protected()
        Err("LSP server rejected " + rpc_method)
      } else {
        match response.result {
          Some(value) => Ok(value)
          None => Err("LSP server returned no result")
        }
      }
  }
}

///|
// The process API requires closing its child-side input endpoint if setup or
// spawn fails before ownership transfers to the child.
#warnings("-deprecated")
async fn NativeLspServer::start(
  config : NativeLspServerConfig,
  worker_launcher : String,
  workspace : String,
  workspace_uri : String,
  workspace_device : Int64,
  workspace_inode : Int64,
) -> Result[NativeLspServer, String] {
  let environment : Map[String, String] = Map([
    ("PATH", "/usr/bin:/bin"),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
  ])
  for (target, source) in config.env {
    match @env.get_env_var(source) {
      Some(value) => environment[target] = value
      None =>
        return Err("required host environment variable is not set: " + source)
    }
  }
  let (reader, stdout) = @process.read_from_process() catch {
    _ => return Err("cannot prepare LSP stdout pipe")
  }
  let (stdin, writer) = @process.write_to_process() catch {
    _ => {
      reader.close()
      stdout.close()
      return Err("cannot prepare LSP stdin pipe")
    }
  }
  let stderr = @process.redirect_to_file("/dev/null", permission=0o600) catch {
    _ => {
      reader.close()
      stdin.close()
      writer.close()
      stdout.close()
      return Err("cannot prepare LSP stderr sink")
    }
  }
  let worker_args = [
    "--internal-worker",
    NATIVE_LSP_MEMORY_LIMIT_MIB.to_string(),
    NATIVE_LSP_CPU_LIMIT_SECONDS.to_string(),
    workspace_device.to_string(),
    workspace_inode.to_string(),
    workspace,
    config.command,
    ..config.args,
  ]
  let pid = @async.protect_from_cancel(async fn() {
    @process.spawn_orphan(
      worker_launcher,
      worker_args,
      extra_env=environment,
      inherit_env=false,
      stdin~,
      stdout~,
      stderr~,
      cwd="/",
    )
  }) catch {
    _ => {
      reader.close()
      stdin.close()
      stdout.close()
      writer.close()
      stderr.close()
      return Err("cannot start configured LSP server")
    }
  }
  let server : NativeLspServer = {
    config,
    workspace,
    workspace_uri,
    pid,
    reader,
    writer,
    gate: @async.Mutex::Mutex(),
    close_gate: @async.Mutex::Mutex(),
    framer: NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES),
    queued_messages: [],
    next_id: 1,
    capabilities: Json::null(),
    initialized: false,
    poisoned: false,
    closed: false,
  }
  let initialized = @async.handle_cancellation(() => {
    @async.with_timeout_opt(NATIVE_LSP_STARTUP_TIMEOUT_MS, () => {
      server.initialize()
    })
  })
  match initialized {
    None => {
      server.poisoned = true
      server.close_protected()
      Err("LSP startup was cancelled; the server was stopped")
    }
    Some(None) => {
      server.poisoned = true
      server.close_protected()
      Err("LSP startup timed out; the server was stopped")
    }
    Some(Some(Ok(_))) => Ok(server)
    Some(Some(Err(error))) => {
      server.poisoned = true
      server.close_protected()
      Err(error)
    }
  }
}

///|
async fn NativeLspServer::initialize(
  self : NativeLspServer,
) -> Result[Unit, String] {
  let response = match
    self.request(
      "initialize",
      {
        "processId": Json::null(),
        "clientInfo": {
          "name": Json::string("dsh-native"),
          "version": Json::string("0.1.7"),
        },
        "rootUri": Json::string(self.workspace_uri),
        "workspaceFolders": Json::array([
          {
            "uri": Json::string(self.workspace_uri),
            "name": Json::string(native_lsp_basename(self.workspace)),
          },
        ]),
        "capabilities": {
          "general": {
            "positionEncodings": Json::array([Json::string("utf-16")]),
          },
          "workspace": {
            "configuration": Json::boolean(true),
            "workspaceFolders": Json::boolean(true),
          },
          "textDocument": {
            "definition": { "linkSupport": Json::boolean(true) },
            "implementation": { "linkSupport": Json::boolean(true) },
            "hover": {
              "contentFormat": Json::array([
                Json::string("markdown"),
                Json::string("plaintext"),
              ]),
            },
          },
          "window": { "workDoneProgress": Json::boolean(false) },
        },
        "initializationOptions": self.config.initialization_options,
      },
      NATIVE_LSP_STARTUP_TIMEOUT_MS,
    ) {
    Ok(value) => value
    Err(error) => return Err("LSP initialization failed: " + error)
  }
  let fields = match native_lsp_json_object(response) {
    Some(value) => value
    None => return Err("LSP initialization result is not an object")
  }
  let capabilities = match
    native_lsp_json_object(fields.get("capabilities").unwrap_or(Json::null())) {
    Some(value) => value
    None => return Err("LSP initialization result has no capabilities object")
  }
  match native_lsp_json_string(capabilities.get("positionEncoding")) {
    None | Some("utf-16") => ()
    Some(_) => return Err("LSP server must negotiate UTF-16 positions")
  }
  if !native_lsp_supports_transient_open(capabilities.get("textDocumentSync")) {
    return Err("LSP server does not support transient textDocument/didOpen")
  }
  self.capabilities = Json::object(capabilities)
  self.initialized = true
  match self.notify("initialized", Json::empty_object()) {
    Ok(_) => Ok(())
    Err(error) => Err("LSP initialized notification failed: " + error)
  }
}

///|
fn native_lsp_capability_enabled(capabilities : Json, name : String) -> Bool {
  match object_field(capabilities, name) {
    Some(Json::True) => true
    Some(Json::Object(_)) => true
    _ => false
  }
}

///|
fn native_lsp_supports_transient_open(value : Json?) -> Bool {
  match value {
    Some(Json::Number(number, ..)) => number == 1.0 || number == 2.0
    Some(Json::Object(fields)) =>
      match fields.get("openClose") {
        Some(Json::True) => true
        _ => false
      }
    _ => false
  }
}

///|
fn native_lsp_method(operation : String) -> String {
  match operation {
    "goToDefinition" => "textDocument/definition"
    "findReferences" => "textDocument/references"
    "goToImplementation" => "textDocument/implementation"
    _ => "textDocument/hover"
  }
}

///|
fn native_lsp_capability(operation : String) -> String {
  match operation {
    "goToDefinition" => "definitionProvider"
    "findReferences" => "referencesProvider"
    "goToImplementation" => "implementationProvider"
    _ => "hoverProvider"
  }
}

///|
async fn NativeLspServer::query(
  self : NativeLspServer,
  operation : String,
  uri : String,
  document : String,
  language_id : String,
  line : Int,
  character : Int,
  root : SafeRoot,
  blocked_path : String?,
  timeout_ms : Int,
) -> Result[String, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.poisoned || !self.initialized {
    return Err("LSP server is unavailable")
  }
  if !native_lsp_capability_enabled(
      self.capabilities,
      native_lsp_capability(operation),
    ) {
    return Err("configured LSP server does not support " + operation)
  }
  let outcome = @async.handle_cancellation(() => {
    @async.with_timeout_opt(timeout_ms, () => {
      match
        self.notify("textDocument/didOpen", {
          "textDocument": {
            "uri": Json::string(uri),
            "languageId": Json::string(language_id),
            "version": Json::number(1.0),
            "text": Json::string(document),
          },
        }) {
        Err(error) => Err(error)
        Ok(_) => {
          let params : Map[String, Json] = Map([
            ("textDocument", { "uri": Json::string(uri) }),
            (
              "position",
              {
                "line": Json::number(line.to_double()),
                "character": Json::number(character.to_double()),
              },
            ),
          ])
          if operation == "findReferences" {
            params["context"] = { "includeDeclaration": Json::boolean(true) }
          }
          let result = self.request(
            native_lsp_method(operation),
            Json::object(params),
            timeout_ms,
          )
          match result {
            Err(error) => Err(error)
            Ok(value) =>
              match
                self.notify("textDocument/didClose", {
                  "textDocument": { "uri": Json::string(uri) },
                }) {
                Err(error) => {
                  self.poisoned = true
                  self.close_protected()
                  Err("LSP didClose failed; the server was stopped: " + error)
                }
                Ok(_) =>
                  native_lsp_project_result(
                    operation,
                    value,
                    self.workspace,
                    root,
                    blocked_path~,
                  )
              }
          }
        }
      }
    })
  })
  match outcome {
    None => {
      self.poisoned = true
      self.close_protected()
      Err("LSP query was cancelled; the server was stopped without replay")
    }
    Some(None) => {
      self.poisoned = true
      self.close_protected()
      Err("LSP query timed out; the server was stopped without replay")
    }
    Some(Some(result)) =>
      match result {
        Ok(value) => Ok(value)
        Err(error) => {
          if !self.closed {
            self.poisoned = true
            self.close_protected()
          }
          Err(error)
        }
      }
  }
}

///|
async fn NativeLspServer::terminate_group(self : NativeLspServer) -> Unit {
  if !os_kill_process_group(self.pid, 15) && os_process_alive(self.pid) {
    ignore(os_kill_process(self.pid, 15))
  }
  let first_wait : Int? = @async.with_timeout_opt(500, () => {
    @process.wait_pid(self.pid)
  }) catch {
    _ => None
  }
  if first_wait is None {
    if !os_kill_process_group(self.pid, 9) && os_process_alive(self.pid) {
      ignore(os_kill_process(self.pid, 9))
    }
    let _ : Int? = @async.with_timeout_opt(1000, () => {
      @process.wait_pid(self.pid)
    }) catch {
      _ => None
    }
  } else if os_process_group_alive(self.pid) {
    @async.sleep(250)
    if os_process_group_alive(self.pid) {
      ignore(os_kill_process_group(self.pid, 9))
    }
  }
}

///|
async fn NativeLspServer::finish_graceful_shutdown(
  self : NativeLspServer,
) -> Unit {
  self.close_gate.acquire()
  defer self.close_gate.release()
  if self.closed {
    return
  }
  if os_process_group_alive(self.pid) {
    ignore(os_kill_process_group(self.pid, 15))
    @async.sleep(250)
    if !self.closed && os_process_group_alive(self.pid) {
      ignore(os_kill_process_group(self.pid, 9))
    }
  }
  self.writer.close()
  self.reader.close()
  self.closed = true
}

///|
async fn NativeLspServer::shutdown(self : NativeLspServer) -> Unit {
  @async.protect_from_cancel(async fn() {
    // Bound the complete graceful phase, including waiting for a route that
    // may still be active, the shutdown request, exit notification write,
    // and process exit. A server can stop reading stdin after its response.
    let graceful = @async.with_timeout_opt(NATIVE_LSP_SHUTDOWN_TIMEOUT_MS, async fn() {
      self.gate.acquire()
      defer self.gate.release()
      if self.closed {
        return false
      }
      if !self.initialized || self.poisoned {
        return false
      }
      match
        self.request("shutdown", Json::null(), NATIVE_LSP_SHUTDOWN_TIMEOUT_MS) {
        Ok(Json::Null) =>
          match self.notify("exit", Json::null()) {
            Err(_) => false
            Ok(_) => {
              let first_wait : Int? = @async.with_timeout_opt(500, () => {
                @process.wait_pid(self.pid)
              }) catch {
                _ => None
              }
              match first_wait {
                Some(_) => true
                None => false
              }
            }
          }
        _ => false
      }
    }) catch {
      _ => None
    }
    match graceful {
      Some(true) => self.finish_graceful_shutdown()
      _ => self.close_protected()
    }
  })
}

///|
async fn NativeLspServer::close_protected(self : NativeLspServer) -> Unit {
  @async.protect_from_cancel(async fn() {
    self.close_gate.acquire()
    defer self.close_gate.release()
    if self.closed {
      return
    }
    self.poisoned = true
    self.terminate_group()
    self.writer.close()
    self.reader.close()
    self.closed = true
  })
}
