///|
async test "native service listener rebinds a fixed port after TIME_WAIT" {
  let mut port = 0
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      for _ in 0..<2 {
        let server = native_service_listener(
          @socket.Addr::parse("127.0.0.1:" + port.to_string()),
        )
        defer server.close()
        port = server.addr.port()
        let duplicate_bind_succeeded = try {
          let duplicate = native_service_listener(
            @socket.Addr::parse("127.0.0.1:" + port.to_string()),
          )
          duplicate.close()
          true
        } catch {
          _ => false
        }
        assert_true(!duplicate_bind_succeeded)
        let (connection, _) = server.accept()
        let request = connection.read_request()
        assert_eq(request.path, "/restart")
        connection.send_response(200, "OK", extra_headers={
          "Connection": "close",
          "Content-Length": "4",
        })
        connection.write("done")
        connection.end_response()
        connection.close()
      }
    }
    for _ in 0..<2 {
      for _ in 0..<200 {
        if port != 0 {
          break
        }
        @async.sleep(5)
      }
      assert_true(port != 0)
      let client = @socket.Tcp::connect(
        @socket.Addr::parse("127.0.0.1:" + port.to_string()),
      )
      defer client.close()
      client.write(
        "GET /restart HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
      )
      let response = client.read_all().text()
      assert_true(response.has_prefix("HTTP/1.1 200 OK"))
      assert_true(response.has_suffix("done"))
    }
  }
}
