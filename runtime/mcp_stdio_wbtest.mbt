///|
test "MCP stdio framing returns parse errors and recovers after oversized lines" {
  let framer = NativeMcpFramer::new()
  let bytes : Array[Byte] = [b'\xff', b'\n']
  for _ in 0..<(NATIVE_MCP_LINE_LIMIT + 1) {
    bytes.push(b'x')
  }
  bytes.push(b'\n')
  for byte in @utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":1}\n") {
    bytes.push(byte)
  }
  let frames = framer.feed(Bytes::from_array(bytes[:]))
  assert_eq(frames.length(), 3)
  assert_eq(
    native_mcp_decode_line(frames[0].bytes),
    Err(NATIVE_MCP_INVALID_UTF8),
  )
  assert_eq(
    NATIVE_MCP_INVALID_UTF8,
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"MCP line is not valid UTF-8\"}}",
  )
  assert_true(frames[1].too_large)
  assert_false(frames[2].too_large)
  assert_eq(
    native_mcp_decode_line(frames[2].bytes),
    Ok("{\"jsonrpc\":\"2.0\",\"id\":1}"),
  )
  assert_eq(framer.finish().length(), 0)
}

///|
test "MCP stdio accepts an exact-limit CRLF split across chunks" {
  let framer = NativeMcpFramer::new()
  let exact : Array[Byte] = []
  for _ in 0..<NATIVE_MCP_LINE_LIMIT {
    exact.push(b'x')
  }
  exact.push(b'\r')
  assert_eq(framer.feed(Bytes::from_array(exact[:])).length(), 0)
  let ending = framer.feed(Bytes::from_array([b'\n']))
  assert_eq(ending.length(), 1)
  assert_false(ending[0].too_large)
  assert_eq(ending[0].bytes.length(), NATIVE_MCP_LINE_LIMIT)
  assert_eq(framer.finish().length(), 0)
}

///|
test "MCP stdio framing preserves a partial valid UTF-8 request at EOF" {
  let framer = NativeMcpFramer::new()
  let bytes = @utf8.encode("{\"method\":\"日本語\"}")
  assert_eq(framer.feed(bytes).length(), 0)
  let trailing = framer.finish()
  assert_eq(trailing.length(), 1)
  assert_eq(
    native_mcp_decode_line(trailing[0].bytes),
    Ok("{\"method\":\"日本語\"}"),
  )
  let carriage_return = NativeMcpFramer::new()
  let eof_line = carriage_return.feed(@utf8.encode("request\r"))
  assert_eq(eof_line.length(), 0)
  let eof_frame = carriage_return.finish()
  assert_eq(eof_frame.length(), 1)
  assert_eq(native_mcp_decode_line(eof_frame[0].bytes), Ok("request\r"))
}

///|
test "native CLI parser preserves node host rejection of missing and extra args" {
  assert_true(native_cli_validate_args(["dsh-native", "--data-dir"]) is Err(_))
  assert_true(
    native_cli_validate_args(
      native_cli_normalize_args([
        "dsh", "web", "--assets-dir", "/tmp/dsh-web-assets", "--demo",
      ]),
    )
    is Ok(_),
  )
  assert_true(
    native_cli_validate_args(
      native_cli_normalize_args(["dsh", "web", "--assets-dir"]),
    )
    is Err(_),
  )
  assert_true(
    native_cli_validate_args(["dsh-native", "--workspace", "--demo"]) is Err(_),
  )
  assert_true(native_cli_validate_args(["dsh-native", "--unknown"]) is Err(_))
  assert_true(
    native_cli_validate_args(native_cli_normalize_args(["dsh-native", "wat"]))
    is Err(_),
  )
  assert_true(
    native_cli_validate_args(native_cli_normalize_args(["dsh-native", "run"]))
    is Err(_),
  )
  assert_true(
    native_cli_validate_args(
      native_cli_normalize_args(["dsh-native", "web", "unexpected"]),
    )
    is Err(_),
  )
  assert_true(
    native_cli_validate_args(
      native_cli_normalize_args(["dsh-native", "web", "--", "--port", "0"]),
    )
    is Err(_),
  )
  assert_true(
    native_cli_validate_args(
      native_cli_normalize_args(["dsh-native", "import-session", "a", "b"]),
    )
    is Err(_),
  )
  assert_eq(
    native_cli_validate_args(
      native_cli_normalize_args([
        "dsh-native", "--demo", "run", "Find", "files", "--approve-writes",
      ]),
    ),
    Ok(()),
  )
  assert_eq(
    native_cli_validate_args(
      native_cli_normalize_args(["dsh-native", "import-session", "--", "--help"]),
    ),
    Ok(()),
  )
}
