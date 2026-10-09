///|
const NATIVE_HOOK_CONFIG_LIMIT : Int = 65536

///|
const NATIVE_HOOK_MAX_GROUPS : Int = 16

///|
const NATIVE_HOOK_MAX_COMMANDS : Int = 32

///|
priv struct NativeHookCommand {
  command : String
  timeout_ms : Int
}

///|
priv struct NativeHookGroup {
  matcher : String?
  commands : Array[NativeHookCommand]
}

///|
priv struct NativeHooks {
  pre_tool : Array[NativeHookGroup]
  post_tool : Array[NativeHookGroup]
  project_dir : String
}

///|
fn native_hook_object(value : Json) -> Map[String, Json]? {
  match value {
    Json::Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn native_hook_string(value : Json?, field : String) -> Result[String?, String] {
  match value {
    None => Ok(None)
    Some(Json::String(text)) if !text.contains("\u0000") => Ok(Some(text))
    _ => Err("hook config field must be a string: " + field)
  }
}

///|
fn native_hook_exact_fields(
  fields : Map[String, Json],
  allowed : Array[String],
  context : String,
) -> Result[Unit, String] {
  for key, _ in fields {
    if !allowed.contains(key) {
      return Err("unsupported " + context + " field: " + key)
    }
  }
  Ok(())
}

///|
fn native_hook_valid_literal_matcher(value : String) -> Bool {
  if value.length() > 128 {
    return false
  }
  if value == "*" {
    return true
  }
  for character in value {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' ||
      character == '|') {
      return false
    }
  }
  true
}

///|
fn native_hook_parse_command(value : Json) -> Result[NativeHookCommand, String] {
  let fields = match native_hook_object(value) {
    Some(value) => value
    None => return Err("hook command must be an object")
  }
  match
    native_hook_exact_fields(
      fields,
      ["type", "command", "timeout"],
      "hook command",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match fields.get("type") {
    None | Some(Json::String("command")) => ()
    Some(_) => return Err("only command hooks are supported")
  }
  let command = match native_hook_string(fields.get("command"), "command") {
    Ok(Some(value)) if !value.trim().is_empty() && value.length() <= 8192 =>
      value
    _ =>
      return Err(
        "hook command must be a nonempty string of at most 8192 characters",
      )
  }
  if command.contains("${CLAUDE_PLUGIN_ROOT}") {
    return Err("${CLAUDE_PLUGIN_ROOT} substitution is not supported")
  }
  let timeout_ms = match fields.get("timeout") {
    None => NATIVE_HOOK_DEFAULT_TIMEOUT_MS
    Some(Json::Number(value, ..)) if value >= 1.0 &&
      value <= NATIVE_HOOK_MAX_TIMEOUT_MS.to_double() / 1000.0 &&
      value.to_int().to_double() == value => value.to_int() * 1000
    _ => return Err("hook timeout must be an integer between 1 and 120 seconds")
  }
  Ok({ command, timeout_ms, })
}

///|
fn native_hook_parse_groups(
  value : Json?,
  event : String,
) -> Result[Array[NativeHookGroup], String] {
  let groups = match value {
    None => return Ok([])
    Some(Json::Array(values)) if values.length() <= NATIVE_HOOK_MAX_GROUPS =>
      values
    _ => return Err(event + " must be an array of at most 16 matcher groups")
  }
  let output : Array[NativeHookGroup] = []
  let mut command_count = 0
  for raw_group in groups {
    let fields = match native_hook_object(raw_group) {
      Some(value) => value
      None => return Err(event + " matcher group must be an object")
    }
    match
      native_hook_exact_fields(fields, ["matcher", "hooks"], "matcher group") {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    let matcher = match native_hook_string(fields.get("matcher"), "matcher") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match matcher {
      Some(value) if !native_hook_valid_literal_matcher(value) =>
        return Err(
          "hook matcher must use literal tool names separated by |; regex is unsupported",
        )
      _ => ()
    }
    let commands = match fields.get("hooks") {
      Some(Json::Array(values)) if !values.is_empty() => values
      _ => return Err(event + " matcher group hooks must be a nonempty array")
    }
    let parsed_commands : Array[NativeHookCommand] = []
    for raw_command in commands {
      command_count += 1
      if command_count > NATIVE_HOOK_MAX_COMMANDS {
        return Err("each hook event is limited to 32 commands")
      }
      let command = match native_hook_parse_command(raw_command) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      parsed_commands.push(command)
    }
    output.push({ matcher, commands: parsed_commands, })
  }
  Ok(output)
}

///|
fn native_hook_parse_config(
  value : Json,
) -> Result[(Array[NativeHookGroup], Array[NativeHookGroup]), String] {
  let root = match native_hook_object(value) {
    Some(value) => value
    None => return Err("hooks config must be a JSON object")
  }
  let hook_map = match root.get("hooks") {
    Some(hooks) => {
      match native_hook_exact_fields(root, ["hooks"], "settings wrapper") {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      match native_hook_object(hooks) {
        Some(value) => value
        None => return Err("hooks field must be an object")
      }
    }
    None => root
  }
  match
    native_hook_exact_fields(
      hook_map,
      ["PreToolUse", "PostToolUse"],
      "hook event",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let pre_tool = match
    native_hook_parse_groups(hook_map.get("PreToolUse"), "PreToolUse") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let post_tool = match
    native_hook_parse_groups(hook_map.get("PostToolUse"), "PostToolUse") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if pre_tool.is_empty() && post_tool.is_empty() {
    return Err(
      "hooks config must define at least one PreToolUse or PostToolUse command",
    )
  }
  Ok((pre_tool, post_tool))
}

///|
async fn native_hook_read_config(path : String) -> Result[String, String] {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch {
    _ => return Err("cannot read hooks config")
  }
  defer file.close()
  if file.kind() != @fs.Regular {
    return Err("hooks config must be a regular file")
  }
  let size = file.size() catch {
    _ => return Err("cannot determine hooks config size")
  }
  if size < 0L || size > NATIVE_HOOK_CONFIG_LIMIT.to_int64() {
    return Err("hooks config exceeds the 64 KiB limit")
  }
  let bytes : Array[Byte] = []
  while true {
    let chunk = file.read_some(max_len=8192) catch {
      _ => return Err("cannot read hooks config")
    }
    match chunk {
      None => break
      Some(chunk) =>
        for byte in chunk {
          if bytes.length() >= NATIVE_HOOK_CONFIG_LIMIT {
            return Err("hooks config exceeds the 64 KiB limit")
          }
          bytes.push(byte)
        }
    }
  }
  let decoded = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("hooks config is not valid UTF-8")
  }
  Ok(decoded)
}

///|
async fn NativeHooks::load(
  path : String?,
  project_dir : String,
) -> Result[NativeHooks, String] {
  match path {
    None => Ok({ pre_tool: [], post_tool: [], project_dir, })
    Some(path) => {
      let text = match native_hook_read_config(path) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let document = @json.parse(text) catch {
        _ => return Err("hooks config is not valid JSON")
      }
      match native_hook_parse_config(document) {
        Ok((pre_tool, post_tool)) => Ok({ pre_tool, post_tool, project_dir, })
        Err(error) => Err(error)
      }
    }
  }
}

///|
fn native_hook_matches(matcher : String?, tool_name : String) -> Bool {
  match matcher {
    None | Some("") | Some("*") => true
    Some(pattern) => {
      for candidate in pattern.split("|") {
        if candidate.to_owned() == tool_name {
          return true
        }
      }
      false
    }
  }
}

///|
