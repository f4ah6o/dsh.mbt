///|
async fn desktop_handle_event(
  state : DesktopState,
  event : @platform.Event,
) -> Unit {
  match event.kind() {
    @platform.Created => state.dirty = true
    @platform.Resized(width=w, height=h) => {
      let width = w
      let height = h
      if state.resize_armed &&
        (
          width != state.resize_baseline_width ||
          height != state.resize_baseline_height
        ) {
        state.resize_seen = true
      }
      state.width = width
      state.height = height
      state.dirty = true
    }
    @platform.ScaleChanged | @platform.FocusChanged(_) => state.dirty = true
    @platform.Input(@primitives.TextInput(text~)) =>
      desktop_insert_text(state, text)
    @platform.Input(@primitives.KeyPressed(key~, modifiers~, repeat=_)) =>
      desktop_handle_key(state, key, modifiers)
    @platform.Input(
      @primitives.PointerButtonPressed(
        position~,
        button=@primitives.Primary,
        ..
      )
    ) => desktop_handle_click(state, position)
    @platform.Input(@primitives.Scroll(position=_, delta~, ..)) => {
      state.scroll_up += delta.y()
      if state.scroll_up < 0.0 {
        state.scroll_up = 0.0
      }
      state.dirty = true
    }
    @platform.CloseRequested | @platform.ExitRequested => {
      // destroy_window invalidates this handle immediately and queues the
      // terminal Destroyed event. Do not query metrics again in this pump.
      state.close_requested = true
      state.dirty = false
      match state.host.destroy_window(state.window) {
        Ok(_) => ()
        Err(error) => state.error_message = desktop_error_text(error)
      }
    }
    @platform.Destroyed => {
      state.done = true
      state.dirty = false
    }
    _ => ()
  }
}

///|
async fn desktop_pump(
  state : DesktopState,
  force_poll : Bool,
) -> Result[Unit, String] {
  let event = match state.host.next_event(timeout_ms=32) {
    Ok(value) => value
    Err(error) => return Err(desktop_error_text(error))
  }
  match event {
    Some(value) =>
      match value.kind() {
        @platform.ExitRequested => desktop_handle_event(state, value)
        _ if value.window() == state.window =>
          desktop_handle_event(state, value)
        _ => ()
      }
    _ => ()
  }
  if !state.close_requested &&
    !state.done &&
    (force_poll || @async.now() - state.last_poll >= 100L) {
    state.last_poll = @async.now()
    desktop_refresh(state)
  }
  if state.dirty && !state.done && !state.close_requested {
    match state.host.window_metrics(state.window) {
      Ok((width, height, scale)) => {
        state.width = width
        state.height = height
        state.scale = scale
      }
      Err(error) => return Err(desktop_error_text(error))
    }
    let draft = desktop_draft_with_caret(state.draft, state.cursor)
    let frame = desktop_scene(
      state.snapshot,
      if state.draft.is_empty() {
        ""
      } else if state.focused {
        draft
      } else {
        desktop_draft_string(state.draft)
      },
      state.sessions,
      state.selected_id,
      state.status_message,
      state.error_message,
      state.width,
      state.height,
      state.scale,
      state.focused,
      state.scroll_up,
    )
    match state.host.present(state.window, frame) {
      Ok(_) => {
        state.render_count += 1
        state.dirty = false
      }
      Err(error) => return Err(desktop_error_text(error))
    }
  }
  // The host poll is a synchronous AppKit call, so explicitly yield to the
  // runtime task group after each bounded poll. Provider/tool effects run in
  // background tasks and otherwise could starve behind an interactive loop.
  @async.sleep(0)
  Ok(())
}

///|
fn desktop_point(x : Double, y : Double) -> @primitives.Point {
  match @primitives.Point::new(x, y) {
    Ok(value) => value
    Err(_) => abort("desktop test pointer is inside the window")
  }
}

///|
fn desktop_post_click(
  state : DesktopState,
  name : String,
) -> Result[Unit, String] {
  let rect = desktop_button_rect(name, state.width, state.height)
  let point = desktop_point(
    (rect.left() + rect.right()) / 2.0,
    (rect.top() + rect.bottom()) / 2.0,
  )
  match state.host.post_test_click(state.window, point) {
    Ok(_) => Ok(())
    Err(error) => Err(desktop_error_text(error))
  }
}
