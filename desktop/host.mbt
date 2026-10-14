///|
/// Platform-owned native host services. The app and its state remain shared.
pub(all) struct Host {
  backend : &@platform.Backend
  asynchronous_frames : Bool
  text_input_events : Bool
  control_shortcuts : Bool
  focus_changed : (@platform.WindowId, Bool) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  initialize_window : (@platform.WindowId) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  read_clipboard : () -> Result[String, @diagnostics.FrameworkError]
  write_clipboard : (String) -> Result[Unit, @diagnostics.FrameworkError]
  capture_frame : (@platform.WindowId) -> Result[
    @testing.FrameCapture,
    @diagnostics.FrameworkError,
  ]
  post_test_click : (@platform.WindowId, @primitives.Point) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
}
