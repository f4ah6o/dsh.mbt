///|
fn native_subagent_http_response(body : String) -> NativeFixtureHttpResponse {
  { code: 200, reason: "OK", body, retry_after: None, }
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
    "prompt": "Complete the fixture child task.",
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
) -> Unit {
  for index in 0..<responses.length() {
    try {
      let (connection, _) = server.accept()
      defer connection.close()
      let gate = if index == gate_index { Some(release) } else { None }
      native_fixture_handle_provider_request(
        connection,
        bodies,
        auth_ok,
        responses[index],
        gate,
      )
    } catch {
      _ => ()
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
        max_retries=0,
        enable_subagents=true,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-subagent-restore"
    let (_, create_effects) = runtime
      .invoke("session_create", { "id": session_id, "title": "Subagent" })
      .unwrap()
    assert_true(create_effects.is_empty())
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
    assert_eq(bodies.val.length(), 4)
    for body in bodies.val {
      let request = @json.parse(body)
      assert_eq(string_field(request, "model"), Some("fixture-model"))
    }
    let parent_request = @json.parse(bodies.val[0])
    assert_true(native_subagent_tool_names(parent_request).contains("subagent"))
    let child_request = @json.parse(bodies.val[1])
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
    assert_eq(bodies.val.length(), 4)
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
    assert_eq(bodies.val.length(), 4)
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
      )
    })
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
    assert_true(preflight is NativeHookAction::Deny(_))
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
