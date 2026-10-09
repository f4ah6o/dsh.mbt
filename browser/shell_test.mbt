///|
test "the MoonBit shell preserves browser entry points and Japanese accessibility" {
  let html = @browser.shell_html()
  assert_true(html.contains("id=\"transcript-scroll\""))
  assert_true(html.contains("id=\"transcript-canvas\""))
  assert_true(html.contains("id=\"text-transcript\""))
  assert_true(html.contains("id=\"composer\""))
  assert_true(html.contains("id=\"prompt\""))
  assert_true(html.contains("id=\"session-search\""))
  assert_true(html.contains("id=\"settings-open\""))
  assert_true(html.contains("id=\"settings-open-sidebar\""))
  assert_true(html.contains("id=\"settings-page\""))
  assert_true(html.contains("id=\"settings-close\""))
  assert_true(html.contains("id=\"chatgpt-settings-slot\""))
  assert_true(html.contains("id=\"auth-sign-in\""))
  assert_true(html.contains("id=\"auth-sign-out\""))
  assert_true(html.contains("id=\"model-picker\""))
  assert_true(
    html.contains(
      "aria-label=\"ワークスペースのナビゲーション\"",
    ),
  )
  assert_true(html.contains("aria-label=\"会話の記録\""))
  assert_true(html.contains("data-action=\"send\""))
  assert_false(html.contains("<script"))
  assert_false(html.contains(" onclick="))
}
