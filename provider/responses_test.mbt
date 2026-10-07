///|
fn responses_value(result : Result[Json, String]) -> Json raise {
  match result {
    Ok(value) => value
    Err(message) => fail(message)
  }
}

///|
fn responses_field(value : Json, name : String) -> Json raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(value) => value
        None => fail("missing " + name)
      }
    _ => fail("expected object")
  }
}

///|
test "Responses request uses stateless streaming and safely maps engine tools" {
  let request : Json = {
    "system": "Use the workspace tools.",
    "messages": [
      { "role": "user", "content": "Inspect files" },
      {
        "role": "assistant",
        "content": "Checking",
        "tool_calls": [
          {
            "id": "call_a",
            "name": "read_file",
            "arguments": "{\"path\":\"README.md\"}",
          },
        ],
      },
      { "role": "tool", "tool_call_id": "call_a", "content": "# dsh" },
      { "role": "user", "content": "Report" },
    ],
    "tools": [
      {
        "name": "read_file",
        "description": "Read a text file",
        "input_schema": { "type": "object", "properties": {} },
      },
    ],
    "max_tokens": 8192,
    "temperature": 0.2,
    "reasoning_effort": "high",
  }
  let prepared = responses_value(
    @provider.prepare_responses("gpt-test", request),
  )
  assert_true(
    responses_field(prepared, "url") == "https://api.openai.com/v1/responses",
  )
  assert_true(responses_field(prepared, "path") == "/v1/responses")
  let body = responses_field(prepared, "body")
  assert_true(responses_field(body, "model") == "gpt-test")
  assert_true(responses_field(body, "store") == false)
  assert_true(responses_field(body, "stream") == true)
  assert_true(
    responses_field(body, "instructions") == "Use the workspace tools.",
  )
  let input = match responses_field(body, "input") {
    Array(values) => values
    _ => fail("input should be an array")
  }
  assert_true(input.length() == 6)
  assert_true(
    input[0] ==
    {
      "type": "additional_tools",
      "role": "developer",
      "tools": [
        {
          "type": "function",
          "name": "read_file",
          "description": "Read a text file",
          "parameters": { "type": "object", "properties": {} },
        },
      ],
    },
  )
  assert_true(
    input[3] ==
    {
      "type": "function_call",
      "call_id": "call_a",
      "name": "read_file",
      "arguments": "{\"path\":\"README.md\"}",
    },
  )
  assert_true(
    input[4] ==
    { "type": "function_call_output", "call_id": "call_a", "output": "# dsh" },
  )
  match body {
    Object(fields) =>
      for
        unsupported in [
          "background", "conversation", "max_output_tokens", "metadata", "temperature",
          "top_p", "truncation", "user", "previous_response_id",
        ] {
        assert_true(!fields.contains(unsupported))
      }
    _ => fail("expected request body")
  }
}

///|
test "Responses SSE decodes the complete fixture in one chunk" {
  let decoder = @provider.ResponsesStreamDecoder::new()
  assert_true(decoder.feed(responses_stream_fixture()) is Ok(_))
  let result = responses_value(decoder.finish())
  assert_true(responses_field(result, "content") == "Hello 🌙")
}

///|
test "Responses rejects malformed history and function arguments" {
  let malformed : Array[Json] = [
    { "system": "", "messages": [{ "role": "system", "content": "bad" }] },
    {
      "system": "",
      "messages": [
        {
          "role": "assistant",
          "content": "",
          "tool_calls": [{ "id": "c1", "name": "f", "arguments": "{}" }],
        },
      ],
    },
    {
      "system": "",
      "messages": [
        {
          "role": "assistant",
          "content": "",
          "tool_calls": [{ "id": "c1", "name": "f", "arguments": "[]" }],
        },
        { "role": "tool", "tool_call_id": "c1", "content": "done" },
      ],
    },
  ]
  for request in malformed {
    assert_true(@provider.prepare_responses("gpt-test", request) is Err(_))
  }
}

///|
test "Models decoder filters account visibility while preserving order" {
  let models = match
    @provider.decode_models({
      "models": [
        { "slug": "first", "display_name": "First", "visibility": "list" },
        { "slug": "hidden", "display_name": "Hidden", "visibility": "hidden" },
        { "slug": "last", "display_name": "Last", "visibility": "list" },
      ],
    }) {
    Ok(value) => value
    Err(message) => fail(message)
  }
  assert_true(
    models ==
    [
      { "slug": "first", "display_name": "First" },
      { "slug": "last", "display_name": "Last" },
    ],
  )
  assert_true(@provider.decode_models({ "data": [] }) is Err(_))
}

///|
test "Responses completion normalizes text tools and usage" {
  let result = responses_value(
    @provider.decode_responses({
      "id": "resp_1",
      "status": "completed",
      "error": Json::null(),
      "output": [
        {
          "type": "message",
          "role": "assistant",
          "content": [{ "type": "output_text", "text": "Hello" }],
        },
        {
          "type": "reasoning",
          "summary": [{ "type": "summary_text", "text": "Read" }],
        },
        {
          "type": "function_call",
          "call_id": "call_1",
          "name": "read_file",
          "arguments": "{\"path\":\"README.md\"}",
        },
      ],
      "usage": {
        "input_tokens": 5,
        "output_tokens": 3,
        "total_tokens": 8,
        "input_tokens_details": { "cached_tokens": 2 },
      },
    }),
  )
  assert_true(responses_field(result, "ok") == true)
  assert_true(responses_field(result, "content") == "Hello")
  assert_true(responses_field(result, "reasoning") == "Read")
  assert_true(responses_field(result, "finish_reason") == "tool_calls")
  assert_true(
    responses_field(result, "usage") ==
    {
      "input_tokens": 5,
      "output_tokens": 3,
      "total_tokens": 8,
      "cache_read_input_tokens": 2,
    },
  )
  assert_true(
    @provider.decode_responses({ "status": "incomplete", "output": [] })
    is Err(_),
  )
}

///|
test "Responses completed and non-streaming payloads accept a null error only" {
  let decoded = @provider.decode_responses({
    "id": "resp_null_error",
    "status": "completed",
    "error": Json::null(),
    "output": [
      {
        "type": "message",
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "Hello" }],
      },
    ],
  })
  assert_true(decoded is Ok(_))
  let rejected = @provider.decode_responses({
    "id": "resp_real_error",
    "status": "completed",
    "error": { "type": "invalid_request", "message": "rejected" },
    "output": [],
  })
  assert_true(rejected is Err(_))
}

///|
test "Responses preserves custom text tool calls across decode and request history" {
  let custom = @provider.decode_responses({
    "id": "resp_custom",
    "status": "completed",
    "output": [
      {
        "type": "custom_tool_call",
        "call_id": "custom_1",
        "name": "run_text",
        "input": "echo keep this as text",
      },
    ],
  })
  let completion = responses_value(custom)
  let calls = match responses_field(completion, "tool_calls") {
    Array(values) => values
    _ => fail("custom completion should contain tool calls")
  }
  assert_true(
    calls[0] ==
    {
      "id": "custom_1",
      "name": "run_text",
      "kind": "custom",
      "arguments": "echo keep this as text",
    },
  )

  let prepared = responses_value(
    @provider.prepare_responses("gpt-test", {
      "system": "",
      "messages": [
        { "role": "user", "content": "Run this" },
        {
          "role": "assistant",
          "content": "",
          "tool_calls": [
            {
              "id": "custom_1",
              "name": "run_text",
              "kind": "custom",
              "arguments": "echo keep this as text",
            },
          ],
        },
        {
          "role": "tool",
          "tool_call_id": "custom_1",
          "content": "Unsupported custom tool input",
          "is_error": true,
        },
      ],
    }),
  )
  let input = match
    responses_field(responses_field(prepared, "body"), "input") {
    Array(values) => values
    _ => fail("input should be an array")
  }
  assert_true(input.length() == 3)
  assert_true(
    input[1] ==
    {
      "type": "custom_tool_call",
      "call_id": "custom_1",
      "name": "run_text",
      "input": "echo keep this as text",
    },
  )
  assert_true(
    input[2] ==
    {
      "type": "custom_tool_call_output",
      "call_id": "custom_1",
      "output": "Unsupported custom tool input",
    },
  )
}

///|
fn responses_frame(kind : String, data : Json) -> String {
  "event: " + kind + "\r\ndata: " + data.stringify() + "\r\n\r\n"
}

///|
fn responses_stream_fixture() -> String {
  responses_frame("response.created", {
    "type": "response.created",
    "response": { "id": "resp_1", "status": "in_progress" },
  }) +
  responses_frame("response.output_item.added", {
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "msg_1",
      "type": "message",
      "role": "assistant",
      "content": [],
    },
  }) +
  responses_frame("response.output_text.delta", {
    "type": "response.output_text.delta",
    "item_id": "msg_1",
    "output_index": 0,
    "content_index": 0,
    "delta": "Hello 🌙",
  }) +
  responses_frame("response.output_item.added", {
    "type": "response.output_item.added",
    "output_index": 1,
    "item": {
      "id": "fc_1",
      "type": "function_call",
      "call_id": "call_1",
      "name": "read_file",
      "arguments": "",
    },
  }) +
  responses_frame("response.function_call_arguments.delta", {
    "type": "response.function_call_arguments.delta",
    "item_id": "fc_1",
    "output_index": 1,
    "delta": "{\"path\":\"README.md\"}",
  }) +
  responses_frame("response.function_call_arguments.done", {
    "type": "response.function_call_arguments.done",
    "item_id": "fc_1",
    "output_index": 1,
    "arguments": "{\"path\":\"README.md\"}",
  }) +
  responses_frame("response.output_item.done", {
    "type": "response.output_item.done",
    "output_index": 1,
    "item": {
      "id": "fc_1",
      "type": "function_call",
      "call_id": "call_1",
      "name": "read_file",
      "arguments": "{\"path\":\"README.md\"}",
    },
  }) +
  responses_frame("response.completed", {
    "type": "response.completed",
    "response": {
      "id": "resp_1",
      "status": "completed",
      "error": Json::null(),
      "output": [
        {
          "type": "message",
          "role": "assistant",
          "content": [{ "type": "output_text", "text": "Hello 🌙" }],
        },
        {
          "type": "function_call",
          "call_id": "call_1",
          "name": "read_file",
          "arguments": "{\"path\":\"README.md\"}",
        },
      ],
      "usage": { "input_tokens": 5, "output_tokens": 2, "total_tokens": 7 },
    },
  })
}

///|
fn responses_text_stream_fixture(text : String) -> String {
  responses_frame("response.created", {
    "type": "response.created",
    "response": { "id": "resp_qc", "status": "in_progress" },
  }) +
  responses_frame("response.output_item.added", {
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "msg_qc",
      "type": "message",
      "role": "assistant",
      "content": [],
    },
  }) +
  responses_frame("response.output_text.delta", {
    "type": "response.output_text.delta",
    "item_id": "msg_qc",
    "output_index": 0,
    "content_index": 0,
    "delta": text,
  }) +
  responses_frame("response.completed", {
    "type": "response.completed",
    "response": {
      "id": "resp_qc",
      "status": "completed",
      "output": [
        {
          "type": "message",
          "role": "assistant",
          "content": [{ "type": "output_text", "text": text }],
        },
      ],
      "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
    },
  })
}

///|
fn split_at_character(value : String, offset : Int) -> (String, String) {
  let before = StringBuilder()
  let after = StringBuilder()
  let mut index = 0
  for character in value {
    if index < offset {
      before.write_char(character)
    } else {
      after.write_char(character)
    }
    index += 1
  }
  (before.to_string(), after.to_string())
}

///|
test "Responses SSE is invariant to every two-chunk split including UTF-8 characters" {
  let wire = responses_stream_fixture()
  let mut characters = 0
  for _ in wire {
    characters += 1
  }
  for split = 0; split <= characters; split = split + 1 {
    let (first, second) = split_at_character(wire, split)
    let decoder = @provider.ResponsesStreamDecoder::new()
    assert_true(decoder.feed(first) is Ok(_))
    match decoder.feed(second) {
      Ok(_) => ()
      Err(error) => fail("split " + split.to_string() + ": " + error)
    }
    let result = responses_value(decoder.finish())
    assert_true(responses_field(result, "content") == "Hello 🌙")
    assert_true(responses_field(result, "finish_reason") == "tool_calls")
  }
}

///|
test "QuickCheck verifies arbitrary Unicode text over every decoded-string SSE split" {
  @quickcheck.check(
    (sample : String) => {
      // Keep a nonempty answer while exercising generated Unicode, escaping,
      // and embedded line breaks from the pinned official QuickCheck generator.
      let text = "🌙" + sample + "✓"
      let wire = responses_text_stream_fixture(text)
      let mut character_count = 0
      for _ in wire {
        character_count += 1
      }
      let mut valid = true
      for split = 0; split <= character_count && valid; split = split + 1 {
        let (first, second) = split_at_character(wire, split)
        let decoder = @provider.ResponsesStreamDecoder::new()
        if decoder.feed(first) is Err(_) || decoder.feed(second) is Err(_) {
          valid = false
        } else {
          match decoder.finish() {
            Ok(Object(fields)) =>
              valid = fields.get("content") == Some(text.to_json())
            _ => valid = false
          }
        }
      }
      valid
    },
    count=40U,
    max_size=64U,
    seed=20261007,
  )
}

///|
test "Responses SSE does not treat EOF or incomplete as success and reports terminal failure" {
  let bare = @provider.ResponsesStreamDecoder::new()
  assert_true(
    bare.feed(
      responses_frame("response.created", {
        "type": "response.created",
        "response": { "id": "resp_1", "status": "in_progress" },
      }),
    )
    is Ok(_),
  )
  assert_true(bare.finish() is Err(_))

  let incomplete = @provider.ResponsesStreamDecoder::new()
  assert_true(
    incomplete.feed(
      responses_frame("response.incomplete", {
        "type": "response.incomplete",
        "response": {
          "id": "resp_1",
          "incomplete_details": { "reason": "max_output_tokens" },
        },
      }),
    )
    is Ok(_),
  )
  assert_true(incomplete.finish() is Err(_))

  let failed = @provider.ResponsesStreamDecoder::new()
  assert_true(
    failed.feed(
      responses_frame("response.failed", {
        "type": "response.failed",
        "response": {
          "id": "resp_1",
          "error": { "code": "rate_limit_exceeded", "message": "try later" },
        },
      }),
    )
    is Ok(_),
  )
  assert_true(failed.finish() is Err(_))
}

///|
test "Responses reports typed terminal events and rejects unknown capabilities" {
  let completed = @provider.ResponsesStreamDecoder::new()
  assert_true(completed.feed(responses_stream_fixture()) is Ok(_))
  let completed_events = completed.take_events()
  let mut saw_completed = false
  for event in completed_events {
    match event {
      @provider.ResponsesEvent::Completed => saw_completed = true
      _ => ()
    }
  }
  assert_true(saw_completed)

  let failed = @provider.ResponsesStreamDecoder::new()
  assert_true(
    failed.feed(
      responses_frame("response.failed", {
        "type": "response.failed",
        "response": {
          "id": "resp_failed",
          "error": { "code": "rate_limit_exceeded", "message": "try later" },
        },
      }),
    )
    is Ok(_),
  )
  let failed_events = failed.take_events()
  let mut saw_failed = false
  for event in failed_events {
    match event {
      @provider.ResponsesEvent::Failed(
        "rate_limit_exceeded",
        "try later",
        Some("resp_failed")
      ) => saw_failed = true
      _ => ()
    }
  }
  assert_true(saw_failed)

  let unknown = @provider.ResponsesStreamDecoder::new()
  match
    unknown.feed(
      responses_frame("response.vendor_extension", {
        "type": "response.vendor_extension",
      }),
    ) {
    Err(error) => assert_true(error.has_prefix("UNSUPPORTED_EVENT:"))
    Ok(_) => fail("unknown Responses event was ignored")
  }

  let custom = @provider.ResponsesStreamDecoder::new()
  assert_true(
    custom.feed(
      responses_frame("response.created", {
        "type": "response.created",
        "response": { "id": "resp_custom", "status": "in_progress" },
      }),
    )
    is Ok(_),
  )
  match
    custom.feed(
      responses_frame("response.output_item.added", {
        "type": "response.output_item.added",
        "output_index": 0,
        "item": { "id": "custom_1", "type": "custom_unknown_tool_call" },
      }),
    ) {
    Err(error) => assert_true(error.has_prefix("UNSUPPORTED_CONTENT:"))
    Ok(_) => fail("unsupported custom tool item was ignored")
  }

  let queued = @provider.ResponsesStreamDecoder::new()
  match
    queued.feed(
      responses_frame("response.queued", { "type": "response.queued" }),
    ) {
    Err(error) => assert_true(error.has_prefix("UNSUPPORTED_CAPABILITY:"))
    Ok(_) => fail("queued/background response was accepted")
  }
}

///|
test "Responses validates custom tool input delta and terminal lifecycle" {
  let decoder = @provider.ResponsesStreamDecoder::new()
  let wire = responses_frame("response.created", {
      "type": "response.created",
      "response": { "id": "resp_custom_stream", "status": "in_progress" },
    }) +
    responses_frame("response.output_item.added", {
      "type": "response.output_item.added",
      "output_index": 0,
      "item": {
        "id": "custom_item",
        "type": "custom_tool_call",
        "call_id": "custom_1",
        "name": "run_text",
        "input": "",
      },
    }) +
    responses_frame("response.custom_tool_call_input.delta", {
      "type": "response.custom_tool_call_input.delta",
      "item_id": "custom_item",
      "output_index": 0,
      "sequence_number": 2,
      "delta": "echo ",
    }) +
    responses_frame("response.custom_tool_call_input.delta", {
      "type": "response.custom_tool_call_input.delta",
      "item_id": "custom_item",
      "output_index": 0,
      "sequence_number": 3,
      "delta": "hello",
    }) +
    responses_frame("response.custom_tool_call_input.done", {
      "type": "response.custom_tool_call_input.done",
      "item_id": "custom_item",
      "output_index": 0,
      "sequence_number": 4,
      "input": "echo hello",
    }) +
    responses_frame("response.output_item.done", {
      "type": "response.output_item.done",
      "output_index": 0,
      "item": {
        "id": "custom_item",
        "type": "custom_tool_call",
        "call_id": "custom_1",
        "name": "run_text",
        "input": "echo hello",
      },
    }) +
    responses_frame("response.completed", {
      "type": "response.completed",
      "response": {
        "id": "resp_custom_stream",
        "status": "completed",
        "output": [
          {
            "type": "custom_tool_call",
            "call_id": "custom_1",
            "name": "run_text",
            "input": "echo hello",
          },
        ],
      },
    })
  assert_true(decoder.feed(wire) is Ok(_))
  let events = decoder.take_events()
  let mut saw_started = false
  let mut saw_done = false
  for event in events {
    match event {
      @provider.ResponsesEvent::CustomToolCallStarted(
        "custom_item",
        "custom_1",
        "run_text"
      ) => saw_started = true
      @provider.ResponsesEvent::CustomToolInputDone(
        "custom_1",
        "run_text",
        "echo hello"
      ) => saw_done = true
      _ => ()
    }
  }
  assert_true(saw_started && saw_done)
  let completion = responses_value(decoder.finish())
  assert_true(responses_field(completion, "finish_reason") == "tool_calls")
  let calls = match responses_field(completion, "tool_calls") {
    Array(values) => values
    _ => fail("custom stream should contain a tool call")
  }
  assert_true(responses_field(calls[0], "kind") == "custom")
  assert_true(responses_field(calls[0], "arguments") == "echo hello")
}
