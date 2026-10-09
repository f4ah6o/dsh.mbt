///|
test "native desktop authentication operations require the displayed profile" {
  let status = Json::object({
    "state": Json::string("connected"),
    "account": Json::object({ "profile_id": Json::string("fixture-profile") }),
  })
  assert_true(native_desktop_auth_profile_matches(status, "fixture-profile"))
  assert_false(
    native_desktop_auth_profile_matches(status, "replacement-profile"),
  )
  assert_false(native_desktop_auth_profile_matches(status, ""))

  let signed_out = Json::object({
    "state": Json::string("signed_out"),
    "account": Json::null(),
  })
  assert_false(
    native_desktop_auth_profile_matches(signed_out, "fixture-profile"),
  )
}
