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
  }
}
