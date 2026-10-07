///|
fn json_string_field(value : Json, key : String) -> String {
  match json_field(value, key) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn json_optional_string_field(value : Json, key : String) -> String? {
  match json_field(value, key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn json_int_field(value : Json, key : String) -> Int {
  match json_field(value, key) {
    Some(Json::Number(number, ..)) if number.to_int().to_double() == number =>
      number.to_int()
    _ => -1
  }
}

///|
fn json_optional_int_field(value : Json, key : String) -> Int? {
  match json_field(value, key) {
    Some(Json::Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => Some(number.to_int())
    _ => None
  }
}

///|
fn json_bool_field(value : Json, key : String) -> Bool? {
  match json_field(value, key) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
fn json_array_field(value : Json, key : String) -> Array[Json]? {
  match json_field(value, key) {
    Some(Json::Array(items)) => Some(items)
    _ => None
  }
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn preferences_optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}
