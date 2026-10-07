///|
fn native_flag(args : Array[String], name : String) -> Bool {
  args.any(value => value == name)
}

///|
fn native_option(args : Array[String], name : String) -> String? {
  for index = 0; index + 1 < args.length(); index = index + 1 {
    if args[index] == name {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn native_worker_payload(args : Array[String]) -> Result[Bytes, String] {
  if args.length() < 8 ||
    args[1] != "--internal-worker" ||
    !args[6].has_prefix("/") {
    return Err("invalid internal worker arguments")
  }
  let payload = StringBuilder()
  for index in [2, 3, 4, 5] {
    if args[index].contains("\u0000") {
      return Err("invalid internal worker argument")
    }
    payload.write_string(args[index])
    payload.write_char('\u0000')
  }
  if args[6].contains("\u0000") {
    return Err("invalid internal worker workspace")
  }
  payload.write_string(args[6])
  payload.write_char('\u0000')
  payload.write_string((args.length() - 7).to_string())
  payload.write_char('\u0000')
  for index = 7; index < args.length(); index = index + 1 {
    if args[index].contains("\u0000") {
      return Err("process arguments cannot contain NUL")
    }
    let encoded = @utf8.encode(args[index])
    payload.write_string(encoded.length().to_string())
    payload.write_char(':')
    payload.write_string(args[index])
    payload.write_char('\u0000')
  }
  Ok(@utf8.encode(payload.to_string()))
}

///|
fn native_usage() -> String {
  "dsh native runtime\n\n" +
  "Usage:\n" +
  "  dsh-native --help\n" +
  "  dsh-native --demo --data-dir PATH --workspace PATH\n\n" +
  "  dsh-native --run PROMPT [--session ID] [--demo] --data-dir PATH --workspace PATH\n" +
  "  dsh-native --fork SESSION_ID [--demo] --data-dir PATH --workspace PATH\n" +
  "  dsh-native --session ID --approve-call CALL_ID --approval-revision REV [--demo] --data-dir PATH --workspace PATH\n" +
  "  dsh-native --session ID --deny-call CALL_ID --approval-revision REV [--demo] --data-dir PATH --workspace PATH\n" +
  "  dsh-native --auth-status|--sign-in|--models|--sign-out|--select-model MODEL --data-dir PATH --workspace PATH\n\n" +
  "  dsh-native --serve --data-dir PATH --workspace PATH [--port PORT] [--allow-shell] [--demo]\n\n" +
  "The demo checkpoints a session, gates a write call on approval, runs the\n" +
  "workspace tool, feeds its result into the next model context, and verifies\n" +
  "that the completed session reloads from the native snapshot."
}

///|
fn native_command_id() -> Result[String, String] {
  let entropy = match random_hex(16) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  @protocol.uuid_v7_command_id_from_entropy(
    native_auth_now().to_int64() * 1000L,
    entropy,
  )
}

///|
async fn native_cli_command(
  runtime : NativeRuntime,
  session_id : String?,
  operation : String,
  input : Json,
  approval_revision : Int?,
) -> Result[Json, String] {
  let command_id = match native_command_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let command_json = Json::object({
    "protocol_version": Json::number(1.0),
    "workspace_id": Json::string(runtime.state.workspace_id),
    "command_id": Json::string(command_id),
    "session_id": session_id
    .map(value => Json::string(value))
    .unwrap_or(Json::null()),
    "operation": Json::string(operation),
    "input": input,
    "approval_revision": approval_revision
    .map(value => Json::number(value.to_double()))
    .unwrap_or(Json::null()),
  })
  let command = match @protocol.RemoteCommand::parse(command_json.stringify()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let identity_key = runtime.state.identity_key
  let (receipt, effects, should_start) = match
    runtime.accept_remote_command(command, identity_key) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if should_start {
    let accepted_revision = int_field(receipt, "accepted_revision").unwrap_or(0)
    runtime.run_command_job(
      command_id, identity_key, accepted_revision, effects,
    )
  }
  match runtime.find_receipt(command_id, identity_key) {
    Ok(Some(value)) => Ok(value)
    Ok(None) => Err("native command receipt disappeared")
    Err(error) => Err(error)
  }
}

///|
fn native_cli_approval_revision(session : Json) -> Json {
  let pending = match object_field(session, "pending_approval") {
    Some(value) => value
    None => return Json::null()
  }
  let call_id = string_field(pending, "call_id")
  match object_field(session, "events") {
    Some(Json::Array(events)) =>
      for event in events {
        if string_field(event, "type") == Some("tool/approval/requested") &&
          string_field(
            object_field(event, "data").unwrap_or(Json::null()),
            "call_id",
          ) ==
          call_id {
          return int_field(event, "seq")
            .map(value => value.to_json())
            .unwrap_or(Json::null())
        }
      }
    _ => ()
  }
  Json::null()
}

///|
async fn native_cli_action(
  runtime : NativeRuntime,
  args : Array[String],
) -> Result[Json, String] {
  if native_flag(args, "--auth-status") {
    return Ok(runtime.auth.status())
  }
  if native_flag(args, "--sign-in") {
    let result = match runtime.auth.sign_in() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return match runtime.touch_projection() {
      Ok(_) => Ok(result)
      Err(error) => Err(error)
    }
  }
  if native_flag(args, "--sign-out") {
    let result = match runtime.auth.sign_out() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return match runtime.touch_projection() {
      Ok(_) => Ok(result)
      Err(error) => Err(error)
    }
  }
  if native_flag(args, "--models") {
    let result = match runtime.auth.models() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return match runtime.touch_projection() {
      Ok(_) => Ok(result)
      Err(error) => Err(error)
    }
  }
  match native_option(args, "--select-model") {
    Some(model) => {
      let result = match runtime.auth.select_model(model) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      return match runtime.touch_projection() {
        Ok(_) => Ok(result)
        Err(error) => Err(error)
      }
    }
    None => ()
  }

  let prompt = native_option(args, "--run")
  let fork_source = native_option(args, "--fork")
  let approve_call = native_option(args, "--approve-call")
  let deny_call = native_option(args, "--deny-call")
  let requested_session = native_option(args, "--session")
  if fork_source is Some(_) &&
    (
      prompt is Some(_) ||
      approve_call is Some(_) ||
      deny_call is Some(_) ||
      requested_session is Some(_)
    ) {
    return Err(
      "--fork cannot be combined with run, session, or approval actions",
    )
  }
  if prompt is Some(_) && (approve_call is Some(_) || deny_call is Some(_)) {
    return Err("--run cannot be combined with approval flags")
  }
  if approve_call is Some(_) && deny_call is Some(_) {
    return Err("choose either --approve-call or --deny-call")
  }
  if prompt is None &&
    fork_source is None &&
    approve_call is None &&
    deny_call is None {
    return Err("no native CLI action was selected")
  }
  let mut session_id = requested_session
  let mut receipt : Json? = None
  match fork_source {
    Some(source_id) => {
      let fork_receipt = match
        native_cli_command(runtime, Some(source_id), "session_fork", {}, None) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let child = match object_field(fork_receipt, "result") {
        Some(value) => value
        None => return Err("native fork receipt has no child session")
      }
      session_id = match string_field(child, "id") {
        Some(value) => Some(value)
        None => return Err("native fork receipt has no child session ID")
      }
      receipt = Some(fork_receipt)
    }
    None => ()
  }

  if prompt is Some(_) && session_id is None {
    let generated = match random_uuid() {
      Ok(value) => "session-" + value
      Err(error) => return Err(error)
    }
    let create_receipt = match
      native_cli_command(
        runtime,
        None,
        "session_create",
        { "id": generated.to_json(), "title": "Native CLI session".to_json() },
        None,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if string_field(create_receipt, "status") != Some("completed") {
      return Ok(create_receipt)
    }
    session_id = Some(generated)
    receipt = Some(create_receipt)
  }
  let active_session = match session_id {
    Some(value) => value
    None => return Err("--session ID is required for this action")
  }
  match prompt {
    Some(prompt_text) => {
      let sent = match
        native_cli_command(
          runtime,
          Some(active_session),
          "session_send",
          { "prompt": prompt_text.to_json() },
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      receipt = Some(sent)
    }
    None =>
      match (approve_call, deny_call) {
        (Some(call_id), None) | (None, Some(call_id)) => {
          let approved = approve_call is Some(_)
          let revision = match native_option(args, "--approval-revision") {
            Some(value) =>
              match service_parse_int(value) {
                Some(parsed) if parsed >= 0 => parsed
                _ =>
                  return Err(
                    "--approval-revision must be a nonnegative integer",
                  )
              }
            None =>
              return Err("approval decision requires --approval-revision REV")
          }
          let decision = match
            native_cli_command(
              runtime,
              Some(active_session),
              "tool_approve",
              { "call_id": call_id.to_json(), "approved": approved.to_json() },
              Some(revision),
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          receipt = Some(decision)
        }
        _ => ()
      }
  }
  let session = match
    runtime.invoke("session_get", { "session_id": active_session }) {
    Ok((value, _)) => value
    Err(error) => return Err(error)
  }
  Ok({
    "session_id": active_session.to_json(),
    "receipt": receipt.unwrap_or(Json::null()),
    "approval_revision": native_cli_approval_revision(session),
    "session": session,
  })
}

///|
async fn main {
  let args = @env.args()
  native_configure_service_signal_policy()
  if native_flag(args, "--internal-worker") {
    let payload = match native_worker_payload(args) {
      Ok(value) => value
      Err(error) => abort(error)
    }
    let status = native_exec_worker(payload)
    abort(
      "native process worker could not start (OS error " +
      status.to_string() +
      ")",
    )
  }
  if native_flag(args, "--help") || native_flag(args, "-h") {
    println(native_usage())
    return
  }
  if native_flag(args, "--serve") {
    let data_dir = match native_option(args, "--data-dir") {
      Some(value) => value
      None => abort("--serve requires --data-dir PATH")
    }
    let workspace = match native_option(args, "--workspace") {
      Some(value) => value
      None => abort("--serve requires --workspace PATH")
    }
    let port = match native_option(args, "--port") {
      Some(value) =>
        match service_parse_int(value) {
          Some(value) if value >= 0 && value <= 65535 => value
          _ => abort("--port must be between 0 and 65535")
        }
      None => 3210
    }
    let source_root = match @env.current_dir() {
      Some(value) => value
      None => abort("cannot determine native service source directory")
    }
    let runtime = match
      NativeRuntime::open(
        data_dir,
        workspace,
        native_flag(args, "--allow-shell"),
        native_flag(args, "--demo"),
      ) {
      Err(error) => abort("native runtime could not start: " + error)
      Ok(runtime) => runtime
    }
    let service = match NativeService::new(runtime, source_root, port) {
      Err(error) => {
        ignore(runtime.close())
        abort("native service could not start: " + error)
      }
      Ok(service) => service
    }
    match service.run() {
      Ok(_) => ()
      Err(error) => abort("native service failed: " + error)
    }
    return
  }
  let cli_action = native_flag(args, "--auth-status") ||
    native_flag(args, "--sign-in") ||
    native_flag(args, "--sign-out") ||
    native_flag(args, "--models") ||
    native_option(args, "--select-model") is Some(_) ||
    native_option(args, "--run") is Some(_) ||
    native_option(args, "--fork") is Some(_) ||
    native_option(args, "--approve-call") is Some(_) ||
    native_option(args, "--deny-call") is Some(_)
  if cli_action {
    let data_dir = match native_option(args, "--data-dir") {
      Some(value) => value
      None => abort("native CLI actions require --data-dir PATH")
    }
    let workspace = match native_option(args, "--workspace") {
      Some(value) => value
      None => abort("native CLI actions require --workspace PATH")
    }
    let runtime = match
      NativeRuntime::open(
        data_dir,
        workspace,
        native_flag(args, "--allow-shell"),
        native_flag(args, "--demo"),
      ) {
      Err(error) => abort("native runtime could not start: " + error)
      Ok(runtime) => runtime
    }
    let output = match native_cli_action(runtime, args) {
      Ok(value) => value
      Err(error) => {
        ignore(runtime.close())
        abort("native CLI action failed: " + error)
      }
    }
    match runtime.close() {
      Err(error) => abort("native runtime shutdown failed: " + error)
      Ok(_) => println(output.stringify())
    }
    return
  }
  if !native_flag(args, "--demo") {
    println(native_usage())
    return
  }
  let data_dir = match native_option(args, "--data-dir") {
    Some(value) => value
    None => abort("--demo requires --data-dir PATH")
  }
  let workspace = match native_option(args, "--workspace") {
    Some(value) => value
    None => abort("--demo requires --workspace PATH")
  }
  match NativeRuntime::open(data_dir, workspace, false, false) {
    Err(error) => abort("native runtime could not start: " + error)
    Ok(runtime) =>
      match runtime.run_demo() {
        Err(error) => {
          ignore(runtime.close())
          abort("native runtime demo failed: " + error)
        }
        Ok(demo_id) => {
          match runtime.close() {
            Err(error) => abort("native runtime shutdown failed: " + error)
            Ok(_) => ()
          }
          match verify_native_demo_reload(data_dir, workspace, demo_id) {
            Err(error) => abort("native runtime reload check failed: " + error)
            Ok(_) =>
              println(
                "native runtime demo passed: checkpoint, approval, tool, context, persisted reload",
              )
          }
        }
      }
  }
}
