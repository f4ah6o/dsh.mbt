///|
fn native_mcp_rpc_result(
  response : NativeMcpRpcResponse,
) -> Result[Json, String] {
  if response.remote_error {
    return Err("external MCP server returned a JSON-RPC error")
  }
  match response.result {
    Some(value) => Ok(value)
    None => Err("external MCP server returned no result")
  }
}

///|
async fn NativeMcpServer::initialize(
  self : NativeMcpServer,
) -> Result[Unit, String] {
  let response = match
    self.request(
      "initialize",
      {
        "protocolVersion": Json::string("2025-06-18"),
        "capabilities": Json::empty_object(),
        "clientInfo": {
          "name": Json::string("dsh-native"),
          "version": Json::string("0.1.3"),
        },
      },
      NATIVE_EXTERNAL_MCP_STARTUP_TIMEOUT_MS,
    ) {
    Ok(value) => value
    Err(_) => return Err("external MCP initialization request failed")
  }
  let result = match native_mcp_rpc_result(response) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fields = match native_mcp_json_object(result) {
    Some(value) => value
    None => return Err("external MCP initialization result is invalid")
  }
  let version = match native_mcp_json_string(fields.get("protocolVersion")) {
    Some(value) if ["2025-06-18", "2025-03-26", "2024-11-05"].contains(value) =>
      value
    _ =>
      return Err("external MCP server selected an unsupported protocol version")
  }
  if native_mcp_json_object(fields.get("capabilities").unwrap_or(Json::null()))
    is None ||
    native_mcp_json_object(fields.get("serverInfo").unwrap_or(Json::null()))
    is None {
    return Err(
      "external MCP initialization result is missing capabilities or server info",
    )
  }
  ignore(version)
  match self.notify("notifications/initialized") {
    Ok(_) => Ok(())
    Err(_) => Err("external MCP initialized notification failed")
  }
}

///|
async fn NativeMcpServer::list_tools(
  self : NativeMcpServer,
  server_index : Int,
) -> Result[
  (Array[NativeMcpTool], Array[Json], Map[String, NativeMcpRoute]),
  String,
] {
  let tools : Array[NativeMcpTool] = []
  let descriptors : Array[Json] = []
  let routes : Map[String, NativeMcpRoute] = Map([])
  let seen_cursors : Map[String, Bool] = Map([])
  let mut cursor : String? = None
  let mut page = 0
  let mut catalog_bytes = 0
  while page < NATIVE_EXTERNAL_MCP_MAX_PAGES {
    let params = match cursor {
      Some(value) => Json::object({ "cursor": Json::string(value) })
      None => Json::empty_object()
    }
    let response = match
      self.request("tools/list", params, NATIVE_EXTERNAL_MCP_STARTUP_TIMEOUT_MS) {
      Ok(value) => value
      Err(_) => return Err("external MCP tool discovery request failed")
    }
    let result = match native_mcp_rpc_result(response) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let fields = match native_mcp_json_object(result) {
      Some(value) => value
      None => return Err("external MCP tool list result is invalid")
    }
    let definitions = match fields.get("tools") {
      Some(Json::Array(values)) => values
      _ => return Err("external MCP tool list omitted its tools array")
    }
    for definition in definitions {
      if tools.length() >= NATIVE_EXTERNAL_MCP_MAX_TOOLS {
        return Err("external MCP tool catalog exceeds the 64-tool limit")
      }
      let (tool, descriptor, route) = match
        native_mcp_parse_tool(server_index, self.name, definition) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let schema_bytes = @utf8.encode(tool.input_schema.stringify()).length()
      catalog_bytes += schema_bytes +
        tool.description.length() +
        tool.name.length()
      if catalog_bytes > NATIVE_EXTERNAL_MCP_CATALOG_LIMIT {
        return Err("external MCP tool catalog exceeds the 1 MiB limit")
      }
      if routes.get(tool.name) is Some(_) {
        return Err("external MCP server returned a duplicate public tool name")
      }
      routes[tool.name] = route
      tools.push(tool)
      descriptors.push(descriptor)
    }
    cursor = match fields.get("nextCursor") {
      None => None
      Some(Json::String(value)) if !value.is_empty() && value.length() <= 4096 => {
        if seen_cursors.get(value) is Some(_) {
          return Err("external MCP server repeated a pagination cursor")
        }
        seen_cursors[value] = true
        Some(value)
      }
      Some(_) =>
        return Err("external MCP server returned an invalid pagination cursor")
    }
    page += 1
    if cursor is None {
      return Ok((tools, descriptors, routes))
    }
  }
  Err("external MCP tool discovery exceeded the 16-page limit")
}

///|
async fn NativeMcpPool::open(
  config_path : String?,
  worker_launcher : String,
  default_workspace : String,
  default_device : Int64,
  default_inode : Int64,
) -> Result[NativeMcpPool, String] {
  let servers : Array[NativeMcpServer] = []
  let outcome = @async.handle_cancellation(() => {
    native_mcp_pool_open_from_config(
      config_path, servers, worker_launcher, default_workspace, default_device, default_inode,
    )
  })
  match outcome {
    None => {
      @async.protect_from_cancel(async fn() {
        native_mcp_close_servers(servers)
      })
      Err("external MCP server startup was cancelled")
    }
    Some(Ok(pool)) => Ok(pool)
    Some(Err(error)) => {
      @async.protect_from_cancel(async fn() {
        native_mcp_close_servers(servers)
      })
      Err(error)
    }
  }
}

///|
async fn native_mcp_pool_open_from_config(
  config_path : String?,
  servers : Array[NativeMcpServer],
  worker_launcher : String,
  default_workspace : String,
  default_device : Int64,
  default_inode : Int64,
) -> Result[NativeMcpPool, String] {
  let configs = match config_path {
    None => []
    Some(path) =>
      match native_mcp_read_config(path) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  native_mcp_pool_start(
    configs, servers, worker_launcher, default_workspace, default_device, default_inode,
  )
}

///|
async fn native_mcp_pool_start(
  configs : Array[NativeMcpServerConfig],
  servers : Array[NativeMcpServer],
  worker_launcher : String,
  default_workspace : String,
  default_device : Int64,
  default_inode : Int64,
) -> Result[NativeMcpPool, String] {
  let tools : Array[NativeMcpTool] = []
  let descriptors : Array[Json] = []
  let routes : Map[String, NativeMcpRoute] = Map([])
  for config in configs {
    let server = match
      NativeMcpServer::start(
        config, worker_launcher, default_workspace, default_device, default_inode,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    // No suspension occurs between start returning and this registration. If
    // initialization is cancelled, the outer owner can close every child.
    servers.push(server)
    match server.initialize() {
      Err(_) =>
        return Err("external MCP server failed initialization: " + config.name)
      Ok(_) => ()
    }
    let discovered = match server.list_tools(servers.length() - 1) {
      Ok(value) => value
      Err(_) =>
        return Err("external MCP server tool discovery failed: " + config.name)
    }
    let (server_tools, server_descriptors, server_routes) = discovered
    if !native_mcp_catalog_capacity(tools.length(), server_tools.length()) {
      return Err("external MCP tool catalog exceeds the global 64-tool limit")
    }
    for tool in server_tools {
      if routes.get(tool.name) is Some(_) {
        return Err("external MCP servers expose a duplicate public tool name")
      }
      tools.push(tool)
    }
    for descriptor in server_descriptors {
      descriptors.push(descriptor)
    }
    for (name, route) in server_routes {
      routes[name] = route
    }
  }
  let catalog_hash = if tools.length() == 0 {
    None
  } else {
    match native_mcp_catalog_hash(tools) {
      Ok(value) => Some(value)
      Err(error) => return Err(error)
    }
  }
  Ok({ servers, descriptors, routes, catalog_hash, closed: false, })
}

///|
async fn native_mcp_close_servers(servers : Array[NativeMcpServer]) -> Unit {
  for server in servers {
    server.close_protected()
  }
}

///|
fn NativeMcpPool::has_tool(self : NativeMcpPool, public_name : String) -> Bool {
  self.routes.get(public_name) is Some(_)
}

///|
async fn NativeMcpPool::close(self : NativeMcpPool) -> Unit {
  if self.closed {
    return
  }
  @async.protect_from_cancel(async fn() {
    if self.closed {
      return
    }
    native_mcp_close_servers(self.servers)
    self.closed = true
  })
}
