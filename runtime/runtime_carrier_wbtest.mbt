///|
priv struct NativeFixtureHttpResponse {
  code : Int
  reason : String
  body : String
  retry_after : String?
}

///|
let native_fixture_provider_env_gate : @async.Mutex = @async.Mutex::Mutex()

///|
fn native_fixture_openai_tool_stream(
  call_id : String,
  file_path : String,
  content : String,
) -> String {
  let arguments = Json::string(
    Json::object({
      "file_path": file_path.to_json(),
      "content": content.to_json(),
    }).stringify(),
  ).stringify()
  "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"tool_calls\":[{\"index\":0,\"id\":\"\{call_id}\",\"type\":\"function\",\"function\":{\"name\":\"write\",\"arguments\":\{arguments}}}]},\"finish_reason\":null}]}\r\n\r\n" +
  "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\r\n\r\n" +
  "data: [DONE]\r\n\r\n"
}

///|
fn native_fixture_openai_calls_stream(
  calls : Array[(String, String, Json)],
) -> String {
  let tool_calls : Array[Json] = []
  for index, (call_id, name, arguments) in calls {
    tool_calls.push({
      "index": Json::number(index.to_double()),
      "id": Json::string(call_id),
      "type": Json::string("function"),
      "function": Json::object({
        "name": Json::string(name),
        "arguments": Json::string(arguments.stringify()),
      }),
    })
  }
  let chunk = Json::object({
    "choices": Json::array([
      Json::object({
        "index": Json::number(0.0),
        "delta": Json::object({
          "role": Json::string("assistant"),
          "tool_calls": Json::array(tool_calls),
        }),
        "finish_reason": Json::null(),
      }),
    ]),
  })
  "data: " +
  chunk.stringify() +
  "\r\n\r\n" +
  "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\r\n\r\n" +
  "data: [DONE]\r\n\r\n"
}

///|
fn native_fixture_openai_text_stream(content : String) -> String {
  let escaped = content.to_json().stringify()
  "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\{escaped}},\"finish_reason\":null}]}\r\n\r\n" +
  "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\r\n\r\n" +
  "data: [DONE]\r\n\r\n"
}

///|
fn native_fixture_mcp_line(
  request_id : String,
  operation : String,
  arguments : Json,
) -> String {
  Json::object({
    "jsonrpc": "2.0".to_json(),
    "id": request_id.to_json(),
    "method": "tools/call".to_json(),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": "2026-07-28".to_json(),
        "io.modelcontextprotocol/clientCapabilities": Json::empty_object(),
      }),
      "name": operation.to_json(),
      "arguments": arguments,
    }),
  }).stringify()
}

///|
fn native_fixture_mcp_structured(response : String) -> Json raise {
  let root = @json.parse(response)
  assert_true(object_field(root, "error") is None)
  let result = object_field(root, "result").unwrap()
  assert_true(!native_json_true(object_field(result, "isError")))
  match object_field(result, "structuredContent").unwrap() {
    Json::String(value) => @json.parse(value)
    value => value
  }
}

///|
async fn native_fixture_handle_provider_request(
  connection : @http.ServerConnection,
  bodies : Ref[Array[String]],
  auth_ok : Ref[Bool],
  response : NativeFixtureHttpResponse,
  release : @async.Semaphore?,
) -> Unit {
  try {
    let request = connection.read_request()
    let body = connection.read_all().text()
    bodies.val.push(body)
    auth_ok.val = auth_ok.val &&
      request.headers.get("authorization") == Some("Bearer native-fixture-key")
    match release {
      Some(gate) => gate.acquire()
      None => ()
    }
    let headers : @http.Headers = {
      "Content-Type": "text/event-stream",
      "Connection": "close",
    }
    if !response.body.is_empty() {
      headers["Content-Length"] = response.body.length().to_string()
    } else {
      headers["Content-Length"] = "0"
    }
    match response.retry_after {
      Some(value) => headers["Retry-After"] = value
      None => ()
    }
    connection.send_response(
      response.code,
      response.reason,
      extra_headers=headers,
    )
    connection.write_string(response.body)
    connection.end_response()
  } catch {
    _ => ()
  }
}

///|
async fn native_fixture_provider_server(
  server : @http.Server,
  responses : Array[NativeFixtureHttpResponse],
  bodies : Ref[Array[String]],
  auth_ok : Ref[Bool],
  first_release : @async.Semaphore?,
) -> Unit {
  for index in 0..<responses.length() {
    try {
      let (connection, _) = server.accept()
      defer connection.close()
      let release = if index == 0 { first_release } else { None }
      native_fixture_handle_provider_request(
        connection,
        bodies,
        auth_ok,
        responses[index],
        release,
      )
    } catch {
      _ => ()
    }
  }
}

///|
async fn native_fixture_mcp_provider_request(
  connection : @http.ServerConnection,
  bodies : Ref[Array[String]],
  auth_ok : Ref[Bool],
  release : @async.Semaphore,
) -> Bool {
  try {
    let request = connection.read_request()
    let body = connection.read_all().text()
    bodies.val.push(body)
    auth_ok.val = auth_ok.val &&
      request.headers.get("authorization") == Some("Bearer native-fixture-key")
    let is_follow_up = body.contains("Start a new turn after cancellation.")
    if !is_follow_up {
      release.acquire()
    }
    let response = if is_follow_up {
      native_fixture_openai_text_stream(
        "The follow-up provider completed after cancellation.",
      )
    } else {
      native_fixture_openai_tool_stream(
        "late-write-call", "late-tool.txt", "late tool must not run after cancellation",
      )
    }
    connection.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
      "Content-Length": response.length().to_string(),
      "Connection": "close",
    })
    connection.write_string(response)
    connection.end_response()
    is_follow_up
  } catch {
    _ => false
  }
}

///|
async fn native_fixture_mcp_provider_server(
  server : @http.Server,
  bodies : Ref[Array[String]],
  auth_ok : Ref[Bool],
  release : @async.Semaphore,
) -> Unit {
  for _ in 0..<2 {
    try {
      let (connection, _) = server.accept()
      defer connection.close()
      if native_fixture_mcp_provider_request(
          connection, bodies, auth_ok, release,
        ) {
        break
      }
    } catch {
      _ => ()
    }
  }
}

///|
fn native_fixture_restore_env(saved : Array[(String, String?)]) -> Unit {
  for (name, value) in saved {
    match value {
      Some(text) => @env.set_env_var(name, text)
      None => @env.unset_env_var(name)
    }
  }
}

///|
fn native_fixture_provider_env() -> Array[(String, String?)] {
  let names = ["DSH_API_KEY"]
  let saved : Array[(String, String?)] = []
  for name in names {
    saved.push((name, @env.get_env_var(name)))
  }
  @env.set_env_var("DSH_API_KEY", "native-fixture-key")
  saved
}

///|
async test "native HTTP provider retries identical input, gates a real write, and reopens completed history" {
  let fixture = @fs.tmpdir(prefix="dsh-native-http-tool-turn")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    native_fixture_provider_env_gate.acquire()
    let saved_env = native_fixture_provider_env()
    group.add_defer(() => {
      native_fixture_restore_env(saved_env)
      native_fixture_provider_env_gate.release()
    })
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          {
            code: 503,
            reason: "Service Unavailable",
            body: "",
            retry_after: Some("0.001"),
          },
          {
            code: 200,
            reason: "OK",
            body: native_fixture_openai_tool_stream(
              "fixture-write-once", "provider-result.txt", "actual fixture tool result",
            ),
            retry_after: None,
          },
          {
            code: 200,
            reason: "OK",
            body: native_fixture_openai_text_stream(
              "Follow-up provider completed after the approved file write.",
            ),
            retry_after: None,
          },
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let base_url = "http://127.0.0.1:" + server.addr.port().to_string()
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override=base_url,
        max_retries=1,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-http-approved-tool-turn"
    let (_, create_effects) = runtime
      .invoke("session_create", {
        "id": session_id,
        "title": "Fixture provider",
      })
      .unwrap()
    assert_true(create_effects.is_empty())
    let (_, initial_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Write provider-result.txt with the requested fixture content.",
      })
      .unwrap()
    assert_eq(initial_effects.length(), 1)
    assert_true(initial_effects[0].kind() == @engine.EffectType::Provider)
    let (pending, pending_effects) = runtime
      .run_provider_effect(initial_effects[0])
      .unwrap()
    assert_true(pending_effects.is_empty())
    assert_eq(string_field(pending, "status"), Some("awaiting_approval"))
    let approval = runtime
      .invoke("session_get", { "session_id": session_id })
      .unwrap().0
    let pending_call = object_field(approval, "pending_approval").unwrap()
    assert_eq(string_field(pending_call, "name"), Some("write"))
    let call_id = string_field(pending_call, "call_id").unwrap()
    let (_, write_effects) = runtime
      .invoke("tool_approve", {
        "session_id": session_id,
        "call_id": call_id,
        "approved": true,
      })
      .unwrap()
    assert_eq(write_effects.length(), 1)
    assert_true(write_effects[0].kind() == @engine.EffectType::Tool)
    let (_, follow_up_effects) = runtime
      .run_tool_effect(write_effects[0])
      .unwrap()
    assert_eq(follow_up_effects.length(), 1)
    assert_true(follow_up_effects[0].kind() == @engine.EffectType::Provider)
    let (completed, trailing_effects) = runtime
      .run_provider_effect(follow_up_effects[0])
      .unwrap()
    assert_true(trailing_effects.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    assert_true(@fs.exists(workspace + "/provider-result.txt"))
    assert_eq(
      @fs.read_file(workspace + "/provider-result.txt").text(),
      "actual fixture tool result",
    )
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 3)
    assert_eq(bodies.val[0], bodies.val[1])
    assert_true(bodies.val[2] != bodies.val[1])
    assert_true(bodies.val[2].contains("actual fixture tool result"))
    let events = match object_field(completed, "events") {
      Some(Json::Array(values)) => values
      _ => fail("completed session omitted its durable events")
    }
    assert_eq(
      events
      .filter(event => string_field(event, "type") == Some("llm/retry"))
      .length(),
      1,
    )
    assert_eq(
      events
      .filter(event => string_field(event, "type") == Some("llm/retry-started"))
      .length(),
      1,
    )
    assert_eq(
      events
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      1,
    )
    runtime.close().unwrap()
    let reopened = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override=base_url,
        max_retries=1,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap().0
    assert_eq(string_field(restored, "status"), Some("completed"))
    assert_eq(
      @fs.read_file(workspace + "/provider-result.txt").text(),
      "actual fixture tool result",
    )
    reopened.close().unwrap()
    assert_eq(bodies.val.length(), 3)
  }
}

///|
async test "MCP acknowledges provider work, serves reads and cancel promptly, and fences a late tool response" {
  let fixture = @fs.tmpdir(prefix="dsh-native-mcp-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    native_fixture_provider_env_gate.acquire()
    let saved_env = native_fixture_provider_env()
    group.add_defer(() => {
      native_fixture_restore_env(saved_env)
      native_fixture_provider_env_gate.release()
    })
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let release = @async.Semaphore::Semaphore(1, initial_value=0)
    let release_sent = Ref(false)
    group.add_defer(() => {
      if !release_sent.val {
        release_sent.val = true
        release.release()
      }
    })
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_mcp_provider_server(server, bodies, auth_ok, release)
    })
    let base_url = "http://127.0.0.1:" + server.addr.port().to_string()
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override=base_url,
        max_retries=0,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-mcp-immediate-cancel"
    ignore(
      runtime
      .invoke("session_create", {
        "id": session_id,
        "title": "MCP cancellation",
      })
      .unwrap(),
    )
    let send_line = native_fixture_mcp_line("mcp-send-first", "session_send", {
      "session_id": session_id,
      "prompt": "Try a write, but do not execute after cancel.",
    })
    let send = match
      @async.with_timeout_opt(500, async fn() {
        runtime.mcp_handle(send_line, group)
      }) {
      Some(Ok(value)) => value
      Some(Err(error)) => fail(error)
      None => fail("MCP session_send waited for the provider response")
    }
    let send_result = native_fixture_mcp_structured(send)
    assert_eq(string_field(send_result, "status"), Some("running"))
    let approve_line = native_fixture_mcp_line(
      "mcp-approve-during-provider",
      "tool_approve",
      {
        "session_id": session_id,
        "call_id": "not-yet-pending",
        "approved": true,
      },
    )
    let approve = @json.parse(runtime.mcp_handle(approve_line, group).unwrap())
    let busy_code = match object_field(approve, "error") {
      Some(error) =>
        match object_field(error, "code") {
          Some(Json::Number(value, ..)) => value.to_int() == -32000
          _ => false
        }
      None => false
    }
    assert_true(busy_code)
    let get_line = native_fixture_mcp_line("mcp-get-pending", "session_get", {
      "session_id": session_id,
    })
    let get = match
      @async.with_timeout_opt(500, async fn() {
        runtime.mcp_handle(get_line, group)
      }) {
      Some(Ok(value)) => value
      Some(Err(error)) => fail(error)
      None => fail("MCP session_get blocked behind the provider worker")
    }
    let pending = native_fixture_mcp_structured(get)
    assert_eq(string_field(pending, "status"), Some("running"))
    let cancel_line = native_fixture_mcp_line(
      "mcp-cancel-pending",
      "session_cancel",
      { "session_id": session_id },
    )
    let cancel = match
      @async.with_timeout_opt(500, async fn() {
        runtime.mcp_handle(cancel_line, group)
      }) {
      Some(Ok(value)) => value
      Some(Err(error)) => fail(error)
      None => fail("MCP session_cancel blocked behind the provider worker")
    }
    let cancelled = native_fixture_mcp_structured(cancel)
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))
    assert_eq(runtime.scheduler.await_idle(session_id), Ok(()))
    release_sent.val = true
    release.release()

    let follow_up = native_fixture_mcp_line(
      "mcp-send-after-cancel",
      "session_send",
      {
        "session_id": session_id,
        "prompt": "Start a new turn after cancellation.",
      },
    )
    let accepted = match
      @async.with_timeout_opt(500, async fn() {
        runtime.mcp_handle(follow_up, group)
      }) {
      Some(Ok(value)) => value
      Some(Err(error)) => fail(error)
      None => fail("a follow-up MCP session_send did not return immediately")
    }
    assert_eq(
      string_field(native_fixture_mcp_structured(accepted), "status"),
      Some("running"),
    )
    let mut completed : Json? = None
    for _ in 0..<300 {
      let state = runtime
        .invoke("session_get", { "session_id": session_id })
        .unwrap().0
      if string_field(state, "status") == Some("completed") {
        completed = Some(state)
        break
      }
      @async.sleep(10)
    }
    let restored = completed.unwrap_or_else(() => {
      fail("the follow-up provider response did not complete")
    })
    assert_eq(string_field(restored, "status"), Some("completed"))
    assert_true(!@fs.exists(workspace + "/late-tool.txt"))
    let events = match object_field(restored, "events") {
      Some(Json::Array(values)) => values
      _ => fail("cancelled and completed session omitted its event history")
    }
    assert_eq(
      events
      .filter(event => {
        string_field(event, "type") == Some("tool/approval/requested")
      })
      .length(),
      0,
    )
    assert_eq(
      events
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      0,
    )
    serving.wait()
    assert_true(bodies.val.length() <= 2)
    assert_true(
      bodies.val.any(body => {
        body.contains("Start a new turn after cancellation.")
      }),
    )
    assert_true(auth_ok.val)
    runtime.close().unwrap()
  }
}
