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
