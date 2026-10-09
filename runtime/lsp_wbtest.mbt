///|
fn native_lsp_test_server_config(
  script_path : String,
  timeout_ms? : Int = 60000,
) -> Json {
  {
    "command": Json::string("/usr/bin/python3"),
    "args": Json::array([Json::string(script_path)]),
    "extensionToLanguage": { ".ts": Json::string("typescript") },
    "toolCallTimeoutMs": Json::number(timeout_ms.to_double()),
  }
}

///|
fn native_lsp_test_config(
  script_path : String,
  timeout_ms? : Int = 60000,
) -> Json {
  {
    "servers": {
      "fixture": native_lsp_test_server_config(script_path, timeout_ms~),
    },
  }
}

///|
fn native_lsp_test_python_server_script(
  counter_path : String,
  target_uri : String,
  behavior? : String = "normal",
  child_pid_path? : String = "",
  transcript_path? : String = "",
) -> String {
  let location : Json = {
    "uri": Json::string(target_uri),
    "range": {
      "start": { "line": Json::number(0.0), "character": Json::number(0.0) },
      "end": { "line": Json::number(0.0), "character": Json::number(4.0) },
    },
  }
  let hover : Json = {
    "contents": {
      "kind": Json::string("markdown"),
      "value": Json::string("fixture hover"),
    },
    "range": {
      "start": { "line": Json::number(0.0), "character": Json::number(0.0) },
      "end": { "line": Json::number(0.0), "character": Json::number(4.0) },
    },
  }
  let capabilities : Json = {
    "capabilities": {
      "positionEncoding": Json::string("utf-16"),
      "textDocumentSync": Json::number(1.0),
      "definitionProvider": Json::boolean(true),
      "referencesProvider": Json::boolean(true),
      "implementationProvider": Json::boolean(true),
      "hoverProvider": Json::boolean(true),
    },
  }
  let response_code = if behavior == "all-ops" {
    "        result = HOVER if method == \"textDocument/hover\" else ([LOCATION] if method == \"textDocument/references\" else LOCATION)\n" +
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": result})"
  } else if behavior == "error" {
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"error\": {\"code\": -32000, \"message\": \"SERVER_SECRET_SENTINEL\"}})"
  } else if behavior == "timeout" {
    "        import subprocess\n" +
    "        child = subprocess.Popen([\"/bin/sleep\", \"30\"])\n" +
    "        with open(CHILD_PID_PATH, \"w\") as child_file: child_file.write(str(child.pid))\n" +
    "        sys.exit(0)"
  } else if behavior == "timeout-once" {
    "        import os, subprocess\n" +
    "        if open(COUNTER_PATH).read().count(\"x\") == 1:\n" +
    "            child = subprocess.Popen([\"/bin/sleep\", \"30\"])\n" +
    "            with open(CHILD_PID_PATH, \"w\") as child_file: child_file.write(str(os.getpid()))\n" +
    "            sys.exit(0)\n" +
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": LOCATION})"
  } else if behavior == "cancel-once" {
    "        import os, subprocess, time\n" +
    "        if open(COUNTER_PATH).read().count(\"x\") == 1:\n" +
    "            subprocess.Popen([\"/bin/sleep\", \"30\"])\n" +
    "            with open(CHILD_PID_PATH, \"w\") as child_file: child_file.write(str(os.getpid()))\n" +
    "            while True: time.sleep(1)\n" +
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": LOCATION})"
  } else if behavior == "disconnect-once" {
    "        if open(COUNTER_PATH).read().count(\"x\") == 1: sys.exit(0)\n" +
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": LOCATION})"
  } else if behavior == "didclose-failure" {
    "        import os, time\n" +
    "        os.close(0)\n" +
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": LOCATION})\n" +
    "        time.sleep(30)"
  } else if behavior == "disconnect" {
    "        sys.exit(0)"
  } else {
    let result = if behavior == "hover" {
      hover
    } else if behavior == "references" {
      Json::array([location])
    } else {
      location
    }
    "        send({\"jsonrpc\": \"2.0\", \"id\": request_id, \"result\": json.loads(" +
    Json::string(result.stringify()).stringify() +
    ")})"
  }
  [
    "import json, os, sys",
    "COUNTER_PATH = " + Json::string(counter_path).stringify(),
    "CHILD_PID_PATH = " + Json::string(child_pid_path).stringify(),
    "TRANSCRIPT_PATH = " + Json::string(transcript_path).stringify(),
    "CAPABILITIES = json.loads(" +
    Json::string(capabilities.stringify()).stringify() +
    ")",
    "LOCATION = json.loads(" +
    Json::string(location.stringify()).stringify() +
    ")",
    "HOVER = json.loads(" + Json::string(hover.stringify()).stringify() + ")",
    "BEHAVIOR = " + Json::string(behavior).stringify(),
    "def read_message():",
    "    headers = {}",
    "    while True:",
    "        line = sys.stdin.buffer.readline()",
    "        if not line: return None",
    "        if line in (b'\\r\\n', b'\\n'): break",
    "        name, separator, value = line.partition(b':')",
    "        if not separator: return None",
    "        key = name.strip().lower()",
    "        if key == b'content-length':",
    "            if key in headers: return None",
    "            headers[key] = int(value.strip())",
    "    length = headers.get(b'content-length')",
    "    if length is None or length < 1 or length > 4194304: return None",
    "    body = sys.stdin.buffer.read(length)",
    "    if len(body) != length: return None",
    "    return json.loads(body)",
    "def send(message):",
    "    body = json.dumps(message, separators=(\",\", \":\")).encode()",
    "    sys.stdout.buffer.write(b'Content-Length: ' + str(len(body)).encode() + b'\\r\\n\\r\\n' + body)",
    "    sys.stdout.buffer.flush()",
    "while True:",
    "    message = read_message()",
    "    if message is None: break",
    "    method = message.get(\"method\")",
    "    if TRANSCRIPT_PATH:",
    "        with open(TRANSCRIPT_PATH, \"a\") as transcript: transcript.write(json.dumps(message, separators=(\",\", \":\")) + \"\\n\")",
    "    if method == \"initialize\":",
    "        with open(COUNTER_PATH, \"a\") as counter: counter.write(\"x\")",
    "        if BEHAVIOR == \"init-hang\" or (BEHAVIOR == \"init-hang-once\" and open(COUNTER_PATH).read().count(\"x\") == 1):",
    "            import subprocess, time",
    "            subprocess.Popen([\"/bin/sleep\", \"30\"])",
    "            with open(CHILD_PID_PATH, \"w\") as child_file: child_file.write(str(os.getpid()))",
    "            while True: time.sleep(1)",
    "        send({\"jsonrpc\": \"2.0\", \"id\": 91, \"method\": \"workspace/configuration\", \"params\": {\"items\": [{\"section\": \"fixture\"}]}})",
    "        send({\"jsonrpc\": \"2.0\", \"id\": message[\"id\"], \"result\": CAPABILITIES})",
    "    elif message.get(\"id\") == 91:",
    "        if message.get(\"result\") != [None]: sys.exit(13)",
    "    elif method in (\"initialized\", \"textDocument/didOpen\", \"textDocument/didClose\"):",
    "        pass",
    "    elif method in (\"textDocument/definition\", \"textDocument/references\", \"textDocument/implementation\", \"textDocument/hover\"):",
    "        request_id = message[\"id\"]",
    "        send({\"jsonrpc\": \"2.0\", \"id\": 92, \"method\": \"workspace/applyEdit\", \"params\": {\"edit\": {\"changes\": {}}}})",
    "        reply = read_message()",
    "        if reply is None or reply.get(\"id\") != 92 or \"error\" not in reply: sys.exit(32)",
    response_code,
    "    elif method == \"shutdown\":",
    "        if \"params\" in message: sys.exit(40)",
    "        send({\"jsonrpc\": \"2.0\", \"id\": message[\"id\"], \"result\": None})",
    "        if BEHAVIOR == \"shutdown-stall\":",
    "            import time",
    "            time.sleep(30)",
    "    elif method == \"exit\":",
    "        if \"params\" in message: sys.exit(41)",
    "        sys.exit(0)",
    "    else:",
    "        sys.exit(42)",
  ].join("\n") +
  "\n"
}

///|
fn native_lsp_test_tool_request(
  operation : String,
  file_path : String,
  line : Int,
  character : Int,
) -> Json {
  {
    "name": Json::string("lsp"),
    "arguments": {
      "operation": Json::string(operation),
      "file_path": Json::string(file_path),
      "line": Json::number(line.to_double()),
      "character": Json::number(character.to_double()),
    },
  }
}

///|
fn native_lsp_test_tools(workspace : String) -> NativeTools {
  let root = SafeRoot::open(workspace).unwrap()
  let (device, inode) = root.identity().unwrap()
  NativeTools::new(
    root,
    workspace,
    None,
    false,
    safety_native_worker_launcher().unwrap(),
    device,
    inode,
  )
}

///|
fn native_lsp_test_provider_response(
  call_id : String,
  arguments : Json,
) -> Json {
  let tool_arguments = object_field(arguments, "arguments").unwrap()
  {
    "ok": Json::boolean(true),
    "content": Json::string(""),
    "reasoning": Json::string(""),
    "tool_calls": Json::array([
      {
        "id": Json::string(call_id),
        "name": Json::string("lsp"),
        "arguments": Json::string(tool_arguments.stringify()),
      },
    ]),
    "finish_reason": Json::string("tool_calls"),
    "usage": {
      "input_tokens": Json::number(1.0),
      "output_tokens": Json::number(1.0),
      "total_tokens": Json::number(2.0),
    },
  }
}

///|
test "native LSP parser enforces settings revision and keeps settings values out of fingerprints" {
  let config = native_lsp_test_server_config("/tmp/server")
  let custom = match config {
    Json::Object(fields) => fields
    _ => fail("test server config is not an object")
  }
  custom["initializationOptions"] = {
    "secret": Json::string("LSP_TEST_SECRET_SENTINEL"),
  }
  assert_true(
    native_lsp_parse_server("fixture", Json::object(custom)) is Err(_),
  )
  custom["settingsRevision"] = Json::string("options-v1")
  let parsed = native_lsp_parse_server("fixture", Json::object(custom)).unwrap()
  let digest = native_lsp_config_hash([parsed]).unwrap()
  assert_false(digest.contains("LSP_TEST_SECRET_SENTINEL"))
  custom["settingsRevision"] = Json::string("options-v2")
  let changed = native_lsp_parse_server("fixture", Json::object(custom)).unwrap()
  assert_true(
    native_lsp_config_hash([parsed]) != native_lsp_config_hash([changed]),
  )
}

///|
test "native LSP fingerprints ignore server, extension, and environment map order" {
  let first = native_lsp_parse_server("alpha", {
    "command": Json::string("/bin/true"),
    "env": {
      "Z_CHILD": Json::string("HOST_Z"),
      "A_CHILD": Json::string("HOST_A"),
    },
    "extensionToLanguage": {
      ".ts": Json::string("typescript"),
      ".js": Json::string("javascript"),
    },
  }).unwrap()
  let second = native_lsp_parse_server("beta", {
    "command": Json::string("/bin/false"),
    "extensionToLanguage": { ".py": Json::string("python") },
  }).unwrap()
  assert_eq(
    native_lsp_config_hash([first, second]),
    native_lsp_config_hash([second, first]),
  )
}

///|
test "native LSP positions and server capability checks are strict UTF-16" {
  let source = "const x = \"🧁\";\n"
  assert_eq(native_lsp_position(source, 1, 12), Ok((0, 11)))
  assert_true(native_lsp_position(source, 1, 13) is Err(_))
  assert_eq(native_lsp_position(source, 1, 14), Ok((0, 13)))
  assert_eq(native_lsp_position(source, 2, 1), Ok((1, 0)))
  assert_true(native_lsp_position(source, 3, 1) is Err(_))
  assert_true(native_lsp_supports_transient_open(Some(Json::number(1.0))))
  assert_true(native_lsp_supports_transient_open(Some(Json::number(2.0))))
  assert_true(
    native_lsp_supports_transient_open(
      Some({ "openClose": Json::boolean(true) }),
    ),
  )
  assert_false(native_lsp_supports_transient_open(Some(Json::number(0.0))))
  assert_false(
    native_lsp_supports_transient_open(
      Some({ "openClose": Json::boolean(false) }),
    ),
  )
}

///|
test "native LSP framing tolerates split UTF-8 and rejects malformed or oversized frames" {
  let body = "{\"text\":\"é🧁\"}"
  let body_bytes = @utf8.encode(body)
  let frame = @utf8.encode(
    "Content-Length: " + body_bytes.length().to_string() + "\r\n\r\n",
  )
  let bytes : Array[Byte] = []
  for byte in frame {
    bytes.push(byte)
  }
  for byte in body_bytes {
    bytes.push(byte)
  }
  let emoji_start = frame.length() + @utf8.encode("{\"text\":\"é").length()
  let framer = NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES)
  assert_eq(framer.feed(Bytes::from_array(bytes[:emoji_start + 1])), Ok([]))
  let messages = framer.feed(Bytes::from_array(bytes[emoji_start + 1:]))
  assert_eq(messages, Ok([@json.parse(body)]))

  let malformed = NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES)
  assert_true(
    malformed.feed(@utf8.encode("Content-Length: x\r\n\r\n{}")) is Err(_),
  )
  let duplicate = NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES)
  assert_true(
    duplicate.feed(
      @utf8.encode("Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}"),
    )
    is Err(_),
  )
  let oversized = NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES)
  assert_true(
    oversized.feed(@utf8.encode("Content-Length: 4194305\r\n\r\n")) is Err(_),
  )
  let deep = StringBuilder()
  for _ in 0..<33 {
    deep.write_char('[')
  }
  deep.write_char('0')
  for _ in 0..<33 {
    deep.write_char(']')
  }
  let deep_text = deep.to_string()
  let deep_body = @utf8.encode(deep_text)
  let deep_frame = @utf8.encode(
    "Content-Length: " + deep_body.length().to_string() + "\r\n\r\n",
  )
  let deep_bytes : Array[Byte] = []
  for byte in deep_frame {
    deep_bytes.push(byte)
  }
  for byte in deep_body {
    deep_bytes.push(byte)
  }
  assert_true(
    NativeLspFramer::new(NATIVE_LSP_MAX_MESSAGE_BYTES).feed(
      Bytes::from_array(deep_bytes[:]),
    )
    is Err(_),
  )
}

///|
async test "native LSP result cap counts visible workspace files and hides protected-store paths" {
  let fixture = @fs.tmpdir(prefix="dsh-lsp-result-filter")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/target.ts", "target")
    @fs.mkdir(workspace + "/private")
    @fs.write_file(workspace + "/private/store.json", "private")
    let root = SafeRoot::open(workspace).unwrap()
    group.add_defer(() => root.close())
    let range : Json = {
      "start": { "line": Json::number(0.0), "character": Json::number(0.0) },
      "end": { "line": Json::number(0.0), "character": Json::number(1.0) },
    }
    let location : Json = {
      "uri": Json::string(native_lsp_file_uri(fixture + "/outside.ts")),
      "range": range,
    }
    let locations : Array[Json] = []
    for _ in 0..<100 {
      locations.push(location)
    }
    locations.push({
      "uri": Json::string(native_lsp_file_uri(workspace + "/target.ts")),
      "range": range,
    })
    let rendered = native_lsp_render_locations(
      Json::array(locations),
      workspace,
      root,
    ).unwrap()
    assert_true(rendered.contains("target.ts:1:1"))
    assert_true(rendered.contains("100 location(s) omitted"))
    let blocked = native_lsp_render_locations(
      Json::array([
        {
          "uri": Json::string(
            native_lsp_file_uri(workspace + "/private/store.json"),
          ),
          "range": range,
        },
      ]),
      workspace,
      root,
      blocked_path=Some("private/store.json"),
    ).unwrap()
    assert_true(blocked.contains("location(s) omitted"))
    assert_false(blocked.contains("private/store.json"))
  }
  assert_true(
    native_lsp_hover_text({ "contents": Json::string("x"), "range": {} })
    is Err(_),
  )
}

///|
async test "native LSP URI projection accepts local URI forms and rejects aliases and traversal" {
  let fixture = @fs.tmpdir(prefix="dsh-lsp-uri-é")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace é"
    @fs.mkdir(workspace)
    let file_path = workspace + "/source #?.ts"
    @fs.write_file(file_path, "source")
    @fs.symlink(workspace + "/source-link.ts", target=file_path)
    let root = SafeRoot::open(workspace).unwrap()
    group.add_defer(() => root.close())
    let encoded = native_lsp_file_uri(file_path)
    let lower = encoded.replace_all(old="%C3%A9", new="%c3%a9")
    let expected_relative = "source #?.ts"
    assert_eq(
      native_lsp_workspace_location_path(lower, workspace, root),
      Some(expected_relative),
    )
    let localhost = "file://localhost" + encoded[7:].to_owned()
    assert_eq(
      native_lsp_workspace_location_path(localhost, workspace, root),
      Some(expected_relative),
    )
    assert_eq(
      native_lsp_workspace_location_path(
        "file://remote.example" + encoded[7:].to_owned(),
        workspace,
        root,
      ),
      None,
    )
    assert_eq(
      native_lsp_workspace_location_path(
        native_lsp_file_uri(workspace + "/%2e%2e/outside.ts"),
        workspace,
        root,
      ),
      None,
    )
    assert_eq(
      native_lsp_workspace_location_path(
        "file://" + workspace + "/%2Fetc/passwd",
        workspace,
        root,
      ),
      None,
    )
    assert_eq(
      native_lsp_workspace_location_path(
        native_lsp_file_uri(workspace + "/source-link.ts"),
        workspace,
        root,
      ),
      None,
    )
  }
}

///|
async test "native LSP model tool requires approval and runs bounded read-only navigation" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-runtime")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "export const x = 1;\n")
    let counter = fixture + "/started"
    let target_uri = native_lsp_file_uri(@fs.realpath(workspace + "/target.ts"))
    let script_path = fixture + "/server.sh"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(counter, target_uri),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let runtime = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      lsp_config_path=Some(config_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_true(runtime.lsp.descriptor is Some(_))
    runtime
    .invoke("session_create", {
      "id": Json::string("lsp-runtime-session"),
      "title": Json::string("LSP tool path"),
    })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": Json::string("lsp-runtime-session"),
        "prompt": Json::string("Find the definition"),
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let request = native_lsp_test_tool_request(
      "goToDefinition", "source.ts", 1, 1,
    )
    let (_, no_effects) = runtime
      .complete(
        provider.id(),
        native_lsp_test_provider_response("lsp-runtime-call", request),
      )
      .unwrap()
    assert_true(no_effects.is_empty())
    assert_false(@fs.exists(counter))
    let pending = runtime
      .invoke("session_get", {
        "session_id": Json::string("lsp-runtime-session"),
      })
      .unwrap().0
    assert_eq(string_field(pending, "status"), Some("awaiting_approval"))
    assert_eq(
      string_field(object_field(pending, "pending_approval").unwrap(), "name"),
      Some("lsp"),
    )
    let call_id = string_field(
      object_field(pending, "pending_approval").unwrap(),
      "call_id",
    ).unwrap()
    let (_, approved) = runtime
      .invoke("tool_approve", {
        "session_id": Json::string("lsp-runtime-session"),
        "call_id": Json::string(call_id),
        "approved": Json::boolean(true),
      })
      .unwrap()
    let tool_effect = native_effect_by_kind(approved, @engine.EffectType::Tool).unwrap()
    let (_, followup) = runtime.run_tool_effect(tool_effect).unwrap()
    assert_true(
      followup.any(effect => effect.kind() == @engine.EffectType::Provider),
    )
    assert_eq(@fs.read_file(counter).text(), "x")
    let session = runtime
      .invoke("session_get", {
        "session_id": Json::string("lsp-runtime-session"),
      })
      .unwrap().0
    if !session.stringify().contains("target.ts:1:1") {
      fail(session.stringify())
    }
    assert_true(runtime.close() is Ok(_))
    assert_eq(@fs.read_file(counter).text(), "x")

    let reopened = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      lsp_config_path=Some(config_path),
    ).unwrap()
    assert_true(reopened.lsp.descriptor is Some(_))
    assert_eq(@fs.read_file(counter).text(), "x")
    assert_true(reopened.close() is Ok(_))
    assert_true(NativeRuntime::open(data_dir, workspace, false, true) is Err(_))
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "native LSP validates paths before spawn and sanitizes server errors" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-errors")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = \"🧁\";\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let script_path = fixture + "/server.sh"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="error",
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    assert_eq(
      native_lsp_workspace_location_path(
        native_lsp_file_uri(workspace + "/target.ts"),
        workspace,
        tools.root,
      ),
      Some("target.ts"),
    )
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let invalid_path = pool.execute(
      tools,
      native_lsp_test_tool_request("hover", "../outside.ts", 1, 1),
    )
    assert_eq(object_field(invalid_path, "ok"), Some(Json::boolean(false)))
    assert_false(@fs.exists(counter))
    let split_emoji = pool.execute(
      tools,
      native_lsp_test_tool_request("hover", "source.ts", 1, 13),
    )
    assert_eq(object_field(split_emoji, "ok"), Some(Json::boolean(false)))
    assert_false(@fs.exists(counter))
    let rejected = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    if !string_field(rejected, "error")
      .unwrap_or("")
      .contains("server rejected") {
      fail(rejected.stringify())
    }
    assert_eq(object_field(rejected, "ok"), Some(Json::boolean(false)))
    assert_true(
      string_field(rejected, "error").unwrap_or("").contains("server rejected"),
    )
    assert_false(rejected.stringify().contains("SERVER_SECRET_SENTINEL"))
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "native LSP per-response notification limits reset across pooled queries" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-notifications")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let script_path = fixture + "/server.sh"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let mut index = 0
    while index < 70 {
      let result = pool.execute(
        tools,
        native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
      )
      if object_field(result, "ok") != Some(Json::boolean(true)) {
        fail(result.stringify() + " markers=" + @fs.read_file(counter).text())
      }
      assert_eq(string_field(result, "content"), Some("target.ts:1:1"))
      assert_eq(object_field(result, "ok"), Some(Json::boolean(true)))
      index += 1
    }
    assert_eq(@fs.read_file(counter).text(), "x")
  }
}

///|
async test "native LSP dispatches all four upstream operations with fresh source text" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-operations")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let source_path = workspace + "/source.ts"
    @fs.write_file(source_path, "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let transcript_path = fixture + "/transcript.jsonl"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="all-ops",
        transcript_path~,
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    for
      operation in [
        "goToDefinition", "findReferences", "goToImplementation", "hover",
      ] {
      let result = pool.execute(
        tools,
        native_lsp_test_tool_request(operation, "source.ts", 1, 1),
      )
      if object_field(result, "ok") != Some(Json::boolean(true)) {
        fail(operation + ": " + result.stringify())
      }
      if operation == "hover" {
        assert_eq(string_field(result, "content"), Some("fixture hover"))
      } else {
        assert_true(
          string_field(result, "content")
          .unwrap_or("")
          .contains("target.ts:1:1"),
        )
      }
    }
    @fs.write_file(source_path, "const x = 2;\n")
    let refreshed = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(refreshed, "ok"), Some(Json::boolean(true)))
    let transcript = @fs.read_file(transcript_path).text()
    assert_true(transcript.contains("\"method\":\"textDocument/definition\""))
    assert_true(transcript.contains("\"method\":\"textDocument/references\""))
    assert_true(
      transcript.contains("\"method\":\"textDocument/implementation\""),
    )
    assert_true(transcript.contains("\"method\":\"textDocument/hover\""))
    assert_true(
      transcript.contains("\"context\":{\"includeDeclaration\":true}"),
    )
    assert_true(transcript.contains("const x = 1;"))
    assert_true(transcript.contains("const x = 2;"))
  }
}

///|
async test "native LSP query timeout reaps descendants and only a later call starts a fresh server" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-timeout")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let group_pid_file = fixture + "/group.pid"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="timeout-once",
        child_pid_path=group_pid_file,
      ),
    )
    let config : Json = {
      "servers": {
        "fixture": native_lsp_test_server_config(script_path, timeout_ms=1000),
      },
    }
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, config.stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))

    let failed = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(failed, "ok"), Some(Json::boolean(false)))
    assert_true(@fs.exists(group_pid_file))
    assert_eq(@fs.read_file(counter).text(), "x")
    let pid = service_parse_int(@fs.read_file(group_pid_file).text()).unwrap()
    assert_false(os_process_group_alive(pid))

    let independent = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(independent, "ok"), Some(Json::boolean(true)))
    assert_eq(string_field(independent, "content"), Some("target.ts:1:1"))
    assert_eq(@fs.read_file(counter).text(), "xx")
  }
}

///|
async test "native LSP disconnect is not replayed and a later independent call may restart" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-disconnect")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="disconnect-once",
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))

    let failed = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(failed, "ok"), Some(Json::boolean(false)))
    assert_eq(@fs.read_file(counter).text(), "x")

    let independent = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(independent, "ok"), Some(Json::boolean(true)))
    assert_eq(string_field(independent, "content"), Some("target.ts:1:1"))
    assert_eq(@fs.read_file(counter).text(), "xx")
  }
}

///|
async test "native LSP didClose write failure poisons and stops the worker" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-didclose-failure")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="didclose-failure",
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let result = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(result, "ok"), Some(Json::boolean(false)))
    assert_true(
      string_field(result, "error").unwrap_or("").contains("didClose failed"),
    )
    assert_eq(@fs.read_file(counter).text(), "x")
    let server_pid = pool.servers.get("fixture").map(value => value.pid)
    let pid = server_pid.unwrap()
    assert_false(os_process_group_alive(pid))
    pool.close()
    assert_false(os_process_group_alive(pid))
  }
}

///|
async test "native LSP close bounds the complete graceful shutdown when server stops reading" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-shutdown-stall")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="shutdown-stall",
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    let result = pool.execute(
      tools,
      native_lsp_test_tool_request("goToDefinition", "source.ts", 1, 1),
    )
    assert_eq(object_field(result, "ok"), Some(Json::boolean(true)))
    let pid = pool.servers.get("fixture").unwrap().pid
    let closed = @async.with_timeout_opt(5000, async fn() {
      pool.close()
      true
    })
    assert_eq(closed, Some(true))
    assert_false(os_process_group_alive(pid))
  }
}

///|
async test "native LSP query cancellation terminates the process group without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let group_pid_file = fixture + "/group.pid"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="cancel-once",
        child_pid_path=group_pid_file,
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let request = native_lsp_test_tool_request(
      "goToDefinition", "source.ts", 1, 1,
    )
    let call = group.spawn(
      async fn() { pool.execute(tools, request) },
      no_wait=true,
      allow_failure=true,
    )
    let mut polls = 0
    while !@fs.exists(group_pid_file) && polls < 200 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(@fs.exists(group_pid_file))
    assert_eq(@fs.read_file(counter).text(), "x")
    let pid = service_parse_int(@fs.read_file(group_pid_file).text()).unwrap()
    call.cancel()
    ignore(call.wait()) catch {
      _ => ()
    }
    assert_false(os_process_group_alive(pid))
    assert_eq(@fs.read_file(counter).text(), "x")

    let independent = pool.execute(tools, request)
    assert_eq(object_field(independent, "ok"), Some(Json::boolean(true)))
    assert_eq(string_field(independent, "content"), Some("target.ts:1:1"))
    assert_eq(@fs.read_file(counter).text(), "xx")
  }
}

///|
async test "native LSP initialize cancellation kills the pending worker and releases its route" {
  let fixture = @fs.tmpdir(prefix="dsh-native-lsp-init-cancel")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.write_file(workspace + "/source.ts", "const x = 1;\n")
    @fs.write_file(workspace + "/target.ts", "target")
    let counter = fixture + "/started"
    let group_pid_file = fixture + "/group.pid"
    let script_path = fixture + "/server.py"
    @fs.write_file(
      script_path,
      native_lsp_test_python_server_script(
        counter,
        native_lsp_file_uri(workspace + "/target.ts"),
        behavior="init-hang-once",
        child_pid_path=group_pid_file,
      ),
    )
    let config_path = fixture + "/lsp.json"
    @fs.write_file(config_path, native_lsp_test_config(script_path).stringify())
    let root = SafeRoot::open(workspace).unwrap()
    let (device, inode) = root.identity().unwrap()
    root.close()
    let pool = NativeLspPool::open(
      Some(config_path),
      safety_native_worker_launcher().unwrap(),
      workspace,
      device,
      inode,
    ).unwrap()
    let tools = native_lsp_test_tools(workspace)
    group.add_defer(() => tools.root.close())
    group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
    let request = native_lsp_test_tool_request(
      "goToDefinition", "source.ts", 1, 1,
    )
    let call = group.spawn(
      async fn() { pool.execute(tools, request) },
      no_wait=true,
      allow_failure=true,
    )
    let mut polls = 0
    while !@fs.exists(group_pid_file) && polls < 200 {
      @async.sleep(5)
      polls += 1
    }
    assert_true(@fs.exists(group_pid_file))
    assert_eq(@fs.read_file(counter).text(), "x")
    let pid = service_parse_int(@fs.read_file(group_pid_file).text()).unwrap()
    call.cancel()
    ignore(call.wait()) catch {
      _ => ()
    }
    assert_false(os_process_group_alive(pid))
    assert_eq(@fs.read_file(counter).text(), "x")

    let independent = pool.execute(tools, request)
    assert_eq(object_field(independent, "ok"), Some(Json::boolean(true)))
    assert_eq(string_field(independent, "content"), Some("target.ts:1:1"))
    assert_eq(@fs.read_file(counter).text(), "xx")
  }
}

///|
async test "native LSP speaks to an installed clangd server" {
  if @fs.exists("/usr/bin/clangd") {
    let fixture = @fs.tmpdir(prefix="dsh-native-lsp-clangd")
    @async.with_task_group() <| group => {
      group.add_defer(() => @fs.rmdir(fixture, recursive=true))
      let workspace_alias = fixture + "/workspace"
      @fs.mkdir(workspace_alias)
      let workspace = @fs.realpath(workspace_alias)
      @fs.write_file(
        workspace + "/source.c",
        "int answer(void) { return 42; }\nint main(void) { return answer(); }\n",
      )
      let config : Json = {
        "servers": {
          "clangd": {
            "command": Json::string("/usr/bin/clangd"),
            "args": Json::array([Json::string("--log=error")]),
            "extensionToLanguage": { ".c": Json::string("c") },
          },
        },
      }
      let config_path = fixture + "/lsp.json"
      @fs.write_file(config_path, config.stringify())
      let root = SafeRoot::open(workspace).unwrap()
      let (device, inode) = root.identity().unwrap()
      root.close()
      let pool = NativeLspPool::open(
        Some(config_path),
        safety_native_worker_launcher().unwrap(),
        workspace,
        device,
        inode,
      ).unwrap()
      let tools = native_lsp_test_tools(workspace)
      group.add_defer(() => tools.root.close())
      group.add_defer(() => @async.protect_from_cancel(() => pool.close()))
      let result = pool.execute(
        tools,
        native_lsp_test_tool_request("goToDefinition", "source.c", 2, 25),
      )
      if object_field(result, "ok") != Some(Json::boolean(true)) {
        fail(result.stringify())
      }
      assert_eq(string_field(result, "content"), Some("source.c:1:5"))
    }
  }
}
