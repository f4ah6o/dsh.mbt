///|
fn desktop_text_char_count(text : String) -> Int32 {
  let mut count = 0
  for _ in text {
    count += 1
  }
  count
}

///|
fn desktop_composition_view_text(
  draft : Array[Char],
  cursor : Int32,
  focused : Bool,
  composition : DesktopComposition?,
) -> String {
  match composition {
    None =>
      if focused {
        desktop_draft_with_caret(draft, cursor)
      } else {
        desktop_draft_string(draft)
      }
    Some(active) => {
      let output = StringBuilder()
      let start = active.start
      let after = start + active.replaced
      for index = 0; index < start && index < draft.length(); index = index + 1 {
        output.write_char(draft[index])
      }
      output.write_string(active.preedit)
      output.write_char('|')
      for index = after; index < draft.length(); index = index + 1 {
        output.write_char(draft[index])
      }
      output.to_string()
    }
  }
}

///|
fn desktop_composition_text(state : DesktopState) -> String {
  desktop_composition_view_text(
    state.draft,
    state.cursor,
    state.focused,
    state.composition,
  )
}

///|
fn desktop_composition_commit_draft(
  draft : Array[Char],
  composition : DesktopComposition,
  text : String,
) -> (Array[Char], Int32)? {
  let next : Array[Char] = []
  for index = 0
      index < composition.start && index < draft.length()
      index = index + 1 {
    next.push(draft[index])
  }
  let mut inserted = 0
  for character in text {
    next.push(character)
    inserted += 1
  }
  let after = composition.start + composition.replaced
  for index = after; index < draft.length(); index = index + 1 {
    next.push(draft[index])
  }
  if next.length() > 16000 {
    None
  } else {
    Some((next, composition.start + inserted))
  }
}

///|
fn desktop_line_caret_column(line : String) -> Int32 {
  let mut column = 0
  for character in line {
    if character == '|' {
      return column
    }
    column += 1
  }
  column
}

///|
fn desktop_preedit_columns(text : String) -> Int32 {
  let mut columns = 0
  for character in text {
    if character == '\n' {
      columns = 0
    } else {
      columns += 1
    }
  }
  columns
}

///|
fn desktop_composer_layout(
  text : String,
  composer_width : Double,
) -> (Array[String], Int32, Int32) {
  let columns = if composer_width < 20.0 {
    1
  } else {
    (composer_width / 12.0).to_int()
  }
  let lines = @ui.wrap_text(desktop_renderable_text(text, 4000), columns)
  let mut caret_line = 0
  let mut caret_column = 0
  for index, line in lines {
    if line.contains("|") {
      caret_line = index
      caret_column = desktop_line_caret_column(line)
      break
    }
  }
  (lines, caret_line, caret_column)
}

///|
fn desktop_composer_caret_rect(state : DesktopState) -> @primitives.Rect? {
  let composer = desktop_button_rect("composer", state.width, state.height)
  let composer_width = composer.right() - composer.left() - 28.0
  let text = desktop_composition_text(state)
  let (lines, caret_line, caret_column) = desktop_composer_layout(
    text, composer_width,
  )
  ignore(lines)
  let first_line = if caret_line > 2 { caret_line - 2 } else { 0 }
  let line_y = composer.top() +
    10.0 +
    (caret_line - first_line).to_double() * 18.0
  let x = composer.left() + 14.0 + caret_column.to_double() * 12.0
  let bounded_x = if x < composer.left() + 14.0 {
    composer.left() + 14.0
  } else if x + 12.0 > composer.right() - 14.0 {
    composer.right() - 26.0
  } else {
    x
  }
  let bounded_y = if line_y < composer.top() + 10.0 {
    composer.top() + 10.0
  } else if line_y + 18.0 > composer.bottom() - 4.0 {
    composer.bottom() - 22.0
  } else {
    line_y
  }
  match @primitives.Rect::new(bounded_x, bounded_y, 12.0, 18.0) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn desktop_sync_composition_caret(state : DesktopState) -> Unit {
  if !state.host.supports_text_composition || !state.composition_enabled {
    return
  }
  match desktop_composer_caret_rect(state) {
    None => ()
    Some(caret) =>
      match (state.host.set_text_composition_caret)(state.window, caret) {
        Ok(_) => ()
        Err(error) => state.error_message = desktop_error_text(error)
      }
  }
}

///|
fn desktop_sync_composition_enabled(state : DesktopState) -> Unit {
  if !state.host.supports_text_composition {
    return
  }
  let requested = @env.get_env_var("DSH_DESKTOP_IME") == Some("1") ||
    @env.get_env_var("GPUI_NATIVE_E2E") == Some("1")
  let enabled = state.focused && !state.settings_open && requested
  if enabled == state.composition_enabled {
    if enabled {
      desktop_sync_composition_caret(state)
    }
    return
  }
  match (state.host.set_text_composition)(state.window, enabled) {
    Ok(_) => {
      state.composition_enabled = enabled
      if !enabled {
        state.composition = None
      } else {
        desktop_sync_composition_caret(state)
      }
    }
    Err(error) => {
      state.composition_enabled = false
      state.composition = None
      state.error_message = desktop_error_text(error)
    }
  }
}

///|
fn desktop_set_focused(state : DesktopState, focused : Bool) -> Unit {
  if state.focused == focused {
    desktop_sync_composition_enabled(state)
    return
  }
  state.focused = focused
  if !focused {
    state.composition = None
  }
  desktop_sync_composition_enabled(state)
  state.dirty = true
}

///|
fn desktop_begin_composition(state : DesktopState) -> Unit {
  if state.composition is Some(_) {
    return
  }
  let start = if state.select_all { 0 } else { state.cursor }
  let replaced = if state.select_all { state.draft.length() } else { 0 }
  state.select_all = false
  state.composition = Some({
    start,
    replaced,
    preedit: "",
    cursor_utf16: 0,
    send_after_commit: false,
  })
  state.dirty = true
}

///|
fn desktop_update_composition(
  state : DesktopState,
  text : String,
  cursor_utf16 : Int32,
) -> Unit {
  if text.length() == 0 {
    desktop_cancel_composition(state)
    return
  }
  if desktop_text_char_count(text) > 1024 {
    state.error_message = "入力中の文字列が長すぎるため、変換を中止しました"
    desktop_finish_composition(state, false)
    return
  }
  if state.composition is None {
    desktop_begin_composition(state)
  }
  let bounded_cursor = if cursor_utf16 < 0 {
    0
  } else if cursor_utf16 > text.length() {
    text.length()
  } else {
    cursor_utf16
  }
  match state.composition {
    Some(composition) => {
      state.composition = Some({
        start: composition.start,
        replaced: composition.replaced,
        preedit: text,
        cursor_utf16: bounded_cursor,
        send_after_commit: composition.send_after_commit,
      })
      state.dirty = true
      desktop_sync_composition_caret(state)
    }
    None => ()
  }
}

///|
fn desktop_cancel_composition(state : DesktopState) -> Unit {
  if state.composition is Some(_) {
    state.composition = None
    state.dirty = true
  }
}

///|
async fn desktop_commit_composition(
  state : DesktopState,
  text : String,
) -> Unit {
  let composition = match state.composition {
    None => {
      desktop_insert_text(state, text)
      return
    }
    Some(value) => value
  }
  match desktop_composition_commit_draft(state.draft, composition, text) {
    None => {
      state.error_message = "入力を確定できませんでした: 上限を超えています"
      desktop_cancel_composition(state)
      return
    }
    Some((next, cursor)) => {
      state.draft = next
      state.cursor = cursor
    }
  }
  state.select_all = false
  state.composition = None
  state.dirty = true
  if composition.send_after_commit {
    desktop_send(state)
  } else {
    desktop_sync_composition_caret(state)
  }
}

///|
fn desktop_finish_composition(state : DesktopState, commit : Bool) -> Unit {
  if state.composition is None {
    return
  }
  match (state.host.finish_text_composition)(state.window, commit) {
    Ok(_) =>
      // Cancelling is terminal even if the host publishes no event (for
      // example when AppKit already dropped its marked text). Keep a commit
      // pending until its text arrives.
      if !commit {
        desktop_cancel_composition(state)
      }
    Err(error) => {
      state.error_message = desktop_error_text(error)
      desktop_cancel_composition(state)
    }
  }
}

///|
async fn desktop_handle_composition(
  state : DesktopState,
  event : @primitives.CompositionEvent,
) -> Unit {
  if state.settings_open || !state.focused {
    return
  }
  if !state.composition_enabled {
    return
  }
  match event {
    @primitives.Start => desktop_begin_composition(state)
    @primitives.Update(text~, cursor_utf16~) =>
      desktop_update_composition(state, text, cursor_utf16)
    @primitives.Commit(text~) => desktop_commit_composition(state, text)
    @primitives.Cancel => desktop_cancel_composition(state)
  }
}
