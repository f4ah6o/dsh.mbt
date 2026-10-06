///|
fn v4_only_fields(
  value : Json,
  required : Array[String],
  optional : Array[String],
  label : String,
) -> Unit raise EngineError {
  let values = fields(value)
  for key, _ in values {
    if !required.contains(key) && !optional.contains(key) {
      raise Invalid("Unsupported Session v4 \{label} field: \{key}")
    }
  }
  for key in required {
    if values.get(key) is None {
      raise Invalid("Session v4 \{label} is missing required field: \{key}")
    }
  }
}

///|
fn v4_image_reference_text(
  block : Json,
  line_number : Int,
) -> String raise EngineError {
  v4_only_fields(block, ["type", "attachment"], [], "image block")
  let attachment = required_field(block, "attachment")
  v4_only_fields(
    attachment,
    ["attachmentId", "mediaType", "width", "height", "bytes"],
    [],
    "image attachment reference",
  )
  let attachment_id = required_string(attachment, "attachmentId", max=256)
  let media_type = required_string(attachment, "mediaType", max=128)
  if attachment_id.length() == 0 ||
    !["image/png", "image/jpeg", "image/webp", "image/gif"].contains(media_type) {
    raise Invalid(
      "Malformed Session v4 image attachment on line \{line_number}",
    )
  }
  let width = int_value(
    required_field(attachment, "width"),
    "image width",
    1,
    2147483647,
  )
  let height = int_value(
    required_field(attachment, "height"),
    "image height",
    1,
    2147483647,
  )
  let bytes = int_value(
    required_field(attachment, "bytes"),
    "image bytes",
    0,
    2147483647,
  )
  "[unresolved image attachment \{attachment_id} (\{media_type}, \{width}x\{height}, \{bytes} bytes; image data is not present in JSONL)]"
}

///|
fn validate_v4_skill_catalog_source(source : Json) -> Unit raise EngineError {
  v4_only_fields(
    source,
    ["kind", "form", "entries"],
    [],
    "skill catalog provenance",
  )
  if required_string(source, "kind", max=64) != "skill-catalog" ||
    required_string(source, "form", max=32) != "catalog" {
    raise Invalid("Session v4 skill catalog provenance is malformed")
  }
  let entries = array_value(
    required_field(source, "entries"),
    "skill catalog entries",
    256,
  )
  for entry in entries {
    v4_only_fields(entry, ["name", "description"], [], "skill catalog entry")
    if required_string(entry, "name", max=128).length() == 0 {
      raise Invalid("Session v4 skill catalog entry has an empty name")
    }
    ignore(
      string_value(
        required_field(entry, "description"),
        "skill description",
        max=4096,
      ),
    )
  }
}

///|
fn validate_v4_inbox_mod_append(original : Json, admitted : Json) -> Bool {
  if !v4_json_fields_equal_except(original, admitted, "content") {
    return false
  }
  let original_content = match json_field(original, "content") {
    Some(Json::Array(blocks)) => blocks
    _ => return false
  }
  let admitted_content = match json_field(admitted, "content") {
    Some(Json::Array(blocks)) => blocks
    _ => return false
  }
  if admitted_content.length() <= original_content.length() {
    return false
  }
  for index in 0..<original_content.length() {
    if original_content[index] != admitted_content[index] {
      return false
    }
  }
  for index in original_content.length()..<admitted_content.length() {
    let added = admitted_content[index]
    let values = match added {
      Json::Object(values) => values
      _ => return false
    }
    if values.length() != 2 || values.get("type") != Some(Json::string("text")) {
      return false
    }
    match values.get("text") {
      Some(Json::String(_)) => ()
      _ => return false
    }
  }
  true
}

///|
fn v4_open_call(replay : V4Replay, id : String) -> ImportedCall? {
  match replay.calls.get(id) {
    Some(call) if call.turn == replay.turn &&
      call.step == replay.step &&
      call.started &&
      !call.settled => Some(call)
    _ => None
  }
}

///|
fn require_v4_ptc_root_settled(
  replay : V4Replay,
  root_call_id : String,
) -> Unit raise EngineError {
  for _, dispatch in replay.ptc_dispatches {
    if dispatch.root_call_id == root_call_id && !dispatch.settled {
      raise Invalid(
        "Session v4 root tool result precedes nested PTC settlement",
      )
    }
  }
}

///|
fn require_v4_ptc_children_settled(
  replay : V4Replay,
  parent_call_id : String,
) -> Unit raise EngineError {
  for _, dispatch in replay.ptc_dispatches {
    if dispatch.parent_call_id == parent_call_id && !dispatch.settled {
      raise Invalid("Session v4 PTC parent settles before its nested child")
    }
  }
}

///|
fn require_v4_workflow_owner_settled(
  replay : V4Replay,
  owner_call_id : String,
) -> Unit raise EngineError {
  for _, run in replay.workflow_runs {
    if run.owner_call_id == owner_call_id && !run.ended {
      raise Invalid("Session v4 foreground workflow result precedes run-end")
    }
  }
}

///|
fn v4_only_open_call_named(replay : V4Replay, name : String) -> String? {
  let mut found : String? = None
  for id in replay.call_order {
    match v4_open_call(replay, id) {
      Some(call) if call.turn == replay.turn &&
        call.step == replay.step &&
        call.name == name =>
        match found {
          None => found = Some(id)
          Some(_) => return None
        }
      _ => ()
    }
  }
  found
}

///|
fn v4_only_open_workflow(replay : V4Replay) -> String? {
  let mut found : String? = None
  for id, run in replay.workflow_runs {
    if !run.ended {
      match found {
        None => found = Some(id)
        Some(_) => return None
      }
    }
  }
  found
}

///|
fn require_v4_metadata_settled(replay : V4Replay) -> Unit raise EngineError {
  for _, dispatch in replay.ptc_dispatches {
    if !dispatch.settled {
      raise Invalid("Session v4 turn ended with an unresolved PTC dispatch")
    }
  }
  for _, run in replay.workflow_runs {
    if !run.ended {
      raise Invalid("Session v4 turn ended with an unresolved workflow run")
    }
    for _, agent in run.agents {
      if !agent.settled {
        raise Invalid("Session v4 turn ended with an unresolved workflow agent")
      }
    }
  }
}
