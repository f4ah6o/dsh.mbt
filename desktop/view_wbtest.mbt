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
      _ => ()
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
fn desktop_assert_scene_budget(scene : @scene.SceneSnapshot) -> Unit raise {
  let mut runs = 0
  for item in scene.items() {
    match item {
      @scene.TextItem(text~, font_size~, bounds~, ..)
      | @scene.TextRunItem(text~, font_size~, bounds~, ..) => {
        runs += 1
        assert_true(font_size <= 32.0)
        assert_true(bounds.size().width() <= 2048.0)
        assert_true(@utf8.encode(text).length() <= 4096)
      }
      _ => ()
    }
  }
  assert_true(runs <= 64)
}

///|
fn desktop_budget_snapshot(messages : Array[Json], auth : Json?) -> Json {
  let session : Map[String, Json] = {
    "id": Json::string("budget-session"),
    "title": Json::string("長い会話"),
    "status": Json::string("completed"),
    "messages": Json::array(messages),
    "todos": Json::array([]),
  }
  let projection : Map[String, Json] = {
    "selected_session": Json::object(session),
    "sessions": Json::array([
      Json::object({
        "id": Json::string("budget-session"),
        "title": Json::string("長い会話"),
      }),
    ]),
  }
  let snapshot : Map[String, Json] = { "projection": Json::object(projection) }
  match auth {
    Some(value) => snapshot["auth"] = value
    None => ()
  }
  Json::object(snapshot)
}

///|
test "native scene text budget bounds a long transcript" {
  let messages : Array[Json] = []
  for index = 0; index < 60; index = index + 1 {
    messages.push({
      "role": Json::string(if index % 2 == 0 { "user" } else { "assistant" }),
      "content": Json::string(
        "長いメッセージ " + index.to_string() + " " + "あ".repeat(120),
      ),
    })
  }
  let scene = desktop_scene(
    desktop_budget_snapshot(messages, None),
    "入力",
    [],
    "budget-session",
    "",
    "",
    1120.0,
    760.0,
    1.0,
    true,
    0.0,
  )
  desktop_assert_scene_budget(scene)
}

///|
test "native scene text budget clips oversized runs" {
  let messages : Array[Json] = [
    {
      "role": Json::string("assistant"),
      "content": Json::string("あ".repeat(5000)),
    },
  ]
  let scene = desktop_scene(
    desktop_budget_snapshot(messages, None),
    "",
    [],
    "budget-session",
    "",
    "",
    1120.0,
    760.0,
    1.0,
    false,
    0.0,
  )
  desktop_assert_scene_budget(scene)
  let clipped = desktop_clip_utf8_bytes("あ".repeat(5000), 4096)
  assert_true(@utf8.encode(clipped).length() <= 4096)
  assert_eq(clipped.length(), 1365)
}

///|
test "native settings scene stays inside the text budget and drops occlusion" {
  let models : Array[Json] = []
  for index = 0; index < 9; index = index + 1 {
    models.push({
      "slug": Json::string("model-" + index.to_string()),
      "display_name": Json::string("モデル " + index.to_string()),
    })
  }
  let auth : Json = {
    "state": Json::string("connected"),
    "provider_choice": Json::string("chatgpt"),
    "models": Json::array(models),
    "selected_model": Json::string("model-0"),
  }
  let messages : Array[Json] = []
  for index = 0; index < 40; index = index + 1 {
    messages.push({
      "role": Json::string("assistant"),
      "content": Json::string(
        "履歴 " + index.to_string() + " " + "い".repeat(80),
      ),
    })
  }
  let scene = desktop_scene(
    desktop_budget_snapshot(messages, Some(auth)),
    "入力",
    [],
    "budget-session",
    "",
    "",
    1120.0,
    760.0,
    1.0,
    false,
    0.0,
    settings_open=true,
    settings_focus=2,
  )
  desktop_assert_scene_budget(scene)
  for item in scene.items() {
    if desktop_scene_is_conversation(item) {
      fail("occluded conversation item id " + item.id().to_string())
    }
  }
}

///|
test "native pending approval scene stays inside the text budget" {
  let session : Json = {
    "id": Json::string("budget-session"),
    "title": Json::string("承認待ち"),
    "status": Json::string("awaiting_approval"),
    "messages": Json::array([
      {
        "role": Json::string("assistant"),
        "content": Json::string("書き込みます"),
      },
    ]),
    "todos": Json::array([]),
    "pending_approval": {
      "call_id": Json::string("call-1"),
      "name": Json::string("write"),
      "arguments": { "file_path": Json::string("a.txt") },
    },
    "approval_revision": Json::number(2.0),
  }
  let snapshot : Json = {
    "projection": {
      "selected_session": session,
      "sessions": Json::array([session]),
    },
  }
  let scene = desktop_scene(
    snapshot,
    "",
    [],
    "budget-session",
    "承認してください",
    "",
    1120.0,
    760.0,
    1.0,
    false,
    0.0,
  )
  desktop_assert_scene_budget(scene)
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
