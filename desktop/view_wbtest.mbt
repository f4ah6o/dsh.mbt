///|
test "native scene preserves the host viewport and bounds oversized text runs" {
  let narrow = desktop_scene(
    Json::empty_object(),
    "",
    [],
    "",
    "",
    "",
    200.0,
    150.0,
    1.0,
    false,
    0.0,
  )
  assert_eq(narrow.viewport().size().width(), 200.0)
  assert_eq(narrow.viewport().size().height(), 150.0)
  let large = desktop_scene(
    Json::empty_object(),
    "",
    [],
    "",
    "",
    "",
    4000.0,
    2400.0,
    1.0,
    false,
    0.0,
  )
  for item in large.items() {
    match item {
      @scene.TextItem(bounds~, ..) =>
        assert_true(bounds.size().width() <= 2048.0)
      @scene.TextRunItem(bounds~, ..) =>
        assert_true(bounds.size().width() <= 2048.0)
      @scene.QuadItem(..) => ()
    }
  }
}
