///|
async fn native_acp_test_wait_permission(
  output : Ref[Array[String]],
  session_id : String,
) -> Json? {
  let mut polls = 0
  while polls < 400 {
    for line in output.val {
      let value = @json.parse(line) catch { _ => Json::null() }
      if string_field(value, "method") == Some("session/request_permission") {
        let params = object_field(value, "params").unwrap_or(Json::null())
        if string_field(params, "sessionId") == Some(session_id) {
          return Some(value)
        }
      }
    }
    @async.sleep(5)
    polls += 1
  }
  None
}

///|
fn native_acp_test_permission_response(
  permission : Json,
  option : String,
) -> Json {
  {
    "jsonrpc": "2.0",
    "id": object_field(permission, "id").unwrap_or(Json::null()),
    "result": { "outcome": { "outcome": "selected", "optionId": option } },
  }
}

///|
fn native_acp_test_apply_permission(
  service : NativeAcpService,
  response : Json,
) -> Unit raise {
  let message = match native_acp_rpc_message(response) {
    Ok(value) => value
    Err(error) => fail("test permission response was invalid: " + error)
  }
  service.resolve_client_response(message, response)
}

///|
fn native_acp_test_updates(
  output : Ref[Array[String]],
  session_id : String,
) -> Array[Json] {
  let updates : Array[Json] = []
  for line in output.val {
    let value = @json.parse(line) catch { _ => Json::null() }
    if string_field(value, "method") == Some("session/update") {
      let params = object_field(value, "params").unwrap_or(Json::null())
      if string_field(params, "sessionId") == Some(session_id) {
        updates.push(object_field(params, "update").unwrap_or(Json::null()))
      }
    }
  }
  updates
}

///|
async test "ACP keeps synthetic hook context out of human and assistant text updates" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-hook-context")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = NativeRuntime::open(fixture + "/data", workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let output : Ref[Array[String]] = Ref([])
    let service = NativeAcpService::new(runtime, fn(line) {
      output.val.push(line)
      Ok(())
    })
    let session : NativeAcpSession = {
      session_id: "acp-hook-context",
      native_session_id: "native-hook-context",
      event_gate: @async.Mutex::Mutex(),
      last_event_seq: 0,
      prompt_generation: 0,
      prompt_active: false,
      resuming: false,
      cancelled: false,
      closing: false,
      closed: false,
      cancel_required: false,
      cancel_sent: false,
      prompt_done: None,
      pending_permission: None,
    }
    let state : Json = {
      "events": [
        {
          "seq": 1,
          "type": "user/message",
          "data": {
            "role": "user",
            "content": [{ "type": "text", "text": "private hook context" }],
            "source": { "kind": "hooks-claude-code" },
          },
        },
      ],
    }
    service.emit_committed_events(session, state).unwrap()
    assert_eq(session.last_event_seq, 1)
    assert_true(output.val.is_empty())
    assert_false(output.val.any(line => line.contains("private hook context")))
  }
}

///|
test "ACP model allowlist is bounded strict JSON and rejects duplicates" {
  assert_eq(native_acp_parse_model_allowlist(None), Ok([]))
  assert_eq(
    native_acp_parse_model_allowlist(Some("[\"model-a\",\"model-b\"]")),
    Ok(["model-a", "model-b"]),
  )
  assert_true(
    native_acp_parse_model_allowlist(Some("model-a,model-b")) is Err(_),
  )
  let byte_boundary = StringBuilder()
  for _ in 0..<(NATIVE_ACP_MODEL_ENV_BYTE_LIMIT - 2) {
    byte_boundary.write_char(' ')
  }
  byte_boundary.write_string("[]")
  assert_eq(
    native_acp_parse_model_allowlist(Some(byte_boundary.to_string())),
    Ok([]),
  )
  byte_boundary.write_char(' ')
  assert_true(
    native_acp_parse_model_allowlist(Some(byte_boundary.to_string())) is Err(_),
  )
  assert_true(
    native_acp_parse_model_allowlist(Some("{\"model\":\"x\"}")) is Err(_),
  )
  assert_true(
    native_acp_parse_model_allowlist(Some("[\"same\",\"same\"]")) is Err(_),
  )
  assert_true(native_acp_parse_model_allowlist(Some("[\"model\",2]")) is Err(_))
  let long_name = StringBuilder()
  for _ in 0..<257 {
    long_name.write_char('x')
  }
  assert_true(
    native_acp_parse_model_allowlist(
      Some(Json::array([Json::string(long_name.to_string())]).stringify()),
    )
    is Err(_),
  )
  let too_many : Array[Json] = []
  for _ in 0..<(NATIVE_ACP_MODEL_LIMIT + 1) {
    too_many.push(Json::string("model"))
  }
  assert_true(
    native_acp_parse_model_allowlist(Some(Json::array(too_many).stringify()))
    is Err(_),
  )
}

///|
test "ACP route fingerprint uses the provider-normalized API root" {
  let omitted = native_acp_route_fingerprint(
    NativeProtocol::OpenAIChatCompletions,
    "api-key",
    "https://api.openai.com",
    false,
  )
  let variants = [
    "https://api.openai.com", "https://api.openai.com/", "https://api.openai.com/v1",
    "https://api.openai.com/v1/",
  ]
  for base_url in variants {
    assert_eq(
      native_acp_route_fingerprint(
        NativeProtocol::OpenAIChatCompletions,
        "api-key",
        base_url,
        false,
      ),
      omitted,
    )
  }
  assert_true(
    native_acp_route_fingerprint(
      NativeProtocol::OpenAIChatCompletions,
      "api-key",
      "https://api.openai.com/custom/v1",
      false,
    ) !=
    omitted,
  )
}

///|
async test "ACP accepts the longest escaped advertised model selector" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-model-selector")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = match
      NativeRuntime::open(
        fixture + "/data",
        workspace,
        false,
        false,
        mode_override="openai",
        model_override="base-model",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let raw_model = StringBuilder()
    raw_model.write_string("[\"")
    for _ in 0..<(NATIVE_ACP_MODEL_NAME_LIMIT - 1) {
      raw_model.write_string("\\u0001")
    }
    raw_model.write_string("x\"]")
    let model = native_acp_parse_model_allowlist(Some(raw_model.to_string())).unwrap()[0]
    let selector = native_acp_model_value(
      NativeProtocol::OpenAIChatCompletions,
      model,
    )
    assert_true(selector.length() > 1024)
    let output : Ref[Array[String]] = Ref([])
    let service = NativeAcpService::new_with_model_config(
      runtime,
      fn(line) {
        output.val.push(line)
        Ok(())
      },
      Ok([model]),
    )
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let created = service.new_session({
      "cwd": runtime.tools.workspace,
      "mcpServers": [],
    })
    let created_result = created.unwrap()
    let session_id = string_field(created_result, "sessionId").unwrap()
    let config_options = match object_field(created_result, "configOptions") {
      Some(Json::Array(values)) => values
      _ => fail("ACP session omitted model config options")
    }
    let provider_group = object_field(config_options[0], "options").unwrap_or(
      Json::null(),
    )
    let choices = match provider_group {
      Json::Array(groups) =>
        match object_field(groups[0], "options") {
          Some(Json::Array(values)) => values
          _ => fail("model provider group omitted its choices")
        }
      _ => fail("model config omitted its provider group")
    }
    assert_true(
      choices.any(choice => string_field(choice, "value") == Some(selector)),
    )
    let changed = service.set_config_option({
      "sessionId": session_id,
      "configId": "model",
      "value": selector,
    })
    let changed_options = match
      object_field(changed.unwrap(), "configOptions") {
      Some(Json::Array(values)) => values
      _ => fail("model change omitted its resulting options")
    }
    assert_eq(string_field(changed_options[0], "currentValue"), Some(selector))
    assert_true(service.close_session({ "sessionId": session_id }) is Ok(_))
    assert_true(runtime.close() is Ok(_))
  }
}

///|
async test "ACP model option persists per session and refuses removed or reinterpreted selections" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-model-config")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    let open_runtime = async fn(mode : String, base_url : String) {
      match
        NativeRuntime::open(
          data_dir,
          workspace,
          false,
          false,
          mode_override=mode,
          model_override="base-model",
          base_url_override=base_url,
        ) {
        Ok(value) => value
        Err(error) => fail(error)
      }
    }
    let runtime = open_runtime("openai", "")
    let startup_route = runtime.acp_route_id().unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let output : Ref[Array[String]] = Ref([])
    let service = NativeAcpService::new_with_model_config(
      runtime,
      fn(line) {
        output.val.push(line)
        Ok(())
      },
      Ok(["alternate-model"]),
    )
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let created = service.new_session({ "cwd": workspace, "mcpServers": [] })
    let created_result = created.unwrap()
    let session_id = string_field(created_result, "sessionId").unwrap()
    let legacy_session_id = "legacy-acp-model-selection"
    let legacy_created = runtime
      .create_acp_session(
        legacy_session_id,
        runtime.tools.workspace,
        None,
        startup_route,
      )
      .unwrap()
    assert_eq(string_field(legacy_created, "id"), Some(legacy_session_id))
    runtime.state.acp_sessions = runtime.state.acp_sessions.map(record => {
      if record.session_id == legacy_session_id {
        { ..record, model: None, route: None, }
      } else {
        record
      }
    })
    runtime.checkpoint_locked().unwrap()
    let options = match object_field(created_result, "configOptions") {
      Some(Json::Array(values)) => values
      _ => fail("new ACP session omitted model config options")
    }
    assert_eq(options.length(), 1)
    let option = options[0]
    assert_eq(string_field(option, "id"), Some("model"))
    assert_eq(string_field(option, "category"), Some("model"))
    assert_eq(string_field(option, "type"), Some("select"))
    assert_eq(
      string_field(option, "currentValue"),
      Some(
        native_acp_model_value(
          NativeProtocol::OpenAIChatCompletions,
          "base-model",
        ),
      ),
    )
    let groups = match object_field(option, "options") {
      Some(Json::Array(values)) => values
      _ => fail("model choices omitted provider group")
    }
    assert_eq(string_field(groups[0], "group"), Some("openai"))
    let choices = match object_field(groups[0], "options") {
      Some(Json::Array(values)) => values
      _ => fail("model provider group omitted its choices")
    }
    assert_eq(
      choices.map(choice => string_field(choice, "name").unwrap_or("")),
      ["base-model", "alternate-model"],
    )
    let changed = service
      .set_config_option({
        "sessionId": session_id,
        "configId": "model",
        "value": native_acp_model_value(
          NativeProtocol::OpenAIChatCompletions,
          "alternate-model",
        ),
      })
      .unwrap()
    let changed_option = match object_field(changed, "configOptions") {
      Some(Json::Array(values)) => values[0]
      _ => fail("model update omitted resulting options")
    }
    assert_eq(
      string_field(changed_option, "currentValue"),
      Some(
        native_acp_model_value(
          NativeProtocol::OpenAIChatCompletions,
          "alternate-model",
        ),
      ),
    )
    let config_updates = native_acp_test_updates(output, session_id)
    assert_eq(config_updates.length(), 1)
    assert_eq(
      string_field(config_updates[0], "sessionUpdate"),
      Some("config_option_update"),
    )
    assert_true(
      service.set_config_option({
        "sessionId": session_id,
        "configId": "model",
        "value": "not-advertised",
      })
      is Err(_),
    )
    let native_session_id = service.sessions.get(session_id).unwrap().native_session_id
    let (_, saved_record) = runtime.read_acp_session(native_session_id).unwrap()
    let saved_record = saved_record.unwrap()
    assert_eq(saved_record.model, Some("alternate-model"))
    assert_eq(saved_record.route, Some(startup_route))
    assert_true(service.close_session({ "sessionId": session_id }) is Ok(_))
    assert_true(runtime.close() is Ok(_))

    let restored = open_runtime("openai", "")
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(restored.close()))
    })
    let restored_output : Ref[Array[String]] = Ref([])
    let restored_service = NativeAcpService::new_with_model_config(
      restored,
      fn(line) {
        restored_output.val.push(line)
        Ok(())
      },
      Ok(["alternate-model"]),
    )
    assert_true(restored_service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let resume_result = restored_service
      .resume_session({
        "sessionId": session_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      .unwrap()
    let resumed_options = match object_field(resume_result, "configOptions") {
      Some(Json::Array(values)) => values
      _ => fail("resumed ACP session omitted model config options")
    }
    assert_eq(
      string_field(resumed_options[0], "currentValue"),
      Some(
        native_acp_model_value(
          NativeProtocol::OpenAIChatCompletions,
          "alternate-model",
        ),
      ),
    )
    assert_true(native_acp_test_updates(restored_output, session_id).is_empty())
    let legacy_resume = restored_service
      .resume_session({
        "sessionId": legacy_session_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      .unwrap()
    let legacy_options = match object_field(legacy_resume, "configOptions") {
      Some(Json::Array(values)) => values
      _ => fail("legacy ACP resume omitted model config options")
    }
    assert_eq(
      string_field(legacy_options[0], "currentValue"),
      Some(
        native_acp_model_value(
          NativeProtocol::OpenAIChatCompletions,
          "base-model",
        ),
      ),
    )
    let (_, adopted_legacy_record) = restored
      .read_acp_session(legacy_session_id)
      .unwrap()
    assert_eq(adopted_legacy_record.unwrap().model, Some("base-model"))
    assert_eq(adopted_legacy_record.unwrap().route, Some(startup_route))
    assert_true(
      native_acp_test_updates(restored_output, legacy_session_id).is_empty(),
    )
    assert_true(restored.api.take_typed_effects().is_empty())
    assert_true(restored.close() is Ok(_))

    let narrowed = open_runtime("openai", "")
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(narrowed.close()))
    })
    let narrowed_service = NativeAcpService::new_with_model_config(
      narrowed,
      fn(_) { Ok(()) },
      Ok([]),
    )
    assert_true(narrowed_service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let revision_before_refusal = narrowed.state.revision
    assert_true(
      narrowed_service.resume_session({
        "sessionId": session_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_eq(narrowed.state.revision, revision_before_refusal)
    let (_, refused_record) = narrowed.read_acp_session(session_id).unwrap()
    assert_eq(refused_record.unwrap().model, Some("alternate-model"))
    assert_eq(refused_record.unwrap().route, Some(startup_route))
    assert_true(narrowed.close() is Ok(_))

    let changed_route = open_runtime("openai-responses", "")
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(changed_route.close()))
    })
    let changed_route_service = NativeAcpService::new_with_model_config(
      changed_route,
      fn(_) { Ok(()) },
      Ok(["alternate-model"]),
    )
    assert_true(
      changed_route_service.initialize({ "protocolVersion": 1 }) is Ok(_),
    )
    let route_revision = changed_route.state.revision
    assert_true(
      changed_route_service.resume_session({
        "sessionId": session_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_eq(changed_route.state.revision, route_revision)
    let (_, route_record) = changed_route.read_acp_session(session_id).unwrap()
    assert_eq(route_record.unwrap().route, Some(startup_route))
    assert_true(changed_route.close() is Ok(_))

    let changed_base = open_runtime(
      "openai", "https://alternate-provider.example/v1",
    )
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(changed_base.close()))
    })
    let changed_base_service = NativeAcpService::new_with_model_config(
      changed_base,
      fn(_) { Ok(()) },
      Ok(["alternate-model"]),
    )
    assert_true(
      changed_base_service.initialize({ "protocolVersion": 1 }) is Ok(_),
    )
    let base_revision = changed_base.state.revision
    assert_true(
      changed_base_service.resume_session({
        "sessionId": session_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_eq(changed_base.state.revision, base_revision)
    let (_, base_record) = changed_base.read_acp_session(session_id).unwrap()
    assert_eq(base_record.unwrap().route, Some(startup_route))
    assert_true(changed_base.close() is Ok(_))

    let final_runtime = open_runtime("openai", "")
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(final_runtime.close()))
    })
    let final_service = NativeAcpService::new_with_model_config(
      final_runtime,
      fn(_) { Ok(()) },
      Ok(["alternate-model"]),
    )
    assert_true(final_service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let final_resume = final_service.resume_session({
      "sessionId": session_id,
      "cwd": workspace,
      "mcpServers": [],
    })
    assert_true(final_resume is Ok(_))
    assert_true(final_runtime.close() is Ok(_))
  }
}

///|
async test "ACP approved native turns preserve approval and isolate close across sessions" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-turns")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let output : Ref[Array[String]] = Ref([])
    let service = NativeAcpService::new(runtime, async fn(line) {
      @async.sleep(0)
      output.val.push(line)
      Ok(())
    })
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    assert_true(service.initialize({ "protocolVersion": 1 }) is Err(_))

    let created_a = service.new_session({ "cwd": workspace, "mcpServers": [] })
    let created_b = service.new_session({ "cwd": workspace, "mcpServers": [] })
    let session_a = string_field(created_a.unwrap(), "sessionId").unwrap()
    let session_b = string_field(created_b.unwrap(), "sessionId").unwrap()
    assert_true(
      service.resume_session({
        "sessionId": session_a,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let native_a = service.sessions.get(session_a).unwrap().native_session_id
    let native_b = service.sessions.get(session_b).unwrap().native_session_id

    let prompt_a : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let prompt_b : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let prepared_a = service
      .prepare_prompt({
        "sessionId": session_a,
        "prompt": [{ "type": "text", "text": "write a file" }],
      })
      .unwrap()
    let prepared_b = service
      .prepare_prompt({
        "sessionId": session_b,
        "prompt": [{ "type": "text", "text": "write a file" }],
      })
      .unwrap()
    let idle_options = runtime
      .acp_model_options(runtime.acp_default_model(), service.model_allowlist)
      .unwrap()
    let idle_option = match idle_options {
      Json::Array(values) => values[0]
      _ => fail("demo ACP session omitted its model option")
    }
    assert_true(
      service.set_config_option({
        "sessionId": session_a,
        "configId": "model",
        "value": string_field(idle_option, "currentValue").unwrap(),
      })
      is Err(_),
    )
    let prompt_task_a = group.spawn(async fn() {
      prompt_a.val = Some(service.execute_prompt(prepared_a))
    })
    let prompt_task_b = group.spawn(async fn() {
      prompt_b.val = Some(service.execute_prompt(prepared_b))
    })
    let busy = service.prepare_prompt({
      "sessionId": session_a,
      "prompt": [{ "type": "text", "text": "overlapping prompt" }],
    })
    assert_true(busy is Err(_))
    assert_true(
      service.resume_session({
        "sessionId": session_a,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )

    let permission_a = match
      native_acp_test_wait_permission(output, session_a) {
      Some(value) => value
      None => fail("ACP did not request permission for session A")
    }
    let permission_b = match
      native_acp_test_wait_permission(output, session_b) {
      Some(value) => value
      None => fail("ACP did not request permission for session B")
    }
    let close_session = service.begin_cancel(session_a, true).unwrap()
    let close_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let close_task = group.spawn(async fn() {
      close_result.val = Some(service.finish_close(close_session))
    })
    // The old allow reply arrives after close has already fenced A's pending
    // generation. It must be ignored, while B remains free to complete.
    let stale_allow = native_acp_test_permission_response(
      permission_a, "allow-once",
    )
    native_acp_test_apply_permission(service, stale_allow)
    let allow_b = native_acp_test_permission_response(
      permission_b, "allow-once",
    )
    native_acp_test_apply_permission(service, allow_b)

    let mut polls = 0
    while (
            prompt_a.val is None ||
            prompt_b.val is None ||
            close_result.val is None
          ) &&
          polls < 800 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(prompt_a.val is Some(_))
    assert_true(prompt_b.val is Some(_))
    assert_true(close_result.val is Some(_))
    let result_a = prompt_a.val.unwrap().unwrap()
    let result_b = prompt_b.val.unwrap().unwrap()
    assert_eq(string_field(result_a, "stopReason"), Some("cancelled"))
    assert_eq(string_field(result_b, "stopReason"), Some("end_turn"))
    assert_true(close_result.val.unwrap() is Ok(_))
    ignore(prompt_task_a.wait())
    ignore(prompt_task_b.wait())
    ignore(close_task.wait())
    assert_true(service.sessions.get(session_a).unwrap().closed)
    assert_true(service.sessions.get(session_b) is Some(_))
    assert_eq(
      @fs.read_file(workspace + "/native-demo.txt").text(),
      "durable native tool result",
    )

    let state_a = runtime
      .invoke("session_get", { "session_id": native_a })
      .unwrap().0
    let state_b = runtime
      .invoke("session_get", { "session_id": native_b })
      .unwrap().0
    assert_eq(string_field(state_a, "status"), Some("cancelled"))
    assert_eq(string_field(state_b, "status"), Some("completed"))
    let events_a = match object_field(state_a, "events").unwrap() {
      Json::Array(values) => values
      _ => fail("session A events were malformed")
    }
    let events_b = match object_field(state_b, "events").unwrap() {
      Json::Array(values) => values
      _ => fail("session B events were malformed")
    }
    assert_eq(
      events_a
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      1,
    )
    assert_eq(
      events_b
      .filter(event => string_field(event, "type") == Some("tool/result"))
      .length(),
      1,
    )
    let results_a = events_a.filter(event => {
      string_field(event, "type") == Some("tool/result")
    })
    assert_true(
      native_json_true(
        object_field(object_field(results_a[0], "data").unwrap(), "is_error"),
      ),
    )

    let updates_b = native_acp_test_updates(output, session_b)
    assert_eq(
      updates_b
      .filter(value => string_field(value, "sessionUpdate") == Some("tool_call"))
      .length(),
      1,
    )
    assert_eq(
      updates_b
      .filter(value => {
        string_field(value, "sessionUpdate") == Some("tool_call_update")
      })
      .length(),
      1,
    )
    assert_true(
      updates_b.any(value => {
        string_field(value, "sessionUpdate") == Some("agent_message_chunk")
      }),
    )
    for line in output.val {
      assert_false(line.contains("assistant/stream_delta"))
      let value = @json.parse(line) catch { _ => Json::null() }
      if string_field(value, "method") == Some("session/update") {
        let update = object_field(
          object_field(value, "params").unwrap(),
          "update",
        ).unwrap()
        assert_true(
          [
            "agent_thought_chunk", "agent_message_chunk", "tool_call", "tool_call_update",
          ].contains(string_field(update, "sessionUpdate").unwrap_or("")),
        )
      }
    }
    assert_true(service.shutdown() is Ok(_))
    assert_true(runtime.close() is Ok(_))
    let reopened = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let restored_a = reopened
      .invoke("session_get", { "session_id": native_a })
      .unwrap().0
    let restored_b = reopened
      .invoke("session_get", { "session_id": native_b })
      .unwrap().0
    assert_eq(string_field(restored_a, "status"), Some("cancelled"))
    assert_eq(string_field(restored_b, "status"), Some("completed"))
    for state in [restored_a, restored_b] {
      let events = match object_field(state, "events").unwrap() {
        Json::Array(values) => values
        _ => fail("reopened ACP session events were malformed")
      }
      assert_eq(
        events
        .filter(event => string_field(event, "type") == Some("tool/result"))
        .length(),
        1,
      )
    }

    let resumed_output : Ref[Array[String]] = Ref([])
    let resumed_service = NativeAcpService::new(reopened, async fn(line) {
      @async.sleep(0)
      resumed_output.val.push(line)
      Ok(())
    })
    assert_true(resumed_service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let revision_before_list = reopened.state.revision
    let listed = resumed_service.list_sessions({}).unwrap()
    assert_eq(reopened.state.revision, revision_before_list)
    assert_true(resumed_service.list_sessions({ "cursor": 123 }) is Err(_))
    assert_true(
      resumed_service.list_sessions({
        "cursor": Json::null(),
        "cwd": Json::null(),
      })
      is Ok(_),
    )
    let listed_sessions = match object_field(listed, "sessions") {
      Some(Json::Array(values)) => values
      _ => fail("ACP session list was malformed")
    }
    assert_eq(listed_sessions.length(), 2)
    assert_eq(string_field(listed_sessions[0], "sessionId"), Some(session_b))
    assert_eq(
      string_field(listed_sessions[0], "cwd"),
      Some(reopened.tools.workspace),
    )
    assert_true(string_field(listed_sessions[0], "updatedAt") is Some(_))

    assert_true(
      resumed_service.resume_session({
        "sessionId": "",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_true(
      resumed_service.resume_session({
        "sessionId": "acp-unknown-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let (_, unregistered_effects) = reopened
      .invoke("session_create", {
        "id": "acp-unregistered-id",
        "title": "not an ACP session",
      })
      .unwrap()
    assert_true(unregistered_effects.is_empty())
    assert_true(
      resumed_service.resume_session({
        "sessionId": "acp-unregistered-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let current_dir = @env.current_dir().unwrap_or_else(() => {
      fail("cannot resolve test checkout")
    })
    let imported_jsonl = @fs.read_file(
      current_dir + "/tests/fixtures/upstream-tool-call-turn/session.v4.jsonl",
    ).text()
    let (imported, imported_effects) = reopened
      .invoke("session_import", { "jsonl": imported_jsonl.to_json() })
      .unwrap()
    assert_true(imported_effects.is_empty())
    let imported_id = string_field(imported, "id").unwrap()
    assert_true(
      resumed_service.resume_session({
        "sessionId": imported_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let (forked, fork_effects) = reopened
      .invoke("session_fork", { "session_id": native_b })
      .unwrap()
    assert_true(fork_effects.is_empty())
    let forked_id = string_field(forked, "id").unwrap()
    assert_eq(string_field(forked, "parent_session_id"), Some(native_b))
    assert_true(
      resumed_service.resume_session({
        "sessionId": forked_id,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let listed_after_fork = resumed_service.list_sessions({}).unwrap()
    assert_eq(
      match object_field(listed_after_fork, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      2,
    )

    let resume_b = resumed_service.resume_session({
      "sessionId": session_b,
      "cwd": workspace,
      "mcpServers": [],
    })
    assert_true(resume_b is Ok(_))
    assert_true(
      resumed_service.resume_session({
        "sessionId": session_b,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    assert_true(
      resumed_service.close_session({ "sessionId": session_b }) is Ok(_),
    )
    assert_true(
      resumed_service.resume_session({
        "sessionId": session_b,
        "cwd": workspace,
        "mcpServers": [],
      })
      is Ok(_),
    )
    assert_true(native_acp_test_updates(resumed_output, session_b).is_empty())
    let continued = resumed_service
      .prepare_prompt({
        "sessionId": session_b,
        "prompt": [{ "type": "text", "text": "continue saved context" }],
      })
      .unwrap()
    let continued_result = resumed_service.execute_prompt(continued).unwrap()
    assert_eq(string_field(continued_result, "stopReason"), Some("end_turn"))
    let continued_updates = native_acp_test_updates(resumed_output, session_b)
    assert_false(
      continued_updates.any(value => {
        string_field(value, "sessionUpdate") == Some("tool_call")
      }),
    )
    assert_true(
      continued_updates.any(value => {
        string_field(value, "sessionUpdate") == Some("agent_message_chunk")
      }),
    )

    // Fence a second resume while its store read waits on the runtime gate.
    // Prompts are rejected while that placeholder is installed, and close can
    // cancel the in-flight resume without losing the persisted session.
    reopened.gate.acquire()
    let resume_a_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let resume_a_task = group.spawn(async fn() {
      resume_a_result.val = Some(
        resumed_service.resume_session({
          "sessionId": session_a,
          "cwd": workspace,
          "mcpServers": [],
        }),
      )
    })
    @async.sleep(10)
    assert_true(resumed_service.sessions.get(session_a).unwrap().resuming)
    assert_true(
      resumed_service.prepare_prompt({
        "sessionId": session_a,
        "prompt": [{ "type": "text", "text": "cannot race resume" }],
      })
      is Err(_),
    )
    let close_a_result : Ref[Result[Json, NativeAcpRpcError]?] = Ref(None)
    let close_a_task = group.spawn(async fn() {
      close_a_result.val = Some(
        resumed_service.close_session({ "sessionId": session_a }),
      )
    })
    @async.sleep(10)
    assert_true(resumed_service.sessions.get(session_a).unwrap().closing)
    reopened.gate.release()
    let mut resume_polls = 0
    while (resume_a_result.val is None || close_a_result.val is None) &&
          resume_polls < 200 {
      @async.sleep(5)
      resume_polls += 1
    }
    assert_true(resume_a_result.val.unwrap() is Err(_))
    assert_true(close_a_result.val.unwrap() is Ok(_))
    ignore(resume_a_task.wait())
    ignore(close_a_task.wait())
    assert_true(resumed_service.shutdown() is Ok(_))
    assert_true(reopened.close() is Ok(_))

    let foreign_workspace = fixture + "/foreign-workspace"
    @fs.mkdir(foreign_workspace)
    assert_true(
      NativeRuntime::open(fixture + "/data", foreign_workspace, false, true)
      is Err(_),
    )
    let restored_again = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(restored_again.close()))
    })
    let listed_again = NativeAcpService::new(restored_again, async fn(_) {
      @async.sleep(0)
      Ok(())
    })
    assert_true(listed_again.initialize({ "protocolVersion": 1 }) is Ok(_))
    let after_failed_foreign_open = listed_again.list_sessions({}).unwrap()
    assert_eq(
      match object_field(after_failed_foreign_open, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      2,
    )
  }
}

///|
async test "ACP list does not adopt legacy native ids without persisted provenance" {
  let fixture = @fs.tmpdir(prefix="dsh-native-acp-legacy")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data_dir = fixture + "/data"
    let runtime = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let (_, effects) = runtime
      .invoke("session_create", {
        "id": "acp-legacy-id",
        "title": "legacy custom id",
      })
      .unwrap()
    assert_true(effects.is_empty())
    assert_true(runtime.close() is Ok(_))

    let envelope_path = data_dir + "/sessions.json"
    let envelope = @json.parse(@fs.read_file(envelope_path).text())
    let fields = match envelope {
      Json::Object(value) => value
      _ => fail("native envelope was not an object")
    }
    assert_true(fields.get("acp_sessions") is Some(_))
    ignore(fields.remove("acp_sessions"))
    @fs.write_file(envelope_path, Json::object(fields).stringify())

    let reopened = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let service = NativeAcpService::new(reopened, async fn(_) {
      @async.sleep(0)
      Ok(())
    })
    assert_true(service.initialize({ "protocolVersion": 1 }) is Ok(_))
    let listed = service.list_sessions({}).unwrap()
    assert_eq(
      match object_field(listed, "sessions") {
        Some(Json::Array(values)) => values.length()
        _ => -1
      },
      0,
    )
    assert_true(
      service.resume_session({
        "sessionId": "acp-legacy-id",
        "cwd": workspace,
        "mcpServers": [],
      })
      is Err(_),
    )
    let legacy_state = reopened
      .invoke("session_get", { "session_id": "acp-legacy-id" })
      .unwrap().0
    assert_eq(string_field(legacy_state, "id"), Some("acp-legacy-id"))
  }
}

///|
test "ACP persisted registry validation rejects duplicate, dangling, imported, and foreign entries" {
  assert_true(native_acp_valid_timestamp("2024-02-29T23:59:59Z"))
  assert_true(native_acp_valid_timestamp("2026-10-10T00:00:00Z"))
  assert_false(native_acp_valid_timestamp("2023-02-29T12:00:00Z"))
  assert_false(native_acp_valid_timestamp("2026-99-99T99:99:99Z"))
  assert_false(native_acp_valid_timestamp("2024-04-31T10:00:00Z"))
  let cwd = "/workspace"
  let root : Json = { "id": "registered-root", "status": "idle", "events": [] }
  let snapshot : Json = { "sessions": [root] }
  let record : NativeAcpStoredSession = {
    session_id: "registered-root",
    cwd,
    updated_at: None,
    model: None,
    route: None,
  }
  assert_true(native_acp_validate_registry(snapshot, [record], cwd) is Ok(_))
  assert_true(
    native_acp_validate_registry(snapshot, [record, record], cwd) is Err(_),
  )
  let dangling : NativeAcpStoredSession = {
    ..record,
    session_id: "missing-native-session",
  }
  assert_true(native_acp_validate_registry(snapshot, [dangling], cwd) is Err(_))
  let foreign : NativeAcpStoredSession = { ..record, cwd: "/other", }
  assert_true(native_acp_validate_registry(snapshot, [foreign], cwd) is Err(_))
  let imported_snapshot : Json = {
    "sessions": [
      {
        "id": "registered-root",
        "status": "idle",
        "events": [],
        "source_format": "deepseek-session-v4",
      },
    ],
  }
  assert_true(
    native_acp_validate_registry(imported_snapshot, [record], cwd) is Err(_),
  )
  let forked_snapshot : Json = {
    "sessions": [
      {
        "id": "registered-root",
        "status": "idle",
        "events": [],
        "parent_session_id": "parent",
      },
    ],
  }
  assert_true(
    native_acp_validate_registry(forked_snapshot, [record], cwd) is Err(_),
  )
  let duplicate_json = native_acp_stored_sessions_from_json(
    Some(
      Json::array([
        { "session_id": "same", "cwd": cwd },
        { "session_id": "same", "cwd": cwd },
      ]),
    ),
  )
  assert_true(duplicate_json is Err(_))
}

///|
test "ACP registry migrates pre-model records and persists non-secret route identity" {
  let legacy = native_acp_stored_sessions_from_json(
    Some(
      Json::array([
        {
          "session_id": "legacy-acp-session",
          "cwd": "/workspace",
          "updated_at": Json::null(),
        },
      ]),
    ),
  )
  assert_true(legacy is Ok(_))
  let legacy_record = legacy.unwrap()[0]
  assert_eq(legacy_record.model, None)
  assert_eq(legacy_record.route, None)
  let selected : NativeAcpStoredSession = {
    ..legacy_record,
    model: Some("alternate-model"),
    route: Some("openai:api-key"),
  }
  let encoded = native_acp_stored_sessions_json([selected])
  let restored = native_acp_stored_sessions_from_json(Some(encoded))
  assert_eq(restored.unwrap()[0].model, Some("alternate-model"))
  assert_eq(restored.unwrap()[0].route, Some("openai:api-key"))
  assert_true(
    native_acp_stored_sessions_from_json(
      Some(
        Json::array([
          {
            "session_id": "missing-route",
            "cwd": "/workspace",
            "model": "alternate-model",
          },
        ]),
      ),
    )
    is Err(_),
  )
}
