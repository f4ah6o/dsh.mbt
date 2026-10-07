///|
async test "native provider bounds stalled reads and total requests" {
  let total = native_provider_with_deadline(25, async fn() {
    @async.sleep(150)
    "late body"
  })
  assert_true(total is None)
  let idle_read = native_provider_with_deadline(25, async fn() {
    @async.sleep(150)
    "late chunk"
  })
  assert_true(idle_read is None)
  let immediate = native_provider_with_deadline(100, fn() { "ready" })
  assert_eq(immediate, Some("ready"))
  let timeout = native_provider_timeout_failure(
    "Provider response stream exceeded the idle time limit",
  )
  let failure = object_field(timeout, "failure").unwrap()
  assert_eq(string_field(failure, "code"), Some("TIMEOUT"))
  assert_true(
    !native_provider_body_limit_exceeded(0, NATIVE_PROVIDER_BODY_LIMIT),
  )
  assert_true(
    native_provider_body_limit_exceeded(0, NATIVE_PROVIDER_BODY_LIMIT + 1),
  )
  assert_true(native_provider_body_limit_exceeded(-1, 1))
}
