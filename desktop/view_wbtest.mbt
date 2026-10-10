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

///|
test "native desktop transcript renders the session todo list" {
  let session : Json = {
    "todos": [
      { "content": "Implement feature", "status": "in_progress" },
      { "content": "Verify", "status": "completed" },
    ],
    "messages": [{ "role": "assistant", "content": "Working" }],
  }
  let blocks = desktop_blocks(session, 1200.0)
  assert_eq(blocks[0].label, "タスク")
  assert_eq(blocks[0].lines, ["[~] Implement feature", "[x] Verify"])
  assert_eq(blocks[1].label, "アシスタント")
  let empty = desktop_blocks({ "todos": [], "messages": [] }, 1200.0)
  assert_eq(empty[0].label, "タスク")
  assert_eq(empty[0].lines, ["タスクはありません。"])
}

///|
test "native desktop labels hook context separately from user input" {
  let session : Json = {
    "messages": [
      {
        "role": "user",
        "content": "hook detail",
        "source": { "kind": "hooks-claude-code" },
        "display_label": "フック補足",
      },
    ],
  }
  let blocks = desktop_blocks(session, 1200.0)
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].label, "フック補足")
  assert_eq(blocks[0].lines.join(""), "hook detail")
}
