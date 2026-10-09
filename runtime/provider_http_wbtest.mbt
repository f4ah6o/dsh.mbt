///|
async fn native_provider_serve_stalled_response(
  server : @http.Server,
  delay_ms : Int,
) -> Unit {
  try {
    let (connection, _) = server.accept()
    defer connection.close()
    ignore(connection.read_request())
    connection.skip_request_body()
    connection.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
      "Content-Length": "4",
      "Connection": "close",
    })
    connection.flush()
    @async.sleep(delay_ms)
    connection.write_string("data")
    connection.end_response()
  } catch {
    _ => ()
  }
}

///|
async fn native_provider_receive_fixture_stream(
  content_type : String?,
  body : String,
) -> Result[Json, String] {
  let address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => fail("could not parse provider HTTP fixture address")
  }
  let server = @http.Server::Server(address, reuse_addr=false)
  let endpoint = "http://127.0.0.1:\{server.addr.port()}/responses"
  let response_headers : @http.Headers = { "Connection": "close" }
  if content_type is Some(value) {
    response_headers["Content-Type"] = value
  }
  let result = @async.with_task_group() <| group => {
    let serving = group.spawn(async fn() {
      try {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        connection.skip_request_body()
        connection.send_response(200, "OK", extra_headers=response_headers)
        connection.write_string(body)
        connection.end_response()
      } catch {
        _ => ()
      }
    })
    let (response, client) = @http.get_stream(endpoint)
    defer client.close()
    let received = native_provider_receive_responses_stream(response, client, async fn(
      decoder,
    ) {
      ignore(decoder.take_events())
      @async.sleep(0)
      Ok(())
    })
    serving.wait()
    received
  }
  server.close()
  result
}

///|
test "native Responses accepts only absent or a single event-stream content type" {
  assert_true(native_provider_responses_mime_is_allowed(None))
  assert_true(
    native_provider_responses_mime_is_allowed(
      Some("Text/Event-Stream; charset=UTF-8"),
    ),
  )
  assert_true(!native_provider_responses_mime_is_allowed(Some("")))
  assert_true(!native_provider_responses_mime_is_allowed(Some("  ")))
  assert_true(
    !native_provider_responses_mime_is_allowed(Some("application/json")),
  )
  assert_true(!native_provider_responses_mime_is_allowed(Some("text/html")))
  assert_true(
    !native_provider_responses_mime_is_allowed(
      Some("application/json, text/event-stream"),
    ),
  )
  assert_true(
    !native_provider_responses_mime_is_allowed(
      Some("text/event-stream; charset=utf-8, application/json"),
    ),
  )
  assert_true(
    native_provider_is_failure_json(
      native_provider_failure_json("MALFORMED", "invalid stream"),
    ),
  )
}

///|
async test "native Responses accepts missing content type only for a completed SSE stream" {
  let result = native_provider_receive_fixture_stream(
    None,
    native_responses_fixture(),
  )
  match result {
    Ok(value) => assert_eq(string_field(value, "content"), Some("中🌙"))
    Err(error) => fail(error)
  }
}

///|
async test "native Responses accepts empty terminal output backed by a completed output item" {
  let body = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_done_backed\",\"status\":\"in_progress\"}}\n\n" +
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"msg_done_backed\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[]}}\n\n" +
    "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_done_backed\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello 🌙\"}\n\n" +
    "event: response.content_part.done\ndata: {\"type\":\"response.content_part.done\",\"item_id\":\"msg_done_backed\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"Hello 🌙\"}}\n\n" +
    "event: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"item_id\":\"msg_done_backed\",\"output_index\":0,\"content_index\":0,\"text\":\"Hello 🌙\"}\n\n" +
    "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"msg_done_backed\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello 🌙\"}]}}\n\n" +
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_done_backed\",\"status\":\"completed\",\"output\":[]}}\n\n"
  let result = native_provider_receive_fixture_stream(None, body)
  match result {
    Ok(value) => assert_eq(string_field(value, "content"), Some("Hello 🌙"))
    Err(error) => fail(error)
  }
}

///|
async test "native Responses returns after completed even while HTTP body stays open" {
  let address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => fail("could not parse provider HTTP fixture address")
  }
  let server = @http.Server::Server(address, reuse_addr=false)
  let endpoint = "http://127.0.0.1:\{server.addr.port()}/responses"
  let body = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_hold_open\",\"status\":\"in_progress\"}}\n\n" +
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"msg_hold_open\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[]}}\n\n" +
    "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_hold_open\",\"output_index\":0,\"content_index\":0,\"delta\":\"Complete now\"}\n\n" +
    "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"msg_hold_open\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Complete now\"}]}}\n\n" +
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_hold_open\",\"status\":\"completed\",\"output\":[]}}\n\n"
  @async.with_task_group() <| group => {
    let serving = group.spawn(async fn() {
      try {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        connection.skip_request_body()
        connection.send_response(200, "OK", extra_headers={
          "Connection": "keep-alive",
        })
        connection.write_string(body)
        connection.flush()
        @async.sleep(1200)
      } catch {
        _ => ()
      }
    })
    let (response, client) = @http.get_stream(endpoint)
    assert_eq(response.code, 200)
    let received = native_provider_with_deadline(300, async fn() {
      native_provider_receive_responses_stream(response, client, fn(decoder) {
        ignore(decoder.take_events())
        Ok(())
      })
    })
    client.close()
    match received {
      Some(Ok(value)) =>
        assert_eq(string_field(value, "content"), Some("Complete now"))
      Some(Err(error)) => fail(error)
      None => fail("receiver waited for HTTP EOF after response.completed")
    }
    serving.wait()
  }
  server.close()
}

///|
async test "native Responses rejects non-SSE and truncated bodies without content type" {
  let incomplete_frame = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_native\",\"status\":\"in_progress\"}}\n\n"
  let complete_stream = native_responses_fixture()
  let incomplete_terminal = complete_stream[:complete_stream.length() - 2].to_owned()
  for
    body in [
      "{\"error\":\"upstream response\"}", "<!doctype html><html></html>", "", incomplete_frame,
      incomplete_terminal,
    ] {
    let result = native_provider_receive_fixture_stream(None, body)
    match result {
      Ok(value) => {
        assert_true(native_provider_is_failure_json(value))
        let failure = object_field(value, "failure").unwrap()
        assert_eq(string_field(failure, "code"), Some("MALFORMED"))
      }
      Err(error) => fail(error)
    }
  }
}

///|
async test "native Responses rejects explicit non-SSE MIME despite SSE body" {
  for
    content_type in [
      "application/json", "text/html", "text/event-stream; charset=utf-8, application/json",
    ] {
    let result = native_provider_receive_fixture_stream(
      Some(content_type),
      native_responses_fixture(),
    )
    match result {
      Ok(value) => {
        assert_true(native_provider_is_failure_json(value))
        let failure = object_field(value, "failure").unwrap()
        assert_eq(string_field(failure, "code"), Some("MALFORMED"))
      }
      Err(error) => fail(error)
    }
  }
}

///|
async test "native Responses reads mixed-case MIME after informational response" {
  let address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => fail("could not parse provider HTTP fixture address")
  }
  let server = @http.Server::Server(address, reuse_addr=false)
  let endpoint = "http://127.0.0.1:\{server.addr.port()}/responses"
  let body = "event: response.completed\ndata: {}\n\n"
  @async.with_task_group() <| group => {
    let serving = group.spawn(async fn() {
      let (connection, _) = server.accept()
      defer connection.close()
      ignore(connection.read_request())
      connection.skip_request_body()
      connection.send_response(103, "Early Hints", extra_headers={
        "Content-Type": "text/html",
      })
      connection.end_response()
      connection.send_response(200, "OK", extra_headers={
        "cOnTeNt-TyPe": "text/event-stream; charset=utf-8",
        "Content-Length": "\{@utf8.encode(body).length()}",
        "Connection": "close",
      })
      connection.write_string(body)
      connection.end_response()
    })
    let (response, client) = @http.get_stream(endpoint)
    defer client.close()
    assert_eq(response.code, 200)
    let content_type = response.headers.get("content-type").unwrap()
    assert_eq(content_type, "text/event-stream; charset=utf-8")
    assert_eq(native_provider_mime_essence(content_type), "text/event-stream")
    let bytes = client.read_some(max_len=1024).unwrap()
    let decoded = @utf8.decode(bytes) catch {
      _ => fail("invalid fixture UTF-8")
    }
    assert_eq(decoded, body)
    serving.wait()
  }
  server.close()
}

///|
async test "native provider bounds stalled reads and total requests" {
  let total = native_provider_with_deadline(25, async fn() {
    @async.sleep(150)
    "late body"
  })
  assert_true(total is None)
  let idle_read = native_provider_with_deadline(25, async fn() {
    @async.sleep(150)
    "late chunk"
  })
  assert_true(idle_read is None)
  let immediate = native_provider_with_deadline(100, fn() { "ready" })
  assert_eq(immediate, Some("ready"))
  let timeout = native_provider_timeout_failure(
    "Provider response stream exceeded the idle time limit",
  )
  let failure = object_field(timeout, "failure").unwrap()
  assert_eq(string_field(failure, "code"), Some("TIMEOUT"))
  assert_true(
    !native_provider_body_limit_exceeded(0, NATIVE_PROVIDER_BODY_LIMIT),
  )
  assert_true(
    native_provider_body_limit_exceeded(0, NATIVE_PROVIDER_BODY_LIMIT + 1),
  )
  assert_true(native_provider_body_limit_exceeded(-1, 1))
}

///|
async test "native provider idle and total deadlines stop an actual stalled HTTP stream" {
  let idle_address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => fail("could not parse provider HTTP fixture address")
  }
  let idle_server = @http.Server::Server(idle_address, reuse_addr=false)
  let idle_endpoint = "http://127.0.0.1:\{idle_server.addr.port()}/events"
  @async.with_task_group() <| group => {
    let server = group.spawn(async fn() {
      native_provider_serve_stalled_response(idle_server, 250)
    })
    let (response, client) = @http.get_stream(idle_endpoint)
    assert_eq(response.code, 200)
    let idle = native_provider_read_chunk_with_timeout(client, 0, 75)
    match idle {
      NativeProviderRead::IdleTimeout => ()
      NativeProviderRead::End =>
        fail("stalled stream ended before its body arrived")
      NativeProviderRead::Data(_) =>
        fail("stalled stream delivered body before its delay")
      NativeProviderRead::TooLarge =>
        fail("stalled stream exceeded its body limit")
    }
    client.close()
    server.wait()
  }
  idle_server.close()

  let total_address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => fail("could not parse provider HTTP fixture address")
  }
  let total_server = @http.Server::Server(total_address, reuse_addr=false)
  let total_endpoint = "http://127.0.0.1:\{total_server.addr.port()}/events"
  @async.with_task_group() <| group => {
    let server = group.spawn(async fn() {
      native_provider_serve_stalled_response(total_server, 250)
    })
    let result = native_provider_with_deadline(75, async fn() {
      let (response, client) = @http.get_stream(total_endpoint)
      defer client.close()
      if response.code != 200 {
        return "invalid response"
      }
      match client.read_some(max_len=16384) {
        Some(_) => "body arrived"
        None => "body ended"
      }
    })
    assert_true(result is None)
    server.wait()
  }
  total_server.close()
}
