///|
fn object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
fn integer(value : Int) -> Json {
  Json::number(value.to_double())
}

///|
fn boolean(value : Bool) -> Json {
  Json::boolean(value)
}

///|
fn fields(value : Json) -> Map[String, Json] raise EngineError {
  match value {
    Json::Object(items) => items
    _ => raise Invalid("Expected an object")
  }
}

///|
fn required_field(value : Json, key : String) -> Json raise EngineError {
  match fields(value).get(key) {
    Some(item) => item
    None => raise Invalid("Missing field: \{key}")
  }
}

///|
fn string_value(
  value : Json,
  label : String,
  max? : Int = 65536,
) -> String raise EngineError {
  match value {
    Json::String(text) => {
      if text.length() > max {
        raise Invalid("\{label} exceeds the length limit")
      }
      text
    }
    _ => raise Invalid("\{label} must be a string")
  }
}

///|
fn required_string(
  value : Json,
  key : String,
  max? : Int = 65536,
) -> String raise EngineError {
  string_value(required_field(value, key), key, max~)
}

///|
fn optional_string(
  value : Json,
  key : String,
  fallback : String,
  max? : Int = 65536,
) -> String raise EngineError {
  match fields(value).get(key) {
    None => fallback
    Some(item) => string_value(item, key, max~)
  }
}

///|
fn bool_value(value : Json, label : String) -> Bool raise EngineError {
  match value {
    Json::True => true
    Json::False => false
    _ => raise Invalid("\{label} must be a boolean")
  }
}

///|
fn int_value(
  value : Json,
  label : String,
  minimum : Int,
  maximum : Int,
) -> Int raise EngineError {
  match value {
    Json::Number(number, ..) => {
      if number.is_inf() ||
        number.is_nan() ||
        number < minimum.to_double() ||
        number > maximum.to_double() {
        raise Invalid("\{label} is outside the supported range")
      }
      let result = number.to_int()
      if result.to_double() != number {
        raise Invalid("\{label} must be an integer")
      }
      result
    }
    _ => raise Invalid("\{label} must be an integer")
  }
}

///|
fn array_value(
  value : Json,
  label : String,
  maximum : Int,
) -> Array[Json] raise EngineError {
  match value {
    Json::Array(items) => {
      if items.length() > maximum {
        raise Invalid("\{label} exceeds the item limit")
      }
      items
    }
    _ => raise Invalid("\{label} must be an array")
  }
}

///|
fn identifier(value : String, label : String) -> String raise EngineError {
  if value.length() == 0 || value.length() > 128 {
    raise Invalid("\{label} must contain 1 to 128 characters")
  }
  for c in value {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.' ||
      c == ':') {
      raise Invalid("\{label} contains unsupported characters")
    }
  }
  value
}

///|
priv struct JsonBudget {
  mut nodes : Int
  mut chars : Int
}

///|
/// Clone every ingress value. Depth and aggregate budgets also reject cyclic
/// or adversarial Json values built by an in-process caller.
fn checked_copy(value : Json) -> Json raise EngineError {
  copy_with_budget(value, 0, { nodes: 1000000, chars: 16777216, })
}

///|
fn copy_with_budget(
  value : Json,
  depth : Int,
  budget : JsonBudget,
) -> Json raise EngineError {
  budget.nodes -= 1
  if depth > 64 || budget.nodes < 0 {
    raise Invalid("JSON exceeds the depth or node limit")
  }
  match value {
    Json::Object(items) => {
      let copied = Map([])
      for key, item in items {
        budget.chars -= key.length()
        if budget.chars < 0 {
          raise Invalid("JSON exceeds the text limit")
        }
        copied.set(key, copy_with_budget(item, depth + 1, budget))
      }
      Json::object(copied)
    }
    Json::Array(items) =>
      Json::array(items.map(item => copy_with_budget(item, depth + 1, budget)))
    Json::String(text) => {
      budget.chars -= text.length()
      if budget.chars < 0 {
        raise Invalid("JSON exceeds the text limit")
      }
      Json::string(text)
    }
    Json::Number(number, ..) => {
      if number.is_inf() || number.is_nan() {
        raise Invalid("JSON numbers must be finite")
      }
      Json::number(number)
    }
    Json::True => Json::boolean(true)
    Json::False => Json::boolean(false)
    Json::Null => Json::null()
  }
}

///|
/// Internal values have already passed checked_copy and cannot be mutated by
/// callers. Build a detached outward view without retaining collection aliases.
fn detached(value : Json) -> Json {
  match value {
    Json::Object(items) => {
      let copied = Map([])
      for key, item in items {
        copied.set(key, detached(item))
      }
      Json::object(copied)
    }
    Json::Array(items) => Json::array(items.map(detached))
    _ => value
  }
}

///|
/// The pinned parser exposes its supported depth limit through a deprecated
/// parameter. Keep this bound below the enclosing snapshot/FFI depth budget.
#warnings("-deprecated")
fn parse_arguments(raw : String) -> Json raise EngineError {
  if raw.length() > 65536 {
    raise Invalid("Tool arguments exceed the length limit")
  }
  let value = @json.parse(raw, max_nesting_depth=24) catch {
    _ => raise Invalid("Tool arguments must be valid JSON")
  }
  ignore(fields(value))
  checked_copy(value)
}

///|
fn Tool::json(self : Tool) -> Json {
  object([
    ("name", Json::string(self.name)),
    ("description", Json::string(self.description)),
    ("input_schema", detached(self.input_schema)),
    ("effect", Json::string(effect_text(self.effect))),
  ])
}

///|
fn parse_tool(value : Json) -> Tool raise EngineError {
  let name = identifier(required_string(value, "name", max=128), "tool name")
  let description = required_string(value, "description", max=4096)
  let input_schema = required_field(value, "input_schema")
  ignore(fields(input_schema))
  if required_string(input_schema, "type", max=16) != "object" {
    raise Invalid("Tool input_schema must describe an object")
  }
  let effect = match required_string(value, "effect", max=16) {
    "read" => Read
    "write" => Write
    "shell" => Shell
    _ => raise Invalid("Unknown tool effect class")
  }
  { name, description, input_schema, effect, }
}

///|
/// The initial provider boundary supports the ordinary JSON Schema types,
/// required properties, closed objects, enum, and nested array/object values.
/// Host tools retain their own filesystem and process-specific validation.
fn validate_arguments(
  schema : Json,
  value : Json,
  depth? : Int = 0,
) -> Unit raise EngineError {
  if depth > 32 {
    raise Invalid("Tool argument schema exceeds the depth limit")
  }
  let schema_fields = fields(schema)
  match schema_fields.get("type") {
    Some(Json::String(kind)) => {
      let matches = match (kind, value) {
        ("object", Json::Object(_))
        | ("array", Json::Array(_))
        | ("string", Json::String(_))
        | ("number", Json::Number(_, ..))
        | ("boolean", Json::True)
        | ("boolean", Json::False)
        | ("null", Json::Null) => true
        ("integer", Json::Number(number, ..)) =>
          number >= -2147483648.0 &&
          number <= 2147483647.0 &&
          number.to_int().to_double() == number
        _ => false
      }
      if !matches {
        raise Invalid("Tool argument does not match schema type \{kind}")
      }
    }
    None => ()
    _ => raise Invalid("Unsupported tool schema type")
  }
  match schema_fields.get("enum") {
    Some(Json::Array(items)) =>
      if !items.contains(value) {
        raise Invalid("Tool argument is not in the schema enum")
      }
    None => ()
    _ => raise Invalid("Tool schema enum must be an array")
  }
  match value {
    Json::Object(items) => {
      match schema_fields.get("required") {
        Some(required) =>
          for key in array_value(required, "required", 256) {
            let key = string_value(key, "required property", max=128)
            if items.get(key) is None {
              raise Invalid("Missing tool argument: \{key}")
            }
          }
        None => ()
      }
      let properties = match schema_fields.get("properties") {
        Some(value) => fields(value)
        None => Map([])
      }
      let closed = schema_fields.get("additionalProperties") ==
        Some(Json::boolean(false))
      for key, item in items {
        match properties.get(key) {
          Some(property) => validate_arguments(property, item, depth=depth + 1)
          None => if closed { raise Invalid("Unknown tool argument: \{key}") }
        }
      }
    }
    Json::Array(items) =>
      match schema_fields.get("items") {
        Some(item_schema) =>
          for item in items {
            validate_arguments(item_schema, item, depth=depth + 1)
          }
        None => ()
      }
    _ => ()
  }
}
