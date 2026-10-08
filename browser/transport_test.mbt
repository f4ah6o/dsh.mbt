///|
test "event stream URL construction is MoonBit-owned and encodes identifiers" {
  assert_eq(
    @browser.browser_event_url("cursor 5&next", "session/1+?"),
    "/api/v1/events?cursor=cursor%205%26next&session_id=session%2F1%2B%3F",
  )
  assert_eq(
    @browser.browser_event_url("cursor-6", ""),
    "/api/v1/events?cursor=cursor-6",
  )
}
