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
