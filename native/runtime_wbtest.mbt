///|
fn native_runtime_command(
  workspace_id : String,
  session_id : String,
  command_id : String,
  prompt : String,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION.to_json(),
    "workspace_id": workspace_id.to_json(),
    "command_id": command_id.to_json(),
    "session_id": session_id.to_json(),
    "operation": "session_send".to_json(),
    "input": { "prompt": prompt.to_json() },
    "approval_revision": Json::null(),
  }
  match @protocol.RemoteCommand::parse(command.stringify()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
fn native_runtime_approval_command(
  workspace_id : String,
  session_id : String,
  command_id : String,
  call_id : String,
  approval_revision : Int,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION.to_json(),
    "workspace_id": workspace_id.to_json(),
    "command_id": command_id.to_json(),
    "session_id": session_id.to_json(),
    "operation": "tool_approve".to_json(),
    "input": { "call_id": call_id.to_json(), "approved": true },
    "approval_revision": approval_revision.to_json(),
  }
  match @protocol.RemoteCommand::parse(command.stringify()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
fn native_runtime_unscoped_command(
  workspace_id : String,
  command_id : String,
  operation : String,
  input : Json,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION.to_json(),
    "workspace_id": workspace_id.to_json(),
    "command_id": command_id.to_json(),
    "session_id": Json::null(),
    "operation": operation.to_json(),
    "input": input,
    "approval_revision": Json::null(),
  }
  match @protocol.RemoteCommand::parse(command.stringify()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
async test "native runtime replays an accepted in-flight command before scheduler admission" {
  let fixture = @fs.tmpdir(prefix="dsh-native-receipt-replay")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "receipt-replay-session"
    let (_, create_effects) = runtime
      .invoke("session_create", { "id": session_id, "title": "Receipt replay" })
      .unwrap()
    assert_true(create_effects.is_empty())
    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "00112233445566778899aabbccddeeff",
    ).unwrap()
    let command = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "finish this turn",
    )
    let (first_receipt, effects, first_accepted) = runtime
      .accept_remote_command(command, runtime.state.identity_key)
      .unwrap()
    assert_true(first_accepted)
    assert_eq(effects.length(), 1)
    assert_eq(string_field(first_receipt, "status"), Some("accepted"))
    let active = runtime.scheduler
      .begin(session_id, command_id, runtime.state.revision)
      .unwrap()

    // The HTTP carrier parses each retry into a fresh command value. Keep the
    // original unsigned input shape instead of reusing the first call's value.
    let duplicate = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "finish this turn",
    )
    let (replayed_receipt, replayed_effects, replayed_accepted) = runtime
      .accept_remote_command(duplicate, runtime.state.identity_key)
      .unwrap()
    assert_eq(string_field(replayed_receipt, "command_id"), Some(command_id))
    assert_eq(string_field(replayed_receipt, "status"), Some("accepted"))
    assert_true(replayed_effects.is_empty())
    assert_true(!replayed_accepted)

    let conflicting = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "changed payload",
    )
    let (conflict_receipt, conflict_effects, conflict_accepted) = runtime
      .accept_remote_command(conflicting, runtime.state.identity_key)
      .unwrap()
    assert_eq(string_field(conflict_receipt, "status"), Some("rejected"))
    assert_true(conflict_effects.is_empty())
    assert_true(!conflict_accepted)
    assert_eq(
      string_field(runtime.state.receipts[0], "status"),
      Some("accepted"),
    )
    runtime.scheduler.finish(active)
  }
}

///|
async test "native runtime marks accepted receipts uncertain after restart without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-uncertain-restart")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let session_id = "uncertain-restart-session"
    let first = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(first.close()))
    })
    let identity_key = first.state.identity_key
    let completed_command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "001122334455768798a9bacbdcedfe0f",
    ).unwrap()
    let completed_command = native_runtime_unscoped_command(
      first.state.workspace_id,
      completed_command_id,
      "session_create",
      { "id": session_id.to_json(), "title": "Prior completed session" },
    )
    let (completed_accepted, completed_effects, completed_should_start) = first
      .accept_remote_command(completed_command, identity_key)
      .unwrap()
    assert_true(completed_should_start)
    assert_true(completed_effects.is_empty())
    first.run_command_job(
      completed_command_id,
      identity_key,
      int_field(completed_accepted, "accepted_revision").unwrap(),
      completed_effects,
    )
    assert_eq(
      string_field(
        first.find_receipt(completed_command_id, identity_key).unwrap().unwrap(),
        "status",
      ),
      Some("completed"),
    )

    let rejected_command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "102132435465768798a9bacbdcedfe0f",
    ).unwrap()
    let rejected_command = native_runtime_unscoped_command(
      first.state.workspace_id,
      rejected_command_id,
      "host_effect_complete",
      {},
    )
    let (rejected, rejected_effects, rejected_should_start) = first
      .accept_remote_command(rejected_command, identity_key)
      .unwrap()
    assert_eq(string_field(rejected, "status"), Some("rejected"))
    assert_true(rejected_effects.is_empty())
    assert_true(!rejected_should_start)

    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "2031425364758697a8b9cadbecfd0e1f",
    ).unwrap()
    let command = native_runtime_command(
      first.state.workspace_id,
      session_id,
      command_id,
      "do not replay this accepted command",
    )
    let (accepted, effects, should_start) = first
      .accept_remote_command(command, identity_key)
      .unwrap()
    assert_true(should_start)
    assert_eq(string_field(accepted, "status"), Some("accepted"))
    assert_eq(effects.length(), 1)

    // Simulate abrupt process loss: release only the OS lock and close local
    // handles, without checkpointing a graceful API shutdown.
    assert_true(first.store.close() is Ok(_))
    first.api.close()
    first.auth.close()
    first.tools.root.close()
    first.closed = true

    let reopened = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let retained_completed = reopened
      .find_receipt(completed_command_id, identity_key)
      .unwrap()
      .unwrap()
    assert_eq(string_field(retained_completed, "status"), Some("completed"))
    let retained_rejected = reopened
      .find_receipt(rejected_command_id, identity_key)
      .unwrap()
      .unwrap()
    assert_eq(string_field(retained_rejected, "status"), Some("rejected"))
    let uncertain = reopened
      .find_receipt(command_id, identity_key)
      .unwrap()
      .unwrap()
    let parsed_uncertain = @protocol.CommandReceipt::parse(
      uncertain.stringify(),
    ).unwrap()
    assert_eq(parsed_uncertain.status, "uncertain")
    assert_eq(parsed_uncertain.command_id, command_id)
    assert_true(
      string_field(uncertain, "error").unwrap_or("").contains("host restarted"),
    )

    let retry = native_runtime_command(
      reopened.state.workspace_id,
      session_id,
      command_id,
      "do not replay this accepted command",
    )
    let (replayed, replay_effects, replay_started) = reopened
      .accept_remote_command(retry, identity_key)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("uncertain"))
    assert_true(replay_effects.is_empty())
    assert_true(!replay_started)
  }
}

///|
async test "native runtime preserves a pending approval across host restart" {
  let fixture = @fs.tmpdir(prefix="dsh-native-approval-restart")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let session_id = "approval-restart-session"
    let first = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(first.close()))
    })
    first
    .invoke("session_create", { "id": session_id, "title": "Restart approval" })
    .unwrap()
    |> ignore
    let (_, first_effects) = first
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "create the demo file",
      })
      .unwrap()
    let provider = match
      native_effect_by_kind(first_effects, @engine.EffectType::Provider) {
      Some(value) => value
      None => fail("expected the initial provider effect")
    }
    let (_, pending_effects) = first
      .complete(provider.id(), native_demo_tool_response())
      .unwrap()
    assert_true(pending_effects.is_empty())
    let (pending, _) = first
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(pending, "status"), Some("awaiting_approval"))
    let approval_revision = int_field(
      native_safe_session(pending),
      "approval_revision",
    ).unwrap()
    assert_eq(
      string_field(
        object_field(pending, "pending_approval").unwrap(),
        "call_id",
      ),
      Some("demo-write-call"),
    )
    assert_true(first.close() is Ok(_))

    let reopened = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, _) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(restored, "status"), Some("awaiting_approval"))
    assert_eq(
      string_field(
        object_field(restored, "pending_approval").unwrap(),
        "call_id",
      ),
      Some("demo-write-call"),
    )

    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "102132435465768798a9bacbdcedfe0f",
    ).unwrap()
    let command = native_runtime_approval_command(
      reopened.state.workspace_id,
      session_id,
      command_id,
      "demo-write-call",
      approval_revision,
    )
    let identity_key = reopened.state.identity_key
    let (accepted, effects, should_start) = reopened
      .accept_remote_command(command, identity_key)
      .unwrap()
    assert_true(should_start)
    assert_eq(string_field(accepted, "status"), Some("accepted"))
    assert_eq(effects.length(), 1)
    reopened.run_command_job(
      command_id,
      identity_key,
      int_field(accepted, "accepted_revision").unwrap(),
      effects,
    )
    let completed = reopened
      .find_receipt(command_id, identity_key)
      .unwrap()
      .unwrap()
    assert_eq(string_field(completed, "status"), Some("completed"))
    let (finished, _) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(finished, "status"), Some("completed"))
    assert_eq(
      reopened.tools.root.read_text("native-demo.txt").unwrap().0,
      "durable native tool result",
    )
  }
}
