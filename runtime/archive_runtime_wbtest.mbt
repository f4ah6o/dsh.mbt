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
      let followup = match
        native_effect_by_kind(followup_effects, @engine.EffectType::Provider) {
        Some(value) => value
        None =>
          fail(
            "archive growth turn " +
            turn.to_string() +
            " produced no follow-up provider: " +
            Json::array(followup_effects.map(@engine.EngineEffect::json)).stringify(),
          )
      }
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

///|
async test "opted-in sends archive prior Read results in the same durable candidate" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-archive-turns")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let original = "R".repeat(44000)
    @fs.write_file(workspace + "/large.txt", @utf8.encode(original))
    let data = fixture + "/data"
    let session_id = "auto-archive-turn-session"
    let mut runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", { "id": session_id, "title": "Auto archive" })
    .unwrap()
    |> ignore

    // A send with no eligible prior output must remain a normal v1 send.
    let (_, empty_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Start with no tool output",
        "auto_prune_tool_results": true,
      })
      .unwrap()
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_eq(
      string_field(runtime.state.engine, "schema"),
      Some("dsh.mbt-session-v1"),
    )
    let empty_provider = native_effect_by_kind(
      empty_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, empty_terminal) = runtime
      .complete(empty_provider.id(), native_demo_response("Ready"))
      .unwrap()
    assert_true(empty_terminal.is_empty())

    for turn in 0..<6 {
      let (_, provider_effects) = runtime
        .invoke("session_send", {
          "session_id": session_id,
          "prompt": "Read the large file for turn " + turn.to_string(),
          "auto_prune_tool_results": true,
        })
        .unwrap()
      assert_eq(runtime.state.archive_objects.length(), turn)
      let provider = native_effect_by_kind(
        provider_effects,
        @engine.EffectType::Provider,
      ).unwrap()
      if turn > 0 {
        let request = provider.request()
        let messages = match object_field(request, "messages") {
          Some(Json::Array(values)) => values
          _ => fail("automatic archive request has no messages")
        }
        let tool_messages = messages.filter(message => {
          string_field(message, "role") == Some("tool")
        })
        assert_eq(tool_messages.length(), turn)
        assert_true(request.stringify().contains("tool result middle pruned"))
        assert_false(request.stringify().contains(original))
        assert_eq(
          string_field(runtime.state.engine, "schema"),
          Some("dsh.mbt-session-v2"),
        )
      }
      let call_id = "auto-archive-read-" + turn.to_string()
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
      let followup = match
        native_effect_by_kind(followup_effects, @engine.EffectType::Provider) {
        Some(value) => value
        None =>
          fail(
            "automatic archive turn " +
            turn.to_string() +
            " produced no follow-up provider: " +
            Json::array(followup_effects.map(@engine.EngineEffect::json)).stringify(),
          )
      }
      let (_, terminal_effects) = runtime
        .complete(followup.id(), native_demo_response("Read complete"))
        .unwrap()
      assert_true(terminal_effects.is_empty())
      assert_eq(runtime.state.archive_objects.length(), turn)

      assert_true(runtime.close() is Ok(_))
      runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
      assert_eq(runtime.state.archive_objects.length(), turn)
      assert_true(runtime.api.take_typed_effects().is_empty())
    }

    // The next opted-in send archives the last Read result too. It emits no
    // maintenance command and the provider sees only bounded projections.
    let (_, last_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Continue after all reads",
        "auto_prune_tool_results": true,
      })
      .unwrap()
    assert_eq(runtime.state.archive_objects.length(), 6)
    assert_eq(runtime.state.archive_sources.length(), 6)
    let last_provider = native_effect_by_kind(
      last_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let last_request = last_provider.request()
    let last_messages = match object_field(last_request, "messages") {
      Some(Json::Array(values)) => values
      _ => fail("last automatic archive request has no messages")
    }
    assert_eq(
      last_messages
      .filter(message => string_field(message, "role") == Some("tool"))
      .length(),
      6,
    )
    assert_true(last_request.stringify().contains("tool result middle pruned"))
    assert_false(last_request.stringify().contains(original))
    assert_true(runtime.close() is Ok(_))

    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.archive_objects.length(), 6)
    assert_eq(reopened.state.archive_sources.length(), 6)
    assert_true(reopened.api.take_typed_effects().is_empty())
    let session = reopened.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    let result_sequences : Array[Int32] = []
    match object_field(session, "events") {
      Some(Json::Array(events)) =>
        for event in events {
          if string_field(event, "type") == Some("tool/result") {
            result_sequences.push(int_field(event, "seq").unwrap())
          }
        }
      _ => fail("reopened automatic archive events are missing")
    }
    assert_eq(result_sequences.length(), 6)
    for result_seq in result_sequences {
      let fetched = reopened
        .archive_original(session_id, result_seq, reopened.state.identity_key)
        .unwrap()
      assert_eq(string_field(fetched, "content"), Some("1: " + original))
    }
  }
}

///|
async test "remote auto-send receipt replay does not republish archives or effects" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-archive-receipt")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let original = "S".repeat(60000)
    @fs.write_file(workspace + "/large.txt", @utf8.encode(original))
    let data = fixture + "/data"
    let session_id = "auto-archive-receipt-session"
    let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime
    .invoke("session_create", { "id": session_id, "title": "Receipt" })
    .unwrap()
    |> ignore
    let (_, provider_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Read one large output",
      })
      .unwrap()
    let provider = native_effect_by_kind(
      provider_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, tool_effects) = runtime
      .complete(provider.id(), {
        "ok": true,
        "content": "",
        "tool_calls": [
          {
            "id": "auto-receipt-read",
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
    assert_eq(runtime.state.archive_objects.length(), 0)

    let command_id = native_command_id().unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      command_id,
      "session_send",
      {
        "prompt": "Continue with a bounded context",
        "auto_prune_tool_results": true,
      },
    )
    let identity = runtime.state.identity_key
    let (receipt, effects, should_start, control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(receipt, "status"), Some("accepted"))
    assert_true(should_start)
    assert_eq(effects.length(), 1)
    assert_true(control is Some(_))
    assert_eq(runtime.state.archive_objects.length(), 1)
    assert_eq(runtime.state.archive_sources.length(), 1)
    let revision = runtime.state.revision
    let engine_snapshot = runtime.api.snapshot()
    let inventory = runtime.store.archive_inventory().unwrap()

    // This models a lost response: the same command ID returns its durable
    // receipt and no provider effect without touching the candidate state.
    let (replay, replay_effects, replay_started, replay_control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(replay, receipt)
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)
    assert_true(replay_control is None)
    assert_eq(runtime.state.revision, revision)
    assert_eq(runtime.api.snapshot(), engine_snapshot)
    assert_eq(runtime.store.archive_inventory().unwrap(), inventory)

    // Simulate abrupt process loss before the returned provider effect is
    // dispatched, then verify reconnect replay still emits no work.
    assert_true(runtime.store.close() is Ok(_))
    runtime.api.close()
    runtime.auth.close()
    runtime.tools.root.close()
    runtime.closed = true
    let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_eq(reopened.state.archive_objects.length(), 1)
    assert_eq(reopened.state.archive_sources.length(), 1)
    assert_true(reopened.api.take_typed_effects().is_empty())
    let reopened_revision = reopened.state.revision
    let reopened_snapshot = reopened.api.snapshot()
    let reopened_inventory = reopened.store.archive_inventory().unwrap()
    let (restart_replay, restart_effects, restart_started, restart_control) = reopened
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(restart_replay, "status"), Some("uncertain"))
    assert_true(restart_effects.is_empty())
    assert_false(restart_started)
    assert_true(restart_control is None)
    assert_eq(reopened.state.revision, reopened_revision)
    assert_eq(reopened.api.snapshot(), reopened_snapshot)
    assert_eq(reopened.store.archive_inventory().unwrap(), reopened_inventory)
    let session = reopened.api
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    let result_seq = match object_field(session, "events") {
      Some(Json::Array(events)) => {
        let mut selected : Int32? = None
        for event in events {
          if string_field(event, "type") == Some("tool/result") &&
            string_field(
              object_field(event, "data").unwrap_or(Json::null()),
              "tool_call_id",
            ) ==
            Some("auto-receipt-read") {
            selected = int_field(event, "seq")
          }
        }
        selected.unwrap()
      }
      _ => fail("reopened receipt session events are missing")
    }
    let archived = reopened
      .archive_original(session_id, result_seq, identity)
      .unwrap()
    assert_eq(string_field(archived, "content"), Some("1: " + original))
  }
}

///|
async test "MCP auto-prune opt-in is rejected before hooks and state mutation" {
  let fixture = @fs.tmpdir(prefix="dsh-native-mcp-auto-archive-rejection")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let marker = workspace + "/hook-count.txt"
    let hooks_path = fixture + "/hooks.json"
    let hook = "cat >/dev/null; printf x >> \"${CLAUDE_PROJECT_DIR}/hook-count.txt\"; printf '{}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", hook)),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (seed, _, _, _, _, _) = archive_codec_test_candidate(
      "original".repeat(1000),
    )
    runtime.api.restore(seed.snapshot()).unwrap()
    runtime.checkpoint_locked().unwrap()
    let before = runtime.api.snapshot()
    let revision = runtime.state.revision
    let inventory = runtime.store.archive_inventory().unwrap()
    let line = Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::string("mcp-auto-archive"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "_meta": Json::object({
          "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
          "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
        }),
        "name": Json::string("session_send"),
        "arguments": Json::object({
          "session_id": Json::string("archive-codec"),
          "prompt": Json::string("Continue with automatic archival"),
          "auto_prune_tool_results": Json::boolean(true),
        }),
      }),
    }).stringify()
    let response = @json.parse(runtime.mcp_handle(line, group).unwrap())
    let error = object_field(response, "error").unwrap()
    assert_true(
      string_field(error, "message")
      .unwrap()
      .contains("unavailable through MCP"),
    )
    assert_eq(runtime.api.snapshot(), before)
    assert_eq(runtime.state.revision, revision)
    assert_eq(runtime.store.archive_inventory().unwrap(), inventory)
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_true(runtime.api.take_typed_effects().is_empty())
    assert_true(runtime.scheduler.active.get("archive-codec") is None)
    assert_false(@fs.exists(marker))
  }
}

///|
fn native_auto_archive_test_reservation(
  runtime : NativeRuntime,
) -> (@protocol.RemoteCommand, NativeSendCommandReceipt) raise {
  let command_id = native_command_id().unwrap()
  let session_id = "archive-codec"
  let command = native_runtime_session_operation_command(
    runtime.state.workspace_id,
    session_id,
    command_id,
    "session_send",
    {
      "prompt": "Continue with automatic archival",
      "auto_prune_tool_results": true,
    },
  )
  let fingerprint = native_digest_hex(
    runtime.store.root,
    @protocol.canonical_command_payload(command),
  ).unwrap()
  let identity_key = runtime.state.identity_key
  let accepted = native_receipt(
    runtime.state.workspace_id,
    command_id,
    fingerprint,
    "accepted",
    Some(runtime.state.revision + 1),
    None,
    None,
  )
  runtime.state.receipts.push(native_receipt_with_owner(accepted, identity_key))
  runtime.checkpoint_locked().unwrap()
  (command, { command_id, fingerprint, identity_key, })
}

///|
fn native_archive_test_crash(runtime : NativeRuntime) -> Unit {
  ignore(runtime.store.close())
  runtime.api.close()
  runtime.auth.close()
  runtime.tools.root.close()
  runtime.closed = true
}

///|
async test "auto-send publication and manifest uncertainty never dispatch or replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-archive-faults")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    for case in ["object", "manifest", "unknown"] {
      let data = fixture + "/" + case + "/data"
      let runtime = NativeRuntime::open(data, workspace, false, true).unwrap()
      let (seed, _, _, _, _, _) = archive_codec_test_candidate(
        "fault".repeat(1000),
      )
      runtime.api.restore(seed.snapshot()).unwrap()
      runtime.checkpoint_locked().unwrap()
      let (command, receipt) = native_auto_archive_test_reservation(runtime)
      let before = runtime.api.snapshot()
      let inventory_before = runtime.store.archive_inventory().unwrap().1
      let publish = (
        store : NativeStore,
        object : NativeToolResultArchiveObject,
        file_name : String,
      ) => {
        if case == "object" {
          Err("injected archive object publication failure")
        } else {
          store.publish_archive_object(object, file_name)
        }
      }
      let save = (store : NativeStore, state : NativeState) => {
        if case == "manifest" {
          Err("injected final send manifest failure")
        } else if case == "unknown" {
          match store.save(state) {
            Ok(_) => Err("injected unknown acknowledgement after send CAS")
            Err(error) => Err(error)
          }
        } else {
          store.save(state)
        }
      }
      runtime.gate.acquire()
      let failed = runtime.auto_send_and_archive_locked_with_io(
        {
          "session_id": "archive-codec",
          "prompt": "Continue with automatic archival",
          "auto_prune_tool_results": true,
        },
        [],
        [],
        runtime.hooks.context_source_kind(),
        Some(receipt),
        "",
        publish,
        save,
      )
      runtime.gate.release()
      assert_true(failed is Err(_))
      assert_true(runtime.stopped)
      assert_eq(runtime.api.snapshot(), before)
      assert_true(runtime.api.take_typed_effects().is_empty())
      assert_eq(runtime.state.archive_objects.length(), 0)
      let expected_inventory = if case == "object" {
        inventory_before
      } else {
        inventory_before + 1
      }
      assert_eq(
        runtime.store.archive_inventory().unwrap().1,
        expected_inventory,
      )
      native_archive_test_crash(runtime)

      let reopened = NativeRuntime::open(data, workspace, false, true).unwrap()
      group.add_defer(() => {
        @async.protect_from_cancel(() => ignore(reopened.close()))
      })
      assert_true(reopened.api.take_typed_effects().is_empty())
      let durable_receipt = reopened
        .find_receipt(receipt.command_id, receipt.identity_key)
        .unwrap()
        .unwrap()
      assert_eq(string_field(durable_receipt, "status"), Some("uncertain"))
      let expected_objects = if case == "unknown" { 1 } else { 0 }
      assert_eq(reopened.state.archive_objects.length(), expected_objects)
      assert_eq(
        reopened.store.archive_inventory().unwrap().1,
        expected_inventory,
      )
      let durable_revision = reopened.state.revision
      let durable_snapshot = reopened.api.snapshot()
      let (replay, effects, should_start, control) = reopened
        .accept_remote_command(command, receipt.identity_key)
        .unwrap()
      assert_eq(replay, durable_receipt)
      assert_true(effects.is_empty())
      assert_false(should_start)
      assert_true(control is None)
      assert_eq(reopened.state.revision, durable_revision)
      assert_eq(reopened.api.snapshot(), durable_snapshot)
    }
  }
}

///|
async test "auto archive revalidates hook contexts once before final admission" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-archive-hook")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let marker = workspace + "/hook-count.txt"
    let hooks_path = fixture + "/hooks.json"
    let hook = "cat >/dev/null; printf x >> \"${CLAUDE_PROJECT_DIR}/hook-count.txt\"; printf '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"keep this hook context\"}}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", hook)),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (seed, _, _, _, _, _) = archive_codec_test_candidate(
      "hooked".repeat(1000),
    )
    runtime.api.restore(seed.snapshot()).unwrap()
    runtime.checkpoint_locked().unwrap()
    let command_id = native_command_id().unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      "archive-codec",
      command_id,
      "session_send",
      {
        "prompt": "Continue with automatic archival",
        "auto_prune_tool_results": true,
      },
    )
    let identity = runtime.state.identity_key
    let (receipt, effects, should_start, control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(receipt, "status"), Some("accepted"))
    assert_true(should_start)
    assert_true(control is Some(_))
    assert_eq(effects.length(), 1)
    assert_eq(runtime.state.archive_objects.length(), 1)
    assert_eq(@fs.read_file(marker).text(), "x")
    let messages = match object_field(effects[0].request(), "messages") {
      Some(Json::Array(values)) => values
      _ => fail("hooked auto archive provider request has no messages")
    }
    assert_true(
      effects[0].request().stringify().contains("keep this hook context"),
    )
    assert_true(
      effects[0].request().stringify().contains("tool result middle pruned"),
    )
    assert_false(effects[0].request().stringify().contains("hookedhooked"))
    assert_true(messages.length() >= 3)

    let revision = runtime.state.revision
    let inventory = runtime.store.archive_inventory().unwrap()
    let (replay, replay_effects, replay_started, replay_control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(replay, receipt)
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)
    assert_true(replay_control is None)
    assert_eq(runtime.state.revision, revision)
    assert_eq(runtime.store.archive_inventory().unwrap(), inventory)
    assert_eq(@fs.read_file(marker).text(), "x")
  }
}
