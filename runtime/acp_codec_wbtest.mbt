///|
fn native_acp_test_byte_array(text : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  for byte in @utf8.encode(text) {
    bytes.push(byte)
  }
  bytes
}

///|
test "ACP framing handles fragmented UTF-8, bounded lines, and recovery" {
  let framer = NativeAcpFramer::new()
  let prefix = @utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":\"日")
  assert_eq(framer.feed(prefix).length(), 0)
  let suffix = @utf8.encode("本\",\"method\":\"initialize\"}\r\n")
  let frames = framer.feed(suffix)
  assert_eq(frames.length(), 1)
  assert_false(frames[0].too_large)
  assert_eq(
    @utf8.decode(Bytes::from_array(frames[0].bytes[:])),
    "{\"jsonrpc\":\"2.0\",\"id\":\"日本\",\"method\":\"initialize\"}",
  )

  let oversized = NativeAcpFramer::new()
  let input : Array[Byte] = []
  for _ in 0..<(NATIVE_ACP_LINE_LIMIT + 1) {
    input.push(b'x')
  }
  input.push(b'\n')
  for byte in @utf8.encode("{}\n") {
    input.push(byte)
  }
  let recovered = oversized.feed(Bytes::from_array(input[:]))
  assert_eq(recovered.length(), 2)
  assert_true(recovered[0].too_large)
  assert_false(recovered[1].too_large)
  assert_eq(recovered[1].bytes.length(), 2)
}

///|
test "ACP nesting is rejected before parsing and JSON-RPC ids keep their type" {
  let nested = StringBuilder()
  for _ in 0..<25 {
    nested.write_char('[')
  }
  nested.write_char('0')
  for _ in 0..<25 {
    nested.write_char(']')
  }
  assert_eq(
    native_acp_decode_json(native_acp_test_byte_array(nested.to_string())),
    Err("ACP JSON exceeds the nesting limit"),
  )

  assert_eq(native_acp_id_key(Json::string("1")), Some("s:1"))
  assert_eq(native_acp_id_key(Json::number(1.0)), Some("n:1"))
  assert_eq(native_acp_id_key(Json::number(1.25)), Some("n:1.25"))
  assert_eq(native_acp_id_key(Json::null()), Some("z:null"))
  let response = native_acp_rpc_message({
    "jsonrpc": "2.0",
    "id": 1.25,
    "result": {},
  })
  assert_true(response is Ok(_))
  let request = native_acp_rpc_message({
    "jsonrpc": "2.0",
    "id": "1",
    "method": "initialize",
    "params": { "protocolVersion": 1 },
  })
  assert_eq(request.unwrap().request_method, Some("initialize"))
  assert_true(
    native_acp_rpc_message({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "result": {},
    })
    is Err(_),
  )
}

///|
fn native_acp_test_is_decision(
  value : NativeAcpPermissionDecision,
  expected : NativeAcpPermissionDecision,
) -> Bool {
  match (value, expected) {
    (
      NativeAcpPermissionDecision::AllowOnce,
      NativeAcpPermissionDecision::AllowOnce,
    ) => true
    (
      NativeAcpPermissionDecision::RejectOnce,
      NativeAcpPermissionDecision::RejectOnce,
    ) => true
    (
      NativeAcpPermissionDecision::Cancelled,
      NativeAcpPermissionDecision::Cancelled,
    ) => true
    _ => false
  }
}

///|
test "ACP permission decisions are one-shot and fail closed" {
  assert_true(
    native_acp_test_is_decision(
      native_acp_permission_decision(
        Some({
          "jsonrpc": "2.0",
          "id": 7,
          "result": {
            "outcome": { "outcome": "selected", "optionId": "allow-once" },
          },
        }),
      ),
      NativeAcpPermissionDecision::AllowOnce,
    ),
  )
  for option in ["reject-once", "allow-always", "unknown"] {
    assert_true(
      native_acp_test_is_decision(
        native_acp_permission_decision(
          Some({
            "jsonrpc": "2.0",
            "id": 7,
            "result": {
              "outcome": { "outcome": "selected", "optionId": option },
            },
          }),
        ),
        NativeAcpPermissionDecision::RejectOnce,
      ),
    )
  }
  assert_true(
    native_acp_test_is_decision(
      native_acp_permission_decision(
        Some({
          "jsonrpc": "2.0",
          "id": 7,
          "error": { "code": -1, "message": "permission failed" },
        }),
      ),
      NativeAcpPermissionDecision::RejectOnce,
    ),
  )
  assert_true(
    native_acp_test_is_decision(
      native_acp_permission_decision(
        Some({
          "jsonrpc": "2.0",
          "id": 7,
          "result": { "outcome": { "outcome": "cancelled" } },
        }),
      ),
      NativeAcpPermissionDecision::Cancelled,
    ),
  )
  assert_true(
    native_acp_test_is_decision(
      native_acp_permission_decision(Some({ "result": { "outcome": {} } })),
      NativeAcpPermissionDecision::RejectOnce,
    ),
  )
}

///|
test "ACP distinguishes provider failure from a completed max-token turn" {
  assert_eq(
    native_acp_stop_reason({ "status": "failed", "events": [] }),
    Err("native provider turn failed"),
  )
  assert_eq(
    native_acp_stop_reason({
      "status": "completed",
      "turn_id": 3,
      "events": [
        { "type": "turn/end", "turn_id": 3, "data": { "reason": "max_tokens" } },
      ],
    }),
    Ok("max_tokens"),
  )
  assert_eq(
    native_acp_stop_reason({
      "status": "failed",
      "turn_id": 3,
      "events": [
        { "type": "turn/end", "turn_id": 3, "data": { "reason": "max_tokens" } },
      ],
    }),
    Ok("max_tokens"),
  )
}

///|
test "ACP text and resource links preserve order; unsupported blocks reject the batch" {
  assert_eq(
    native_acp_prompt_text({
      "prompt": [
        { "type": "text", "text": "First " },
        { "type": "resource_link", "name": "notes", "uri": "file:///notes.txt" },
        { "type": "text", "text": " last" },
      ],
    }),
    Ok("First [resource_link name=notes uri=file:///notes.txt] last"),
  )
  assert_true(
    native_acp_prompt_text({
      "prompt": [
        { "type": "text", "text": "accepted only if complete" },
        { "type": "image", "data": "ignored" },
      ],
    })
    is Err(_),
  )
}
