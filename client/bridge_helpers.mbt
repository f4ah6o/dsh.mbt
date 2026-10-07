///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn parse_timestamp_ms(raw : String) -> Int64? {
  let chars = raw.to_array()
  if chars.is_empty() || chars.length() > 15 {
    return None
  }
  let mut result = 0L
  for value in chars {
    if value < '0' || value > '9' {
      return None
    }
    result = result * 10L + (value.to_int() - '0'.to_int()).to_int64()
  }
  if result > 281474976710655L {
    None
  } else {
    Some(result)
  }
}
