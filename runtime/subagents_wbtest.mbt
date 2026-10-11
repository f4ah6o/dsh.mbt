///|
fn native_subagent_http_response(body : String) -> NativeFixtureHttpResponse {
  { code: 200, reason: "OK", body, retry_after: None, }
}

///|
fn native_subagent_openai_text_stream_with_reason(
  content : String,
  finish_reason : String,
) -> String {
  let escaped = content.to_json().stringify()
  let reason = finish_reason.to_json().stringify()
  "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\{escaped}},\"finish_reason\":null}]}\r\n\r\n" +
  "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\{reason}}]}\r\n\r\n" +
  "data: [DONE]\r\n\r\n"
}

///|
fn native_subagent_result_for_call(
  session : Json,
  call_id : String,
) -> Json raise {
  let event = match native_hook_tool_result(session, call_id) {
    Some(value) => value
    None => fail("parent session omitted the subagent tool result")
  }
  let content = string_field(event, "content").unwrap_or_else(() => {
    fail("subagent tool result omitted its bounded JSON content")
  })
  @json.parse(content)
}

///|
fn native_subagent_tool_names(request : Json) -> Array[String] {
  let output : Array[String] = []
  match object_field(request, "tools") {
    Some(Json::Array(tools)) =>
      for tool in tools {
        let name = match string_field(tool, "name") {
          Some(value) => value
          None =>
            string_field(
              object_field(tool, "function").unwrap_or(Json::null()),
              "name",
            ).unwrap_or("")
        }
        output.push(name)
      }
    _ => ()
  }
  output
}

///|
async fn native_subagent_parent_tool_effect(
  runtime : NativeRuntime,
  session_id : String,
  call_id : String,
  prompt : String,
  child_prompt? : String = "Complete the fixture child task.",
) -> @engine.EngineEffect {
  runtime
  .invoke("session_create", { "id": session_id, "title": "Subagent fixture" })
  .unwrap()
  |> ignore
  let (_, initial) = runtime
    .invoke("session_send", { "session_id": session_id, "prompt": prompt })
    .unwrap()
  let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap_or_else(() => {
      fail("parent fixture had no provider effect")
    },
  )
  let arguments : Json = {
    "description": "Fixture delegation",
    "prompt": child_prompt,
  }
  let (_, effects) = runtime
    .complete(provider.id(), {
      "ok": true,
      "content": "",
      "tool_calls": [
        {
          "id": call_id,
          "name": "subagent",
          "arguments": arguments.stringify(),
        },
      ],
      "finish_reason": "tool_calls",
    })
    .unwrap()
  native_effect_by_kind(effects, @engine.EffectType::Tool).unwrap_or_else(() => {
    fail("parent fixture emitted no subagent tool effect")
  })
}

///|
fn native_subagent_result_messages(envelope : Json) -> Array[Json] {
  match object_field(envelope, "transcript") {
    Some(Json::Array(messages)) => messages
    _ => []
  }
}

///|
async fn native_subagent_provider_server_gated_index(
  server : @http.Server,
  responses : Array[NativeFixtureHttpResponse],
  bodies : Ref[Array[String]],
  auth_ok : Ref[Bool],
  gate_index : Int,
  release : @async.Semaphore,
  ignored_connections? : Ref[Int]? = None,
  ignored_connection_errors? : Ref[Array[String]]? = None,
  response_errors? : Ref[Array[String]]? = None,
) -> Unit {
  let mut index = 0
  let mut ignored = 0
  while index < responses.length() {
    let (connection, _) = server.accept()
    let gate = if index == gate_index { Some(release) } else { None }
    let handled = native_fixture_handle_provider_request(
      connection,
      bodies,
      auth_ok,
      responses[index],
      gate,
      ignored_connections,
      ignored_connection_errors,
      response_errors,
    )
    if handled {
      index += 1
    } else {
      ignored += 1
      if ignored > NATIVE_FIXTURE_MAX_EMPTY_PROVIDER_CONNECTIONS {
        raise NativeFixtureProviderFailure(
          "provider fixture ignored more than " +
          NATIVE_FIXTURE_MAX_EMPTY_PROVIDER_CONNECTIONS.to_string() +
          " empty TCP connections",
        )
      }
    }
  }
}

///|
async test "native foreground subagent runs a bounded child loop and restores correlation without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-restore")
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
    @fs.write_file(workspace + "/target.txt", "child-visible-note\n")
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
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "parent-subagent-call",
                "subagent",
                {
                  "description": "Inspect target",
                  "prompt": "Read target.txt and report its contents.",
                },
              ),
            ]),
          ),
          {
            code: 503,
            reason: "Service Unavailable",
            body: "",
            retry_after: Some("0.001"),
          },
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "child-read-call",
                "read",
                { "file_path": "target.txt", "offset": 1, "limit": 10 },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "target.txt contains child-visible-note",
            ),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "Parent resumed after the child returned.",
            ),
          ),
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
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-restore"
    let _created = match
      runtime.create_acp_session(
        session_id,
        runtime.tools.workspace,
        Some("acp-child-model"),
        runtime.acp_route_id().unwrap(),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let (_, initial_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Ask a read-only child to inspect target.txt.",
      })
      .unwrap()
    let parent_provider = native_effect_by_kind(
      initial_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, tool_effects) = runtime
      .run_provider_effect(parent_provider)
      .unwrap()
    assert_eq(tool_effects.length(), 1)
    let subagent_effect = tool_effects[0]
    assert_true(subagent_effect.kind() == @engine.EffectType::Tool)
    let parent_effect_id = subagent_effect.id().as_string()
    let (_, parent_follow_up) = runtime
      .run_tool_effect(subagent_effect)
      .unwrap()
    assert_eq(parent_follow_up.length(), 1)
    assert_true(parent_follow_up[0].kind() == @engine.EffectType::Provider)
    let (completed, trailing) = runtime
      .run_provider_effect(parent_follow_up[0])
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    serving.wait()

    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 6)
    for body in bodies.val {
      let request = @json.parse(body)
      assert_eq(string_field(request, "model"), Some("acp-child-model"))
    }
    assert_eq(bodies.val[0], bodies.val[1])
    assert_eq(bodies.val[2], bodies.val[3])
    let parent_request = @json.parse(bodies.val[0])
    assert_true(native_subagent_tool_names(parent_request).contains("subagent"))
    let child_request = @json.parse(bodies.val[3])
    assert_eq(native_subagent_tool_names(child_request), [
      "read", "glob", "grep",
    ])
    assert_true(!native_subagent_tool_names(child_request).contains("write"))
    assert_true(!native_subagent_tool_names(child_request).contains("subagent"))

    let envelope = native_subagent_result_for_call(
      completed, "parent-subagent-call",
    )
    assert_eq(string_field(envelope, "schema"), Some("dsh-subagent-result-v1"))
    assert_eq(string_field(envelope, "parent_session_id"), Some(session_id))
    assert_eq(
      string_field(envelope, "parent_effect_id"),
      Some(parent_effect_id),
    )
    assert_eq(
      string_field(envelope, "parent_tool_call_id"),
      Some("parent-subagent-call"),
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_eq(int_field(envelope, "steps"), Some(2))
    assert_eq(int_field(envelope, "tool_call_count"), Some(1))
    let child_id = string_field(envelope, "child_id").unwrap()
    assert_true(child_id.has_prefix("subagent-"))
    let serialized = string_field(
      native_hook_tool_result(completed, "parent-subagent-call").unwrap(),
      "content",
    ).unwrap()
    assert_true(native_provider_utf16_units(serialized) <= 16384)
    let transcript = match object_field(envelope, "transcript") {
      Some(Json::Array(messages)) => messages
      _ => fail("subagent JSON result omitted its child transcript")
    }
    assert_true(
      transcript.any(message => {
        string_field(message, "content")
        .unwrap_or("")
        .contains("child-visible-note")
      }),
    )
    assert_true(
      transcript.any(message => {
        string_field(message, "content") ==
        Some("target.txt contains child-visible-note")
      }),
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
        max_retries=0,
        enable_subagents=true,
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
      native_subagent_result_for_call(restored, "parent-subagent-call"),
      envelope,
    )
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_eq(bodies.val.length(), 6)
    reopened.close().unwrap()
    assert_true(
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override=base_url,
        max_retries=0,
      )
      is Err(_),
    )
    assert_eq(bodies.val.length(), 6)
  }
}

///|
async test "native subagent reuses SafeRoot protections and reports its child step limit" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-safe-root")
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
    @fs.write_file(
      fixture + "/outside-secret.txt",
      "OUTSIDE_SECRET_MUST_NOT_LEAK",
    )
    @fs.write_file(workspace + "/safe.txt", "safe child content")
    let private_data = workspace + "/.private-data"
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let ignored_connections = Ref(0)
    let ignored_connection_errors = Ref([])
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "child-escape-read",
                "read",
                { "file_path": "../outside-secret.txt" },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "child-protected-read",
                "read",
                { "file_path": ".private-data/host-secret.txt" },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              ("child-safe-read", "read", { "file_path": "safe.txt" }),
            ]),
          ),
        ],
        bodies,
        auth_ok,
        None,
        ignored_connections=Some(ignored_connections),
        ignored_connection_errors=Some(ignored_connection_errors),
      )
    })
    let speculative = @socket.Tcp::connect(server.addr)
    speculative.close()
    let mut empty_connection_observed = false
    for _ in 0..<200 {
      if ignored_connections.val == 1 {
        empty_connection_observed = true
        break
      }
      @async.sleep(5)
    }
    assert_true(empty_connection_observed)
    assert_eq(ignored_connection_errors.val.length(), 1)
    assert_eq(ignored_connection_errors.val[0], "ReaderClosed")
    let runtime = match
      NativeRuntime::open(
        private_data,
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    @fs.write_file(
      private_data + "/host-secret.txt",
      "HOST_SECRET_MUST_NOT_LEAK",
    )
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-safe-root", "parent-safe-root-call", "Ask the child to inspect three paths.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    assert_true(follow_up[0].kind() == @engine.EffectType::Provider)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 3)
    let session = runtime
      .invoke("session_get", { "session_id": "native-subagent-safe-root" })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      session, "parent-safe-root-call",
    )
    assert_eq(string_field(envelope, "status"), Some("failed"))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("child reached the 3-step limit before completing"),
    )
    assert_eq(int_field(envelope, "steps"), Some(3))
    assert_eq(int_field(envelope, "tool_call_count"), Some(3))
    let transcript = native_subagent_result_messages(envelope)
    assert_true(
      transcript.any(message => {
        string_field(message, "role") == Some("tool") &&
        native_json_true(object_field(message, "is_error")) &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("Path escapes the workspace")
      }),
    )
    assert_true(
      transcript.any(message => {
        string_field(message, "role") == Some("tool") &&
        native_json_true(object_field(message, "is_error")) &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("Host data is not accessible through workspace tools")
      }),
    )
    assert_true(
      transcript.any(message => {
        string_field(message, "role") == Some("tool") &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("safe child content")
      }),
    )
    let serialized = envelope.stringify()
    assert_true(!serialized.contains("OUTSIDE_SECRET_MUST_NOT_LEAK"))
    assert_true(!serialized.contains("HOST_SECRET_MUST_NOT_LEAK"))
  }
}

///|
async test "native subagent cannot write or recursively delegate even when the model requests it" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-denied-tools")
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
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "child-write-attempt",
                "write",
                { "file_path": "must-not-exist.txt", "content": "blocked" },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "child-recursive-attempt",
                "subagent",
                { "description": "recursive", "prompt": "delegate again" },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "Child completed after rejected calls.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-denied-tools", "parent-denied-tools-call", "Try the child tool restrictions.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 3)
    assert_true(!@fs.exists(workspace + "/must-not-exist.txt"))
    let session = runtime
      .invoke("session_get", { "session_id": "native-subagent-denied-tools" })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      session, "parent-denied-tools-call",
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_eq(int_field(envelope, "tool_call_count"), Some(2))
    let transcript = native_subagent_result_messages(envelope)
    assert_true(
      transcript.any(message => {
        string_field(message, "role") == Some("tool") &&
        native_json_true(object_field(message, "is_error")) &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("Unknown tool: write")
      }),
    )
    assert_true(
      transcript.any(message => {
        string_field(message, "role") == Some("tool") &&
        native_json_true(object_field(message, "is_error")) &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("Unknown tool: subagent")
      }),
    )
  }
}

///|
async test "native parent turns cannot dispatch more than two subagents" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-parent-limit")
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
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "parent-limit-one",
                "subagent",
                { "description": "one", "prompt": "delegate one" },
              ),
              (
                "parent-limit-two",
                "subagent",
                { "description": "two", "prompt": "delegate two" },
              ),
              (
                "parent-limit-three",
                "subagent",
                { "description": "three", "prompt": "delegate three" },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "The parent turn continued after rejecting excessive delegation.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-parent-limit"
    runtime
    .invoke("session_create", { "id": session_id, "title": "Parent limit" })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Do not delegate more than the host limit.",
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let (_, tool_effects) = runtime.run_provider_effect(provider).unwrap()
    assert_eq(tool_effects.length(), 3)
    let mut follow_up : Array[@engine.EngineEffect] = []
    for effect in tool_effects {
      let (_, next) = runtime.run_tool_effect(effect).unwrap()
      if !next.is_empty() {
        follow_up = next
      }
    }
    assert_eq(follow_up.length(), 1)
    assert_true(follow_up[0].kind() == @engine.EffectType::Provider)
    let (completed, trailing) = runtime
      .run_provider_effect(follow_up[0])
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    let tool_errors = [
      "parent-limit-one", "parent-limit-two", "parent-limit-three",
    ].map(call_id => native_hook_tool_result(completed, call_id).unwrap())
    assert_eq(tool_errors.length(), 3)
    for result in tool_errors {
      assert_true(native_json_true(object_field(result, "is_error")))
      assert_true(
        string_field(result, "content")
        .unwrap_or("")
        .contains("at most two foreground subagents"),
      )
    }
  }
}

///|
async test "native parent cancellation reaches a blocked child provider and restores without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-cancel-provider")
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
    @fs.write_file(workspace + "/target.txt", "child data")
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/cancel-stop-payloads.jsonl\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"observation only\"}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_hook_test_config("SubagentStop", "general-purpose", stop_command),
      ),
    )
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
    let response_errors = Ref([])
    let serving = group.spawn(no_wait=true, async fn() {
      native_subagent_provider_server_gated_index(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "parent-cancel-subagent",
                "subagent",
                { "description": "Inspect", "prompt": "Read target.txt." },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "This reply is held until cancellation.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        1,
        release,
        response_errors=Some(response_errors),
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
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-cancel-provider"
    runtime
    .invoke("session_create", { "id": session_id, "title": "Cancel child" })
    .unwrap()
    |> ignore
    let command_time = native_auth_now().to_int64() * 1000L
    let identity = runtime.state.identity_key
    let send_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time, "10112233445566778899aabbccddeeff",
    ).unwrap()
    let send = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      send_id,
      "Delegate a read that will be cancelled.",
    )
    let (accepted, effects, should_start, control) = runtime
      .accept_remote_command(send, identity)
      .unwrap()
    assert_true(should_start)
    assert_eq(effects.length(), 1)
    let control = control.unwrap()
    let accepted_revision = int_field(accepted, "accepted_revision").unwrap()
    let job = group.spawn(
      async fn() {
        runtime.run_command_job(
          send_id,
          identity,
          accepted_revision,
          effects,
          control=Some(control),
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut reached_child = false
    for _ in 0..<600 {
      if bodies.val.length() == 2 {
        reached_child = true
        break
      }
      @async.sleep(5)
    }
    assert_true(reached_child)

    let cancel_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time + 1L,
      "20112233445566778899aabbccddeeff",
    ).unwrap()
    let cancel = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      cancel_id,
      "session_cancel",
      {},
    )
    let (cancel_receipt, cancel_effects, cancel_started, _) = runtime
      .accept_remote_command(cancel, identity)
      .unwrap()
    assert_eq(string_field(cancel_receipt, "status"), Some("accepted"))
    assert_true(cancel_started)
    assert_true(cancel_effects.is_empty())
    runtime.run_command_job(
      cancel_id,
      identity,
      int_field(cancel_receipt, "accepted_revision").unwrap(),
      cancel_effects,
    )
    ignore(job.wait()) catch {
      _ => ()
    }
    let stop_payloads = @fs.read_file(workspace + "/cancel-stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(stop_payloads.length(), 1)
    let stop_payload = @json.parse(stop_payloads[0])
    assert_eq(
      string_field(stop_payload, "hook_event_name"),
      Some("SubagentStop"),
    )
    assert_eq(
      object_field(stop_payload, "stop_hook_active"),
      Some(Json::boolean(false)),
    )
    assert_eq(
      string_field(
        runtime.find_receipt(send_id, identity).unwrap().unwrap(),
        "status",
      ),
      Some("uncertain"),
    )
    release_sent.val = true
    release.release()
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    assert_true(response_errors.val.all(error => !error.is_empty()))
    let cancelled = runtime
      .invoke("session_get", { "session_id": session_id })
      .unwrap().0
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))

    runtime.close().unwrap()
    let reopened = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override=base_url,
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap().0
    assert_eq(string_field(restored, "status"), Some("cancelled"))
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_eq(bodies.val.length(), 2)
  }
}

///|
async test "native subagent semaphore cancellation does not dispatch queued parents or leak its permit" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-queued-cancel")
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
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_text_stream("First child completed."),
          ),
        ],
        bodies,
        auth_ok,
        Some(release),
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let first = native_subagent_parent_tool_effect(
      runtime, "native-subagent-first-parent", "first-parent-call", "Start first delegated task.",
    )
    let second = native_subagent_parent_tool_effect(
      runtime, "native-subagent-queued-parent", "queued-parent-call", "Wait for the child slot.",
    )
    let first_job = group.spawn(
      async fn() { runtime.run_tool_effect(first) },
      no_wait=true,
      allow_failure=true,
    )
    let mut first_child_started = false
    for _ in 0..<600 {
      if bodies.val.length() == 1 {
        first_child_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(first_child_started)

    let queued = @async.with_timeout_opt(100, async fn() {
      runtime.run_tool_effect(second)
    })
    assert_true(queued is None)
    assert_eq(bodies.val.length(), 1)
    let cancelled = runtime
      .invoke("session_cancel", {
        "session_id": "native-subagent-queued-parent",
      })
      .unwrap().0
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))

    release_sent.val = true
    release.release()
    match first_job.wait() {
      Ok((_, follow_up)) => {
        assert_eq(follow_up.length(), 1)
        assert_true(follow_up[0].kind() == @engine.EffectType::Provider)
      }
      _ =>
        fail(
          "the active parent did not finish after the child provider released",
        )
    }
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 1)
    let permit = @async.with_timeout_opt(100, async fn() {
      runtime.subagent_semaphore.acquire()
    })
    assert_true(permit is Some(_))
    runtime.subagent_semaphore.release()

    let completed_parent = runtime
      .invoke("session_get", { "session_id": "native-subagent-first-parent" })
      .unwrap().0
    assert_eq(
      string_field(
        native_subagent_result_for_call(completed_parent, "first-parent-call"),
        "status",
      ),
      Some("completed"),
    )
    runtime.close().unwrap()
    let reopened = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
      max_retries=0,
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", { "session_id": "native-subagent-first-parent" })
      .unwrap().0
    assert_eq(
      string_field(
        native_subagent_result_for_call(restored, "first-parent-call"),
        "status",
      ),
      Some("completed"),
    )
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_eq(bodies.val.length(), 1)
  }
}

///|
async test "native demo provider can execute the opt-in foreground subagent without credentials" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-demo")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(
      workspace + "/README.md",
      "demo-child-readable-line\nsecond line\n",
    )
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-demo"
    runtime
    .invoke("session_create", { "id": session_id, "title": "Demo subagent" })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Use the offline child to inspect README.md.",
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let (_, child_effects) = runtime.run_provider_effect(provider).unwrap()
    assert_eq(child_effects.length(), 1)
    assert_eq(
      string_field(child_effects[0].request(), "name"),
      Some("subagent"),
    )
    let (_, parent_follow_up) = runtime
      .run_tool_effect(child_effects[0])
      .unwrap()
    assert_eq(parent_follow_up.length(), 1)
    let (completed, trailing) = runtime
      .run_provider_effect(parent_follow_up[0])
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    let envelope = native_subagent_result_for_call(
      completed, "demo-subagent-call",
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_true(envelope.stringify().contains("demo-child-readable-line"))
  }
}

///|
async test "native subagent inherits the configured read hook policy" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-hook")
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
    @fs.write_file(workspace + "/target.txt", "must not be exposed")
    let command = "printf '%s' " +
      native_hook_shell_quote(
        "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"child read denied by fixture\"}}",
      )
    let config_path = fixture + "/hooks.json"
    @fs.write_file(
      config_path,
      native_hook_test_config("PreToolUse", "read", command),
    )
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              ("child-hook-read", "read", { "file_path": "target.txt" }),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "The child respected the read hook.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        hooks_config_path=Some(config_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_eq(runtime.hooks.pre_tool.length(), 1)
    let preflight = runtime.hooks
      .before_tool(runtime.tools, "synthetic-child", {
        "name": "read",
        "call_id": "synthetic-read",
        "arguments": { "file_path": "target.txt" },
      })
      .unwrap()
    assert_true(preflight.action is NativeHookAction::Deny(_))
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-hook", "parent-hook-call", "Use the child to read target.txt.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    let session = runtime
      .invoke("session_get", { "session_id": "native-subagent-hook" })
      .unwrap().0
    let envelope = native_subagent_result_for_call(session, "parent-hook-call")
    assert_eq(string_field(envelope, "status"), Some("completed"))
    if envelope.stringify().contains("must not be exposed") {
      fail(envelope.stringify())
    }
    assert_true(
      native_subagent_result_messages(envelope).any(message => {
        string_field(message, "role") == Some("tool") &&
        native_json_true(object_field(message, "is_error")) &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("child read denied by fixture")
      }),
    )
  }
}

///|
test "native subagent serialization overflow falls back to bounded valid JSON" {
  let messages : Array[Json] = []
  for _ in 0..<16 {
    messages.push({ "role": "assistant", "content": "\\\"".repeat(1024) })
  }
  let session : Json = { "step": 3, "messages": Json::array(messages) }
  let envelope = native_subagent_transcript_result(
    "subagent-serialization-overflow",
    "parent-session",
    "parent-effect",
    "parent-call",
    "Overflow fixture",
    session,
    "failed",
    Some("fixture terminal error"),
  )
  let serialized = envelope.stringify()
  assert_true(
    native_provider_utf16_units(serialized) <=
    NATIVE_SUBAGENT_MAX_TRANSCRIPT_UNITS,
  )
  let parsed = @json.parse(serialized)
  assert_eq(string_field(parsed, "schema"), Some("dsh-subagent-result-v1"))
  assert_true(native_json_true(object_field(parsed, "transcript_truncated")))
  assert_true(native_subagent_result_messages(parsed).is_empty())
  assert_eq(
    string_field(parsed, "failure_reason"),
    Some("fixture terminal error"),
  )
}

///|
async test "native subagent provider failure on the final step preserves its terminal error" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-provider-failure")
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
    @fs.write_file(workspace + "/target.txt", "child data")
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/failure-stop-payloads.jsonl\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"observation only\"}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_hook_test_config("SubagentStop", "general-purpose", stop_command),
      ),
    )
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              ("child-failure-read-1", "read", { "file_path": "target.txt" }),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              ("child-failure-read-2", "read", { "file_path": "target.txt" }),
            ]),
          ),
          { code: 401, reason: "Unauthorized", body: "", retry_after: None, },
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-provider-failure", "parent-provider-failure-call",
      "Exercise child provider error fidelity.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 3)
    let stop_payloads = @fs.read_file(
        workspace + "/failure-stop-payloads.jsonl",
      )
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(stop_payloads.length(), 1)
    assert_eq(
      string_field(@json.parse(stop_payloads[0]), "hook_event_name"),
      Some("SubagentStop"),
    )
    let session = runtime
      .invoke("session_get", {
        "session_id": "native-subagent-provider-failure",
      })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      session, "parent-provider-failure-call",
    )
    assert_eq(string_field(envelope, "status"), Some("failed"))
    assert_eq(int_field(envelope, "steps"), Some(3))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("provider endpoint returned HTTP 401"),
    )
    assert_true(
      !string_field(envelope, "failure_reason")
      .unwrap_or("")
      .contains("3-step limit"),
    )
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the provider failure.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
  }
}

///|
async test "native subagent enforces the eight child tool-call budget before dispatch" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-tool-budget")
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
    @fs.write_file(workspace + "/target.txt", "must not be read")
    let calls : Array[(String, String, Json)] = []
    for index in 0..<9 {
      calls.push(
        (
          "child-budget-read-" + index.to_string(),
          "read",
          { "file_path": "target.txt" },
        ),
      )
    }
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream(calls),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-tool-budget", "parent-tool-budget-call", "Exercise the child tool-call budget.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 1)
    let session = runtime
      .invoke("session_get", { "session_id": "native-subagent-tool-budget" })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      session, "parent-tool-budget-call",
    )
    assert_eq(string_field(envelope, "status"), Some("cancelled"))
    assert_eq(int_field(envelope, "steps"), Some(1))
    assert_eq(int_field(envelope, "tool_call_count"), Some(9))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("child exceeded the 8-tool-call limit"),
    )
    assert_true(
      !native_subagent_result_messages(envelope).any(message => {
        string_field(message, "role") == Some("tool") &&
        string_field(message, "content")
        .unwrap_or("")
        .contains("must not be read")
      }),
    )
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the child budget result.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
  }
}

///|
async test "native subagent timeout cancels a child waiting on its provider" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-timeout")
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
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/timeout-stop-payloads.jsonl\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"observation only\"}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_hook_test_config("SubagentStop", "general-purpose", stop_command),
      ),
    )
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
    let response_errors = Ref([])
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "The child response will remain behind the fixture gate.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        Some(release),
        response_errors=Some(response_errors),
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-timeout", "parent-timeout-call", "Exercise the child deadline.",
    )
    let job = group.spawn(
      async fn() { runtime.run_tool_effect(effect, subagent_timeout_ms=500) },
      no_wait=true,
      allow_failure=true,
    )
    let mut request_started = false
    for _ in 0..<400 {
      if bodies.val.length() == 1 {
        request_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(request_started)
    let (_, follow_up) = match job.wait() {
      Ok(value) => value
      Err(_) => fail("bounded subagent timeout did not settle the parent tool")
    }
    assert_eq(follow_up.length(), 1)
    let session = runtime
      .invoke("session_get", { "session_id": "native-subagent-timeout" })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      session, "parent-timeout-call",
    )
    assert_eq(string_field(envelope, "status"), Some("timed_out"))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("child run exceeded 500 ms"),
    )
    assert_eq(int_field(envelope, "steps"), Some(1))
    let stop_payloads = @fs.read_file(
        workspace + "/timeout-stop-payloads.jsonl",
      )
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(stop_payloads.length(), 1)
    assert_eq(
      string_field(@json.parse(stop_payloads[0]), "hook_event_name"),
      Some("SubagentStop"),
    )
    release_sent.val = true
    release.release()
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 1)
    assert_true(response_errors.val.all(error => !error.is_empty()))
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the timeout result.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
  }
}

///|
async test "native foreground child applies prompt context and Stop continuation hooks" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-lifecycle-hooks")
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
    let canonical_workspace = @fs.realpath(workspace)
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/child-stop-payloads.jsonl\"; if [ ! -e \"${CLAUDE_PROJECT_DIR}/first-child-stop\" ]; then : > \"${CLAUDE_PROJECT_DIR}/first-child-stop\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"continue after child review\"}'; else printf '{}'; fi"
    let prompt_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/child-prompt-payloads.jsonl\"; case \"$payload\" in *\"continue after child review\"*) printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"child continuation context\"}}' ;; *) printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"child initial context\"}}' ;; esac"
    let config = Json::object({
      "Stop": Json::array([
        Json::object({
          "matcher": Json::boolean(false),
          "hooks": Json::array([
            Json::object({ "command": Json::string(stop_command) }),
          ]),
        }),
      ]),
      "UserPromptSubmit": Json::array([
        Json::object({
          "matcher": Json::string("ignored prompt matcher"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(prompt_command) }),
          ]),
        }),
      ]),
    })
    @fs.write_file(hooks_path, @utf8.encode(config.stringify()))
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_text_stream("The first child answer."),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "The child continued after review.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_true(runtime.hooks.has_user_prompt_submit())
    assert_true(runtime.hooks.has_stop())
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-lifecycle-hooks", "parent-lifecycle-hook-call", "Use a child to finish this task.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    assert_true(
      @async.with_timeout_opt(5000, async fn() { serving.wait() }) is Some(_),
    )
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    assert_true(bodies.val[0].contains("child initial context"))
    assert_true(bodies.val[1].contains("child continuation context"))

    let prompt_lines = @fs.read_file(workspace + "/child-prompt-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(prompt_lines.length(), 3)
    let prompt_payloads : Array[Json] = []
    for line in prompt_lines {
      prompt_payloads.push(@json.parse(line))
    }
    assert_eq(prompt_payloads.length(), 3)
    let mut initial_prompt = Json::null()
    let mut continuation_prompt = Json::null()
    for payload in prompt_payloads {
      if string_field(payload, "prompt") ==
        Some("Complete the fixture child task.") {
        initial_prompt = payload
      } else if string_field(payload, "prompt") ==
        Some("continue after child review") {
        continuation_prompt = payload
      }
    }
    assert_true(initial_prompt is Json::Object(_))
    assert_true(continuation_prompt is Json::Object(_))
    let parent_session = runtime
      .invoke("session_get", { "session_id": "native-subagent-lifecycle-hooks" })
      .unwrap().0
    let child_id = string_field(
      native_subagent_result_for_call(
        parent_session, "parent-lifecycle-hook-call",
      ),
      "child_id",
    )
    assert_eq(string_field(initial_prompt, "session_id"), child_id)
    assert_eq(
      string_field(initial_prompt, "hook_event_name"),
      Some("UserPromptSubmit"),
    )
    assert_eq(string_field(initial_prompt, "transcript_path"), Some(""))
    assert_eq(string_field(initial_prompt, "cwd"), Some(canonical_workspace))
    assert_eq(
      string_field(continuation_prompt, "session_id"),
      string_field(initial_prompt, "session_id"),
    )
    assert_eq(
      string_field(continuation_prompt, "hook_event_name"),
      Some("UserPromptSubmit"),
    )

    let stop_lines = @fs.read_file(workspace + "/child-stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(stop_lines.length(), 2)
    for line in stop_lines {
      let payload = @json.parse(line)
      assert_eq(native_hook_test_fields(payload).length(), 5)
      assert_eq(string_field(payload, "hook_event_name"), Some("Stop"))
      assert_eq(string_field(payload, "transcript_path"), Some(""))
      assert_eq(
        object_field(payload, "stop_hook_active"),
        Some(Json::boolean(false)),
      )
      assert_eq(string_field(payload, "cwd"), Some(canonical_workspace))
      assert_eq(
        string_field(payload, "session_id"),
        string_field(initial_prompt, "session_id"),
      )
    }
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the child answer.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    let envelope = native_subagent_result_for_call(
      completed, "parent-lifecycle-hook-call",
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_eq(int_field(envelope, "steps"), Some(2))
  }
}

///|
async test "native SubagentStart remains detached, injects context, and Stop only observes" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-start-stop-hooks")
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
    let canonical_workspace = @fs.realpath(workspace)
    let hooks_path = fixture + "/hooks.json"
    let start_release_path = workspace + "/start-release"
    let prompt_release_path = workspace + "/prompt-release"
    let prompt_started_path = workspace + "/prompt-started"
    let start_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/subagent-start-payloads.jsonl\"; : > \"${CLAUDE_PROJECT_DIR}/start-started\"; while [ ! -e \"${CLAUDE_PROJECT_DIR}/start-release\" ]; do /bin/sleep 0.01; done; printf '%s' '{\"decision\":\"block\",\"reason\":\"ignored start denial\",\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"late child context\"}}'; : > \"${CLAUDE_PROJECT_DIR}/start-done\"; /bin/sleep 0.1"
    let unmatched_start_command = ": > \"${CLAUDE_PROJECT_DIR}/unmatched-start-fired\""
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/subagent-stop-payloads.jsonl\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"ignored stop denial\"}'"
    let prompt_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/subagent-prompt-payloads.jsonl\"; case \"$payload\" in *\"Complete the fixture child task.\"*) : > \"${CLAUDE_PROJECT_DIR}/prompt-started\"; while [ ! -e \"${CLAUDE_PROJECT_DIR}/prompt-release\" ]; do /bin/sleep 0.01; done; printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"initial prompt admission\"}}' ;; *\"late child context\"*) printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"late prompt admission\"}}' ;; *) printf '{}' ;; esac"
    let config = Json::object({
      "SubagentStart": Json::array([
        Json::object({
          "matcher": Json::string("general-purpose"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(start_command) }),
          ]),
        }),
        Json::object({
          "matcher": Json::string("code-review"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(unmatched_start_command) }),
          ]),
        }),
      ]),
      "SubagentStop": Json::array([
        Json::object({
          "matcher": Json::string("general-purpose"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(stop_command) }),
          ]),
        }),
      ]),
      "UserPromptSubmit": Json::array([
        Json::object({
          "matcher": Json::string("ignored prompt matcher"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(prompt_command) }),
          ]),
        }),
      ]),
    })
    @fs.write_file(hooks_path, @utf8.encode(config.stringify()))
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let release = @async.Semaphore::Semaphore(1, initial_value=0)
    let release_sent = Ref(false)
    group.add_defer(() => {
      @async.protect_from_cancel(async fn() {
        if !release_sent.val {
          release_sent.val = true
          release.release()
        }
        if !@fs.exists(start_release_path) {
          @fs.write_file(start_release_path, @utf8.encode("release"))
        }
        if !@fs.exists(prompt_release_path) {
          @fs.write_file(prompt_release_path, @utf8.encode("release"))
        }
      })
    })
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_subagent_provider_server_gated_index(
        server,
        [
          native_subagent_http_response(
            native_subagent_openai_text_stream_with_reason(
              "First child answer before context delivery.", "stop",
            ),
          ),
          native_subagent_http_response(
            native_subagent_openai_text_stream_with_reason(
              "Final child answer after context delivery.", "stop",
            ),
          ),
        ],
        bodies,
        auth_ok,
        0,
        release,
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
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_true(runtime.hooks.has_subagent_start())
    assert_true(runtime.hooks.has_subagent_stop())
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-start-stop-hooks", "parent-start-stop-hook-call",
      "Use a child to finish this task.",
    )
    let job = group.spawn(
      async fn() { runtime.run_tool_effect(effect) },
      no_wait=true,
      allow_failure=true,
    )
    let mut lifecycle_and_prompt_started = false
    for _ in 0..<1000 {
      if @fs.exists(workspace + "/start-started") &&
        @fs.exists(prompt_started_path) {
        lifecycle_and_prompt_started = true
        break
      }
      @async.sleep(5)
    }
    if !@fs.exists(workspace + "/start-started") {
      fail(
        "SubagentStart command did not start; provider requests=" +
        bodies.val.length().to_string(),
      )
    }
    assert_true(lifecycle_and_prompt_started)
    assert_true(bodies.val.is_empty())
    @fs.write_file(start_release_path, @utf8.encode("release"))
    let mut start_finished = false
    for _ in 0..<1000 {
      if @fs.exists(workspace + "/start-done") {
        start_finished = true
        break
      }
      @async.sleep(5)
    }
    assert_true(start_finished)
    // The hook subprocess emits before it exits; let its detached callback
    // enqueue input while the initial UserPromptSubmit command is still open.
    @async.sleep(200)
    @fs.write_file(prompt_release_path, @utf8.encode("release"))
    let mut first_provider_started = false
    for _ in 0..<1000 {
      if bodies.val.length() == 1 {
        first_provider_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(first_provider_started)
    assert_false(bodies.val[0].contains("late child context"))
    assert_true(bodies.val[0].contains("initial prompt admission"))
    release_sent.val = true
    release.release()
    let (_, follow_up) = match job.wait() {
      Ok(value) => value
      Err(_) => fail("native lifecycle hook task failed the child run")
    }
    assert_eq(follow_up.length(), 1)
    assert_true(
      @async.with_timeout_opt(5000, async fn() { serving.wait() }) is Some(_),
    )
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    assert_true(!bodies.val[0].contains("late child context"))
    assert_true(bodies.val[1].contains("late child context"))
    assert_true(bodies.val[1].contains("late prompt admission"))
    assert_false(@fs.exists(workspace + "/unmatched-start-fired"))

    let start_lines = @fs.read_file(
        workspace + "/subagent-start-payloads.jsonl",
      )
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    let stop_lines = @fs.read_file(workspace + "/subagent-stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    assert_eq(start_lines.length(), 1)
    assert_eq(stop_lines.length(), 1)
    let start_payload = @json.parse(start_lines[0])
    let stop_payload = @json.parse(stop_lines[0])
    assert_eq(native_hook_test_fields(start_payload).length(), 6)
    assert_eq(native_hook_test_fields(stop_payload).length(), 7)
    let child_id = string_field(start_payload, "session_id").unwrap()
    let prompt_lines = @fs.read_file(
        workspace + "/subagent-prompt-payloads.jsonl",
      )
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .to_array()
    let prompt_payloads : Array[Json] = []
    for line in prompt_lines {
      prompt_payloads.push(@json.parse(line))
    }
    let child_prompt_payloads = prompt_payloads.filter(payload => {
      string_field(payload, "session_id") == Some(child_id)
    })
    assert_eq(child_prompt_payloads.length(), 2)
    assert_eq(
      string_field(child_prompt_payloads[0], "prompt"),
      Some("Complete the fixture child task."),
    )
    assert_eq(
      string_field(child_prompt_payloads[1], "prompt"),
      Some("late child context"),
    )
    assert_eq(
      string_field(start_payload, "hook_event_name"),
      Some("SubagentStart"),
    )
    assert_eq(string_field(start_payload, "session_id"), Some(child_id))
    assert_eq(string_field(start_payload, "agent_id"), Some(child_id))
    assert_eq(
      string_field(start_payload, "agent_type"),
      Some("general-purpose"),
    )
    assert_eq(string_field(start_payload, "transcript_path"), Some(""))
    assert_eq(string_field(start_payload, "cwd"), Some(canonical_workspace))
    assert_true(object_field(start_payload, "stop_hook_active") is None)
    assert_eq(
      string_field(stop_payload, "hook_event_name"),
      Some("SubagentStop"),
    )
    assert_eq(string_field(stop_payload, "session_id"), Some(child_id))
    assert_eq(string_field(stop_payload, "agent_id"), Some(child_id))
    assert_eq(string_field(stop_payload, "agent_type"), Some("general-purpose"))
    assert_eq(string_field(stop_payload, "transcript_path"), Some(""))
    assert_eq(string_field(stop_payload, "cwd"), Some(canonical_workspace))
    assert_eq(
      object_field(stop_payload, "stop_hook_active"),
      Some(Json::boolean(false)),
    )

    let parent_session = runtime
      .invoke("session_get", {
        "session_id": "native-subagent-start-stop-hooks",
      })
      .unwrap().0
    let envelope = native_subagent_result_for_call(
      parent_session, "parent-start-stop-hook-call",
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_eq(int_field(envelope, "steps"), Some(2))
    assert_true(
      native_subagent_result_messages(envelope).any(message => {
        string_field(message, "content")
        .unwrap_or("")
        .contains("late child context")
      }),
    )
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the child answer.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    runtime.close().unwrap()
    let reopened = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override=base_url,
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", {
        "session_id": "native-subagent-start-stop-hooks",
      })
      .unwrap().0
    assert_eq(restored, completed)
    assert_true(reopened.api.take_typed_effects().is_empty())
    assert_eq(bodies.val.length(), 2)
    assert_eq(
      @fs.read_file(workspace + "/subagent-start-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .length(),
      1,
    )
    assert_eq(
      @fs.read_file(workspace + "/subagent-stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .length(),
      1,
    )
  }
}

///|
async test "native observational SubagentStop cannot turn a completed child into timed_out" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-stop-after-deadline")
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
    let hooks_path = fixture + "/hooks.json"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_hook_test_config(
          "SubagentStop", "general-purpose", "/bin/sleep 2",
        ),
      ),
    )
    let server = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_text_stream(
              "Completed before the observation hook ran.",
            ),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-stop-after-deadline", "parent-stop-after-deadline-call",
      "Delegate the fixture task.",
    )
    let (parent, _) = runtime
      .run_tool_effect(effect, subagent_timeout_ms=500)
      .unwrap()
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 1)
    let envelope = native_subagent_result_for_call(
      parent, "parent-stop-after-deadline-call",
    )
    assert_true(
      native_subagent_result_messages(envelope).any(message => {
        string_field(message, "content") ==
        Some("Completed before the observation hook ran.")
      }),
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
  }
}

///|
async test "native child UserPromptSubmit denial prevents provider admission" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-prompt-deny")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/prompt-payloads.jsonl\"; case \"$payload\" in *\"deny child prompt\"*) printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"child prompt denied by fixture\"}}' ;; *) printf '{}';; esac"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", command)),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime,
      "native-subagent-prompt-deny",
      "parent-prompt-deny-call",
      "Ask a child to do work.",
      child_prompt="deny child prompt",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received a child refusal.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    let envelope = native_subagent_result_for_call(
      completed, "parent-prompt-deny-call",
    )
    assert_eq(string_field(envelope, "status"), Some("failed"))
    assert_eq(int_field(envelope, "steps"), Some(0))
    assert_true(
      string_field(envelope, "failure_reason")
      .unwrap_or("")
      .contains("child prompt denied by fixture"),
    )
    let payload_lines = @fs.read_file(workspace + "/prompt-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
    let payloads : Array[Json] = []
    for line in payload_lines {
      payloads.push(@json.parse(line))
    }
    assert_true(
      payloads.any(payload => {
        string_field(payload, "session_id")
        .unwrap_or("")
        .has_prefix("subagent-") &&
        string_field(payload, "prompt") == Some("deny child prompt")
      }),
    )
  }
}

///|
async test "native child Stop denial cannot exceed the existing three-step limit" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-stop-max-steps")
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
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/stop-payloads.jsonl\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"continue child\"}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("Stop", "*", stop_command)),
    )
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_text_stream("Child step one."),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream("Child step two."),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream("Child step three."),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-stop-max-steps", "parent-stop-max-steps-call", "Ask a child to continue until bounded.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 3)
    assert_eq(
      @fs.read_file(workspace + "/stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .length(),
      3,
    )
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the bounded child result.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    let envelope = native_subagent_result_for_call(
      completed, "parent-stop-max-steps-call",
    )
    assert_eq(string_field(envelope, "status"), Some("failed"))
    assert_eq(int_field(envelope, "steps"), Some(3))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("child reached the 3-step limit before completing"),
    )
  }
}

///|
async test "native child Stop continuation keeps max-token completion sticky" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-stop-max-tokens")
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
    let hooks_path = fixture + "/hooks.json"
    let stop_command = "payload=$(cat); printf '%s\\n' \"$payload\" >> \"${CLAUDE_PROJECT_DIR}/stop-payloads.jsonl\"; if [ ! -e \"${CLAUDE_PROJECT_DIR}/first-child-stop\" ]; then : > \"${CLAUDE_PROJECT_DIR}/first-child-stop\"; printf '%s' '{\"decision\":\"block\",\"reason\":\"continue after max tokens\"}'; else printf '{}'; fi"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("Stop", "*", stop_command)),
    )
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_subagent_openai_text_stream_with_reason(
              "The first child answer reached its token limit.", "length",
            ),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream("The child continuation answer."),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-stop-max-tokens", "parent-stop-max-tokens-call",
      "Ask a child to finish despite a max-token stop.",
    )
    let (_, follow_up) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(follow_up.length(), 1)
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)
    assert_eq(
      @fs.read_file(workspace + "/stop-payloads.jsonl")
      .text()
      .split("\n")
      .filter(line => !line.is_empty())
      .length(),
      2,
    )
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the child token-limit result.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    let envelope = native_subagent_result_for_call(
      completed, "parent-stop-max-tokens-call",
    )
    assert_eq(string_field(envelope, "status"), Some("failed"))
    assert_eq(int_field(envelope, "steps"), Some(2))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("Model output reached its token limit"),
    )
  }
}

///|
async test "native child prompt hook stays inside the total deadline and is drained" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-prompt-hook-timeout")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        ignore(
          @fs.write_file(workspace + "/hook-release", @utf8.encode("release")),
        )
      })
    })
    let hooks_path = fixture + "/hooks.json"
    let command = "payload=$(cat); case \"$payload\" in *\"Complete the fixture child task.\"*) printf started > \"${CLAUDE_PROJECT_DIR}/hook-started\"; (trap '' TERM; while [ ! -f \"${CLAUDE_PROJECT_DIR}/hook-release\" ]; do /bin/sleep 0.01; done; printf escaped > \"${CLAUDE_PROJECT_DIR}/hook-child-alive\") & wait; printf '{}' ;; *) printf '{}';; esac"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", command)),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let effect = native_subagent_parent_tool_effect(
      runtime, "native-subagent-prompt-hook-timeout", "parent-prompt-timeout-call",
      "Ask a child to wait on its prompt hook.",
    )
    let job = group.spawn(
      async fn() { runtime.run_tool_effect(effect, subagent_timeout_ms=150) },
      no_wait=true,
      allow_failure=true,
    )
    let mut hook_started = false
    for _ in 0..<600 {
      if @fs.exists(workspace + "/hook-started") {
        hook_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(hook_started)
    let (_, follow_up) = match job.wait() {
      Ok(value) => value
      Err(_) => fail("child prompt deadline did not settle the parent tool")
    }
    assert_eq(follow_up.length(), 1)
    let (completed, trailing) = runtime
      .complete(follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the child timeout.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    let envelope = native_subagent_result_for_call(
      completed, "parent-prompt-timeout-call",
    )
    assert_eq(string_field(envelope, "status"), Some("timed_out"))
    assert_eq(
      string_field(envelope, "failure_reason"),
      Some("child run exceeded 150 ms"),
    )
    assert_eq(int_field(envelope, "steps"), Some(0))
    @fs.write_file(workspace + "/hook-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-child-alive"))
  }
}

///|
async test "native parent cancellation drains a running child prompt hook and frees the session" {
  let fixture = @fs.tmpdir(prefix="dsh-native-subagent-prompt-hook-cancel")
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
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        ignore(
          @fs.write_file(workspace + "/hook-release", @utf8.encode("release")),
        )
      })
    })
    let hooks_path = fixture + "/hooks.json"
    let command = "payload=$(cat); case \"$payload\" in *\"Wait on the child prompt hook.\"*) printf x >> \"${CLAUDE_PROJECT_DIR}/hook-count.txt\"; printf started > \"${CLAUDE_PROJECT_DIR}/hook-started\"; (trap '' TERM; while [ ! -f \"${CLAUDE_PROJECT_DIR}/hook-release\" ]; do /bin/sleep 0.01; done; printf escaped > \"${CLAUDE_PROJECT_DIR}/hook-child-alive\") & wait ;; esac; printf '{}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", command)),
    )
    let address = @socket.Addr::parse("127.0.0.1:0")
    let server = @http.Server::Server(address, reuse_addr=false)
    group.add_defer(() => server.close())
    let bodies = Ref([])
    let auth_ok = Ref(true)
    let serving = group.spawn(no_wait=true, async fn() {
      native_fixture_provider_server(
        server,
        [
          native_subagent_http_response(
            native_fixture_openai_calls_stream([
              (
                "parent-child-hook-cancel",
                "subagent",
                {
                  "description": "Wait",
                  "prompt": "Wait on the child prompt hook.",
                },
              ),
            ]),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let base_url = "http://127.0.0.1:" + server.addr.port().to_string()
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      false,
      mode_override="openai",
      model_override="fixture-model",
      base_url_override=base_url,
      max_retries=0,
      hooks_config_path=Some(hooks_path),
      enable_subagents=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-prompt-hook-cancel"
    runtime
    .invoke("session_create", { "id": session_id, "title": "Cancel child hook" })
    .unwrap()
    |> ignore
    let command_time = native_auth_now().to_int64() * 1000L
    let identity = runtime.state.identity_key
    let send_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time, "30112233445566778899aabbccddeeff",
    ).unwrap()
    let send = native_hook_remote_prompt_command(
      runtime.state.workspace_id,
      session_id,
      send_id,
      { "prompt": Json::string("Delegate and cancel the child prompt hook.") },
    )
    let (accepted, effects, should_start, control) = runtime
      .accept_remote_command(send, identity)
      .unwrap()
    assert_true(should_start)
    assert_eq(effects.length(), 1)
    let control = control.unwrap()
    let accepted_revision = int_field(accepted, "accepted_revision").unwrap()
    let job = group.spawn(
      async fn() {
        runtime.run_command_job(
          send_id,
          identity,
          accepted_revision,
          effects,
          control=Some(control),
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut hook_started = false
    for _ in 0..<600 {
      if @fs.exists(workspace + "/hook-started") {
        hook_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(hook_started)

    let cancel_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time + 1L,
      "40112233445566778899aabbccddeeff",
    ).unwrap()
    let cancel = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      cancel_id,
      "session_cancel",
      {},
    )
    let (cancel_receipt, cancel_effects, cancel_started, _) = runtime
      .accept_remote_command(cancel, identity)
      .unwrap()
    assert_eq(string_field(cancel_receipt, "status"), Some("accepted"))
    assert_true(cancel_started)
    assert_true(cancel_effects.is_empty())
    runtime.run_command_job(
      cancel_id,
      identity,
      int_field(cancel_receipt, "accepted_revision").unwrap(),
      cancel_effects,
    )
    ignore(job.wait()) catch {
      _ => ()
    }
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 1)
    assert_eq(
      string_field(
        runtime.find_receipt(send_id, identity).unwrap().unwrap(),
        "status",
      ),
      Some("uncertain"),
    )
    let cancelled = runtime
      .invoke("session_get", { "session_id": session_id })
      .unwrap().0
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))

    @fs.write_file(workspace + "/hook-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-child-alive"))
    assert_eq(@fs.read_file(workspace + "/hook-count.txt").text(), "x")
    let replay = native_hook_remote_prompt_command(
      runtime.state.workspace_id,
      session_id,
      send_id,
      { "prompt": Json::string("Delegate and cancel the child prompt hook.") },
    )
    let (replayed, replay_effects, replay_started, _) = runtime
      .accept_remote_command(replay, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("uncertain"))
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)

    let (_, fresh_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Fresh parent prompt after child hook cancellation.",
      })
      .unwrap()
    assert_eq(fresh_effects.length(), 1)
    assert_true(fresh_effects[0].kind() == @engine.EffectType::Provider)
    assert_eq(@fs.read_file(workspace + "/hook-count.txt").text(), "x")
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-child-alive"))
  }
}
