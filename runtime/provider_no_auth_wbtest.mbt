///|
fn native_no_auth_array(value : Json, name : String) -> Array[Json] {
  match object_field(value, name) {
    Some(Array(values)) => values
    _ => []
  }
}

///|
fn native_no_auth_request() -> Json {
  {
    "messages": [
      { "role": "user", "content": "Read README.md" },
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "prior",
            "name": "read_file",
            "arguments": "{\"path\":\"README.md\"}",
          },
        ],
      },
      { "role": "tool", "tool_call_id": "prior", "content": "# fixture" },
    ],
    "tools": [
      {
        "name": "read_file",
        "description": "Read a file",
        "input_schema": {
          "type": "object",
          "properties": { "path": { "type": "string" } },
        },
      },
    ],
  }
}

///|
async fn native_no_auth_serve_connection(
  connection : @http.ServerConnection,
  response : NativeFixtureHttpResponse,
  bodies : Ref[Array[Json]],
  authorization : String?,
  path : String,
  content_type : String,
) -> Bool {
  defer connection.close()
  let request = connection.read_request() catch {
    error if error.to_string() == "ReaderClosed" => return false
    error => raise error
  }
  assert_true(request.meth is @http.Post)
  assert_eq(request.path, path)
  assert_eq(request.headers.get("authorization"), authorization)
  assert_eq(request.headers.get("x-api-key"), None)
  assert_eq(request.headers.get("cookie"), None)
  assert_eq(request.headers.get("content-type"), Some("application/json"))
  assert_eq(request.headers.get("accept"), Some("text/event-stream"))
  bodies.val.push(@json.parse(connection.read_all().text()))
  connection.send_response(response.code, response.reason, extra_headers={
    "Content-Type": content_type,
    "Connection": "close",
    "Retry-After": response.retry_after.unwrap_or("0"),
  })
  for line in response.body.split("\n") {
    connection.write_string(line.to_owned() + "\n")
    connection.flush()
    @async.sleep(0)
  }
  connection.end_response()
  true
}

///|
async fn native_no_auth_serve(
  server : @http.Server,
  responses : Array[NativeFixtureHttpResponse],
  bodies : Ref[Array[Json]],
  authorization : String?,
  path : String,
  content_type~ : String = "text/event-stream",
) -> Unit {
  for response in responses {
    let mut ignored = 0
    for ;; {
      let (connection, _) = server.accept()
      if native_no_auth_serve_connection(
          connection, response, bodies, authorization, path, content_type,
        ) {
        break
      }
      ignored += 1
      assert_true(ignored <= NATIVE_FIXTURE_MAX_EMPTY_PROVIDER_CONNECTIONS)
    }
  }
}

///|
test "unauthenticated selection requires a safe explicit root and model" {
  for
    root in [
      "", "http://public.example/v1", "https://user:pass@example.test", "https://example.test?key=x",
      "https://example.test/#fragment", "https://example.test/../v1", "https://example.test/\r\nheader",
    ] {
    assert_true(
      NativeProviderSelection::no_auth("big-pickle", root, "generation")
      is Err(_),
    )
  }
  assert_true(
    NativeProviderSelection::no_auth(
      "", "https://opencode.ai/inference/openai/v1", "generation",
    )
    is Err(_),
  )
  assert_true(
    NativeProviderSelection::no_auth(
      "big-pickle", "https://opencode.ai/inference/openai/v1", "",
    )
    is Err(_),
  )
  for
    root in [
      "https://opencode.ai/inference/openai", "https://opencode.ai/inference/openai/",
      "https://opencode.ai/inference/openai/v1", "https://opencode.ai/inference/openai/v1/",
    ] {
    let selection = NativeProviderSelection::no_auth(
      "big-pickle", root, "generation",
    ).unwrap()
    assert_true(selection.auth_mode() == NoAuth)
    assert_true(selection.protocol() == OpenAIChatCompletions)
    assert_eq(
      native_provider_base_url(root).unwrap(),
      ("https://opencode.ai", "/inference/openai"),
    )
  }
}

///|
async test "API-key mode still rejects absent and invalid credentials before connecting" {
  let selection = NativeProviderSelection::api_key(
    OpenAIChatCompletions,
    "fixture-model",
    Some("http://127.0.0.1:1"),
    "generation",
  ).unwrap()
  for key in ["", "invalid\r\nheader"] {
    let result = native_run_configured_provider(
      selection,
      native_no_auth_request(),
      key,
      fn(_, _) { Ok(()) },
    ).unwrap()
    assert_eq(
      string_field(object_field(result, "failure").unwrap(), "code"),
      Some("AUTH"),
    )
  }
}

///|
async test "explicit no-auth and bearer requests preserve URL model tools and streaming" {
  for
    suffix in [
      "/inference/openai", "/inference/openai/", "/inference/openai/v1", "/inference/openai/v1/",
    ] {
    for no_auth in [true, false] {
      let server = @http.Server::Server(
        @socket.Addr::parse("127.0.0.1:0"),
        reuse_addr=false,
      )
      defer server.close()
      let bodies = Ref([])
      let base = "http://127.0.0.1:" + server.addr.port().to_string() + suffix
      let selection = if no_auth {
        NativeProviderSelection::no_auth("big-pickle", base, "generation").unwrap()
      } else {
        NativeProviderSelection::api_key(
          OpenAIChatCompletions,
          "big-pickle",
          Some(base),
          "generation",
        ).unwrap()
      }
      let delta = Ref("")
      @async.with_task_group() <| group => {
        let serving = group.spawn(no_wait=true, async fn() {
          native_no_auth_serve(
            server,
            [
              {
                code: 200,
                reason: "OK",
                body: native_fixture_openai_text_stream("会話🌙"),
                retry_after: None,
              },
            ],
            bodies,
            if no_auth {
              None
            } else {
              Some("Bearer fixture-key")
            },
            "/inference/openai/v1/chat/completions",
          )
        })
        let result = native_run_configured_provider(
          selection,
          native_no_auth_request(),
          "fixture-key",
          fn(text, _) {
            delta.val += text
            Ok(())
          },
        ).unwrap()
        assert_eq(string_field(result, "content"), Some("会話🌙"))
        assert_eq(delta.val, "会話🌙")
        serving.wait()
      }
      assert_eq(bodies.val.length(), 1)
      let body = bodies.val[0]
      assert_eq(string_field(body, "model"), Some("big-pickle"))
      assert_true(native_json_true(object_field(body, "stream")))
      let tool = native_no_auth_array(body, "tools")[0]
      assert_eq(
        string_field(object_field(tool, "function").unwrap(), "name"),
        Some("read_file"),
      )
      let history = native_no_auth_array(body, "messages")
      assert_eq(
        string_field(history[history.length() - 1], "tool_call_id"),
        Some("prior"),
      )
    }
  }
}

///|
async test "no-auth streams normalize tool calls and classify HTTP and malformed errors" {
  let tool_stream = native_fixture_openai_calls_stream([
    ("call-free", "read_file", { "path": "README.md" }),
  ])
  for
    (status, body, content_type, expected) in [
      (200, tool_stream, "text/event-stream", ""),
      (401, "secret-provider-body", "application/json", "AUTH"),
      (403, "secret-provider-body", "application/json", "AUTH"),
      (429, "rate limited", "application/json", "RATE_LIMIT"),
      (503, "unavailable", "application/json", "SERVER"),
      (200, "data: {broken}\n\n", "text/event-stream", "MALFORMED"),
      (200, "{}", "application/json", "MALFORMED"),
    ] {
    let server = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    defer server.close()
    let selection = NativeProviderSelection::no_auth(
      "big-pickle",
      "http://127.0.0.1:" + server.addr.port().to_string(),
      "generation",
    ).unwrap()
    let bodies = Ref([])
    @async.with_task_group() <| group => {
      let serving = group.spawn(no_wait=true, async fn() {
        native_no_auth_serve(
          server,
          [{ code: status, reason: "Fixture", body, retry_after: Some("1"), }],
          bodies,
          None,
          "/v1/chat/completions",
          content_type~,
        )
      })
      let result = native_run_configured_provider(
        selection,
        native_no_auth_request(),
        "ignored\r\nkey",
        fn(_, _) { Ok(()) },
      ).unwrap()
      if expected.is_empty() {
        let call = native_no_auth_array(result, "tool_calls")[0]
        assert_eq(string_field(call, "id"), Some("call-free"))
        assert_eq(string_field(call, "name"), Some("read_file"))
        assert_eq(
          string_field(call, "arguments"),
          Some("{\"path\":\"README.md\"}"),
        )
      } else {
        assert_eq(
          string_field(object_field(result, "failure").unwrap(), "code"),
          Some(expected),
        )
        assert_true(!result.stringify().contains("secret-provider-body"))
        assert_true(!result.stringify().contains("ignored"))
      }
      serving.wait()
    }
  }
}

///|
test "no-auth configuration requires explicit auth root model and Chat Completions" {
  let names = ["DSH_AUTH", "DSH_BASE_URL", "DSH_MODEL"]
  let saved = names.map(name => (name, @env.get_env_var(name)))
  defer native_fixture_restore_env(saved)
  @env.unset_env_var("DSH_BASE_URL")
  @env.unset_env_var("DSH_MODEL")
  @env.unset_env_var("DSH_AUTH")
  assert_true(
    native_provider_config(
      false, "openai", "fixture-model", "https://example.test/v1", 0,
    ).unwrap().auth_mode ==
    ApiKey,
  )
  @env.set_env_var("DSH_AUTH", "none")
  assert_true(
    native_provider_config(false, "openai", "fixture-model", "", 0) is Err(_),
  )
  for mode in ["deepseek", "openai-responses"] {
    assert_true(
      native_provider_config(
        false, mode, "fixture-model", "https://example.test/v1", 0,
      )
      is Err(_),
    )
  }
  assert_true(
    native_provider_config(false, "openai", "", "https://example.test/v1", 0)
    is Err(_),
  )
  assert_true(
    native_provider_config(
      false, "openai", "big-pickle", "https://example.test/v1", 0,
    ).unwrap().auth_mode ==
    NoAuth,
  )
}

///|
async test "no-auth parent and child dispatch omit credentials and respect ChatGPT selection" {
  let fixture = @fs.tmpdir(prefix="dsh-no-auth")
  defer @fs.rmdir(fixture, recursive=true)
  let server = @http.Server::Server(
    @socket.Addr::parse("127.0.0.1:0"),
    reuse_addr=false,
  )
  defer server.close()
  let bodies = Ref([])
  let runtime = NativeRuntime::open(
    fixture + "/data",
    fixture,
    false,
    false,
    mode_override="openai",
    model_override="big-pickle",
    base_url_override="http://127.0.0.1:" +
      server.addr.port().to_string() +
      "/inference/openai/v1",
    max_retries=0,
  ).unwrap()
  let runtime = {
    ..runtime,
    provider_config: { ..runtime.provider_config, auth_mode: NoAuth, },
  }
  defer ignore(runtime.close())
  @async.with_task_group() <| group => {
    let serving = group.spawn(no_wait=true, async fn() {
      native_no_auth_serve(
        server,
        [
          {
            code: 200,
            reason: "OK",
            body: native_fixture_openai_text_stream("parent completed"),
            retry_after: None,
          },
          {
            code: 200,
            reason: "OK",
            body: native_fixture_openai_text_stream("child completed"),
            retry_after: None,
          },
        ],
        bodies,
        None,
        "/inference/openai/v1/chat/completions",
      )
    })
    ignore(runtime.invoke("session_create", { "id": "free-session" }).unwrap())
    let (_, effects) = runtime
      .invoke("session_send", {
        "session_id": "free-session",
        "prompt": "Say hi",
      })
      .unwrap()
    assert_eq(effects.length(), 1)
    ignore(runtime.run_provider_effect(effects[0]).unwrap())
    let binding = runtime.subagent_provider_binding("free-session").unwrap()
    assert_true(binding.selection.auth_mode() == NoAuth)
    assert_eq(binding.api_key, None)
    let result = runtime
      .subagent_provider_request(binding, native_no_auth_request())
      .unwrap()
    assert_eq(string_field(result, "content"), Some("child completed"))
    serving.wait()
    assert_eq(bodies.val.length(), 2)
    runtime.auth.provider_choice = "chatgpt"
    assert_true(runtime.effective_provider_config().auth_mode == ChatGPT)
    assert_true(
      runtime.validate_provider_selection(binding.selection) is Err(_),
    )
    runtime.auth.provider_choice = "configured"
  }
}

///|
async test "CLI no-auth ignores environment keys in an isolated process" {
  let executable = safety_native_worker_launcher().unwrap()
  let fixture = @fs.tmpdir(prefix="dsh-no-auth-cli")
  defer @fs.rmdir(fixture, recursive=true)
  let server = @http.Server::Server(
    @socket.Addr::parse("127.0.0.1:0"),
    reuse_addr=false,
  )
  defer server.close()
  let bodies = Ref([])
  @async.with_task_group() <| group => {
    let serving = group.spawn(no_wait=true, async fn() {
      native_no_auth_serve(
        server,
        [
          {
            code: 200,
            reason: "OK",
            body: native_fixture_openai_text_stream("DSH_OK"),
            retry_after: None,
          },
        ],
        bodies,
        None,
        "/inference/openai/v1/chat/completions",
      )
    })
    let result = @async.with_timeout_opt(10000, async fn() {
      @process.collect_output(
        executable,
        [
          "run",
          "Say DSH_OK",
          "--mode",
          "openai",
          "--model",
          "big-pickle",
          "--base-url",
          "http://127.0.0.1:" +
          server.addr.port().to_string() +
          "/inference/openai/v1/",
          "--workspace",
          fixture,
          "--data-dir",
          fixture + "/data",
          "--max-retries",
          "0",
          "--json",
        ],
        extra_env=Map([
          ("DSH_AUTH", "none"),
          ("DSH_API_KEY", "must-not-be-sent\r\n"),
          ("OPENAI_API_KEY", "must-not-be-sent"),
          ("DEEPSEEK_API_KEY", "must-not-be-sent"),
        ]),
      )
    })
    let (status, stdout, stderr) = result.unwrap()
    assert_eq(status, 0)
    assert_eq(stderr.text(), "")
    let session = @json.parse(stdout.text())
    assert_eq(string_field(session, "status"), Some("completed"))
    assert_true(session.stringify().contains("DSH_OK"))
    assert_true(!session.stringify().contains("must-not-be-sent"))
    serving.wait()
    assert_eq(bodies.val.length(), 1)
    assert_eq(string_field(bodies.val[0], "model"), Some("big-pickle"))
  }
}
