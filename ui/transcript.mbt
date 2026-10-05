///|
/// Portable transcript geometry and scene construction. Browser code owns the
/// Canvas/DOM handles; gpui owns card layout, scroll clamping and paint data.
priv struct Block {
  label : String
  role : String
  lines : Array[String]
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn string_member(value : Json, key : String) -> String {
  match json_field(value, key) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn array_member(value : Json, key : String) -> Array[Json] {
  match json_field(value, key) {
    Some(Json::Array(values)) => values
    _ => []
  }
}

///|
fn bounded_width(width : Int) -> Double {
  if width < 1 {
    1.0
  } else {
    width.to_double()
  }
}

///|
fn side_padding(width : Double) -> Double {
  if width > 820.0 {
    (width - 820.0) / 2.0 + 16.0
  } else if width < 64.0 {
    width / 4.0
  } else {
    16.0
  }
}

///|
fn positive(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else {
    value
  }
}

///|
fn rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, positive(width), positive(height)) {
    Ok(value) => value
    Err(_) => abort("transcript geometry is finite and bounded")
  }
}

///|
fn size(width : Double, height : Double) -> @primitives.Size {
  match @primitives.Size::new(positive(width), positive(height)) {
    Ok(value) => value
    Err(_) => abort("transcript size is finite and bounded")
  }
}

///|
fn rgb(red : Int, green : Int, blue : Int) -> @primitives.Color {
  match @primitives.Color::rgba(red, green, blue, 255) {
    Ok(value) => value
    Err(_) => abort("transcript palette is valid")
  }
}

///|
fn point_dimension(value : Double) -> @layout.Dimension {
  match @layout.Dimension::points(value) {
    Ok(value) => value
    Err(_) => abort("transcript dimensions are finite")
  }
}

///|
/// Conservative host-font wrapping in Unicode scalars. Surrogate pairs are
/// never split, and combining marks / joiner continuations stay with their
/// base. Exact shaping and caret metrics remain the host font's responsibility.
pub fn wrap_text(source : String, columns : Int) -> Array[String] {
  let text = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .replace_all(old="\t", new="    ")
  let limit = if columns < 1 { 1 } else { columns }
  let lines : Array[String] = []
  let mut start = 0
  let mut index = 0
  let mut used = 0
  let mut previous = 0
  let mut last_break = -1
  let mut break_used = 0
  while index < text.length() {
    let code = text[index].to_int()
    if code == 10 {
      lines.push(text[start:index].to_owned())
      index += 1
      start = index
      used = 0
      last_break = -1
      previous = code
      continue
    }
    let continuation = (code >= 0x0300 && code <= 0x036f) ||
      (code >= 0xfe00 && code <= 0xfe0f) ||
      code == 0x200d ||
      previous == 0x200d
    if index - start >= 60000 ||
      (used >= limit && !continuation && (code != 32 || used > limit)) {
      if last_break > start {
        lines.push(text[start:last_break].to_owned())
        start = last_break
        used -= break_used
      } else {
        lines.push(text[start:index].to_owned())
        start = index
        used = 0
      }
      last_break = -1
    }
    let units = if code >= 0xd800 &&
      code <= 0xdbff &&
      index + 1 < text.length() &&
      text[index + 1].to_int() >= 0xdc00 &&
      text[index + 1].to_int() <= 0xdfff {
      2
    } else {
      1
    }
    index += units
    if !continuation {
      used += 1
    }
    if code == 32 {
      last_break = index
      break_used = used
    }
    previous = code
  }
  lines.push(text[start:text.length()].to_owned())
  lines
}

///|
fn transcript_blocks(snapshot : Json, width : Double) -> Array[Block] {
  let text_width = width - side_padding(width) * 2.0 - 32.0
  // One full em per scalar keeps narrow screens readable without cutting a
  // wide host-font glyph off the end of a run.
  let columns = if text_width < 15.0 { 1 } else { (text_width / 15.0).to_int() }
  let blocks : Array[Block] = []
  for message in array_member(snapshot, "messages") {
    let role = string_member(message, "role")
    if role == "system" || role == "developer" {
      continue
    }
    let reasoning = string_member(message, "reasoning")
    if reasoning != "" {
      blocks.push({
        label: "Reasoning",
        role: "reasoning",
        lines: wrap_text(reasoning, columns),
      })
    }
    let content = string_member(message, "content")
    if content != "" {
      let label = match role {
        "user" => "You"
        "assistant" => "Assistant"
        "tool" => "Tool result"
        _ => "Message"
      }
      blocks.push({ label, role, lines: wrap_text(content, columns), })
    }
    for call in array_member(message, "tool_calls") {
      let name = string_member(call, "name")
      let arguments = string_member(call, "arguments")
      blocks.push({
        label: "Tool request · " + name,
        role: "tool",
        lines: wrap_text(arguments, columns),
      })
    }
  }
  let live = string_member(snapshot, "_ui_live_text")
  if live != "" {
    blocks.push({
      label: "Assistant · writing",
      role: "assistant",
      lines: wrap_text(live, columns),
    })
  }
  if blocks.is_empty() {
    blocks.push({
      label: "Ready when you are",
      role: "empty",
      lines: wrap_text(
        "Send a prompt to start. Messages and tool results will appear here.", columns,
      ),
    })
  }
  blocks
}

///|
fn block_height(block : Block) -> Double {
  54.0 + block.lines.length().to_double() * 22.0
}

///|
fn document_height(blocks : Array[Block]) -> Double {
  let mut height = 32.0
  for index, block in blocks {
    if index > 0 {
      height += 12.0
    }
    height += block_height(block)
  }
  height
}

///|
/// Native scroll-container extent. The Canvas itself only allocates a bitmap
/// for its visible viewport, even when the transcript is long.
pub fn measure(snapshot : Json, width : Int) -> Int {
  document_height(transcript_blocks(snapshot, bounded_width(width))).to_int()
}

///|
fn transcript_layout(
  blocks : Array[Block],
  width : Double,
) -> @layout.FlexLayout {
  let padding = side_padding(width)
  let insets = match @layout.Insets::new(16.0, padding, 16.0, padding) {
    Ok(value) => value
    Err(_) => abort("transcript insets are finite")
  }
  let container = @layout.FlexContainer::new(
      @layout.FlowDirection::column(),
      size(width, document_height(blocks)),
    )
    .with_insets(insets, @layout.Insets::zero())
    .with_align(@layout.AlignItems::stretch())
  let container = match container.with_gap(12.0) {
    Ok(value) => value
    Err(_) => abort("transcript gap is valid")
  }
  let items : Array[@layout.FlexItem] = []
  for index, block in blocks {
    let item = @layout.FlexItem::new(
      (100 + index).to_uint64(),
      point_dimension(block_height(block)),
      @layout.Dimension::auto(),
      size(0.0, 0.0),
    )
    match item.with_flex(0.0, 0.0) {
      Ok(value) => items.push(value)
      Err(_) => abort("transcript cards have fixed measured heights")
    }
  }
  match @layout.layout_flex(container, items) {
    Ok(value) => value
    Err(_) => abort("transcript layout is valid")
  }
}

///|
fn background(role : String) -> @primitives.Color {
  match role {
    "user" => rgb(235, 241, 252)
    "tool" => rgb(251, 245, 229)
    "reasoning" => rgb(242, 243, 241)
    "empty" => rgb(247, 248, 250)
    _ => rgb(255, 255, 255)
  }
}

///|
fn add_text(
  items : Array[@scene.SceneItem],
  id : UInt64,
  bounds : @primitives.Rect,
  text : String,
  font_size : Double,
  color : @primitives.Color,
) -> Unit {
  // Every run is viewport-clipped by the single shared clip chain.
  match
    @scene.SceneItem::text(
      id,
      bounds,
      text,
      font_size,
      color,
      @scene.AffineTransform::identity(),
      1.0,
      Some(0),
    ) {
    Ok(item) => items.push(item)
    Err(_) => abort("transcript text run exceeds the scene contract")
  }
}

///|
/// Render a snapshot using real gpui flex layout, ElementTree backgrounds,
/// ScrollState and SceneSnapshot text. `_ui_scroll_top` is a host-only copied
/// presentation value and never modifies the harness session.
pub fn render(snapshot : Json, width : Int, height : Int) -> String {
  let width = bounded_width(width)
  let height = bounded_width(height)
  let viewport = rect(0.0, 0.0, width, height)
  let blocks = transcript_blocks(snapshot, width)
  let layout = transcript_layout(blocks, width)
  let scroll = @element.ScrollState::new(
    size(width, height),
    size(width, document_height(blocks)),
  )
  let requested_scroll = match json_field(snapshot, "_ui_scroll_top") {
    Some(Json::Number(value, ..)) if !value.is_nan() && !value.is_inf() =>
      positive(value)
    _ => 0.0
  }
  let scroll = match scroll.scroll_to(0.0, requested_scroll) {
    Ok(value) => value
    Err(_) => scroll
  }
  let offset = scroll.offset().y()
  let nodes : Array[@element.ElementNode] = [
    @element.ElementNode::new(1, None, viewport)
    .with_pointer_events(false)
    .with_background(Some(rgb(247, 248, 250))),
  ]
  let text_items : Array[@scene.SceneItem] = []
  let mut text_id : UInt64 = 100000
  for index, item in layout.items() {
    let block = blocks[index]
    let bounds = item.bounds()
    let top = bounds.top() - offset
    let card = rect(
      bounds.left(),
      top,
      bounds.size().width(),
      bounds.size().height(),
    )
    match card.intersection(viewport) {
      None => continue
      Some(visible) if visible.size().height() <= 0.0 => continue
      Some(visible) =>
        nodes.push(
          @element.ElementNode::new(item.id(), Some(1), visible).with_background(
            Some(background(block.role)),
          ),
        )
    }
    let text_x = bounds.left() + 16.0
    let text_width = positive(bounds.size().width() - 32.0)
    if top + 32.0 > 0.0 && top + 14.0 < height {
      add_text(
        text_items,
        text_id,
        rect(text_x, top + 14.0, text_width, 18.0),
        block.label,
        11.0,
        rgb(89, 100, 117),
      )
      text_id += 1
    }
    for line_index, line in block.lines {
      let line_y = top + 40.0 + line_index.to_double() * 22.0
      if line_y + 22.0 > 0.0 && line_y < height {
        add_text(
          text_items,
          text_id,
          rect(text_x, line_y, text_width, 22.0),
          line,
          15.0,
          rgb(29, 40, 57),
        )
        text_id += 1
      }
    }
  }
  let tree = match @element.ElementTree::new(nodes) {
    Ok(value) => value
    Err(_) => abort("transcript element hierarchy is valid")
  }
  let base = match tree.to_scene().snapshot_v1(viewport, 1.0) {
    Ok(value) => value
    Err(_) => abort("transcript background scene is valid")
  }
  let items = base.items()
  for item in text_items {
    items.push(item)
  }
  match
    @scene.SceneSnapshot::new(
      viewport,
      1.0,
      [],
      [@scene.ClipChain::new(0, [viewport])],
      items,
    ) {
    Ok(value) => value.canonical_json()
    Err(_) => abort("transcript scene is valid")
  }
}
