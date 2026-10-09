///|
/// A local native-UI handle over the same durable runtime used by the CLI and
/// local service. Commands are accepted and checkpointed before their effects
/// are dispatched to the caller's task group.
pub struct NativeDesktop {
  priv runtime : NativeRuntime
}

///|
/// Open a local desktop session using the existing native runtime and store.
/// The demo provider is deterministic and never contacts an external service.
pub async fn NativeDesktop::open(
  data_dir : String,
  workspace : String,
  demo? : Bool = false,
  allow_shell? : Bool = false,
  mode? : String = "",
  model? : String = "",
  base_url? : String = "",
  max_retries? : Int = 5,
) -> Result[NativeDesktop, String] {
  // A packaged Dsh.app carries the CLI as a private helper because native
  // tool effects re-enter the executable with --internal-worker.
  if @env.get_env_var("DSH_NATIVE_WORKER_BIN") is None {
    match native_executable_path() {
      Ok(executable) => {
        let components = executable.split("/").to_array()
        let count = components.length()
        if count >= 4 &&
          components[count - 3] == "Contents" &&
          components[count - 2] == "MacOS" {
          let bundle_root = components[:count - 3].join("/")
          let candidate = bundle_root + "/Contents/Helpers/dsh"
          let helper = @fs.realpath(candidate) catch { _ => "" }
          if helper != "" {
            @env.set_env_var("DSH_NATIVE_WORKER_BIN", helper)
          }
        }
      }
      Err(_) => ()
    }
  }
  match
    NativeRuntime::open(
      data_dir,
      workspace,
      allow_shell,
      demo,
      mode_override=mode,
      model_override=model,
      base_url_override=base_url,
      max_retries~,
    ) {
    Err(error) => Err(error)
    Ok(runtime) => Ok({ runtime, })
  }
}

///|
/// Return the persisted workspace snapshot and, when requested, one selected
/// transcript. Session details are passed through the runtime's safe local
/// projection, the same one used by the native service.
pub async fn NativeDesktop::snapshot(
  self : NativeDesktop,
  selected_session : String?,
) -> Result[Json, String] {
  self.runtime.remote_snapshot(
    self.runtime.state.identity_key,
    selected_session~,
  )
}

///|
/// Submit a protocol command through the durable native command boundary.
/// Provider and tool effects run in the supplied background task group so the
/// UI event loop stays responsive while a turn is active.
pub async fn[X] NativeDesktop::command(
  self : NativeDesktop,
  operation : String,
  session_id : String?,
  input : Json,
  approval_revision : Int?,
  group : @async.TaskGroup[X],
) -> Result[Json, String] {
  if operation == "tool_approve" {
    match session_id {
      Some(id) => {
        let mut attempts = 0
        while attempts < 80 {
          match self.runtime.scheduler.await_idle(id) {
            Ok(_) => break
            Err(error) if error ==
              "a native effect job is still active for this session" => {
              // The projection can expose an approval a few event-loop turns
              // before the provider job has released its scheduler slot. Give
              // that job a bounded chance to settle before accepting approval.
              @async.sleep(10)
              attempts += 1
            }
            Err(error) => return Err(error)
          }
        }
        if attempts >= 80 {
          return Err("native effect job did not settle before tool approval")
        }
      }
      None => return Err("tool approval requires a session id")
    }
  }
  let command_id = match native_command_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let command_json = Json::object({
    "protocol_version": Json::number(1.0),
    "workspace_id": Json::string(self.runtime.state.workspace_id),
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
  let identity_key = self.runtime.state.identity_key
  let (receipt, effects, should_start, control) = match
    self.runtime.accept_remote_command(command, identity_key) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if should_start {
    let accepted_revision = int_field(receipt, "accepted_revision").unwrap_or(0)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      self.runtime.run_command_job(
        command_id,
        identity_key,
        accepted_revision,
        effects,
        control~,
      )
    }
  }
  Ok(receipt)
}

///|
/// Cancel active sessions before checkpointing and closing the runtime.
/// Accepted tool or provider work is allowed to unwind before the store closes.
pub async fn NativeDesktop::close(self : NativeDesktop) -> Result[Unit, String] {
  let snapshot = match
    self.runtime.remote_snapshot(self.runtime.state.identity_key) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let projection = match object_field(snapshot, "projection") {
    Some(value) => value
    None => return Err("native snapshot has no projection")
  }
  let sessions = match object_field(projection, "sessions") {
    Some(Json::Array(values)) => values
    _ => return Err("native snapshot session list is invalid")
  }
  for session in sessions {
    let session_id = string_field(session, "id").unwrap_or("")
    let status = string_field(session, "status").unwrap_or("")
    if session_id != "" &&
      (status == "running" || status == "awaiting_approval") {
      match
        native_cli_command(
          self.runtime,
          Some(session_id),
          "session_cancel",
          {},
          None,
        ) {
        Ok(_) => ()
        Err(error) => {
          ignore(self.runtime.close())
          return Err("cannot cancel active desktop session: " + error)
        }
      }
      match self.runtime.scheduler.await_idle(session_id) {
        Ok(_) => ()
        Err(error) => {
          ignore(self.runtime.close())
          return Err(error)
        }
      }
    }
  }
  self.runtime.close()
}
