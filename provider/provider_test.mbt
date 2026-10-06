///|
fn value(result : Result[Json, String]) -> Json raise {
  match result {
    Ok(value) => value
    Err(message) => fail(message)
  }
}

///|
fn at(value : Json, name : String) -> Json raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(value) => value
        None => fail("missing " + name)
      }
    _ => fail("expected an object")
  }
}

///|
fn transcript() -> Json {
  {
    "system": "Use the workspace tools.",
    "messages": [
      { "role": "user", "content": "Inspect files" },
      {
        "role": "assistant",
        "content": "Checking",
        "reasoning": "Read before editing",
        "tool_calls": [
          {
            "id": "call_a",
            "name": "read_file",
            "arguments": "{\"path\":\"README.md\"}",
          },
          {
            "id": "call_b",
            "name": "read_file",
            "arguments": "{\"path\":\"missing.txt\"}",
          },
        ],
      },
      { "role": "tool", "tool_call_id": "call_a", "content": "# project" },
      {
        "role": "tool",
        "tool_call_id": "call_b",
        "content": "File not found",
        "is_error": true,
      },
      { "role": "user", "content": "Report what you found" },
    ],
    "tools": [
      {
        "name": "read_file",
        "description": "Read a text file",
        "input_schema": {
          "type": "object",
          "properties": { "path": { "type": "string" } },
          "required": ["path"],
        },
        "effect": "read",
      },
    ],
    "stream": false,
    "max_tokens": 512,
    "reasoning_effort": "off",
  }
}

///|
test "Messages request groups parallel tool results before user text and strips local effects" {
  let prepared = value(
    @provider.prepare("deepseek", "deepseek-test", transcript()),
  )
  let expected : Json = {
    "path": "/v1/messages",
    "headers": {
      "content-type": "application/json",
      "accept": "application/json",
      "anthropic-version": "2023-06-01",
    },
    "body": {
      "model": "deepseek-test",
      "stream": false,
      "max_tokens": 512,
      "system": "Use the workspace tools.",
      "thinking": { "type": "disabled" },
      "messages": [
        {
          "role": "user",
          "content": [{ "type": "text", "text": "Inspect files" }],
        },
        {
          "role": "assistant",
          "content": [
            { "type": "thinking", "thinking": "Read before editing" },
            { "type": "text", "text": "Checking" },
            {
              "type": "tool_use",
              "id": "call_a",
              "name": "read_file",
              "input": { "path": "README.md" },
            },
            {
              "type": "tool_use",
              "id": "call_b",
              "name": "read_file",
              "input": { "path": "missing.txt" },
            },
          ],
        },
        {
          "role": "user",
          "content": [
            {
              "type": "tool_result",
              "tool_use_id": "call_a",
              "content": [{ "type": "text", "text": "# project" }],
            },
            {
              "type": "tool_result",
              "tool_use_id": "call_b",
              "content": [{ "type": "text", "text": "File not found" }],
              "is_error": true,
            },
            { "type": "text", "text": "Report what you found" },
          ],
        },
      ],
      "tools": [
        {
          "name": "read_file",
          "description": "Read a text file",
          "input_schema": {
            "type": "object",
            "properties": { "path": { "type": "string" } },
            "required": ["path"],
          },
        },
      ],
    },
  }
  assert_true(prepared == expected)
}

///|
test "Chat Completions preserves correlated tool messages and reasoning replay" {
  let prepared = value(@provider.prepare("openai", "chat-test", transcript()))
  assert_true(at(prepared, "path") == "/v1/chat/completions")
  let body = at(prepared, "body")
  let expected : Json = [
    { "role": "system", "content": "Use the workspace tools." },
    { "role": "user", "content": "Inspect files" },
    {
      "role": "assistant",
      "content": "Checking",
      "reasoning_content": "Read before editing",
      "tool_calls": [
        {
          "type": "function",
          "id": "call_a",
          "function": {
            "name": "read_file",
            "arguments": "{\"path\":\"README.md\"}",
          },
        },
        {
          "type": "function",
          "id": "call_b",
          "function": {
            "name": "read_file",
            "arguments": "{\"path\":\"missing.txt\"}",
          },
        },
      ],
    },
    { "role": "tool", "tool_call_id": "call_a", "content": "# project" },
    { "role": "tool", "tool_call_id": "call_b", "content": "File not found" },
    { "role": "user", "content": "Report what you found" },
  ]
  assert_true(at(body, "messages") == expected)
  assert_true(
    at(body, "tools") ==
    [
      {
        "type": "function",
        "function": {
          "name": "read_file",
          "description": "Read a text file",
          "parameters": {
            "type": "object",
            "properties": { "path": { "type": "string" } },
            "required": ["path"],
          },
        },
      },
    ],
  )
  assert_true(
    at(prepared, "headers") ==
    { "content-type": "application/json", "accept": "application/json" },
  )
}

///|
test "provider defaults prepare streaming and high effort without credentials" {
  let request : Json = {
    "system": "",
    "messages": [{ "role": "user", "content": "Hello" }],
    "tools": [],
  }
  let prepared = value(@provider.prepare("deepseek", "test", request))
  let body = at(prepared, "body")
  assert_true(at(body, "stream") == true)
  assert_true(at(body, "max_tokens") == 4096)
  assert_true(at(body, "thinking") == { "type": "enabled" })
  assert_true(at(body, "output_config") == { "effort": "high" })
  assert_true(
    at(prepared, "headers") ==
    {
      "content-type": "application/json",
      "accept": "text/event-stream",
      "anthropic-version": "2023-06-01",
    },
  )
  let openai_body = at(
    value(@provider.prepare("openai", "test", request)),
    "body",
  )
  assert_true(at(openai_body, "stream_options") == { "include_usage": true })
}

///|
test "request rejects unresolved and mismatched tool histories before HTTP" {
  let histories : Array[Json] = [
    [{ "role": "tool", "content": "result", "tool_call_id": "unknown" }],
    [
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [{ "id": "a", "name": "read_file", "arguments": "{}" }],
      },
    ],
    [
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [{ "id": "a", "name": "read_file", "arguments": "{}" }],
      },
      { "role": "user", "content": "continue" },
    ],
    [
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          { "id": "a", "name": "read_file", "arguments": "{}" },
          { "id": "a", "name": "read_file", "arguments": "{}" },
        ],
      },
      { "role": "tool", "content": "x", "tool_call_id": "a" },
    ],
    [
      {
        "role": "user",
        "content": "x",
        "tool_calls": [{ "id": "a", "name": "read_file", "arguments": "{}" }],
      },
    ],
  ]
  for mode in ["deepseek", "openai"] {
    for history in histories {
      assert_true(
        @provider.prepare(mode, "test", { "messages": history }) is Err(_),
      )
    }
  }
}

///|
test "rejected historical arguments remain replayable for model self-correction" {
  for arguments in ["{", "[]", "null", "true", "\"value\""] {
    let request : Json = {
      "messages": [
        { "role": "user", "content": "Read the file" },
        {
          "role": "assistant",
          "content": "",
          "tool_calls": [
            { "id": "a", "name": "read_file", "arguments": arguments.to_json() },
          ],
        },
        {
          "role": "tool",
          "content": "Invalid tool arguments",
          "tool_call_id": "a",
          "is_error": true,
        },
      ],
    }
    let before = request.stringify()
    let deepseek = at(
      value(@provider.prepare("deepseek", "test", request)),
      "body",
    )
    match at(deepseek, "messages") {
      Array(messages) => {
        assert_true(
          at(messages[1], "content") ==
          [
            {
              "type": "tool_use",
              "id": "a",
              "name": "read_file",
              "input": Json::empty_object(),
            },
          ],
        )
        assert_true(
          at(messages[2], "content") ==
          [
            {
              "type": "tool_result",
              "tool_use_id": "a",
              "content": [{ "type": "text", "text": "Invalid tool arguments" }],
              "is_error": true,
            },
          ],
        )
      }
      _ => fail("expected Messages history")
    }
    let openai = at(value(@provider.prepare("openai", "test", request)), "body")
    match at(openai, "messages") {
      Array(messages) =>
        assert_true(
          at(messages[1], "tool_calls") ==
          [
            {
              "id": "a",
              "type": "function",
              "function": {
                "name": "read_file",
                "arguments": arguments.to_json(),
              },
            },
          ],
        )
      _ => fail("expected Chat Completions history")
    }
    assert_true(request.stringify() == before)
  }
}

///|
test "invalid options and tool declarations fail before HTTP" {
  let request : Json = { "messages": [{ "role": "user", "content": "x" }] }
  assert_true(@provider.prepare("unknown", "test", request) is Err(_))
  assert_true(@provider.prepare("deepseek", "", request) is Err(_))
  for
    invalid in [
      Json::null(),
      { "messages": [] },
      { "messages": [{ "role": "developer", "content": "x" }] },
      { "messages": [{ "role": "user", "content": "x" }], "max_tokens": 0 },
      { "messages": [{ "role": "user", "content": "x" }], "max_tokens": 1.5 },
      { "messages": [{ "role": "user", "content": "x" }], "stream": "yes" },
      {
        "messages": [{ "role": "user", "content": "x" }],
        "reasoning_effort": "huge",
      },
      {
        "messages": [{ "role": "user", "content": "x" }],
        "tools": [{ "name": "bad", "description": "x", "input_schema": [] }],
      },
      {
        "messages": [{ "role": "user", "content": "x" }],
        "tools": [
          {
            "name": "a",
            "description": "x",
            "input_schema": { "type": "object" },
          },
          {
            "name": "a",
            "description": "y",
            "input_schema": { "type": "object" },
          },
        ],
      },
    ] {
    assert_true(@provider.prepare("deepseek", "test", invalid) is Err(_))
  }
}

///|
test "Messages JSON response preserves text reasoning calls and cumulative usage" {
  let response : Json = {
    "type": "message",
    "role": "assistant",
    "stop_reason": "tool_use",
    "content": [
      { "type": "thinking", "thinking": "Inspect the file" },
      { "type": "text", "text": "Reading it" },
      {
        "type": "tool_use",
        "id": "call_1",
        "name": "read_file",
        "input": { "path": "README.md" },
      },
    ],
    "usage": {
      "input_tokens": 10,
      "output_tokens": 20,
      "cache_read_input_tokens": 4,
    },
  }
  let expected : Json = {
    "ok": true,
    "content": "Reading it",
    "reasoning": "Inspect the file",
    "tool_calls": [
      {
        "id": "call_1",
        "name": "read_file",
        "arguments": "{\"path\":\"README.md\"}",
      },
    ],
    "finish_reason": "tool_calls",
    "usage": {
      "input_tokens": 10,
      "output_tokens": 20,
      "cache_read_input_tokens": 4,
    },
  }
  assert_true(value(@provider.decode("deepseek", response)) == expected)
}

///|
test "Chat Completions normalizes function calls and cache usage" {
  let response : Json = {
    "choices": [
      {
        "index": 0,
        "finish_reason": "tool_calls",
        "message": {
          "role": "assistant",
          "content": null,
          "reasoning_content": "Need evidence",
          "tool_calls": [
            {
              "type": "function",
              "id": "id1",
              "function": {
                "name": "read_file",
                "arguments": "{\"path\":\"x\"}",
              },
            },
          ],
        },
      },
    ],
    "usage": {
      "prompt_tokens": 20,
      "completion_tokens": 5,
      "total_tokens": 25,
      "prompt_tokens_details": { "cached_tokens": 7 },
    },
  }
  let expected : Json = {
    "ok": true,
    "content": "",
    "reasoning": "Need evidence",
    "finish_reason": "tool_calls",
    "tool_calls": [
      { "id": "id1", "name": "read_file", "arguments": "{\"path\":\"x\"}" },
    ],
    "usage": {
      "input_tokens": 20,
      "output_tokens": 5,
      "total_tokens": 25,
      "cache_read_input_tokens": 7,
    },
  }
  assert_true(value(@provider.decode("openai", response)) == expected)
}

///|
test "wire errors refusals empty responses and unsafe calls are not successes" {
  for
    response in [
      Json::null(),
      { "error": { "type": "rate_limit_error", "message": "retry later" } },
      { "choices": [] },
      {
        "choices": [
          {
            "finish_reason": "stop",
            "message": { "role": "assistant", "content": "" },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "stop",
            "message": {
              "role": "assistant",
              "content": "",
              "refusal": "Cannot comply",
            },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "stop",
            "message": {
              "role": "assistant",
              "content": "x",
              "function_call": { "name": "read_file", "arguments": "{}" },
            },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "content_filter",
            "message": { "role": "assistant", "content": "partial" },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "tool_calls",
            "message": { "role": "assistant", "content": "x", "tool_calls": [] },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "tool_calls",
            "message": {
              "role": "assistant",
              "content": "",
              "tool_calls": [
                {
                  "id": "a",
                  "type": "function",
                  "function": { "name": "read_file", "arguments": "[]" },
                },
              ],
            },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "stop",
            "message": {
              "role": "assistant",
              "content": "x",
              "tool_calls": [
                {
                  "id": "a",
                  "type": "function",
                  "function": { "name": "read_file", "arguments": "{}" },
                },
              ],
            },
          },
        ],
      },
      {
        "choices": [
          {
            "finish_reason": "stop",
            "message": { "role": "assistant", "content": "x" },
          },
        ],
        "usage": { "completion_tokens": -1 },
      },
    ] {
    assert_true(@provider.decode("openai", response) is Err(_))
  }
  assert_true(
    @provider.decode("deepseek", {
      "type": "message",
      "role": "assistant",
      "stop_reason": "end_turn",
      "content": [{ "type": "image", "data": "unsupported" }],
    })
    is Err(_),
  )
}

///|
test "length-limited responses never expose executable tools" {
  let openai : Json = {
    "choices": [
      {
        "finish_reason": "length",
        "message": {
          "role": "assistant",
          "content": "Partial",
          "tool_calls": [
            {
              "type": "function",
              "id": "a",
              "function": { "name": "write_file", "arguments": "{\"path\":" },
            },
          ],
        },
      },
    ],
  }
  let deepseek : Json = {
    "type": "message",
    "role": "assistant",
    "stop_reason": "max_tokens",
    "content": [
      { "type": "text", "text": "Partial" },
      {
        "type": "tool_use",
        "id": "a",
        "name": "write_file",
        "input": { "path": "x" },
      },
    ],
  }
  let expected : Json = {
    "ok": true,
    "content": "Partial",
    "tool_calls": [],
    "finish_reason": "length",
  }
  assert_true(value(@provider.decode("openai", openai)) == expected)
  assert_true(value(@provider.decode("deepseek", deepseek)) == expected)
}
