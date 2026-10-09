///|
test "mounts are atomic and dependencies cannot be removed while live" {
  let registry = @plugins.Registry::new()
  assert_eq(registry.mount("base", [], []), Ok(()))
  assert_eq(registry.mount("dependent", ["base"], []), Ok(()))
  assert_eq(registry.unmount("base"), Err("plugin is required by: dependent"))
  assert_eq(
    registry.mount("missing", ["absent"], []),
    Err("missing plugin dependency: absent"),
  )
  assert_false(registry.contains("missing"))
  assert_eq(registry.unmount("dependent"), Ok(()))
  assert_eq(registry.unmount("base"), Ok(()))
}

///|
test "duplicate tools reject the whole plugin and returned descriptors are copies" {
  let registry = @plugins.Registry::new()
  let tools = @plugins.builtin_tools()
  assert_eq(registry.mount("tools", [], tools), Ok(()))
  assert_true(registry.mount("duplicate", [], tools) is Err(_))
  assert_false(registry.contains("duplicate"))
  let returned = registry.tools()
  returned.clear()
  assert_eq(registry.tools().length(), 6)
  assert_eq(registry.unmount("tools"), Ok(()))
  assert_eq(registry.tools().length(), 0)
}

///|
test "plugin identifiers enforce both boundaries and cannot overwrite a mount" {
  let registry = @plugins.Registry::new()
  assert_true(registry.mount("", [], []) is Err(_))
  assert_true(registry.mount("x".repeat(129), [], []) is Err(_))
  assert_false(registry.contains(""))
  assert_eq(registry.mount("x".repeat(128), [], []), Ok(()))
  assert_true(
    registry.mount("x".repeat(128), [], @plugins.builtin_tools()) is Err(_),
  )
  assert_eq(registry.tools().length(), 0)
  assert_eq(registry.unmount("absent"), Err("plugin is not mounted: absent"))
}

///|
test "unknown tool effects fail atomically and schemas reject extra properties" {
  let registry = @plugins.Registry::new()
  let invalid : Json = {
    "name": "danger",
    "description": "invalid effect must not become an implicitly allowed tool",
    "input_schema": { "type": "object" },
    "effect": "unknown",
  }
  assert_true(
    registry.mount("invalid", [], [@plugins.builtin_tools()[0], invalid])
    is Err(_),
  )
  assert_false(registry.contains("invalid"))
  assert_eq(registry.tools().length(), 0)
  for tool in @plugins.builtin_tools() {
    match tool {
      { "input_schema": { "additionalProperties": False, .. }, .. } => ()
      _ => fail("built-in tools must explicitly forbid unknown properties")
    }
  }
}

///|
test "skill loader descriptor is read-only and carries exact catalog entries" {
  let tool = @plugins.skill_tool([
    ("review-plan", "Review plans against project constraints"),
    ("test-workflow", "Run the repository's test workflow"),
  ])
  match tool {
    {
      "name": String("skill"),
      "description": String(description),
      "effect": String("read"),
      "input_schema": {
        "additionalProperties": False,
        "properties": { "name": { "type": String("string"), .. }, .. },
        "required": Array(required),
        "type": String("object"),
        ..
      },
      ..
    } => {
      assert_true(description.contains("review-plan"))
      assert_true(description.contains("test-workflow"))
      assert_false(
        description.contains(
          "No model-invocable workspace skills are available",
        ),
      )
      assert_true(
        description.contains("Review plans against project constraints"),
      )
      assert_eq(required.length(), 1)
      match required[0] {
        String("name") => ()
        _ => fail("skill loader requires the skill name")
      }
    }
    _ => fail("skill loader must use the bounded read-only tool schema")
  }
  let empty_tool = @plugins.skill_tool([])
  match empty_tool {
    { "description": String(description), .. } =>
      assert_true(
        description.contains(
          "No model-invocable workspace skills are available",
        ),
      )
    _ => fail("empty skill catalog must be described to the provider")
  }
}

///|
test "LSP tool is opt-in and uses the exact four-operation approval-gated schema" {
  assert_false(
    @plugins.builtin_tools().any(tool => {
      match tool {
        { "name": String("lsp"), .. } => true
        _ => false
      }
    }),
  )
  match @plugins.lsp_tool() {
    {
      "name": String("lsp"),
      "effect": String("write"),
      "input_schema": {
        "additionalProperties": False,
        "properties": {
          "operation": { "enum": Array(operations), .. },
          "file_path": { "type": String("string"), .. },
          "line": { "minimum": Number(1.0, ..), .. },
          "character": { "minimum": Number(1.0, ..), .. },
          ..
        },
        "required": Array(required),
        ..
      },
      ..
    } => {
      let names = operations.map(value => {
        match value {
          String(name) => name
          _ => fail("LSP operation enum must contain strings")
        }
      })
      assert_eq(names, [
        "goToDefinition", "findReferences", "goToImplementation", "hover",
      ])
      assert_eq(required.length(), 4)
      assert_true(@plugins.lsp_tool().stringify().contains("requires approval"))
    }
    _ => fail("LSP descriptor must use the bounded approval-gated schema")
  }
}
