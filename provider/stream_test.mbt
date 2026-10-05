///|
fn frame(event : String, payload : Json) -> String {
  (if event.is_empty() { "" } else { "event: " + event + "\r\n" }) +
  "data: " +
  payload.stringify() +
  "\r\n\r\n"
}

///|
fn openai_frame(delta : Json, reason : Json) -> String {
  frame("", {
    "choices": [{ "index": 0, "delta": delta, "finish_reason": reason }],
  })
}

///|
fn openai_stream() -> String {
  ": heartbeat\r\n\r\n" +
  openai_frame({ "role": "assistant", "reasoning_content": "Read first" }, null) +
  openai_frame(
    {
      "content": "確認",
      "tool_calls": [
        {
          "index": 0,
          "id": "call_",
          "type": "function",
          "function": { "name": "read_", "arguments": "{\"path\":" },
        },
      ],
    },
    null,
  ) +
  openai_frame(
    {
      "content": "します",
      "tool_calls": [
        {
          "index": 0,
          "id": "one",
          "function": { "name": "file", "arguments": "\"README.md\"}" },
        },
      ],
    },
    null,
  ) +
  openai_frame(Json::empty_object(), "tool_calls") +
  frame("", {
    "choices": [],
    "usage": { "prompt_tokens": 10, "completion_tokens": 4, "total_tokens": 14 },
  }) +
  "data: [DONE]\r\n\r\n"
}

///|
fn openai_expected() -> Json {
  {
    "ok": true,
    "content": "確認します",
    "reasoning": "Read first",
    "tool_calls": [
      {
        "id": "call_one",
        "name": "read_file",
        "arguments": "{\"path\":\"README.md\"}",
      },
    ],
    "finish_reason": "tool_calls",
    "usage": { "input_tokens": 10, "output_tokens": 4, "total_tokens": 14 },
  }
}

///|
fn messages_start() -> String {
  frame("message_start", {
    "type": "message_start",
    "message": {
      "id": "m1",
      "type": "message",
      "role": "assistant",
      "content": [],
      "usage": { "input_tokens": 12, "output_tokens": 0 },
    },
  })
}

///|
fn messages_end(reason : String) -> String {
  frame("message_delta", {
    "type": "message_delta",
    "delta": { "stop_reason": reason },
    "usage": { "output_tokens": 9 },
  }) +
  frame("message_stop", { "type": "message_stop" })
}

///|
fn messages_stream() -> String {
  messages_start() +
  frame("ping", { "type": "ping" }) +
  frame("content_block_start", {
    "type": "content_block_start",
    "index": 3,
    "content_block": { "type": "thinking", "thinking": "Read " },
  }) +
  frame("content_block_delta", {
    "type": "content_block_delta",
    "index": 3,
    "delta": { "type": "thinking_delta", "thinking": "the file" },
  }) +
  frame("content_block_delta", {
    "type": "content_block_delta",
    "index": 3,
    "delta": { "type": "signature_delta", "signature": "sig" },
  }) +
  frame("content_block_stop", { "type": "content_block_stop", "index": 3 }) +
  frame("content_block_start", {
    "type": "content_block_start",
    "index": 1,
    "content_block": { "type": "text", "text": "確認" },
  }) +
  frame("content_block_delta", {
    "type": "content_block_delta",
    "index": 1,
    "delta": { "type": "text_delta", "text": "します" },
  }) +
  frame("content_block_stop", { "type": "content_block_stop", "index": 1 }) +
  frame("content_block_start", {
    "type": "content_block_start",
    "index": 5,
    "content_block": {
      "type": "tool_use",
      "id": "c1",
      "name": "read_file",
      "input": Json::empty_object(),
    },
  }) +
  frame("content_block_delta", {
    "type": "content_block_delta",
    "index": 5,
    "delta": { "type": "input_json_delta", "partial_json": "{\"path\":" },
  }) +
  frame("content_block_delta", {
    "type": "content_block_delta",
    "index": 5,
    "delta": { "type": "input_json_delta", "partial_json": "\"README.md\"}" },
  }) +
  frame("content_block_stop", { "type": "content_block_stop", "index": 5 }) +
  messages_end("tool_use")
}

///|
fn messages_expected() -> Json {
  {
    "ok": true,
    "content": "確認します",
    "reasoning": "Read the file",
    "tool_calls": [
      {
        "id": "c1",
        "name": "read_file",
        "arguments": "{\"path\":\"README.md\"}",
      },
    ],
    "finish_reason": "tool_calls",
    "usage": { "input_tokens": 12, "output_tokens": 9 },
  }
}

///|
test "OpenAI streaming is invariant to every two-chunk boundary including CRLF and JSON fragments" {
  let wire = openai_stream()
  let expected = openai_expected()
  for split = 0; split <= wire.length(); split = split + 1 {
    let decoder = @provider.StreamDecoder::new("openai")
    assert_true(decoder.feed(wire[:split].to_owned()) is Ok(_))
    assert_true(decoder.feed(wire[split:].to_owned()) is Ok(_))
    assert_true(value(decoder.finish()) == expected)
  }
}

///|
test "Messages streaming preserves reasoning text tools and usage under one-character chunks" {
  let decoder = @provider.StreamDecoder::new("deepseek")
  for character in messages_stream() {
    assert_true(decoder.feed(character.to_string()) is Ok(_))
  }
  assert_true(value(decoder.finish()) == messages_expected())
  assert_true(value(decoder.finish()) == messages_expected())
  assert_true(decoder.feed("") is Err(_))
}

///|
test "Messages event framing supports LF CR BOM comments and multiline data" {
  let lf_wire = messages_stream().replace_all(old="\r\n", new="\n")
  let cr_wire = messages_stream().replace_all(old="\r\n", new="\r")
  assert_true(
    value(@provider.decode_sse("deepseek", "\u{FEFF}: heartbeat\n\n" + lf_wire)) ==
    messages_expected(),
  )
  assert_true(
    value(@provider.decode_sse("deepseek", cr_wire)) == messages_expected(),
  )
  let multiline = "event: message_start\ndata: {\"type\":\"message_start\",\ndata: \"message\":{\"type\":\"message\",\"role\":\"assistant\",\"usage\":{}}}\n\n" +
    frame("", {
      "type": "content_block_start",
      "index": 0,
      "content_block": { "type": "text", "text": "Hello" },
    }) +
    frame("", { "type": "content_block_stop", "index": 0 }) +
    messages_end("end_turn")
  assert_true(
    at(value(@provider.decode_sse("deepseek", multiline)), "content") == "Hello",
  )
}

///|
test "stream EOF is not completion and a terminal must be fully framed" {
  let openai = openai_stream()
  for
    incomplete in [
      "",
      openai_frame({ "content": "x" }, "stop"),
      "data: [DONE]\n\n",
      openai[:openai.length() - 2].to_owned(),
      openai + "data: {",
    ] {
    assert_true(@provider.decode_sse("openai", incomplete) is Err(_))
  }
  for
    incomplete in [
      messages_start(),
      frame("message_stop", { "type": "message_stop" }),
      messages_start() +
      frame("content_block_start", {
        "type": "content_block_start",
        "index": 0,
        "content_block": { "type": "text", "text": "x" },
      }) +
      messages_end("end_turn"),
      messages_start() + frame("message_stop", { "type": "message_stop" }),
    ] {
    assert_true(@provider.decode_sse("deepseek", incomplete) is Err(_))
  }
}

///|
test "stream parser rejects mismatched event names malformed JSON and in-band errors" {
  for
    wire in [
      "data: {bad}\n\n",
      frame("message_stop", { "type": "message_start" }),
      frame("error", {
        "type": "error",
        "error": { "type": "rate_limit_error", "message": "slow down" },
      }),
      frame("error", { "type": "error" }),
      frame("", {
        "type": "content_block_delta",
        "index": 0,
        "delta": { "type": "text_delta", "text": "x" },
      }),
      messages_start() + messages_start(),
      messages_stream() + frame("", { "type": "ping" }),
    ] {
    assert_true(@provider.decode_sse("deepseek", wire) is Err(_))
  }
  assert_true(
    @provider.decode_sse(
      "openai",
      openai_frame({ "refusal": "Cannot comply" }, "stop") + "data: [DONE]\n\n",
    )
    is Err(_),
  )
  assert_true(
    @provider.decode_sse("openai", frame("error", { "message": "failed" }))
    is Err(_),
  )
}

///|
test "tool arguments require a JSON object and duplicate IDs never become executable" {
  for arguments in ["{", "[]", "null", "true", "\"text\""] {
    let wire = openai_frame(
        {
          "tool_calls": [
            {
              "index": 0,
              "id": "c1",
              "type": "function",
              "function": {
                "name": "read_file",
                "arguments": arguments.to_json(),
              },
            },
          ],
        },
        "tool_calls",
      ) +
      "data: [DONE]\n\n"
    assert_true(@provider.decode_sse("openai", wire) is Err(_))
  }
  let duplicate = openai_frame(
      {
        "tool_calls": [
          {
            "index": 0,
            "id": "same",
            "type": "function",
            "function": { "name": "read_file", "arguments": "{}" },
          },
          {
            "index": 1,
            "id": "same",
            "type": "function",
            "function": { "name": "read_file", "arguments": "{}" },
          },
        ],
      },
      "tool_calls",
    ) +
    "data: [DONE]\n\n"
  assert_true(@provider.decode_sse("openai", duplicate) is Err(_))
  let unknown = openai_frame(
      {
        "tool_calls": [
          { "index": 0, "type": "function", "function": { "arguments": "{}" } },
        ],
      },
      "tool_calls",
    ) +
    "data: [DONE]\n\n"
  assert_true(@provider.decode_sse("openai", unknown) is Err(_))
}

///|
test "length-limited stream drops partial tool arguments" {
  let wire = openai_frame(
      {
        "content": "Partial",
        "tool_calls": [
          {
            "index": 0,
            "id": "c1",
            "type": "function",
            "function": { "name": "write_file", "arguments": "{\"path\":" },
          },
        ],
      },
      "length",
    ) +
    "data: [DONE]\n\n"
  assert_true(
    value(@provider.decode_sse("openai", wire)) ==
    {
      "ok": true,
      "content": "Partial",
      "tool_calls": [],
      "finish_reason": "length",
    },
  )
  let messages = messages_start() +
    frame("", {
      "type": "content_block_start",
      "index": 0,
      "content_block": {
        "type": "tool_use",
        "id": "a",
        "name": "write_file",
        "input": Json::empty_object(),
      },
    }) +
    frame("", {
      "type": "content_block_delta",
      "index": 0,
      "delta": { "type": "input_json_delta", "partial_json": "{\"path\":" },
    }) +
    frame("", { "type": "content_block_stop", "index": 0 }) +
    messages_end("max_tokens")
  assert_true(
    at(value(@provider.decode_sse("deepseek", messages)), "tool_calls") == [],
  )
}

///|
test "decoder errors are sticky and resource limits bound frame and response buffering" {
  let invalid = @provider.StreamDecoder::new("unknown")
  assert_true(invalid.feed("") is Err(_))
  assert_true(invalid.finish() is Err(_))
  let decoder = @provider.StreamDecoder::new("openai")
  let first_error = decoder.feed("data: {bad}\n\n")
  assert_true(first_error is Err(_))
  assert_true(decoder.feed(openai_stream()) == first_error)
  assert_true(decoder.finish() is Err(_))
  let large = @provider.StreamDecoder::new("openai")
  assert_true(large.feed("data: " + "a".repeat(1048577)) is Err(_))
  let many_frames = @provider.StreamDecoder::new("openai")
  let comment_chunk = ":" + "x".repeat(524288) + "\n"
  for index = 0; index < 31; index = index + 1 {
    assert_true(many_frames.feed(comment_chunk) is Ok(_))
  }
  assert_true(many_frames.feed(comment_chunk) is Err(_))
}

///|
test "block lifecycle rejects repeated indexes delta after stop and mismatched delta kind" {
  let start = frame("", {
    "type": "content_block_start",
    "index": 0,
    "content_block": { "type": "text", "text": "x" },
  })
  let stop = frame("", { "type": "content_block_stop", "index": 0 })
  let delta = frame("", {
    "type": "content_block_delta",
    "index": 0,
    "delta": { "type": "text_delta", "text": "y" },
  })
  for
    tail in [
      start + start,
      start + stop + delta,
      stop,
      start +
      frame("", {
        "type": "content_block_delta",
        "index": 0,
        "delta": { "type": "input_json_delta", "partial_json": "{}" },
      }),
      frame("", {
        "type": "content_block_start",
        "index": 1024,
        "content_block": { "type": "text", "text": "x" },
      }),
    ] {
    assert_true(
      @provider.decode_sse("deepseek", messages_start() + tail) is Err(_),
    )
  }
}
