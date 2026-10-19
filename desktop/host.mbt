///|
/// Platform-owned native host services. The app and its state remain shared.
pub(all) struct Host {
  backend : &@platform.Backend
  asynchronous_frames : Bool
  text_input_events : Bool
  control_shortcuts : Bool
  // Only hosts routing all text through Composition suppress direct TextInput.
  composition_owns_text_input : Bool
  supports_text_composition : Bool
  set_text_composition : (@platform.WindowId, Bool) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  set_text_composition_caret : (@platform.WindowId, @primitives.Rect) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  finish_text_composition : (@platform.WindowId, Bool) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  post_test_composition : (@platform.WindowId, @primitives.CompositionEvent) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
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

///|
/// Fail-closed fallback for hosts without a native composition client.
pub fn desktop_unsupported_text_composition(
  _window : @platform.WindowId,
  _enabled : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  Err(
    @diagnostics.FrameworkError::new(
      @diagnostics.UnsupportedCapability,
      "set_text_composition",
      subsystem="dsh-desktop",
      backend="text",
    ),
  )
}

///|
pub fn desktop_unsupported_text_composition_caret(
  _window : @platform.WindowId,
  _caret : @primitives.Rect,
) -> Result[Unit, @diagnostics.FrameworkError] {
  Err(
    @diagnostics.FrameworkError::new(
      @diagnostics.UnsupportedCapability,
      "set_text_composition_caret",
      subsystem="dsh-desktop",
      backend="text",
    ),
  )
}

///|
pub fn desktop_unsupported_finish_text_composition(
  _window : @platform.WindowId,
  _commit : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  Err(
    @diagnostics.FrameworkError::new(
      @diagnostics.UnsupportedCapability,
      "finish_text_composition",
      subsystem="dsh-desktop",
      backend="text",
    ),
  )
}

///|
pub fn desktop_unsupported_post_test_composition(
  _window : @platform.WindowId,
  _event : @primitives.CompositionEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  Err(
    @diagnostics.FrameworkError::new(
      @diagnostics.UnsupportedCapability,
      "post_test_composition",
      subsystem="dsh-desktop",
      backend="text",
    ),
  )
}
