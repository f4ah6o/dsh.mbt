///|
const NATIVE_ACP_TOO_LARGE : String = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"ACP line exceeds the 1 MiB limit\"}}"

///|
async fn native_acp_stdio_write(line : String) -> Result[Unit, String] {
  try {
    @stdio.stdout.write(line + "\n")
    Ok(())
  } catch {
    _ => Err("cannot write ACP response to stdout")
  }
}

///|
async fn native_acp_reply_result(
  service : NativeAcpService,
  id : Json?,
  result : Result[Json, NativeAcpRpcError],
  failure : Ref[String?],
) -> Unit {
  match id {
    None => ()
    Some(id) => {
      let write_result = match result {
        Ok(value) => service.write_response(id, value)
        Err(error) => service.write_error(id, error)
      }
      match write_result {
        Ok(_) => ()
        Err(error) => failure.val = Some(error)
      }
    }
  }
}

///|
async fn native_acp_dispatch(
  service : NativeAcpService,
  group : @async.TaskGroup[Unit],
  message : NativeAcpRpcMessage,
  raw : Json,
  failure : Ref[String?],
) -> Unit {
  match message.request_method {
    None => service.resolve_client_response(message, raw)
    Some(method_name) => {
      let id = message.id
      match method_name {
        "session/prompt" =>
          match service.prepare_prompt(message.params) {
            Err(error) =>
              native_acp_reply_result(service, id, Err(error), failure)
            Ok(prepared) =>
              ignore(
                group.spawn(
                  async fn() {
                    let result = service.execute_prompt(prepared)
                    native_acp_reply_result(service, id, result, failure)
                  },
                  allow_failure=true,
                ),
              )
          }
        "session/cancel" =>
          match service.require_initialized() {
            Err(error) =>
              native_acp_reply_result(service, id, Err(error), failure)
            Ok(_) =>
              match native_acp_required_session_id(message.params) {
                Err(error) =>
                  native_acp_reply_result(service, id, Err(error), failure)
                Ok(session_id) =>
                  match service.begin_cancel(session_id, false) {
                    Err(error) =>
                      native_acp_reply_result(service, id, Err(error), failure)
                    Ok(session) =>
                      ignore(
                        group.spawn(
                          async fn() {
                            let result = match service.apply_cancel(session) {
                              Ok(_) => Ok(Json::empty_object())
                              Err(error) => Err(error)
                            }
                            native_acp_reply_result(
                              service, id, result, failure,
                            )
                          },
                          allow_failure=true,
                        ),
                      )
                  }
              }
          }
        "session/close" =>
          match service.require_initialized() {
            Err(error) =>
              native_acp_reply_result(service, id, Err(error), failure)
            Ok(_) =>
              match native_acp_required_session_id(message.params) {
                Err(error) =>
                  native_acp_reply_result(service, id, Err(error), failure)
                Ok(session_id) =>
                  match service.begin_cancel(session_id, true) {
                    Err(error) =>
                      native_acp_reply_result(service, id, Err(error), failure)
                    Ok(session) =>
                      ignore(
                        group.spawn(
                          async fn() {
                            let result = service.finish_close(session)
                            native_acp_reply_result(
                              service, id, result, failure,
                            )
                          },
                          allow_failure=true,
                        ),
                      )
                  }
              }
          }
        _ => {
          let result = service.handle_request(method_name, message.params)
          native_acp_reply_result(service, id, result, failure)
        }
      }
    }
  }
}

///|
async fn native_acp_stdio_frame(
  service : NativeAcpService,
  group : @async.TaskGroup[Unit],
  frame : NativeAcpFrame,
  failure : Ref[String?],
) -> Unit {
  if frame.too_large {
    match service.write_json(@json.parse(NATIVE_ACP_TOO_LARGE)) {
      Ok(_) => ()
      Err(error) => failure.val = Some(error)
    }
    return
  }
  let raw = match native_acp_decode_json(frame.bytes) {
    Ok(value) => value
    Err(error) => {
      let response = @json.parse(
        native_acp_rpc_error(Json::null(), -32700, error),
      )
      match service.write_json(response) {
        Ok(_) => ()
        Err(write_error) => failure.val = Some(write_error)
      }
      return
    }
  }
  let message = match native_acp_rpc_message(raw) {
    Ok(value) => value
    Err(error) => {
      // A response-shaped object belongs to the client side of an outstanding
      // permission request. Fail a matching pending permission closed, but
      // never answer a malformed response with a second response.
      match raw {
        Json::Object(fields) if fields.get("method") is None &&
          (fields.get("result") is Some(_) || fields.get("error") is Some(_)) => {
          service.reject_malformed_client_response(raw)
          return
        }
        _ => ()
      }
      let id = match raw {
        Json::Object(fields) =>
          match fields.get("id") {
            Some(value) if native_acp_id_key(value) is Some(_) => value
            _ => Json::null()
          }
        _ => Json::null()
      }
      match
        service.write_json(@json.parse(native_acp_rpc_error(id, -32600, error))) {
        Ok(_) => ()
        Err(write_error) => failure.val = Some(write_error)
      }
      return
    }
  }
  native_acp_dispatch(service, group, message, raw, failure)
}

///|
async fn native_acp_stdio_frames(
  service : NativeAcpService,
  group : @async.TaskGroup[Unit],
  frames : Array[NativeAcpFrame],
  failure : Ref[String?],
) -> Unit {
  for frame in frames {
    native_acp_stdio_frame(service, group, frame, failure)
  }
}

///|
async fn native_acp_stdio_loop(
  service : NativeAcpService,
  group : @async.TaskGroup[Unit],
  failure : Ref[String?],
) -> Result[Unit, String] {
  let framer = NativeAcpFramer::new()
  while @stdio.stdin.read_some(max_len=8192) is Some(chunk) {
    if failure.val is Some(error) {
      return Err(error)
    }
    native_acp_stdio_frames(service, group, framer.feed(chunk), failure)
  }
  native_acp_stdio_frames(service, group, framer.finish(), failure)
  Ok(())
}

///|
/// Run an ACP agent over newline-delimited JSON-RPC stdio. Prompt and close
/// handlers remain concurrent with reads so clients can cancel or answer an
/// outstanding permission request.
async fn native_acp_stdio(runtime : NativeRuntime) -> Result[Unit, String] {
  let service = NativeAcpService::new(runtime, async fn(line) {
    native_acp_stdio_write(line)
  })
  let failure : Ref[String?] = Ref(None)
  let loop_result : Ref[Result[Unit, String]] = Ref(Ok(()))
  @async.with_task_group() <| group => {
    let input = native_acp_stdio_loop(service, group, failure)
    let shutdown = service.shutdown()
    loop_result.val = match input {
      Err(error) => Err(error)
      Ok(_) => shutdown
    }
  }
  match failure.val {
    Some(error) => Err(error)
    None => loop_result.val
  }
}
