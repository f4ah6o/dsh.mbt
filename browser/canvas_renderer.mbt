///|
#external
priv type BrowserValue

///|
extern "js" fn canvas_root_css_property(
  context : BrowserValue,
  property_name : String,
) -> String =
  #| (context, propertyName) => context?.canvas?.ownerDocument?.defaultView?.getComputedStyle?.(context.canvas.ownerDocument.documentElement)?.getPropertyValue(propertyName)?.trim() || ""

///|
extern "js" fn canvas_save(context : BrowserValue) -> Unit =
  #| (context) => context.save()

///|
extern "js" fn canvas_restore(context : BrowserValue) -> Unit =
  #| (context) => context.restore()

///|
extern "js" fn canvas_set_transform(
  context : BrowserValue,
  scale : Double,
) -> Unit =
  #| (context, scale) => context.setTransform(scale, 0, 0, scale, 0, 0)

///|
extern "js" fn canvas_clear(
  context : BrowserValue,
  width : Double,
  height : Double,
) -> Unit =
  #| (context, width, height) => context.clearRect(0, 0, width, height)

///|
extern "js" fn canvas_set_source_over(context : BrowserValue) -> Unit =
  #| (context) => { context.globalCompositeOperation = "source-over"; context.filter = "none"; context.shadowBlur = 0; context.shadowColor = "rgba(0, 0, 0, 0)" }

///|
extern "js" fn canvas_clip(
  context : BrowserValue,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Unit =
  #| (context, x, y, width, height) => { context.beginPath(); context.rect(x, y, width, height); context.clip() }

///|
extern "js" fn canvas_transform(
  context : BrowserValue,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  tx : Double,
  ty : Double,
) -> Unit =
  #| (context, a, b, c, d, tx, ty) => context.transform(a, b, c, d, tx, ty)

///|
extern "js" fn canvas_set_alpha(context : BrowserValue, alpha : Double) -> Unit =
  #| (context, alpha) => { context.globalAlpha = alpha }

///|
extern "js" fn canvas_set_color(
  context : BrowserValue,
  red : Int,
  green : Int,
  blue : Int,
  alpha : Double,
) -> Unit =
  #| (context, red, green, blue, alpha) => { context.fillStyle = `rgba(${red}, ${green}, ${blue}, ${alpha})` }

///|
extern "js" fn canvas_fill_rect(
  context : BrowserValue,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Unit =
  #| (context, x, y, width, height) => context.fillRect(x, y, width, height)

///|
extern "js" fn canvas_set_text_font(
  context : BrowserValue,
  font_size : Double,
  family : String,
) -> Unit =
  #| (context, font_size, family) => { context.font = `${font_size}px ${family}`; context.textAlign = "left"; context.textBaseline = "top"; context.direction = "ltr" }

///|
extern "js" fn canvas_fill_text(
  context : BrowserValue,
  text : String,
  x : Double,
  y : Double,
) -> Unit =
  #| (context, text, x, y) => context.fillText(text, x, y)

///|
extern "js" fn canvas_is_context_usable(context : BrowserValue) -> Bool =
  #| (context) => !!context && !(typeof context.isContextLost === "function" && context.isContextLost())

///|
/// A validation failure is reported before the Canvas receives any draw call.
pub struct CanvasSceneError {
  message : String
  code : String
}

///|
pub fn CanvasSceneError::message(self : CanvasSceneError) -> String {
  self.message
}

///|
pub fn CanvasSceneError::code(self : CanvasSceneError) -> String {
  self.code
}

///|
priv struct SceneRect {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
priv struct SceneColor {
  red : Int
  green : Int
  blue : Int
  alpha : Int
}

///|
priv struct SceneTransform {
  a : Double
  b : Double
  c : Double
  d : Double
  tx : Double
  ty : Double
}

///|
priv struct SceneItem {
  kind : String
  bounds : SceneRect
  color : SceneColor
  transform : SceneTransform
  opacity : Double
  clip_chain_id : Int?
  text : String
  font_size : Double
}

///|
priv struct ValidatedScene {
  viewport : SceneRect
  clip_chains : Map[Int, Array[SceneRect]]
  items : Array[SceneItem]
}

///|
fn scene_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn scene_number(value : Json, key : String) -> Double? {
  match scene_field(value, key) {
    Some(Json::Number(number, ..)) => Some(number)
    _ => None
  }
}

///|
fn scene_string(value : Json, key : String) -> String? {
  match scene_field(value, key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn scene_error(
  message : String,
  code? : String = "conversion_failed",
) -> CanvasSceneError {
  { message, code, }
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn integer(value : Double) -> Bool {
  finite(value) && value.trunc() == value
}

///|
fn parse_rect(
  value : Json,
  label : String,
) -> Result[SceneRect, CanvasSceneError] {
  let x = match scene_number(value, "x") {
    Some(number) => number
    _ => return Err(scene_error(label + " must be a rectangle."))
  }
  let y = match scene_number(value, "y") {
    Some(number) => number
    _ => return Err(scene_error(label + " must be a rectangle."))
  }
  let width = match scene_number(value, "width") {
    Some(number) => number
    _ => return Err(scene_error(label + " must be a rectangle."))
  }
  let height = match scene_number(value, "height") {
    Some(number) => number
    _ => return Err(scene_error(label + " must be a rectangle."))
  }
  let right = x + width
  let bottom = y + height
  if !finite(x) ||
    !finite(y) ||
    !finite(width) ||
    !finite(height) ||
    !finite(right) ||
    !finite(bottom) ||
    width < 0.0 ||
    height < 0.0 ||
    (width > 0.0 && right <= x) ||
    (height > 0.0 && bottom <= y) {
    return Err(
      scene_error(
        label + " must have finite, non-negative, representable bounds.",
      ),
    )
  }
  Ok({ x, y, width, height, })
}

///|
fn parse_color(value : Json) -> Result[SceneColor, CanvasSceneError] {
  let red = match scene_number(value, "red") {
    Some(number) => number
    _ =>
      return Err(
        scene_error("Scene color channels must be integers in [0, 255]."),
      )
  }
  let green = match scene_number(value, "green") {
    Some(number) => number
    _ =>
      return Err(
        scene_error("Scene color channels must be integers in [0, 255]."),
      )
  }
  let blue = match scene_number(value, "blue") {
    Some(number) => number
    _ =>
      return Err(
        scene_error("Scene color channels must be integers in [0, 255]."),
      )
  }
  let alpha = match scene_number(value, "alpha") {
    Some(number) => number
    _ =>
      return Err(
        scene_error("Scene color channels must be integers in [0, 255]."),
      )
  }
  if ![red, green, blue, alpha].all(number => {
      integer(number) && number >= 0.0 && number <= 255.0
    }) {
    return Err(
      scene_error("Scene color channels must be integers in [0, 255]."),
    )
  }
  Ok({
    red: red.to_int(),
    green: green.to_int(),
    blue: blue.to_int(),
    alpha: alpha.to_int(),
  })
}

///|
fn parse_transform(value : Json) -> Result[SceneTransform, CanvasSceneError] {
  let a = match scene_number(value, "a") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let b = match scene_number(value, "b") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let c = match scene_number(value, "c") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let d = match scene_number(value, "d") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let tx = match scene_number(value, "tx") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let ty = match scene_number(value, "ty") {
    Some(number) => number
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  if ![a, b, c, d, tx, ty].all(finite) {
    return Err(scene_error("Scene item transforms must be finite."))
  }
  Ok({ a, b, c, d, tx, ty, })
}

///|
fn parse_scene_item(
  value : Json,
  clip_chains : Map[Int, Array[SceneRect]],
) -> Result[SceneItem, CanvasSceneError] {
  let kind = match scene_string(value, "kind") {
    Some(text) => text
    _ => return Err(scene_error("Scene items must be objects."))
  }
  if kind != "quad" && kind != "text" {
    return Err(
      scene_error(
        "Unsupported Canvas scene item: " + kind + ".",
        code="unsupported_capability",
      ),
    )
  }
  let id = match scene_number(value, "id") {
    Some(number) => number
    _ =>
      return Err(scene_error("Scene item IDs must be non-negative integers."))
  }
  if !integer(id) || id < 0.0 {
    return Err(scene_error("Scene item IDs must be non-negative integers."))
  }
  let bounds = match scene_field(value, "bounds") {
    Some(item_bounds) =>
      match parse_rect(item_bounds, "Item bounds") {
        Ok(rect) => rect
        Err(error) => return Err(error)
      }
    _ => return Err(scene_error("Item bounds must be a rectangle."))
  }
  let color = match scene_field(value, "color") {
    Some(item_color) =>
      match parse_color(item_color) {
        Ok(color) => color
        Err(error) => return Err(error)
      }
    _ =>
      return Err(
        scene_error("Scene color channels must be integers in [0, 255]."),
      )
  }
  let transform = match scene_field(value, "transform") {
    Some(item_transform) =>
      match parse_transform(item_transform) {
        Ok(transform) => transform
        Err(error) => return Err(error)
      }
    _ => return Err(scene_error("Scene item transforms must be finite."))
  }
  let opacity = match scene_number(value, "opacity") {
    Some(number) => number
    _ => return Err(scene_error("Scene item opacity must be in [0, 1]."))
  }
  if !finite(opacity) || opacity < 0.0 || opacity > 1.0 {
    return Err(scene_error("Scene item opacity must be in [0, 1]."))
  }
  let clip_chain_id = match scene_field(value, "clip_chain_id") {
    Some(Json::Null) => None
    Some(Json::Number(number, ..)) if integer(number) &&
      number >= -2147483648.0 &&
      number <= 2147483647.0 => {
      let id = number.to_int()
      if !clip_chains.contains(id) {
        return Err(scene_error("Scene item references an unknown clip chain."))
      }
      Some(id)
    }
    _ => return Err(scene_error("Scene item references an unknown clip chain."))
  }
  let text = match scene_string(value, "text") {
    Some(text) => text
    _ => ""
  }
  let font_size = match scene_number(value, "font_size") {
    Some(number) => number
    _ => 0.0
  }
  if kind == "text" &&
    (scene_string(value, "text") is None || text.length() > 65536) {
    return Err(scene_error("Text must be at most 65,536 UTF-16 code units."))
  }
  if kind == "text" &&
    (!finite(font_size) || font_size <= 0.0 || font_size > 1024.0) {
    return Err(
      scene_error("Text font size must be in (0, 1024] logical pixels."),
    )
  }
  Ok({
    kind,
    bounds,
    color,
    transform,
    opacity,
    clip_chain_id,
    text,
    font_size,
  })
}

///|
/// Parse and validate an entire SceneSnapshot v1 envelope before painting.
fn parse_validated_scene(
  snapshot : Json,
  width : Double,
  height : Double,
  scale : Double,
) -> Result[ValidatedScene, CanvasSceneError] {
  if !finite(width) ||
    !finite(height) ||
    !finite(scale) ||
    width <= 0.0 ||
    height <= 0.0 ||
    scale <= 0.0 {
    return Err(
      scene_error(
        "Canvas dimensions and device scale must be finite and positive.",
      ),
    )
  }
  if scene_number(snapshot, "schema_version") != Some(1.0) {
    return Err(scene_error("Expected a SceneSnapshot v1 envelope."))
  }
  let resources = match scene_field(snapshot, "resources") {
    Some(Json::Array(values)) => values
    _ => return Err(scene_error("Expected a SceneSnapshot v1 envelope."))
  }
  let raw_items = match scene_field(snapshot, "items") {
    Some(Json::Array(values)) => values
    _ => return Err(scene_error("Expected a SceneSnapshot v1 envelope."))
  }
  let raw_chains = match scene_field(snapshot, "clip_chains") {
    Some(Json::Array(values)) => values
    _ => return Err(scene_error("Expected a SceneSnapshot v1 envelope."))
  }
  if !resources.is_empty() {
    return Err(
      scene_error(
        "Canvas resource-backed paint is not supported.",
        code="unsupported_capability",
      ),
    )
  }
  let viewport = match scene_field(snapshot, "viewport") {
    Some(value) =>
      match parse_rect(value, "Scene viewport") {
        Ok(viewport) => viewport
        Err(error) => return Err(error)
      }
    _ => return Err(scene_error("Scene viewport must be a rectangle."))
  }
  let scene_scale = match scene_number(snapshot, "scale") {
    Some(value) => value
    _ => 0.0
  }
  if !finite(scene_scale) || scene_scale <= 0.0 {
    return Err(scene_error("Scene scale must be finite and positive."))
  }
  let clip_chains : Map[Int, Array[SceneRect]] = Map([])
  for chain in raw_chains {
    let id = match scene_number(chain, "id") {
      Some(value) if integer(value) &&
        value >= -2147483648.0 &&
        value <= 2147483647.0 => value.to_int()
      _ => return Err(scene_error("Invalid scene clip chain."))
    }
    let raw_rects = match scene_field(chain, "rects") {
      Some(Json::Array(values)) => values
      _ => return Err(scene_error("Invalid scene clip chain."))
    }
    if clip_chains.contains(id) {
      return Err(
        scene_error("Duplicate scene clip chain " + id.to_string() + "."),
      )
    }
    let rects : Array[SceneRect] = []
    for bounds in raw_rects {
      match parse_rect(bounds, "Clip rectangle") {
        Ok(value) => rects.push(value)
        Err(error) => return Err(error)
      }
    }
    clip_chains[id] = rects
  }
  let items : Array[SceneItem] = []
  for raw_item in raw_items {
    match parse_scene_item(raw_item, clip_chains) {
      Ok(item) => items.push(item)
      Err(error) => return Err(error)
    }
  }
  Ok({ viewport, clip_chains, items, })
}

///|
/// Validate the complete SceneSnapshot v1 contract without touching Canvas.
pub fn validate_scene(
  snapshot : Json,
  width : Double,
  height : Double,
  scale : Double,
) -> Result[Unit, CanvasSceneError] {
  match parse_validated_scene(snapshot, width, height, scale) {
    Ok(_) => Ok(())
    Err(error) => Err(error)
  }
}

///|
fn clip_rect(context : BrowserValue, bounds : SceneRect) -> Unit {
  canvas_clip(context, bounds.x, bounds.y, bounds.width, bounds.height)
}

///|
/// Validate a complete scene then paint the supported quad/text subset.
fn draw_scene_snapshot(
  context : BrowserValue,
  snapshot : Json,
  width : Double,
  height : Double,
  scale : Double,
) -> Result[Unit, CanvasSceneError] {
  let scene = match parse_validated_scene(snapshot, width, height, scale) {
    Ok(scene) => scene
    Err(error) => return Err(error)
  }
  if !canvas_is_context_usable(context) {
    return Err(
      scene_error(
        "The browser Canvas 2D context is unavailable.",
        code="surface_lost",
      ),
    )
  }
  canvas_save(context)
  canvas_set_transform(context, scale)
  canvas_clear(context, width, height)
  canvas_set_source_over(context)
  clip_rect(context, scene.viewport)
  let font_family = canvas_root_css_property(context, "--dsh-font-family")
  let font_family = if font_family == "" {
    "system-ui, sans-serif"
  } else {
    font_family
  }
  for item in scene.items {
    canvas_save(context)
    match item.clip_chain_id {
      Some(id) =>
        match scene.clip_chains.get(id) {
          Some(rects) =>
            for bounds in rects {
              clip_rect(context, bounds)
            }
          None => ()
        }
      None => ()
    }
    let transform = item.transform
    canvas_transform(
      context,
      transform.a,
      transform.b,
      transform.c,
      transform.d,
      transform.tx,
      transform.ty,
    )
    canvas_set_alpha(context, item.opacity)
    let color = item.color
    canvas_set_color(
      context,
      color.red,
      color.green,
      color.blue,
      color.alpha.to_double() / 255.0,
    )
    let bounds = item.bounds
    if item.kind == "quad" {
      canvas_fill_rect(context, bounds.x, bounds.y, bounds.width, bounds.height)
    } else {
      clip_rect(context, bounds)
      canvas_set_text_font(context, item.font_size, font_family)
      canvas_fill_text(context, item.text, bounds.x, bounds.y)
    }
    canvas_restore(context)
  }
  canvas_restore(context)
  Ok(())
}
