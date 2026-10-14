///|
fn native_choice_test_credential(host_id : String) -> @auth.Credential {
  @auth.Credential::from_storage_json({
    "version": 1,
    "host_id": host_id,
    "client_id": "fixture-client",
    "subject": "fixture-account",
    "email": "user@example.test",
    "profile_id": "fixture-account",
    "id_token": "synthetic-id-token",
    "access_token": "synthetic-access-token",
    "refresh_token": "synthetic-refresh-token",
    "scopes": [
      "openid", "profile", "email", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct",
    ],
    "expires_at": native_auth_now() + 7200,
  }).unwrap()
}

///|
async test "desktop model selection routes root metadata subagents and ACP durably without API key fallback" {
  let fixture = @fs.tmpdir(prefix="dsh-provider-choice")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    let server = @http.Server::Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=false,
    )
    group.add_defer(() => server.close())
    let endpoint = "http://127.0.0.1:" +
      server.addr.port().to_string() +
      "/models"
    let original = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      false,
      mode_override="deepseek",
    ).unwrap()
    let runtime = {
      ..original,
      auth: {
        ..original.auth,
        endpoints: {
          ..AuthEndpoints::production(),
          models: endpoint,
          test_mode: true,
        },
      },
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let credential = native_choice_test_credential(runtime.store.host_id())
    runtime.auth.credential = Some(credential)
    runtime.auth.model_identity = Some(credential.identity_for_native())
    runtime.auth.models = [{ "slug": "gpt-test", "display_name": "GPT Test" }]
    runtime.auth.selected_model = Some("gpt-test")
    runtime.auth.login_state = "connected"
    runtime.auth.persist_locked().unwrap()
    // Merely connecting/caching an account preserves the configured API route.
    let configured = runtime.capture_provider_selection(None).unwrap()
    assert_true(configured.protocol() == DeepSeekMessages)
    assert_true(configured.auth_mode() == ApiKey)
    let old_route = runtime.acp_route_id().unwrap()
    runtime
    .create_acp_session(
      "choice-acp",
      runtime.tools.workspace,
      Some("deepseek-flash"),
      old_route,
    )
    .unwrap()
    |> ignore
    runtime
    .invoke("session_create", {
      "id": "choice-root",
      "title": "Provider choice",
    })
    .unwrap()
    |> ignore
    let (_, effects) = runtime
      .invoke("session_send", {
        "session_id": "choice-root",
        "prompt": "synthetic",
      })
      .unwrap()
    let effect = native_effect_by_kind(effects, @engine.EffectType::Provider).unwrap()
    let desktop : NativeDesktop = { runtime, }
    let catalog : Json = {
      "models": [
        { "slug": "gpt-test", "display_name": "GPT Test", "visibility": "list" },
      ],
    }
    let listing = group.spawn(async fn() {
      native_auth_serve_json_once(server, catalog.stringify(), 0)
    })
    desktop.auth_select_model("fixture-account", "gpt-test").unwrap() |> ignore
    listing.wait()
    // Cached same-model choice must still activate ChatGPT.
    let selected = runtime.capture_provider_selection(None).unwrap()
    assert_true(selected.protocol() == OpenAIResponses)
    assert_true(selected.auth_mode() == ChatGPT)
    assert_eq(selected.model(), "gpt-test")
    assert_true(runtime.validate_provider_selection(configured) is Err(_))
    let service = NativeService::new(runtime, workspace, 0).unwrap()
    let metadata = service.metadata()
    assert_eq(string_field(metadata, "provider"), Some("ChatGPT"))
    assert_eq(string_field(metadata, "model"), Some("gpt-test"))
    let binding = runtime.subagent_provider_binding("choice-root").unwrap()
    assert_true(binding.selection.auth_mode() == ChatGPT)
    assert_eq(binding.selection.model(), "gpt-test")
    assert_true(runtime.acp_model_for_session("choice-acp") is Err(_))
    runtime
    .set_acp_session_model(
      "choice-acp",
      Some("gpt-test"),
      runtime.acp_route_id().unwrap(),
    )
    .unwrap()
    assert_eq(runtime.acp_model_for_session("choice-acp"), Ok(Some("gpt-test")))
    assert_true(
      runtime
      .acp_model_options(Some("gpt-test"), [])
      .unwrap()
      .stringify()
      .contains("openai-responses"),
    )
    // Both operations begin while the old selection is valid and wait on the
    // runtime gate. A transition while they wait must be checked inside it.
    runtime.gate.acquire()
    let blocked_projection = group.spawn(async fn() {
      runtime.project_provider_delta(
        effect.id(),
        "stale answer",
        "",
        selection=Some(selected),
      )
    })
    let blocked_completion = group.spawn(async fn() {
      runtime.complete(
        effect.id(),
        { "ok": true, "content": "stale answer" },
        selection=Some(selected),
      )
    })
    @async.sleep(0)
    runtime.auth.use_configured_provider().unwrap() |> ignore
    runtime.gate.release()
    assert_true(blocked_projection.wait() is Err(_))
    blocked_completion.wait().unwrap() |> ignore
    let (session, _) = runtime
      .invoke("session_get", { "session_id": "choice-root" })
      .unwrap()
    assert_false(session.stringify().contains("stale answer"))
    assert_eq(string_field(session, "status"), Some("failed"))
    desktop.auth_use_configured_provider().unwrap() |> ignore
    assert_true(runtime.validate_provider_selection(selected) is Err(_))
    assert_eq(runtime.auth.selected_model, Some("gpt-test"))
    let listing_again = group.spawn(async fn() {
      native_auth_serve_json_once(server, catalog.stringify(), 0)
    })
    desktop.auth_select_model("fixture-account", "gpt-test").unwrap() |> ignore
    listing_again.wait()
    assert_true(
      runtime.capture_provider_selection(None).unwrap().auth_mode() == ChatGPT,
    )
    let route = runtime.acp_route_id().unwrap()
    runtime.close().unwrap()
    let reopened = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      false,
      mode_override="deepseek",
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    assert_true(
      reopened.capture_provider_selection(None).unwrap().auth_mode() == ChatGPT,
    )
    assert_eq(reopened.acp_route_id(), Ok(route))
    reopened.auth.sign_out().unwrap() |> ignore
    assert_true(
      reopened.capture_provider_selection(None) is Err(error) &&
      error.has_prefix("AUTH_REQUIRED"),
    )
    assert_true(reopened.effective_provider_config().auth_mode == ChatGPT)
    let signed_out_metadata = NativeService::new(reopened, workspace, 0)
      .unwrap()
      .metadata()
    assert_eq(string_field(signed_out_metadata, "provider"), Some("ChatGPT"))
    assert_eq(
      string_field(signed_out_metadata, "model"),
      Some("モデル未選択"),
    )
    assert_true(reopened.validate_provider_selection(selected) is Err(_))
    reopened.invoke("session_create", { "id": "choice-signed-out" }).unwrap()
    |> ignore
    let (_, signed_out_effects) = reopened
      .invoke("session_send", {
        "session_id": "choice-signed-out",
        "prompt": "synthetic",
      })
      .unwrap()
    let signed_out_effect = native_effect_by_kind(
      signed_out_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    reopened.run_provider_effect(signed_out_effect).unwrap() |> ignore
    let (failed_session, _) = reopened
      .invoke("session_get", { "session_id": "choice-signed-out" })
      .unwrap()
    assert_eq(string_field(failed_session, "status"), Some("failed"))
    assert_true(failed_session.stringify().contains("AUTH_REQUIRED"))
    reopened.auth.use_configured_provider().unwrap() |> ignore
    assert_true(
      reopened.capture_provider_selection(None).unwrap().auth_mode() == ApiKey,
    )
    assert_true(reopened.validate_provider_selection(configured) is Err(_))
  }
}

///|
async test "legacy auth store preserves configured routing and demo refuses activation" {
  let fixture = @fs.tmpdir(prefix="dsh-provider-choice-legacy")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = NativeRuntime::open(fixture + "/data", workspace, false, true).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let legacy : Json = {
      "version": 1,
      "credential": Json::null(),
      "generation": "legacy",
      "selected_model": Json::null(),
      "model_identity": Json::null(),
      "models": [],
      "login_state": "signed_out",
    }
    runtime.auth.root
    .write_atomic_protected("siwc-auth.json", legacy.stringify())
    .unwrap()
    let loaded = native_auth_load(runtime.auth.root, runtime.auth.host_id).unwrap()
    assert_eq(loaded.provider_choice, "configured")
    assert_eq(loaded.route_generation, "")
    assert_true(
      runtime.select_chatgpt_model("gpt-test") is Err(error) &&
      error.has_prefix("DEMO_PROVIDER"),
    )
    assert_eq(
      runtime.capture_provider_selection(None).unwrap().model(),
      "offline-demo",
    )
  }
}
