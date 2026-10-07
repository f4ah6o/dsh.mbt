///|
fn get(value : Json, key : String) -> Json raise {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(value) => value
        None => fail("missing " + key)
      }
    _ => fail("expected object")
  }
}

///|
fn rpc(
  api : @api.HarnessApi,
  id : String,
  operation : String,
  arguments : Json,
) -> Json raise {
  let request : Json = {
    "jsonrpc": "2.0",
    "id": id.to_json(),
    "method": "tools/call",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
      "name": operation.to_json(),
      "arguments": arguments,
    },
  }
  @json.parse(api.mcp_handle(request.stringify()).unwrap())
}

///|
test "GUI and direct capability paths share state and input validation" {
  let api = @api.HarnessApi::new().unwrap()
  let binding = api.gui_binding("session_create").unwrap()
  let created = binding.trigger({ "id": "shared", "title": "Shared" }).unwrap()
  let read = api.invoke("session_get", { "session_id": "shared" }).unwrap()
  assert_eq(created, read)
  assert_true(binding.trigger({ "id": 7 }) is Err(_))
  assert_true(api.invoke("session_create", { "id": 7 }) is Err(_))
  assert_true(binding.trigger({ "id": "extra", "unknown": true }) is Err(_))
  assert_true(
    api.invoke("session_create", { "id": "extra", "unknown": true }) is Err(_),
  )
  api.close()
  assert_true(api.invoke("session_list", {}) is Err(_))
  assert_true(binding.trigger({ "id": "closed" }) is Err(_))
}

///|
test "MCP explicit session identity prevents duplicate session creation" {
  let api = @api.HarnessApi::new().unwrap()
  let first = rpc(api, "create-once", "session_create", {
    "id": "mcp-stable",
    "title": "RPC",
  })
  let retry = rpc(api, "create-once", "session_create", {
    "id": "mcp-stable",
    "title": "RPC",
  })
  assert_eq(get(get(retry, "result"), "isError"), true)
  assert_eq(get(get(first, "result"), "isError"), false)
  let list = api.invoke("session_list", {}).unwrap()
  match list {
    Array(sessions) => assert_eq(sessions.length(), 1)
    _ => fail("expected sessions")
  }
  let conflict = rpc(api, "create-once", "session_create", {
    "id": "mcp-stable",
    "title": "Changed",
  })
  assert_eq(get(get(conflict, "result"), "isError"), true)
  api.close()
}

///|
test "tool-result pruning is a validated state-change capability for idle sessions" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "prune-api" }).unwrap() |> ignore
  let result = api
    .invoke("session_prune_tool_results", { "session_id": "prune-api" })
    .unwrap()
  assert_eq(get(result, "chars_unit"), "unicode_code_points")
  match get(result, "pruned") {
    Array(entries) => assert_eq(entries.length(), 0)
    _ => fail("expected a pruning summary")
  }
  assert_true(
    api.invoke("session_prune_tool_results", {
      "session_id": "prune-api",
      "threshold": 10,
    })
    is Err(_),
  )
  api.close()
}

///|
test "capability send emits work and cancellation rejects its late settlement" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "cancel" }).unwrap() |> ignore
  api
  .invoke("session_send", { "session_id": "cancel", "prompt": "hello" })
  .unwrap()
  |> ignore
  let effects = api.take_effects()
  assert_eq(effects.length(), 1)
  let id = match get(effects[0], "id") {
    String(value) => value
    _ => fail("expected effect id")
  }
  api.invoke("session_cancel", { "session_id": "cancel" }).unwrap() |> ignore
  assert_true(
    api.complete(id, {
      "ok": true,
      "content": "late",
      "tool_calls": [],
      "finish_reason": "stop",
    })
    is Err(_),
  )
  assert_eq(api.take_effects().length(), 0)
  assert_eq(
    get(
      api.invoke("session_get", { "session_id": "cancel" }).unwrap(),
      "status",
    ),
    "cancelled",
  )
  let profile = api.invoke("profile_stats", {}).unwrap()
  match profile {
    String(text) => assert_true(text.contains("api.session_send"))
    _ => fail("expected hotpath report")
  }
  api.close()
}

///|
test "closing an API drains no effects and refuses future completions or restore" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "closing" }).unwrap() |> ignore
  api
  .invoke("session_send", { "session_id": "closing", "prompt": "work" })
  .unwrap()
  |> ignore
  let saved = api.snapshot()
  api.close()
  assert_eq(api.take_effects().length(), 0)
  assert_true(
    api.complete("effect-1", { "ok": false, "error": "late" }) is Err(_),
  )
  assert_true(api.restore(saved) is Err(_))
  api.close()
}
