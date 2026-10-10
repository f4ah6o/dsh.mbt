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
    "settings-open" => desktop_rect(16.0, height - 54.0, 204.0, 38.0)
    "send" => desktop_rect(width - 156.0, height - 54.0, 136.0, 38.0)
    "cancel" => desktop_rect(width - 294.0, height - 54.0, 120.0, 38.0)
    "allow" => desktop_rect(width - 156.0, height - 54.0, 136.0, 38.0)
    "deny" => desktop_rect(width - 294.0, height - 54.0, 120.0, 38.0)
    "composer" => desktop_rect(260.0, height - 134.0, width - 280.0, 70.0)
    _ => desktop_rect(0.0, 0.0, 0.0, 0.0)
  }
}

///|
fn desktop_settings_button_rect(
  name : String,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  let content_x = 480.0
  let content_width = (width - 512.0).max(240.0)
  match name {
    "settings-close" => desktop_rect(width - 94.0, 18.0, 72.0, 34.0)
    "settings-nav-chatgpt" => desktop_rect(258.0, 94.0, 194.0, 38.0)
    "auth-sign-in" => desktop_rect(content_x + 16.0, 252.0, 172.0, 34.0)
    "auth-models-retry" => desktop_rect(content_x + 16.0, 252.0, 156.0, 34.0)
    "auth-sign-out" => desktop_rect(content_x + 180.0, 252.0, 112.0, 34.0)
    _ => desktop_rect(0.0, 0.0, content_width, height)
  }
}

///|
fn desktop_settings_visible_model_rows(height : Double) -> Int {
  ((height - 432.0) / 44.0).to_int().max(1).min(9)
}

///|
fn desktop_settings_max_scroll(model_count : Int, height : Double) -> Int {
  (model_count - desktop_settings_visible_model_rows(height)).max(0)
}

///|
fn desktop_settings_clamp_scroll(
  settings_scroll : Int,
  model_count : Int,
  height : Double,
) -> Int {
  settings_scroll.max(0).min(desktop_settings_max_scroll(model_count, height))
}

///|
fn desktop_auth_model_label(model : Json) -> String {
  let slug = desktop_json_string(model, "slug")
  let display_name = desktop_json_string(model, "display_name")
  if display_name == "" {
    slug
  } else {
    display_name
  }
}

///|
fn desktop_settings_model_rect(
  visible_index : Int,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  let content_x = 480.0
  let content_width = (width - 512.0).max(240.0)
  let top = 402.0 + visible_index.to_double() * 42.0
  let row_height = (height - 24.0 - top).min(38.0).max(0.0)
  desktop_rect(content_x + 12.0, top, content_width - 24.0, row_height)
}

///|
fn desktop_settings_model_focus_at(
  auth : Json,
  settings_scroll : Int,
  width : Double,
  height : Double,
  position : @primitives.Point,
) -> Int? {
  let model_count = desktop_auth_model_count(auth)
  let first = desktop_settings_clamp_scroll(
    settings_scroll, model_count, height,
  )
  for visible_index in 0..<desktop_settings_visible_model_rows(height) {
    let model_index = first + visible_index
    if model_index < model_count &&
      desktop_settings_model_rect(visible_index, width, height).contains(
        position,
      ) {
      return Some(model_index + 4)
    }
  }
  None
}

///|
fn desktop_add_focus_outline(
  items : Array[@scene.SceneItem],
  id : UInt64,
  bounds : @primitives.Rect,
) -> Unit {
  let color = desktop_color(37, 99, 235)
  desktop_add_quad(
    items,
    id,
    desktop_rect(
      bounds.left(),
      bounds.top(),
      bounds.right() - bounds.left(),
      1.0,
    ),
    color,
    None,
  )
  desktop_add_quad(
    items,
    id + 1,
    desktop_rect(
      bounds.left(),
      bounds.bottom() - 1.0,
      bounds.right() - bounds.left(),
      1.0,
    ),
    color,
    None,
  )
  desktop_add_quad(
    items,
    id + 2,
    desktop_rect(
      bounds.left(),
      bounds.top(),
      1.0,
      bounds.bottom() - bounds.top(),
    ),
    color,
    None,
  )
  desktop_add_quad(
    items,
    id + 3,
    desktop_rect(
      bounds.right() - 1.0,
      bounds.top(),
      1.0,
      bounds.bottom() - bounds.top(),
    ),
    color,
    None,
  )
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
  match desktop_json_field(session, "todos") {
    Some(Json::Array(todos)) => {
      let lines : Array[String] = []
      if todos.is_empty() {
        lines.push("タスクはありません。")
      }
      for todo in todos {
        let marker = match desktop_json_string(todo, "status") {
          "in_progress" => "[~] "
          "completed" => "[x] "
          _ => "[ ] "
        }
        lines.append(
          @ui.wrap_text(
            desktop_renderable_text(
              marker + desktop_json_string(todo, "content"),
              600,
            ),
            columns,
          ),
        )
      }
      blocks.push({ label: "タスク", role: "todo", lines, })
    }
    _ => ()
  }
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
        label: match desktop_json_string(message, "display_label") {
          label if label != "" => label
          _ =>
            match role {
              "user" => "あなた"
              "assistant" => "アシスタント"
              "tool" => "ツール結果"
              _ => "メッセージ"
            }
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
        "user" => desktop_color(235, 241, 247)
        "tool" => desktop_color(247, 244, 237)
        "reasoning" => desktop_color(246, 247, 248)
        _ => desktop_color(249, 250, 251)
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
        desktop_color(71, 98, 122),
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
            desktop_color(31, 41, 55),
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
  settings_open? : Bool = false,
  auth_busy? : Bool = false,
  auth_error? : String = "",
  settings_scroll? : Int = 0,
  settings_focus? : Int = 0,
) -> @scene.SceneSnapshot {
  let viewport = desktop_rect(0.0, 0.0, width, height)
  let items : Array[@scene.SceneItem] = []
  desktop_add_quad(items, 1, viewport, desktop_color(255, 255, 255), None)
  desktop_add_quad(
    items,
    2,
    desktop_rect(0.0, 0.0, 236.0, height),
    desktop_color(249, 250, 251),
    None,
  )
  desktop_add_quad(
    items,
    3,
    desktop_rect(236.0, 0.0, 1.0, height),
    desktop_color(229, 231, 235),
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
    desktop_color(17, 24, 39),
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
    desktop_color(107, 114, 128),
    None,
  )
  desktop_add_button(
    items,
    10,
    desktop_button_rect("new", width, height),
    "+  新しいセッション",
    desktop_color(31, 41, 55),
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
    desktop_color(107, 114, 128),
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
        desktop_color(233, 238, 245),
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
        desktop_color(17, 24, 39)
      } else {
        desktop_color(75, 85, 99)
      },
      None,
    )
  }
  desktop_add_button(
    items,
    58,
    desktop_button_rect("settings-open", width, height),
    "設定",
    desktop_color(243, 244, 246),
    desktop_color(55, 65, 81),
  )
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
    desktop_color(17, 24, 39),
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
    desktop_color(107, 114, 128),
    None,
  )
  desktop_add_transcript(items, Ref(10000), selected, width, height, scroll_up)
  let composer = desktop_button_rect("composer", width, height)
  desktop_add_quad(items, 300, composer, desktop_color(255, 255, 255), None)
  desktop_add_quad(
    items,
    301,
    desktop_rect(
      composer.left(),
      composer.top(),
      composer.right() - composer.left(),
      1.0,
    ),
    desktop_color(209, 213, 219),
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
        desktop_color(31, 41, 55),
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
      desktop_color(156, 163, 175),
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
      desktop_color(185, 28, 28),
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
      desktop_color(107, 114, 128),
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
        desktop_color(254, 242, 242),
        desktop_color(153, 27, 27),
      )
      desktop_add_button(
        items,
        352,
        desktop_button_rect("allow", width, height),
        "承認して続行",
        desktop_color(22, 101, 52),
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
          desktop_color(254, 242, 242),
          desktop_color(153, 27, 27),
        )
      } else {
        desktop_add_button(
          items,
          352,
          desktop_button_rect("send", width, height),
          "送信  Enter",
          desktop_color(31, 41, 55),
          desktop_color(255, 255, 255),
        )
      }
  }
  if settings_open {
    desktop_add_settings(
      items, snapshot, width, height, auth_busy, auth_error, settings_scroll, settings_focus,
    )
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
            desktop_color(255, 255, 255),
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
fn desktop_add_settings(
  items : Array[@scene.SceneItem],
  snapshot : Json,
  width : Double,
  height : Double,
  auth_busy : Bool,
  auth_error : String,
  settings_scroll : Int,
  settings_focus : Int,
) -> Unit {
  // Settings replaces the conversation workspace while keeping the history
  // sidebar visible, matching the Electron shell's navigation hierarchy.
  desktop_add_quad(
    items,
    500,
    desktop_rect(236.0, 0.0, width - 236.0, height),
    desktop_color(255, 255, 255),
    None,
  )
  desktop_add_text(
    items,
    501,
    264.0,
    22.0,
    320.0,
    21.0,
    "設定",
    desktop_color(17, 24, 39),
    None,
  )
  desktop_add_button(
    items,
    502,
    desktop_settings_button_rect("settings-close", width, height),
    "閉じる",
    desktop_color(243, 244, 246),
    desktop_color(55, 65, 81),
  )
  if settings_focus == 0 {
    desktop_add_focus_outline(
      items,
      300000,
      desktop_settings_button_rect("settings-close", width, height),
    )
  }
  desktop_add_quad(
    items,
    504,
    desktop_rect(236.0, 66.0, width - 236.0, 1.0),
    desktop_color(229, 231, 235),
    None,
  )
  desktop_add_text(
    items,
    505,
    270.0,
    74.0,
    170.0,
    12.0,
    "サービス",
    desktop_color(107, 114, 128),
    None,
  )
  desktop_add_quad(
    items,
    506,
    desktop_settings_button_rect("settings-nav-chatgpt", width, height),
    desktop_color(239, 243, 248),
    None,
  )
  desktop_add_text(
    items,
    507,
    282.0,
    105.0,
    164.0,
    13.0,
    "ChatGPT",
    desktop_color(31, 41, 55),
    None,
  )
  if settings_focus == 1 {
    desktop_add_focus_outline(
      items,
      300004,
      desktop_settings_button_rect("settings-nav-chatgpt", width, height),
    )
  }

  let auth = desktop_json_field(snapshot, "auth").unwrap_or(
    Json::empty_object(),
  )
  let account = desktop_json_field(auth, "account").unwrap_or(Json::null())
  let state = desktop_json_string(auth, "state")
  let connected = state == "connected" &&
    desktop_json_string(account, "profile_id") != ""
  let content_x = 480.0
  let content_width = (width - 512.0).max(240.0)

  desktop_add_text(
    items,
    510,
    content_x,
    92.0,
    content_width,
    20.0,
    "ChatGPT",
    desktop_color(17, 24, 39),
    None,
  )
  desktop_add_text(
    items,
    511,
    content_x,
    122.0,
    content_width,
    13.0,
    "アカウントと利用するモデルを管理します。",
    desktop_color(107, 114, 128),
    None,
  )
  desktop_add_quad(
    items,
    512,
    desktop_rect(content_x, 158.0, content_width, 148.0),
    desktop_color(255, 255, 255),
    None,
  )
  desktop_add_quad(
    items,
    513,
    desktop_rect(content_x, 158.0, content_width, 1.0),
    desktop_color(229, 231, 235),
    None,
  )
  desktop_add_quad(
    items,
    514,
    desktop_rect(content_x, 305.0, content_width, 1.0),
    desktop_color(229, 231, 235),
    None,
  )
  desktop_add_text(
    items,
    515,
    content_x + 12.0,
    172.0,
    content_width - 24.0,
    13.0,
    "アカウント",
    desktop_color(31, 41, 55),
    None,
  )
  let status_label = if connected {
    "接続済み"
  } else if state == "signing_in" {
    "ブラウザーでサインイン中..."
  } else if state == "reauth_required" {
    "再認証が必要です"
  } else {
    "未接続"
  }
  desktop_add_text(
    items,
    516,
    content_x + 12.0,
    198.0,
    content_width - 24.0,
    12.0,
    status_label,
    if connected {
      desktop_color(22, 101, 52)
    } else {
      desktop_color(107, 114, 128)
    },
    None,
  )
  let email = desktop_json_string(account, "email")
  if email != "" {
    desktop_add_text(
      items,
      517,
      content_x + 92.0,
      198.0,
      content_width - 112.0,
      12.0,
      email,
      desktop_color(75, 85, 99),
      None,
    )
  }
  if connected {
    desktop_add_button(
      items,
      518,
      desktop_settings_button_rect("auth-models-retry", width, height),
      if auth_busy {
        "読み込み中..."
      } else {
        "モデルを更新"
      },
      desktop_color(243, 244, 246),
      desktop_color(55, 65, 81),
    )
    if settings_focus == 2 {
      desktop_add_focus_outline(
        items,
        300008,
        desktop_settings_button_rect("auth-models-retry", width, height),
      )
    }
    desktop_add_button(
      items,
      520,
      desktop_settings_button_rect("auth-sign-out", width, height),
      "サインアウト",
      desktop_color(243, 244, 246),
      desktop_color(55, 65, 81),
    )
    if settings_focus == 3 {
      desktop_add_focus_outline(
        items,
        300012,
        desktop_settings_button_rect("auth-sign-out", width, height),
      )
    }
    let scopes = desktop_json_array(auth, "scopes")
    let plan = desktop_json_string(auth, "plan_usage")
    desktop_add_text(
      items,
      522,
      content_x + 12.0,
      224.0,
      155.0,
      11.0,
      if plan == "enabled" {
        "モデル利用可能"
      } else {
        "利用権限を確認中"
      },
      desktop_color(107, 114, 128),
      None,
    )
    if scopes.length() > 0 {
      desktop_add_text(
        items,
        523,
        content_x + 176.0,
        224.0,
        content_width - 188.0,
        11.0,
        scopes.length().to_string() + " 個の権限を利用中",
        desktop_color(107, 114, 128),
        None,
      )
    }
  } else {
    desktop_add_button(
      items,
      518,
      desktop_settings_button_rect("auth-sign-in", width, height),
      if auth_busy {
        "サインイン中..."
      } else {
        "ChatGPT にサインイン"
      },
      desktop_color(31, 41, 55),
      desktop_color(255, 255, 255),
    )
    if settings_focus == 2 {
      desktop_add_focus_outline(
        items,
        300008,
        desktop_settings_button_rect("auth-sign-in", width, height),
      )
    }
    desktop_add_text(
      items,
      520,
      content_x + 200.0,
      260.0,
      content_width - 216.0,
      11.0,
      "認証は既定のブラウザーで行います。",
      desktop_color(107, 114, 128),
      None,
    )
  }

  desktop_add_text(
    items,
    530,
    content_x,
    330.0,
    content_width,
    16.0,
    "モデル",
    desktop_color(17, 24, 39),
    None,
  )
  desktop_add_text(
    items,
    531,
    content_x,
    354.0,
    content_width,
    11.0,
    "会話で使うモデルを選択します。",
    desktop_color(107, 114, 128),
    None,
  )
  if !connected {
    desktop_add_text(
      items,
      532,
      content_x + 12.0,
      402.0,
      content_width - 24.0,
      12.0,
      "サインインすると利用可能なモデルが表示されます。",
      desktop_color(107, 114, 128),
      None,
    )
  } else {
    let models = desktop_json_array(auth, "models")
    let selected_model = desktop_json_string(auth, "selected_model")
    let visible = desktop_settings_visible_model_rows(height)
    let first = desktop_settings_clamp_scroll(
      settings_scroll,
      models.length(),
      height,
    )
    let last = (first + visible).min(models.length())
    if models.is_empty() {
      desktop_add_text(
        items,
        532,
        content_x + 12.0,
        402.0,
        content_width - 24.0,
        12.0,
        "モデル一覧がありません。モデルを更新してください。",
        desktop_color(107, 114, 128),
        None,
      )
    }
    for model_index = first; model_index < last; model_index = model_index + 1 {
      let model = models[model_index]
      let slug = desktop_json_string(model, "slug")
      let label = desktop_auth_model_label(model)
      let visible_index = model_index - first
      let row = desktop_settings_model_rect(visible_index, width, height)
      let is_selected = slug != "" && slug == selected_model
      if is_selected {
        desktop_add_quad(
          items,
          540 + model_index.to_uint64() * 3,
          row,
          desktop_color(239, 243, 248),
          None,
        )
      }
      if settings_focus == model_index + 4 {
        desktop_add_focus_outline(
          items,
          301000 + model_index.to_uint64() * 4,
          row,
        )
      }
      desktop_add_text(
        items,
        541 + model_index.to_uint64() * 3,
        row.left() + 10.0,
        row.top() + 9.0,
        row.right() - row.left() - 112.0,
        12.0,
        label,
        desktop_color(31, 41, 55),
        None,
      )
      desktop_add_text(
        items,
        542 + model_index.to_uint64() * 3,
        row.right() - 98.0,
        row.top() + 9.0,
        90.0,
        11.0,
        if is_selected {
          "選択中"
        } else {
          ""
        },
        desktop_color(37, 99, 235),
        None,
      )
    }
  }
  let safe_error = desktop_renderable_text(auth_error, 200)
  if safe_error != "" {
    desktop_add_text(
      items,
      599,
      content_x,
      height - 30.0,
      content_width,
      11.0,
      safe_error,
      desktop_color(185, 28, 28),
      None,
    )
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
