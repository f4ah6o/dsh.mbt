///|
async fn native_acp_test_wait_permission(
  output : Ref[Array[String]],
  session_id : String,
) -> Json? {
  let mut polls = 0
  while polls < 400 {
    for line in output.val {
      let value = @json.parse(line) catch { _ => Json::null() }
      if string_field(value, "method") == Some("session/request_permission") {
        let params = object_field(value, "params").unwrap_or(Json::null())
        if string_field(params, "sessionId") == Some(session_id) {
          return Some(value)
        }
      }
    }
    @async.sleep(5)
    polls += 1
  }
  None
}

///|
fn native_acp_test_permission_response(
  permission : Json,
  option : String,
) -> Json {
  {
    "jsonrpc": "2.0",
    "id": object_field(permission, "id").unwrap_or(Json::null()),
    "result": { "outcome": { "outcome": "selected", "optionId": option } },
  }
}

///|
fn native_acp_test_apply_permission(
  service : NativeAcpService,
  response : Json,
) -> Unit raise {
  let message = match native_acp_rpc_message(response) {
    Ok(value) => value
    Err(error) => fail("test permission response was invalid: " + error)
  }
  service.resolve_client_response(message, response)
}

///|
fn native_acp_test_updates(
  output : Ref[Array[String]],
  session_id : String,
) -> Array[Json] {
  let updates : Array[Json] = []
  for line in output.val {
    let value = @json.parse(line) catch { _ => Json::null() }
    if string_field(value, "method") == Some("session/update") {
      let params = object_field(value, "params").unwrap_or(Json::null())
      if string_field(params, "sessionId") == Some(session_id) {
        updates.push(object_field(params, "update").unwrap_or(Json::null()))
      }
    }
  }
  updates
}

///|
async test "ACP approved native turns preserve approval and isolate close across sessions" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-turns")
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
    let output : Ref[Array[String]] = Ref([])
    let service = NativeAcpService::new(runtime, async fn(line) {
      @async.sleep(0)
      output.val.push(line)
      Ok(())
    })
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    assert_true(service.initialize({ "protocolVersion": 1 }) is Err(_))

    let created_a = service.new_session({ "cwd": workspace, "mcpServers": [] })
    let created_b = service.new_session({ "cwd": workspace, "mcpServers": [] })
    let session_a = string_field(created_a.unwrap(), "sessionId").unwrap()
    let session_b = string_field(created_b.unwrap(), "sessionId").unwrap()
    assert_true(
      service.resume_session({
        "sessionId": session_a,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let native_a = service.sessions.get(session_a).unwrap().native_session_id
    let native_b = service.sessions.get(session_b).unwrap().native_session_id

    let prompt_a : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let prompt_b : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let prepared_a = service
      .prepare_prompt({
        "sessionId": session_a,
        "prompt": [{ "type": "text", "text": "write a file" }],
      })
      .unwrap()
    let prepared_b = service
      .prepare_prompt({
        "sessionId": session_b,
        "prompt": [{ "type": "text", "text": "write a file" }],
      })
      .unwrap()
    let prompt_task_a = group.spawn(async fn() {
      prompt_a.val = Some(service.execute_prompt(prepared_a))
    })
    let prompt_task_b = group.spawn(async fn() {
      prompt_b.val = Some(service.execute_prompt(prepared_b))
    })
    let busy = service.prepare_prompt({
      "sessionId": session_a,
      "prompt": [{ "type": "text", "text": "overlapping prompt" }],
    })
    assert_true(busy is Err(_))
    assert_true(
      service.resume_session({
        "sessionId": session_a,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )

    let permission_a = match
      native_acp_test_wait_permission(output, session_a) {
      Some(value) => value
      None => fail("ACP did not request permission for session A")
    }
    let permission_b = match
      native_acp_test_wait_permission(output, session_b) {
      Some(value) => value
      None => fail("ACP did not request permission for session B")
    }
    let close_session = service.begin_cancel(session_a, true).unwrap()
    let close_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let close_task = group.spawn(async fn() {
      close_result.val = Some(service.finish_close(close_session))
    })
    // The old allow reply arrives after close has already fenced A's pending
    // generation. It must be ignored, while B remains free to complete.
    let stale_allow = native_acp_test_permission_response(
      permission_a, "allow-once",
    )
    native_acp_test_apply_permission(service, stale_allow)
    let allow_b = native_acp_test_permission_response(
      permission_b, "allow-once",
    )
    native_acp_test_apply_permission(service, allow_b)

    let mut polls = 0
    while (
            prompt_a.val is None ||
            prompt_b.val is None ||
            close_result.val is None
          ) &&
          polls < 800 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(prompt_a.val is Some(_))
    assert_true(prompt_b.val is Some(_))
    assert_true(close_result.val is Some(_))
    let result_a = prompt_a.val.unwrap().unwrap()
    let result_b = prompt_b.val.unwrap().unwrap()
    assert_eq(string_field(result_a, "stopReason"), Some("cancelled"))
    assert_eq(string_field(result_b, "stopReason"), Some("end_turn"))
    assert_true(close_result.val.unwrap() is Ok(_))
    ignore(prompt_task_a.wait())
    ignore(prompt_task_b.wait())
    ignore(close_task.wait())
    assert_true(service.sessions.get(session_a).unwrap().closed)
    assert_true(service.sessions.get(session_b) is Some(_))
    assert_eq(
      @fs.read_file(workspace + "/native-demo.txt").text(),
      "durable native tool result",
    )

    let state_a = runtime
      .invoke("session_get", { "session_id": native_a })
      .unwrap().0
    let state_b = runtime
      .invoke("session_get", { "session_id": native_b })
      .unwrap().0
    assert_eq(string_field(state_a, "status"), Some("cancelled"))
    assert_eq(string_field(state_b, "status"), Some("completed"))
    let events_a = match object_field(state_a, "events").unwrap() {
      Json::Array(values) => values
      _ => fail("session A events were malformed")
    }
    let events_b = match object_field(state_b, "events").unwrap() {
      Json::Array(values) => values
      _ => fail("session B events were malformed")
    }
    assert_eq(
      events_a
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      1,
    )
    assert_eq(
      events_b
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      1,
    )
    let results_a = events_a.filter(event => {
      string_field(event, "type") == Some("tool/result")
    })
    assert_true(
      native_json_true(
        object_field(object_field(results_a[0], "data").unwrap(), "is_error"),
      ),
    )

    let updates_b = native_acp_test_updates(output, session_b)
    assert_eq(
      updates_b
      .filter(value => string_field(value, "sessionUpdate") == Some("tool_call"))
      .length(),
      1,
    )
    assert_eq(
      updates_b
      .filter(value => {
        string_field(value, "sessionUpdate") == Some("tool_call_update")
      })
      .length(),
      1,
    )
    assert_true(
      updates_b.any(value => {
        string_field(value, "sessionUpdate") == Some("agent_message_chunk")
      }),
    )
    for line in output.val {
      assert_false(line.contains("assistant/stream_delta"))
      let value = @json.parse(line) catch { _ => Json::null() }
      if string_field(value, "method") == Some("session/update") {
        let update = object_field(
          object_field(value, "params").unwrap(),
          "update",
        ).unwrap()
        assert_true(
          [
            "agent_thought_chunk", "agent_message_chunk", "tool_call", "tool_call_update",
          ].contains(string_field(update, "sessionUpdate").unwrap_or("")),
        )
      }
    }
    assert_true(service.shutdown() is Ok(_))
    assert_true(runtime.close() is Ok(_))
    let reopened = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored_a = reopened
      .invoke("session_get", { "session_id": native_a })
      .unwrap().0
    let restored_b = reopened
      .invoke("session_get", { "session_id": native_b })
      .unwrap().0
    assert_eq(string_field(restored_a, "status"), Some("cancelled"))
    assert_eq(string_field(restored_b, "status"), Some("completed"))
    for state in [restored_a, restored_b] {
      let events = match object_field(state, "events").unwrap() {
        Json::Array(values) => values
        _ => fail("reopened ACP session events were malformed")
      }
      assert_eq(
        events
        .filter(event => string_field(event, "type") == Some("tool/result"))
        .length(),
        1,
      )
    }

    let resumed_output : Ref[Array[String]] = Ref([])
    let resumed_service = NativeAcpService::new(reopened, async fn(line) {
      @async.sleep(0)
      resumed_output.val.push(line)
      Ok(())
    })
    assert_true(resumed_service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let revision_before_list = reopened.state.revision
    let listed = resumed_service.list_sessions({}).unwrap()
    assert_eq(reopened.state.revision, revision_before_list)
    assert_true(resumed_service.list_sessions({ "cursor": 123 }) is Err(_))
    assert_true(
      resumed_service.list_sessions({
        "cursor": Json::null(),
        "cwd": Json::null(),
      })
      is Ok(_),
    )
    let listed_sessions = match object_field(listed, "sessions") {
      Some(Json::Array(values)) => values
      _ => fail("ACP session list was malformed")
    }
    assert_eq(listed_sessions.length(), 2)
    assert_eq(string_field(listed_sessions[0], "sessionId"), Some(session_b))
    assert_eq(
      string_field(listed_sessions[0], "cwd"),
      Some(reopened.tools.workspace),
    )
    assert_true(string_field(listed_sessions[0], "updatedAt") is Some(_))

    assert_true(
      resumed_service.resume_session({
        "sessionId": "",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_true(
      resumed_service.resume_session({
        "sessionId": "acp-unknown-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let (_, unregistered_effects) = reopened
      .invoke("session_create", {
        "id": "acp-unregistered-id",
        "title": "not an ACP session",
      })
      .unwrap()
    assert_true(unregistered_effects.is_empty())
    assert_true(
      resumed_service.resume_session({
        "sessionId": "acp-unregistered-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let current_dir = @env.current_dir().unwrap_or_else(() => {
      fail("cannot resolve test checkout")
    })
    let imported_jsonl = @fs.read_file(
      current_dir + "/tests/fixtures/upstream-tool-call-turn/session.v4.jsonl",
    ).text()
    let (imported, imported_effects) = reopened
      .invoke("session_import", { "jsonl": imported_jsonl.to_json() })
      .unwrap()
    assert_true(imported_effects.is_empty())
    let imported_id = string_field(imported, "id").unwrap()
    assert_true(
      resumed_service.resume_session({
        "sessionId": imported_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let (forked, fork_effects) = reopened
      .invoke("session_fork", { "session_id": native_b })
      .unwrap()
    assert_true(fork_effects.is_empty())
    let forked_id = string_field(forked, "id").unwrap()
    assert_eq(string_field(forked, "parent_session_id"), Some(native_b))
    assert_true(
      resumed_service.resume_session({
        "sessionId": forked_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let listed_after_fork = resumed_service.list_sessions({}).unwrap()
    assert_eq(
      match object_field(listed_after_fork, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      2,
    )

    let resume_b = resumed_service.resume_session({
      "sessionId": session_b,
      "cwd": workspace,
      "mcpServers": [],
    })
    assert_true(resume_b is Ok(_))
    assert_true(
      resumed_service.resume_session({
        "sessionId": session_b,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_true(
      resumed_service.close_session({ "sessionId": session_b }) is Ok(_),
    )
    assert_true(
      resumed_service.resume_session({
        "sessionId": session_b,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Ok(_),
    )
    assert_true(native_acp_test_updates(resumed_output, session_b).is_empty())
    let continued = resumed_service
      .prepare_prompt({
        "sessionId": session_b,
        "prompt": [{ "type": "text", "text": "continue saved context" }],
      })
      .unwrap()
    let continued_result = resumed_service.execute_prompt(continued).unwrap()
    assert_eq(string_field(continued_result, "stopReason"), Some("end_turn"))
    let continued_updates = native_acp_test_updates(resumed_output, session_b)
    assert_false(
      continued_updates.any(value => {
        string_field(value, "sessionUpdate") == Some("tool_call")
      }),
    )
    assert_true(
      continued_updates.any(value => {
        string_field(value, "sessionUpdate") == Some("agent_message_chunk")
      }),
    )

    // Fence a second resume while its store read waits on the runtime gate.
    // Prompts are rejected while that placeholder is installed, and close can
    // cancel the in-flight resume without losing the persisted session.
    reopened.gate.acquire()
    let resume_a_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let resume_a_task = group.spawn(async fn() {
      resume_a_result.val = Some(
        resumed_service.resume_session({
          "sessionId": session_a,
          "cwd": workspace,
          "mcpServers": [],
        }),
      )
    })
    @async.sleep(10)
    assert_true(resumed_service.sessions.get(session_a).unwrap().resuming)
    assert_true(
      resumed_service.prepare_prompt({
        "sessionId": session_a,
        "prompt": [{ "type": "text", "text": "cannot race resume" }],
      })
      is Err(_),
    )
    let close_a_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let close_a_task = group.spawn(async fn() {
      close_a_result.val = Some(
        resumed_service.close_session({ "sessionId": session_a }),
      )
    })
    @async.sleep(10)
    assert_true(resumed_service.sessions.get(session_a).unwrap().closing)
    reopened.gate.release()
    let mut resume_polls = 0
    while (resume_a_result.val is None || close_a_result.val is None) &&
          resume_polls < 200 {
      @async.sleep(5)
      resume_polls += 1
    }
    assert_true(resume_a_result.val.unwrap() is Err(_))
    assert_true(close_a_result.val.unwrap() is Ok(_))
    ignore(resume_a_task.wait())
    ignore(close_a_task.wait())
    assert_true(resumed_service.shutdown() is Ok(_))
    assert_true(reopened.close() is Ok(_))

    let foreign_workspace = fixture + "/foreign-workspace"
    @fs.mkdir(foreign_workspace)
    assert_true(
      NativeRuntime::open(fixture + "/data", foreign_workspace, false, true)
      is Err(_),
    )
    let restored_again = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(restored_again.close()))
    })
    let listed_again = NativeAcpService::new(restored_again, async fn(_) {
      @async.sleep(0)
      Ok(())
    })
    assert_true(listed_again.initialize({ "protocolVersion": 1 }) is Ok(_))
    let after_failed_foreign_open = listed_again.list_sessions({}).unwrap()
    assert_eq(
      match object_field(after_failed_foreign_open, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      2,
    )
  }
}

///|
async test "ACP list does not adopt legacy native ids without persisted provenance" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-legacy")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data_dir = fixture + "/data"
    let runtime = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (_, effects) = runtime
      .invoke("session_create", {
        "id": "acp-legacy-id",
        "title": "legacy custom id",
      })
      .unwrap()
    assert_true(effects.is_empty())
    assert_true(runtime.close() is Ok(_))

    let envelope_path = data_dir + "/sessions.json"
    let envelope = @json.parse(@fs.read_file(envelope_path).text())
    let fields = match envelope {
      Json::Object(value) => value
      _ => fail("native envelope was not an object")
    }
    assert_true(fields.get("acp_sessions") is Some(_))
    ignore(fields.remove("acp_sessions"))
    @fs.write_file(envelope_path, Json::object(fields).stringify())

    let reopened = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let service = NativeAcpService::new(reopened, async fn(_) {
      @async.sleep(0)
      Ok(())
    })
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let listed = service.list_sessions({}).unwrap()
    assert_eq(
      match object_field(listed, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      0,
    )
    assert_true(
      service.resume_session({
        "sessionId": "acp-legacy-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let legacy_state = reopened
      .invoke("session_get", { "session_id": "acp-legacy-id" })
      .unwrap().0
    assert_eq(string_field(legacy_state, "id"), Some("acp-legacy-id"))
  }
}

///|
test "ACP persisted registry validation rejects duplicate, dangling, imported, and foreign entries" {
  assert_true(native_acp_valid_timestamp("2024-02-29T23:59:59Z"))
  assert_true(native_acp_valid_timestamp("2026-10-10T00:00:00Z"))
  assert_false(native_acp_valid_timestamp("2023-02-29T12:00:00Z"))
  assert_false(native_acp_valid_timestamp("2026-99-99T99:99:99Z"))
  assert_false(native_acp_valid_timestamp("2024-04-31T10:00:00Z"))
  let cwd = "/workspace"
  let root : Json = { "id": "registered-root", "status": "idle", "events": [] }
  let snapshot : Json = { "sessions": [root] }
  let record : NativeAcpStoredSession = {
    session_id: "registered-root",
    cwd,
    updated_at: None,
  }
  assert_true(native_acp_validate_registry(snapshot, [record], cwd) is Ok(_))
  assert_true(
    native_acp_validate_registry(snapshot, [record, record], cwd) is Err(_),
  )
  let dangling : NativeAcpStoredSession = {
    ..record,
    session_id: "missing-native-session",
  }
  assert_true(native_acp_validate_registry(snapshot, [dangling], cwd) is Err(_))
  let foreign : NativeAcpStoredSession = { ..record, cwd: "/other", }
  assert_true(native_acp_validate_registry(snapshot, [foreign], cwd) is Err(_))
  let imported_snapshot : Json = {
    "sessions": [
      {
        "id": "registered-root",
        "status": "idle",
        "events": [],
        "source_format": "deepseek-session-v4",
      },
    ],
  }
  assert_true(
    native_acp_validate_registry(imported_snapshot, [record], cwd) is Err(_),
  )
  let forked_snapshot : Json = {
    "sessions": [
      {
        "id": "registered-root",
        "status": "idle",
        "events": [],
        "parent_session_id": "parent",
      },
    ],
  }
  assert_true(
    native_acp_validate_registry(forked_snapshot, [record], cwd) is Err(_),
  )
  let duplicate_json = native_acp_stored_sessions_from_json(
    Some(
      Json::array([
        { "session_id": "same", "cwd": cwd },
        { "session_id": "same", "cwd": cwd },
      ]),
    ),
  )
  assert_true(duplicate_json is Err(_))
}
