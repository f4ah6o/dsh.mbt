///|
priv struct DesktopBlock {
  label : String
  role : String
  lines : Array[String]
}

///|
fn desktop_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match
    @primitives.Rect::new(
      x,
      y,
      if width < 0.0 {
        0.0
      } else {
        width
      },
      if height < 0.0 {
        0.0
      } else {
        height
      },
    ) {
    Ok(value) => value
    Err(_) => abort("desktop geometry must be finite and non-negative")
  }
}

///|
fn desktop_color(red : Int, green : Int, blue : Int) -> @primitives.Color {
  match @primitives.Color::rgba(red, green, blue, 255) {
    Ok(value) => value
    Err(_) => abort("desktop palette channels must be valid")
  }
}

///|
fn desktop_json_field(value : Json, name : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn desktop_json_string(value : Json, name : String) -> String {
  match desktop_json_field(value, name) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn desktop_json_array(value : Json, name : String) -> Array[Json] {
  match desktop_json_field(value, name) {
    Some(Json::Array(values)) => values
    _ => []
  }
}

///|
fn desktop_clipboard_supported_codepoint(value : Int) -> Bool {
  (value >= 0x20 && value <= 0x7e) ||
  (value >= 0xa0 && value <= 0x024f) ||
  value == 0x09 ||
  value == 0x0a ||
  value == 0x0d ||
  value == 0x25a1 ||
  value == 0xfffd ||
  (value >= 0x0300 && value <= 0x036f) ||
  (value >= 0x3000 && value <= 0x30ff) ||
  (value >= 0x31f0 && value <= 0x31ff) ||
  (value >= 0x3400 && value <= 0x4dbf) ||
  (value >= 0x4e00 && value <= 0x9fff) ||
  (value >= 0xf900 && value <= 0xfaff) ||
  (value >= 0xff00 && value <= 0xffef)
}

///|
/// GPUI's current CoreText renderer deliberately reports unsupported and
/// color glyphs as errors. Keep external/provider text renderable by replacing
/// codepoints outside the bounded grayscale font set with a visible square.
fn desktop_renderable_text(source : String, limit : Int) -> String {
  let output = StringBuilder()
  let mut kept = 0
  let mut clipped = false
  for character in source {
    if kept >= limit {
      clipped = true
      break
    }
    if character == '\n' || character == '\r' || character == '\t' {
      output.write_char(character)
    } else if desktop_clipboard_supported_codepoint(character.to_int()) {
      output.write_char(character)
    } else {
      output.write_char('□')
    }
    kept += 1
  }
  if clipped {
    output.write_string("...")
  }
  output.to_string()
}

///|
/// GPUI text scene items are single-line CoreText runs. Normalize externally
/// supplied labels and messages at the final boundary so embedded line breaks
/// cannot make present fail; transcript paragraphs are wrapped before this.
fn desktop_renderable_single_line(source : String, limit : Int) -> String {
  let output = StringBuilder()
  let mut kept = 0
  let mut clipped = false
  let mut previous_cr = false
  for character in source {
    if kept >= limit {
      clipped = true
      break
    }
    kept += 1
    if character == '\r' {
      output.write_char(' ')
      previous_cr = true
    } else if character == '\n' {
      if !previous_cr {
        output.write_char(' ')
      }
      previous_cr = false
    } else if character == '\t' {
      output.write_char(' ')
      previous_cr = false
    } else {
      output.write_char(character)
      previous_cr = false
    }
  }
  if clipped {
    output.write_string("...")
  }
  desktop_renderable_text(output.to_string(), limit + 3)
}

///|
fn desktop_add_quad(
  items : Array[@scene.SceneItem],
  id : UInt64,
  bounds : @primitives.Rect,
  color : @primitives.Color,
  clip_id : Int?,
) -> Unit {
  match
    @scene.SceneItem::quad(
      id,
      bounds,
      color,
      @scene.AffineTransform::identity(),
      1.0,
      clip_id,
    ) {
    Ok(item) => items.push(item)
    Err(_) => ()
  }
}

///|
fn desktop_add_text(
  items : Array[@scene.SceneItem],
  id : UInt64,
  x : Double,
  y : Double,
  width : Double,
  font_size : Double,
  text : String,
  color : @primitives.Color,
  clip_id : Int?,
) -> Unit {
  let text_width = if width > 2048.0 {
    2048.0
  } else if width < 0.0 {
    0.0
  } else {
    width
  }
  if text.is_empty() || text_width <= 0.0 {
    return
  }
  let text_height = if font_size + 8.0 > 128.0 {
    128.0
  } else {
    font_size + 8.0
  }
  let bounds = desktop_rect(x, y, text_width, text_height)
  match
    @scene.SceneItem::text(
      id,
      bounds,
      desktop_renderable_single_line(text, 3000),
      font_size,
      color,
      @scene.AffineTransform::identity(),
      1.0,
      clip_id,
    ) {
    Ok(item) => items.push(item)
    Err(_) => ()
  }
}

///|
fn desktop_button_rect(
  name : String,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match name {
    "new" => desktop_rect(16.0, 62.0, 204.0, 38.0)
    "send" => desktop_rect(width - 156.0, height - 54.0, 136.0, 38.0)
    "cancel" => desktop_rect(width - 294.0, height - 54.0, 120.0, 38.0)
    "allow" => desktop_rect(width - 156.0, height - 54.0, 136.0, 38.0)
    "deny" => desktop_rect(width - 294.0, height - 54.0, 120.0, 38.0)
    "composer" => desktop_rect(260.0, height - 134.0, width - 280.0, 70.0)
    _ => desktop_rect(0.0, 0.0, 0.0, 0.0)
  }
}

///|
fn desktop_session_row_rect(index : Int) -> @primitives.Rect {
  desktop_rect(12.0, 126.0 + index.to_double() * 50.0, 212.0, 42.0)
}

///|
fn desktop_add_button(
  items : Array[@scene.SceneItem],
  id : UInt64,
  bounds : @primitives.Rect,
  label : String,
  fill : @primitives.Color,
  foreground : @primitives.Color,
) -> Unit {
  desktop_add_quad(items, id, bounds, fill, None)
  desktop_add_text(
    items,
    id + 1,
    bounds.left() + 12.0,
    bounds.top() + (bounds.bottom() - bounds.top() - 18.0) / 2.0,
    bounds.right() - bounds.left() - 24.0,
    14.0,
    label,
    foreground,
    None,
  )
}

///|
fn desktop_block_height(block : DesktopBlock) -> Double {
  46.0 + block.lines.length().to_double() * 20.0
}

///|
fn desktop_blocks(session : Json, width : Double) -> Array[DesktopBlock] {
  let blocks : Array[DesktopBlock] = []
  let text_width = width - 320.0
  let columns = if text_width < 30.0 { 2 } else { (text_width / 14.0).to_int() }
  for message in desktop_json_array(session, "messages") {
    let role = desktop_json_string(message, "role")
    if role == "system" || role == "developer" {
      continue
    }
    let reasoning = desktop_renderable_text(
      desktop_json_string(message, "reasoning"),
      6000,
    )
    if reasoning != "" {
      blocks.push({
        label: "推論",
        role: "reasoning",
        lines: @ui.wrap_text(reasoning, columns),
      })
    }
    let content = desktop_renderable_text(
      desktop_json_string(message, "content"),
      6000,
    )
    if content != "" {
      blocks.push({
        label: match role {
          "user" => "あなた"
          "assistant" => "アシスタント"
          "tool" => "ツール結果"
          _ => "メッセージ"
        },
        role,
        lines: @ui.wrap_text(content, columns),
      })
    }
    for call in desktop_json_array(message, "tool_calls") {
      let tool_name = desktop_renderable_text(
        desktop_json_string(call, "name"),
        80,
      )
      let arguments = desktop_renderable_text(
        desktop_json_string(call, "arguments"),
        3000,
      )
      blocks.push({
        label: "ツール要求 · " + tool_name,
        role: "tool",
        lines: @ui.wrap_text(arguments, columns),
      })
    }
  }
  if blocks.is_empty() {
    blocks.push({
      label: "準備ができました",
      role: "empty",
      lines: @ui.wrap_text(
        "メッセージを送ると開始します。会話とツールの結果がここに表示されます。",
        columns,
      ),
    })
  }
  blocks
}

///|
fn desktop_add_transcript(
  items : Array[@scene.SceneItem],
  next_id : Ref[UInt64],
  selected : Json,
  width : Double,
  height : Double,
  scroll_up : Double,
) -> Unit {
  let area = desktop_rect(244.0, 82.0, width - 264.0, height - 250.0)
  let blocks = desktop_blocks(selected, width)
  let mut total = 12.0
  for block in blocks {
    total += desktop_block_height(block) + 12.0
  }
  let visible_height = area.bottom() - area.top()
  let max_scroll = if total > visible_height {
    total - visible_height
  } else {
    0.0
  }
  let normalized_scroll = if scroll_up < 0.0 {
    0.0
  } else if scroll_up > max_scroll {
    max_scroll
  } else {
    scroll_up
  }
  let top_offset = max_scroll - normalized_scroll
  let mut y = area.top() - top_offset
  for block in blocks {
    let block_top = y
    let block_height = desktop_block_height(block)
    if block_top + block_height >= area.top() && block_top <= area.bottom() {
      let fill = match block.role {
        "user" => desktop_color(48, 66, 92)
        "tool" => desktop_color(63, 55, 39)
        "reasoning" => desktop_color(38, 48, 57)
        _ => desktop_color(34, 46, 58)
      }
      desktop_add_quad(
        items,
        next_id.val,
        desktop_rect(
          area.left() + 14.0,
          block_top,
          area.right() - area.left() - 28.0,
          block_height - 4.0,
        ),
        fill,
        Some(0),
      )
      next_id.val += 1
      desktop_add_text(
        items,
        next_id.val,
        area.left() + 28.0,
        block_top + 9.0,
        area.right() - area.left() - 56.0,
        12.0,
        block.label,
        desktop_color(135, 185, 222),
        Some(0),
      )
      next_id.val += 1
      for line_index, line in block.lines {
        let line_y = block_top + 29.0 + line_index.to_double() * 20.0
        if line_y + 22.0 >= area.top() && line_y <= area.bottom() {
          desktop_add_text(
            items,
            next_id.val,
            area.left() + 28.0,
            line_y,
            area.right() - area.left() - 56.0,
            14.0,
            line,
            desktop_color(230, 236, 242),
            Some(0),
          )
          next_id.val += 1
        }
      }
    }
    y += block_height + 12.0
  }
}

///|
fn desktop_scene(
  snapshot : Json,
  draft : String,
  sessions : Array[Json],
  selected_id : String,
  status_message : String,
  error_message : String,
  width : Double,
  height : Double,
  scale : Double,
  focused : Bool,
  scroll_up : Double,
) -> @scene.SceneSnapshot {
  let viewport = desktop_rect(0.0, 0.0, width, height)
  let items : Array[@scene.SceneItem] = []
  desktop_add_quad(items, 1, viewport, desktop_color(15, 21, 29), None)
  desktop_add_quad(
    items,
    2,
    desktop_rect(0.0, 0.0, 236.0, height),
    desktop_color(22, 31, 41),
    None,
  )
  desktop_add_quad(
    items,
    3,
    desktop_rect(236.0, 0.0, 1.0, height),
    desktop_color(47, 61, 75),
    None,
  )
  desktop_add_text(
    items,
    4,
    18.0,
    18.0,
    200.0,
    22.0,
    "dsh",
    desktop_color(240, 247, 252),
    None,
  )
  desktop_add_text(
    items,
    5,
    65.0,
    22.0,
    154.0,
    13.0,
    "ネイティブ会話",
    desktop_color(126, 180, 216),
    None,
  )
  desktop_add_button(
    items,
    10,
    desktop_button_rect("new", width, height),
    "+  新しいセッション",
    desktop_color(43, 100, 145),
    desktop_color(255, 255, 255),
  )
  desktop_add_text(
    items,
    20,
    20.0,
    110.0,
    200.0,
    12.0,
    "最近の会話",
    desktop_color(134, 151, 167),
    None,
  )
  let first_session = if sessions.length() > 9 {
    sessions.length() - 9
  } else {
    0
  }
  for row_index = 0; row_index < 9; row_index = row_index + 1 {
    let session_index = first_session + row_index
    if session_index >= sessions.length() {
      break
    }
    let session = sessions[session_index]
    let row = desktop_session_row_rect(row_index)
    let session_id = desktop_json_string(session, "id")
    let selected = session_id == selected_id
    if selected {
      desktop_add_quad(
        items,
        30 + row_index.to_uint64() * 2,
        row,
        desktop_color(41, 56, 72),
        None,
      )
    }
    let title = desktop_renderable_text(
      if desktop_json_string(session, "title") == "" {
        "無題の会話"
      } else {
        desktop_json_string(session, "title")
      },
      28,
    )
    desktop_add_text(
      items,
      31 + row_index.to_uint64() * 2,
      row.left() + 10.0,
      row.top() + 7.0,
      row.right() - row.left() - 20.0,
      13.0,
      title,
      if selected {
        desktop_color(244, 248, 251)
      } else {
        desktop_color(173, 189, 202)
      },
      None,
    )
  }
  let projection = desktop_json_field(snapshot, "projection").unwrap_or(
    Json::null(),
  )
  let selected = desktop_json_field(projection, "selected_session").unwrap_or(
    Json::null(),
  )
  let title = desktop_renderable_text(
    if desktop_json_string(selected, "title") == "" {
      "新しい会話"
    } else {
      desktop_json_string(selected, "title")
    },
    80,
  )
  let status = desktop_json_string(selected, "status")
  let status_label = match status {
    "running" => "生成中"
    "awaiting_approval" => "ツール承認待ち"
    "completed" => "完了"
    "failed" => "失敗"
    "cancelled" => "キャンセル済み"
    _ => "待機中"
  }
  desktop_add_text(
    items,
    60,
    264.0,
    20.0,
    width - 290.0,
    21.0,
    title,
    desktop_color(240, 246, 250),
    None,
  )
  desktop_add_text(
    items,
    61,
    264.0,
    51.0,
    width - 290.0,
    12.0,
    status_label,
    desktop_color(127, 176, 208),
    None,
  )
  desktop_add_transcript(items, Ref(10000), selected, width, height, scroll_up)
  let composer = desktop_button_rect("composer", width, height)
  desktop_add_quad(items, 300, composer, desktop_color(27, 37, 48), None)
  desktop_add_quad(
    items,
    301,
    desktop_rect(
      composer.left(),
      composer.top(),
      composer.right() - composer.left(),
      1.0,
    ),
    desktop_color(61, 80, 98),
    None,
  )
  let composer_width = composer.right() - composer.left() - 28.0
  let visible_draft = desktop_renderable_text(draft, 4000)
  let lines = @ui.wrap_text(
    visible_draft,
    if composer_width < 20.0 {
      1
    } else {
      (composer_width / 12.0).to_int()
    },
  )
  let mut caret_line = 0
  if focused {
    for index, line in lines {
      if line.contains("|") {
        caret_line = index
        break
      }
    }
  }
  let first_line = if caret_line > 2 { caret_line - 2 } else { 0 }
  let mut line_y = composer.top() + 10.0
  let mut shown = 0
  for index, line in lines {
    if index >= first_line && shown < 3 {
      desktop_add_text(
        items,
        310 + index.to_uint64(),
        composer.left() + 14.0,
        line_y,
        composer_width,
        13.0,
        line,
        desktop_color(235, 240, 245),
        None,
      )
      line_y += 18.0
      shown += 1
    }
  }
  if draft == "" {
    desktop_add_text(
      items,
      311,
      composer.left() + 14.0,
      composer.top() + 10.0,
      composer_width,
      13.0,
      "メッセージを入力 (Command-V で貼り付け)",
      desktop_color(120, 139, 155),
      None,
    )
  }
  let safe_status = desktop_renderable_text(status_message, 180)
  let safe_error = desktop_renderable_text(error_message, 180)
  if safe_error != "" {
    desktop_add_text(
      items,
      340,
      264.0,
      height - 57.0,
      width - 580.0,
      12.0,
      safe_error,
      desktop_color(244, 144, 132),
      None,
    )
  } else if safe_status != "" {
    desktop_add_text(
      items,
      341,
      264.0,
      height - 57.0,
      width - 580.0,
      12.0,
      safe_status,
      desktop_color(142, 178, 195),
      None,
    )
  }
  let pending = desktop_json_field(selected, "pending_approval")
  match pending {
    Some(Json::Object(_)) => {
      desktop_add_button(
        items,
        350,
        desktop_button_rect("deny", width, height),
        "拒否",
        desktop_color(89, 57, 56),
        desktop_color(255, 236, 232),
      )
      desktop_add_button(
        items,
        352,
        desktop_button_rect("allow", width, height),
        "承認して続行",
        desktop_color(35, 128, 89),
        desktop_color(255, 255, 255),
      )
    }
    _ =>
      if status == "running" {
        desktop_add_button(
          items,
          350,
          desktop_button_rect("cancel", width, height),
          "キャンセル",
          desktop_color(73, 54, 55),
          desktop_color(255, 234, 231),
        )
      } else {
        desktop_add_button(
          items,
          352,
          desktop_button_rect("send", width, height),
          "送信  Enter",
          desktop_color(43, 100, 145),
          desktop_color(255, 255, 255),
        )
      }
  }
  match
    @scene.SceneSnapshot::new(
      viewport,
      scale,
      [],
      [
        @scene.ClipChain::new(0, [
          desktop_rect(244.0, 82.0, width - 264.0, height - 250.0),
        ]),
      ],
      items,
    ) {
    Ok(value) => value
    Err(_) =>
      @scene.SceneSnapshot::new(viewport, scale, [], [], [
        match
          @scene.SceneItem::quad(
            1,
            viewport,
            desktop_color(15, 21, 29),
            @scene.AffineTransform::identity(),
            1.0,
            None,
          ) {
          Ok(item) => item
          Err(_) => abort("desktop fallback scene is valid")
        },
      ]).unwrap()
  }
}

///|
fn desktop_draft_string(characters : Array[Char]) -> String {
  let output = StringBuilder()
  for character in characters {
    output.write_char(character)
  }
  output.to_string()
}

///|
fn desktop_draft_with_caret(characters : Array[Char], cursor : Int) -> String {
  let output = StringBuilder()
  for index = 0; index < characters.length(); index = index + 1 {
    if index == cursor {
      output.write_char('|')
    }
    output.write_char(characters[index])
  }
  if cursor >= characters.length() {
    output.write_char('|')
  }
  output.to_string()
}
