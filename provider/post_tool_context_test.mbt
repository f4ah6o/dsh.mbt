///|
fn post_tool_context_request() -> Json {
  {
    "messages": [
      { "role": "user", "content": "Read both files" },
      {
        "role": "assistant",
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
      },
      { "role": "tool", "tool_call_id": "read-a", "content": "alpha" },
      { "role": "tool", "tool_call_id": "read-b", "content": "beta" },
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "context a" },
          { "type": "text", "text": "context a second hook" },
        ],
        "source": { "kind": "hooks-claude-code" },
      },
      {
        "role": "user",
        "content": [{ "type": "text", "text": "context b" }],
        "source": { "kind": "hooks-claude-code" },
      },
    ],
    "stream": false,
  }
}

///|
fn post_tool_context_field(value : Json, key : String) -> Json raise {
  match value {
    Json::Object(fields) =>
      match fields.get(key) {
        Some(value) => value
        None => fail("missing " + key)
      }
    _ => fail("expected object")
  }
}

///|
fn post_tool_context_array(value : Json) -> Array[Json] raise {
  match value {
    Json::Array(values) => values
    _ => fail("expected array")
  }
}

///|
test "PostToolUse context messages follow every correlated result in each provider adapter" {
  let openai = match
    @provider.prepare("openai", "fixture", post_tool_context_request()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let openai_messages = post_tool_context_array(
    post_tool_context_field(post_tool_context_field(openai, "body"), "messages"),
  )
  assert_eq(openai_messages.length(), 6)
  assert_eq(
    post_tool_context_field(openai_messages[2], "role"),
    "tool".to_json(),
  )
  assert_eq(
    post_tool_context_field(openai_messages[2], "tool_call_id"),
    "read-a".to_json(),
  )
  assert_eq(
    post_tool_context_field(openai_messages[3], "role"),
    "tool".to_json(),
  )
  assert_eq(
    post_tool_context_field(openai_messages[3], "tool_call_id"),
    "read-b".to_json(),
  )
  assert_eq(
    post_tool_context_array(
      post_tool_context_field(openai_messages[4], "content"),
    ).length(),
    2,
  )
  assert_eq(
    post_tool_context_field(
      post_tool_context_array(
        post_tool_context_field(openai_messages[4], "content"),
      )[1],
      "text",
    ),
    "context a second hook".to_json(),
  )
  assert_eq(
    post_tool_context_field(
      post_tool_context_array(
        post_tool_context_field(openai_messages[5], "content"),
      )[0],
      "text",
    ),
    "context b".to_json(),
  )

  let deepseek = match
    @provider.prepare("deepseek", "fixture", post_tool_context_request()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let deepseek_messages = post_tool_context_array(
    post_tool_context_field(
      post_tool_context_field(deepseek, "body"),
      "messages",
    ),
  )
  assert_eq(deepseek_messages.length(), 3)
  let deepseek_tool_turn = post_tool_context_array(
    post_tool_context_field(deepseek_messages[2], "content"),
  )
  assert_eq(deepseek_tool_turn.length(), 5)
  assert_eq(
    post_tool_context_field(deepseek_tool_turn[0], "tool_use_id"),
    "read-a".to_json(),
  )
  assert_eq(
    post_tool_context_field(deepseek_tool_turn[1], "tool_use_id"),
    "read-b".to_json(),
  )
  assert_eq(
    post_tool_context_field(deepseek_tool_turn[2], "text"),
    "context a".to_json(),
  )
  assert_eq(
    post_tool_context_field(deepseek_tool_turn[3], "text"),
    "context a second hook".to_json(),
  )
  assert_eq(
    post_tool_context_field(deepseek_tool_turn[4], "text"),
    "context b".to_json(),
  )

  let responses = match
    @provider.prepare_responses("fixture", post_tool_context_request()) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let responses_input = post_tool_context_array(
    post_tool_context_field(post_tool_context_field(responses, "body"), "input"),
  )
  assert_eq(responses_input.length(), 7)
  assert_eq(
    post_tool_context_field(responses_input[3], "type"),
    "function_call_output".to_json(),
  )
  assert_eq(
    post_tool_context_field(responses_input[3], "call_id"),
    "read-a".to_json(),
  )
  assert_eq(
    post_tool_context_field(responses_input[4], "call_id"),
    "read-b".to_json(),
  )
  assert_eq(
    post_tool_context_field(responses_input[5], "role"),
    "user".to_json(),
  )
  let response_context = post_tool_context_array(
    post_tool_context_field(responses_input[5], "content"),
  )
  assert_eq(response_context.length(), 2)
  assert_eq(
    post_tool_context_field(response_context[0], "type"),
    "input_text".to_json(),
  )
  assert_eq(
    post_tool_context_field(response_context[1], "text"),
    "context a second hook".to_json(),
  )
  assert_eq(
    post_tool_context_field(
      post_tool_context_array(
        post_tool_context_field(responses_input[6], "content"),
      )[0],
      "text",
    ),
    "context b".to_json(),
  )
}

///|
test "provider context content accepts only nonempty text-block arrays" {
  let request : Json = {
    "messages": [
      { "role": "user", "content": [{ "type": "image", "url": "data:" }] },
    ],
  }
  assert_true(@provider.prepare("openai", "fixture", request) is Err(_))
  assert_true(@provider.prepare("deepseek", "fixture", request) is Err(_))
  assert_true(@provider.prepare_responses("fixture", request) is Err(_))

  let unmarked_user : Json = {
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "context" }] },
    ],
  }
  assert_true(@provider.prepare("openai", "fixture", unmarked_user) is Err(_))
  assert_true(@provider.prepare_responses("fixture", unmarked_user) is Err(_))

  let assistant_blocks : Json = {
    "messages": [
      {
        "role": "assistant",
        "content": [{ "type": "text", "text": "context" }],
        "source": { "kind": "hooks-claude-code" },
      },
    ],
  }
  assert_true(
    @provider.prepare("openai", "fixture", assistant_blocks) is Err(_),
  )
  assert_true(
    @provider.prepare("deepseek", "fixture", assistant_blocks) is Err(_),
  )
  assert_true(
    @provider.prepare_responses("fixture", assistant_blocks) is Err(_),
  )
}
