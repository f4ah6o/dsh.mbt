///|
const NATIVE_MCP_LINE_LIMIT : Int = 1048576

///|
const NATIVE_MCP_TOO_LARGE : String = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"MCP line exceeds the 1 MiB limit\"}}"

///|
const NATIVE_MCP_INVALID_UTF8 : String = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"MCP line is not valid UTF-8\"}}"

///|
struct NativeMcpFrame {
  bytes : Array[Byte]
  too_large : Bool
}

///|
/// Stateful bounded framing for the newline-delimited MCP stdio carrier.
struct NativeMcpFramer {
  mut buffered : Array[Byte]
  mut discarding : Bool
}

///|
fn NativeMcpFramer::new() -> NativeMcpFramer {
  { buffered: [], discarding: false, }
}

///|
fn NativeMcpFramer::take_line(
  self : NativeMcpFramer,
  strip_carriage_return : Bool,
) -> NativeMcpFrame {
  if strip_carriage_return &&
    self.buffered.length() > 0 &&
    self.buffered[self.buffered.length() - 1] == b'\r' {
    ignore(self.buffered.pop())
  }
  let frame = { bytes: self.buffered, too_large: false, }
  self.buffered = []
  frame
}

///|
fn NativeMcpFramer::feed(
  self : NativeMcpFramer,
  chunk : Bytes,
) -> Array[NativeMcpFrame] {
  let frames : Array[NativeMcpFrame] = []
  for byte in chunk {
    if byte == b'\n' {
      if self.discarding {
        self.discarding = false
      } else {
        let frame = self.take_line(true)
        if frame.bytes.length() > NATIVE_MCP_LINE_LIMIT {
          frames.push({ bytes: [], too_large: true, })
        } else {
          frames.push(frame)
        }
      }
    } else if !self.discarding {
      // A CR is temporarily allowed after the exact byte limit because a
      // following LF makes it part of CRLF framing rather than the request.
      // If another byte or EOF follows, the line is oversized.
      let trailing_cr_candidate = self.buffered.length() ==
        NATIVE_MCP_LINE_LIMIT &&
        byte == b'\r'
      if self.buffered.length() > NATIVE_MCP_LINE_LIMIT ||
        (
          self.buffered.length() == NATIVE_MCP_LINE_LIMIT &&
          !trailing_cr_candidate
        ) {
        self.discarding = true
        self.buffered = []
        frames.push({ bytes: [], too_large: true, })
      } else {
        self.buffered.push(byte)
      }
    }
  }
  frames
}

///|
fn NativeMcpFramer::finish(self : NativeMcpFramer) -> Array[NativeMcpFrame] {
  if self.discarding || self.buffered.length() == 0 {
    []
  } else if self.buffered.length() > NATIVE_MCP_LINE_LIMIT {
    [{ bytes: [], too_large: true, }]
  } else {
    [self.take_line(false)]
  }
}

///|
fn native_mcp_decode_line(bytes : Array[Byte]) -> Result[String, String] {
  let text = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err(NATIVE_MCP_INVALID_UTF8)
  }
  Ok(text)
}

///|
async fn native_mcp_stdio_write(line : String) -> Result[Unit, String] {
  try {
    @stdio.stdout.write(line + "\n")
    Ok(())
  } catch {
    _ => Err("cannot write MCP response to stdout")
  }
}

///|
async fn native_mcp_stdio_line(
  runtime : NativeRuntime,
  group : @async.TaskGroup[Result[Unit, String]],
  bytes : Array[Byte],
) -> Result[Unit, String] {
  let line = match native_mcp_decode_line(bytes) {
    Ok(value) => value
    Err(response) => return native_mcp_stdio_write(response)
  }
  if line.trim().is_empty() {
    return Ok(())
  }
  let response = match runtime.mcp_handle(line, group) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if response.is_empty() {
    Ok(())
  } else {
    native_mcp_stdio_write(response)
  }
}

///|
async fn native_mcp_stdio_frames(
  runtime : NativeRuntime,
  group : @async.TaskGroup[Result[Unit, String]],
  frames : Array[NativeMcpFrame],
) -> Result[Unit, String] {
  for frame in frames {
    if frame.too_large {
      match native_mcp_stdio_write(NATIVE_MCP_TOO_LARGE) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else {
      match native_mcp_stdio_line(runtime, group, frame.bytes) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
  }
  Ok(())
}

///|
/// Serve the newline-delimited gpui MCP protocol over standard input/output.
/// Invalid UTF-8 and oversized lines receive JSON-RPC parse errors. Oversized
/// input is discarded through its newline so the next request stays aligned.
async fn native_mcp_stdio_loop(
  runtime : NativeRuntime,
  group : @async.TaskGroup[Result[Unit, String]],
) -> Result[Unit, String] {
  let framer = NativeMcpFramer::new()
  while @stdio.stdin.read_some(max_len=8192) is Some(chunk) {
    match native_mcp_stdio_frames(runtime, group, framer.feed(chunk)) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  native_mcp_stdio_frames(runtime, group, framer.finish())
}

///|
/// Keep background provider and tool work structured under the stdio carrier.
async fn native_mcp_stdio(runtime : NativeRuntime) -> Result[Unit, String] {
  @async.with_task_group() <| group => { native_mcp_stdio_loop(runtime, group) }
}
