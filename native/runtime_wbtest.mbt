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
fn native_runtime_session_operation_command(
  workspace_id : String,
  session_id : String,
  command_id : String,
  operation : String,
  input : Json,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION.to_json(),
    "workspace_id": workspace_id.to_json(),
    "command_id": command_id.to_json(),
    "session_id": session_id.to_json(),
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
async test "native runtime projects exact provider deltas and completes long Unicode output" {
  let fixture = @fs.tmpdir(prefix="dsh-native-stream-deltas")
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
    let session_id = "native-stream-delta-session"
    let (_, create_effects) = runtime
      .invoke("session_create", {
        "id": session_id,
        "title": "Stream delta projection",
      })
      .unwrap()
    assert_true(create_effects.is_empty())
    let (_, effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "return a short answer",
      })
      .unwrap()
    assert_eq(effects.length(), 1)
    let effect = effects[0]

    let small_deltas = [("Hel", "think "), ("lo", "carefully")]
    for (text, reasoning) in small_deltas {
      assert_eq(
        runtime.project_provider_delta(effect.id(), text, reasoning),
        Ok(()),
      )
    }
    let long_text = StringView::repeat("x"[:], 4095).to_owned() + "😀z"
    let long_reasoning = StringView::repeat("r"[:], 4500).to_owned()
    assert_eq(native_provider_split_stream_delta(long_text).length(), 2)
    assert_eq(native_provider_split_stream_delta(long_text)[0].length(), 4095)
    assert_eq(native_provider_split_stream_delta(long_text)[1], "😀z")
    assert_eq(
      runtime.project_provider_delta(effect.id(), long_text, long_reasoning),
      Ok(()),
    )

    let (streaming, no_effects) = runtime
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(no_effects.is_empty())
    let events = match object_field(streaming, "events") {
      Some(Json::Array(values)) => values
      _ => fail("streaming session did not contain events")
    }
    let deltas = events.filter(event => {
      string_field(event, "type") == Some("assistant/stream_delta")
    })
    assert_eq(deltas.length(), 6)
    let first = object_field(deltas[0], "data").unwrap()
    assert_eq(string_field(first, "content"), Some("Hel"))
    assert_eq(string_field(first, "reasoning"), Some("think "))
    let second = object_field(deltas[1], "data").unwrap()
    assert_eq(string_field(second, "content"), Some("lo"))
    assert_eq(string_field(second, "reasoning"), Some("carefully"))
    let third = object_field(deltas[2], "data").unwrap()
    assert_eq(
      string_field(third, "content"),
      Some(StringView::repeat("x"[:], 4095).to_owned()),
    )
    assert_eq(string_field(third, "reasoning"), Some(""))
    let fourth = object_field(deltas[3], "data").unwrap()
    assert_eq(string_field(fourth, "content"), Some("😀z"))
    assert_eq(string_field(fourth, "reasoning"), Some(""))
    let fifth = object_field(deltas[4], "data").unwrap()
    assert_eq(string_field(fifth, "content"), Some(""))
    assert_eq(
      string_field(fifth, "reasoning"),
      Some(StringView::repeat("r"[:], 4096).to_owned()),
    )
    let sixth = object_field(deltas[5], "data").unwrap()
    assert_eq(string_field(sixth, "content"), Some(""))
    assert_eq(
      string_field(sixth, "reasoning"),
      Some(StringView::repeat("r"[:], 404).to_owned()),
    )

    let final_content = "Hello" + long_text
    let final_reasoning = "think carefully" + long_reasoning
    let (completed, follow_up_effects) = runtime
      .complete(effect.id(), {
        "ok": true,
        "content": final_content,
        "reasoning": final_reasoning,
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(follow_up_effects.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    let messages = match object_field(completed, "messages") {
      Some(Json::Array(values)) => values
      _ => fail("completed session did not contain messages")
    }
    let assistant = messages[messages.length() - 1]
    assert_eq(string_field(assistant, "content"), Some(final_content))
    assert_eq(string_field(assistant, "reasoning"), Some(final_reasoning))
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
async test "native fork command and CLI receipt replay the same durable child without effects" {
  let fixture = @fs.tmpdir(prefix="dsh-native-session-fork")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let source_id = "native-fork-source"
    let runtime = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", { "id": source_id, "title": "Native source" })
    .unwrap()
    |> ignore
    let (_, effects) = runtime
      .invoke("session_send", {
        "session_id": source_id,
        "prompt": "Settle a native conversation",
      })
      .unwrap()
    let provider = match
      native_effect_by_kind(effects, @engine.EffectType::Provider) {
      Some(value) => value
      None => fail("expected source provider effect")
    }
    let (_, next_effects) = runtime
      .complete(provider.id(), {
        "ok": true,
        "content": "Native answer",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(next_effects.is_empty())
    let (source_before, _) = runtime
      .invoke("session_get", { "session_id": source_id })
      .unwrap()

    let cli = native_cli_action(runtime, ["--fork", source_id])
    let cli_output = match cli {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let cli_receipt = object_field(cli_output, "receipt").unwrap()
    assert_eq(string_field(cli_receipt, "status"), Some("completed"))
    let cli_child = object_field(cli_receipt, "result").unwrap()
    assert_eq(string_field(cli_child, "parent_session_id"), Some(source_id))
    assert_eq(string_field(cli_child, "status"), Some("idle"))

    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "00112233445566778899aabbccddeeff",
    ).unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      source_id,
      command_id,
      "session_fork",
      {},
    )
    let identity = runtime.state.identity_key
    let (accepted, accepted_effects, should_start) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(accepted, "status"), Some("accepted"))
    assert_true(should_start)
    assert_true(accepted_effects.is_empty())
    runtime.run_command_job(
      command_id,
      identity,
      int_field(accepted, "accepted_revision").unwrap(),
      accepted_effects,
    )
    let receipt = runtime.find_receipt(command_id, identity).unwrap().unwrap()
    assert_eq(string_field(receipt, "status"), Some("completed"))
    let child = object_field(receipt, "result").unwrap()
    let child_id = string_field(child, "id").unwrap()
    assert_eq(string_field(child, "parent_session_id"), Some(source_id))
    assert_eq(string_field(child, "status"), Some("idle"))

    let duplicate = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      source_id,
      command_id,
      "session_fork",
      {},
    )
    let (replayed, replayed_effects, replayed_accepted) = runtime
      .accept_remote_command(duplicate, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("completed"))
    assert_eq(
      string_field(object_field(replayed, "result").unwrap(), "id"),
      Some(child_id),
    )
    assert_true(replayed_effects.is_empty())
    assert_true(!replayed_accepted)
    let (source_after, _) = runtime
      .invoke("session_get", { "session_id": source_id })
      .unwrap()
    assert_eq(source_after, source_before)

    assert_true(runtime.close() is Ok(_))
    let reopened = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let durable = reopened.find_receipt(command_id, identity).unwrap().unwrap()
    assert_eq(string_field(durable, "status"), Some("completed"))
    assert_eq(
      string_field(object_field(durable, "result").unwrap(), "id"),
      Some(child_id),
    )
    let after_restart = native_runtime_session_operation_command(
      reopened.state.workspace_id,
      source_id,
      command_id,
      "session_fork",
      {},
    )
    let (restart_replay, restart_effects, restart_accepted) = reopened
      .accept_remote_command(after_restart, identity)
      .unwrap()
    assert_eq(string_field(restart_replay, "status"), Some("completed"))
    assert_eq(
      string_field(object_field(restart_replay, "result").unwrap(), "id"),
      Some(child_id),
    )
    assert_true(restart_effects.is_empty())
    assert_true(!restart_accepted)
    let (restored_child, no_effects) = reopened
      .invoke("session_get", { "session_id": child_id })
      .unwrap()
    assert_eq(
      string_field(restored_child, "parent_session_id"),
      Some(source_id),
    )
    assert_true(no_effects.is_empty())
  }
}

///|
async test "native MCP carrier checkpoints gpui protocol operations" {
  let fixture = @fs.tmpdir(prefix="dsh-native-mcp-carrier")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let line = Json::object({
      "jsonrpc": "2.0".to_json(),
      "id": "native-mcp-create".to_json(),
      "method": "tools/call".to_json(),
      "params": Json::object({
        "_meta": Json::object({
          "io.modelcontextprotocol/protocolVersion": "2026-07-28".to_json(),
          "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
        }),
        "name": "session_create".to_json(),
        "arguments": Json::object({
          "id": "mcp-checkpointed-session".to_json(),
          "title": "MCP checkpoint".to_json(),
        }),
      }),
    }).stringify()
    let response = match runtime.mcp_handle(line) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let response_json = @json.parse(response)
    assert_eq(string_field(response_json, "id"), Some("native-mcp-create"))
    let current = runtime
      .invoke("session_get", { "session_id": "mcp-checkpointed-session" })
      .unwrap().0
    assert_eq(string_field(current, "title"), Some("MCP checkpoint"))
    runtime.close().unwrap()

    let reopened = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", { "session_id": "mcp-checkpointed-session" })
      .unwrap().0
    assert_eq(string_field(restored, "title"), Some("MCP checkpoint"))
    reopened.close().unwrap()
  }
}

///|
async test "native remote fork rejects a live source without creating a child or effects" {
  let fixture = @fs.tmpdir(prefix="dsh-native-session-fork-live")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let source_id = "native-fork-live-source"
    let runtime = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", { "id": source_id, "title": "Live source" })
    .unwrap()
    |> ignore
    let (_, source_effects) = runtime
      .invoke("session_send", {
        "session_id": source_id,
        "prompt": "Keep this native source running",
      })
      .unwrap()
    assert_eq(source_effects.length(), 1)
    let (source_before, _) = runtime
      .invoke("session_get", { "session_id": source_id })
      .unwrap()
    assert_eq(string_field(source_before, "status"), Some("running"))

    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "a0112233445566778899aabbccddeeff",
    ).unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      source_id,
      command_id,
      "session_fork",
      {},
    )
    let (receipt, effects, should_start) = runtime
      .accept_remote_command(command, runtime.state.identity_key)
      .unwrap()
    assert_eq(string_field(receipt, "status"), Some("rejected"))
    assert_true(
      string_field(receipt, "error").unwrap_or("").contains("settled"),
    )
    assert_true(effects.is_empty())
    assert_true(!should_start)
    let (source_after, no_effects) = runtime
      .invoke("session_get", { "session_id": source_id })
      .unwrap()
    assert_eq(source_after, source_before)
    assert_true(no_effects.is_empty())
    let (sessions, list_effects) = runtime.invoke("session_list", {}).unwrap()
    match sessions {
      Json::Array(rows) => assert_eq(rows.length(), 1)
      _ => fail("expected one source session after rejected fork")
    }
    assert_true(list_effects.is_empty())
    let command_receipt = runtime
      .find_receipt(command_id, runtime.state.identity_key)
      .unwrap()
      .unwrap()
    assert_eq(string_field(command_receipt, "status"), Some("rejected"))
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
