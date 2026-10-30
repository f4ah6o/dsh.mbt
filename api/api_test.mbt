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
fn message_text(message : Json) -> String raise {
  match get(message, "content") {
    String(text) => text
    Array(blocks) if blocks.length() == 1 =>
      match get(blocks[0], "text") {
        String(text) => text
        _ => fail("expected a text block")
      }
    _ => fail("expected message text")
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
    "id": id,
    "method": "tools/call",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
      "name": operation,
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
test "detached API candidates isolate session pruning until explicit adoption" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "detached-api" }).unwrap() |> ignore
  api
  .invoke("session_send", {
    "session_id": "detached-api",
    "prompt": "read one file",
  })
  .unwrap()
  |> ignore
  let provider = api.take_typed_effects()[0]
  api
  .complete_effect(provider.id(), {
    "ok": true,
    "content": "",
    "tool_calls": [
      {
        "id": "detached-read",
        "name": "read",
        "arguments": "{\"file_path\":\"large.txt\"}",
      },
    ],
    "finish_reason": "tool_calls",
  })
  .unwrap()
  |> ignore
  let read = api.take_typed_effects()[0]
  match
    api.complete_effect(read.id(), {
      "ok": true,
      "content": "x".repeat(512),
      "is_error": false,
    }) {
    Ok(_) => ()
    Err(error) => fail("read effect failed: " + error)
  }
  let follow_up = api.take_typed_effects()[0]
  api
  .complete_effect(follow_up.id(), {
    "ok": true,
    "content": "done",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  api.invoke("session_create", { "id": "detached-other" }).unwrap() |> ignore
  api
  .invoke("session_send", {
    "session_id": "detached-other",
    "prompt": "keep this turn pending",
  })
  .unwrap()
  |> ignore
  let other_effect = api.take_typed_effects()[0]
  let before = api.snapshot()
  let candidate = api.detached_copy().unwrap()
  let prune = candidate
    .invoke("session_prune_tool_results", {
      "session_id": "detached-api",
      "threshold_chars": 100,
      "head_chars": 40,
      "tail_chars": 20,
    })
    .unwrap()
  assert_eq(get(prune, "chars_removed"), 413)
  assert_eq(api.snapshot(), before)
  assert_true(candidate.snapshot() != before)
  assert_eq(
    get(
      candidate
      .invoke("session_get", { "session_id": "detached-other" })
      .unwrap(),
      "status",
    ),
    "running",
  )
  candidate
  .complete_effect(other_effect.id(), {
    "ok": true,
    "content": "candidate only",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  assert_eq(
    get(
      api.invoke("session_get", { "session_id": "detached-other" }).unwrap(),
      "status",
    ),
    "running",
  )
  candidate.close()
  api.close()
}

///|
test "session fork is exposed as a validated GUI capability and returns lineage" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "fork-api", "max_steps": 3 }).unwrap()
  |> ignore
  api
  .invoke("session_send", {
    "session_id": "fork-api",
    "prompt": "Create a settled source conversation",
  })
  .unwrap()
  |> ignore
  let effects = api.take_effects()
  assert_eq(effects.length(), 1)
  let effect_id = match get(effects[0], "id") {
    String(value) => value
    _ => fail("expected provider effect id")
  }
  api
  .complete(effect_id, {
    "ok": true,
    "content": "settled",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  let fork = api
    .invoke("session_fork", {
      "session_id": "fork-api",
      "id": "fork-api-child",
      "title": "Review branch",
    })
    .unwrap()
  assert_eq(get(fork, "parent_session_id"), "fork-api")
  assert_eq(get(fork, "title"), "Review branch")
  assert_eq(get(fork, "status"), "idle")
  let summaries = api.invoke("session_list", {}).unwrap()
  match summaries {
    Array(sessions) => {
      let mut child_summary : Json? = None
      for session in sessions {
        if get(session, "id") == "fork-api-child" {
          child_summary = Some(session)
        }
      }
      match child_summary {
        Some(summary) =>
          assert_eq(get(summary, "parent_session_id"), "fork-api")
        None => fail("forked child missing from session summaries")
      }
    }
    _ => fail("expected session summaries")
  }
  assert_true(api.manifest().contains("session_fork"))
  api.close()
}

///|
test "provider todo_write roundtrip updates the session projection without a host effect" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "todo-provider" }).unwrap() |> ignore
  api
  .invoke("session_send", {
    "session_id": "todo-provider",
    "prompt": "Plan and implement a small feature",
  })
  .unwrap()
  |> ignore
  let first_effects = api.take_effects()
  assert_eq(first_effects.length(), 1)
  let provider_id = match get(first_effects[0], "id") {
    String(value) => value
    _ => fail("expected provider effect id")
  }
  let tools = match get(get(first_effects[0], "request"), "tools") {
    Array(values) => values
    _ => fail("expected provider tool catalog")
  }
  let mut todo_tool : Json? = None
  for tool in tools {
    if get(tool, "name") == "todo_write" {
      todo_tool = Some(tool)
    }
  }
  match todo_tool {
    Some(tool) => assert_eq(get(tool, "effect"), "session")
    _ => fail("provider request must expose native todo_write")
  }
  let updated = api
    .complete(provider_id, {
      "ok": true,
      "content": "",
      "tool_calls": [
        {
          "id": "todo-api-call",
          "name": "todo_write",
          "arguments": "{\"todos\":[{\"content\":\"Implement feature\",\"status\":\"in_progress\"},{\"content\":\"Verify\",\"status\":\"pending\"}]}",
        },
      ],
      "finish_reason": "tool_calls",
    })
    .unwrap()
  assert_eq(get(updated, "todos"), [
    { "content": "Implement feature", "status": "in_progress" },
    { "content": "Verify", "status": "pending" },
  ])
  let follow_up = api.take_effects()
  assert_eq(follow_up.length(), 1)
  assert_eq(get(follow_up[0], "kind"), "llm")
  let done = api
    .complete(
      match get(follow_up[0], "id") {
        String(value) => value
        _ => fail("expected follow-up provider effect id")
      },
      {
        "ok": true,
        "content": "Both tasks are complete.",
        "tool_calls": [],
        "finish_reason": "stop",
      },
    )
    .unwrap()
  assert_eq(get(done, "todos"), get(updated, "todos"))
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
  api.close()
}

///|
test "runtime profiling is absent from direct GUI manifest and MCP capabilities" {
  let api = @api.HarnessApi::new().unwrap()
  assert_eq(
    api.invoke("profile_stats", {}),
    Err("Unknown operation: profile_stats"),
  )
  assert_true(api.gui_binding("profile_stats") is None)
  assert_true(!api.manifest().contains("profile_stats"))
  let listed = api
    .mcp_handle(
      "{\"jsonrpc\":\"2.0\",\"id\":\"list\",\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}",
    )
    .unwrap()
  let tools = get(get(@json.parse(listed), "result"), "tools")
  match tools {
    Array(tools) => {
      assert_eq(tools.length(), 10)
      for tool in tools {
        assert_true(get(tool, "name") != Json::string("profile_stats"))
      }
    }
    _ => fail("expected MCP tools")
  }
  let rejected = rpc(api, "removed-profile", "profile_stats", {})
  assert_eq(get(get(rejected, "error"), "code"), -32602)
  api.close()
}

///|
test "native API drains and settles typed effects against typed event identity" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "typed-api" }).unwrap() |> ignore
  api
  .invoke("session_send", { "session_id": "typed-api", "prompt": "typed" })
  .unwrap()
  |> ignore
  let effects = api.take_typed_effects()
  assert_eq(effects.length(), 1)
  let effect = effects[0]
  assert_true(effect.kind() == @engine.EffectType::Provider)
  assert_eq(effect.id().as_string(), "effect-1")
  api.project_effect_stream(effect.id(), "answer", "").unwrap() |> ignore
  api
  .complete_effect(effect.id(), {
    "ok": true,
    "content": "answer",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  let session_id = @engine.SessionId::new("typed-api").unwrap()
  let events = api.event_log(session_id).unwrap()
  assert_true(
    events.any(event => event.kind() == @engine.EngineEventKind::TurnStarted),
  )
  api.close()
}

///|
test "native API measures its active provider request without draining effects" {
  let api = @api.HarnessApi::new().unwrap()
  api
  .invoke("session_create", {
    "id": "context-measurement-api",
    "system_prompt": "System 🌙",
  })
  .unwrap()
  |> ignore
  api
  .invoke("session_send", {
    "session_id": "context-measurement-api",
    "prompt": "Question 😀",
  })
  .unwrap()
  |> ignore

  let session_id = @engine.SessionId::new("context-measurement-api").unwrap()
  let before = api.snapshot()
  let measurement = api
    .provider_context_measurement(session_id)
    .unwrap()
    .unwrap()
  assert_eq(api.snapshot(), before)
  assert_eq(measurement.message_count(), 1)
  assert_eq(
    measurement.system_text_code_points(),
    "System 🌙"[:].char_length(),
  )
  let effects = api.take_typed_effects()
  assert_eq(effects.length(), 1)
  assert_eq(
    measurement.request_json_utf8_bytes(),
    @utf8.encode(effects[0].request().stringify()).length(),
  )
  assert_true(api.provider_context_measurement(session_id) is Ok(Some(_)))
  assert_true(api.take_typed_effects().is_empty())

  api
  .complete_effect(effects[0].id(), {
    "ok": true,
    "content": "done",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  assert_true(api.provider_context_measurement(session_id) is Ok(None))
  api.close()
}

///|
test "session_send byte ceiling rejects before provider dispatch through the API schema" {
  let api = @api.HarnessApi::new().unwrap()
  api
  .invoke("session_create", {
    "id": "api-byte-ceiling",
    "system_prompt": "system",
  })
  .unwrap()
  |> ignore
  let refused = api
    .invoke("session_send", {
      "session_id": "api-byte-ceiling",
      "prompt": "question",
      "max_provider_request_utf8_bytes": 1,
    })
    .unwrap()
  assert_eq(get(refused, "status"), Json::string("failed"))
  assert_true(api.take_effects().is_empty())
  let before = api.snapshot()
  assert_true(
    api.invoke("session_send", {
      "session_id": "api-byte-ceiling",
      "prompt": "another question",
      "max_provider_request_utf8_bytes": 0,
    })
    is Err(_),
  )
  assert_eq(api.snapshot(), before)
  api.invoke("session_create", { "id": "api-hook-byte-ceiling" }).unwrap()
  |> ignore
  let hook_refused = api
    .invoke_session_send_with_prompt_contexts(
      {
        "session_id": "api-hook-byte-ceiling",
        "prompt": "question",
        "max_provider_request_utf8_bytes": 1,
      },
      ["already completed hook output"],
    )
    .unwrap()
  assert_eq(get(hook_refused, "status"), Json::string("failed"))
  assert_true(api.take_effects().is_empty())
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

///|
test "closing an API preserves a quiescent tool approval for host restart" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "approval-restart" }).unwrap() |> ignore
  api
  .invoke("session_send", {
    "session_id": "approval-restart",
    "prompt": "write a file",
  })
  .unwrap()
  |> ignore
  let effects = api.take_effects()
  assert_eq(effects.length(), 1)
  let provider_id = match get(effects[0], "id") {
    String(value) => value
    _ => fail("expected provider effect id")
  }
  api
  .complete(provider_id, {
    "ok": true,
    "content": "",
    "tool_calls": [
      {
        "id": "write-call",
        "name": "write",
        "arguments": "{\"file_path\":\"persisted.txt\",\"content\":\"hello\"}",
      },
    ],
    "finish_reason": "tool_calls",
  })
  .unwrap()
  |> ignore
  let before_close = api
    .invoke("session_get", { "session_id": "approval-restart" })
    .unwrap()
  assert_eq(get(before_close, "status"), "awaiting_approval")
  api.close()
  let sessions = match get(api.snapshot(), "sessions") {
    Array(values) => values
    _ => fail("expected saved sessions")
  }
  assert_eq(sessions.length(), 1)
  assert_eq(get(sessions[0], "status"), "awaiting_approval")
  assert_eq(get(get(sessions[0], "pending_approval"), "call_id"), "write-call")
}

///|
test "session_send exposes the opt-in pruning field and preserves hook context order" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "auto-prune-api" }).unwrap() |> ignore
  let before = api.snapshot().stringify()
  assert_true(
    api.invoke("session_send", {
      "session_id": "auto-prune-api",
      "prompt": "bad flag",
      "auto_prune_tool_results": "yes",
    })
    is Err(_),
  )
  assert_eq(api.snapshot().stringify(), before)

  let sent = api
    .invoke_session_send_with_hook_contexts(
      {
        "session_id": "auto-prune-api",
        "prompt": "continue",
        "auto_prune_tool_results": true,
      },
      ["session-start context"],
      ["prompt-hook context"],
    )
    .unwrap()
  let messages = match get(sent, "messages") {
    Array(messages) => messages
    _ => fail("expected transcript messages")
  }
  assert_eq(messages.length(), 3)
  assert_eq(message_text(messages[0]), "session-start context")
  assert_eq(message_text(messages[1]), "continue")
  assert_eq(message_text(messages[2]), "prompt-hook context")

  let effects = api.take_effects()
  assert_eq(effects.length(), 1)
  let request_messages = match get(get(effects[0], "request"), "messages") {
    Array(messages) => messages
    _ => fail("expected provider request messages")
  }
  assert_eq(request_messages.length(), 3)
  assert_eq(message_text(request_messages[0]), "session-start context")
  assert_eq(message_text(request_messages[1]), "continue")
  assert_eq(message_text(request_messages[2]), "prompt-hook context")
  api.close()
}

///|
test "hook-dispatched send forwards automatic pruning for a long tool result" {
  let api = @api.HarnessApi::new().unwrap()
  api.invoke("session_create", { "id": "auto-prune-hook" }).unwrap() |> ignore
  api
  .invoke("session_send", {
    "session_id": "auto-prune-hook",
    "prompt": "Read the long output",
  })
  .unwrap()
  |> ignore
  let first_effects = api.take_effects()
  assert_eq(first_effects.length(), 1)
  let first_id = match get(first_effects[0], "id") {
    String(value) => value
    _ => fail("expected provider effect id")
  }
  api
  .complete(first_id, {
    "ok": true,
    "content": "",
    "tool_calls": [
      {
        "id": "read-long",
        "name": "read",
        "arguments": "{\"file_path\":\"large.txt\"}",
      },
    ],
    "finish_reason": "tool_calls",
  })
  .unwrap()
  |> ignore
  let tool_effects = api.take_effects()
  assert_eq(tool_effects.length(), 1)
  let tool_id = match get(tool_effects[0], "id") {
    String(value) => value
    _ => fail("expected tool effect id")
  }
  let original = "😀"[:].repeat(8193).to_owned()
  api.complete(tool_id, { "ok": true, "content": original }).unwrap() |> ignore
  let followup_effects = api.take_effects()
  assert_eq(followup_effects.length(), 1)
  let followup_id = match get(followup_effects[0], "id") {
    String(value) => value
    _ => fail("expected follow-up provider effect id")
  }
  api
  .complete(followup_id, {
    "ok": true,
    "content": "Read complete",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  assert_eq(api.take_effects().length(), 0)

  let sent = api
    .invoke_session_send_with_hook_contexts(
      {
        "session_id": "auto-prune-hook",
        "prompt": "Continue with bounded context",
        "auto_prune_tool_results": true,
      },
      ["session-start context"],
      ["prompt-hook context"],
    )
    .unwrap()
  let transcript_tools = match get(sent, "messages") {
    Array(messages) =>
      messages.filter(message => get(message, "role") == "tool")
    _ => fail("expected transcript messages")
  }
  assert_eq(transcript_tools.length(), 1)
  assert_eq(get(transcript_tools[0], "content"), Json::string(original))

  let effects = api.take_effects()
  assert_eq(effects.length(), 1)
  let request_messages = match get(get(effects[0], "request"), "messages") {
    Array(messages) => messages
    _ => fail("expected provider request messages")
  }
  let request_tools = request_messages.filter(message => {
    get(message, "role") == "tool"
  })
  assert_eq(request_tools.length(), 1)
  assert_eq(get(request_tools[0], "tool_call_id"), "read-long")
  assert_eq(
    get(request_tools[0], "content"),
    Json::string(
      "😀"[:].repeat(4096).to_owned() +
      "\n\n[... tool result middle pruned ...]\n\n" +
      "😀"[:].repeat(1024).to_owned(),
    ),
  )
  assert_true(request_messages.length() >= 3)
  let last = request_messages.length() - 1
  assert_eq(message_text(request_messages[last - 2]), "session-start context")
  assert_eq(
    message_text(request_messages[last - 1]),
    "Continue with bounded context",
  )
  assert_eq(message_text(request_messages[last]), "prompt-hook context")
  api.close()
}
