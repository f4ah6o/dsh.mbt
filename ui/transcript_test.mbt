///|
fn parse(source : String) -> Json {
  @json.parse(source) catch {
    _ => abort("invalid test JSON")
  }
}

///|
fn scene_text(source : String) -> Array[String] {
  let scene = parse(source)
  let result : Array[String] = []
  match scene {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(items)) =>
          for item in items {
            if item is Json::Object(value) {
              if value.get("text") is Some(Json::String(text)) {
                result.push(text)
              }
            }
          }
        _ => ()
      }
    _ => ()
  }
  result
}

///|
test "wrapping preserves scalar pairs and explicit line breaks" {
  assert_eq(@ui.wrap_text("A😀日\r\nB", 1), ["A", "😀", "日", "B"])
  assert_eq(@ui.wrap_text("e\u0301x", 1), ["e\u0301", "x"])
  assert_eq(@ui.wrap_text("👩‍💻x", 1), ["👩‍💻", "x"])
  assert_eq(@ui.wrap_text("", 0), [""])
  assert_eq(@ui.wrap_text("the session completed through MoonBit", 10), [
    "the ", "session ", "completed ", "through ", "MoonBit",
  ])
}

///|
test "mobile layout measures more lines than desktop without losing text" {
  let snapshot = parse(
    "{\"messages\":[{\"role\":\"assistant\",\"content\":\"A fairly long response with many words is wrapped by the MoonBit layout for the current viewport.\"}]}",
  )
  assert_true(@ui.measure(snapshot, 320) > @ui.measure(snapshot, 900))
  let rendered = @ui.render(snapshot, 320, 1000)
  let text = scene_text(rendered)
  assert_eq(text[0], "アシスタント")
  assert_eq(
    text[1:].to_owned().join(""),
    "A fairly long response with many words is wrapped by the MoonBit layout for the current viewport.",
  )
}

///|
test "viewport painting clamps large scroll offsets to the final message" {
  let snapshot = parse(
    "{\"_ui_scroll_top\":100000,\"messages\":[{\"role\":\"user\",\"content\":\"first\"},{\"role\":\"assistant\",\"content\":\"tail\"}]}",
  )
  let text = scene_text(@ui.render(snapshot, 500, 100))
  assert_true(text.contains("tail"))
  assert_false(text.contains("first"))
}

///|
test "reasoning tool requests and tool results are rendered but system prompts are hidden" {
  let snapshot = parse(
    "{\"messages\":[{\"role\":\"system\",\"content\":\"private system instructions\"},{\"role\":\"assistant\",\"content\":\"answer\",\"reasoning\":\"reason\",\"tool_calls\":[{\"name\":\"read_file\",\"id\":\"call_1\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"}]},{\"role\":\"tool\",\"content\":\"file contents\"}]}",
  )
  let text = scene_text(@ui.render(snapshot, 1000, 1000))
  assert_true(text.contains("推論"))
  assert_true(text.contains("ツール要求 · read_file"))
  assert_true(text.contains("file contents"))
  assert_false(text.contains("private system instructions"))
}

///|
test "native transcript shows the durable todo projection before messages" {
  let snapshot = parse(
    "{\"todos\":[{\"content\":\"Implement feature\",\"status\":\"in_progress\"},{\"content\":\"Verify\",\"status\":\"completed\"}],\"messages\":[{\"role\":\"assistant\",\"content\":\"Working\"}]}",
  )
  let text = scene_text(@ui.render(snapshot, 800, 1200))
  assert_eq(text[0], "タスク")
  assert_true(text.contains("[~] Implement feature"))
  assert_true(text.contains("[x] Verify"))
  assert_true(text.contains("Working"))
  let empty = scene_text(
    @ui.render(parse("{\"todos\":[],\"messages\":[]}"), 800, 600),
  )
  assert_eq(empty[0], "タスク")
  assert_true(empty.contains("タスクはありません。"))
}

///|
test "provisional transcript blocks announce writing and partial status" {
  let snapshot = parse(
    "{\"messages\":[{\"role\":\"assistant\",\"reasoning\":\"thinking\",\"content\":\"draft\",\"provisional\":true,\"stream_status\":\"partial\"}]}",
  )
  let text = scene_text(@ui.render(snapshot, 500, 800))
  assert_true(text.contains("推論 · 一部表示"))
  assert_true(text.contains("アシスタント · 一部表示"))
}

///|
test "hook context transcript rows are labeled separately from user input" {
  let snapshot = parse(
    "{\"messages\":[{\"role\":\"user\",\"content\":\"first hook\\nsecond hook\",\"source\":{\"kind\":\"hooks-claude-code\"},\"display_label\":\"フック補足\"}]}",
  )
  let text = scene_text(@ui.render(snapshot, 500, 800))
  assert_true(text.contains("フック補足"))
  assert_true(text.contains("first hook"))
  assert_true(text.contains("second hook"))
  assert_false(text.contains("あなた"))
}

///|
test "render is deterministic and does not mutate a session snapshot" {
  let snapshot = parse(
    "{\"id\":\"session-1\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}",
  )
  let original = snapshot.stringify()
  let first = @ui.render(snapshot, 400, 300)
  assert_eq(first, @ui.render(snapshot, 400, 300))
  assert_eq(snapshot.stringify(), original)
  ignore(parse(@ui.render(snapshot, 0, 0)))
}

///|
test "long whitespace runs stay within the scene text budget" {
  let source = StringBuilder()
  for _ in 0..<70000 {
    source.write_string(" ")
  }
  let text = source.to_string()
  let lines = @ui.wrap_text(text, 20)
  assert_eq(lines.join(""), text)
  for line in lines {
    assert_true(line.length() <= 21)
  }
}
