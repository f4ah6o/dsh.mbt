///|
async fn main {
  @desktop.run(fn() {
    let host = match @native.Host::start() {
      Ok(value) => value
      Err(error) => return Err(error.operation() + ": " + error.code().label())
    }
    Ok({
      backend: host,
      asynchronous_frames: false,
      text_input_events: false,
      control_shortcuts: false,
      supports_text_composition: true,
      set_text_composition: fn(window, enabled) {
        host.set_text_composition(window, enabled)
      },
      set_text_composition_caret: fn(window, caret) {
        host.set_text_composition_caret(window, caret)
      },
      finish_text_composition: fn(window, commit) {
        host.finish_text_composition(window, commit)
      },
      post_test_composition: fn(window, event) {
        host.post_test_composition(window, event)
      },
      focus_changed: fn(_window, _focused) { Ok(()) },
      initialize_window: fn(_window) { Ok(()) },
      read_clipboard: fn() { host.read_clipboard() },
      write_clipboard: fn(text) { host.write_clipboard(text) },
      capture_frame: fn(window) { @testing.capture_frame(host, window) },
      post_test_click: fn(window, point) { host.post_test_click(window, point) },
    })
  })
}
