///|
fn native_service_signal_tool_response(command : String) -> Json {
  let arguments = Json::object({
    "command": Json::string(command),
    "timeout": Json::number(60000.0),
  })
  Json::object({
    "ok": true,
    "content": Json::string(""),
    "reasoning": Json::string(""),
    "tool_calls": Json::array([
      Json::object({
        "id": Json::string("signal-shutdown-call"),
        "name": Json::string("bash"),
        "arguments": Json::string(arguments.stringify()),
      }),
    ]),
    "finish_reason": Json::string("tool_calls"),
    "usage": Json::object({
      "input_tokens": Json::number(1.0),
      "output_tokens": Json::number(1.0),
      "total_tokens": Json::number(2.0),
    }),
  })
}

///|
async fn native_service_signal_get_json(url : String) -> Json? {
  try {
    let (response, body) = @http.get(url)
    if response.code != 200 {
      return None
    }
    match parse_json(body.text()) {
      Ok(value) => Some(value)
      Err(_) => None
    }
  } catch {
    _ => None
  }
}

///|
async fn native_service_signal_post_json(
  url : String,
  value : Json,
  origin : String,
) -> Result[(Int, Json), String] {
  try {
    let (response, body) = @http.post(url, value, headers={
      "Content-Type": "application/json",
      "Origin": origin,
    })
    match parse_json(body.text()) {
      Ok(parsed) => Ok((response.code, parsed))
      Err(error) => Err(error)
    }
  } catch {
    _ => Err("native service HTTP request failed")
  }
}

///|
async fn native_service_signal_prepare_pending(
  data_dir : String,
  workspace : String,
  command : String,
) -> (String, String, String, Int) {
  let runtime = match NativeRuntime::open(data_dir, workspace, true, true) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let session_id = "signal-shutdown-session"
  let (_, create_effects) = runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Signal shutdown fixture".to_json(),
    })
    .unwrap()
  assert_true(create_effects.is_empty())
  let (_, effects) = runtime
    .invoke("session_send", {
      "session_id": session_id.to_json(),
      "prompt": "Run the approved shutdown fixture command".to_json(),
    })
    .unwrap()
  let provider = match
    native_effect_by_kind(effects, @engine.EffectType::Provider) {
    Some(value) => value
    None => fail("signal fixture did not receive a provider effect")
  }
  let (_, trailing) = runtime
    .complete(provider.id(), native_service_signal_tool_response(command))
    .unwrap()
  assert_true(trailing.is_empty())
  let (session, effects) = runtime
    .invoke("session_get", { "session_id": session_id.to_json() })
    .unwrap()
  assert_true(effects.is_empty())
  let pending = object_field(session, "pending_approval").unwrap_or(
    Json::null(),
  )
  let call_id = string_field(pending, "call_id").unwrap_or_else(() => {
    fail("signal fixture has no pending approval")
  })
  let revision = match native_cli_approval_revision(session) {
    Json::Number(value, ..) => value.to_int()
    _ => fail("signal fixture has no approval revision")
  }
  let workspace_id = runtime.state.workspace_id
  runtime.close().unwrap()
  (workspace_id, session_id, call_id, revision)
}

///|
async fn native_service_signal_request_approval(
  port : Int,
  workspace_id : String,
  session_id : String,
  call_id : String,
  approval_revision : Int,
) -> (String, Json) {
  let command_id = native_command_id().unwrap()
  let origin = "http://127.0.0.1:" + port.to_string()
  let command : Json = Json::object({
    "protocol_version": Json::number(1.0),
    "workspace_id": Json::string(workspace_id),
    "command_id": Json::string(command_id),
    "session_id": Json::string(session_id),
    "operation": Json::string("tool_approve"),
    "input": Json::object({ "call_id": Json::string(call_id), "approved": true }),
    "approval_revision": Json::number(approval_revision.to_double()),
  })
  match
    native_service_signal_post_json(
      origin + "/api/v1/commands",
      command,
      origin,
    ) {
    Ok((status, receipt)) if status == 202 => (command_id, receipt)
    Ok((status, _)) =>
      fail("service rejected approved signal fixture: " + status.to_string())
    Err(error) => fail(error)
  }
}

///|
async test "native service handles SIGTERM and SIGINT with durable worker cleanup" {
  let fixture = @fs.tmpdir(prefix="dsh-native-service-signal")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    for signal_name in ["SIGTERM", "SIGINT"] {
      let data_dir = fixture + "/data-" + signal_name
      let workspace = fixture + "/workspace-" + signal_name
      @fs.mkdir(data_dir)
      @fs.mkdir(workspace)
      let bash_command = "(trap '' TERM; exec sleep 60) &\n" +
        "child=$!\n" +
        "printf '%s' \"$child\" > shutdown-child.pid\n" +
        "printf ready\n" +
        "wait\n"
      let (workspace_id, session_id, call_id, approval_revision) = native_service_signal_prepare_pending(
        data_dir, workspace, bash_command,
      )

      let executable = match @env.get_env_var("DSH_NATIVE_WORKER_BIN") {
        Some(value) if value.has_prefix("/") => value
        _ => fail("signal fixture requires DSH_NATIVE_WORKER_BIN")
      }
      let address = @socket.Addr::parse("127.0.0.1:0")
      let reservation = @http.Server::Server(address, reuse_addr=false)
      let port = reservation.addr.port()
      reservation.close()

      let pid_ref = Ref(None)
      let child_reaped = Ref(false)
      group.add_defer(() => {
        @async.protect_from_cancel(async fn() {
          match pid_ref.val {
            Some(pid) if !child_reaped.val => {
              if os_process_alive(pid) {
                ignore(os_kill_process(pid, 15))
              }
              match
                @async.with_timeout_opt(3000, () => @process.wait_pid(pid)) {
                Some(_) => child_reaped.val = true
                None => {
                  ignore(os_kill_process(pid, 9))
                  ignore(@process.wait_pid(pid))
                  child_reaped.val = true
                }
              }
            }
            _ => ()
          }
        })
      })
      let log = fixture + "/service-" + signal_name + ".log"
      let output = @process.redirect_to_file(log, permission=0o600)
      let pid = @process.spawn_orphan(
        executable,
        [
          "--serve",
          "--data-dir",
          data_dir,
          "--workspace",
          workspace,
          "--port",
          port.to_string(),
          "--allow-shell",
          "--demo",
        ],
        stdout=output,
        stderr=output,
      )
      pid_ref.val = Some(pid)

      let origin = "http://127.0.0.1:" + port.to_string()
      let snapshot_url = origin + "/api/v1/snapshot"
      let mut ready = false
      for _ in 0..<200 {
        match native_service_signal_get_json(snapshot_url) {
          Some(snapshot) if string_field(snapshot, "workspace_id") ==
            Some(workspace_id) => {
            ready = true
            break
          }
          _ => @async.sleep(25)
        }
      }
      assert_true(ready)

      let (command_id, accepted) = native_service_signal_request_approval(
        port, workspace_id, session_id, call_id, approval_revision,
      )
      assert_eq(string_field(accepted, "status"), Some("accepted"))
      let marker = workspace + "/shutdown-child.pid"
      let mut child_pid : Int? = None
      for _ in 0..<200 {
        if @fs.exists(marker) {
          let text = @fs.read_file(marker).text()
          child_pid = service_parse_int(text)
          if child_pid is Some(_) {
            break
          }
        }
        @async.sleep(25)
      }
      let child = child_pid.unwrap_or_else(() => {
        fail("approved bash worker did not start; see " + log)
      })
      assert_true(os_process_alive(child))

      let signal_number = if signal_name == "SIGINT" { 2 } else { 15 }
      assert_true(os_kill_process(pid, signal_number))
      let exit_status = match
        @async.with_timeout_opt(10000, () => @process.wait_pid(pid)) {
        Some(value) => {
          child_reaped.val = true
          value
        }
        None => {
          ignore(os_kill_process(pid, 9))
          let value = @process.wait_pid(pid)
          child_reaped.val = true
          fail(
            "native service did not exit after " +
            signal_name +
            "; status=" +
            value.to_string(),
          )
        }
      }
      if exit_status != 0 {
        let diagnostics = @fs.read_file(log).text() catch { _ => "" }
        fail(
          "native service exited " +
          exit_status.to_string() +
          " after " +
          signal_name +
          "; log=" +
          diagnostics,
        )
      }

      let mut child_stopped = false
      for _ in 0..<100 {
        if !os_process_alive(child) {
          child_stopped = true
          break
        }
        @async.sleep(25)
      }
      assert_true(child_stopped)

      let recovered = match
        NativeRuntime::open(data_dir, workspace, true, true) {
        Ok(value) => value
        Err(error) => fail("cannot reopen signalled service: " + error)
      }
      let receipt = recovered
        .find_receipt(command_id, recovered.state.identity_key)
        .unwrap()
        .unwrap()
      let wire_receipt = match
        @protocol.CommandReceipt::parse(receipt.stringify()) {
        Ok(value) => value
        Err(error) =>
          fail("uncertain shutdown receipt was not valid protocol: " + error)
      }
      assert_eq(wire_receipt.status, "uncertain")
      let (session, effects) = recovered
        .invoke("session_get", { "session_id": session_id.to_json() })
        .unwrap()
      assert_true(effects.is_empty())
      assert_true(session is Json::Object(_))
      recovered.close().unwrap()
    }
  }
}
