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
