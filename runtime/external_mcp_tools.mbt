///|
fn native_mcp_request_arguments(request : Json) -> Result[Json, String] {
  let arguments = match string_field(request, "arguments") {
    Some(raw) =>
      match parse_json(raw) {
        Ok(value) => value
        Err(_) => return Err("external MCP tool arguments are invalid JSON")
      }
    None =>
      match object_field(request, "arguments") {
        Some(value) => value
        None => return Err("external MCP tool arguments are missing")
      }
  }
  match arguments {
    Json::Object(_) => Ok(arguments)
    _ => Err("external MCP tool arguments must be an object")
  }
}

///|
fn native_mcp_append_text(
  output : StringBuilder,
  has_content : Bool,
  text : String,
) -> Bool {
  if has_content {
    output.write_string("\n\n")
  }
  output.write_string(text)
  true
}

///|
fn native_mcp_project_result(result : Json) -> Result[String, String] {
  let fields = match native_mcp_json_object(result) {
    Some(value) => value
    None => return Err("external MCP tool result is invalid")
  }
  let output = StringBuilder()
  let mut has_content = false
  match fields.get("content") {
    Some(Json::Array(blocks)) =>
      for block in blocks {
        let block_fields = native_mcp_json_object(block)
        let kind = match block_fields {
          Some(value) => native_mcp_json_string(value.get("type")).unwrap_or("")
          None => ""
        }
        match (kind, block_fields) {
          ("text", Some(value)) =>
            match native_mcp_json_string(value.get("text")) {
              Some(text) =>
                has_content = native_mcp_append_text(output, has_content, text)
              None =>
                has_content = native_mcp_append_text(
                  output, has_content, "[MCP text block omitted: text field is invalid]",
                )
            }
          ("resource_link", Some(value)) => {
            let title = native_mcp_json_string(value.get("title")).unwrap_or(
              "Resource",
            )
            let uri = native_mcp_json_string(value.get("uri")).unwrap_or("")
            has_content = native_mcp_append_text(
              output,
              has_content,
              title + ": " + uri,
            )
          }
          ("resource", Some(value)) => {
            let embedded = value.get("resource")
            let text = match embedded {
              Some(Json::Object(resource)) =>
                native_mcp_json_string(resource.get("text"))
              _ => None
            }
            match text {
              Some(text) =>
                has_content = native_mcp_append_text(output, has_content, text)
              None =>
                has_content = native_mcp_append_text(
                  output, has_content, "[MCP embedded resource omitted: only text resources are supported]",
                )
            }
          }
          ("image", _) =>
            has_content = native_mcp_append_text(
              output, has_content, "[MCP image omitted: this runtime exposes text-only tool results]",
            )
          ("audio", _) =>
            has_content = native_mcp_append_text(
              output, has_content, "[MCP audio omitted: this runtime exposes text-only tool results]",
            )
          ("", _) =>
            has_content = native_mcp_append_text(
              output, has_content, "[MCP content block omitted: invalid block]",
            )
          (other, _) =>
            has_content = native_mcp_append_text(
              output,
              has_content,
              "[MCP content block omitted: unsupported type " + other + "]",
            )
        }
      }
    None => ()
    Some(_) => return Err("external MCP tool result content is invalid")
  }
  match fields.get("structuredContent") {
    Some(value) =>
      has_content = native_mcp_append_text(
        output,
        has_content,
        "Structured content:\n" + value.stringify(),
      )
    None => ()
  }
  if !has_content {
    return Err("external MCP tool returned no supported content")
  }
  Ok(bounded_tool_text(output.to_string()))
}

///|
fn native_mcp_is_error(result : Json) -> Result[Bool, String] {
  match object_field(result, "isError") {
    None | Some(Json::False) => Ok(false)
    Some(Json::True) => Ok(true)
    Some(_) => Err("external MCP tool isError must be a boolean")
  }
}

///|
async fn NativeMcpPool::execute(self : NativeMcpPool, request : Json) -> Json {
  let public_name = string_field(request, "name").unwrap_or("")
  let route = match self.routes.get(public_name) {
    Some(value) => value
    None => return tool_error("Unknown external MCP tool")
  }
  let arguments = match native_mcp_request_arguments(request) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  if route.server_index < 0 || route.server_index >= self.servers.length() {
    return tool_error("External MCP tool route is unavailable")
  }
  let server = self.servers[route.server_index]
  let response = match
    server.request(
      "tools/call",
      { "name": Json::string(route.raw_name), "arguments": arguments },
      server.tool_timeout_ms,
    ) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let result = match native_mcp_rpc_result(response) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let is_error = match native_mcp_is_error(result) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let content = match native_mcp_project_result(result) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  if is_error {
    tool_error(content)
  } else {
    tool_success(content)
  }
}
