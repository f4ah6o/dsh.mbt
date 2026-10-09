///|
fn native_mcp_child_environment(
  config : NativeMcpServerConfig,
) -> Result[Map[String, String], String] {
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
  Ok(environment)
}

///|
// The pinned process API requires this deprecated close method for the
// child-side input endpoint before spawn; closing it is required on failure.
#warnings("-deprecated")
async fn NativeMcpServer::start(
  config : NativeMcpServerConfig,
  worker_launcher : String,
  default_workspace : String,
  default_device : Int64,
  default_inode : Int64,
) -> Result[NativeMcpServer, String] {
  let environment = match native_mcp_child_environment(config) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (workspace, device, inode) = match config.cwd {
    None => (default_workspace, default_device, default_inode)
    Some(cwd) => {
      let resolved = @fs.realpath(cwd) catch {
        _ => return Err("external MCP working directory cannot be resolved")
      }
      let root = match SafeRoot::open(resolved) {
        Ok(value) => value
        Err(_) => return Err("external MCP working directory is unavailable")
      }
      let identity = match root.identity() {
        Ok(value) => value
        Err(_) => {
          root.close()
          return Err("external MCP working directory identity is unavailable")
        }
      }
      root.close()
      (resolved, identity.0, identity.1)
    }
  }
  let (reader, stdout) = @process.read_from_process() catch {
    _ => return Err("cannot prepare external MCP output pipe")
  }
  let (stdin, writer) = @process.write_to_process() catch {
    _ => {
      reader.close()
      stdout.close()
      return Err("cannot prepare external MCP input pipe")
    }
  }
  let stderr = @process.redirect_to_file("/dev/null", permission=0o600) catch {
    _ => {
      reader.close()
      stdin.close()
      writer.close()
      stdout.close()
      return Err("cannot prepare external MCP stderr redirection")
    }
  }
  let worker_args = [
    "--internal-worker",
    "512",
    "3600",
    device.to_string(),
    inode.to_string(),
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
      return Err("cannot start configured external MCP server")
    }
  }
  Ok({
    name: config.name,
    tool_timeout_ms: config.tool_timeout_ms,
    pid,
    reader,
    writer,
    gate: @async.Mutex::Mutex(),
    close_gate: @async.Mutex::Mutex(),
    framer: NativeMcpFramer::new(),
    queued_frames: [],
    next_id: 1,
    poisoned: false,
    closed: false,
  })
}

///|
async fn NativeMcpServer::close(self : NativeMcpServer) -> Unit {
  if self.closed {
    return
  }
  @async.protect_from_cancel(async fn() {
    self.close_gate.acquire()
    defer self.close_gate.release()
    if self.closed {
      return
    }
    self.poisoned = true
    if !os_kill_process_group(self.pid, 15) && os_process_alive(self.pid) {
      // Close can race the worker's first instruction. The early C setsid()
      // makes later signals group-scoped; this fallback only covers that
      // brief pre-session window and targets the owned leader PID.
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
      @async.sleep(500)
      if os_process_group_alive(self.pid) {
        ignore(os_kill_process_group(self.pid, 9))
      }
    }
    self.writer.close()
    self.reader.close()
    self.closed = true
  })
}

///|
async fn NativeMcpServer::close_protected(self : NativeMcpServer) -> Unit {
  @async.protect_from_cancel(() => self.close())
}

///|
fn native_mcp_response_id_matches(value : Json?, expected : Int) -> Bool {
  match value {
    Some(Json::Number(number, ..)) =>
      number == expected.to_double() && number.to_int().to_double() == number
    _ => false
  }
}

///|
async fn NativeMcpServer::read_response(
  self : NativeMcpServer,
  expected_id : Int,
) -> Result[NativeMcpRpcResponse, String] {
  let mut notifications = 0
  while true {
    if self.queued_frames.length() == 0 {
      let chunk = self.reader.read_some(max_len=8192) catch {
        _ => return Err("external MCP server output could not be read")
      }
      match chunk {
        None => return Err("external MCP server closed its output")
        Some(bytes) => {
          let frames = self.framer.feed(bytes)
          if frames.length() + self.queued_frames.length() >
            NATIVE_EXTERNAL_MCP_MAX_NOTIFICATIONS + 1 {
            return Err("external MCP server exceeded the frame queue limit")
          }
          for frame in frames {
            self.queued_frames.push(frame)
          }
          if self.queued_frames.length() == 0 {
            continue
          }
        }
      }
    }
    let frame = self.queued_frames[0]
    self.queued_frames = self.queued_frames[1:].to_owned()
    if frame.too_large {
      return Err("external MCP server sent a line over the 1 MiB limit")
    }
    let line = match native_mcp_decode_line(frame.bytes) {
      Ok(value) => value
      Err(_) => return Err("external MCP server sent invalid UTF-8")
    }
    let message = @json.parse(line) catch {
      _ => return Err("external MCP server sent invalid JSON")
    }
    let fields = match native_mcp_json_object(message) {
      Some(fields) => fields
      None =>
        return Err("external MCP server sent a non-object JSON-RPC message")
    }
    if native_mcp_json_string(fields.get("jsonrpc")) != Some("2.0") {
      return Err("external MCP server sent an invalid JSON-RPC version")
    }
    match fields.get("id") {
      None => {
        if native_mcp_json_string(fields.get("method")) is None {
          return Err("external MCP server sent a response without an id")
        }
        notifications += 1
        if notifications > NATIVE_EXTERNAL_MCP_MAX_NOTIFICATIONS {
          return Err("external MCP server exceeded the notification limit")
        }
      }
      Some(id) => {
        if !native_mcp_response_id_matches(Some(id), expected_id) {
          return Err("external MCP server returned an unexpected response id")
        }
        let result = fields.get("result")
        let error = fields.get("error")
        if result is Some(_) && error is Some(_) {
          return Err("external MCP server returned both result and error")
        }
        if error is Some(_) {
          return Ok({ result: None, remote_error: true, })
        }
        match result {
          Some(result) =>
            return Ok({ result: Some(result), remote_error: false, })
          None => return Err("external MCP server returned an empty response")
        }
      }
    }
  }
  Err("external MCP server response is unavailable")
}

///|
async fn NativeMcpServer::rpc_once(
  self : NativeMcpServer,
  id : Int,
  rpc_method : String,
  params : Json,
) -> Result[NativeMcpRpcResponse, String] {
  let request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string(rpc_method),
    "params": params,
  })
  self.writer.write(request.stringify() + "\n") catch {
    _ => return Err("external MCP request could not be written")
  }
  self.read_response(id)
}

///|
async fn NativeMcpServer::request(
  self : NativeMcpServer,
  rpc_method : String,
  params : Json,
  timeout_ms : Int,
) -> Result[NativeMcpRpcResponse, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.poisoned {
    return Err("external MCP server is unavailable")
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
      Err("external MCP request was cancelled; remote outcome is unknown")
    }
    Some(None) => {
      self.poisoned = true
      self.close_protected()
      Err("external MCP request timed out; remote outcome is unknown")
    }
    Some(Some(Err(error))) => {
      self.poisoned = true
      self.close_protected()
      if rpc_method == "tools/call" {
        Err(
          "external MCP call failed; remote outcome is unknown (" + error + ")",
        )
      } else {
        Err(error)
      }
    }
    Some(Some(Ok(response))) => Ok(response)
  }
}

///|
async fn NativeMcpServer::notify(
  self : NativeMcpServer,
  rpc_method : String,
) -> Result[Unit, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.poisoned {
    return Err("external MCP server is unavailable")
  }
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(rpc_method),
  })
  self.writer.write(notification.stringify() + "\n") catch {
    _ => return Err("external MCP notification could not be written")
  }
  Ok(())
}
