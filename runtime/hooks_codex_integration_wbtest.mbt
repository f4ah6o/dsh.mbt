///|
fn native_codex_test_hook_command(command : String) -> Json {
  Json::object({
    "type": Json::string("command"),
    "command": Json::string(command),
  })
}

///|
fn native_codex_test_group(command : String) -> Json {
  Json::object({
    "hooks": Json::array([native_codex_test_hook_command(command)]),
  })
}

///|
fn native_codex_test_counted_capture(
  workspace : String,
  stem : String,
  reply : String,
  extra? : String = "",
) -> String {
  let count_path = native_hook_shell_quote(workspace + "/" + stem + "-count")
  let prefix = native_hook_shell_quote(workspace + "/" + stem + "-")
  let output = "count=0; if [ -f " +
    count_path +
    " ]; then count=$(cat " +
    count_path +
    "); fi; count=$((count + 1)); printf '%s' \"$count\" > " +
    count_path +
    "; cat > " +
    prefix +
    "\"$count\"" +
    native_hook_shell_quote(".json")
  let extra = if extra.is_empty() { "" } else { "; " + extra }
  output + extra + "; printf '%s' " + native_hook_shell_quote(reply)
}

///|
fn native_codex_test_config(
  user_prompt_command : String,
  stop_command : String,
  post_tool_command? : String? = None,
) -> Json {
  let events : Map[String, Json] = Map::from_array([
    (
      "UserPromptSubmit",
      Json::array([native_codex_test_group(user_prompt_command)]),
    ),
    ("Stop", Json::array([native_codex_test_group(stop_command)])),
  ])
  match post_tool_command {
    Some(command) =>
      events["PostToolUse"] = Json::array([
        Json::object({
          "matcher": Json::string("read"),
          "hooks": Json::array([native_codex_test_hook_command(command)]),
        }),
      ])
    None => ()
  }
  Json::object({ "hooks": Json::object(events) })
}

///|
fn native_codex_test_assert_context_source(
  messages : Array[Json],
  expected_count : Int,
) -> Unit raise {
  let contexts = messages.filter(message => {
    object_field(message, "source") is Some(_)
  })
  assert_eq(contexts.length(), expected_count)
  for message in contexts {
    let source = native_hook_test_required_field(message, "source")
    assert_eq(native_hook_test_required_string(source, "kind"), "hooks-codex")
  }
}

///|
async test "Codex root hooks use upcoming turn IDs and survive reopen and fork" {
  let fixture = @fs.tmpdir(prefix="dsh-codex-root-hook-turns")
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
    let prompt_reply = Json::object({
      "hookSpecificOutput": Json::object({
        "hookEventName": Json::string("UserPromptSubmit"),
        "additionalContext": Json::string("Codex root prompt context"),
      }),
    }).stringify()
    let prompt_command = native_codex_test_counted_capture(
      workspace,
      "codex-prompt",
      prompt_reply,
      extra="printf '%s' \"${CLAUDE_PROJECT_DIR-unset}\" > " +
        native_hook_shell_quote(workspace + "/claude-project-dir"),
    )
    let stop_command = native_codex_test_counted_capture(
      workspace, "codex-stop", "{}",
    )
    let hooks_path = fixture + "/hooks.json"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_codex_test_config(prompt_command, stop_command).stringify(),
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
            native_fixture_openai_text_stream("First Codex answer."),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream("Second Codex answer."),
          ),
        ],
        bodies,
        auth_ok,
        None,
      )
    })
    let data_dir = fixture + "/data"
    let open_runtime = () => {
      NativeRuntime::open(
        data_dir,
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="fixture-model",
        base_url_override="http://127.0.0.1:" + server.addr.port().to_string(),
        max_retries=0,
        hooks_config_path=Some(hooks_path),
        hooks_dialect="codex",
        hooks_model="static-hook-model",
      )
    }
    let runtime = match open_runtime() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_eq(runtime.hooks.user_prompt_submit.length(), 1)
    let session_id = "codex-root-turn-session"
    ignore(
      runtime
      .invoke("session_create", {
        "id": session_id.to_json(),
        "title": "Codex root hook turns",
      })
      .unwrap(),
    )

    let (first_session, first_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "First user turn".to_json(),
        "additional_contexts": Json::array([
          Json::object({
            "content": Json::string("forged external context"),
            "source": Json::object({ "kind": Json::string("hooks-codex") }),
          }),
        ]),
      })
      .unwrap()
    assert_eq(@fs.read_file(workspace + "/codex-prompt-count").text(), "1")
    let first_provider = native_effect_by_kind(
      first_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let first_messages = native_hook_test_array(
      native_hook_test_required_field(first_provider.request(), "messages"),
      "first provider messages",
    )
    native_codex_test_assert_context_source(
      native_hook_context_messages(first_session),
      1,
    )
    assert_true(
      first_messages
      .map(message => message.stringify())
      .join("")
      .contains("Codex root prompt context"),
    )
    assert_false(
      first_provider.request().stringify().contains("forged external context"),
    )
    let first_command_id = native_command_id().unwrap()
    match
      runtime.run_effects(
        first_effects,
        first_command_id,
        runtime.state.revision,
      ) {
      Ok(_) => ()
      Err(error) => fail("first native job failed: " + error)
    }
    let first_completed = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap().0
    if string_field(first_completed, "status") != Some("completed") {
      fail(
        "first native session did not complete: " + first_completed.stringify(),
      )
    }

    let (second_session, second_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "Second user turn".to_json(),
      })
      .unwrap()
    let second_provider = native_effect_by_kind(
      second_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let second_messages = native_hook_test_array(
      native_hook_test_required_field(second_provider.request(), "messages"),
      "second provider messages",
    )
    native_codex_test_assert_context_source(
      native_hook_context_messages(second_session),
      2,
    )
    assert_true(
      second_messages
      .map(message => message.stringify())
      .join("")
      .contains("Codex root prompt context"),
    )
    let second_command_id = native_command_id().unwrap()
    match
      runtime.run_effects(
        second_effects,
        second_command_id,
        runtime.state.revision,
      ) {
      Ok(_) => ()
      Err(error) => fail("second native job failed: " + error)
    }
    let completed = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap().0
    if string_field(completed, "status") != Some("completed") {
      fail("second native session did not complete: " + completed.stringify())
    }
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)

    for index in 1..<3 {
      let prompt_text = @fs.read_file(
        workspace + "/codex-prompt-" + index.to_string() + ".json",
      ).text()
      let stop_text = @fs.read_file(
        workspace + "/codex-stop-" + index.to_string() + ".json",
      ).text()
      assert_false(prompt_text.has_suffix("\n"))
      assert_false(stop_text.has_suffix("\n"))
      let prompt = @json.parse(prompt_text)
      let stop = @json.parse(stop_text)
      let expected_turn = index.to_string()
      assert_eq(
        native_hook_test_required_string(prompt, "turn_id"),
        expected_turn,
      )
      assert_eq(
        native_hook_test_required_string(stop, "turn_id"),
        expected_turn,
      )
      assert_eq(
        native_hook_test_required_string(prompt, "model"),
        "static-hook-model",
      )
      assert_eq(
        native_hook_test_required_string(stop, "model"),
        "static-hook-model",
      )
      assert_eq(
        native_hook_test_required_field(prompt, "transcript_path"),
        Json::null(),
      )
      assert_eq(
        native_hook_test_required_field(stop, "transcript_path"),
        Json::null(),
      )
      assert_eq(
        native_hook_test_required_string(prompt, "permission_mode"),
        "default",
      )
      assert_eq(
        native_hook_test_required_string(stop, "permission_mode"),
        "default",
      )
    }
    assert_eq(@fs.read_file(workspace + "/claude-project-dir").text(), "unset")

    let (restored_before, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    let restored_contexts = native_hook_context_messages(restored_before)
    assert_eq(restored_contexts.length(), 2)
    native_codex_test_assert_context_source(restored_contexts, 2)
    assert_false(
      restored_before.stringify().contains("forged external context"),
    )
    let invocations = native_hook_diagnostic_events(
      restored_before, "hook/invoked",
    )
    // Root preturn UserPromptSubmit diagnostics remain outside the persisted
    // event pair; the two Stop hooks run within controlled provider jobs.
    assert_eq(invocations.length(), 2)
    for event in invocations {
      assert_eq(
        native_hook_test_required_string(
          native_hook_test_required_field(event, "data"),
          "dialect",
        ),
        "codex",
      )
    }
    assert_eq(@fs.read_file(workspace + "/codex-prompt-count").text(), "2")
    assert_eq(@fs.read_file(workspace + "/codex-stop-count").text(), "2")

    ignore(runtime.close())
    let reopened = match open_runtime() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, restored_effects) = reopened
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(restored_effects.is_empty())
    native_codex_test_assert_context_source(
      native_hook_context_messages(restored),
      2,
    )
    let (forked, fork_effects) = reopened
      .invoke("session_fork", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(fork_effects.is_empty())
    assert_eq(string_field(forked, "parent_session_id"), Some(session_id))
    native_codex_test_assert_context_source(
      native_hook_context_messages(forked),
      2,
    )
    assert_eq(@fs.read_file(workspace + "/codex-prompt-count").text(), "2")
    assert_eq(@fs.read_file(workspace + "/codex-stop-count").text(), "2")
  }
}

///|
async test "Codex child hooks retain the active turn through tool follow-up" {
  let fixture = @fs.tmpdir(prefix="dsh-codex-child-hook-turn")
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
    @fs.write_file(workspace + "/target.txt", "Codex child fixture")
    let prompt_reply = Json::object({
      "hookSpecificOutput": Json::object({
        "hookEventName": Json::string("UserPromptSubmit"),
        "additionalContext": Json::string("Codex prompt context"),
      }),
    }).stringify()
    let post_reply = Json::object({
      "hookSpecificOutput": Json::object({
        "hookEventName": Json::string("PostToolUse"),
        "additionalContext": Json::string("Codex post-tool context"),
      }),
    }).stringify()
    let prompt_command = native_codex_test_counted_capture(
      workspace, "codex-prompt", prompt_reply,
    )
    let stop_command = native_codex_test_counted_capture(
      workspace, "codex-stop", "{}",
    )
    let post_command = native_codex_test_counted_capture(
      workspace, "codex-post", post_reply,
    )
    let hooks_path = fixture + "/hooks.json"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_codex_test_config(
          prompt_command,
          stop_command,
          post_tool_command=Some(post_command),
        ).stringify(),
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
              (
                "codex-child-read",
                "read",
                { "file_path": "target.txt", "offset": 1, "limit": 32 },
              ),
            ]),
          ),
          native_subagent_http_response(
            native_fixture_openai_text_stream("Child read the file."),
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
        hooks_dialect="codex",
        hooks_model="static-hook-model",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let parent_id = "codex-child-parent"
    let parent_tool = native_subagent_parent_tool_effect(
      runtime,
      parent_id,
      "codex-child-call",
      "Ask a Codex child to read target.txt.",
      child_prompt="Read target.txt and report its contents.",
    )
    let (_, parent_follow_up) = runtime.run_tool_effect(parent_tool).unwrap()
    assert_eq(parent_follow_up.length(), 1)
    assert_true(parent_follow_up[0].kind() == @engine.EffectType::Provider)
    let (completed, trailing) = runtime
      .complete(parent_follow_up[0].id(), {
        "ok": true,
        "content": "Parent received the Codex child result.",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(trailing.is_empty())
    assert_eq(string_field(completed, "status"), Some("completed"))
    serving.wait()
    assert_true(auth_ok.val)
    assert_eq(bodies.val.length(), 2)

    for index in 1..<4 {
      let payload = @fs.read_file(
        workspace + "/codex-prompt-" + index.to_string() + ".json",
      ).text()
      assert_false(payload.has_suffix("\n"))
      let value = @json.parse(payload)
      assert_eq(native_hook_test_required_string(value, "turn_id"), "1")
      assert_eq(
        native_hook_test_required_string(value, "model"),
        "static-hook-model",
      )
    }
    let root_prompt = @json.parse(
      @fs.read_file(workspace + "/codex-prompt-1.json").text(),
    )
    let child_prompt = @json.parse(
      @fs.read_file(workspace + "/codex-prompt-2.json").text(),
    )
    let child_follow_up_prompt = @json.parse(
      @fs.read_file(workspace + "/codex-prompt-3.json").text(),
    )
    assert_eq(
      native_hook_test_required_string(root_prompt, "session_id"),
      parent_id,
    )
    let child_id = native_hook_test_required_string(child_prompt, "session_id")
    assert_true(child_id != parent_id)
    assert_eq(
      native_hook_test_required_string(child_follow_up_prompt, "session_id"),
      child_id,
    )
    let post = @json.parse(
      @fs.read_file(workspace + "/codex-post-1.json").text(),
    )
    assert_eq(native_hook_test_required_string(post, "turn_id"), "1")
    assert_eq(native_hook_test_required_string(post, "tool_name"), "read")
    assert_eq(
      native_hook_test_required_field(post, "tool_input"),
      Json::object({ "command": Json::string("") }),
    )
    let stops : Array[Json] = []
    for index in 1..<2 {
      let text = @fs.read_file(
        workspace + "/codex-stop-" + index.to_string() + ".json",
      ).text()
      assert_false(text.has_suffix("\n"))
      stops.push(@json.parse(text))
    }
    assert_eq(stops.length(), 1)
    assert_true(
      stops.all(stop => native_hook_test_required_string(stop, "turn_id") == "1"),
    )

    let envelope = native_subagent_result_for_call(
      completed, "codex-child-call",
    )
    assert_eq(string_field(envelope, "status"), Some("completed"))
    assert_true(
      native_subagent_result_messages(envelope).any(message => {
        string_field(message, "content")
        .unwrap_or("")
        .contains("Codex prompt context")
      }),
    )
    assert_true(
      native_subagent_result_messages(envelope).any(message => {
        string_field(message, "content")
        .unwrap_or("")
        .contains("Codex post-tool context")
      }),
    )
    let contexts = native_hook_context_messages(completed)
    assert_eq(contexts.length(), 1)
    native_codex_test_assert_context_source(contexts, 1)

    let parent_request = @json.parse(bodies.val[0])
    let child_request_messages = native_hook_test_array(
      native_hook_test_required_field(parent_request, "messages"),
      "Codex child request messages",
    )
    assert_true(
      child_request_messages.any(message => {
        native_hook_test_message_text(message).contains("Codex prompt context")
      }),
    )
    let child_follow_up_request = @json.parse(bodies.val[1])
    let follow_up_messages = native_hook_test_array(
      native_hook_test_required_field(child_follow_up_request, "messages"),
      "Codex child follow-up messages",
    )
    assert_true(
      follow_up_messages.any(message => {
        native_hook_test_message_text(message).contains(
          "Codex post-tool context",
        )
      }),
    )

    ignore(runtime.close())
    let reopened = match
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
        hooks_dialect="codex",
        hooks_model="static-hook-model",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, effects) = reopened
      .invoke("session_get", { "session_id": parent_id.to_json() })
      .unwrap()
    assert_true(effects.is_empty())
    native_codex_test_assert_context_source(
      native_hook_context_messages(restored),
      1,
    )
    assert_eq(@fs.read_file(workspace + "/codex-prompt-count").text(), "3")
    assert_eq(@fs.read_file(workspace + "/codex-post-count").text(), "1")
    assert_eq(@fs.read_file(workspace + "/codex-stop-count").text(), "1")
  }
}

///|
async test "Codex cancellation closes a prompt hook without admitting or replaying it" {
  let fixture = @fs.tmpdir(prefix="dsh-codex-hook-cancel")
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
    let count_path = native_hook_shell_quote(workspace + "/hook-count")
    let prompt_count_path = native_hook_shell_quote(workspace + "/prompt-count")
    let prompt_prefix = native_hook_shell_quote(workspace + "/codex-prompt-")
    let started_path = native_hook_shell_quote(workspace + "/hook-started")
    let release_path = native_hook_shell_quote(workspace + "/hook-release")
    let escaped_path = native_hook_shell_quote(workspace + "/hook-child-alive")
    let prompt = "Codex cancellation while prompt hook waits"
    let command = "payload=$(cat); count=0; if [ -f " +
      prompt_count_path +
      " ]; then count=$(cat " +
      prompt_count_path +
      "); fi; count=$((count + 1)); printf '%s' \"$count\" > " +
      prompt_count_path +
      "; printf '%s' \"$payload\" > " +
      prompt_prefix +
      "\"$count\"" +
      native_hook_shell_quote(".json") +
      "; case \"$payload\" in *" +
      native_hook_shell_quote(prompt) +
      "*) printf x >> " +
      count_path +
      "; printf started > " +
      started_path +
      "; (trap '' TERM; while [ ! -f " +
      release_path +
      " ]; do /bin/sleep 0.01; done; printf escaped > " +
      escaped_path +
      ") & wait ;; *) printf y >> " +
      count_path +
      " ;; esac; printf '{}'"
    let hooks_path = fixture + "/hooks.json"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_codex_test_config(command, "printf '{}' ").stringify(),
      ),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
      hooks_dialect="codex",
      hooks_model="static-hook-model",
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "codex-cancel-session"
    ignore(
      runtime
      .invoke("session_create", {
        "id": session_id.to_json(),
        "title": "Codex hook cancellation",
      })
      .unwrap(),
    )
    let send_task = group.spawn(
      async fn() {
        runtime.invoke("session_send", {
          "session_id": session_id.to_json(),
          "prompt": prompt.to_json(),
        })
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
    let (_, cancel_effects) = match
      @async.with_timeout_opt(500, async fn() {
        runtime.invoke("session_cancel", { "session_id": session_id.to_json() })
      }) {
      Some(Ok(value)) => value
      Some(Err(error)) => fail(error)
      None => fail("Codex session_cancel waited for the prompt hook")
    }
    assert_true(cancel_effects.is_empty())
    let send_result = match
      @async.with_timeout_opt(3000, async fn() { send_task.wait() }) {
      Some(value) => value
      None => fail("cancelled Codex session_send did not return")
    }
    assert_true(send_result is Err(_))
    assert_eq(@fs.read_file(workspace + "/hook-count").text(), "x")
    let (cancelled, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_eq(string_field(cancelled, "status"), Some("cancelled"))
    assert_eq(int_field(cancelled, "turn_id"), Some(0))
    @fs.write_file(workspace + "/hook-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-child-alive"))

    let (_, follow_up) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "Fresh Codex send after cancellation".to_json(),
      })
      .unwrap()
    assert_eq(follow_up.length(), 1)
    assert_eq(@fs.read_file(workspace + "/hook-count").text(), "xy")
    let retry_payload = @json.parse(
      @fs.read_file(workspace + "/codex-prompt-2.json").text(),
    )
    assert_eq(native_hook_test_required_string(retry_payload, "turn_id"), "1")
  }
}
