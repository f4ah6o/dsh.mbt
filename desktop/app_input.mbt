///|
fn desktop_insert_text(state : DesktopState, text : String) -> Unit {
  let (next, cursor) = desktop_insert_at(
    state.draft,
    state.cursor,
    state.select_all,
    text,
  )
  state.draft = next
  state.cursor = cursor
  state.select_all = false
  state.dirty = true
}

///|
fn desktop_delete_before_cursor(state : DesktopState) -> Unit {
  if state.select_all {
    state.draft = []
    state.cursor = 0
    state.select_all = false
    state.dirty = true
    return
  }
  if state.cursor > 0 && state.cursor <= state.draft.length() {
    ignore(state.draft.remove(state.cursor - 1))
    state.cursor -= 1
    state.dirty = true
  }
}

///|
fn desktop_delete_after_cursor(state : DesktopState) -> Unit {
  if state.select_all {
    state.draft = []
    state.cursor = 0
    state.select_all = false
    state.dirty = true
    return
  }
  if state.cursor >= 0 && state.cursor < state.draft.length() {
    ignore(state.draft.remove(state.cursor))
    state.dirty = true
  }
}

///|
async fn desktop_handle_click(
  state : DesktopState,
  position : @primitives.Point,
) -> Unit {
  state.click_count += 1
  let width = state.width
  let height = state.height
  if desktop_button_rect("new", width, height).contains(position) {
    desktop_create_session(state)
    return
  }
  let selected = desktop_selected_session(state.snapshot)
  let is_awaiting_approval = match
    desktop_json_field(selected, "pending_approval") {
    Some(Json::Object(_)) => true
    _ => false
  }
  if is_awaiting_approval {
    if desktop_button_rect("allow", width, height).contains(position) {
      desktop_approve(state, true)
      return
    }
    if desktop_button_rect("deny", width, height).contains(position) {
      desktop_approve(state, false)
      return
    }
  } else {
    if desktop_button_rect("send", width, height).contains(position) {
      desktop_send(state)
      return
    }
    if desktop_button_rect("cancel", width, height).contains(position) {
      desktop_cancel(state)
      return
    }
  }
  if desktop_button_rect("composer", width, height).contains(position) {
    state.focused = true
    state.dirty = true
    return
  }
  let first_session = if state.sessions.length() > 9 {
    state.sessions.length() - 9
  } else {
    0
  }
  for row_index = 0; row_index < 9; row_index = row_index + 1 {
    let session_index = first_session + row_index
    if session_index < state.sessions.length() &&
      desktop_session_row_rect(row_index).contains(position) {
      state.selected_id = desktop_json_string(
        state.sessions[session_index],
        "id",
      )
      state.scroll_up = 0.0
      state.error_message = ""
      desktop_refresh(state)
      return
    }
  }
}

///|
async fn desktop_handle_key(
  state : DesktopState,
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
) -> Unit {
  state.focused = true
  match desktop_insertable_key(key, modifiers) {
    Some(text) => {
      desktop_insert_text(state, text)
      return
    }
    None => ()
  }
  match key {
    @primitives.Character(text) if modifiers.meta() && text.to_lower() == "v" =>
      match state.host.read_clipboard() {
        Ok(value) => desktop_insert_text(state, value)
        Err(error) => state.error_message = desktop_error_text(error)
      }
    @primitives.Character(text) if modifiers.meta() && text.to_lower() == "a" => {
      state.select_all = true
      state.cursor = state.draft.length()
      state.dirty = true
    }
    @primitives.Character(text) if modifiers.meta() && text.to_lower() == "c" =>
      if state.select_all {
        match state.host.write_clipboard(desktop_draft_string(state.draft)) {
          Ok(_) => state.status_message = "入力をコピーしました"
          Err(error) => state.error_message = desktop_error_text(error)
        }
      }
    @primitives.Character(text) if modifiers.meta() && text.to_lower() == "x" =>
      if state.select_all {
        match state.host.write_clipboard(desktop_draft_string(state.draft)) {
          Ok(_) => {
            state.draft = []
            state.cursor = 0
            state.select_all = false
            state.status_message = "入力を切り取りました"
          }
          Err(error) => state.error_message = desktop_error_text(error)
        }
        state.dirty = true
      }
    @primitives.Enter if modifiers.shift() => desktop_insert_text(state, "\n")
    @primitives.Enter => desktop_send(state)
    @primitives.Backspace => desktop_delete_before_cursor(state)
    @primitives.Delete => desktop_delete_after_cursor(state)
    @primitives.ArrowLeft => {
      if state.cursor > 0 {
        state.cursor -= 1
      }
      state.select_all = false
      state.dirty = true
    }
    @primitives.ArrowRight => {
      if state.cursor < state.draft.length() {
        state.cursor += 1
      }
      state.select_all = false
      state.dirty = true
    }
    @primitives.Home => {
      state.cursor = 0
      state.select_all = false
      state.dirty = true
    }
    @primitives.End => {
      state.cursor = state.draft.length()
      state.select_all = false
      state.dirty = true
    }
    @primitives.PageUp | @primitives.ArrowUp => {
      state.scroll_up += 160.0
      state.dirty = true
    }
    @primitives.PageDown | @primitives.ArrowDown => {
      state.scroll_up -= 160.0
      if state.scroll_up < 0.0 {
        state.scroll_up = 0.0
      }
      state.dirty = true
    }
    @primitives.Escape => {
      if state.draft.length() > 0 {
        state.draft = []
        state.cursor = 0
        state.status_message = "入力をクリアしました"
      } else if desktop_json_string(
          desktop_selected_session(state.snapshot),
          "status",
        ) ==
        "running" {
        desktop_cancel(state)
      }
      state.select_all = false
      state.dirty = true
    }
    _ => ()
  }
}
