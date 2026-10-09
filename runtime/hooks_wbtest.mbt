///|
fn native_hook_test_config(
  event : String,
  matcher : String,
  command : String,
) -> String {
  let hook = Json::object({
    "type": Json::string("command"),
    "command": Json::string(command),
  })
  let group = Json::object({
    "matcher": Json::string(matcher),
    "hooks": Json::array([hook]),
  })
  Json::object(Map::from_array([(event, Json::array([group]))])).stringify()
}

///|
fn native_hook_test_tools(workspace : String) -> NativeTools {
  let root = SafeRoot::open(workspace).unwrap()
  let (device, inode) = root.identity().unwrap()
  let worker = @env.get_env_var("DSH_NATIVE_WORKER_BIN").unwrap()
  NativeTools::new(root, workspace, None, false, worker, device, inode)
}

///|
fn native_hook_has_successful_write_result(session : Json) -> Bool {
  match object_field(session, "events") {
    Some(Json::Array(events)) =>
      events.any(event => {
        if string_field(event, "type") != Some("tool/result") {
          false
        } else {
          let data = object_field(event, "data").unwrap_or(Json::null())
          !native_json_true(object_field(data, "is_error")) &&
          string_field(data, "content") ==
          Some("Wrote 26 bytes to native-demo.txt.")
        }
      })
    _ => false
  }
}

///|
fn native_hook_has_event(
  session : Json,
  event_type : String,
  call_id : String,
  source : String?,
) -> Bool {
  match object_field(session, "events") {
    Some(Json::Array(events)) =>
      events.any(event => {
        if string_field(event, "type") != Some(event_type) {
          false
        } else {
          let data = object_field(event, "data").unwrap_or(Json::null())
          string_field(data, "call_id") == Some(call_id) &&
          string_field(data, "source") == source
        }
      })
    _ => false
  }
}

///|
fn native_hook_tool_result_ids(session : Json) -> Array[String] {
  let output : Array[String] = []
  match object_field(session, "messages") {
    Some(Json::Array(messages)) =>
      for message in messages {
        if string_field(message, "role") == Some("tool") {
          output.push(string_field(message, "tool_call_id").unwrap_or(""))
        }
      }
    _ => ()
  }
  output
}

///|
fn native_hook_tool_result(session : Json, call_id : String) -> Json? {
  match object_field(session, "events") {
    Some(Json::Array(events)) =>
      for event in events {
        if string_field(event, "type") == Some("tool/result") {
          let data = object_field(event, "data").unwrap_or(Json::null())
          if string_field(data, "tool_call_id") == Some(call_id) {
            return Some(data)
          }
        }
      }
    _ => ()
  }
  None
}

///|
test "native Claude hook config rejects unsupported events and matcher syntax" {
  assert_true(native_hook_parse_config(@json.parse("{\"Stop\":[]}")) is Err(_))
  assert_true(
    native_hook_parse_config(
      @json.parse(
        "{\"PreToolUse\":[{\"matcher\":\"write.*\",\"hooks\":[{\"command\":\"true\"}]}]}",
      ),
    )
    is Err(_),
  )
  let mcp_alias = "mcp__server-name__tool"
  assert_true(
    native_hook_parse_config(
      @json.parse(
        "{\"PreToolUse\":[{\"matcher\":\"mcp__server-name__tool|write\",\"hooks\":[{\"command\":\"true\"}]}]}",
      ),
    )
    is Ok(_),
  )
  assert_true(native_hook_matches(Some(mcp_alias), mcp_alias))
  assert_false(native_hook_matches(Some(mcp_alias), "mcp__server_name__tool"))
  assert_true(
    native_hook_parse_config(
      @json.parse(
        "{\"PreToolUse\":[{\"hooks\":[{\"type\":\"prompt\",\"command\":\"true\"}]}]}",
      ),
    )
    is Err(_),
  )
  assert_true(
    native_hook_parse_config(
      @json.parse(
        "{\"PostToolUse\":[{\"hooks\":[{\"command\":\"true\",\"timeout\":121}]}]}",
      ),
    )
    is Err(_),
  )
}

///|
test "native hook result codec preserves supported Claude exit and decision semantics" {
  let exit_two = native_hook_result_decision(
    {
      exit_code: 2,
      stdout: "ignored",
      stderr: "policy says no",
      truncated: false,
    },
    "PreToolUse",
  )
  assert_true(exit_two is Ok(NativeHookAction::Deny("policy says no")))
  let denied = native_hook_result_decision(
    {
      exit_code: 0,
      stdout: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"blocked\"}}",
      stderr: "",
      truncated: false,
    },
    "PreToolUse",
  )
  assert_true(denied is Ok(NativeHookAction::Deny("blocked")))
  let allow_overrides_legacy_block = native_hook_result_decision(
    {
      exit_code: 0,
      stdout: "{\"decision\":\"block\",\"reason\":\"legacy\",\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}",
      stderr: "",
      truncated: false,
    },
    "PreToolUse",
  )
  assert_true(allow_overrides_legacy_block is Ok(NativeHookAction::Continue))
  let mismatched_event = native_hook_result_decision(
    {
      exit_code: 0,
      stdout: "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"permissionDecision\":\"deny\"}}",
      stderr: "",
      truncated: false,
    },
    "PreToolUse",
  )
  assert_true(mismatched_event is Ok(NativeHookAction::Continue))
  let nonblocking_exit = native_hook_result_decision(
    {
      exit_code: 7,
      stdout: "{\"decision\":\"block\"}",
      stderr: "",
      truncated: false,
    },
    "PreToolUse",
  )
  assert_true(nonblocking_exit is Ok(NativeHookAction::Continue))
  assert_true(
    native_hook_result_decision(
      { exit_code: 0, stdout: "{not-json}", stderr: "", truncated: false, },
      "PreToolUse",
    )
    is Err(_),
  )
  assert_true(
    native_hook_result_decision(
      {
        exit_code: 0,
        stdout: "{\"decision\":\"deny\"}",
        stderr: "",
        truncated: false,
      },
      "PreToolUse",
    )
    is Err(_),
  )
  assert_true(
    native_hook_result_decision(
      {
        exit_code: 0,
        stdout: "{\"additionalContext\":\"not supported\"}",
        stderr: "",
        truncated: false,
      },
      "PostToolUse",
    )
    is Err(_),
  )
  assert_true(
    native_hook_result_decision(
      { exit_code: 0, stdout: "{}", stderr: "", truncated: true, },
      "PreToolUse",
    )
    is Err(_),
  )
}

///|
async test "native hook subprocess bounds streams, scrubs env, and kills timeout descendants" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-process")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let tools = native_hook_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    let previous_secret = @env.get_env_var("NATIVE_HOOK_TEST_SECRET")
    @env.set_env_var("NATIVE_HOOK_TEST_SECRET", "hook-test-secret")
    group.add_defer(() => {
      match previous_secret {
        Some(value) => @env.set_env_var("NATIVE_HOOK_TEST_SECRET", value)
        None => @env.unset_env_var("NATIVE_HOOK_TEST_SECRET")
      }
    })

    let stdin_probe = match
      native_run_hook_command(
        tools,
        {
          command: "if [ \"${NATIVE_HOOK_TEST_SECRET-}\" = hook-test-secret ]; then printf leaked; else printf scrubbed; fi; cat",
          timeout_ms: 3000,
        },
        "{\"payload\":true}\n",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(stdin_probe.stdout, "scrubbed{\"payload\":true}\n")
    assert_eq(stdin_probe.stderr, "")
    assert_false(stdin_probe.truncated)

    let oversized = native_run_hook_command(
      tools,
      { command: "head -c 17000 /dev/zero", timeout_ms: 3000, },
      "{}\n",
    )
    assert_true(oversized is Ok(value) && value.truncated)

    let oversized_before_timeout = native_run_hook_command(
      tools,
      { command: "head -c 17000 /dev/zero; /bin/sleep 5", timeout_ms: 400, },
      "{}\n",
    )
    assert_true(oversized_before_timeout is Ok(value) && value.truncated)
    assert_true(
      native_hook_result_decision(
        oversized_before_timeout.unwrap(),
        "PreToolUse",
      )
      is Err(_),
    )

    let timeout_hook = {
      command: "(printf ready > hook-child-ready; while [ ! -f hook-timeout-release ]; do /bin/sleep 0.01; done; printf escaped > hook-child-alive) & wait",
      timeout_ms: 400,
    }
    let timeout_result = native_run_hook_command(tools, timeout_hook, "{}\n")
    assert_true(timeout_result is Err(_))
    @fs.write_file(workspace + "/hook-timeout-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-child-alive"))

    let leader_exits_with_child = group.spawn(
      async fn() {
        native_run_hook_command(
          tools,
          {
            command: "(trap '' TERM; printf ready > hook-reaped-child-ready; while [ ! -f hook-reaped-release ]; do /bin/sleep 0.01; done; printf escaped > hook-reaped-child-alive) & exit 0",
            timeout_ms: 400,
          },
          "{}\n",
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut child_ready = false
    for _ in 0..<100 {
      if @fs.exists(workspace + "/hook-reaped-child-ready") {
        child_ready = true
        break
      }
      @async.sleep(5)
    }
    assert_true(child_ready)
    assert_true(leader_exits_with_child.wait() is Err(_))
    @fs.write_file(workspace + "/hook-reaped-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-reaped-child-alive"))

    let explicitly_cancelled = group.spawn(
      async fn() {
        native_run_hook_command(
          tools,
          {
            command: "(trap '' TERM; printf ready > hook-cancel-reaped-ready; while [ ! -f hook-cancel-reaped-release ]; do /bin/sleep 0.01; done; printf escaped > hook-cancel-reaped-alive) & exit 0",
            timeout_ms: 10000,
          },
          "{}\n",
        )
        is Err(_)
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut cancel_child_ready = false
    for _ in 0..<100 {
      if @fs.exists(workspace + "/hook-cancel-reaped-ready") {
        cancel_child_ready = true
        break
      }
      @async.sleep(5)
    }
    assert_true(cancel_child_ready)
    // Let the short-lived shell leader exit and be reaped while its child
    // keeps the captured pipes open, then cancel the owning hook task.
    @async.sleep(100)
    explicitly_cancelled.cancel()
    ignore(explicitly_cancelled.wait()) catch {
      @async.WaitedTaskAlreadyCancelled => ()
      _ => ()
    }
    @fs.write_file(
      workspace + "/hook-cancel-reaped-release",
      @utf8.encode("release"),
    )
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-cancel-reaped-alive"))
  }
}

///|
async fn native_hook_prepare_approved_demo_write(
  runtime : NativeRuntime,
  session_id : String,
) -> @engine.EngineEffect {
  let (_, create_effects) = runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Hook integration",
    })
    .unwrap()
  assert_true(create_effects.is_empty())
  let (_, provider_effects) = runtime
    .invoke("session_send", {
      "session_id": session_id.to_json(),
      "prompt": "Use the approved workspace write",
    })
    .unwrap()
  let provider = match
    native_effect_by_kind(provider_effects, @engine.EffectType::Provider) {
    Some(value) => value
    None => fail("demo provider effect was not produced")
  }
  let (_, approval_effects) = runtime
    .complete(provider.id(), native_demo_tool_response())
    .unwrap()
  assert_true(approval_effects.is_empty())
  let (approval, _) = runtime
    .invoke("session_get", { "session_id": session_id.to_json() })
    .unwrap()
  assert_eq(string_field(approval, "status"), Some("awaiting_approval"))
  let pending = object_field(approval, "pending_approval").unwrap()
  let call_id = string_field(pending, "call_id").unwrap()
  let (_, tool_effects) = runtime
    .invoke("tool_approve", {
      "session_id": session_id.to_json(),
      "call_id": call_id.to_json(),
      "approved": true,
    })
    .unwrap()
  match native_effect_by_kind(tool_effects, @engine.EffectType::Tool) {
    Some(value) => value
    None => fail("explicit approval did not produce a tool effect")
  }
}

///|
async test "native PreToolUse and PostToolUse receive bounded payloads after approval" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-allow")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace $(touch hook-injected.txt) 'quoted'"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let pre_command = "cat > hook-pre.json; printf '%s' \"${CLAUDE_PROJECT_DIR}\" > hook-project-dir.txt; if [ \"${NATIVE_HOOK_TEST_SECRET-}\" = hook-test-secret ]; then printf leaked > hook-secret-env.txt; else printf scrubbed > hook-secret-env.txt; fi; printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}'"
    let post_command = "cat > hook-post.json; printf x >> hook-post-count.txt"
    let pre_group = Json::object({
      "matcher": Json::string("write"),
      "hooks": Json::array([
        Json::object({ "command": Json::string(pre_command) }),
      ]),
    })
    let post_group = Json::object({
      "matcher": Json::string("write"),
      "hooks": Json::array([
        Json::object({ "command": Json::string(post_command) }),
      ]),
    })
    let config = Json::object({
      "PreToolUse": Json::array([pre_group]),
      "PostToolUse": Json::array([post_group]),
    })
    @fs.write_file(hooks_path, @utf8.encode(config.stringify()))
    let previous_secret = @env.get_env_var("NATIVE_HOOK_TEST_SECRET")
    @env.set_env_var("NATIVE_HOOK_TEST_SECRET", "hook-test-secret")
    group.add_defer(() => {
      match previous_secret {
        Some(value) => @env.set_env_var("NATIVE_HOOK_TEST_SECRET", value)
        None => @env.unset_env_var("NATIVE_HOOK_TEST_SECRET")
      }
    })
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        hooks_config_path=Some(hooks_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "hook-allow-session"
    // The hook marker does not exist until the engine's explicit approval has
    // emitted a tool effect.
    assert_false(@fs.exists(workspace + "/hook-pre.json"))
    let tool_effect = native_hook_prepare_approved_demo_write(
      runtime, session_id,
    )
    assert_false(@fs.exists(workspace + "/hook-pre.json"))
    let (_, next_effects) = runtime.run_tool_effect(tool_effect).unwrap()
    assert_eq(next_effects.length(), 1)
    assert_eq(
      @fs.read_file(workspace + "/native-demo.txt").text(),
      "durable native tool result",
    )
    let pre_json = @json.parse(
      @fs.read_file(workspace + "/hook-pre.json").text(),
    )
    assert_eq(string_field(pre_json, "hook_event_name"), Some("PreToolUse"))
    assert_eq(string_field(pre_json, "tool_name"), Some("write"))
    assert_eq(string_field(pre_json, "session_id"), Some(session_id))
    assert_true(string_field(pre_json, "tool_use_id").unwrap().length() > 0)
    let pre_input = object_field(pre_json, "tool_input").unwrap()
    assert_eq(string_field(pre_input, "file_path"), Some("native-demo.txt"))
    assert_eq(
      string_field(pre_input, "content"),
      Some("durable native tool result"),
    )
    let canonical_workspace = @fs.realpath(workspace)
    assert_eq(string_field(pre_json, "cwd"), Some(canonical_workspace))
    assert_eq(
      @fs.read_file(workspace + "/hook-project-dir.txt").text(),
      canonical_workspace,
    )
    assert_eq(
      @fs.read_file(workspace + "/hook-secret-env.txt").text(),
      "scrubbed",
    )
    assert_false(@fs.exists(workspace + "/hook-injected.txt"))
    let post_json = @json.parse(
      @fs.read_file(workspace + "/hook-post.json").text(),
    )
    assert_eq(string_field(post_json, "hook_event_name"), Some("PostToolUse"))
    assert_true(
      string_field(post_json, "tool_response")
      .unwrap()
      .contains("Wrote 26 bytes to native-demo.txt."),
    )
    let (after_write, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(native_hook_has_successful_write_result(after_write))
    assert_eq(next_effects.length(), 1)
    let (_, final_effects) = runtime
      .complete(next_effects[0].id(), native_demo_response("Finished"))
      .unwrap()
    assert_true(final_effects.is_empty())
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
    assert_true(runtime.close() is Ok(_))
    let reopened = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, _) = reopened
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(native_hook_has_successful_write_result(restored))
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
  }
}

///|
async test "native runtime without hooks keeps the original tool event stream" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-disabled")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = NativeRuntime::open(fixture + "/data", workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "hook-disabled-session"
    let effect = native_hook_prepare_approved_demo_write(runtime, session_id)
    let (_, trailing) = runtime.run_tool_effect(effect).unwrap()
    assert_eq(trailing.length(), 1)
    let (session, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(native_hook_has_successful_write_result(session))
    assert_false(session.stringify().contains("effect-known"))
  }
}

///|
async test "native owner task cancellation during PreToolUse cannot dispatch a tool" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-pre-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let pre_command = "cat >/dev/null; printf started > hook-pre-started; while [ ! -f hook-pre-release ]; do /bin/sleep 0.01; done; printf '{}'"
    let post_command = "printf x >> hook-post-count.txt"
    let config = Json::object({
      "PreToolUse": Json::array([
        Json::object({
          "matcher": Json::string("write"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(pre_command) }),
          ]),
        }),
      ]),
      "PostToolUse": Json::array([
        Json::object({
          "matcher": Json::string("write"),
          "hooks": Json::array([
            Json::object({ "command": Json::string(post_command) }),
          ]),
        }),
      ]),
    })
    @fs.write_file(hooks_path, @utf8.encode(config.stringify()))
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
    let effect = native_hook_prepare_approved_demo_write(
      runtime, "hook-pre-cancel-session",
    )
    let task = group.spawn(
      async fn() { runtime.run_tool_effect(effect) },
      no_wait=true,
      allow_failure=true,
    )
    let mut pre_started = false
    for _ in 0..<200 {
      if @fs.exists(workspace + "/hook-pre-started") {
        pre_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(pre_started)
    task.cancel()
    ignore(task.wait()) catch {
      _ => ()
    }
    @fs.write_file(workspace + "/hook-pre-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/native-demo.txt"))
    assert_false(@fs.exists(workspace + "/hook-post-count.txt"))
  }
}

///|
async test "native pending PostToolUse result cannot reorder parallel reads" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-read-order")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/a.txt", @utf8.encode("alpha"))
    @fs.write_file(workspace + "/b.txt", @utf8.encode("beta"))
    let hooks_path = fixture + "/hooks.json"
    let post_command = "payload=$(cat); case \"$payload\" in *a.txt*) printf started > hook-a-started; while [ ! -f hook-a-release ]; do /bin/sleep 0.01; done; printf '%s' '{\"decision\":\"block\",\"reason\":\"post A denied\"}' ;; *b.txt*) printf done > hook-b-finished; printf '%s' '{}' ;; *) printf '%s' '{}' ;; esac"
    let post_group = Json::object({
      "matcher": Json::string("read"),
      "hooks": Json::array([
        Json::object({
          "type": Json::string("command"),
          "command": Json::string(post_command),
          "timeout": Json::number(30.0),
        }),
      ]),
    })
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        Json::object({ "PostToolUse": Json::array([post_group]) }).stringify(),
      ),
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
    let session_id = "hook-read-order-session"
    runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Hook read order",
    })
    .unwrap()
    |> ignore
    let (_, provider_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "Read two files",
      })
      .unwrap()
    let provider = match
      native_effect_by_kind(provider_effects, @engine.EffectType::Provider) {
      Some(value) => value
      None => fail("provider effect was not produced")
    }
    let (_, read_effects) = runtime
      .complete(provider.id(), {
        "ok": true,
        "content": "",
        "tool_calls": [
          {
            "id": "read-a",
            "name": "read",
            "arguments": "{\"file_path\":\"a.txt\"}",
          },
          {
            "id": "read-b",
            "name": "read",
            "arguments": "{\"file_path\":\"b.txt\"}",
          },
        ],
        "finish_reason": "tool_calls",
      })
      .unwrap()
    assert_eq(read_effects.length(), 2)
    assert_eq(
      string_field(read_effects[1].request(), "call_id"),
      Some("read-b"),
    )
    let control = runtime.scheduler
      .begin(session_id, "hook-read-order-command", 3)
      .unwrap()
    let b_finished = @async.Semaphore::Semaphore(1, initial_value=0)
    let b_callback_status : Ref[String?] = Ref(None)
    let task = group.spawn(
      async fn() {
        native_drive_effects(runtime.scheduler, read_effects, control, async fn(
          effect,
        ) {
          if effect.kind() == @engine.EffectType::Provider {
            runtime.complete(effect.id(), native_demo_response("Read done"))
          } else {
            let result = runtime.run_tool_effect(effect, control=Some(control))
            if string_field(effect.request(), "call_id") == Some("read-b") {
              match result {
                Ok(_) => {
                  b_callback_status.val = Some("run_tool_effect succeeded")
                  b_finished.release()
                }
                Err(error) =>
                  b_callback_status.val = Some(
                    "run_tool_effect failed: " + error,
                  )
              }
            }
            result
          }
        })
      },
      no_wait=true,
      allow_failure=true,
    )
    runtime.scheduler.attach_task(control, task)
    let mut a_started = false
    for _ in 0..<600 {
      if @fs.exists(workspace + "/hook-a-started") {
        a_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(a_started)
    let b_completion = @async.with_timeout_opt(10000, () => b_finished.acquire())
    if b_completion is None {
      let (latest, _) = runtime
        .invoke("session_get", { "session_id": session_id.to_json() })
        .unwrap()
      let b_known = native_hook_has_event(
        latest,
        "tool/completed",
        "read-b",
        Some("effect-known"),
      )
      let b_final = native_hook_has_event(
        latest,
        "tool/completed",
        "read-b",
        Some("effect"),
      )
      @fs.write_file(workspace + "/hook-a-release", @utf8.encode("release"))
      let task_outcome = match task.wait() {
        Ok(_) => "completed"
        Err(error) => error
      }
      fail(
        "B did not finish within 10 seconds: hook marker=" +
        @fs.exists(workspace + "/hook-b-finished").to_string() +
        ", outcome staged=" +
        b_known.to_string() +
        ", final=" +
        b_final.to_string() +
        ", callback=" +
        b_callback_status.val.unwrap_or("not returned") +
        ", task outcome=" +
        task_outcome,
      )
    }
    let (during_a, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(@fs.exists(workspace + "/hook-b-finished"))
    assert_true(
      native_hook_has_event(
        during_a,
        "tool/completed",
        "read-a",
        Some("effect-known"),
      ),
    )
    assert_eq(native_hook_tool_result_ids(during_a), [])
    @fs.write_file(workspace + "/hook-a-release", @utf8.encode("release"))
    assert_eq(task.wait(), Ok(()))
    runtime.scheduler.finish(control)
    let (finished, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_eq(native_hook_tool_result_ids(finished), ["read-a", "read-b"])
    let a_result = native_hook_tool_result(finished, "read-a").unwrap()
    assert_true(native_json_true(object_field(a_result, "is_error")))
    assert_true(
      string_field(a_result, "content")
      .unwrap()
      .contains("PostToolUse hook blocked"),
    )
    let b_result = native_hook_tool_result(finished, "read-b").unwrap()
    assert_false(native_json_true(object_field(b_result, "is_error")))
    assert_eq(string_field(b_result, "content"), Some("1: beta"))
  }
}

///|
async test "native PreToolUse denial prevents tool work and receipt replay does not rerun hooks" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-deny")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let command = "cat >/dev/null; printf x >> hook-count.txt; printf '%s' '{\"decision\":\"block\",\"reason\":\"fixture denial\"}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("PreToolUse", "write", command)),
    )
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        hooks_config_path=Some(hooks_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "hook-deny-session"
    runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Hook denial",
    })
    .unwrap()
    |> ignore
    let command_time = native_auth_now().to_int64() * 1000L
    let send_command_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time, "00112233445566778899aabbccddeeff",
    ).unwrap()
    let send = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      send_command_id,
      "Use the workspace write",
    )
    let identity = runtime.state.identity_key
    let (accepted_send, send_effects, start_send, send_control) = runtime
      .accept_remote_command(send, identity)
      .unwrap()
    assert_true(start_send)
    runtime.run_command_job(
      send_command_id,
      identity,
      int_field(accepted_send, "accepted_revision").unwrap(),
      send_effects,
      control=send_control,
    )
    let (approval, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    let pending = object_field(approval, "pending_approval").unwrap()
    let call_id = string_field(pending, "call_id").unwrap()
    let revision = int_field(native_safe_session(approval), "approval_revision").unwrap()
    let approval_command_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time + 1L,
      "102132435465768798a9bacbdcedfe0f",
    ).unwrap()
    let approval_command = native_runtime_approval_command(
      runtime.state.workspace_id,
      session_id,
      approval_command_id,
      call_id,
      revision,
    )
    let (accepted, effects, should_start, control) = runtime
      .accept_remote_command(approval_command, identity)
      .unwrap()
    assert_true(should_start)
    assert_eq(effects.length(), 1)
    runtime.run_command_job(
      approval_command_id,
      identity,
      int_field(accepted, "accepted_revision").unwrap(),
      effects,
      control~,
    )
    assert_eq(@fs.read_file(workspace + "/hook-count.txt").text(), "x")
    assert_false(@fs.exists(workspace + "/native-demo.txt"))
    let (denied_session, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(denied_session.stringify().contains("fixture denial"))

    let replay = native_runtime_approval_command(
      runtime.state.workspace_id,
      session_id,
      approval_command_id,
      call_id,
      revision,
    )
    let (replayed, replay_effects, replay_started, _) = runtime
      .accept_remote_command(replay, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("completed"))
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)
    assert_eq(@fs.read_file(workspace + "/hook-count.txt").text(), "x")

    assert_true(runtime.close() is Ok(_))
    let reopened = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        hooks_config_path=Some(hooks_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let after_restart = native_runtime_approval_command(
      reopened.state.workspace_id,
      session_id,
      approval_command_id,
      call_id,
      revision,
    )
    let (restart_replay, restart_effects, restart_started, _) = reopened
      .accept_remote_command(after_restart, identity)
      .unwrap()
    assert_eq(string_field(restart_replay, "status"), Some("completed"))
    assert_true(restart_effects.is_empty())
    assert_false(restart_started)
    assert_eq(@fs.read_file(workspace + "/hook-count.txt").text(), "x")
  }
}

///|
async test "native session cancellation checkpoints the completed tool result and kills the post-hook group" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-post-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let post_command = "printf x >> hook-post-count.txt; (trap '' TERM; while [ ! -f hook-post-release ]; do /bin/sleep 0.01; done; printf escaped > hook-post-child-alive) & printf started > hook-post-started; wait"
    @fs.write_file(
      hooks_path,
      @utf8.encode(
        native_hook_test_config("PostToolUse", "write", post_command),
      ),
    )
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        hooks_config_path=Some(hooks_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "hook-post-cancel-session"
    runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Hook cancellation",
    })
    .unwrap()
    |> ignore
    let command_time = native_auth_now().to_int64() * 1000L
    let identity = runtime.state.identity_key
    let send_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time, "00112233445566778899aabbccddeeff",
    ).unwrap()
    let send = native_runtime_command(
      runtime.state.workspace_id,
      session_id,
      send_id,
      "Use the workspace write",
    )
    let (accepted_send, send_effects, send_started, send_control) = runtime
      .accept_remote_command(send, identity)
      .unwrap()
    assert_true(send_started)
    assert_eq(send_effects.length(), 1)
    runtime.run_command_job(
      send_id,
      identity,
      int_field(accepted_send, "accepted_revision").unwrap(),
      send_effects,
      control=send_control,
    )
    let (approval, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    let pending = object_field(approval, "pending_approval").unwrap()
    let call_id = string_field(pending, "call_id").unwrap()
    let approval_revision = int_field(
      native_safe_session(approval),
      "approval_revision",
    ).unwrap()
    let approval_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time + 1L,
      "102132435465768798a9bacbdcedfe0f",
    ).unwrap()
    let approval_command = native_runtime_approval_command(
      runtime.state.workspace_id,
      session_id,
      approval_id,
      call_id,
      approval_revision,
    )
    let (accepted_approval, approval_effects, approval_started, control) = runtime
      .accept_remote_command(approval_command, identity)
      .unwrap()
    assert_true(approval_started)
    assert_eq(approval_effects.length(), 1)
    let accepted_revision = int_field(accepted_approval, "accepted_revision").unwrap()
    let task = group.spawn(
      async fn() {
        runtime.run_command_job(
          approval_id,
          identity,
          accepted_revision,
          approval_effects,
          control~,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut post_started = false
    for _ in 0..<600 {
      if @fs.exists(workspace + "/hook-post-started") {
        post_started = true
        break
      }
      @async.sleep(5)
    }
    assert_true(post_started)
    let cancel_id = @protocol.uuid_v7_command_id_from_entropy(
      command_time + 2L,
      "2031425364758697a8b9cadbecfd0e1f",
    ).unwrap()
    let cancel = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      session_id,
      cancel_id,
      "session_cancel",
      {},
    )
    let (cancel_receipt, cancel_effects, cancel_started, _) = runtime
      .accept_remote_command(cancel, runtime.state.identity_key)
      .unwrap()
    assert_eq(string_field(cancel_receipt, "status"), Some("accepted"))
    assert_true(cancel_started)
    assert_true(cancel_effects.is_empty())
    ignore(task.wait()) catch {
      _ => ()
    }
    runtime.run_command_job(
      cancel_id,
      identity,
      int_field(cancel_receipt, "accepted_revision").unwrap(),
      cancel_effects,
    )
    let approval_receipt = runtime
      .find_receipt(approval_id, identity)
      .unwrap()
      .unwrap()
    assert_eq(string_field(approval_receipt, "status"), Some("uncertain"))
    assert_eq(
      @fs.read_file(workspace + "/native-demo.txt").text(),
      "durable native tool result",
    )
    let (session, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(native_hook_has_successful_write_result(session))
    assert_eq(
      object_field(native_safe_session(session), "has_tool_results"),
      Some(Json::boolean(true)),
    )
    assert_eq(string_field(session, "status"), Some("cancelled"))
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
    let replay = native_runtime_approval_command(
      runtime.state.workspace_id,
      session_id,
      approval_id,
      call_id,
      approval_revision,
    )
    let (replayed, replay_effects, replay_started, _) = runtime
      .accept_remote_command(replay, identity)
      .unwrap()
    assert_eq(string_field(replayed, "status"), Some("uncertain"))
    assert_true(replay_effects.is_empty())
    assert_false(replay_started)
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
    @fs.write_file(workspace + "/hook-post-release", @utf8.encode("release"))
    @async.sleep(100)
    assert_false(@fs.exists(workspace + "/hook-post-child-alive"))
    assert_true(runtime.close() is Ok(_))
    let reopened = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let durable_approval_receipt = reopened
      .find_receipt(approval_id, identity)
      .unwrap()
      .unwrap()
    assert_eq(
      string_field(durable_approval_receipt, "status"),
      Some("uncertain"),
    )
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
    let (restored, _) = reopened
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_true(native_hook_has_successful_write_result(restored))
    assert_eq(
      object_field(native_safe_session(restored), "has_tool_results"),
      Some(Json::boolean(true)),
    )
    let after_restart = native_runtime_approval_command(
      reopened.state.workspace_id,
      session_id,
      approval_id,
      call_id,
      approval_revision,
    )
    let (restart_replay, restart_effects, restart_started, _) = reopened
      .accept_remote_command(after_restart, identity)
      .unwrap()
    assert_eq(string_field(restart_replay, "status"), Some("uncertain"))
    assert_true(restart_effects.is_empty())
    assert_false(restart_started)
    assert_eq(@fs.read_file(workspace + "/hook-post-count.txt").text(), "x")
  }
}

///|
async test "native oversized known outcome closes before PostToolUse runs" {
  let fixture = @fs.tmpdir(prefix="dsh-native-hooks-outcome-capacity")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let hooks_path = fixture + "/hooks.json"
    let post_command = "printf x >> hook-post-count.txt"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("PostToolUse", "read", post_command)),
    )
    @fs.write_file(
      workspace + "/oversized.txt",
      @utf8.encode("x".repeat(100000)),
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
    let session_id = "hook-outcome-capacity-session"
    runtime
    .invoke("session_create", {
      "id": session_id.to_json(),
      "title": "Hook outcome capacity",
    })
    .unwrap()
    |> ignore
    let (_, first_provider_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "Build up bounded history",
      })
      .unwrap()
    let provider = native_effect_by_kind(
      first_provider_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, _) = runtime
      .complete(provider.id(), native_demo_response("x".repeat(60000)))
      .unwrap()

    let (_, second_provider_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "q".repeat(16000),
      })
      .unwrap()
    let second_provider = native_effect_by_kind(
      second_provider_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (filled, _) = runtime
      .complete(second_provider.id(), native_demo_response("y".repeat(50000)))
      .unwrap()
    assert_eq(string_field(filled, "status"), Some("completed"))
    assert_true(filled.stringify().length() < 262144)

    let (_, final_provider_effects) = runtime
      .invoke("session_send", {
        "session_id": session_id.to_json(),
        "prompt": "Read the large file",
      })
      .unwrap()
    let final_provider = native_effect_by_kind(
      final_provider_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, read_effects) = runtime
      .complete(final_provider.id(), {
        "ok": true,
        "content": "",
        "tool_calls": [
          {
            "id": "read-oversized",
            "name": "read",
            "arguments": "{\"file_path\":\"oversized.txt\"}",
          },
        ],
        "finish_reason": "tool_calls",
      })
      .unwrap()
    let effect = native_effect_by_kind(read_effects, @engine.EffectType::Tool).unwrap()
    let actual_result = runtime.tools.execute(effect.request())
    assert_true(native_json_true(object_field(actual_result, "ok")))
    assert_true(
      string_field(actual_result, "content").unwrap().length() >= 65000,
    )
    assert_true(
      runtime.finish_tool_effect(effect, session_id, actual_result) is Err(_),
    )
    assert_false(@fs.exists(workspace + "/hook-post-count.txt"))
    let (closed, _) = runtime
      .invoke("session_get", { "session_id": session_id.to_json() })
      .unwrap()
    assert_eq(string_field(closed, "status"), Some("failed"))
    assert_false(
      native_hook_has_event(
        closed,
        "tool/completed",
        "read-oversized",
        Some("effect-known"),
      ),
    )
  }
}
