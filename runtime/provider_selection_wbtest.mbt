///|
test "native API-key provider selection is explicit and secret-free" {
  let deepseek = NativeProviderSelection::api_key(
    NativeProtocol::DeepSeekMessages,
    "deepseek-flash",
    None,
    "config-1",
  )
  assert_true(deepseek is Ok(_))
  match deepseek {
    Ok(selection) => {
      assert_true(selection.protocol() == NativeProtocol::DeepSeekMessages)
      assert_true(selection.auth_mode() == NativeAuthMode::ApiKey)
      assert_eq(selection.base_url(), "https://api.deepseek.com/anthropic")
      assert_eq(selection.generation(), "config-1")
    }
    Err(_) => ()
  }
  let openai = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "gpt-test",
    Some("https://example.test/v1"),
    "config-2",
  )
  assert_true(openai is Ok(_))
  let responses = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIResponses,
    "gpt-test",
    Some("https://example.test/v1"),
    "config-3",
  )
  assert_true(responses is Ok(_))
}

///|
test "native provider selection rejects unsafe API roots and missing model" {
  let cleartext_public = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "gpt-test",
    Some("http://provider.example"),
    "config",
  )
  assert_true(cleartext_public is Err(_))
  let credentials = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "gpt-test",
    Some("https://user:pass@provider.example"),
    "config",
  )
  assert_true(credentials is Err(_))
  let query = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "gpt-test",
    Some("https://provider.example?key=secret"),
    "config",
  )
  assert_true(query is Err(_))
  let model_missing = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "",
    None,
    "config",
  )
  assert_true(model_missing is Err(_))
  let local_http = NativeProviderSelection::api_key(
    NativeProtocol::OpenAIChatCompletions,
    "gpt-test",
    Some("http://127.0.0.1:43127/v1"),
    "config",
  )
  assert_true(local_http is Ok(_))
}
