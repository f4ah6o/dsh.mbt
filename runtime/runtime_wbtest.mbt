///|
fn native_runtime_command(
  workspace_id : String,
  session_id : String,
  command_id : String,
  prompt : String,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "workspace_id": workspace_id,
    "command_id": command_id,
    "session_id": session_id,
    "operation": "session_send",
    "input": { "prompt": prompt },
    "approval_revision": Json::null(),
  }
  match @protocol.RemoteCommand::parse(command.stringify()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
test "native remote session projection exposes tool-result presence without raw events" {
  let raw = @json.parse(
    "{\"id\":\"s1\",\"events\":[{\"type\":\"tool/result\",\"data\":{\"content\":\"private event result\"}}]}",
  )
  let projected = native_safe_session(raw)
  assert_true(object_field(projected, "has_tool_results") is Some(Json::True))
  assert_true(!projected.stringify().contains("private event result"))

  let empty = native_safe_session(@json.parse("{\"id\":\"s2\",\"events\":[]}"))
  assert_true(object_field(empty, "has_tool_results") is Some(Json::False))
}

///|
test "native v1 transcript marks archived projections instead of calling them original" {
  let session = native_safe_session({
    "id": "archive-ui-session",
    "messages": [
      {
        "role": "tool",
        "tool_call_id": "archive-ui-call",
        "content": "pruned model projection",
        "archive_ref": {
          "session_id": "archive-ui-session",
          "call_id": "archive-ui-call",
          "result_seq": 7,
          "object_id": "aabb",
        },
      },
    ],
    "events": [],
  })
  let message = match object_field(session, "messages") {
    Some(Json::Array(values)) => values[0]
    _ => fail("safe session did not retain an explicit archive marker")
  }
  assert_true(string_field(message, "content").unwrap().contains("Archived"))
  assert_true(
    object_field(message, "archive_original_available") is Some(Json::True),
  )
  assert_eq(string_field(message, "tool_call_id"), Some("archive-ui-call"))
  assert_false(session.stringify().contains("pruned model projection"))
}

///|
test "archive compatibility checks only native semantic marker slots" {
  assert_true(
    native_session_has_archive_markers({
      "messages": [
        {
          "role": "tool",
          "content": "projection",
          "archive_ref": { "object_id": "digest" },
        },
      ],
    }),
  )
  assert_true(
    native_session_has_archive_markers({
      "events": [
        {
          "type": "tool/result",
          "data": { "archive_ref": { "object_id": "digest" } },
        },
      ],
    }),
  )
  assert_false(
    native_session_has_archive_markers({
      "source_format": "deepseek-session-v4",
      "data": {
        "archive_ref": { "note": "ordinary upstream extension metadata" },
      },
      "messages": [],
      "events": [],
    }),
  )
}

///|
fn native_runtime_approval_command(
  workspace_id : String,
  session_id : String,
  command_id : String,
  call_id : String,
  approval_revision : Int32,
) -> @protocol.RemoteCommand raise {
  let command : Json = {
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "workspace_id": workspace_id,
    "command_id": command_id,
    "session_id": session_id,
    "operation": "tool_approve",
    "input": { "call_id": call_id, "approved": true },
    "approval_revision": approval_revision,
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
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "workspace_id": workspace_id,
    "command_id": command_id,
    "session_id": Json::null(),
    "operation": operation,
    "input": input,
    "approval_revision": Json::null(),
  }
  match @protocol.RemoteCommand::parse(command.stringify()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
}

///|
test "native receipt replacement scopes by owner and keeps legacy local ownership" {
  let command_id = "018bcfe5-6800-7000-8000-000000000000"
  let legacy = native_receipt(
    "workspace",
    command_id,
    "legacy-fingerprint",
    "accepted",
    Some(1),
    None,
    None,
  )
  let legacy_owner = native_receipt_owner(legacy)
  let foreign = native_receipt_with_owner(
    native_receipt(
      "workspace",
      command_id,
      "foreign-fingerprint",
      "completed",
      None,
      None,
      None,
    ),
    "tailscale:previous@example.com",
  )
  let replacement = native_receipt_with_owner(
    native_receipt(
      "workspace",
      command_id,
      "legacy-fingerprint",
      "completed",
      Some(1),
      None,
      None,
    ),
    legacy_owner,
  )
  let replaced = native_replace_receipt(
    [legacy, foreign],
    command_id,
    legacy_owner,
    replacement,
  )
  assert_eq(replaced.length(), 2)
  assert_true(
    replaced.any(receipt => {
      native_receipt_owner(receipt) == legacy_owner &&
      string_field(receipt, "status") == Some("completed")
    }),
  )
  assert_true(
    replaced.any(receipt => {
      native_receipt_owner(receipt) == "tailscale:previous@example.com" &&
      string_field(receipt, "status") == Some("completed") &&
      string_field(receipt, "payload_fingerprint") ==
      Some("foreign-fingerprint")
    }),
  )
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
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "workspace_id": workspace_id,
    "command_id": command_id,
    "session_id": session_id,
    "operation": operation,
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
    let (first_receipt, effects, first_accepted, active) = runtime
      .accept_remote_command(command, runtime.state.identity_key)
      .unwrap()
    assert_true(first_accepted)
    assert_eq(effects.length(), 1)
    assert_eq(string_field(first_receipt, "status"), Some("accepted"))
    let active = active.unwrap()

    // The HTTP carrier parses each retry into a fresh command value. Keep the
    // original unsigned input shape instead of reusing the first call's value.
    let duplicate = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "finish this turn",
    )
    let (replayed_receipt, replayed_effects, replayed_accepted, _) = runtime
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
    let (conflict_receipt, conflict_effects, conflict_accepted, _) = runtime
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
async test "native receipts survive owner changes and reopen without replaying effects" {
  let fixture = @fs.tmpdir(prefix="dsh-native-receipt-owner-change")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_a = "receipt-owner-a-session"
    let session_b = "receipt-owner-b-session"
    assert_true(
      runtime
      .invoke("session_create", { "id": session_a, "title": "Owner A" })
      .unwrap().1.is_empty(),
    )
    assert_true(
      runtime
      .invoke("session_create", { "id": session_b, "title": "Owner B" })
      .unwrap().1.is_empty(),
    )
    let owner_a = runtime.state.identity_key
    let command_id = @protocol.uuid_v7_command_id_from_entropy(
      native_auth_now().to_int64() * 1000L,
      "1032547698badcfe0123456789abcdef",
    ).unwrap()
    let command_a = native_runtime_command(
      runtime.state.workspace_id,
      session_a,
      command_id,
      "owner A prompt",
    )
    let (receipt_a, effects_a, started_a, control_a) = runtime
      .accept_remote_command(command_a, owner_a)
      .unwrap()
    assert_eq(string_field(receipt_a, "status"), Some("accepted"))
    assert_true(started_a)
    assert_eq(effects_a.length(), 1)
    runtime.scheduler.finish(control_a.unwrap())
    runtime
    .finish_receipt(
      command_id,
      owner_a,
      "uncertain",
      Some("simulated interrupted effect"),
    )
    .unwrap()

    let owner_b = "receipt-test:owner-b"
    runtime.state = {
      ..runtime.state,
      identity_key: owner_b,
      auth_revision: runtime.state.auth_revision + 1,
    }
    assert_true(runtime.checkpoint_locked() is Ok(_))
    let command_b = native_runtime_command(
      runtime.state.workspace_id,
      session_b,
      command_id,
      "owner B prompt",
    )
    let (receipt_b, effects_b, started_b, control_b) = runtime
      .accept_remote_command(command_b, owner_b)
      .unwrap()
    assert_eq(string_field(receipt_b, "status"), Some("accepted"))
    assert_true(started_b)
    assert_eq(effects_b.length(), 1)
    runtime.scheduler.finish(control_b.unwrap())
    runtime
    .finish_receipt(
      command_id,
      owner_b,
      "uncertain",
      Some("simulated interrupted effect"),
    )
    .unwrap()

    let duplicate_b = native_runtime_command(
      runtime.state.workspace_id,
      session_b,
      command_id,
      "owner B prompt",
    )
    let (replayed_b, replayed_effects_b, replayed_started_b, _) = runtime
      .accept_remote_command(duplicate_b, owner_b)
      .unwrap()
    assert_eq(string_field(replayed_b, "status"), Some("uncertain"))
    assert_true(replayed_effects_b.is_empty())
    assert_false(replayed_started_b)

    assert_true(runtime.close() is Ok(_))
    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.identity_key, owner_a)
    let same_id_receipts = reopened.state.receipts.filter(receipt => {
      string_field(receipt, "command_id") == Some(command_id)
    })
    assert_eq(same_id_receipts.length(), 2)
    assert_true(
      same_id_receipts.any(receipt => {
        native_receipt_owner(receipt) == owner_a &&
        string_field(receipt, "status") == Some("uncertain")
      }),
    )
    assert_true(
      same_id_receipts.any(receipt => {
        native_receipt_owner(receipt) == owner_b &&
        string_field(receipt, "status") == Some("uncertain")
      }),
    )
    let retry_a = native_runtime_command(
      reopened.state.workspace_id,
      session_a,
      command_id,
      "owner A prompt",
    )
    let (replayed_a, replayed_effects_a, replayed_started_a, _) = reopened
      .accept_remote_command(retry_a, owner_a)
      .unwrap()
    assert_eq(string_field(replayed_a, "status"), Some("uncertain"))
    assert_true(replayed_effects_a.is_empty())
    assert_false(replayed_started_a)
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
    let (accepted, accepted_effects, should_start, control) = runtime
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
      control~,
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
    let (replayed, replayed_effects, replayed_accepted, _) = runtime
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
    let (restart_replay, restart_effects, restart_accepted, _) = reopened
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
      "jsonrpc": "2.0",
      "id": "native-mcp-create",
      "method": "tools/call",
      "params": Json::object({
        "_meta": Json::object({
          "io.modelcontextprotocol/protocolVersion": "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
        }),
        "name": "session_create",
        "arguments": Json::object({
          "id": "mcp-checkpointed-session",
          "title": "MCP checkpoint",
        }),
      }),
    }).stringify()
    let response = match runtime.mcp_handle(line, group) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let response_json = @json.parse(response)
    assert_eq(string_field(response_json, "id"), Some("native-mcp-create"))
    if object_field(response_json, "error") is Some(_) {
      fail("MCP create failed: " + response)
    }
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
async test "native MCP archive policy validates protocol first and refuses legacy prune" {
  let fixture = @fs.tmpdir(prefix="dsh-native-mcp-archive-boundary")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = NativeRuntime::open(fixture + "/data", workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", {
      "id": "mcp-archive-session",
      "title": "MCP archive",
    })
    .unwrap()
    |> ignore
    let malformed = Json::object({
      "jsonrpc": Json::string("1.0"),
      "id": Json::string("mcp-archive-malformed"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "name": Json::string("session_prune_tool_results"),
        "arguments": Json::object({
          "session_id": Json::string("mcp-archive-session"),
        }),
      }),
    }).stringify()
    let malformed_response = @json.parse(
      runtime.mcp_handle(malformed, group).unwrap(),
    )
    assert_true(malformed_response.stringify().contains("-32600"))

    let valid = Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::string("mcp-archive-valid"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "_meta": Json::object({
          "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
          "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
        }),
        "name": Json::string("session_prune_tool_results"),
        "arguments": Json::object({
          "session_id": Json::string("mcp-archive-session"),
        }),
      }),
    }).stringify()
    let valid_response = @json.parse(runtime.mcp_handle(valid, group).unwrap())
    assert_true(
      string_field(object_field(valid_response, "error").unwrap(), "message")
      .unwrap()
      .contains("native archive transaction"),
    )
    assert_true(runtime.scheduler.active.get("mcp-archive-session") is None)
    let (session, effects) = runtime
      .invoke("session_get", { "session_id": "mcp-archive-session" })
      .unwrap()
    assert_true(effects.is_empty())
    assert_eq(
      match object_field(session, "events") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      1,
    )
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
    let (receipt, effects, should_start, _) = runtime
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
      { "id": session_id, "title": "Prior completed session" },
    )
    let (completed_accepted, completed_effects, completed_should_start, _) = first
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
    let (rejected, rejected_effects, rejected_should_start, _) = first
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
    let (accepted, effects, should_start, _) = first
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
    let (replayed, replay_effects, replay_started, _) = reopened
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
    let (accepted, effects, should_start, control) = reopened
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
      control~,
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

///|
async test "native auto-prune hook reservation failure runs no hook and keeps the durable turn unchanged" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-prune-reservation-failure")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let hooks_path = fixture + "/hooks.json"
    let marker = workspace + "/hook-count.txt"
    let command = "cat >/dev/null; printf x >> \"${CLAUDE_PROJECT_DIR}/hook-count.txt\"; printf '{}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", command)),
    )
    let runtime = NativeRuntime::open(
      data,
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "auto-prune-reservation-failure"
    runtime
    .invoke("session_create", {
      "id": session_id,
      "title": "Reservation failure",
    })
    .unwrap()
    |> ignore

    // A competing SafeRoot write changes only the file version while leaving
    // a valid snapshot. The runtime's next reservation checkpoint must fail.
    let competing_root = SafeRoot::open(data).unwrap()
    let (saved_text, saved_version) = competing_root
      .read_text("sessions.json")
      .unwrap()
    assert_true(
      competing_root.write_atomic(
        "sessions.json",
        saved_text + "\n",
        expected=saved_version,
        permission=0o600,
      )
      is Ok(_),
    )
    let failed_send = runtime.invoke("session_send", {
      "session_id": session_id,
      "prompt": "Continue with automatic pruning",
      "auto_prune_tool_results": true,
    })
    match failed_send {
      Err(error) => assert_true(error.contains("native checkpoint failed:"))
      Ok(_) => fail("expected the reservation checkpoint to fail")
    }
    assert_true(runtime.stopped)
    assert_false(@fs.exists(marker))
    assert_true(runtime.api.take_typed_effects().is_empty())
    assert_true(runtime.close() is Err(_))
    competing_root.close()

    let reopened = NativeRuntime::open(
      data,
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_false(@fs.exists(marker))
    let (durable, effects) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(effects.is_empty())
    assert_false(@fs.exists(marker))
    assert_eq(string_field(durable, "status"), Some("idle"))
    assert_eq(int_field(durable, "turn_id"), Some(0))
    let durable_events = match object_field(durable, "events") {
      Some(Json::Array(values)) => values
      _ => fail("durable session omitted its events")
    }
    assert_false(
      durable_events.any(event => {
        string_field(event, "type") == Some("tool/result/pruned")
      }),
    )
  }
}

///|
async test "native auto-prune final checkpoint failure returns no provider effect and preserves durable tool output" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-prune-final-failure")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "auto-prune-final-checkpoint-failure"
    let original_tool_result = StringView::repeat("x"[:], 9000).to_owned()
    runtime
    .invoke("session_create", {
      "id": session_id,
      "title": "Final checkpoint failure",
    })
    .unwrap()
    |> ignore

    // Seed one completed turn with an oversized tool result using the same
    // effect-completion boundary as an ordinary native provider/tool cycle.
    let (_, initial_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Read the large result",
      })
      .unwrap()
    let provider = native_effect_by_kind(
      initial_effects,
      @engine.EffectType::Provider,
    ).unwrap_or_else(() => fail("expected initial provider effect"))
    let (_, tool_effects) = runtime
      .complete(provider.id(), {
        "ok": true,
        "content": "",
        "tool_calls": [
          {
            "id": "read-large-result",
            "name": "read",
            "arguments": "{\"file_path\":\"large.txt\"}",
          },
        ],
        "finish_reason": "tool_calls",
      })
      .unwrap()
    let tool = native_effect_by_kind(tool_effects, @engine.EffectType::Tool).unwrap_or_else(() => {
        fail("expected read tool effect")
      },
    )
    let (_, followup_effects) = runtime
      .complete(tool.id(), { "ok": true, "content": original_tool_result })
      .unwrap()
    let followup = native_effect_by_kind(
      followup_effects,
      @engine.EffectType::Provider,
    ).unwrap_or_else(() => fail("expected follow-up provider effect"))
    let (_, trailing_effects) = runtime
      .complete(followup.id(), {
        "ok": true,
        "content": "Read complete",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing_effects.is_empty())
    let engine_before = runtime.api.snapshot()

    // Keep the external writer's replacement valid so reopen can prove the
    // old durable engine contents survive the failed final checkpoint.
    let competing_root = SafeRoot::open(data).unwrap()
    let (saved_text, saved_version) = competing_root
      .read_text("sessions.json")
      .unwrap()
    let saved_envelope = @json.parse(saved_text)
    assert_eq(object_field(saved_envelope, "engine"), Some(engine_before))
    assert_true(
      competing_root.write_atomic(
        "sessions.json",
        saved_text + "\n",
        expected=saved_version,
        permission=0o600,
      )
      is Ok(_),
    )

    // The detached send candidate is published as an archive object, then its
    // final CAS loses. The authoritative engine remains untouched and no
    // provider effect reaches the host.
    let failed_send = runtime.invoke("session_send", {
      "session_id": session_id,
      "prompt": "Continue with automatic pruning",
      "auto_prune_tool_results": true,
    })
    match failed_send {
      Err(error) => assert_true(error.contains("native checkpoint failed:"))
      Ok(_) => fail("expected the final checkpoint to fail")
    }
    assert_true(runtime.stopped)
    assert_true(runtime.api.take_typed_effects().is_empty())
    let live_session = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(live_session, "status"), Some("completed"))
    assert_eq(int_field(live_session, "turn_id"), Some(1))
    let live_events = match object_field(live_session, "events") {
      Some(Json::Array(values)) => values
      _ => fail("live session omitted its events")
    }
    assert_false(
      live_events.any(event => {
        string_field(event, "type") == Some("tool/result/pruned")
      }),
    )
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_eq(runtime.store.archive_inventory().unwrap().1, 1)

    let (durable_text, _) = competing_root.read_text("sessions.json").unwrap()
    let durable_envelope = @json.parse(durable_text)
    assert_eq(object_field(durable_envelope, "engine"), Some(engine_before))
    assert_eq(object_field(durable_envelope, "archive_objects"), None)
    ignore(runtime.close())
    competing_root.close()

    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (durable, effects) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(effects.is_empty())
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_eq(string_field(durable, "status"), Some("completed"))
    assert_eq(int_field(durable, "turn_id"), Some(1))
    let durable_events = match object_field(durable, "events") {
      Some(Json::Array(values)) => values
      _ => fail("reopened session omitted its events")
    }
    assert_false(
      durable_events.any(event => {
        string_field(event, "type") == Some("tool/result/pruned")
      }),
    )
    assert_eq(reopened.state.archive_objects.length(), 0)
    assert_eq(reopened.store.archive_inventory().unwrap().1, 1)
    let tool_results = durable_events.filter(event => {
      string_field(event, "type") == Some("tool/result")
    })
    assert_eq(tool_results.length(), 1)
    assert_eq(
      string_field(object_field(tool_results[0], "data").unwrap(), "content"),
      Some(original_tool_result),
    )
  }
}
