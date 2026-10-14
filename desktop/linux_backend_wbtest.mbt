///|
test "Linux backend selection respects explicit choices and session precedence" {
  assert_eq(
    select_linux_backend(None, Some("wayland-0"), None, Some(":1")),
    Ok("wayland"),
  )
  assert_eq(
    select_linux_backend(Some("auto"), None, Some("3"), Some(":1")),
    Ok("wayland"),
  )
  assert_eq(select_linux_backend(None, None, None, Some(":1")), Ok("x11"))
  assert_eq(
    select_linux_backend(Some("x11"), Some("wayland-0"), None, Some(":1")),
    Ok("x11"),
  )
  assert_eq(
    select_linux_backend(Some("wayland"), Some("wayland-0"), None, Some(":1")),
    Ok("wayland"),
  )
  assert_eq(
    select_linux_backend(None, Some(""), Some(""), Some(":1")),
    Ok("x11"),
  )
}

///|
test "Linux backend selection rejects invalid and missing session choices" {
  assert_true(select_linux_backend(None, None, None, None) is Err(_))
  assert_true(
    select_linux_backend(None, Some(""), Some(""), Some("")) is Err(_),
  )
  assert_true(
    select_linux_backend(Some("x11"), Some("wayland-0"), None, None) is Err(_),
  )
  assert_true(
    select_linux_backend(Some("wayland"), None, None, Some(":1")) is Err(_),
  )
  assert_true(
    select_linux_backend(Some("invalid"), Some("wayland-0"), None, Some(":1"))
    is Err(_),
  )
  assert_true(
    select_linux_backend(Some(""), Some("wayland-0"), None, Some(":1"))
    is Err(_),
  )
}
