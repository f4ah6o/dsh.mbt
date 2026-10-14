///|
async fn main {
  @desktop.run(fn() {
    if @env.get_env_var("WAYLAND_DISPLAY") is None &&
      @env.get_env_var("WAYLAND_SOCKET") is None {
      return Err(
        "Linux desktop requires a running Wayland session (WAYLAND_DISPLAY); X11-only sessions are not supported",
      )
    }
    let host = match @native.Host::start() {
      Ok(value) => value
      Err(error) => return Err(error.operation() + ": " + error.code().label())
    }
    Ok({
      backend: host,
      asynchronous_frames: true,
      text_input_events: true,
      control_shortcuts: true,
      focus_changed: fn(window, focused) {
        host.set_direct_keyboard_text(window, focused)
      },
      initialize_window: fn(_window) { Ok(()) },
      read_clipboard: fn() { host.read_clipboard() },
      write_clipboard: fn(text) { host.write_clipboard(text) },
      capture_frame: fn(window) { @testing.capture_frame(host, window) },
      post_test_click: fn(_window, point) {
        if @env.get_env_var("GPUI_NATIVE_E2E") == Some("1") &&
          @env.get_env_var("DSH_DESKTOP_EXTERNAL_INPUT") == Some("1") {
          // Only an external, isolated compositor driver can turn this request
          // into real OS input. No event is synthesized inside the app.
          println("DSH_DESKTOP_INPUT {\"x\":\{point.x()},\"y\":\{point.y()}}")
          @runtime.desktop_flush_output()
          Ok(())
        } else {
          Err(
            @diagnostics.FrameworkError::new(
              @diagnostics.UnsupportedCapability,
              "post_test_click",
              subsystem="dsh-desktop",
              backend="wayland",
            ),
          )
        }
      },
    })
  })
}
