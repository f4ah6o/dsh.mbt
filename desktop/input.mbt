///|
fn desktop_limit_prompt(text : String, maximum : Int) -> String {
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
  cursor : Int,
  replace_all : Bool,
  text : String,
) -> (Array[Char], Int) {
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
