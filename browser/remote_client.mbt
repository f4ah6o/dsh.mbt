///|
priv struct BrowserRequestError {
  status : Int
  message : String
}

///|
priv struct RemoteClient {
  handle : Int
  mut restored_scope : String
  mut stream : BrowserValue?
  mut persist_timer : Int?
}

///|
fn browser_state_result(value : Json) -> Json {
  match browser_json_field(value, "state") {
    Some(state) => state
    _ => Json::empty_object()
  }
}

///|
fn browser_error_text(value : Json, fallback : String) -> String {
  nonempty(browser_json_string(value, "error"), fallback)
}

///|
async fn request_json(
  path : String,
  http_method? : String = "GET",
  body? : String = "",
  timeout_ms? : Int = 20_000,
) -> Result[Json, BrowserRequestError] {
  let controller = @js_async.AbortController::new()
  let timed_out = Ref(false)
  let timer = browser_timeout(
    () => {
      timed_out.val = true
      controller.abort()
    },
    timeout_ms,
  )
  let response = @js_async.Promise::wait(
    browser_fetch(
      path,
      http_method,
      body,
      body != "",
      "no-store",
      "same-origin",
      "application/json",
      if body == "" {
        ""
      } else {
        "application/json"
      },
      controller.signal(),
    ),
    abort_controller=controller,
  ) catch {
    _ => {
      browser_clear_timeout(timer)
      if timed_out.val {
        return Err({
          status: 0,
          message: "ワークスペースへのリクエストがタイムアウトしました。再送信する前に操作の受付結果を確認してください。",
        })
      }
      return Err({
        status: 0,
        message: "ワークスペースのホストに接続できません。ネットワークまたは Tailnet の接続を確認してください。",
      })
    }
  }
  let status = browser_response_status(response)
  let raw = if status == 204 {
    ""
  } else {
    @js_async.Promise::wait(
      browser_response_text(response),
      abort_controller=controller,
    ) catch {
      _ => {
        browser_clear_timeout(timer)
        return Err({
          status,
          message: "ワークスペースからの応答を読み取れませんでした（HTTP \{status}）。",
        })
      }
    }
  }
  browser_clear_timeout(timer)
  let payload = if raw == "" {
    Json::null()
  } else {
    match browser_json(raw) {
      Ok(value) => value
      Err(_) =>
        return Err({
          status,
          message: "ワークスペースからの応答を読み取れませんでした（HTTP \{status}）。",
        })
    }
  }
  if !browser_response_ok(response) {
    let detail = nonempty(
      browser_json_string(payload, "error"),
      "HTTP \{status}",
    )
    return Err({
      status,
      message: "ワークスペースへのリクエストに失敗しました: " +
      detail,
    })
  }
  Ok(payload)
}

///|
fn RemoteClient::new() -> RemoteClient {
  {
    handle: @client.client_init(),
    restored_scope: "",
    stream: None,
    persist_timer: None,
  }
}

///|
fn RemoteClient::state(self : RemoteClient) -> Json {
  match browser_json(@client.client_state(self.handle)) {
    Ok(value) => value
    Err(_) => Json::empty_object()
  }
}

///|
fn RemoteClient::begin_connect(self : RemoteClient) -> Unit {
  ignore(@client.client_begin_connect(self.handle))
}

///|
fn RemoteClient::connection_failed(self : RemoteClient) -> Unit {
  ignore(@client.client_connection_failed(self.handle))
}

///|
fn RemoteClient::write_preferences(self : RemoteClient) -> Unit {
  let preferences = match
    browser_json(@client.client_persisted_state(self.handle)) {
    Ok(value) => value
    Err(_) => return
  }
  let scope_key = browser_json_string(preferences, "scope_key")
  if scope_key == "" {
    return
  }
  browser_local_storage_set(
    "dsh.client.preferences.v1:" + scope_key,
    preferences.stringify(),
  )
}

///|
fn RemoteClient::persist(self : RemoteClient) -> Unit {
  match self.persist_timer {
    Some(timer) => browser_clear_timeout(timer)
    None => ()
  }
  self.persist_timer = Some(
    browser_timeout(
      () => {
        self.persist_timer = None
        self.write_preferences()
      },
      180,
    ),
  )
}

///|
fn RemoteClient::persist_now(self : RemoteClient) -> Unit {
  match self.persist_timer {
    Some(timer) => browser_clear_timeout(timer)
    None => ()
  }
  self.persist_timer = None
  self.write_preferences()
}

///|
fn RemoteClient::restore_for_scope(self : RemoteClient, current : Json) -> Json {
  let scope_key = browser_json_string(current, "scope_key")
  if scope_key == "" || self.restored_scope == scope_key {
    return current
  }
  let previous_scope = self.restored_scope
  self.restored_scope = scope_key
  if previous_scope != "" {
    browser_local_storage_remove("dsh.client.preferences.v1:" + previous_scope)
  }
  match browser_local_storage_get("dsh.client.preferences.v1:" + scope_key) {
    Some(raw) => ignore(@client.client_restore_preferences(self.handle, raw))
    None => ()
  }
  self.state()
}

///|
async fn RemoteClient::snapshot(
  self : RemoteClient,
) -> Result[(Json, Json), String] {
  match request_json("/api/v1/snapshot") {
    Err(error) => Err(error.message)
    Ok(payload) => {
      let result = match
        browser_json(
          @client.client_accept_snapshot(self.handle, payload.stringify()),
        ) {
        Ok(value) => value
        Err(_) =>
          return Err(
            "ワークスペースのスナップショットを読み取れませんでした。",
          )
      }
      if !browser_json_bool(result, "ok") {
        return Err(
          browser_error_text(
            result, "ワークスペースのスナップショットが拒否されました。",
          ),
        )
      }
      let state = self.restore_for_scope(browser_state_result(result))
      self.persist()
      Ok((state, result))
    }
  }
}

///|
async fn RemoteClient::selected_session(
  self : RemoteClient,
  session_id : String,
) -> Result[Json, String] {
  let path = "/api/v1/sessions/" + browser_encode_uri_component(session_id)
  match request_json(path) {
    Err(error) => Err(error.message)
    Ok(payload) => {
      let result = match
        browser_json(
          @client.client_accept_session(self.handle, payload.stringify()),
        ) {
        Ok(value) => value
        Err(_) =>
          return Err(
            "選択中のセッションを読み取れませんでした。",
          )
      }
      if !browser_json_bool(result, "ok") {
        return Err(
          browser_error_text(
            result, "選択中のセッションが変わりました。ワークスペースを更新してください。",
          ),
        )
      }
      Ok(browser_state_result(result))
    }
  }
}

///|
fn RemoteClient::close_stream(self : RemoteClient) -> Unit {
  match self.stream {
    Some(stream) => browser_event_source_close(stream)
    None => ()
  }
  self.stream = None
}

///|
fn RemoteClient::subscribe(
  self : RemoteClient,
  on_event : (Json, Bool) -> Unit,
  on_error : (String?) -> Unit,
) -> Result[Unit, String] {
  self.close_stream()
  let current = self.state()
  let cursor = browser_json_string(current, "cursor")
  if cursor == "" {
    return Err(
      "ライブ更新を開始する前にワークスペースのスナップショットが必要です。",
    )
  }
  let selected = browser_json_string(current, "selected_session")
  let stream = browser_event_source_new(browser_event_url(cursor, selected))
  self.stream = Some(stream)
  let apply_event = fn(event : BrowserValue) {
    let result = match
      browser_json(
        @client.client_accept_event(
          self.handle,
          browser_event_data(event),
          browser_event_last_id(event),
        ),
      ) {
      Ok(value) => value
      Err(_) => Json::empty_object()
    }
    let status = browser_json_string(result, "status")
    let needs_snapshot = !browser_json_bool(result, "ok") ||
      status == "gap" ||
      status == "wrong_workspace" ||
      status == "identity_changed" ||
      status == "epoch_changed" ||
      status == "requires_snapshot" ||
      status == "cursor_mismatch"
    if needs_snapshot {
      on_event(result, true)
    } else {
      self.persist()
      on_event(result, false)
    }
  }
  dom_on(stream, "message", apply_event, false)
  dom_on(stream, "projection", apply_event, false)
  dom_on(stream, "resync", apply_event, false)
  dom_on(
    stream,
    "open",
    fn(_event) {
      ignore(@client.client_connection_restored(self.handle))
      on_error(None)
    },
    false,
  )
  dom_on(
    stream,
    "error",
    fn(_event) {
      self.connection_failed()
      on_error(
        Some(
          "ライブ更新を一時停止しました。ブラウザーが自動的に再接続します。",
        ),
      )
    },
    false,
  )
  Ok(())
}

///|
async fn RemoteClient::command(
  self : RemoteClient,
  operation : String,
  session_id : String?,
  input : Json,
  approval_revision? : Int = -1,
) -> Result[Json, String] {
  let command_id = @client.client_new_command_id(
    browser_now_ms(),
    browser_entropy_hex(),
  )
  if command_id == "" {
    return Err("安全な操作 ID を作成できませんでした。")
  }
  let queued = match
    browser_json(
      @client.client_queue_command(
        self.handle,
        command_id,
        operation,
        session_id.unwrap_or(""),
        input.stringify(),
        approval_revision,
      ),
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        "このワークスペースの状態では操作を実行できません。",
      )
  }
  if !browser_json_bool(queued, "ok") {
    return Err(
      browser_error_text(
        queued, "このワークスペースの状態では操作を実行できません。",
      ),
    )
  }
  let command = match browser_json_field(queued, "command") {
    Some(value) => value
    None =>
      return Err(
        "このワークスペースの状態では操作を実行できません。",
      )
  }
  ignore(@client.client_mark_command_sent(self.handle, command_id))
  self.persist_now()
  match
    request_json(
      "/api/v1/commands",
      http_method="POST",
      body=command.stringify(),
    ) {
    Ok(receipt) =>
      match self.apply_receipt(receipt) {
        Ok(_) => {
          self.persist()
          Ok(receipt)
        }
        Err(error) => Err(error)
      }
    Err(error) => {
      ignore(@client.client_mark_command_uncertain(self.handle, command_id))
      self.persist_now()
      match self.receipt_for(command_id) {
        Ok(Some(receipt)) => Ok(receipt)
        Ok(None) => {
          ignore(@client.client_mark_receipt_missing(self.handle, command_id))
          self.persist_now()
          Err(
            "ホストは操作を受け付けたか確認できませんでした。再送信する前に受付記録を確認してください。",
          )
        }
        Err(_) =>
          Err(
            error.message +
            " 操作がホストに届いている場合があります。再接続して受付記録を確認してください。",
          )
      }
    }
  }
}

///|
fn RemoteClient::apply_receipt(
  self : RemoteClient,
  receipt : Json,
) -> Result[Unit, String] {
  let applied = match
    browser_json(@client.client_apply_receipt(self.handle, receipt.stringify())) {
    Ok(value) => value
    Err(_) =>
      return Err("操作の受付記録を読み取れませんでした。")
  }
  if !browser_json_bool(applied, "ok") {
    return Err(
      browser_error_text(
        applied, "操作の受付記録がこのリクエストと一致しません。",
      ),
    )
  }
  self.persist()
  Ok(())
}

///|
async fn RemoteClient::receipt_for(
  self : RemoteClient,
  command_id : String,
) -> Result[Json?, String] {
  let path = "/api/v1/commands/" + browser_encode_uri_component(command_id)
  match request_json(path) {
    Err(error) if error.status == 404 => Ok(None)
    Err(error) => Err(error.message)
    Ok(receipt) =>
      match self.apply_receipt(receipt) {
        Ok(_) => Ok(Some(receipt))
        Err(error) => Err(error)
      }
  }
}

///|
fn RemoteClient::pending_ids(self : RemoteClient) -> Array[String] {
  match browser_json(@client.client_pending_ids(self.handle)) {
    Ok(Json::Array(ids)) =>
      ids.map(value => {
        match value {
          Json::String(id) => id
          _ => ""
        }
      })
    _ => []
  }
}

///|
async fn RemoteClient::reconcile_receipts(
  self : RemoteClient,
) -> Result[Unit, String] {
  for command_id in self.pending_ids() {
    match self.receipt_for(command_id) {
      Ok(Some(_)) => ()
      Ok(None) => {
        ignore(@client.client_mark_receipt_missing(self.handle, command_id))
        self.persist()
      }
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn RemoteClient::save_draft(self : RemoteClient, value : String) -> Unit {
  ignore(@client.client_set_draft(self.handle, value))
  self.persist()
}

///|
fn RemoteClient::select(self : RemoteClient, session_id : String?) -> Unit {
  ignore(@client.client_set_selection(self.handle, session_id.unwrap_or("")))
  self.persist()
}

///|
fn RemoteClient::set_scroll_anchor(
  self : RemoteClient,
  value : String?,
) -> Unit {
  ignore(@client.client_set_scroll_anchor(self.handle, value.unwrap_or("")))
  self.persist()
}

///|
fn RemoteClient::set_follow_latest(self : RemoteClient, value : Bool) -> Unit {
  ignore(@client.client_set_follow_latest(self.handle, value.to_string()))
  self.persist()
}

///|
fn RemoteClient::set_text_view(self : RemoteClient, value : Bool) -> Unit {
  ignore(@client.client_set_text_view(self.handle, value.to_string()))
  self.persist()
}

///|
fn RemoteClient::dispose(self : RemoteClient) -> Unit {
  self.persist_now()
  self.close_stream()
  ignore(@client.client_dispose(self.handle))
}
