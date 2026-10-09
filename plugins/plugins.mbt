///|
/// A startup composition. Registrations belong to a plugin and are removed
/// together. This is a MoonBit API, not an ABI for loading Cordis/npm plugins.
pub struct Registry {
  priv entries : Array[Plugin]
}

///|
priv struct Plugin {
  id : String
  requires : Array[String]
  tools : Array[Json]
}

///|
pub fn Registry::new() -> Registry {
  { entries: [], }
}

///|
fn copy_json(value : Json) -> Json {
  match value {
    Array(values) => Json::array(values.map(copy_json))
    Object(values) => {
      let result : Map[String, Json] = Map([])
      for key, value in values {
        result[key] = copy_json(value)
      }
      Json::object(result)
    }
    _ => value
  }
}

///|
fn tool_name(tool : Json) -> String? {
  match tool {
    { "name": String(name), .. } => Some(name)
    _ => None
  }
}

///|
pub fn Registry::contains(self : Registry, id : String) -> Bool {
  self.entries.any(entry => entry.id == id)
}

///|
/// Validate the whole registration before changing the composition.
pub fn Registry::mount(
  self : Registry,
  id : String,
  requires : Array[String],
  tools : Array[Json],
) -> Result[Unit, String] {
  if id.length() == 0 || id.length() > 128 {
    return Err("plugin id must contain 1..128 characters")
  }
  if self.contains(id) {
    return Err("plugin is already mounted: " + id)
  }
  for dependency in requires {
    if !self.contains(dependency) {
      return Err("missing plugin dependency: " + dependency)
    }
  }
  let names : Array[String] = []
  for entry in self.entries {
    for tool in entry.tools {
      if tool_name(tool) is Some(name) {
        names.push(name)
      }
    }
  }
  for tool in tools {
    let name = match tool {
      {
        "name": String(name),
        "description": String(_),
        "input_schema": Object(_),
        "effect": String(effect),
        ..
      } => {
        if effect != "read" && effect != "write" && effect != "shell" {
          return Err("invalid tool effect: " + effect)
        }
        name
      }
      _ =>
        return Err("tool requires name, description, input_schema and effect")
    }
    if name.length() == 0 || names.contains(name) {
      return Err("empty or duplicate tool name: " + name)
    }
    names.push(name)
  }
  self.entries.push({
    id,
    requires: requires.copy(),
    tools: tools.map(copy_json),
  })
  Ok(())
}

///|
/// A dependency must stay mounted while another plugin consumes it.
pub fn Registry::unmount(self : Registry, id : String) -> Result[Unit, String] {
  for entry in self.entries {
    if entry.requires.contains(id) {
      return Err("plugin is required by: " + entry.id)
    }
  }
  for index in 0..<self.entries.length() {
    if self.entries[index].id == id {
      self.entries.remove(index) |> ignore
      return Ok(())
    }
  }
  Err("plugin is not mounted: " + id)
}

///|
pub fn Registry::tools(self : Registry) -> Array[Json] {
  let result : Array[Json] = []
  for entry in self.entries {
    for tool in entry.tools {
      result.push(copy_json(tool))
    }
  }
  result
}

///|
pub fn Registry::manifest(self : Registry) -> Json {
  Json::array(
    self.entries.map(entry => {
      "id": entry.id.to_json(),
      "requires": Json::array(entry.requires.map(value => Json::string(value))),
      "tools": Json::array(
        entry.tools.map(tool => Json::string(tool_name(tool).unwrap())),
      ),
    }),
  )
}

///|
fn builtin_schema(properties : Json, required : Array[String]) -> Json {
  {
    "type": "object",
    "properties": properties,
    "required": Json::array(required.map(value => Json::string(value))),
    "additionalProperties": false,
  }
}

///|
pub fn builtin_tools() -> Array[Json] {
  let path : Json = {
    "type": "string",
    "description": "Path within the selected workspace",
  }
  let text : Json = { "type": "string" }
  let positive : Json = { "type": "integer", "minimum": 1 }
  [
    {
      "name": "read",
      "description": "Read a UTF-8 file; offset is a 1-based line number.",
      "effect": "read",
      "input_schema": builtin_schema(
        { "file_path": path, "offset": positive, "limit": positive },
        ["file_path"],
      ),
    },
    {
      "name": "write",
      "description": "Create or replace a UTF-8 file after explicit approval.",
      "effect": "write",
      "input_schema": builtin_schema({ "file_path": path, "content": text }, [
        "file_path", "content",
      ]),
    },
    {
      "name": "edit",
      "description": "Replace one exact occurrence, or all occurrences with replace_all, after approval.",
      "effect": "write",
      "input_schema": builtin_schema(
        {
          "file_path": path,
          "old_string": text,
          "new_string": text,
          "replace_all": { "type": "boolean" },
        },
        ["file_path", "old_string", "new_string"],
      ),
    },
    {
      "name": "glob",
      "description": "List workspace paths matching a glob pattern.",
      "effect": "read",
      "input_schema": builtin_schema({ "pattern": text, "path": path }, [
        "pattern",
      ]),
    },
    {
      "name": "grep",
      "description": "Search workspace text files using a bounded regular expression search.",
      "effect": "read",
      "input_schema": builtin_schema({ "pattern": text, "path": path }, [
        "pattern",
      ]),
    },
    {
      "name": "bash",
      "description": "Run a shell command only when the host enables shell access and the user approves this call. Shell commands are not a filesystem sandbox.",
      "effect": "shell",
      "input_schema": builtin_schema(
        { "command": text, "description": text, "timeout": positive },
        ["command"],
      ),
    },
  ]
}

///|
/// Build the native workspace skill loader descriptor. The catalog contains
/// summaries only; full instruction bodies are read by the host after a call.
pub fn skill_tool(model_catalog : Array[(String, String)]) -> Json {
  let description = StringBuilder()
  description.write_string(
    "Load the full instructions for an exact model-invocable workspace skill. Use a matching skill before acting on a task. The catalog below contains summaries only; do not infer instructions until the skill has been loaded.\n\n<available_skills>\n",
  )
  if model_catalog.is_empty() {
    description.write_string(
      "No model-invocable workspace skills are available.\n",
    )
  }
  for skill in model_catalog {
    let name = skill.0
    let summary = skill.1
    description.write_string("- `")
    description.write_string(name)
    description.write_string("`: ")
    description.write_string(summary)
    description.write_char('\n')
  }
  description.write_string("</available_skills>")
  {
    "name": "skill",
    "description": description.to_string(),
    "effect": "read",
    "input_schema": builtin_schema(
      {
        "name": {
          "type": "string",
          "description": "The exact kebab-case skill name from the available_skills catalog",
        },
      },
      ["name"],
    ),
  }
}

///|
pub fn defaults() -> Result[Registry, String] {
  let registry = Registry::new()
  for
    definition in [
      ("session", [], []),
      ("agent-loop", ["session"], []),
      ("llm.deepseek-messages", ["agent-loop"], []),
      ("llm.openai-chat", ["agent-loop"], []),
      ("tools.local", ["agent-loop"], builtin_tools()),
      ("ui.gpui", ["session"], []),
      ("api.gpui-capability", ["agent-loop"], []),
    ] {
    let (id, requires, tools) = definition
    match registry.mount(id, requires, tools) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(registry)
}
