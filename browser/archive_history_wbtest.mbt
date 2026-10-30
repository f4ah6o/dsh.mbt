///|
fn archive_history_fixture(value : String) -> Json {
  @json.parse(value) catch {
    _ => abort("valid archive history fixture")
  }
}

///|
test "archive history response binds session result and immutable object identity" {
  let payload = archive_history_fixture(
    "{\"session_id\":\"session-a\",\"result_sequence\":17,\"object_id\":\"digest-a\",\"content\":\"original text\"}",
  )
  assert_eq(
    browser_archive_original_response(payload, "session-a", "17", "digest-a"),
    Ok("original text"),
  )
  assert_true(
    browser_archive_original_response(payload, "session-a", "18", "digest-a")
    is Err(_),
  )
  let fractional = archive_history_fixture(
    "{\"session_id\":\"session-a\",\"result_sequence\":17.5,\"object_id\":\"digest-a\",\"content\":\"wrong result\"}",
  )
  assert_true(
    browser_archive_original_response(fractional, "session-a", "17", "digest-a")
    is Err(_),
  )
  assert_true(
    browser_archive_original_response(payload, "session-a", "17", "digest-b")
    is Err(_),
  )
  assert_true(
    browser_archive_original_response(payload, "session-b", "17", "digest-a")
    is Err(_),
  )
}
