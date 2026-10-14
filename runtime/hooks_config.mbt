///|
const NATIVE_HOOK_CONFIG_LIMIT : Int32 = 65536

///|
const NATIVE_HOOK_MAX_GROUPS : Int32 = 16

///|
const NATIVE_HOOK_MAX_COMMANDS : Int32 = 32

///|
priv struct NativeHookCommand {
  command : String
  timeout_ms : Int32
}

///|
priv struct NativeHookGroup {
  matcher : String?
  codex_regex : @string.Regex?
  commands : Array[NativeHookCommand]
}

///|
priv struct NativeHooks {
  session_start : Array[NativeHookGroup]
  pre_tool : Array[NativeHookGroup]
  post_tool : Array[NativeHookGroup]
  user_prompt_submit : Array[NativeHookGroup]
  stop : Array[NativeHookGroup]
  subagent_start : Array[NativeHookGroup]
  subagent_stop : Array[NativeHookGroup]
  dialect : String
  model : String
  project_dir : String
  mut handler_counter : Int32
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
/// Codex matchers use JavaScript RegExp search semantics. This adapter accepts
/// an explicitly bounded ASCII subset: literals, groups, alternation,
/// positive ASCII character classes, and quantifiers. Dot, negated/POSIX
/// classes, flags, Unicode patterns, and nonportable escapes are rejected so
/// they cannot silently acquire different MoonBit-regex semantics.
fn native_hook_codex_regex_supported(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return value.is_empty()
  }
  let characters = value.to_array()
  let mut index = 0
  while index < characters.length() {
    let character = characters[index]
    if character.to_int() > 0x7F || character == '.' {
      return false
    }
    if character == '^' && index != 0 {
      return false
    }
    if character == '$' && index != characters.length() - 1 {
      return false
    }
    if character == '\\' {
      index += 1
      if index >= characters.length() ||
        !['\\', '^', '$', '*', '+', '?', '{', '}', '[', ']', '(', ')', '|'].contains(
          characters[index],
        ) {
        return false
      }
    } else if character == '[' {
      index += 1
      if index < characters.length() && characters[index] == '^' {
        return false
      }
      let mut has_member = false
      let mut closed = false
      while index < characters.length() {
        if characters[index] == ']' {
          closed = has_member
          break
        }
        let class_char = characters[index]
        if class_char.to_int() > 0x7F ||
          class_char == '[' ||
          class_char == '\\' ||
          class_char == ':' {
          return false
        }
        if class_char == '-' &&
          (
            index <= 1 ||
            index + 1 >= characters.length() ||
            characters[index + 1] == ']'
          ) {
          return false
        }
        has_member = true
        index += 1
      }
      if !closed {
        return false
      }
    } else if character == '(' &&
      index + 1 < characters.length() &&
      characters[index + 1] == '?' {
      if index + 2 >= characters.length() || characters[index + 2] != ':' {
        return false
      }
      index += 2
    }
    index += 1
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
  dialect : String,
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
    // The pinned Claude Code bridge discards matcher values for
    // UserPromptSubmit and Stop because neither event has a matcher subject.
    let matcher = if event == "UserPromptSubmit" || event == "Stop" {
      None
    } else {
      let matcher = match native_hook_string(fields.get("matcher"), "matcher") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match matcher {
        Some(value) if dialect == "claude-code" &&
          !native_hook_valid_literal_matcher(value) =>
          return Err(
            "hook matcher must use literal tool names separated by |; regex is unsupported",
          )
        Some(value) if dialect == "codex" &&
          !native_hook_codex_regex_supported(value) =>
          return Err(
            "Codex matcher uses syntax outside the supported ASCII regex subset",
          )
        _ => ()
      }
      matcher
    }
    let codex_regex = match (dialect, matcher) {
      ("codex", Some(pattern)) if !pattern.is_empty() && pattern != "*" => {
        let regex = @string.Regex(pattern) catch {
          _ => return Err("invalid Codex regex matcher")
        }
        Some(regex)
      }
      _ => None
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
    output.push({ matcher, codex_regex, commands: parsed_commands, })
  }
  Ok(output)
}

///|
fn native_hook_parse_codex_command(value : Json) -> NativeHookCommand? {
  let fields = match native_hook_object(value) {
    Some(value) => value
    None => return None
  }
  let hook_type = match fields.get("type") {
    Some(Json::String(value)) => value
    _ => "command"
  }
  if hook_type != "command" || fields.get("async") == Some(Json::boolean(true)) {
    return None
  }
  let command = match fields.get("command") {
    Some(Json::String(value)) if !value.contains("\u0000") &&
      !value.trim().is_empty() &&
      value.length() <= 8192 => value
    _ => return None
  }
  let timeout = match fields.get("timeout") {
    Some(Json::Number(value, ..)) => Some(value)
    _ =>
      match fields.get("timeoutSec") {
        Some(Json::Number(value, ..)) => Some(value)
        _ => None
      }
  }
  let timeout_ms = match timeout {
    None => NATIVE_HOOK_DEFAULT_TIMEOUT_MS
    Some(value) if value >= 1.0 &&
      value <= NATIVE_HOOK_MAX_TIMEOUT_MS.to_double() / 1000.0 &&
      value.to_int().to_double() == value => value.to_int() * 1000
    Some(_) => return None
  }
  Some({ command, timeout_ms, })
}

///|
fn native_hook_parse_codex_groups(
  value : Json?,
  event : String,
) -> Result[Array[NativeHookGroup], String] {
  let groups = match value {
    Some(Json::Array(values)) => values
    _ => return Ok([])
  }
  let output : Array[NativeHookGroup] = []
  for raw_group in groups {
    let fields = match native_hook_object(raw_group) {
      Some(value) => value
      None => continue
    }
    let raw_commands = match fields.get("hooks") {
      Some(Json::Array(values)) => values
      _ => continue
    }
    let commands : Array[NativeHookCommand] = []
    for raw_command in raw_commands {
      match native_hook_parse_codex_command(raw_command) {
        Some(command) => commands.push(command)
        None => ()
      }
    }
    if commands.is_empty() {
      continue
    }
    let matcher = if event == "UserPromptSubmit" || event == "Stop" {
      None
    } else {
      match fields.get("matcher") {
        Some(Json::String(value)) => Some(value)
        _ => None
      }
    }
    match matcher {
      Some(pattern) if !native_hook_codex_regex_supported(pattern) =>
        return Err(
          "Codex matcher uses syntax outside the supported ASCII regex subset",
        )
      _ => ()
    }
    let codex_regex = match matcher {
      Some(pattern) if !pattern.is_empty() && pattern != "*" => {
        let regex = @string.Regex(pattern) catch {
          _ => return Err("invalid Codex regex matcher")
        }
        Some(regex)
      }
      _ => None
    }
    output.push({ matcher, codex_regex, commands, })
  }
  Ok(output)
}

///|
fn native_hook_parse_config(
  value : Json,
  dialect~ : String = "claude-code",
) -> Result[
  (
    Array[NativeHookGroup],
    Array[NativeHookGroup],
    Array[NativeHookGroup],
    Array[NativeHookGroup],
    Array[NativeHookGroup],
    Array[NativeHookGroup],
    Array[NativeHookGroup],
  ),
  String,
] {
  let root = match native_hook_object(value) {
    Some(value) => value
    None => return Err("hooks config must be a JSON object")
  }
  let hook_map = match root.get("hooks") {
    Some(hooks) => {
      if dialect == "claude-code" {
        match native_hook_exact_fields(root, ["hooks"], "settings wrapper") {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      match native_hook_object(hooks) {
        Some(value) => value
        None if dialect == "codex" => root
        None => return Err("hooks field must be an object")
      }
    }
    None => root
  }
  if dialect == "codex" {
    let session_start = match
      native_hook_parse_codex_groups(
        hook_map.get("SessionStart"),
        "SessionStart",
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let pre_tool = match
      native_hook_parse_codex_groups(hook_map.get("PreToolUse"), "PreToolUse") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let post_tool = match
      native_hook_parse_codex_groups(hook_map.get("PostToolUse"), "PostToolUse") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let user_prompt_submit = match
      native_hook_parse_codex_groups(
        hook_map.get("UserPromptSubmit"),
        "UserPromptSubmit",
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let stop = match
      native_hook_parse_codex_groups(hook_map.get("Stop"), "Stop") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return Ok(
      (session_start, pre_tool, post_tool, user_prompt_submit, stop, [], []),
    )
  }
  match
    native_hook_exact_fields(
      hook_map,
      [
        "SessionStart", "PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop",
        "SubagentStart", "SubagentStop",
      ],
      "hook event",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let session_start = match
    native_hook_parse_groups(
      hook_map.get("SessionStart"),
      "SessionStart",
      dialect,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pre_tool = match
    native_hook_parse_groups(hook_map.get("PreToolUse"), "PreToolUse", dialect) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let post_tool = match
    native_hook_parse_groups(
      hook_map.get("PostToolUse"),
      "PostToolUse",
      dialect,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let user_prompt_submit = match
    native_hook_parse_groups(
      hook_map.get("UserPromptSubmit"),
      "UserPromptSubmit",
      dialect,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let stop = match
    native_hook_parse_groups(hook_map.get("Stop"), "Stop", dialect) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let subagent_start = match
    native_hook_parse_groups(
      hook_map.get("SubagentStart"),
      "SubagentStart",
      dialect,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let subagent_stop = match
    native_hook_parse_groups(
      hook_map.get("SubagentStop"),
      "SubagentStop",
      dialect,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if session_start.is_empty() &&
    pre_tool.is_empty() &&
    post_tool.is_empty() &&
    user_prompt_submit.is_empty() &&
    stop.is_empty() &&
    subagent_start.is_empty() &&
    subagent_stop.is_empty() {
    return Err("hooks config must define at least one supported command hook")
  }
  Ok(
    (
      session_start, pre_tool, post_tool, user_prompt_submit, stop, subagent_start,
      subagent_stop,
    ),
  )
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
  dialect~ : String = "claude-code",
  model~ : String = "",
) -> Result[NativeHooks, String] {
  if dialect != "claude-code" && dialect != "codex" {
    return Err("hooks dialect must be claude-code or codex")
  }
  match path {
    None =>
      Ok({
        session_start: [],
        pre_tool: [],
        post_tool: [],
        user_prompt_submit: [],
        stop: [],
        subagent_start: [],
        subagent_stop: [],
        dialect,
        model,
        project_dir,
        handler_counter: 0,
      })
    Some(path) => {
      let text = match native_hook_read_config(path) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let document = @json.parse(text) catch {
        _ => return Err("hooks config is not valid JSON")
      }
      match native_hook_parse_config(document, dialect~) {
        Ok(
          (
            session_start,
            pre_tool,
            post_tool,
            user_prompt_submit,
            stop,
            subagent_start,
            subagent_stop,
          )
        ) =>
          Ok({
            session_start,
            pre_tool,
            post_tool,
            user_prompt_submit,
            stop,
            subagent_start,
            subagent_stop,
            dialect,
            model,
            project_dir,
            handler_counter: 0,
          })
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
fn native_hook_group_matches(
  group : NativeHookGroup,
  subject : String,
  dialect : String,
) -> Bool {
  match dialect {
    "codex" =>
      match group.matcher {
        None | Some("") | Some("*") => true
        Some(_) =>
          match group.codex_regex {
            Some(regex) => regex.execute(subject) is Some(_)
            None => false
          }
      }
    _ => native_hook_matches(group.matcher, subject)
  }
}

///|
