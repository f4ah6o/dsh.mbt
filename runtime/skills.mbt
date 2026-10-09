///|
const NATIVE_SKILL_FILE_LIMIT : Int = 65536

///|
const NATIVE_SKILL_BODY_LIMIT : Int = 60000

///|
const NATIVE_SKILL_DESCRIPTION_LIMIT : Int = 4096

///|
const NATIVE_SKILL_CATALOG_LIMIT : Int = 64

///|
const NATIVE_SKILL_MODEL_CATALOG_LIMIT : Int = 16

///|
const NATIVE_SKILL_PATH_LIMIT : Int = 4096

///|
priv struct NativeSkill {
  name : String
  description : String
  model_invocable : Bool
  user_invocable : Bool
  source : String
  path : String
  resource_base : String
}

///|
priv struct NativeSkills {
  entries : Array[NativeSkill]
  enabled : Bool
}

///|
priv struct NativeSkillParsed {
  name : String
  description : String
  model_invocable : Bool
  user_invocable : Bool
  content : String
}

///|
fn native_skill_name_valid(name : String) -> Bool {
  if name.is_empty() || name.length() > 64 {
    return false
  }
  let chars = name.to_array()
  let mut previous_hyphen = true
  for index in 0..<chars.length() {
    let character = chars[index]
    let alphanumeric = (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9')
    if alphanumeric {
      previous_hyphen = false
    } else if character == '-' && !previous_hyphen && index + 1 < chars.length() {
      previous_hyphen = true
    } else {
      return false
    }
  }
  !previous_hyphen
}

///|
fn native_skill_relative_path(path : String) -> Result[String, String] {
  if path.is_empty() ||
    path.length() > NATIVE_SKILL_PATH_LIMIT ||
    path.contains("\u0000") ||
    path.has_prefix("/") ||
    path.has_prefix("\\") {
    return Err("skill directories must be nonempty workspace-relative paths")
  }
  let parts : Array[String] = []
  for part in path.split("/") {
    if part == ".." {
      return Err("skill directory escapes the workspace")
    }
    if part.contains("\\") {
      return Err("skill directory must use workspace path separators")
    }
    if part != "" && part != "." {
      parts.push(part.to_owned())
    }
  }
  if parts.is_empty() {
    return Err("skill directory must not be the workspace root")
  }
  Ok(parts.join("/"))
}

///|
fn native_skill_path_is_protected(
  path : String,
  blocked_path : String?,
) -> Bool {
  match blocked_path {
    None => false
    Some(blocked) => path == blocked || path.has_prefix(blocked + "/")
  }
}

///|
fn native_skill_directory_exists(
  root : SafeRoot,
  path : String,
  blocked_path : String?,
) -> Result[Bool, String] {
  if native_skill_path_is_protected(path, blocked_path) {
    return Ok(false)
  }
  let mut current = ""
  for raw_component in path.split("/") {
    let component = raw_component.to_owned()
    let parent = if current.is_empty() { "." } else { current }
    let entries = match root.list_directory(parent) {
      Ok(value) => value
      Err(_) => return Ok(false)
    }
    let mut found = false
    for (name, kind) in entries {
      if name == component {
        if kind != "directory" {
          return Ok(false)
        }
        found = true
        break
      }
    }
    if !found {
      return Ok(false)
    }
    current = if current.is_empty() {
      component
    } else {
      current + "/" + component
    }
  }
  Ok(true)
}

///|
fn native_skill_scalar(value : String, key : String) -> Result[String, String] {
  let trimmed = value.trim().to_owned()
  if trimmed.is_empty() {
    return Ok("")
  }
  let chars = trimmed.to_array()
  if chars.length() >= 2 &&
    (
      (chars[0] == '\'' && chars[chars.length() - 1] == '\'') ||
      (chars[0] == '"' && chars[chars.length() - 1] == '"')
    ) {
    let quote = chars[0]
    let inner = String::from_array(chars[1:chars.length() - 1])
    if quote == '"' && inner.contains("\\") {
      return Err("quoted frontmatter escapes are unsupported")
    }
    Ok(if quote == '\'' { inner.replace_all(old="''", new="'") } else { inner })
  } else if chars[0] == '\'' || chars[0] == '"' {
    Err("frontmatter has an unterminated quoted scalar")
  } else if ['[', ']', '{', '}', '|', '>', '&', '*', '!', '`'].contains(
      chars[0],
    ) {
    Err("frontmatter supports plain and quoted string scalars only")
  } else {
    let plain = match trimmed.find(" #") {
      Some(index) => trimmed[:index].trim().to_owned()
      None => trimmed
    }
    if plain == "" {
      Ok("")
    } else if (plain.to_lower() == "true" || plain.to_lower() == "false") &&
      (key == "disable-model-invocation" || key == "user-invocable") {
      Ok(plain.to_lower())
    } else if plain.to_lower() == "true" ||
      plain.to_lower() == "false" ||
      plain.to_lower() == "null" ||
      plain == "~" ||
      native_skill_numeric_scalar(plain) {
      Err(
        "frontmatter string fields must use quotes for YAML non-string scalars",
      )
    } else {
      Ok(plain)
    }
  }
}

///|
fn native_skill_boolean(value : String, key : String) -> Result[Bool, String] {
  if value.is_empty() {
    return Err("frontmatter field " + key + " must be a boolean")
  }
  match value.trim().to_lower() {
    "true" => Ok(true)
    "false" => Ok(false)
    _ => Err("frontmatter field " + key + " must be a boolean")
  }
}

///|
fn native_skill_numeric_scalar(value : String) -> Bool {
  let chars = value.to_array()
  let length = chars.length()
  if length == 0 {
    return false
  }
  let lowered = value.to_lower()
  if lowered == ".inf" ||
    lowered == "+.inf" ||
    lowered == "-.inf" ||
    lowered == ".nan" ||
    lowered == "+.nan" ||
    lowered == "-.nan" {
    return true
  }
  let mut start = 0
  if chars[start] == '+' || chars[start] == '-' {
    start = start + 1
    if start == length {
      return false
    }
  }
  if start + 2 < length && chars[start] == '0' {
    let radix = match chars[start + 1] {
      'x' | 'X' => 16
      'o' | 'O' => 8
      'b' | 'B' => 2
      _ => 0
    }
    if radix != 0 {
      let (end, count, valid) = native_skill_scan_numeric_digits(
        chars,
        start + 2,
        radix,
      )
      return valid && count > 0 && end == length
    }
  }
  let (integer_end, integer_count, integer_valid) = native_skill_scan_numeric_digits(
    chars, start, 10,
  )
  let mut index = integer_end
  let mut fraction_count = 0
  let mut fraction_valid = true
  if index < length && chars[index] == '.' {
    let (end, count, valid) = native_skill_scan_numeric_digits(
      chars,
      index + 1,
      10,
    )
    index = end
    fraction_count = count
    fraction_valid = valid
  }
  if !integer_valid || !fraction_valid || integer_count + fraction_count == 0 {
    return false
  }
  if index < length && (chars[index] == 'e' || chars[index] == 'E') {
    index = index + 1
    if index < length && (chars[index] == '+' || chars[index] == '-') {
      index = index + 1
    }
    let (end, count, valid) = native_skill_scan_numeric_digits(chars, index, 10)
    if !valid || count == 0 {
      return false
    }
    index = end
  }
  index == length
}

///|
fn native_skill_scan_numeric_digits(
  chars : Array[Char],
  start : Int,
  radix : Int,
) -> (Int, Int, Bool) {
  let mut index = start
  let mut count = 0
  let mut previous_digit = false
  let mut valid = true
  while index < chars.length() {
    let character = chars[index]
    if native_skill_numeric_digit(character, radix) {
      count = count + 1
      previous_digit = true
      index = index + 1
    } else if character == '_' {
      if !previous_digit ||
        index + 1 >= chars.length() ||
        !native_skill_numeric_digit(chars[index + 1], radix) {
        valid = false
      }
      previous_digit = false
      index = index + 1
    } else {
      break
    }
  }
  (index, count, valid)
}

///|
fn native_skill_numeric_digit(character : Char, radix : Int) -> Bool {
  if character >= '0' && character <= '9' {
    character.to_int() - '0'.to_int() < radix
  } else if radix > 10 && character >= 'a' && character <= 'f' {
    character.to_int() - 'a'.to_int() + 10 < radix
  } else if radix > 10 && character >= 'A' && character <= 'F' {
    character.to_int() - 'A'.to_int() + 10 < radix
  } else {
    false
  }
}

///|
fn native_skill_boolean_field(
  fields : Map[String, String],
  key : String,
  fallback : Bool,
) -> Result[Bool, String] {
  match fields.get(key) {
    None => Ok(fallback)
    Some(value) => native_skill_boolean(value, key)
  }
}

///|
fn native_skill_parse(
  path : String,
  raw : String,
) -> Result[NativeSkillParsed, String] {
  if @utf8.encode(raw).length() > NATIVE_SKILL_FILE_LIMIT {
    return Err("skill file exceeds the 65536-byte limit")
  }
  let normalized = raw.replace_all(old="\r\n", new="\n")
  let lines : Array[String] = normalized
    .split("\n")
    .map(line => line.to_owned())
    .to_array()
  if lines.length() < 2 || lines[0] != "---" {
    return Err("skill file must start with YAML frontmatter")
  }
  let fields : Map[String, String] = Map([])
  let mut closing = -1
  for index in 1..<lines.length() {
    let line = lines[index]
    if line == "---" {
      closing = index
      break
    }
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    if line.has_prefix(" ") || line.has_prefix("\t") {
      return Err("nested or indented YAML frontmatter is unsupported")
    }
    let separator = match line.find(":") {
      Some(value) => value
      None => return Err("frontmatter field is missing ':'")
    }
    let key = line[:separator].trim().to_owned()
    let raw_value = line[separator + 1:].to_owned()
    if key.is_empty() || fields.get(key) is Some(_) {
      return Err("frontmatter contains an empty or duplicate field")
    }
    if ["disableModelInvocation", "modelInvocable", "userInvocable"].contains(
        key,
      ) {
      return Err("legacy invocation field " + key + " is unsupported")
    }
    if ![
        "name", "description", "whenToUse", "disable-model-invocation", "user-invocable",
      ].contains(key) {
      return Err("unsupported frontmatter field " + key)
    }
    let value = match native_skill_scalar(raw_value, key) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    fields[key] = value
  }
  if closing < 0 {
    return Err("skill file has no closing frontmatter delimiter")
  }
  let name = fields.get("name").unwrap_or("")
  let description = fields.get("description").unwrap_or("").trim().to_owned()
  if !native_skill_name_valid(name) {
    return Err("frontmatter name must be a kebab-case identifier")
  }
  if description.is_empty() ||
    description.length() > NATIVE_SKILL_DESCRIPTION_LIMIT ||
    description.contains("\u0000") {
    return Err(
      "frontmatter description is empty or exceeds the 4096-character limit",
    )
  }
  let disable_model = match
    native_skill_boolean_field(fields, "disable-model-invocation", false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let user_invocable = match
    native_skill_boolean_field(fields, "user-invocable", true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let body = lines[closing + 1:].join("\n").trim().to_owned()
  if @utf8.encode(body).length() > NATIVE_SKILL_BODY_LIMIT {
    return Err("skill instructions exceed the 60000-byte limit")
  }
  ignore(path)
  Ok({
    name,
    description,
    model_invocable: !disable_model,
    user_invocable,
    content: body,
  })
}

///|
fn native_skill_source_for_root(index : Int) -> String {
  if index == 0 {
    "project-dsh"
  } else if index == 1 {
    "project-agents"
  } else {
    "custom"
  }
}

///|
fn native_skill_add_root(
  root : SafeRoot,
  root_path : String,
  source : String,
  blocked_path : String?,
  entries : Array[NativeSkill],
  seen : Map[String, Bool],
) -> Result[Unit, String] {
  let exists = match
    native_skill_directory_exists(root, root_path, blocked_path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !exists {
    return Ok(())
  }
  let listing = match root.list_directory(root_path) {
    Ok(value) => value
    Err(_) => return Ok(())
  }
  if listing.length() > 1024 {
    return Err("skill directory exceeds the 1024-entry discovery limit")
  }
  listing.sort_by((left, right) => native_mcp_string_compare(left.0, right.0))
  for (entry_name, kind) in listing {
    let (instruction_path, resource_base) = if kind == "directory" {
      (root_path + "/" + entry_name + "/SKILL.md", root_path + "/" + entry_name)
    } else if kind == "file" && entry_name.has_suffix(".md") {
      (root_path + "/" + entry_name, root_path)
    } else {
      continue
    }
    if native_skill_path_is_protected(instruction_path, blocked_path) {
      continue
    }
    if @utf8.encode(instruction_path).length() > NATIVE_SKILL_PATH_LIMIT {
      continue
    }
    let raw = match
      root.read_text(instruction_path, max_bytes=NATIVE_SKILL_FILE_LIMIT) {
      Ok((value, _)) => value
      Err(_) => continue
    }
    let parsed = match native_skill_parse(instruction_path, raw) {
      Ok(value) => value
      Err(_) => continue
    }
    if seen.get(parsed.name) is Some(_) {
      continue
    }
    if entries.length() >= NATIVE_SKILL_CATALOG_LIMIT {
      return Err("skill catalog exceeds the 64-skill limit")
    }
    seen[parsed.name] = true
    entries.push({
      name: parsed.name,
      description: parsed.description,
      model_invocable: parsed.model_invocable,
      user_invocable: parsed.user_invocable,
      source,
      path: instruction_path,
      resource_base,
    })
  }
  Ok(())
}

///|
fn NativeSkills::discover(
  root : SafeRoot,
  enabled : Bool,
  custom_skill_dirs : Array[String],
  blocked_path : String?,
) -> Result[NativeSkills, String] {
  if custom_skill_dirs.length() > 8 {
    return Err("--skill-dir may be specified at most 8 times")
  }
  if !enabled && custom_skill_dirs.length() > 0 {
    return Err("--skill-dir requires --enable-skills")
  }
  let normalized_custom : Array[String] = []
  for path in custom_skill_dirs {
    let normalized = match native_skill_relative_path(path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    normalized_custom.push(normalized)
  }
  if !enabled {
    return Ok({ entries: [], enabled: false, })
  }
  let roots = [".dsh/skills", ".agents/skills"] + normalized_custom
  let entries : Array[NativeSkill] = []
  let seen : Map[String, Bool] = Map([])
  for index, root_path in roots {
    match
      native_skill_add_root(
        root,
        root_path,
        native_skill_source_for_root(index),
        blocked_path,
        entries,
        seen,
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  entries.sort_by((left, right) => {
    native_mcp_string_compare(left.name, right.name)
  })
  let model_count = entries.filter(entry => entry.model_invocable).length()
  if model_count > NATIVE_SKILL_MODEL_CATALOG_LIMIT {
    return Err("model skill catalog exceeds the 16-skill limit")
  }
  Ok({ entries, enabled: true, })
}

///|
fn NativeSkills::model_catalog(self : NativeSkills) -> Array[(String, String)] {
  self.entries
  .filter(entry => entry.model_invocable)
  .map(entry => {
    (entry.name, native_skill_catalog_description(entry.description))
  })
}

///|
fn native_skill_catalog_description(description : String) -> String {
  let normalized = StringBuilder()
  let mut pending_space = false
  let mut has_content = false
  for character in description {
    if character.is_whitespace() {
      pending_space = true
    } else {
      if pending_space && has_content {
        normalized.write_char(' ')
      }
      normalized.write_char(character)
      pending_space = false
      has_content = true
    }
  }
  let chars = normalized.to_string().to_array()
  let output = StringBuilder()
  let mut output_length = 0
  let mut was_clipped = false
  for character in chars {
    let escaped = match character {
      '&' => "&amp;"
      '<' => "&lt;"
      '>' => "&gt;"
      _ => character.to_string()
    }
    if output_length + escaped.length() > 117 {
      was_clipped = true
      break
    }
    output.write_string(escaped)
    output_length += escaped.length()
  }
  if was_clipped {
    output.write_string("...")
  }
  output.to_string()
}

///|
fn native_skill_escape_text(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn native_skill_find_entry(
  entries : Array[NativeSkill],
  name : String,
) -> NativeSkill? {
  for entry in entries {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
fn NativeSkills::parse_current(
  self : NativeSkills,
  root : SafeRoot,
  name : String,
) -> Result[(NativeSkill, NativeSkillParsed), String] {
  if !native_skill_name_valid(name) {
    return Err("invalid skill name")
  }
  let skill = match native_skill_find_entry(self.entries, name) {
    Some(value) => value
    None => return Err("skill is unknown or no longer available")
  }
  let raw = match
    root.read_text(skill.path, max_bytes=NATIVE_SKILL_FILE_LIMIT) {
    Ok((value, _)) => value
    Err(_) => return Err("skill is unknown or no longer available")
  }
  let parsed = match native_skill_parse(skill.path, raw) {
    Ok(value) => value
    Err(_) => return Err("skill is unknown or no longer available")
  }
  if parsed.name != skill.name {
    return Err("skill is unknown or no longer available")
  }
  Ok((skill, parsed))
}

///|
fn native_skill_render(skill : NativeSkill, content : String) -> String {
  let safe_base = native_skill_escape_text(skill.resource_base)
    .replace_all(old="\n", new=" ")
    .replace_all(old="\r", new=" ")
  [
    "<skill_content name=\"" +
    skill.name +
    "\" source=\"" +
    skill.source +
    "\">",
    "<skill_resources>",
    "Base directory for this skill in the workspace: " + safe_base,
    "Resolve relative paths against this directory. Load referenced files only as needed with workspace tools.",
    "</skill_resources>",
    "",
    "<skill_instructions>",
    content,
    "</skill_instructions>",
    "</skill_content>",
  ].join("\n")
}

///|
fn NativeSkills::execute(
  self : NativeSkills,
  root : SafeRoot,
  request : Json,
) -> Json {
  let arguments = match string_field(request, "arguments") {
    Some(raw) =>
      match parse_json(raw) {
        Ok(value) => value
        Err(_) => return tool_error("Tool arguments are not valid JSON")
      }
    None =>
      match object_field(request, "arguments") {
        Some(value) => value
        None => return tool_error("Tool arguments are missing")
      }
  }
  let name = match string_field(arguments, "name") {
    Some(value) if value.length() <= 64 => value
    Some(_) => return tool_error("name exceeds the 64-character limit")
    None => return tool_error("name must be a string")
  }
  let (skill, parsed) = match self.parse_current(root, name) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  if !skill.model_invocable || !parsed.model_invocable {
    return tool_error("skill is not available for model invocation")
  }
  let content = native_skill_render(skill, parsed.content)
  if @utf8.encode(content).length() > TOOL_OUTPUT_LIMIT {
    return tool_error("skill instructions exceed the tool result limit")
  }
  tool_success(content)
}

///|
fn NativeRuntime::prepare_input(
  self : NativeRuntime,
  operation : String,
  input : Json,
) -> Result[Json, String] {
  if operation != "session_send" {
    return Ok(input)
  }
  let prompt = match string_field(input, "prompt") {
    Some(value) => value
    None => return Ok(input)
  }
  let expanded = match self.skills.expand_user_prompt(self.tools.root, prompt) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if expanded == prompt {
    return Ok(input)
  }
  let input_fields = match input {
    Json::Object(fields) => fields
    _ => return Ok(input)
  }
  let output : Map[String, Json] = Map([])
  for (key, value) in input_fields {
    output[key] = value
  }
  output["prompt"] = Json::string(expanded)
  Ok(Json::object(output))
}

///|
fn NativeSkills::expand_user_prompt(
  self : NativeSkills,
  root : SafeRoot,
  prompt : String,
) -> Result[String, String] {
  if !self.enabled {
    return Ok(prompt)
  }
  let chars = prompt.to_array()
  let mut start = 0
  while start < chars.length() && chars[start].is_whitespace() {
    start += 1
  }
  if start >= chars.length() || chars[start] != '/' {
    return Ok(prompt)
  }
  let mut end = start + 1
  while end < chars.length() && !chars[end].is_whitespace() {
    end += 1
  }
  let token = String::from_array(chars[start + 1:end])
  if !native_skill_name_valid(token) {
    return Ok(prompt)
  }
  let (skill, parsed) = match self.parse_current(root, token) {
    Ok(value) => value
    Err(_) => return Ok(prompt)
  }
  if !skill.user_invocable || !parsed.user_invocable {
    return Ok(prompt)
  }
  let content = native_skill_render(skill, parsed.content)
  let invocation_marker = "<skill_invocation name=\"" +
    skill.name +
    "\" source=\"skill-invocation\">"
  let instruction = "\n\n<system-reminder>\nThe user explicitly invoked this skill. Follow its instructions and do not load it again.\n" +
    invocation_marker +
    "\n" +
    content +
    "\n</skill_invocation>\n</system-reminder>"
  if prompt.length() + instruction.length() > 16384 {
    let guidance = if skill.model_invocable && parsed.model_invocable {
      "ask without /name to load it through the skill tool"
    } else {
      "shorten the skill instructions or prompt"
    }
    return Err(
      "directly invoked skill does not fit the 16384-character user message limit; " +
      guidance,
    )
  }
  Ok(prompt + instruction)
}
