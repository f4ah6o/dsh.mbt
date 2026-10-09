///|
async test "native provider todo_write is checkpointed and reopened without tool effects" {
  let fixture = @fs.tmpdir(prefix="dsh-native-todo-roundtrip")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let session_id = "native-todo-session"
    let runtime = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    runtime.invoke("session_create", { "id": session_id }).unwrap() |> ignore
    let (_, effects) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Plan a small feature",
      })
      .unwrap()
    let provider = match
      native_effect_by_kind(effects, @engine.EffectType::Provider) {
      Some(value) => value
      None => fail("expected provider effect")
    }
    let provider_tools = match object_field(provider.request(), "tools") {
      Some(Json::Array(values)) => values
      _ => fail("provider request did not contain the built-in catalog")
    }
    assert_true(
      provider_tools.any(tool => {
        string_field(tool, "name") == Some("todo_write") &&
        string_field(tool, "effect") == Some("session")
      }),
    )

    let (updated, next_effects) = runtime
      .complete(provider.id(), {
        "ok": true,
        "content": "",
        "tool_calls": [
          {
            "id": "native-todo-call",
            "name": "todo_write",
            "arguments": "{\"todos\":[{\"content\":\"Implement\",\"status\":\"in_progress\"},{\"content\":\"Verify\",\"status\":\"pending\"}]}",
          },
        ],
        "finish_reason": "tool_calls",
      })
      .unwrap()
    assert_eq(next_effects.length(), 1)
    match next_effects[0].kind() {
      @engine.EffectType::Provider => ()
      _ => fail("todo_write must not create a host tool effect")
    }
    assert_eq(
      object_field(updated, "todos"),
      Some(
        Json::array([
          { "content": "Implement", "status": "in_progress" },
          { "content": "Verify", "status": "pending" },
        ]),
      ),
    )
    let event_rows = match object_field(updated, "events") {
      Some(Json::Array(values)) => values
      _ => fail("updated session did not contain its durable event log")
    }
    assert_eq(
      event_rows
      .filter(event => string_field(event, "type") == Some("todo/write"))
      .length(),
      1,
    )
    assert_eq(
      event_rows
      .filter(event => string_field(event, "type") == Some("tool/request"))
      .length(),
      0,
    )
    assert_eq(
      event_rows
      .filter(event => {
        string_field(event, "type") == Some("tool/approval/requested")
      })
      .length(),
      0,
    )

    let (finished, final_effects) = runtime
      .complete(next_effects[0].id(), {
        "ok": true,
        "content": "Completed",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      .unwrap()
    assert_true(final_effects.is_empty())
    assert_eq(object_field(finished, "todos"), object_field(updated, "todos"))
    assert_true(runtime.close() is Ok(_))

    let reopened = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, restored_effects) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(restored_effects.is_empty())
    assert_eq(object_field(restored, "todos"), object_field(updated, "todos"))
    assert_eq(string_field(restored, "status"), Some("completed"))
  }
}
