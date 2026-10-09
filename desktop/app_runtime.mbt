///|
fn desktop_selected_session(snapshot : Json) -> Json {
  let projection = desktop_json_field(snapshot, "projection").unwrap_or(
    Json::null(),
  )
  desktop_json_field(projection, "selected_session").unwrap_or(Json::null())
}

///|
fn desktop_session_exists(sessions : Array[Json], id : String) -> Bool {
  sessions.any(session => desktop_json_string(session, "id") == id)
}

///|
async fn desktop_refresh(state : DesktopState) -> Unit {
  let session_id = if state.selected_id == "" {
    None
  } else {
    Some(state.selected_id)
  }
  let snapshot = match state.runtime.snapshot(session_id) {
    Ok(value) => value
    Err(error) => {
      state.error_message = error
      state.dirty = true
      return
    }
  }
  state.snapshot = snapshot
  let projection = desktop_json_field(snapshot, "projection").unwrap_or(
    Json::null(),
  )
  state.sessions = desktop_json_array(projection, "sessions")
  if !desktop_session_exists(state.sessions, state.selected_id) {
    state.selected_id = if state.sessions.is_empty() {
      ""
    } else {
      desktop_json_string(state.sessions[state.sessions.length() - 1], "id")
    }
    if state.selected_id != "" {
      match state.runtime.snapshot(Some(state.selected_id)) {
        Ok(value) => state.snapshot = value
        Err(error) => state.error_message = error
      }
    }
  }
  let selected = desktop_selected_session(state.snapshot)
  let status = desktop_json_string(selected, "status")
  if status == "running" {
    state.status_message = "応答を生成しています"
  } else if status == "awaiting_approval" {
    state.status_message = "ツールの内容を確認して承認してください"
    state.approval_seen = true
  } else if status == "completed" {
    state.status_message = "会話を保存しました"
    state.complete_seen = true
  }
  state.dirty = true
}

///|
async fn desktop_command(
  state : DesktopState,
  operation : String,
  session_id : String?,
  input : Json,
  approval_revision : Int?,
) -> Result[Json, String] {
  let receipt = match
    state.runtime.command(
      operation,
      session_id,
      input,
      approval_revision,
      state.group,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if desktop_json_string(receipt, "status") == "accepted" {
    Ok(receipt)
  } else {
    let error = desktop_json_string(receipt, "error")
    Err(if error == "" { "native command was rejected" } else { error })
  }
}

///|
async fn desktop_create_session(state : DesktopState) -> Unit {
  state.error_message = ""
  let title = "セッション " + (state.sessions.length() + 1).to_string()
  match
    desktop_command(
      state,
      "session_create",
      None,
      Json::object({ "title": Json::string(title) }),
      None,
    ) {
    Err(error) => state.error_message = error
    Ok(receipt) => {
      let result = desktop_json_field(receipt, "result").unwrap_or(Json::null())
      let session = desktop_json_field(result, "session").unwrap_or(result)
      let id = desktop_json_string(session, "id")
      if id == "" {
        state.error_message = "新しいセッション ID を読み取れません"
      } else {
        state.selected_id = id
        state.draft = []
        state.cursor = 0
        state.select_all = false
        state.scroll_up = 0.0
        state.status_message = "新しい会話を開始しました"
      }
    }
  }
  desktop_refresh(state)
}

///|
async fn desktop_send(state : DesktopState) -> Unit {
  let prompt = desktop_draft_string(state.draft).trim()
  if prompt.is_empty() || state.selected_id == "" {
    return
  }
  state.error_message = ""
  match
    desktop_command(
      state,
      "session_send",
      Some(state.selected_id),
      desktop_prompt_payload(prompt.to_owned()),
      None,
    ) {
    Err(error) => state.error_message = error
    Ok(_) => {
      state.draft = []
      state.cursor = 0
      state.select_all = false
      state.scroll_up = 0.0
      state.send_seen = true
      state.status_message = "メッセージを送信しました"
    }
  }
  desktop_refresh(state)
}

///|
async fn desktop_cancel(state : DesktopState) -> Unit {
  if state.selected_id == "" {
    return
  }
  match
    desktop_command(
      state,
      "session_cancel",
      Some(state.selected_id),
      Json::empty_object(),
      None,
    ) {
    Err(error) => state.error_message = error
    Ok(_) => state.status_message = "キャンセルを要求しました"
  }
  desktop_refresh(state)
}

///|
async fn desktop_approve(state : DesktopState, approved : Bool) -> Unit {
  let session = desktop_selected_session(state.snapshot)
  let pending = desktop_json_field(session, "pending_approval").unwrap_or(
    Json::null(),
  )
  let call_id = desktop_json_string(pending, "call_id")
  let revision = match desktop_json_field(session, "approval_revision") {
    Some(Json::Number(value, ..)) if value.to_int().to_double() == value =>
      Some(value.to_int())
    _ => None
  }
  if state.selected_id == "" || call_id == "" || revision is None {
    state.error_message = "承認情報が更新されました。少し待ってから再試行してください"
    state.dirty = true
    return
  }
  match
    desktop_command(
      state,
      "tool_approve",
      Some(state.selected_id),
      Json::object({
        "call_id": Json::string(call_id),
        "approved": approved.to_json(),
      }),
      revision,
    ) {
    Err(error) => state.error_message = error
    Ok(_) =>
      state.status_message = if approved {
        "ツールを承認しました"
      } else {
        "ツールを拒否しました"
      }
  }
  desktop_refresh(state)
}
