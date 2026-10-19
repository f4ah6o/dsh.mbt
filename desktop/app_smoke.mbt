///|
async fn desktop_wait_status(
  state : DesktopState,
  status : String,
  timeout_ms : Int32,
) -> Result[Unit, String] {
  let deadline = @async.now() + timeout_ms.to_int64()
  while @async.now() < deadline {
    match desktop_pump(state, true) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if state.done {
      return Err("native window closed while awaiting session status")
    }
    if desktop_json_string(desktop_selected_session(state.snapshot), "status") ==
      status {
      return Ok(())
    }
  }
  Err(
    "timed out waiting for session status " +
    status +
    "; current=" +
    desktop_json_string(desktop_selected_session(state.snapshot), "status") +
    "; native_clicks=" +
    state.click_count.to_string() +
    "; ui_error=" +
    state.error_message,
  )
}

///|
fn desktop_has_completed_answer(session : Json) -> Bool {
  for message in desktop_json_array(session, "messages") {
    if desktop_json_string(message, "role") == "assistant" &&
      desktop_json_string(message, "content").contains(
        "Offline demo finished after the approved workspace write",
      ) {
      return true
    }
  }
  false
}

///|
fn desktop_frame_has_japanese_heading(
  frame : @testing.FrameCapture,
) -> Result[Bool, String] {
  // The shared desktop layout uses absolute DIP coordinates (not a uniform
  // scale of 1120x760), so probe the design rectangle and clamp it to the
  // logical frame. A smaller window still renders the same header at x=264.
  let right = (frame.width().to_double() / frame.scale()).to_int().min(474)
  let bottom = (frame.height().to_double() / frame.scale()).to_int().min(52)
  let mut pixels = 0
  let mut y = 18
  while y < bottom {
    let mut x = 254
    while x < right {
      let (red, green, blue, _) = match
        frame.pixel_rgba8_logical(x.to_double(), y.to_double()) {
        Ok(value) => value
        Err(error) => return Err(desktop_error_text(error))
      }
      if red < 100 && green < 110 && blue < 125 {
        pixels += 1
      }
      x += 1
    }
    y += 1
  }
  Ok(pixels > 8)
}

///|
fn desktop_frame_has_transcript(
  frame : @testing.FrameCapture,
) -> Result[Bool, String] {
  let right = (frame.width().to_double() / frame.scale()).to_int().min(1100)
  let bottom = (frame.height().to_double() / frame.scale()).to_int().min(510)
  let mut pixels = 0
  let mut y = 96
  while y < bottom {
    let mut x = 260
    while x < right {
      let (red, green, blue, _) = match
        frame.pixel_rgba8_logical(x.to_double(), y.to_double()) {
        Ok(value) => value
        Err(error) => return Err(desktop_error_text(error))
      }
      if red < 100 && green < 110 && blue < 125 {
        pixels += 1
      }
      x += 1
    }
    y += 1
  }
  Ok(pixels > 40)
}

///|
fn desktop_frame_has_settings(
  frame : @testing.FrameCapture,
) -> Result[Bool, String] {
  // "ChatGPT" is drawn at x=480, y=92 in the shared absolute layout. Clamp to
  // the logical frame instead of assuming a proportional 1120x760 scale.
  let right = (frame.width().to_double() / frame.scale()).to_int().min(680)
  let bottom = (frame.height().to_double() / frame.scale()).to_int().min(126)
  let mut pixels = 0
  let mut y = 90
  while y < bottom {
    let mut x = 480
    while x < right {
      let (red, green, blue, _) = match
        frame.pixel_rgba8_logical(x.to_double(), y.to_double()) {
        Ok(value) => value
        Err(error) => return Err(desktop_error_text(error))
      }
      if red < 100 && green < 110 && blue < 125 {
        pixels += 1
      }
      x += 1
    }
    y += 1
  }
  Ok(pixels > 8)
}

///|
async fn desktop_run_smoke(state : DesktopState) -> Result[Unit, String] {
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if state.render_count < 1 {
    return Err("initial native window frame was not presented")
  }
  let previous_width = state.width
  let previous_height = state.height
  let previous_frames = state.render_count
  state.resize_armed = true
  state.resize_baseline_width = previous_width
  state.resize_baseline_height = previous_height
  match
    state.host.backend.set_size(
      state.window,
      previous_width - 60.0,
      previous_height - 40.0,
    ) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  let resize_deadline = @async.now() + 5000L
  while !state.resize_seen && @async.now() < resize_deadline {
    match desktop_pump(state, false) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if !state.resize_seen {
    return Err("native resize did not produce a resized event")
  }
  // A Resized event marks the scene dirty, but an earlier asynchronous frame
  // can still make present return Busy. Keep pumping until a newly submitted
  // frame completes rather than treating the resize notification as a frame.
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if state.render_count <= previous_frames {
    return Err("native resize did not produce a second frame")
  }
  match state.host.backend.request_close(state.window) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  let close_deadline = @async.now() + 5000L
  while !state.done && @async.now() < close_deadline {
    match desktop_pump(state, false) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if !state.done {
    return Err("native smoke did not receive terminal Destroyed event")
  }
  println(
    "DSH_DESKTOP_SMOKE {\"frame\":true,\"resized\":true,\"close_requested\":true,\"destroyed\":true}",
  )
  Ok(())
}

///|
async fn desktop_verify_persisted_reload(
  config : DesktopConfig,
  session_id : String,
) -> Result[Unit, String] {
  let runtime = match
    @runtime.NativeDesktop::open(
      config.data_dir,
      config.workspace,
      demo=true,
      allow_shell=false,
      mode=config.mode,
      model=config.model,
      base_url=config.base_url,
      max_retries=config.max_retries,
      hooks_config_path=config.hooks_config_path,
      hooks_plugin_root=config.hooks_plugin_root,
      hooks_project_dir=config.hooks_project_dir,
      hooks_dialect=config.hooks_dialect,
      hooks_model=config.hooks_model,
    ) {
    Ok(value) => value
    Err(error) =>
      return Err("runtime could not reload persisted offline session: " + error)
  }
  let snapshot = match runtime.snapshot(Some(session_id)) {
    Ok(value) => value
    Err(error) => {
      ignore(runtime.close())
      return Err(error)
    }
  }
  let selected = desktop_selected_session(snapshot)
  let close_result = runtime.close()
  if close_result is Err(error) {
    return Err("reloaded native runtime could not shut down cleanly: " + error)
  }
  if desktop_json_string(selected, "status") != "completed" ||
    !desktop_has_completed_answer(selected) {
    return Err("completed transcript did not survive runtime restart")
  }
  Ok(())
}

///|
async fn desktop_wait_composition(
  state : DesktopState,
  active : Bool,
  timeout_ms : Int32,
) -> Result[Unit, String] {
  let deadline = @async.now() + timeout_ms.to_int64()
  while @async.now() < deadline {
    match desktop_pump(state, false) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    if state.done {
      return Err("native window closed while awaiting text composition")
    }
    if (state.composition is Some(_)) == active {
      return Ok(())
    }
  }
  Err(
    if active {
      "timed out waiting for text composition to start"
    } else {
      "timed out waiting for text composition to finish"
    },
  )
}

///|
async fn desktop_run_offline_composition(
  state : DesktopState,
) -> Result[Unit, String] {
  if !state.host.supports_text_composition {
    return Ok(())
  }
  desktop_set_focused(state, true)
  match
    (state.host.post_test_composition)(
      state.window,
      @primitives.Update(text="にほんご", cursor_utf16=4),
    ) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_wait_composition(state, true, 10000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if desktop_composer_caret_rect(state) is None {
    return Err("composition did not produce a candidate caret rectangle")
  }
  state.dirty = true
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    (state.host.post_test_composition)(
      state.window,
      @primitives.Commit(text="日本語"),
    ) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_wait_composition(state, false, 10000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if desktop_draft_string(state.draft) != "日本語" {
    return Err("committed IME text did not reach the draft")
  }
  state.draft = []
  state.cursor = 0
  state.dirty = true
  match
    (state.host.post_test_composition)(
      state.window,
      @primitives.Update(text="にほんご", cursor_utf16=4),
    ) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_wait_composition(state, true, 10000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match (state.host.post_test_composition)(state.window, @primitives.Cancel) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_wait_composition(state, false, 10000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if !state.draft.is_empty() {
    return Err("cancelled IME preedit mutated the draft")
  }
  state.composition_seen = true
  state.draft = []
  state.cursor = 0
  state.dirty = true
  Ok(())
}

///|
async fn desktop_run_offline_e2e(
  state : DesktopState,
) -> Result[String, String] {
  if @env.get_env_var("GPUI_NATIVE_E2E") != Some("1") {
    return Err(
      "offline E2E requires a GPUI test-hook build and GPUI_NATIVE_E2E=1",
    )
  }
  desktop_create_session(state)
  if state.error_message != "" || state.selected_id == "" {
    return Err(
      "cannot create native offline demo session: " + state.error_message,
    )
  }
  let session_id = state.selected_id
  match desktop_run_offline_composition(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  state.draft = []
  for character in "Create and verify a durable file." {
    state.draft.push(character)
  }
  state.cursor = state.draft.length()
  state.dirty = true
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let frame = match (state.host.capture_frame)(state.window) {
    Ok(value) => value
    Err(error) => return Err(desktop_error_text(error))
  }
  match frame.write_ppm(state.config.frame_output + ".initial.ppm") {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_frame_has_japanese_heading(frame) {
    Ok(true) => ()
    Ok(false) =>
      return Err("owned GPUI frame contains no bright Japanese header pixels")
    Err(error) => return Err(error)
  }
  match desktop_post_click(state, "send") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match desktop_wait_status(state, "awaiting_approval", 20000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match @env.get_env_var("DSH_DESKTOP_E2E_TEXT") {
    Some(expected) => {
      let messages = desktop_json_array(
        desktop_selected_session(state.snapshot),
        "messages",
      )
      if !messages.any(message => {
          desktop_json_string(message, "role") == "user" &&
          desktop_json_string(message, "content") == expected
        }) {
        return Err("real keyboard input did not produce the expected prompt")
      }
    }
    None => ()
  }
  if state.click_count < 1 || !state.send_seen || !state.approval_seen {
    return Err("send click did not reach the native session approval state")
  }
  match desktop_post_click(state, "allow") {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match desktop_wait_status(state, "completed", 20000) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if state.click_count < 2 {
    return Err("allow click did not reach the native event route")
  }
  let completed = desktop_selected_session(state.snapshot)
  if !desktop_has_completed_answer(completed) || !state.complete_seen {
    return Err("approved demo answer is absent from the native transcript")
  }
  if !(@fs.exists(state.config.workspace + "/native-demo.txt") catch {
      _ => false
    }) {
    return Err("approved demo did not write the expected workspace file")
  }
  state.dirty = true
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let transcript_frame = match (state.host.capture_frame)(state.window) {
    Ok(value) => value
    Err(error) => return Err(desktop_error_text(error))
  }
  match transcript_frame.write_ppm(state.config.frame_output) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_frame_has_transcript(transcript_frame) {
    Ok(true) => ()
    Ok(false) =>
      return Err("owned GPUI frame contains no completed transcript pixels")
    Err(error) => return Err(error)
  }
  state.settings_open = true
  state.settings_focus = 1
  desktop_set_focused(state, false)
  state.dirty = true
  match desktop_flush_frame(state) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let settings_frame = match (state.host.capture_frame)(state.window) {
    Ok(value) => value
    Err(error) => return Err(desktop_error_text(error))
  }
  match settings_frame.write_ppm(state.config.frame_output + ".settings.ppm") {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  match desktop_frame_has_settings(settings_frame) {
    Ok(true) => ()
    Ok(false) =>
      return Err("owned GPUI frame contains no ChatGPT Settings heading")
    Err(error) => return Err(error)
  }
  match state.host.backend.request_close(state.window) {
    Ok(_) => ()
    Err(error) => return Err(desktop_error_text(error))
  }
  let close_deadline = @async.now() + 5000L
  while !state.done && @async.now() < close_deadline {
    match desktop_pump(state, false) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if !state.done {
    return Err("native window did not complete close and destroy lifecycle")
  }
  Ok(session_id)
}

///|
async fn desktop_flush_frame(state : DesktopState) -> Result[Unit, String] {
  let target = state.render_count + 1
  state.dirty = true
  let deadline = @async.now() + 10000L
  while @async.now() < deadline {
    match desktop_pump(state, false) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if state.done {
      return Err("native window closed before frame completion")
    }
    if state.render_count >= target &&
      (!state.host.asynchronous_frames || state.frame_completed_count >= target) {
      return Ok(())
    }
  }
  Err("native frame did not complete before the deadline")
}
