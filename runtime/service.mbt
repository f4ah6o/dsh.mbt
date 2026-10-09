///|
const NATIVE_HTTP_BODY_LIMIT : Int = 1048576

///|
const NATIVE_HTTP_CONNECTION_LIMIT : Int = 64

///|
extern "C" fn c_service_signals_install() -> Int = "dsh_service_signals_install"

///|
extern "C" fn c_service_signals_requested() -> Int = "dsh_service_signals_requested"

///|
extern "C" fn c_service_signals_restore() -> Int = "dsh_service_signals_restore"

///|
fn native_configure_service_signal_policy(args : Array[String]) -> Unit {
  if args.any(value => value == "--serve") {
    // async's default event-loop signal waiter consumes SIGINT/SIGTERM and
    // re-raises them after cancelling main. Reconfigure the existing waiter
    // before the service starts accepting requests so the native sig_atomic_t
    // handler below owns those two shutdown signals instead.
    @signal.set_global_cancellation_signals([])
  }
}

///|
priv struct NativeService {
  runtime : NativeRuntime
  web_root : String
  requested_port : Int
  tailnet_host : String?
  tailnet_owner : String?
  tailnet_port : Int
}

///|
fn service_tailnet_config_from_settings(
  host : String?,
  users : String?,
  raw_port : String?,
) -> Result[(String, String, Int)?, String] {
  let port = match service_tailnet_port_from_setting(raw_port) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match (host, users) {
    (None, None) =>
      match raw_port {
        None => Ok(None)
        Some(_) =>
          Err(
            "DSH_TAILNET_PORT requires DSH_TAILNET_HOST and DSH_TAILNET_ALLOWED_USERS",
          )
      }
    (Some(raw_host), Some(raw_users)) => {
      let normalized_host = raw_host.trim().to_lower().to_owned()
      if normalized_host.is_empty() ||
        normalized_host.length() > 253 ||
        normalized_host.contains("/") ||
        normalized_host.contains(":") ||
        normalized_host.contains("@") ||
        normalized_host.contains(" ") {
        return Err("DSH_TAILNET_HOST must be a hostname without scheme or path")
      }
      let owners = raw_users
        .split(",")
        .map(value => value.trim().to_lower().to_owned())
        .to_array()
      if owners.length() != 1 ||
        owners[0].is_empty() ||
        owners[0].length() > 254 ||
        !owners[0].contains("@") ||
        owners[0].contains(" ") {
        return Err(
          "DSH_TAILNET_ALLOWED_USERS must name exactly one owner login",
        )
      }
      Ok(Some((normalized_host, owners[0], port)))
    }
    _ =>
      Err("DSH_TAILNET_HOST and DSH_TAILNET_ALLOWED_USERS must be set together")
  }
}

///|
fn service_tailnet_config_from_env() -> Result[(String, String, Int)?, String] {
  service_tailnet_config_from_settings(
    @env.get_env_var("DSH_TAILNET_HOST"),
    @env.get_env_var("DSH_TAILNET_ALLOWED_USERS"),
    @env.get_env_var("DSH_TAILNET_PORT"),
  )
}

///|
fn service_tailnet_port_from_setting(raw_port : String?) -> Result[Int, String] {
  match raw_port {
    None => Ok(443)
    Some(value) if value.length() <= 5 =>
      match service_parse_int(value) {
        Some(port) if port >= 1 && port <= 65535 => Ok(port)
        _ => Err("DSH_TAILNET_PORT must be an integer between 1 and 65535")
      }
    Some(_) => Err("DSH_TAILNET_PORT must be an integer between 1 and 65535")
  }
}

///|
async fn NativeService::new(
  runtime : NativeRuntime,
  source_root : String,
  requested_port : Int,
  assets_dir? : String? = None,
) -> Result[NativeService, String] {
  if requested_port < 0 || requested_port > 65535 {
    return Err("HTTP port must be between 0 and 65535")
  }
  let tailnet_config = match service_tailnet_config_from_env() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let root = @fs.realpath(source_root) catch {
    _ => return Err("cannot resolve native service source directory")
  }
  let web_assets_path = match assets_dir {
    Some(path) if path.has_prefix("/") => path
    Some(path) => root + "/" + path
    None => root + "/web"
  }
  let web_root = @fs.realpath(web_assets_path) catch {
    _ => return Err("cannot resolve native service web assets")
  }
  Ok({
    runtime,
    web_root,
    requested_port,
    tailnet_host: tailnet_config.map(config => config.0),
    tailnet_owner: tailnet_config.map(config => config.1),
    tailnet_port: tailnet_config.map(config => config.2).unwrap_or(443),
  })
}

///|
async fn NativeService::run(self : NativeService) -> Result[Unit, String] {
  if c_service_signals_install() != 0 {
    let close_result = @async.protect_from_cancel(async fn() {
      self.runtime.close()
    })
    return match close_result {
      Ok(_) => Err("native service could not install shutdown signal handlers")
      Err(error) =>
        Err(
          "native service could not install shutdown signal handlers; checkpoint failed: " +
          error,
        )
    }
  }
  defer (if c_service_signals_restore() != 0 {
    eprintln("native service could not restore shutdown signal handlers")
  })
  println("native service shutdown signal handlers installed")
  native_flush_stdout()
  let service_result = @async.handle_cancellation(async fn() {
    self.run_listener() catch {
      _ => Err("native service HTTP listener failed unexpectedly")
    }
  })
  let close_result = @async.protect_from_cancel(async fn() {
    self.runtime.close()
  })
  match (service_result, close_result) {
    (None, Ok(_)) => Err("native service was cancelled")
    (None, Err(error)) =>
      Err("native service was cancelled; shutdown checkpoint failed: " + error)
    (Some(Err(error)), Ok(_)) => Err(error)
    (Some(Err(error)), Err(close_error)) =>
      Err(error + "; shutdown checkpoint failed: " + close_error)
    (Some(Ok(_)), Ok(_)) => Ok(())
    (Some(Ok(_)), Err(error)) =>
      Err("native service shutdown checkpoint failed: " + error)
  }
}

///|
async fn NativeService::run_listener(
  self : NativeService,
) -> Result[Unit, String] {
  let address = @socket.Addr::parse(
    "127.0.0.1:" + self.requested_port.to_string(),
  )
  let server = native_service_listener(address)
  defer server.close()
  let port = server.addr.port()
  let local_url = "http://127.0.0.1:" + port.to_string()
  println("native service listening at " + local_url)
  native_flush_stdout()
  if self.runtime.provider_config.demo_provider {
    println(
      "Offline deterministic provider demo is active; no external provider is contacted",
    )
  }
  match (self.tailnet_host, self.tailnet_owner) {
    (Some(host), Some(owner)) => {
      ignore(owner)
      let authority = if self.tailnet_port == 443 {
        host
      } else {
        host + ":" + self.tailnet_port.to_string()
      }
      println("Tailscale Serve mode: https://" + authority)
    }
    _ =>
      println(
        "Local-only mode; configure DSH_TAILNET_HOST and DSH_TAILNET_ALLOWED_USERS for Serve",
      )
  }
  native_flush_stdout()
  @async.with_task_group <| group => {
    let listener = group.spawn(no_wait=true, allow_failure=true, async fn() {
      server.run_forever(max_connections=NATIVE_HTTP_CONNECTION_LIMIT) <| ((
        request,
        _body,
        connection,
      ) => self.handle(request, connection, group, port))
    })
    let mut finished = false
    while !finished {
      let shutdown_signal = c_service_signals_requested()
      if shutdown_signal != 0 {
        let signal_name = if shutdown_signal == 2 {
          "SIGINT"
        } else {
          "SIGTERM"
        }
        println("native service received " + signal_name + "; shutting down")
        native_flush_stdout()
        server.close()
        finished = true
      } else {
        let listener_state = Some(listener.try_wait()) catch { _ => None }
        match listener_state {
          Some(Some(_)) => {
            server.close()
            finished = true
          }
          None => {
            server.close()
            finished = true
          }
          Some(None) => @async.sleep(25)
        }
      }
    }
  }
  if c_service_signals_requested() != 0 {
    Ok(())
  } else {
    Err("native service HTTP listener stopped unexpectedly")
  }
}

///|
async fn native_service_listener(address : @socket.Addr) -> @http.Server {
  @http.Server(address, reuse_addr=true)
}

///|
async fn NativeService::handle(
  self : NativeService,
  request : @http.Request,
  connection : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
  port : Int,
) -> Unit {
  let (path, query) = match request.path.split_once("?") {
    Some((path, query)) => (path.to_owned(), query.to_owned())
    None => (request.path, "")
  }
  let (identity_key, is_local_request) = match
    self.request_identity(request, port) {
    Ok(value) => value
    Err(_) => {
      self.respond_json(connection, 403, {
        "error": "request identity or origin is not authorized",
      })
      return
    }
  }
  match request.meth {
    @http.Get =>
      self.handle_get(path, query, connection, group, port, identity_key)
    @http.Head => self.handle_head(path, connection, port)
    @http.Post =>
      self.handle_post(
        path, request, connection, group, identity_key, is_local_request,
      )
    _ =>
      self.respond_json(connection, 405, { "error": "method is not allowed" }, extra_headers={
        "Allow": "GET, HEAD, POST",
      })
  }
}

///|
fn NativeService::request_identity(
  self : NativeService,
  request : @http.Request,
  port : Int,
) -> Result[(String, Bool), String] {
  let (identity, is_local_request) = match
    service_request_identity(
      request.headers.get("host").unwrap_or(""),
      request.headers.get("origin"),
      request.headers.get("tailscale-user-login"),
      port,
      self.tailnet_host,
      self.tailnet_owner,
      self.tailnet_port,
      self.runtime.state.identity_key,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if identity != self.runtime.state.identity_key {
    return Err("caller identity scope changed")
  }
  Ok((identity, is_local_request))
}

///|
fn service_request_identity(
  host_header : String,
  origin : String?,
  tailscale_login : String?,
  port : Int,
  tailnet_host : String?,
  tailnet_owner : String?,
  tailnet_port : Int,
  local_identity : String,
) -> Result[(String, Bool), String] {
  let expected_ip = "127.0.0.1:" + port.to_string()
  let expected_localhost = "localhost:" + port.to_string()
  let host = host_header.trim().to_lower().to_owned()
  if host == expected_ip || host == expected_localhost {
    match origin {
      None => ()
      Some(value) if value == "http://127.0.0.1:" + port.to_string() ||
        value == "http://localhost:" + port.to_string() => ()
      _ => return Err("local request origin is not allowed")
    }
    if tailscale_login is Some(_) {
      return Err(
        "Tailscale identity headers are invalid on a local-origin request",
      )
    }
    return Ok((local_identity, true))
  }
  match (tailnet_host, tailnet_owner) {
    (Some(expected_host), Some(owner)) => {
      let expected_authority = if tailnet_port == 443 {
        expected_host
      } else {
        expected_host + ":" + tailnet_port.to_string()
      }
      let host_matches = if tailnet_port == 443 {
        host == expected_authority || host == expected_authority + ":443"
      } else {
        host == expected_authority
      }
      if !host_matches {
        return Err("request Host is not an authorized local or Serve origin")
      }
      let expected_origin = "https://" + expected_authority
      match origin {
        None => ()
        Some(value) if value == expected_origin => ()
        _ => return Err("Tailscale request origin is not allowed")
      }
      let login = tailscale_login.unwrap_or("").trim().to_lower().to_owned()
      if login != owner {
        return Err("Tailscale user is missing or not on the owner allowlist")
      }
      let identity_key = "tailscale:" + owner
      Ok((identity_key, false))
    }
    _ => Err("request Host is not an authorized local or Serve origin")
  }
}

///|
async fn NativeService::handle_head(
  self : NativeService,
  path : String,
  connection : @http.ServerConnection,
  port : Int,
) -> Unit {
  match self.static_asset(path) {
    None => self.respond_json(connection, 404, { "error": "not found" })
    Some((asset_path, mime)) => {
      let size = try {
        let file = @fs.open(asset_path, mode=@fs.ReadOnly)
        defer file.close()
        file.size()
      } catch {
        _ => -1L
      }
      if size < 0L || size > 16777216L {
        self.respond_json(connection, 404, { "error": "not found" })
      } else {
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": mime,
          "Content-Length": size.to_string(),
          "Cache-Control": self.cache_control(path),
          "X-Content-Type-Options": "nosniff",
          "Content-Security-Policy": self.content_security_policy(port),
        })
        connection.end_response()
      }
    }
  }
}

///|
async fn NativeService::handle_get(
  self : NativeService,
  path : String,
  query : String,
  connection : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
  port : Int,
  identity_key : String,
) -> Unit {
  if path == "/api/metadata" {
    self.respond_json(connection, 200, {
      "ok": true.to_json(),
      "result": self.metadata(),
    })
    return
  }
  if path == "/api/v1/snapshot" {
    match self.runtime.remote_snapshot(identity_key) {
      Ok(value) => self.respond_json(connection, 200, value)
      Err(error) => self.respond_json(connection, 503, { "error": error })
    }
    return
  }
  if path.has_prefix("/api/v1/sessions/") {
    let session_id = service_decode_component(path[17:].to_owned())
    if session_id.is_empty() || session_id.contains("/") {
      self.respond_json(connection, 400, { "error": "invalid session ID" })
      return
    }
    match self.runtime.remote_session(session_id, identity_key) {
      Ok(value) => self.respond_json(connection, 200, value)
      Err(_) =>
        self.respond_json(connection, 404, { "error": "session not found" })
    }
    return
  }
  if path == "/api/v1/events" {
    let cursor = service_query_value(query, "cursor").unwrap_or("")
    let selected_session = service_query_value(query, "session_id")
    self.serve_events(connection, cursor, selected_session, group, identity_key)
    return
  }
  if path.has_prefix("/api/v1/commands/") {
    let command_id = service_decode_component(path[17:].to_owned())
    if !@protocol.is_uuid_v7_command_id(command_id) {
      self.respond_json(connection, 400, { "error": "invalid command ID" })
      return
    }
    match self.runtime.find_receipt(command_id, identity_key) {
      Ok(Some(receipt)) => self.respond_json(connection, 200, receipt)
      Ok(None) =>
        self.respond_json(connection, 404, { "error": "receipt not found" })
      Err(error) => self.respond_json(connection, 503, { "error": error })
    }
    return
  }
  if path == "/" {
    self.serve_static("/index.html", connection, port)
    return
  }
  self.serve_static(path, connection, port)
}

///|
fn service_provider_hostname(raw_url : String) -> String? {
  let remainder = if raw_url.has_prefix("https://") {
    raw_url[8:].to_owned()
  } else if raw_url.has_prefix("http://") {
    raw_url[7:].to_owned()
  } else {
    return None
  }
  let authority = match remainder.find("/") {
    Some(index) => remainder[:index].to_owned()
    None => remainder
  }
  let authority = match authority.split_once("@") {
    Some((_, host)) => host.to_owned()
    None => authority
  }
  let authority = match authority.find("?") {
    Some(index) => authority[:index].to_owned()
    None => authority
  }
  let authority = match authority.find("#") {
    Some(index) => authority[:index].to_owned()
    None => authority
  }
  let hostname = if authority.has_prefix("[") {
    match authority.find("]") {
      Some(index) => authority[:index + 1].to_owned()
      None => return None
    }
  } else {
    match authority.split_once(":") {
      Some((host, _)) => host.to_owned()
      None => authority
    }
  }
  let hostname = hostname.to_lower()
  let mut suspicious = hostname.has_prefix("sk-") ||
    hostname.has_prefix("sk_") ||
    hostname.contains("sk-") ||
    hostname.contains("sk_") ||
    hostname.contains("api_key") ||
    hostname.contains("api-key") ||
    hostname.contains("token") ||
    hostname.contains("secret") ||
    hostname.contains("password")
  let mut hexadecimal_run = 0
  for ch in hostname {
    let code = ch.to_int()
    if (code >= 48 && code <= 57) || (code >= 97 && code <= 102) {
      hexadecimal_run += 1
      if hexadecimal_run >= 32 {
        suspicious = true
      }
    } else {
      hexadecimal_run = 0
    }
  }
  if hostname.is_empty() ||
    hostname.length() > 253 ||
    suspicious ||
    hostname.contains("@") {
    return None
  }
  let mut valid = true
  if hostname.has_prefix("[") {
    for ch in hostname[1:hostname.length() - 1] {
      let code = ch.to_int()
      if !((code >= 48 && code <= 57) ||
        (code >= 97 && code <= 102) ||
        code == 58) {
        valid = false
      }
    }
  } else {
    for ch in hostname {
      let code = ch.to_int()
      if !((code >= 48 && code <= 57) ||
        (code >= 97 && code <= 122) ||
        code == 45 ||
        code == 46) {
        valid = false
      }
    }
  }
  if valid {
    Some(hostname)
  } else {
    None
  }
}

///|
fn service_provider_label(config : NativeProviderConfig) -> String {
  if config.demo_provider {
    return "デモ"
  }
  if config.auth_mode == NativeAuthMode::ChatGPT {
    return "ChatGPT"
  }
  let protocol_label = match config.protocol {
    NativeProtocol::DeepSeekMessages => "DeepSeek"
    NativeProtocol::OpenAIChatCompletions => "OpenAI 互換 API"
    NativeProtocol::OpenAIResponses => "OpenAI Responses API"
  }
  let default_url = match config.protocol {
    NativeProtocol::DeepSeekMessages => "https://api.deepseek.com/anthropic"
    NativeProtocol::OpenAIChatCompletions => "https://api.openai.com"
    NativeProtocol::OpenAIResponses => "https://api.openai.com"
  }
  let hostname = match
    service_provider_hostname(config.base_url.unwrap_or(default_url)) {
    Some(value) => value
    None => return protocol_label
  }
  if hostname == "localhost" || hostname == "127.0.0.1" || hostname == "[::1]" {
    return "ローカル API"
  }
  if hostname == "api.deepseek.com" || hostname.has_suffix(".deepseek.com") {
    return "DeepSeek"
  }
  if hostname == "api.openai.com" || hostname.has_suffix(".openai.com") {
    return if config.protocol == NativeProtocol::OpenAIResponses {
      "OpenAI Responses API"
    } else {
      "OpenAI"
    }
  }
  hostname
}

///|
fn service_model_display_name(value : String) -> String {
  let model = value.trim().to_owned()
  if model.is_empty() || model.length() > 128 {
    return "カスタムモデル"
  }
  let lower_model = model.to_lower()
  if lower_model.contains("sk-") ||
    lower_model.contains("sk_") ||
    lower_model.contains("api-key") ||
    lower_model.contains("api_key") ||
    lower_model.contains("token") ||
    lower_model.contains("secret") ||
    lower_model.contains("password") {
    return "カスタムモデル"
  }
  let mut valid = true
  let mut identifier_only = true
  for ch in model {
    let code = ch.to_int()
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95 ||
      code == 46 ||
      code == 58 ||
      code == 47 ||
      code == 43 ||
      code == 45) {
      valid = false
    }
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95 ||
      code == 45) {
      identifier_only = false
    }
  }
  if identifier_only && model.length() >= 40 {
    valid = false
  }
  if valid {
    model
  } else {
    "カスタムモデル"
  }
}

///|
async fn NativeService::metadata(self : NativeService) -> Json {
  let provider_config = self.runtime.provider_config
  let model = if provider_config.auth_mode == NativeAuthMode::ChatGPT {
    string_field(self.runtime.auth.status(), "selected_model").unwrap_or(
      provider_config.model,
    )
  } else {
    provider_config.model
  }
  {
    "project": native_workspace_basename(self.runtime.tools.workspace).to_json(),
    "repository": self.runtime.tools.repository_metadata(),
    "provider": service_provider_label(provider_config).to_json(),
    "model": service_model_display_name(model).to_json(),
  }
}

///|
async fn NativeService::handle_post(
  self : NativeService,
  path : String,
  request : @http.Request,
  connection : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
  identity_key : String,
  is_local_request : Bool,
) -> Unit {
  let site = request.headers.get("sec-fetch-site").unwrap_or("")
  if site == "cross-site" {
    self.respond_json(connection, 403, {
      "error": "cross-site requests are not allowed",
    })
    return
  }
  let content_type = request.headers.get("content-type").unwrap_or("")
  let media_type = match content_type.split_once(";") {
    Some((media, _)) => media.to_owned()
    None => content_type
  }
  if media_type.trim().to_lower() != "application/json" {
    self.respond_json(connection, 415, {
      "error": "application/json is required",
    })
    return
  }
  if request.headers.get("content-length") is Some(length) &&
    service_parse_int(length) is Some(size) &&
    size > NATIVE_HTTP_BODY_LIMIT {
    self.respond_json(connection, 413, { "error": "request body is too large" })
    connection.close()
    return
  }
  let body = match service_read_body(connection) {
    Ok(value) => value
    Err(error) => {
      self.respond_json(connection, 413, { "error": error })
      connection.close()
      return
    }
  }
  if path == "/mcp" {
    match self.runtime.mcp_handle(body, group) {
      Err(error) => self.respond_json(connection, 503, { "error": error })
      Ok(response) =>
        if response.is_empty() {
          connection.send_response(202, "Accepted", extra_headers={
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
          })
          connection.end_response()
        } else {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
          })
          connection.write_string(response)
          connection.end_response()
        }
    }
  } else if path == "/api/v1/commands" {
    self.handle_command(body, connection, group, identity_key)
  } else if path == "/api/call" {
    self.handle_call(body, connection, group, is_local_request)
  } else {
    self.respond_json(connection, 404, { "error": "not found" })
  }
}

///|
async fn NativeService::handle_command(
  self : NativeService,
  body : String,
  connection : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
  identity_key : String,
) -> Unit {
  let command = match @protocol.RemoteCommand::parse(body) {
    Ok(value) => value
    Err(error) => {
      self.respond_json(connection, 400, { "error": error })
      return
    }
  }
  match self.runtime.accept_remote_command(command, identity_key) {
    Err(error) => self.respond_json(connection, 409, { "error": error })
    Ok((receipt, effects, should_start, control)) => {
      if should_start {
        let command_id = string_field(receipt, "command_id").unwrap_or("")
        let accepted_revision = int_field(receipt, "accepted_revision").unwrap_or(
          0,
        )
        group.spawn_bg(no_wait=true) <| () => {
          self.runtime.run_command_job(
            command_id,
            identity_key,
            accepted_revision,
            effects,
            control~,
          )
        }
      }
      self.respond_json(connection, 202, receipt)
    }
  }
}

///|
async fn NativeService::handle_call(
  self : NativeService,
  body : String,
  connection : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
  is_local_request : Bool,
) -> Unit {
  let value = @json.parse(body) catch {
    _ => {
      self.respond_json(connection, 400, {
        "ok": false,
        "error": "invalid JSON",
      })
      return
    }
  }
  let operation = string_field(value, "operation").unwrap_or("")
  let input = object_field(value, "input").unwrap_or(Json::empty_object())
  match operation {
    "auth_status" =>
      self.respond_json(connection, 200, {
        "ok": true,
        "result": self.runtime.auth.status(),
      })
    "auth_sign_in" =>
      if !is_local_request {
        self.respond_json(connection, 403, {
          "ok": false,
          "error": "Open dsh on the host computer to start or switch ChatGPT sign-in.",
        })
      } else {
        match self.runtime.auth.begin_sign_in() {
          Err(error) => self.auth_error(connection, error)
          Ok(started) => {
            if native_json_true(object_field(started, "started")) {
              group.spawn_bg(no_wait=true) <| () => {
                match self.runtime.auth.sign_in() {
                  Ok(_) => ignore(self.runtime.touch_projection())
                  Err(_) => ignore(self.runtime.touch_projection())
                }
              }
            }
            self.respond_json(connection, 202, { "ok": true, "result": started })
          }
        }
      }
    "auth_sign_in_browser" =>
      if !is_local_request {
        self.respond_json(connection, 403, {
          "ok": false,
          "error": "Open dsh on the host computer to start or switch ChatGPT sign-in.",
        })
      } else {
        match self.runtime.auth.prepare_browser_sign_in() {
          Err(error) => self.auth_error(connection, error)
          Ok(None) =>
            self.respond_json(connection, 202, {
              "ok": true,
              "result": { "started": false },
            })
          Ok(Some(prepared)) => {
            let authorization_url = prepared.authorization_url
            group.spawn_bg(no_wait=true) <| () => {
              match self.runtime.auth.finish_browser_sign_in(prepared) {
                Ok(_) => ignore(self.runtime.touch_projection())
                Err(_) => ignore(self.runtime.touch_projection())
              }
            }
            self.respond_json(connection, 202, {
              "ok": true,
              "result": {
                "started": true,
                "authorization_url": authorization_url,
              },
            })
          }
        }
      }
    "auth_sign_out" => {
      let requested_profile = string_field(input, "profile_id").unwrap_or("")
      let current = self.runtime.auth.status()
      let active_profile = string_field(
        object_field(current, "account").unwrap_or(Json::null()),
        "profile_id",
      ).unwrap_or("")
      if requested_profile.is_empty() || requested_profile != active_profile {
        self.respond_json(connection, 409, {
          "ok": false,
          "error": "the selected ChatGPT profile is no longer active",
        })
      } else {
        match self.runtime.auth.sign_out() {
          Ok(result) =>
            match self.runtime.touch_projection() {
              Ok(_) =>
                self.respond_json(connection, 200, {
                  "ok": true,
                  "result": result,
                })
              Err(error) =>
                self.respond_json(connection, 503, {
                  "ok": false,
                  "error": error,
                })
            }
          Err(error) => self.auth_error(connection, error)
        }
      }
    }
    "auth_models" =>
      match self.runtime.auth.models() {
        Ok(result) =>
          match self.runtime.touch_projection() {
            Ok(_) =>
              self.respond_json(connection, 200, {
                "ok": true,
                "result": result,
              })
            Err(error) =>
              self.respond_json(connection, 503, { "ok": false, "error": error })
          }
        Err(error) => self.auth_error(connection, error)
      }
    "auth_select_model" => {
      let model = string_field(input, "model").unwrap_or("")
      match self.runtime.auth.select_model(model) {
        Ok(result) =>
          match self.runtime.touch_projection() {
            Ok(_) =>
              self.respond_json(connection, 200, {
                "ok": true,
                "result": result,
              })
            Err(error) =>
              self.respond_json(connection, 503, { "ok": false, "error": error })
          }
        Err(error) => self.auth_error(connection, error)
      }
    }
    _ =>
      self.respond_json(connection, 404, {
        "ok": false,
        "error": "unknown operation",
      })
  }
}

///|
async fn NativeService::auth_error(
  self : NativeService,
  connection : @http.ServerConnection,
  error : String,
) -> Unit {
  let status = if error.has_prefix("AUTH_REQUIRED") ||
    error.has_prefix("AUTH_DIRECT_SCOPE_REQUIRED") {
    401
  } else if error.has_prefix("AUTH_ACCOUNT_CHANGED") ||
    error.has_prefix("INVALID_MODEL") ||
    error.has_prefix("MODEL_REQUIRED") {
    409
  } else {
    502
  }
  self.respond_json(connection, status, { "ok": false, "error": error })
}

///|
async fn NativeService::serve_events(
  self : NativeService,
  connection : @http.ServerConnection,
  initial_cursor : String,
  selected_session : String?,
  _group : @async.TaskGroup[Unit],
  identity_key : String,
) -> Unit {
  connection.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-store, must-revalidate",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
    "X-Content-Type-Options": "nosniff",
  })
  let mut cursor = initial_cursor
  let mut heartbeat = 0
  let mut keep_open = true
  while keep_open {
    let snapshot = match
      self.runtime.remote_snapshot(identity_key, selected_session~) {
      Ok(value) => value
      Err(_) => {
        keep_open = false
        continue
      }
    }
    let current = string_field(snapshot, "cursor").unwrap_or("")
    if current != cursor {
      let (kind, data) = service_event(snapshot, cursor, current)
      let frame = "id: " +
        current +
        "\nevent: " +
        kind +
        "\ndata: " +
        data.stringify() +
        "\n\n"
      let wrote = try {
        connection.write_string(frame)
        connection.flush()
        true
      } catch {
        _ => false
      }
      if !wrote {
        keep_open = false
      } else {
        cursor = current
        heartbeat = 0
      }
    } else {
      @async.sleep(500)
      heartbeat += 1
      if heartbeat >= 30 {
        let wrote = try {
          connection.write_string(": keep-alive\n\n")
          connection.flush()
          true
        } catch {
          _ => false
        }
        if !wrote {
          keep_open = false
        }
        heartbeat = 0
      }
    }
  }
}

///|
fn service_event(
  snapshot : Json,
  previous : String,
  current : String,
) -> (String, Json) {
  let previous_parts = previous
    .split(":")
    .map(value => value.to_owned())
    .to_array()
  let current_parts = current
    .split(":")
    .map(value => value.to_owned())
    .to_array()
  let mut contiguous = false
  if previous_parts.length() == 3 &&
    current_parts.length() == 3 &&
    previous_parts[0] == current_parts[0] &&
    previous_parts[1] == current_parts[1] {
    match
      (
        service_parse_int(previous_parts[2]),
        service_parse_int(current_parts[2]),
      ) {
      (Some(last), Some(now)) => contiguous = now == last + 1
      _ => ()
    }
  }
  let projection = object_field(snapshot, "projection").unwrap_or(Json::null())
  let kind = if contiguous { "projection" } else { "resync" }
  (
    kind,
    {
      "protocol_version": 1,
      "workspace_id": object_field(snapshot, "workspace_id").unwrap_or(
        Json::null(),
      ),
      "identity_key": object_field(snapshot, "identity_key").unwrap_or(
        Json::null(),
      ),
      "auth_revision": object_field(snapshot, "auth_revision").unwrap_or(
        Json::null(),
      ),
      "epoch": object_field(snapshot, "epoch").unwrap_or(Json::null()),
      "revision": object_field(snapshot, "revision").unwrap_or(Json::null()),
      "cursor": current.to_json(),
      "kind": kind.to_json(),
      "projection": projection,
    },
  )
}

///|
async fn NativeService::serve_static(
  self : NativeService,
  path : String,
  connection : @http.ServerConnection,
  port : Int,
) -> Unit {
  match self.static_asset(path) {
    None => self.respond_json(connection, 404, { "error": "not found" })
    Some((asset_path, mime)) => {
      let contents = @fs.read_file(asset_path).text() catch {
        _ => {
          self.respond_json(connection, 404, { "error": "asset not found" })
          return
        }
      }
      if contents.length() > 16777216 {
        self.respond_json(connection, 404, { "error": "asset not found" })
        return
      }
      connection.send_response(200, "OK", extra_headers={
        "Content-Type": mime,
        "Cache-Control": self.cache_control(path),
        "X-Content-Type-Options": "nosniff",
        "Content-Security-Policy": self.content_security_policy(port),
        "Referrer-Policy": "no-referrer",
      })
      connection.write_string(contents)
      connection.end_response()
    }
  }
}

///|
fn NativeService::static_asset(
  self : NativeService,
  path : String,
) -> (String, String)? {
  let (relative, mime) = match path {
    "/index.html" => ("index.html", "text/html; charset=utf-8")
    "/moonbit/browser.js" =>
      return Some(
        (
          self.web_root + "/moonbit/browser.js",
          "text/javascript; charset=utf-8",
        ),
      )
    "/kumo-standalone.css" => ("kumo-standalone.css", "text/css; charset=utf-8")
    "/yami-kumo-components.css" =>
      ("yami-kumo-components.css", "text/css; charset=utf-8")
    "/yami-kumo-shell.css" => ("yami-kumo-shell.css", "text/css; charset=utf-8")
    "/manifest.webmanifest" =>
      ("manifest.webmanifest", "application/manifest+json")
    "/icon.svg" => ("icon.svg", "image/svg+xml")
    "/sw.js" => ("sw.js", "text/javascript; charset=utf-8")
    _ => return None
  }
  Some((self.web_root + "/" + relative, mime))
}

///|
fn NativeService::cache_control(self : NativeService, path : String) -> String {
  ignore(self)
  if path == "/" || path == "/index.html" || path.has_prefix("/api/") {
    "no-cache, no-store, must-revalidate"
  } else {
    "public, max-age=300"
  }
}

///|
fn NativeService::content_security_policy(
  self : NativeService,
  port : Int,
) -> String {
  ignore(self)
  "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " +
  "connect-src 'self' http://127.0.0.1:\{port} http://localhost:\{port}; " +
  "object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
}

///|
async fn NativeService::respond_json(
  self : NativeService,
  connection : @http.ServerConnection,
  status : Int,
  body : Json,
  extra_headers? : @http.Headers = {},
) -> Unit {
  ignore(self)
  let reason = match status {
    200 => "OK"
    202 => "Accepted"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    409 => "Conflict"
    413 => "Payload Too Large"
    415 => "Unsupported Media Type"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "Error"
  }
  let headers : @http.Headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  }
  for key, value in extra_headers {
    headers[key] = value
  }
  connection.send_response(status, reason, extra_headers=headers)
  connection.write_string(body.stringify())
  connection.end_response()
}

///|
async fn service_read_body(
  connection : @http.ServerConnection,
) -> Result[String, String] {
  let bytes : Array[Byte] = []
  while connection.read_some(max_len=8192) is Some(chunk) {
    if bytes.length() + chunk.length() > NATIVE_HTTP_BODY_LIMIT {
      return Err("request body exceeds the 1 MiB limit")
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  let value = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("request body must be UTF-8")
  }
  Ok(value)
}

///|
fn service_query_value(query : String, name : String) -> String? {
  for pair in query.split("&") {
    match pair.split_once("=") {
      Some((key, value)) if service_decode_component(key.to_owned()) == name =>
        return Some(service_decode_component(value.to_owned()))
      _ => ()
    }
  }
  None
}

///|
fn service_decode_component(value : String) -> String {
  let bytes : Array[Byte] = []
  let raw = @utf8.encode(value)
  let mut index = 0
  while index < raw.length() {
    if raw[index] == b'%' && index + 2 < raw.length() {
      match
        (service_hex_value(raw[index + 1]), service_hex_value(raw[index + 2])) {
        (Some(high), Some(low)) => {
          bytes.push((high * 16 + low).to_byte())
          index += 3
        }
        _ => {
          bytes.push(raw[index])
          index += 1
        }
      }
    } else if raw[index] == b'+' {
      bytes.push(b' ')
      index += 1
    } else {
      bytes.push(raw[index])
      index += 1
    }
  }
  @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => ""
  }
}

///|
fn service_hex_value(value : Byte) -> Int? {
  let value = value.to_int()
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
fn service_parse_int(value : String) -> Int? {
  if value.is_empty() || value.length() > 10 {
    return None
  }
  let mut result = 0
  for digit in value {
    if digit < '0' || digit > '9' {
      return None
    }
    result = result * 10 + (digit.to_int() - '0'.to_int())
  }
  Some(result)
}
