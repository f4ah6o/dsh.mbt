///|
priv struct NativeChoiceWireResponse {
  status : Int32
  prefix : String
  suffix : String
}

///|
fn native_choice_response_frame(kind : String, value : Json) -> String {
  "event: " + kind + "\ndata: " + value.stringify() + "\n\n"
}

///|
fn native_choice_response_prefix(text : String) -> String {
  native_choice_response_frame("response.created", {
    "type": "response.created",
    "response": { "id": "choice-response", "status": "in_progress" },
  }) +
  native_choice_response_frame("response.output_item.added", {
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "choice-message",
      "type": "message",
      "role": "assistant",
      "content": [],
    },
  }) +
  native_choice_response_delta(text)
}

///|
fn native_choice_response_delta(text : String) -> String {
  native_choice_response_frame("response.output_text.delta", {
    "type": "response.output_text.delta",
    "item_id": "choice-message",
    "output_index": 0,
    "content_index": 0,
    "delta": text,
  })
}

///|
fn native_choice_response_suffix(text : String) -> String {
  native_choice_response_frame("response.output_item.done", {
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "choice-message",
      "type": "message",
      "role": "assistant",
      "content": [{ "type": "output_text", "text": text }],
    },
  }) +
  native_choice_response_frame("response.completed", {
    "type": "response.completed",
    "response": { "id": "choice-response", "status": "completed", "output": [] },
  })
}

///|
fn native_choice_wire_response(text : String) -> NativeChoiceWireResponse {
  {
    status: 200,
    prefix: native_choice_response_prefix(text),
    suffix: native_choice_response_suffix(text),
  }
}

///|
async fn native_choice_wire_connection(
  connection : @http.ServerConnection,
  response : NativeChoiceWireResponse,
  bodies : Ref[Array[Json]],
  authorization : String,
  path : String,
  release : @async.Semaphore?,
) -> Bool {
  defer connection.close()
  let request = connection.read_request() catch {
    error if error.to_string() == "ReaderClosed" => return false
    error => raise error
  }
  assert_true(request.meth is @http.Post)
  assert_eq(request.path, path)
  assert_eq(request.headers.get("authorization"), Some(authorization))
  bodies.val.push(@json.parse(connection.read_all().text()))
  // Empty prefixes gate the entire HTTP response; nonempty ones gate the
  // terminal stream after an observable text delta has reached the engine.
  if response.prefix.is_empty() && release is Some(gate) {
    gate.acquire()
  }
  connection.send_response(
    response.status,
    if response.status == 200 {
      "OK"
    } else {
      "Service Unavailable"
    },
    extra_headers={
      "Content-Type": "text/event-stream",
      "Connection": "close",
      "Retry-After": "0.001",
      "Content-Length": @utf8.encode(response.prefix + response.suffix)
      .length()
      .to_string(),
    },
  )
  connection.write_string(response.prefix)
  if !response.prefix.is_empty() && release is Some(gate) {
    connection.flush()
    gate.acquire()
  }
  // A stale stream may be closed by the client as soon as its first late
  // event is rejected. That expected close does not invalidate the fixture.
  try {
    connection.write_string(response.suffix)
    connection.end_response()
  } catch {
    _ if @async.is_being_cancelled() => @async.pause()
    _ => ()
  }
  true
}

///|
async fn native_choice_wire_server(
  server : @http.Server,
  responses : Array[NativeChoiceWireResponse],
  bodies : Ref[Array[Json]],
  authorization~ : String = "Bearer synthetic-access-token",
  path~ : String = "/v1/responses",
  first_release~ : @async.Semaphore? = None,
) -> Unit {
  let mut index = 0
  let mut empty = 0
  while index < responses.length() {
    let (connection, _) = server.accept()
    if native_choice_wire_connection(
        connection,
        responses[index],
        bodies,
        authorization,
        path,
        if index == 0 {
          first_release
        } else {
          None
        },
      ) {
      index += 1
    } else {
      empty += 1
      assert_true(empty <= 32)
    }
  }
}

///|
fn native_choice_wire_runtime(
  original : NativeRuntime,
  models : @http.Server,
  responses : @http.Server,
) -> NativeRuntime {
  let runtime = {
    ..original,
    auth: {
      ..original.auth,
      endpoints: {
        ..AuthEndpoints::production(),
        models: "http://127.0.0.1:" + models.addr.port().to_string() + "/models",
        responses: "http://127.0.0.1:" +
        responses.addr.port().to_string() +
        "/v1/responses",
        test_mode: true,
      },
    },
  }
  let credential = native_choice_test_credential(runtime.store.host_id())
  runtime.auth.credential = Some(credential)
  runtime.auth.model_identity = Some(credential.identity_for_native())
  runtime.auth.login_state = "connected"
  runtime.auth.generation = "wire-fixture-generation"
  runtime
}

///|
async fn native_choice_wire_select(
  runtime : NativeRuntime,
  server : @http.Server,
  model : String,
  group : @async.TaskGroup[Unit],
) -> Unit {
  let catalog : Json = {
    "models": [
      { "slug": "gpt-one", "display_name": "GPT One", "visibility": "list" },
      { "slug": "gpt-two", "display_name": "GPT Two", "visibility": "list" },
    ],
  }
  let listing = group.spawn(async fn() {
    native_auth_serve_json_once(server, catalog.stringify(), 0)
  })
  let desktop : NativeDesktop = { runtime, }
  desktop.auth_select_model("fixture-account", model).unwrap() |> ignore
  listing.wait()
}

///|
async fn native_choice_wire_send(
  runtime : NativeRuntime,
  id : String,
) -> @engine.EngineEffect {
  let (_, effects) = runtime
    .invoke("session_send", {
      "session_id": id,
      "prompt": "synthetic routing check",
    })
    .unwrap()
  native_effect_by_kind(effects, @engine.EffectType::Provider).unwrap()
}

///|
async test "selected ChatGPT model reaches real Responses HTTP for root ACP and child loops" {
  let fixture = @fs.tmpdir(prefix="dsh-choice-wire")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let models = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    let responses = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    group.add_defer(() => models.close())
    group.add_defer(() => responses.close())
    let original = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="deepseek",
      enable_subagents=true,
    ).unwrap()
    let runtime = native_choice_wire_runtime(original, models, responses)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    native_choice_wire_select(runtime, models, "gpt-one", group)
    let route = runtime.acp_route_id().unwrap()
    let bodies : Ref[Array[Json]] = Ref([])
    let serving = group.spawn(async fn() {
      native_choice_wire_server(
        responses,
        [
          native_choice_wire_response("root response"),
          native_choice_wire_response("ACP response"),
          native_choice_wire_response("child response"),
          native_choice_wire_response("parent response"),
          native_choice_wire_response("changed global model response"),
        ],
        bodies,
      )
    })
    runtime.invoke("session_create", { "id": "wire-root" }).unwrap() |> ignore
    let root = native_choice_wire_send(runtime, "wire-root")
    let (completed, _) = runtime.run_provider_effect(root).unwrap()
    assert_eq(string_field(completed, "status"), Some("completed"))
    assert_true(completed.stringify().contains("root response"))
    runtime
    .create_acp_session(
      "wire-acp",
      runtime.tools.workspace,
      Some("gpt-two"),
      route,
    )
    .unwrap()
    |> ignore
    let acp = native_choice_wire_send(runtime, "wire-acp")
    let (completed, _) = runtime.run_provider_effect(acp).unwrap()
    assert_eq(string_field(completed, "status"), Some("completed"))
    runtime
    .create_acp_session(
      "wire-child-parent",
      runtime.tools.workspace,
      Some("gpt-two"),
      route,
    )
    .unwrap()
    |> ignore
    let parent = native_choice_wire_send(runtime, "wire-child-parent")
    let arguments : Json = {
      "description": "Synthetic child",
      "prompt": "Return the synthetic fixture response.",
    }
    let (_, effects) = runtime
      .complete(parent.id(), {
        "ok": true,
        "content": "",
        "finish_reason": "tool_calls",
        "tool_calls": [
          {
            "id": "wire-child-call",
            "name": "subagent",
            "arguments": arguments.stringify(),
          },
        ],
      })
      .unwrap()
    let child_tool = native_effect_by_kind(effects, @engine.EffectType::Tool).unwrap()
    let (_, follow_up) = runtime.run_tool_effect(child_tool).unwrap()
    let (completed, _) = runtime
      .invoke("session_get", { "session_id": "wire-child-parent" })
      .unwrap()
    let envelope = native_subagent_result_for_call(completed, "wire-child-call")
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_true(envelope.stringify().contains("child response"))
    runtime
    .run_provider_effect(
      native_effect_by_kind(follow_up, @engine.EffectType::Provider).unwrap(),
    )
    .unwrap()
    |> ignore
    native_choice_wire_select(runtime, models, "gpt-two", group)
    assert_eq(runtime.acp_route_id(), Ok(route))
    runtime.invoke("session_create", { "id": "wire-new-model" }).unwrap()
    |> ignore
    runtime
    .run_provider_effect(native_choice_wire_send(runtime, "wire-new-model"))
    .unwrap()
    |> ignore
    serving.wait()
    assert_eq(bodies.val.map(body => string_field(body, "model").unwrap()), [
      "gpt-one", "gpt-two", "gpt-two", "gpt-two", "gpt-two",
    ])
    runtime.auth.sign_out().unwrap() |> ignore
    runtime.invoke("session_create", { "id": "wire-signed-out" }).unwrap()
    |> ignore
    runtime
    .run_provider_effect(native_choice_wire_send(runtime, "wire-signed-out"))
    .unwrap()
    |> ignore
    let (signed_out, _) = runtime
      .invoke("session_get", { "session_id": "wire-signed-out" })
      .unwrap()
    assert_eq(string_field(signed_out, "status"), Some("failed"))
    assert_true(signed_out.stringify().contains("AUTH_REQUIRED"))
    assert_eq(bodies.val.length(), 5)
  }
}

///|
async test "provider transition fences an API key retry and its captured child binding over HTTP" {
  let fixture = @fs.tmpdir(prefix="dsh-choice-wire-retry")
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
    let models = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    let responses = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    group.add_defer(() => models.close())
    group.add_defer(() => responses.close())
    let original = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="configured-model",
      base_url_override="http://127.0.0.1:" + responses.addr.port().to_string(),
      max_retries=1,
    ).unwrap()
    let runtime = native_choice_wire_runtime(original, models, responses)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime.invoke("session_create", { "id": "wire-retry" }).unwrap() |> ignore
    let effect = native_choice_wire_send(runtime, "wire-retry")
    let binding = runtime.subagent_provider_binding("wire-retry").unwrap()
    let release = @async.Semaphore::Semaphore(1, initial_value=0)
    let bodies : Ref[Array[Json]] = Ref([])
    let serving = group.spawn(async fn() {
      native_choice_wire_server(
        responses,
        [{ status: 503, prefix: "", suffix: "", }],
        bodies,
        authorization="Bearer native-fixture-key",
        path="/v1/chat/completions",
        first_release=Some(release),
      )
    })
    let running = group.spawn(async fn() { runtime.run_provider_effect(effect) })
    let request_deadline = @async.now() + 3000L
    while bodies.val.is_empty() && @async.now() < request_deadline {
      @async.sleep(1)
    }
    assert_eq(bodies.val.length(), 1)
    native_choice_wire_select(runtime, models, "gpt-one", group)
    release.release()
    let (completed, _) = running.wait().unwrap()
    serving.wait()
    assert_eq(string_field(completed, "status"), Some("failed"))
    assert_true(completed.stringify().contains("PROVIDER_CHANGED"))
    assert_eq(bodies.val.length(), 1)
    assert_eq(string_field(bodies.val[0], "model"), Some("configured-model"))
    assert_true(
      runtime.subagent_provider_request(binding, effect.request()) is Err(error) &&
      error.has_prefix("PROVIDER_CHANGED"),
    )
  }
}

///|
async test "restoring configured routing rejects a late ChatGPT HTTP stream and completion" {
  let fixture = @fs.tmpdir(prefix="dsh-choice-wire-stream")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let models = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    let responses = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    group.add_defer(() => models.close())
    group.add_defer(() => responses.close())
    let original = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="deepseek",
    ).unwrap()
    let runtime = native_choice_wire_runtime(original, models, responses)
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    native_choice_wire_select(runtime, models, "gpt-one", group)
    runtime.invoke("session_create", { "id": "wire-stream" }).unwrap() |> ignore
    let effect = native_choice_wire_send(runtime, "wire-stream")
    let release = @async.Semaphore::Semaphore(1, initial_value=0)
    let bodies : Ref[Array[Json]] = Ref([])
    let serving = group.spawn(async fn() {
      native_choice_wire_server(
        responses,
        [
          {
            status: 200,
            prefix: native_choice_response_prefix("accepted prefix"),
            suffix: native_choice_response_delta("stale suffix") +
            native_choice_response_suffix("accepted prefixstale suffix"),
          },
        ],
        bodies,
        first_release=Some(release),
      )
    })
    let running = group.spawn(async fn() { runtime.run_provider_effect(effect) })
    let mut saw_prefix = false
    let stream_deadline = @async.now() + 3000L
    while !saw_prefix && @async.now() < stream_deadline {
      let (session, _) = runtime
        .invoke("session_get", { "session_id": "wire-stream" })
        .unwrap()
      saw_prefix = session.stringify().contains("accepted prefix")
      if !saw_prefix {
        @async.sleep(1)
      }
    }
    assert_true(saw_prefix)
    runtime.auth.use_configured_provider().unwrap() |> ignore
    release.release()
    let (completed, _) = running.wait().unwrap()
    serving.wait()
    assert_eq(string_field(completed, "status"), Some("failed"))
    assert_false(completed.stringify().contains("stale suffix"))
    assert_true(
      completed.stringify().contains("AUTH_ACCOUNT_CHANGED") ||
      completed.stringify().contains("PROVIDER_CHANGED"),
    )
    assert_eq(bodies.val.length(), 1)
  }
}

///|
test "production Responses destination cannot be redirected by fixture endpoints" {
  let production = AuthEndpoints::production()
  assert_true(
    native_auth_endpoint_allowed(production, production.responses, "responses"),
  )
  for
    endpoint in [
      "http://127.0.0.1:1234/v1/responses", "https://api.openai.com.evil.test/v1/responses",
      "https://api.openai.com/v1/responses?redirect=1",
    ] {
    assert_false(
      native_auth_endpoint_allowed(production, endpoint, "responses"),
    )
  }
}
