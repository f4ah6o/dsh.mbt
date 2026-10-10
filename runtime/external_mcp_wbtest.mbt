///|
fn native_mcp_test_response(id : Int, result : Json) -> Json {
  {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "result": result,
  }
}

///|
fn native_mcp_test_server_script(
  schema : Json,
  counter_path : String,
  is_error : Json?,
  tool_call_behavior? : String? = None,
) -> String {
  let initialize = native_mcp_test_response(1, {
    "protocolVersion": Json::string("2025-06-18"),
    "capabilities": Json::empty_object(),
    "serverInfo": {
      "name": Json::string("fixture"),
      "version": Json::string("1"),
    },
  })
  let tool = {
    "name": Json::string("a/b"),
    "description": Json::string("Fixture tool"),
    "inputSchema": schema,
  }
  let list_tools = native_mcp_test_response(2, { "tools": Json::array([tool]) })
  let call_result : Map[String, Json] = Map([
    (
      "content",
      Json::array([
        { "type": Json::string("text"), "text": Json::string("mcp-ok") },
      ]),
    ),
  ])
  match is_error {
    Some(value) => call_result["isError"] = value
    None => ()
  }
  let call = native_mcp_test_response(3, Json::object(call_result))
  let increment = if counter_path.is_empty() {
    ""
  } else {
    "printf x >> '" + counter_path + "'\n"
  }
  let call_branch = match tool_call_behavior {
    Some(value) => value
    None => increment + "      printf '%s\\n' '" + call.stringify() + "'"
  }
  "while IFS= read -r line; do\n" +
  "  case \"$line\" in\n" +
  "    *\\\"method\\\":\\\"initialize\\\"*) printf '%s\\n' '" +
  initialize.stringify() +
  "' ;;\n" +
  "    *tools/list*) printf '%s\\n' '" +
  list_tools.stringify() +
  "' ;;\n" +
  "    *tools/call*)\n" +
  call_branch +
  " ;;\n" +
  "  esac\n" +
  "done\n"
}

///|
fn native_mcp_test_config(
  workspace : String,
  script_path : String,
  tool_timeout_ms? : Int = 60000,
) -> Json {
  {
    "servers": Json::array([
      native_mcp_test_server_entry(
        "fixture", workspace, script_path, tool_timeout_ms,
      ),
    ]),
  }
}

///|
fn native_mcp_test_server_entry(
  name : String,
  workspace : String,
  script_path : String,
  tool_timeout_ms : Int,
) -> Json {
  {
    "name": Json::string(name),
    "command": Json::string("/bin/sh"),
    "args": Json::array([Json::string(script_path)]),
    "cwd": Json::string(workspace),
    "toolCallTimeoutMs": Json::number(tool_timeout_ms.to_double()),
  }
}

///|
fn native_mcp_test_schema(description : String) -> Json {
  {
    "type": Json::string("object"),
    "properties": Json::empty_object(),
    "additionalProperties": Json::boolean(false),
    "description": Json::string(description),
  }
}

///|
fn native_mcp_test_provider_tool_response(
  call_id : String,
  name : String,
) -> Json {
  {
    "ok": Json::boolean(true),
    "content": Json::string(""),
    "reasoning": Json::string(""),
    "tool_calls": Json::array([
      {
        "id": Json::string(call_id),
        "name": Json::string(name),
        "arguments": Json::string("{}"),
      },
    ]),
    "finish_reason": Json::string("tool_calls"),
    "usage": {
      "input_tokens": Json::number(1.0),
      "output_tokens": Json::number(1.0),
      "total_tokens": Json::number(2.0),
    },
  }
}

///|
fn native_mcp_test_deep_json(depth : Int) -> Json {
  if depth == 0 {
    Json::string("leaf")
  } else {
    Json::array([native_mcp_test_deep_json(depth - 1)])
  }
}

///|
test "external MCP names, catalog bounds, and canonical fingerprints are stable" {
  let name = native_mcp_public_tool_name("fixture", "a/b").unwrap()
  assert_true(name.length() <= 64)
  assert_true(name.has_prefix("mcp__fixture__a_b"))
  assert_false(name.contains("/"))
  assert_true(native_mcp_catalog_capacity(48, 16))
  assert_false(native_mcp_catalog_capacity(64, 64))

  let schema_one = Json::object(
    Map::from_array([
      ("type", Json::string("object")),
      (
        "properties",
        Json::object(
          Map::from_array([
            ("alpha", { "type": Json::string("string") }),
            ("beta", { "type": Json::string("integer") }),
          ]),
        ),
      ),
    ]),
  )
  let schema_two = Json::object(
    Map::from_array([
      (
        "properties",
        Json::object(
          Map::from_array([
            ("beta", { "type": Json::string("integer") }),
            ("alpha", { "type": Json::string("string") }),
          ]),
        ),
      ),
      ("type", Json::string("object")),
    ]),
  )
  let first = {
    name: "mcp__fixture__first",
    server_name: "fixture",
    raw_name: "first",
    description: "First",
    input_schema: schema_one,
  }
  let second = {
    name: "mcp__fixture__second",
    server_name: "fixture",
    raw_name: "second",
    description: "Second",
    input_schema: schema_two,
  }
  assert_eq(
    native_mcp_catalog_hash([first, second]),
    native_mcp_catalog_hash([second, first]),
  )
  let legacy_native_only : Json = { "sessions": Json::array([]) }
  let legacy_mcp_history : Json = {
    "sessions": Json::array([
      {
        "events": Json::array([
          {
            "type": Json::string("tool/call"),
            "data": { "name": Json::string("mcp__fixture__read") },
          },
        ]),
      },
    ]),
  }
  let legacy_pending_mcp_history : Json = {
    "sessions": Json::array([
      {
        "events": Json::array([
          {
            "type": Json::string("assistant/message"),
            "data": {
              "message": {
                "tool_calls": Json::array([
                  { "name": Json::string("write") },
                  { "name": Json::string("mcp__fixture__read") },
                ]),
              },
            },
          },
          {
            "type": Json::string("tool/call"),
            "data": { "name": Json::string("write") },
          },
          {
            "type": Json::string("tool/approval/requested"),
            "data": { "name": Json::string("write") },
          },
        ]),
      },
    ]),
  }
  assert_true(
    native_mcp_catalog_matches_stored(None, Some("new"), legacy_native_only),
  )
  assert_false(
    native_mcp_catalog_matches_stored(None, Some("new"), legacy_mcp_history),
  )
  assert_false(
    native_mcp_catalog_matches_stored(
      None,
      Some("new"),
      legacy_pending_mcp_history,
    ),
  )
  assert_true(native_mcp_catalog_matches_stored(None, None, legacy_mcp_history))
  assert_true(
    native_mcp_catalog_matches_stored(
      Some("same"),
      Some("same"),
      legacy_native_only,
    ),
  )
  assert_false(
    native_mcp_catalog_matches_stored(
      Some("old"),
      Some("new"),
      legacy_native_only,
    ),
  )
  assert_false(
    native_mcp_catalog_matches_stored(Some("old"), None, legacy_native_only),
  )
}

///|
test "external MCP rejects task-required tools and deeply nested schema annotations" {
  let task_only : Json = {
    "name": Json::string("task-only"),
    "execution": { "taskSupport": Json::string("required") },
    "inputSchema": { "type": Json::string("object") },
  }
  assert_true(native_mcp_parse_tool(0, "fixture", task_only) is Err(_))

  let annotation_schema : Json = {
    "type": Json::string("object"),
    "default": native_mcp_test_deep_json(30),
  }
  let annotation_tool : Json = {
    "name": Json::string("annotation"),
    "inputSchema": annotation_schema,
  }
  assert_true(native_mcp_parse_tool(0, "fixture", annotation_tool) is Err(_))

  let enum_schema : Json = {
    "type": Json::string("object"),
    "enum": Json::array([native_mcp_test_deep_json(30)]),
  }
  let enum_tool : Json = {
    "name": Json::string("deep-enum"),
    "inputSchema": enum_schema,
  }
  assert_true(native_mcp_parse_tool(0, "fixture", enum_tool) is Err(_))

  assert_eq(native_mcp_is_error({}), Ok(false))
  assert_eq(native_mcp_is_error({ "isError": Json::boolean(false) }), Ok(false))
  assert_eq(native_mcp_is_error({ "isError": Json::boolean(true) }), Ok(true))
  assert_true(
    native_mcp_is_error({ "isError": Json::string("true") }) is Err(_),
  )
}

///|
async test "external MCP stdio reads fragmented discovery and routes lossy raw names" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-fragmented")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let large_description = StringView::repeat("x"[:], 10000).to_owned()
    let script = native_mcp_test_server_script(
      native_mcp_test_schema(large_description),
      counter,
      None,
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = match
      NativeMcpPool::open(
        Some(config_path),
        safety_native_worker_launcher().unwrap(),
        workspace,
        device,
        inode,
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    assert_eq(pool.descriptors.length(), 1)
    let descriptor = pool.descriptors[0]
    let public_name = string_field(descriptor, "name").unwrap()
    assert_true(public_name.length() <= 64)
    assert_false(public_name.contains("/"))
    let schema = object_field(descriptor, "input_schema").unwrap()
    assert_eq(string_field(schema, "description").unwrap().length(), 10000)
    assert_eq(string_field(descriptor, "effect"), Some("write"))

    let result = pool.execute({
      "name": Json::string(public_name),
      "arguments": Json::empty_object(),
    })
    assert_eq(object_field(result, "ok"), Some(Json::boolean(true)))
    assert_eq(string_field(result, "content"), Some("mcp-ok"))
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "external MCP isError rejects malformed values through the tool result path" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-is-error")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let config_path = fixture + "/mcp.json"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      "",
      Some(Json::string("true")),
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeMcpPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let public_name = string_field(pool.descriptors[0], "name").unwrap()
    let result = pool.execute({
      "name": Json::string(public_name),
      "arguments": Json::empty_object(),
    })
    assert_eq(object_field(result, "ok"), Some(Json::boolean(false)))
    assert_eq(
      string_field(result, "error"),
      Some("external MCP tool isError must be a boolean"),
    )
  }
}

///|
async test "external MCP tools require approval and only approved calls reach the server" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-approval")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      counter,
      None,
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        mcp_config_path=Some(config_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let public_name = native_mcp_public_tool_name("fixture", "a/b").unwrap()

    let (_, _) = runtime
      .invoke("session_create", {
        "id": Json::string("mcp-deny-session"),
        "title": Json::string("Deny MCP call"),
      })
      .unwrap()
    let (_, deny_initial) = runtime
      .invoke("session_send", {
        "session_id": Json::string("mcp-deny-session"),
        "prompt": Json::string("call the fixture tool"),
      })
      .unwrap()
    let deny_provider = native_effect_by_kind(
      deny_initial,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, deny_pending) = runtime
      .complete(
        deny_provider.id(),
        native_mcp_test_provider_tool_response("mcp-denied-call", public_name),
      )
      .unwrap()
    assert_true(deny_pending.is_empty())
    let pending = runtime
      .invoke("session_get", { "session_id": Json::string("mcp-deny-session") })
      .unwrap().0
    assert_eq(string_field(pending, "status"), Some("awaiting_approval"))
    let call_id = string_field(
      object_field(pending, "pending_approval").unwrap(),
      "call_id",
    ).unwrap()
    let (_, denied_effects) = runtime
      .invoke("tool_approve", {
        "session_id": Json::string("mcp-deny-session"),
        "call_id": Json::string(call_id),
        "approved": Json::boolean(false),
      })
      .unwrap()
    assert_false(
      denied_effects.any(effect => effect.kind() == @engine.EffectType::Tool),
    )
    assert_false(@fs.exists(counter))

    let (_, _) = runtime
      .invoke("session_create", {
        "id": Json::string("mcp-allow-session"),
        "title": Json::string("Allow MCP call"),
      })
      .unwrap()
    let (_, allow_initial) = runtime
      .invoke("session_send", {
        "session_id": Json::string("mcp-allow-session"),
        "prompt": Json::string("call the fixture tool"),
      })
      .unwrap()
    let allow_provider = native_effect_by_kind(
      allow_initial,
      @engine.EffectType::Provider,
    ).unwrap()
    let (_, allow_pending) = runtime
      .complete(
        allow_provider.id(),
        native_mcp_test_provider_tool_response("mcp-allowed-call", public_name),
      )
      .unwrap()
    assert_true(allow_pending.is_empty())
    let pending = runtime
      .invoke("session_get", { "session_id": Json::string("mcp-allow-session") })
      .unwrap().0
    assert_eq(string_field(pending, "status"), Some("awaiting_approval"))
    let call_id = string_field(
      object_field(pending, "pending_approval").unwrap(),
      "call_id",
    ).unwrap()
    let (_, approved_effects) = runtime
      .invoke("tool_approve", {
        "session_id": Json::string("mcp-allow-session"),
        "call_id": Json::string(call_id),
        "approved": Json::boolean(true),
      })
      .unwrap()
    assert_eq(approved_effects.length(), 1)
    assert_true(approved_effects[0].kind() == @engine.EffectType::Tool)
    let (_, followup) = runtime.run_tool_effect(approved_effects[0]).unwrap()
    assert_true(
      followup.any(effect => effect.kind() == @engine.EffectType::Provider),
    )
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "external MCP catalog reopens without replay and rejects schema drift" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-reopen")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let script_path = fixture + "/server.sh"
    @fs.write_file(
      script_path,
      native_mcp_test_server_script(
        native_mcp_test_schema("fixture"),
        counter,
        None,
      ),
    )
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let runtime = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      mcp_config_path=Some(config_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let public_name = native_mcp_public_tool_name("fixture", "a/b").unwrap()
    runtime
    .invoke("session_create", {
      "id": Json::string("mcp-reopen-session"),
      "title": Json::string("MCP reopen"),
    })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": Json::string("mcp-reopen-session"),
        "prompt": Json::string("call the fixture tool"),
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let (_, no_effects) = runtime
      .complete(
        provider.id(),
        native_mcp_test_provider_tool_response("mcp-reopen-call", public_name),
      )
      .unwrap()
    assert_true(no_effects.is_empty())
    let pending = runtime
      .invoke("session_get", {
        "session_id": Json::string("mcp-reopen-session"),
      })
      .unwrap().0
    let call_id = string_field(
      object_field(pending, "pending_approval").unwrap(),
      "call_id",
    ).unwrap()
    let (_, approved) = runtime
      .invoke("tool_approve", {
        "session_id": Json::string("mcp-reopen-session"),
        "call_id": Json::string(call_id),
        "approved": Json::boolean(true),
      })
      .unwrap()
    let tool_effect = native_effect_by_kind(approved, @engine.EffectType::Tool).unwrap()
    let (_, followup) = runtime.run_tool_effect(tool_effect).unwrap()
    let followup_provider = native_effect_by_kind(
      followup,
      @engine.EffectType::Provider,
    ).unwrap()
    runtime
    .complete(followup_provider.id(), native_demo_response("finished"))
    .unwrap()
    |> ignore
    assert_eq(@fs.read_file(counter).text(), "x")
    runtime.close().unwrap()

    let reopened = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      mcp_config_path=Some(config_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored = reopened
      .invoke("session_get", {
        "session_id": Json::string("mcp-reopen-session"),
      })
      .unwrap().0
    assert_eq(string_field(restored, "status"), Some("completed"))
    assert_eq(@fs.read_file(counter).text(), "x")
    reopened.close().unwrap()
    let snapshot_before_mismatch = @fs.read_file(data_dir + "/sessions.json").text()

    let changed_script = fixture + "/changed-server.sh"
    @fs.write_file(
      changed_script,
      native_mcp_test_server_script(
        native_mcp_test_schema("changed schema"),
        counter,
        None,
      ),
    )
    let changed_config = fixture + "/changed-mcp.json"
    @fs.write_file(
      changed_config,
      native_mcp_test_config(workspace, changed_script).stringify(),
    )
    let mismatch = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      mcp_config_path=Some(changed_config),
    )
    assert_true(mismatch is Err(_))
    assert_eq(
      @fs.read_file(data_dir + "/sessions.json").text(),
      snapshot_before_mismatch,
    )
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "external MCP shutdown and in-flight EOF close share one process reaper" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-close-race")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let behavior = "printf x >> '" + counter + "'\nsleep 30\n"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      counter,
      None,
      tool_call_behavior=Some(behavior),
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        true,
        mcp_config_path=Some(config_path),
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let public_name = native_mcp_public_tool_name("fixture", "a/b").unwrap()
    runtime
    .invoke("session_create", {
      "id": Json::string("mcp-close-race"),
      "title": Json::string("Close an active MCP call"),
    })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": Json::string("mcp-close-race"),
        "prompt": Json::string("call the fixture tool"),
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let (_, no_effects) = runtime
      .complete(
        provider.id(),
        native_mcp_test_provider_tool_response("mcp-close-call", public_name),
      )
      .unwrap()
    assert_true(no_effects.is_empty())
    let pending = runtime
      .invoke("session_get", { "session_id": Json::string("mcp-close-race") })
      .unwrap().0
    let call_id = string_field(
      object_field(pending, "pending_approval").unwrap(),
      "call_id",
    ).unwrap()
    let (_, approved) = runtime
      .invoke("tool_approve", {
        "session_id": Json::string("mcp-close-race"),
        "call_id": Json::string(call_id),
        "approved": Json::boolean(true),
      })
      .unwrap()
    let tool_effect = native_effect_by_kind(approved, @engine.EffectType::Tool).unwrap()
    let call_task = group.spawn(() => runtime.run_tool_effect(tool_effect))
    let mut polls = 0
    while !@fs.exists(counter) && polls < 200 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(@fs.exists(counter))
    assert_eq(@fs.read_file(counter).text(), "x")
    assert_true(runtime.close() is Ok(_))
    assert_true(call_task.wait() is Err(_))
    assert_false(os_process_group_alive(runtime.external_mcp.servers[0].pid))
  }
}

///|
async test "external MCP timeout is unknown, never replayed, and kills descendants" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-timeout")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let behavior = "sleep 30 &\nprintf x >> '" + counter + "'\nsleep 30\n"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      counter,
      None,
      tool_call_behavior=Some(behavior),
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path, tool_timeout_ms=100).stringify(),
    )
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeMcpPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let pid = pool.servers[0].pid
    let public_name = string_field(pool.descriptors[0], "name").unwrap()
    let request : Json = {
      "name": Json::string(public_name),
      "arguments": Json::empty_object(),
    }
    let result = pool.execute(request)
    assert_eq(object_field(result, "ok"), Some(Json::boolean(false)))
    assert_true(
      string_field(result, "error")
      .unwrap_or("")
      .contains("remote outcome is unknown"),
    )
    assert_eq(@fs.read_file(counter).text(), "x")
    let retry = pool.execute(request)
    assert_eq(object_field(retry, "ok"), Some(Json::boolean(false)))
    assert_eq(@fs.read_file(counter).text(), "x")
    assert_false(os_process_group_alive(pid))
  }
}

///|
async test "external MCP EOF after dispatch reports an unknown outcome without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-eof")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let behavior = "printf x >> '" + counter + "'\nexit 0\n"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      counter,
      None,
      tool_call_behavior=Some(behavior),
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeMcpPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let request : Json = {
      "name": Json::string(string_field(pool.descriptors[0], "name").unwrap()),
      "arguments": Json::empty_object(),
    }
    let result = pool.execute(request)
    assert_eq(object_field(result, "ok"), Some(Json::boolean(false)))
    assert_true(
      string_field(result, "error")
      .unwrap_or("")
      .contains("remote outcome is unknown"),
    )
    assert_eq(@fs.read_file(counter).text(), "x")
    let retry = pool.execute(request)
    assert_eq(object_field(retry, "ok"), Some(Json::boolean(false)))
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "external MCP cancellation closes the server and prevents a second dispatch" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let counter = fixture + "/calls"
    let child_ready_path = fixture + "/child.ready"
    let child_release_path = fixture + "/child.release"
    let child_escape_path = fixture + "/child.escaped"
    let behavior = "(trap '' TERM; printf ready > '" +
      child_ready_path +
      "'; while [ ! -f '" +
      child_release_path +
      "' ]; do /bin/sleep 0.01; done; printf escaped > '" +
      child_escape_path +
      "') &\nprintf x >> '" +
      counter +
      "'\nwait\n"
    let script = native_mcp_test_server_script(
      native_mcp_test_schema("fixture"),
      counter,
      None,
      tool_call_behavior=Some(behavior),
    )
    let script_path = fixture + "/server.sh"
    @fs.write_file(script_path, script)
    let config_path = fixture + "/mcp.json"
    @fs.write_file(
      config_path,
      native_mcp_test_config(workspace, script_path).stringify(),
    )
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeMcpPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let pid = pool.servers[0].pid
    let request : Json = {
      "name": Json::string(string_field(pool.descriptors[0], "name").unwrap()),
      "arguments": Json::empty_object(),
    }
    let call_task = group.spawn(
      async fn() { pool.execute(request) },
      no_wait=true,
      allow_failure=true,
    )
    let mut polls = 0
    while (!@fs.exists(counter) || !@fs.exists(child_ready_path)) && polls < 200 {
      @async.sleep(5)
      polls += 1
    }
    if !@fs.exists(counter) || !@fs.exists(child_ready_path) {
      fail(
        "external MCP cancellation fixture did not become ready; pid=" +
        pid.to_string() +
        "; counter=" +
        @fs.exists(counter).to_string() +
        "; child_ready=" +
        @fs.exists(child_ready_path).to_string(),
      )
    }
    call_task.cancel()
    ignore(call_task.wait()) catch {
      _ => ()
    }
    assert_false(os_process_alive(pid))
    @fs.write_file(child_release_path, @utf8.encode("release"))
    polls = 0
    while !@fs.exists(child_escape_path) && polls < 100 {
      @async.sleep(5)
      polls += 1
    }
    if @fs.exists(child_escape_path) {
      fail(
        "external MCP cancellation left a descendant able to escape; pid=" +
        pid.to_string() +
        "; child_ready=true; released=true; marker=true",
      )
    }
    assert_eq(@fs.read_file(counter).text(), "x")
    let retry = pool.execute(request)
    assert_eq(object_field(retry, "ok"), Some(Json::boolean(false)))
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "external MCP startup cancellation closes earlier and current servers" {
  let fixture = @fs.tmpdir(prefix="dsh-external-mcp-start-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let first_pid_file = fixture + "/first.pid"
    let first_script_path = fixture + "/first.sh"
    let first_script = "printf '%s' \"$$\" > '" +
      first_pid_file +
      "'\n" +
      native_mcp_test_server_script(native_mcp_test_schema("first"), "", None)
    @fs.write_file(first_script_path, first_script)

    let second_pid_file = fixture + "/second.pid"
    let second_script_path = fixture + "/second.sh"
    @fs.write_file(
      second_script_path,
      "printf '%s' \"$$\" > '" +
      second_pid_file +
      "'\n" +
      "while IFS= read -r line; do :; done\n",
    )
    let config_path = fixture + "/mcp.json"
    let config : Json = {
      "servers": Json::array([
        native_mcp_test_server_entry(
          "first", workspace, first_script_path, 60000,
        ),
        native_mcp_test_server_entry(
          "second", workspace, second_script_path, 60000,
        ),
      ]),
    }
    @fs.write_file(config_path, config.stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let open_task = group.spawn(
      async fn() {
        NativeMcpPool::open(
          Some(config_path),
          safety_native_worker_launcher().unwrap(),
          workspace,
          device,
          inode,
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut polls = 0
    while !@fs.exists(second_pid_file) && polls < 400 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(@fs.exists(first_pid_file))
    assert_true(@fs.exists(second_pid_file))
    open_task.cancel()
    ignore(open_task.wait()) catch {
      _ => ()
    }
    let first_pid = service_parse_int(@fs.read_file(first_pid_file).text()).unwrap()
    let second_pid = service_parse_int(@fs.read_file(second_pid_file).text()).unwrap()
    assert_false(os_process_group_alive(first_pid))
    assert_false(os_process_group_alive(second_pid))
  }
}
