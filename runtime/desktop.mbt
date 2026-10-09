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
  mcp_config_path? : String? = None,
  enable_skills? : Bool = false,
  skill_dirs? : Array[String] = [],
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
      mcp_config_path~,
      enable_skills~,
      skill_dirs~,
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
/// Return the credential-free SIWC projection used by the desktop Settings page.
pub fn NativeDesktop::auth_status(self : NativeDesktop) -> Json {
  self.runtime.auth.status()
}

///|
/// Mark a browser sign-in attempt active before the desktop launches its task.
pub async fn NativeDesktop::auth_begin_sign_in(
  self : NativeDesktop,
) -> Result[Bool, String] {
  match self.runtime.auth.begin_sign_in() {
    Err(error) => Err(error)
    Ok(result) => {
      let started = match result {
        Object(fields) =>
          match fields.get("started") {
            Some(Json::True) => true
            _ => false
          }
        _ => false
      }
      match self.runtime.touch_projection() {
        Ok(_) => Ok(started)
        Err(error) => Err(error)
      }
    }
  }
}

///|
/// Start the host-browser SIWC flow and checkpoint its final account projection.
pub async fn NativeDesktop::auth_sign_in(
  self : NativeDesktop,
) -> Result[Json, String] {
  match self.runtime.auth.sign_in() {
    Ok(status) =>
      match self.runtime.touch_projection() {
        Ok(_) => Ok(status)
        Err(error) => Err(error)
      }
    Err(error) => {
      ignore(self.runtime.touch_projection())
      Err(error)
    }
  }
}

///|
fn native_desktop_auth_profile(status : Json) -> String {
  let account = object_field(status, "account").unwrap_or(Json::null())
  string_field(account, "profile_id").unwrap_or("")
}

///|
fn native_desktop_auth_profile_matches(
  status : Json,
  profile_id : String,
) -> Bool {
  !profile_id.is_empty() && native_desktop_auth_profile(status) == profile_id
}

///|
/// Remove the connected account only when the Settings view still refers to
/// that same profile, matching the local service's stale-account fence.
pub async fn NativeDesktop::auth_sign_out(
  self : NativeDesktop,
  profile_id : String,
) -> Result[Json, String] {
  if !native_desktop_auth_profile_matches(
      self.runtime.auth.status(),
      profile_id,
    ) {
    return Err("the selected ChatGPT profile is no longer active")
  }
  match self.runtime.auth.sign_out_for_profile(Some(profile_id)) {
    Ok(result) =>
      match self.runtime.touch_projection() {
        Ok(_) => Ok(result)
        Err(error) => Err(error)
      }
    Err(error) => Err(error)
  }
}

///|
/// Refresh only the model catalog for the profile currently shown in Settings.
pub async fn NativeDesktop::auth_refresh_models(
  self : NativeDesktop,
  profile_id : String,
) -> Result[Json, String] {
  if !native_desktop_auth_profile_matches(
      self.runtime.auth.status(),
      profile_id,
    ) {
    return Err("the selected ChatGPT profile is no longer active")
  }
  let result = match self.runtime.auth.models() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !native_desktop_auth_profile_matches(
      self.runtime.auth.status(),
      profile_id,
    ) {
    return Err("the selected ChatGPT profile changed while listing models")
  }
  match self.runtime.touch_projection() {
    Ok(_) => Ok(result)
    Err(error) => Err(error)
  }
}

///|
/// Select a model after checking that the account shown by Settings is still
/// the active account. NativeAuth validates the slug against that account's
/// visible model catalog before persisting the selection.
pub async fn NativeDesktop::auth_select_model(
  self : NativeDesktop,
  profile_id : String,
  model : String,
) -> Result[Json, String] {
  if !native_desktop_auth_profile_matches(
      self.runtime.auth.status(),
      profile_id,
    ) {
    return Err("the selected ChatGPT profile is no longer active")
  }
  let result = match
    self.runtime.auth.select_model_for_profile(model, Some(profile_id)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !native_desktop_auth_profile_matches(
      self.runtime.auth.status(),
      profile_id,
    ) {
    return Err("the selected ChatGPT profile changed while choosing a model")
  }
  match self.runtime.touch_projection() {
    Ok(_) => Ok(result)
    Err(error) => Err(error)
  }
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
