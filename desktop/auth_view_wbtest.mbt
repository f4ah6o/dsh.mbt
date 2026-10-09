///|
test "ChatGPT settings keyboard focus follows available account controls" {
  let signed_out = Json::object({
    "state": Json::string("signed_out"),
    "account": Json::null(),
    "models": Json::array([]),
  })
  assert_eq(desktop_auth_focus_count(signed_out), 3)
  assert_eq(desktop_auth_next_focus(signed_out, 0, false), 1)
  assert_eq(desktop_auth_next_focus(signed_out, 2, false), 0)
  assert_eq(desktop_auth_next_focus(signed_out, 0, true), 2)

  let connected = Json::object({
    "state": Json::string("connected"),
    "account": Json::object({ "profile_id": Json::string("fixture-profile") }),
    "models": Json::array([
      Json::object({ "slug": Json::string("fixture-model-one") }),
      Json::object({ "slug": Json::string("fixture-model-two") }),
    ]),
  })
  assert_eq(desktop_auth_focus_count(connected), 6)
  assert_eq(desktop_auth_next_focus(connected, 5, false), 0)
  assert_eq(desktop_auth_next_focus(connected, 0, true), 5)
  assert_eq(desktop_auth_model_slug(connected, 1), "fixture-model-two")
  assert_eq(desktop_auth_model_slug(connected, 2), "")
}

///|
test "native model rows clamp after catalog shrink and use provider display names" {
  let height = 760.0
  let visible = desktop_settings_visible_model_rows(height)
  assert_eq(desktop_settings_max_scroll(2, height), 0)
  assert_eq(desktop_settings_clamp_scroll(8, 2, height), 0)
  assert_eq(desktop_settings_clamp_scroll(8, visible + 5, height), 5)

  let provider_row = Json::object({
    "slug": Json::string("gpt-test"),
    "display_name": Json::string("GPT Test"),
  })
  assert_eq(desktop_auth_model_label(provider_row), "GPT Test")
  assert_eq(
    desktop_auth_model_label(
      Json::object({ "slug": Json::string("slug-only") }),
    ),
    "slug-only",
  )
}

///|
test "Settings pointer mapping targets the model row painted before focus repair" {
  let models : Array[Json] = []
  for index in 0..<10 {
    models.push(
      Json::object({
        "slug": Json::string("model-" + index.to_string()),
        "display_name": Json::string("Model " + index.to_string()),
      }),
    )
  }
  let auth = Json::object({
    "state": Json::string("connected"),
    "account": Json::object({ "profile_id": Json::string("fixture-profile") }),
    "models": Json::array(models),
    "selected_model": Json::string("model-0"),
  })
  let width = 1120.0
  let height = 560.0
  // Focus model 6 from the taller window, while the current rendered scroll
  // still shows model 0 at the top of the shorter window.
  let (focus_before_click, scroll_before_click) = desktop_auth_bounded_settings_controls(
    auth, 10, 0, height,
  )
  assert_eq(focus_before_click, 10)
  assert_eq(scroll_before_click, 0)

  let rendered = desktop_scene(
    Json::object({ "auth": auth }),
    "",
    [],
    "",
    "",
    "",
    width,
    height,
    1.0,
    false,
    0.0,
    settings_open=true,
    settings_scroll=scroll_before_click,
    settings_focus=focus_before_click,
  )
  assert_true(
    rendered
    .items()
    .any(item => {
      match item {
        @scene.TextItem(text~, ..) => text == "Model 0"
        _ => false
      }
    }),
  )

  let row = desktop_settings_model_rect(0, width, height)
  let (focus_after_click, scroll_after_click, clicked_focus) = desktop_auth_settings_pointer_target(
    auth,
    focus_before_click,
    scroll_before_click,
    width,
    height,
    desktop_point(
      (row.left() + row.right()) / 2.0,
      (row.top() + row.bottom()) / 2.0,
    ),
  )
  assert_eq(focus_after_click, 4)
  assert_eq(scroll_after_click, 0)
  assert_eq(clicked_focus, Some(4))
}
