///|
/// Windows-only font prerequisite. A missing Japanese system font is a
/// failure, not a skipped pass: the GUI gate must not claim a Japanese frame
/// it cannot render.
#cfg(platform="windows")
test "windows Japanese font is measurable and admitted" {
  let document = match @text.TextDocument::new("日本語") {
    Ok(value) => value
    Err(_) =>
      fail(
        "Japanese font prerequisite not met: TextDocument rejected 日本語",
      )
  }
  let measurement = match @windows_text.measure(document, "Yu Gothic", 16.0) {
    Ok(value) => value
    Err(_) => fail("Japanese font prerequisite not met: measured layout failed")
  }
  assert_true(measurement.logical_rect().size().width() > 0.0)
  assert_eq(measurement.unknown_glyph_count(), 0)
  let origin = match @primitives.Point::new(0.0, 0.0) {
    Ok(value) => value
    Err(_) => fail("Japanese font prerequisite not met: invalid origin")
  }
  let clip = match @primitives.Rect::new(0.0, 0.0, 200.0, 32.0) {
    Ok(value) => value
    Err(_) => fail("Japanese font prerequisite not met: invalid clip")
  }
  match @windows_text.admit_scene_text_run_at(document, 16.0, origin, clip) {
    Ok(_) => ()
    Err(_) => fail("Japanese font prerequisite not met: scene admission failed")
  }
}
