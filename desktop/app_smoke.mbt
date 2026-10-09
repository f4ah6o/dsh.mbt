///|
async fn desktop_wait_status(
  state : DesktopState,
  status : String,
  timeout_ms : Int,
) -> Result[Unit, String] {
  let deadline = @async.now() + timeout_ms.to_int64()
  while @async.now() < deadline {
    match desktop_pump(state, true) {
      Err(error) => return Err(error)
      Ok(_) => ()
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
  let scale_x = frame.width().to_double() / 1120.0
  let scale_y = frame.height().to_double() / 760.0
  let mut pixels = 0
  let mut y = (18.0 * scale_y).to_int()
  while y < (52.0 * scale_y).to_int() && y < frame.height() {
    let mut x = (254.0 * scale_x).to_int()
    while x < (474.0 * scale_x).to_int() && x < frame.width() {
      let (red, green, blue, _) = match frame.pixel_rgba8(x, y) {
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
  let scale_x = frame.width().to_double() / 1120.0
  let scale_y = frame.height().to_double() / 760.0
  let mut pixels = 0
  let mut y = (96.0 * scale_y).to_int()
  while y < (510.0 * scale_y).to_int() && y < frame.height() {
    let mut x = (260.0 * scale_x).to_int()
    while x < (1100.0 * scale_x).to_int() && x < frame.width() {
      let (red, green, blue, _) = match frame.pixel_rgba8(x, y) {
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
  let scale_x = frame.width().to_double() / 1120.0
  let scale_y = frame.height().to_double() / 760.0
  let mut pixels = 0
  let mut y = (90.0 * scale_y).to_int()
  while y < (126.0 * scale_y).to_int() && y < frame.height() {
    let mut x = (480.0 * scale_x).to_int()
    while x < (680.0 * scale_x).to_int() && x < frame.width() {
      let (red, green, blue, _) = match frame.pixel_rgba8(x, y) {
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
  for _ in 0..<3 {
    match desktop_pump(state, true) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
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
    state.host.set_size(
      state.window,
      previous_width + 60.0,
      previous_height + 40.0,
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
  if !state.resize_seen || state.render_count <= previous_frames {
    return Err("native resize did not produce a second frame")
  }
  match state.host.request_close(state.window) {
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
  state.draft = []
  for character in "Create and verify a durable file." {
    state.draft.push(character)
  }
  state.cursor = state.draft.length()
  state.dirty = true
  for _ in 0..<3 {
    match desktop_pump(state, true) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let frame = match @testing.capture_frame(state.host, state.window) {
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
  for _ in 0..<3 {
    match desktop_pump(state, true) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let transcript_frame = match
    @testing.capture_frame(state.host, state.window) {
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
  state.focused = false
  state.dirty = true
  for _ in 0..<3 {
    match desktop_pump(state, true) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let settings_frame = match @testing.capture_frame(state.host, state.window) {
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
  match state.host.request_close(state.window) {
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
