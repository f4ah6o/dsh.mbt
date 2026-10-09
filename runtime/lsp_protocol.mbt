///|
fn native_lsp_file_uri(path : String) -> String {
  let builder = StringBuilder()
  builder.write_string("file://")
  for byte in @utf8.encode(path) {
    let value = byte.to_int()
    if (value >= 'A'.to_int() && value <= 'Z'.to_int()) ||
      (value >= 'a'.to_int() && value <= 'z'.to_int()) ||
      (value >= '0'.to_int() && value <= '9'.to_int()) ||
      value == '-'.to_int() ||
      value == '_'.to_int() ||
      value == '.'.to_int() ||
      value == '~'.to_int() ||
      value == '/'.to_int() {
      builder.write_char(value.unsafe_to_char())
    } else {
      builder.write_char('%')
      let hex = value.to_string(radix=16)
      if hex.length() == 1 {
        builder.write_char('0')
      }
      builder.write_string(native_lsp_ascii_upper(hex))
    }
  }
  builder.to_string()
}

///|
fn native_lsp_ascii_upper(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character >= 'a' && character <= 'z' {
      builder.write_char((character.to_int() - 32).unsafe_to_char())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn native_lsp_basename(path : String) -> String {
  let parts = path.split("/").to_array()
  if parts.is_empty() {
    path
  } else {
    parts[parts.length() - 1].to_owned()
  }
}

///|
fn native_lsp_decode_path_segment(value : String) -> Result[String, String] {
  let chars = value.to_array()
  let bytes : Array[Byte] = []
  let mut index = 0
  while index < chars.length() {
    let character = chars[index]
    if character == '%' {
      if index + 2 >= chars.length() {
        return Err("LSP location URI has an incomplete percent escape")
      }
      let high = match native_lsp_hex_value(chars[index + 1]) {
        Some(value) => value
        None => return Err("LSP location URI has an invalid percent escape")
      }
      let low = match native_lsp_hex_value(chars[index + 2]) {
        Some(value) => value
        None => return Err("LSP location URI has an invalid percent escape")
      }
      let decoded = (high << 4) | low
      if decoded == 0 || decoded == '/'.to_int() || decoded == '\\'.to_int() {
        return Err("LSP location URI encodes a path separator or NUL")
      }
      bytes.push(decoded.to_byte())
      index += 3
    } else {
      if character == '\\' || character == '/' || character == '\u0000' {
        return Err("LSP location URI contains an invalid path separator")
      }
      for byte in @utf8.encode(character.to_string()) {
        bytes.push(byte)
      }
      index += 1
    }
  }
  let decoded = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("LSP location URI contains invalid UTF-8")
  }
  if decoded == "." || decoded == ".." || decoded.is_empty() {
    return Err("LSP location URI contains a traversal path segment")
  }
  Ok(decoded)
}

///|
fn native_lsp_local_file_uri_path(uri : String) -> String? {
  if uri.length() < 8 ||
    native_lsp_ascii_lower(uri[:5].to_owned()) != "file:" ||
    !uri[5:].has_prefix("//") ||
    uri.contains("?") ||
    uri.contains("#") {
    return None
  }
  let remainder = uri[7:].to_owned()
  let (authority, raw_path) = if remainder.has_prefix("/") {
    ("", remainder)
  } else {
    let chars = remainder.to_array()
    let mut slash = -1
    for index in 0..<chars.length() {
      if chars[index] == '/' {
        slash = index
        break
      }
    }
    if slash <= 0 {
      return None
    }
    (remainder[:slash].to_owned(), remainder[slash:].to_owned())
  }
  if authority != "" && native_lsp_ascii_lower(authority) != "localhost" {
    return None
  }
  if !raw_path.has_prefix("/") {
    return None
  }
  let raw_components = raw_path.split("/").to_array()
  let components : Array[String] = []
  for index in 1..<raw_components.length() {
    let raw = raw_components[index].to_owned()
    let component = match native_lsp_decode_path_segment(raw) {
      Ok(value) => value
      Err(_) => return None
    }
    components.push(component)
  }
  Some("/" + components.join("/"))
}

///|
fn native_lsp_workspace_location_path(
  uri : String,
  workspace : String,
  root : SafeRoot,
  blocked_path? : String? = None,
) -> String? {
  let absolute_path = match native_lsp_local_file_uri_path(uri) {
    Some(value) => value
    None => return None
  }
  let workspace_prefix = if workspace == "/" { "/" } else { workspace + "/" }
  if !absolute_path.has_prefix(workspace_prefix) || absolute_path == workspace {
    return None
  }
  let relative_path = absolute_path[workspace_prefix.length():].to_owned()
  if relative_path.is_empty() {
    return None
  }
  if blocked_path is Some(blocked) &&
    (relative_path == blocked || relative_path.has_prefix(blocked + "/")) {
    return None
  }
  let fd = match root.open_regular(relative_path) {
    Ok(value) => value
    Err(_) => return None
  }
  ignore(c_close(fd))
  Some(relative_path)
}

///|
fn native_lsp_wire_coordinate(value : Json?) -> Int? {
  match value {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 10000000.0 &&
      number.to_int().to_double() == number => Some(number.to_int())
    _ => None
  }
}

///|
fn native_lsp_wire_position(value : Json?) -> Bool {
  match value {
    Some(Json::Object(fields)) =>
      native_lsp_wire_coordinate(fields.get("line")) is Some(_) &&
      native_lsp_wire_coordinate(fields.get("character")) is Some(_)
    _ => false
  }
}

///|
fn native_lsp_wire_range(value : Json?) -> Bool {
  match value {
    Some(Json::Object(fields)) =>
      native_lsp_wire_position(fields.get("start")) &&
      native_lsp_wire_position(fields.get("end"))
    _ => false
  }
}

///|
fn native_lsp_location_fields(value : Json) -> Result[(String, Json), String] {
  let fields = match native_lsp_json_object(value) {
    Some(fields) => fields
    None => return Err("LSP navigation result contained a non-object entry")
  }
  match
    (
      native_lsp_json_string(fields.get("targetUri")),
      fields.get("targetSelectionRange"),
    ) {
    (Some(uri), Some(range)) if uri.length() <= 4096 &&
      native_lsp_wire_range(Some(range)) => Ok((uri, range))
    _ =>
      match (native_lsp_json_string(fields.get("uri")), fields.get("range")) {
        (Some(uri), Some(range)) if uri.length() <= 4096 &&
          native_lsp_wire_range(Some(range)) => Ok((uri, range))
        _ =>
          Err(
            "LSP navigation result contained neither a Location nor a LocationLink",
          )
      }
  }
}

///|
fn native_lsp_range_start(range : Json) -> (Int, Int) {
  let start = object_field(range, "start").unwrap_or(Json::null())
  (
    native_lsp_wire_coordinate(object_field(start, "line")).unwrap_or(0),
    native_lsp_wire_coordinate(object_field(start, "character")).unwrap_or(0),
  )
}

///|
fn native_lsp_cap_result(text : String, label : String) -> String {
  let chars = text.to_array()
  if chars.length() <= NATIVE_LSP_MAX_RESULT_CHARS {
    return text
  }
  let suffix = "\n… " + label + " truncated (limit 16000 characters)."
  let limit = Int::max(0, NATIVE_LSP_MAX_RESULT_CHARS - suffix.length())
  let builder = StringBuilder()
  for index in 0..<limit {
    builder.write_char(chars[index])
  }
  builder.write_string(suffix)
  builder.to_string()
}

///|
fn native_lsp_render_locations(
  payload : Json,
  workspace : String,
  root : SafeRoot,
  blocked_path? : String? = None,
) -> Result[String, String] {
  let values = match payload {
    Json::Null => []
    Json::Array(values) => values
    value => [value]
  }
  if values.is_empty() {
    return Ok("No results.")
  }
  let lines : Array[String] = []
  let mut omitted = 0
  let mut rendered = 0
  let mut examined = 0
  for index, value in values {
    if examined >= 4096 {
      omitted += values.length() - index
      break
    }
    examined += 1
    let (uri, range) = match native_lsp_location_fields(value) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match
      native_lsp_workspace_location_path(uri, workspace, root, blocked_path~) {
      None => omitted += 1
      Some(path) =>
        if rendered >= NATIVE_LSP_MAX_LOCATIONS {
          omitted += 1
        } else {
          rendered += 1
          let (line, character) = native_lsp_range_start(range)
          lines.push(
            path +
            ":" +
            (line + 1).to_string() +
            ":" +
            (character + 1).to_string(),
          )
        }
    }
  }
  if omitted > 0 {
    lines.push(
      "… " +
      omitted.to_string() +
      " location(s) omitted (outside the workspace, protected, or beyond the result limit).",
    )
  }
  if lines.is_empty() {
    Ok("No in-workspace results.")
  } else {
    Ok(native_lsp_cap_result(lines.join("\n"), "locations"))
  }
}

///|
fn native_lsp_marked_string(value : Json) -> Result[String, String] {
  match value {
    Json::String(text) => Ok(text)
    Json::Object(fields) =>
      match
        (
          native_lsp_json_string(fields.get("language")),
          native_lsp_json_string(fields.get("value")),
        ) {
        (Some(language), Some(text)) if language.length() <= 64 &&
          native_lsp_valid_identifier(language, 64) =>
          Ok("```" + language + "\n" + text + "\n```")
        (Some(_), Some(text)) => Ok(text)
        _ => Err("LSP hover contents contained a malformed MarkedString")
      }
    _ => Err("LSP hover contents contained a malformed MarkedString")
  }
}

///|
fn native_lsp_hover_text(payload : Json) -> Result[String, String] {
  match payload {
    Json::Null => Ok("No hover information.")
    Json::Object(fields) => {
      match fields.get("range") {
        Some(range) if !native_lsp_wire_range(Some(range)) =>
          return Err("LSP hover result contains a malformed range")
        _ => ()
      }
      match fields.get("contents") {
        Some(Json::String(text)) => Ok(text)
        Some(Json::Array(parts)) if parts.length() <= 256 => {
          let rendered : Array[String] = []
          for part in parts {
            rendered.push(
              match native_lsp_marked_string(part) {
                Ok(value) => value
                Err(error) => return Err(error)
              },
            )
          }
          Ok(rendered.join("\n\n"))
        }
        Some(Json::Object(content)) =>
          match
            (
              native_lsp_json_string(content.get("kind")),
              native_lsp_json_string(content.get("value")),
            ) {
            (Some(kind), Some(text)) if kind == "markdown" ||
              kind == "plaintext" => Ok(text)
            (Some(_), Some(_)) =>
              Err("LSP hover used an unsupported MarkupContent kind")
            _ => native_lsp_marked_string(Json::object(content))
          }
        None => Err("LSP hover result has no contents")
        _ => Err("LSP hover contents are malformed")
      }
    }
    _ => Err("LSP hover result is not an object or null")
  }
}

///|
fn native_lsp_project_result(
  operation : String,
  payload : Json,
  workspace : String,
  root : SafeRoot,
  blocked_path? : String? = None,
) -> Result[String, String] {
  if operation == "hover" {
    match native_lsp_hover_text(payload) {
      Ok(value) => Ok(native_lsp_cap_result(value, "hover"))
      Err(error) => Err(error)
    }
  } else {
    // The root is anchored to the canonical workspace and opened read-only to
    // verify each reported target without following symlinks or accepting
    // aliases outside the workspace.
    match native_lsp_render_locations(payload, workspace, root, blocked_path~) {
      Ok(value) => Ok(value)
      Err(error) => Err(error)
    }
  }
}
