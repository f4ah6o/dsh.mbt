///|
fn part(value : String) -> String {
  value.length().to_string() + ":" + value
}

///|
#warnings("-deprecated")
fn parse_json(raw : String) -> Json raise {
  @json.parse(raw, max_nesting_depth=32)
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn string_field(value : Json, key : String) -> String {
  match optional_field(value, key) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn optional_string_field(value : Json, key : String) -> String? {
  match optional_field(value, key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn int_field(value : Json, key : String) -> Int {
  match optional_field(value, key) {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ => -1
  }
}

///|
fn optional_int_field(value : Json, key : String) -> Int? {
  match optional_field(value, key) {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => Some(number.to_int())
    _ => None
  }
}

///|
fn string_array_field(value : Json, key : String) -> Array[String] {
  match optional_field(value, key) {
    Some(Json::Array(items)) =>
      items.filter_map(item => {
        match item {
          Json::String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn object_field(value : Json, key : String) -> Json? {
  match optional_field(value, key) {
    Some(Json::Object(_)) as item => item
    _ => None
  }
}

///|
fn value_at(value : Json, key : String) -> Json {
  optional_field(value, key).unwrap_or(Json::null())
}

///|
fn optional_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn has_exact_keys(fields : Map[String, Json], expected : Array[String]) -> Bool {
  let keys = fields.keys()
  if keys.length() != expected.length() {
    return false
  }
  for key in keys {
    if !expected.contains(key) {
      return false
    }
  }
  true
}

///|
fn hex_range(chars : Array[Char], start : Int, end : Int) -> Bool {
  for index in start..<end {
    if hex_value(chars[index]) is None {
      return false
    }
  }
  true
}

///|
fn lower_hex_range(chars : Array[Char], start : Int, end : Int) -> Bool {
  for index in start..<end {
    let value = chars[index]
    if !(value >= '0' && value <= '9') && !(value >= 'a' && value <= 'f') {
      return false
    }
  }
  true
}

///|
fn variant_char(value : Char) -> Bool {
  value == '8' || value == '9' || value == 'a' || value == 'b'
}

///|
fn hex_value(value : Char) -> Int? {
  if value >= '0' && value <= '9' {
    Some(value.to_int() - '0'.to_int())
  } else if value >= 'a' && value <= 'f' {
    Some(value.to_int() - 'a'.to_int() + 10)
  } else if value >= 'A' && value <= 'F' {
    Some(value.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn hex_char(value : Int) -> Char {
  let digit = if value < 10 {
    '0'.to_int() + value
  } else {
    'a'.to_int() + value - 10
  }
  digit.to_char().unwrap_or('0')
}

///|
fn lowercase_hex(chars : Array[Char], start : Int, end : Int) -> String {
  let output : Array[Char] = []
  for index in start..<end {
    output.push(hex_char(hex_value(chars[index]).unwrap_or(0)))
  }
  String::from_array(output)
}

///|
/// Compare Unicode strings by scalar value rather than the core `String`
/// comparison's length-first order; this is the canonical JSON object order.
fn lexical_string_compare(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let shared = if left_chars.length() < right_chars.length() {
    left_chars.length()
  } else {
    right_chars.length()
  }
  for index in 0..<shared {
    let left_value = left_chars[index].to_int()
    let right_value = right_chars[index].to_int()
    if left_value < right_value {
      return -1
    }
    if left_value > right_value {
      return 1
    }
  }
  left_chars.length() - right_chars.length()
}
