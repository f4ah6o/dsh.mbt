///|
test "native workspace metadata identifies providers without endpoint secrets" {
  let custom = {
    protocol: NativeProtocol::OpenAIChatCompletions,
    auth_mode: NativeAuthMode::ApiKey,
    model: "gpt-5.1-codex",
    base_url: Some(
      "https://user:private@provider.example:8443/v1?api_key=sk-test-secret",
    ),
    generation: "fixture",
    demo_provider: false,
  }
  let custom_label = service_provider_label(custom)
  assert_eq(custom_label, "provider.example")
  assert_true(!custom_label.contains("private"))
  assert_true(!custom_label.contains("8443"))
  assert_true(!custom_label.contains("api_key"))
  assert_true(!custom_label.contains("sk-test-secret"))
  assert_eq(service_model_display_name(custom.model), "gpt-5.1-codex")
  assert_eq(
    service_model_display_name("sk-test-secret"),
    "カスタムモデル",
  )
}

///|
test "native workspace metadata names known providers and hides secret-like hosts" {
  let deepseek = {
    protocol: NativeProtocol::DeepSeekMessages,
    auth_mode: NativeAuthMode::ApiKey,
    model: "deepseek-flash",
    base_url: Some("https://api.deepseek.com/anthropic"),
    generation: "fixture",
    demo_provider: false,
  }
  assert_eq(service_provider_label(deepseek), "DeepSeek")
  assert_eq(
    service_provider_label({ ..deepseek, demo_provider: true, }),
    "デモ",
  )

  let secret_host = {
    ..deepseek,
    protocol: NativeProtocol::OpenAIChatCompletions,
    base_url: Some("https://sk-live-secret-value.example/v1"),
  }
  let label = service_provider_label(secret_host)
  assert_eq(label, "OpenAI 互換 API")
  assert_true(!label.contains("sk-live-secret-value"))

  let chatgpt = { ..deepseek, auth_mode: NativeAuthMode::ChatGPT, }
  assert_eq(service_provider_label(chatgpt), "ChatGPT")
}

///|
async test "native repository metadata resolves nested worktree git directories" {
  let fixture = @fs.tmpdir(prefix="dsh-native-metadata-git")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let repository = fixture + "/original-repository"
    let worktree = fixture + "/sample-worktree"
    let nested_workspace = worktree + "/nested/workspace"
    @fs.mkdir(repository)
    @fs.mkdir(repository + "/.git")
    @fs.mkdir(worktree)
    @fs.mkdir(worktree + "/nested")
    @fs.mkdir(nested_workspace)

    let common_path = native_resolved_git_common_dir(
      nested_workspace, "../../../original-repository/.git",
    )
    let resolved_repository = @fs.realpath(repository) catch {
      _ => fail("fixture repository must resolve")
    }
    assert_eq(common_path, resolved_repository + "/.git")
    assert_eq(
      native_repository_name(worktree, common_path),
      "original-repository",
    )

    let separate_git_dir = fixture + "/git-storage"
    @fs.mkdir(separate_git_dir)
    assert_eq(
      native_repository_name(worktree, separate_git_dir),
      "sample-worktree",
    )
  }
}
