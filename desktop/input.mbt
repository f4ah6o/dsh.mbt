///|
fn desktop_limit_prompt(text : String, maximum : Int32) -> String {
  let output = StringBuilder()
  let mut count = 0
  for character in text {
    if count >= maximum {
      break
    }
    output.write_char(character)
    count += 1
  }
  output.to_string()
}

///|
fn desktop_insert_at(
  draft : Array[Char],
  cursor : Int32,
  replace_all : Bool,
  text : String,
) -> (Array[Char], Int32) {
  let base = if replace_all { [] } else { draft }
  let bounded = desktop_limit_prompt(text, 16000)
  let inserted : Array[Char] = []
  for character in bounded {
    inserted.push(character)
  }
  let insertion_point = if cursor < 0 {
    0
  } else if cursor > base.length() {
    base.length()
  } else {
    cursor
  }
  let result : Array[Char] = []
  for index = 0; index < insertion_point; index = index + 1 {
    result.push(base[index])
  }
  for character in inserted {
    result.push(character)
  }
  for index = insertion_point; index < base.length(); index = index + 1 {
    result.push(base[index])
  }
  (result, insertion_point + inserted.length())
}

///|
fn desktop_prompt_payload(prompt : String) -> Json {
  Json::object({ "prompt": Json::string(prompt) })
}

///|
fn desktop_insertable_key(
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
) -> String? {
  if modifiers.meta() || modifiers.control() || modifiers.alt() {
    return None
  }
  match key {
    @primitives.Character(text) => Some(text)
    @primitives.Space => Some(" ")
    @primitives.Tab => Some("\t")
    _ => None
  }
}

///|
fn desktop_key_input_text(
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
  text_input_events : Bool,
) -> String? {
  // Wayland supplies both physical KeyPressed and committed TextInput.
  // Only the committed text may mutate the composer on that backend.
  if text_input_events {
    None
  } else {
    desktop_insertable_key(key, modifiers)
  }
}

///|
fn desktop_shortcut_modifier(
  modifiers : @primitives.Modifiers,
  control_shortcuts : Bool,
) -> Bool {
  modifiers.meta() || (control_shortcuts && modifiers.control())
}
