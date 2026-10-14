///|
test "desktop options preserve Claude Code substitution overrides" {
  let config = desktop_parse_config([
    "--workspace", "/workspace", "--hooks-config", "/hooks.json", "--hooks-plugin-root",
    "", "--hooks-project-dir", "/configured-project",
  ]).unwrap()
  assert_eq(config.hooks_config_path, Some("/hooks.json"))
  assert_eq(config.hooks_plugin_root, Some(""))
  assert_eq(config.hooks_project_dir, Some("/configured-project"))
  assert_eq(config.hooks_dialect, "claude-code")

  assert_true(
    desktop_parse_config([
      "--hooks-config", "/hooks.json", "--hooks-dialect", "codex", "--hooks-project-dir",
      "/project",
    ])
    is Err(_),
  )
  assert_true(
    desktop_parse_config([
      "--hooks-config", "/hooks.json", "--hooks-plugin-root", "/plugin\u0000root",
    ])
    is Err(_),
  )
  assert_true(
    desktop_parse_config(["--hooks-plugin-root", "/plugin"]) is Err(_),
  )
}
