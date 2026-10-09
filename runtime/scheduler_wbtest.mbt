///|
fn native_scheduler_tool_calls(tools : Array[(String, String, Json)]) -> Json {
  let calls : Array[Json] = []
  for (id, name, arguments) in tools {
    calls.push({
      "id": id.to_json(),
      "name": name.to_json(),
      "arguments": arguments.stringify().to_json(),
    })
  }
  {
    "ok": true,
    "content": "",
    "tool_calls": Json::array(calls),
    "finish_reason": "tool_calls",
  }
}

///|
fn native_scheduler_session(api : @api.HarnessApi, id : String) -> Unit {
  ignore(api.invoke("session_create", { "id": id, "title": id }).unwrap())
  ignore(
    api
    .invoke("session_send", { "session_id": id, "prompt": "schedule" })
    .unwrap(),
  )
}

///|
fn native_scheduler_initial_provider(
  api : @api.HarnessApi,
) -> Array[@engine.EngineEffect] raise {
  let effects = api.take_typed_effects()
  if effects.length() != 1 || effects[0].kind() != @engine.EffectType::Provider {
    fail("expected one initial provider effect")
  }
  effects
}

///|
async test "native rolling read pool caps four workers and preserves engine result order" {
  let api = @api.HarnessApi::new().unwrap()
  native_scheduler_session(api, "scheduler-pool")
  let provider = native_scheduler_initial_provider(api)
  let calls : Array[(String, String, Json)] = []
  for index in 0..<6 {
    calls.push(
      (
        "read-" + index.to_string(),
        "read",
        { "file_path": "file-" + index.to_string() + ".txt" },
      ),
    )
  }
  ignore(
    api
    .complete_effect(provider[0].id(), native_scheduler_tool_calls(calls))
    .unwrap(),
  )
  let initial = api.take_typed_effects()
  assert_eq(initial.length(), 4)
  let scheduler = NativeScheduler::new()
  let control = scheduler.begin("scheduler-pool", "pool-command", 1).unwrap()
  let active = Ref(0)
  let peak = Ref(0)
  let slow_read_finished = Ref(false)
  let replenished_before_slow_finish = Ref(false)
  let provider_request : Ref[Json?] = Ref(None)
  let result = native_drive_effects(scheduler, initial, control, async fn(
    effect,
  ) {
    if effect.kind() == @engine.EffectType::Provider {
      provider_request.val = Some(effect.request())
      let completion = api.complete_effect(effect.id(), {
        "ok": true,
        "content": "all reads completed",
        "tool_calls": [],
        "finish_reason": "stop",
      })
      match completion {
        Ok(value) => Ok((value, api.take_typed_effects()))
        Err(error) => Err(error)
      }
    } else {
      let arguments = object_field(effect.request(), "arguments").unwrap()
      let path = string_field(arguments, "file_path").unwrap()
      active.val += 1
      if active.val > peak.val {
        peak.val = active.val
      }
      if path == "file-4.txt" && !slow_read_finished.val {
        replenished_before_slow_finish.val = true
      }
      if path == "file-0.txt" {
        @async.sleep(120)
        slow_read_finished.val = true
      } else {
        @async.sleep(15)
      }
      active.val -= 1
      let completion = api.complete_effect(effect.id(), {
        "ok": true,
        "content": path,
      })
      match completion {
        Ok(value) => Ok((value, api.take_typed_effects()))
        Err(error) => Err(error)
      }
    }
  })
  assert_eq(result, Ok(()))
  assert_eq(peak.val, 4)
  assert_true(replenished_before_slow_finish.val)
  assert_true(slow_read_finished.val)
  let request = provider_request.val.unwrap()
  let messages = match object_field(request, "messages") {
    Some(Json::Array(values)) => values
    _ => fail("final provider request did not contain message history")
  }
  let ordered_results : Array[String] = []
  for message in messages {
    if string_field(message, "role") == Some("tool") {
      ordered_results.push(string_field(message, "tool_call_id").unwrap())
    }
  }
  assert_eq(ordered_results, [
    "read-0", "read-1", "read-2", "read-3", "read-4", "read-5",
  ])
  scheduler.finish(control)
  api.close()
}

///|
async test "native scheduler keeps write approval as a read-pool barrier" {
  let api = @api.HarnessApi::new().unwrap()
  native_scheduler_session(api, "scheduler-barrier")
  let provider = native_scheduler_initial_provider(api)
  ignore(
    api
    .complete_effect(
      provider[0].id(),
      native_scheduler_tool_calls([
        ("read-before", "read", { "file_path": "before.txt" }),
        (
          "write-middle",
          "write",
          { "file_path": "middle.txt", "content": "approved" },
        ),
        ("read-after", "read", { "file_path": "after.txt" }),
      ]),
    )
    .unwrap(),
  )
  let initial = api.take_typed_effects()
  assert_eq(initial.length(), 1)
  let scheduler = NativeScheduler::new()
  let control = scheduler
    .begin("scheduler-barrier", "barrier-command", 1)
    .unwrap()
  let order : Array[String] = []
  let runner = async fn(
    effect : @engine.EngineEffect,
  ) -> Result[(Json, Array[@engine.EngineEffect]), String] {
    @async.sleep(0)
    if effect.kind() == @engine.EffectType::Provider {
      order.push("provider")
      match
        api.complete_effect(effect.id(), {
          "ok": true,
          "content": "barriers respected",
          "tool_calls": [],
          "finish_reason": "stop",
        }) {
        Ok(value) => Ok((value, api.take_typed_effects()))
        Err(error) => Err(error)
      }
    } else {
      let request = effect.request()
      let name = string_field(request, "name").unwrap()
      order.push(name)
      match
        api.complete_effect(effect.id(), {
          "ok": true,
          "content": name + " done",
        }) {
        Ok(value) => Ok((value, api.take_typed_effects()))
        Err(error) => Err(error)
      }
    }
  }
  assert_eq(native_drive_effects(scheduler, initial, control, runner), Ok(()))
  assert_eq(order, ["read"])
  let snapshot = api
    .invoke("session_get", { "session_id": "scheduler-barrier" })
    .unwrap()
  assert_eq(string_field(snapshot, "status"), Some("awaiting_approval"))
  let pending = object_field(snapshot, "pending_approval").unwrap()
  let call_id = string_field(pending, "call_id").unwrap()
  ignore(
    api
    .invoke("tool_approve", {
      "session_id": "scheduler-barrier",
      "call_id": call_id,
      "approved": true,
    })
    .unwrap(),
  )
  let approved = api.take_typed_effects()
  assert_eq(approved.length(), 1)
  assert_eq(native_drive_effects(scheduler, approved, control, runner), Ok(()))
  assert_eq(order, ["read", "write", "read", "provider"])
  scheduler.finish(control)
  api.close()
}
