///|
async test "native runtime archives cumulative Read history and reopens into a later terminal turn" {
  let browser_fixture = @env.get_env_var("DSH_BROWSER_ARCHIVE_FIXTURE_ROOT")
  let fixture = match browser_fixture {
    Some(path) => path
    None => @fs.tmpdir(prefix="dsh-native-archive-runtime-growth")
  }
  @async.with_task_group() <| group => {
    group.add_defer(() => {
      if browser_fixture is None {
        @fs.rmdir(fixture, recursive=true)
      }
    })
    if browser_fixture is Some(_) {
      @fs.mkdir(fixture)
    }
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let original = "R".repeat(60000)
    @fs.write_file(workspace + "/large.txt", @utf8.encode(original))
    let data = fixture + "/data"
    let session_id = "archive-runtime-growth-session"
    let mut runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", { "id": session_id, "title": "Archive growth" })
    .unwrap()
    |> ignore

    for turn in 0..<6 {
      let (_, provider_effects) = runtime
        .invoke("session_send", {
          "session_id": session_id,
          "prompt": "Read the large file for turn " + turn.to_string(),
        })
        .unwrap()
      let provider = native_effect_by_kind(
        provider_effects,
        @engine.EffectType::Provider,
      ).unwrap()
      let call_id = "archive-read-" + turn.to_string()
      let (_, tool_effects) = runtime
        .complete(provider.id(), {
          "ok": true,
          "content": "",
          "tool_calls": [
            {
              "id": call_id,
              "name": "read",
              "arguments": "{\"file_path\":\"large.txt\"}",
            },
          ],
          "finish_reason": "tool_calls",
        })
        .unwrap()
      let read = native_effect_by_kind(tool_effects, @engine.EffectType::Tool).unwrap()
      let (_, followup_effects) = runtime.run_tool_effect(read).unwrap()
      let followup = native_effect_by_kind(
        followup_effects,
        @engine.EffectType::Provider,
      ).unwrap()
      let (_, terminal_effects) = runtime
        .complete(followup.id(), native_demo_response("Read complete"))
        .unwrap()
      assert_true(terminal_effects.is_empty())

      let prune_input : Json = {
        "session_id": session_id,
        "threshold_chars": 100,
        "head_chars": 40,
        "tail_chars": 20,
      }
      let prune_result = if turn == 1 {
        let command_id = native_command_id().unwrap()
        let command = native_runtime_session_operation_command(
          runtime.state.workspace_id,
          session_id,
          command_id,
          "session_prune_tool_results",
          prune_input,
        )
        let identity = runtime.state.identity_key
        let (receipt, effects, should_start, control) = runtime
          .accept_remote_command(command, identity)
          .unwrap()
        assert_eq(string_field(receipt, "status"), Some("completed"))
        assert_true(effects.is_empty())
        assert_false(should_start)
        assert_true(control is None)
        assert_true(runtime.scheduler.active.get(session_id) is None)
        let revision = runtime.state.revision
        let inventory = runtime.store.archive_inventory().unwrap()
        let (duplicate, replay_effects, replay_start, replay_control) = runtime
          .accept_remote_command(command, identity)
          .unwrap()
        assert_eq(duplicate, receipt)
        assert_true(replay_effects.is_empty())
        assert_false(replay_start)
        assert_true(replay_control is None)
        assert_eq(runtime.state.revision, revision)
        assert_eq(runtime.store.archive_inventory().unwrap(), inventory)
        object_field(receipt, "result").unwrap()
      } else {
        let (result, effects) = runtime
          .invoke("session_prune_tool_results", prune_input)
          .unwrap()
        assert_true(effects.is_empty())
        result
      }
      assert_eq(
        match object_field(prune_result, "archive_refs") {
          Some(Json::Array(values)) => values.length()
          _ => -1
        },
        1,
      )

      // inspect archived coordinate
      let internal_session = runtime.api
        .invoke("session_get", { "session_id": session_id })
        .unwrap()
      let mut selected_reference : Json? = None
      match object_field(internal_session, "events") {
        Some(Json::Array(events)) =>
          for event in events {
            if string_field(event, "type") == Some("tool/result") {
              let data = object_field(event, "data").unwrap_or(Json::null())
              if string_field(data, "tool_call_id") == Some(call_id) {
                selected_reference = object_field(data, "archive_ref")
              }
            }
          }
        _ => fail("archived session events are missing")
      }
      let reference = match selected_reference {
        Some(value) => value
        None => fail("tool result has no archive reference")
      }
      assert_eq(runtime.state.archive_objects.length(), turn + 1)
      assert_eq(string_field(reference, "call_id"), Some(call_id))
      assert_true(runtime.read_acp_session(session_id) is Err(_))
      let acp_output : Ref[Array[String]] = Ref([])
      let acp_service = NativeAcpService::new(runtime, line => {
        acp_output.val.push(line)
        Ok(())
      })
      let acp_session : NativeAcpSession = {
        session_id: "acp-archive-projection",
        native_session_id: session_id,
        event_gate: @async.Mutex::Mutex(),
        last_event_seq: 0,
        prompt_generation: 0,
        prompt_active: false,
        resuming: false,
        cancelled: false,
        closing: false,
        closed: false,
        cancel_required: false,
        cancel_sent: false,
        prompt_done: None,
        pending_permission: None,
      }
      assert_true(
        acp_service.emit_committed_events(acp_session, internal_session)
        is Err(_),
      )
      assert_true(acp_output.val.is_empty())
      assert_eq(acp_session.last_event_seq, 0)
      let original_result = runtime
        .archive_original(
          session_id,
          int_field(reference, "result_seq").unwrap(),
          runtime.state.identity_key,
        )
        .unwrap()
      assert_eq(
        string_field(original_result, "content"),
        Some("1: " + original),
      )
      assert_true(
        runtime.invoke("session_get", { "session_id": session_id }) is Err(_),
      )
      let public = runtime
        .remote_session(session_id, runtime.state.identity_key)
        .unwrap()
      assert_false(public.stringify().contains(original))
      assert_true(public.stringify().contains("Archived tool output"))
      let legacy_history_request = Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::string("archive-legacy-history"),
        "method": Json::string("tools/call"),
        "params": Json::object({
          "_meta": Json::object({
            "io.modelcontextprotocol/protocolVersion": Json::string(
              "2026-07-28",
            ),
            "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
          }),
          "name": Json::string("session_get"),
          "arguments": Json::object({ "session_id": Json::string(session_id) }),
        }),
      }).stringify()
      let legacy_history_response = @json.parse(
        runtime.mcp_handle(legacy_history_request, group).unwrap(),
      )
      assert_true(
        string_field(
          object_field(legacy_history_response, "error").unwrap(),
          "message",
        )
        .unwrap()
        .contains("archive-aware history endpoint"),
      )

      if turn < 5 {
        assert_true(runtime.close() is Ok(_))
        runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
        assert_eq(runtime.state.archive_objects.length(), turn + 1)
        assert_true(runtime.api.take_typed_effects().is_empty())
        let reopened_original = runtime
          .archive_original(
            session_id,
            int_field(reference, "result_seq").unwrap(),
            runtime.state.identity_key,
          )
          .unwrap()
        assert_eq(
          string_field(reopened_original, "content"),
          Some("1: " + original),
        )
      }
    }

    let compact_session = runtime.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(runtime.state.archive_sources.length(), 6)
    assert_true(compact_session.stringify().length() < 262144)
    let tool_message_count = match object_field(compact_session, "messages") {
      Some(Json::Array(messages)) =>
        messages
        .filter(message => string_field(message, "role") == Some("tool"))
        .length()
      _ => -1
    }
    assert_eq(tool_message_count, 6)
    assert_true(compact_session.stringify().contains("archive_ref"))
    assert_true(6 * ("1: " + original).length() > 262144)

    let finished = native_cli_action(runtime, [
      "dsh-native", "--run", "Finish after archive reopen", "--session", session_id,
      "--approve-writes",
    ]).unwrap()
    assert_eq(string_field(finished, "kind"), Some("run"))
    let finished_session = object_field(finished, "session").unwrap()
    assert_eq(string_field(finished_session, "status"), Some("completed"))
    native_cli_assert_approved_write_events(finished_session)
    assert_true(finished_session.stringify().contains("Archived tool output"))
    assert_false(finished_session.stringify().contains("1: " + original))
    let archived_events = match object_field(finished_session, "events") {
      Some(Json::Array(events)) =>
        events.filter(event => {
          let kind = string_field(event, "type")
          let data = object_field(event, "data").unwrap_or(Json::null())
          (kind == Some("tool/completed") || kind == Some("tool/result")) &&
          object_field(data, "archive_ref") is Some(_)
        })
      _ => fail("CLI archived session omitted its event history")
    }
    assert_eq(archived_events.length(), 12)
    assert_true(
      archived_events.all(event => {
        let data = object_field(event, "data").unwrap_or(Json::null())
        string_field(data, "content") ==
        Some(native_archived_tool_output_marker()) &&
        object_field(data, "archive_original_available") is Some(Json::True)
      }),
    )
    ignore(runtime.close())

    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.archive_sources.length(), 6)
    let restored = reopened.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_eq(string_field(restored, "status"), Some("completed"))
    assert_true(restored.stringify().contains("Finish after archive reopen"))
    assert_true(reopened.api.take_typed_effects().is_empty())
  }
}

///|
async test "archive envelope quota rejects before immutable object publication" {
  let fixture = @fs.tmpdir(prefix="dsh-native-archive-envelope-admission")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = NativeRuntime::open(fixture + "/data", workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (seed, _, _, _, _, _) = archive_codec_test_candidate("x".repeat(128))
    runtime.api.restore(seed.snapshot()).unwrap()
    let make_padding = (content : String) => {
      native_receipt_with_owner(
        native_receipt(
          runtime.state.workspace_id,
          "padding-receipt",
          "padding-fingerprint",
          "completed",
          Some(1),
          Some(Json::string(content)),
          None,
        ),
        runtime.state.identity_key,
      )
    }
    runtime.state.receipts = [make_padding("")]
    runtime.checkpoint_locked().unwrap()
    let (base, _) = runtime.store.root
      .read_bytes("sessions.json", max_bytes=SNAPSHOT_LIMIT)
      .unwrap()
    let padding_bytes = SNAPSHOT_LIMIT - base.length() - 1024
    runtime.state.receipts = [make_padding("p".repeat(padding_bytes))]
    runtime.checkpoint_locked().unwrap()
    assert_eq(runtime.store.archive_inventory().unwrap(), (0L, 0))
    let before = runtime.api.snapshot()
    runtime.gate.acquire()
    let failed = runtime.prune_and_archive_locked({
      "session_id": "archive-codec",
    })
    runtime.gate.release()
    match failed {
      Err(error) => assert_true(error.contains("32 MiB"))
      Ok(_) => fail("expected final envelope admission to reject")
    }
    assert_false(runtime.stopped)
    assert_eq(runtime.api.snapshot(), before)
    assert_eq(runtime.store.archive_inventory().unwrap(), (0L, 0))
    assert_true(runtime.close() is Ok(_))
  }
}

///|
async test "archive final CAS conflict leaves a charged orphan and no replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-archive-cas-conflict")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (seed, _, _, _, _, _) = archive_codec_test_candidate("x".repeat(1000))
    runtime.api.restore(seed.snapshot()).unwrap()
    runtime.checkpoint_locked().unwrap()
    let session_id = "archive-codec"
    let identity = runtime.state.identity_key
    let command_id = native_command_id().unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "session_prune_tool_results",
      {},
    )
    let fingerprint = native_digest_hex(
      runtime.store.root,
      @protocol.canonical_command_payload(command),
    ).unwrap()
    let reservation = native_receipt(
      runtime.state.workspace_id,
      command_id,
      fingerprint,
      "accepted",
      Some(runtime.state.revision + 1),
      None,
      None,
    )
    runtime.state.receipts.push(
      native_receipt_with_owner(reservation, identity),
    )
    runtime.checkpoint_locked().unwrap()
    let before = runtime.api.snapshot()
    let (raw, version) = runtime.store.root
      .read_text("sessions.json", max_bytes=SNAPSHOT_LIMIT)
      .unwrap()
    runtime.store.root
    .write_atomic_bounded(
      "sessions.json",
      raw + " ",
      SNAPSHOT_LIMIT,
      expected=version,
      permission=0o600,
    )
    .unwrap()
    runtime.gate.acquire()
    let failed = runtime.prune_and_archive_locked(
      { "session_id": session_id },
      receipt=Some({ command_id, fingerprint, identity_key: identity, }),
    )
    runtime.gate.release()
    assert_true(failed is Err(_))
    assert_true(runtime.stopped)
    assert_eq(runtime.api.snapshot(), before)
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_eq(runtime.store.archive_inventory().unwrap().1, 1)
    ignore(runtime.close())

    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.archive_objects.length(), 0)
    assert_true(reopened.api.take_typed_effects().is_empty())
    let (replayed, effects, should_start, control) = reopened
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("uncertain"))
    assert_true(effects.is_empty())
    assert_false(should_start)
    assert_true(control is None)
    assert_eq(reopened.store.archive_inventory().unwrap().1, 1)
    assert_true(reopened.scheduler.active.get(session_id) is None)
  }
}

///|
async test "archive manifest write with unknown acknowledgement resolves as completed without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-archive-post-write-unknown")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (seed, _, _, _, _, _) = archive_codec_test_candidate("x".repeat(1000))
    runtime.api.restore(seed.snapshot()).unwrap()
    runtime.checkpoint_locked().unwrap()
    let session_id = "archive-codec"
    let identity = runtime.state.identity_key
    let command_id = native_command_id().unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "session_prune_tool_results",
      {},
    )
    let fingerprint = native_digest_hex(
      runtime.store.root,
      @protocol.canonical_command_payload(command),
    ).unwrap()
    let reservation = native_receipt(
      runtime.state.workspace_id,
      command_id,
      fingerprint,
      "accepted",
      Some(runtime.state.revision + 1),
      None,
      None,
    )
    runtime.state.receipts.push(
      native_receipt_with_owner(reservation, identity),
    )
    runtime.checkpoint_locked().unwrap()
    let before = runtime.api.snapshot()
    runtime.gate.acquire()
    let failed = runtime.prune_and_archive_locked_with_writer(
      { "session_id": session_id },
      receipt=Some({ command_id, fingerprint, identity_key: identity, }),
      (store, state) => {
        match store.save(state) {
          Ok(_) => Err("injected unknown acknowledgement after durable write")
          Err(error) => Err(error)
        }
      },
    )
    runtime.gate.release()
    assert_true(failed is Err(_))
    assert_true(runtime.stopped)
    assert_eq(runtime.api.snapshot(), before)
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_eq(runtime.store.archive_inventory().unwrap().1, 1)
    ignore(runtime.close())

    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.archive_objects.length(), 1)
    assert_eq(reopened.state.archive_sources.length(), 1)
    assert_true(reopened.api.take_typed_effects().is_empty())
    let durable = reopened.find_receipt(command_id, identity).unwrap().unwrap()
    assert_eq(string_field(durable, "status"), Some("completed"))
    let inventory = reopened.store.archive_inventory().unwrap()
    let (replayed, effects, should_start, control) = reopened
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(replayed, durable)
    assert_true(effects.is_empty())
    assert_false(should_start)
    assert_true(control is None)
    assert_eq(reopened.store.archive_inventory().unwrap(), inventory)
    assert_true(reopened.scheduler.active.get(session_id) is None)
  }
}
