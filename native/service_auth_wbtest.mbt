///|
test "native Serve identity requires exact configured Host Origin and owner" {
  let host = Some("dsh-device.example-tailnet.ts.net")
  let owner = Some("alice@example.com")
  let valid = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("Alice@Example.com"),
    3210,
    host,
    owner,
    "tailscale:alice@example.com",
  )
  assert_eq(valid, Ok("tailscale:alice@example.com"))

  let missing_identity = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net"),
    None,
    3210,
    host,
    owner,
    "tailscale:alice@example.com",
  )
  assert_true(missing_identity is Err(_))

  let forged_identity = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("Mallory@example.com"),
    3210,
    host,
    owner,
    "tailscale:alice@example.com",
  )
  assert_true(forged_identity is Err(_))

  let wrong_origin = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://attacker.example"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    "tailscale:alice@example.com",
  )
  assert_true(wrong_origin is Err(_))

  let wrong_host = service_request_identity(
    "attacker.example",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    "tailscale:alice@example.com",
  )
  assert_true(wrong_host is Err(_))
}

///|
test "native local-only carrier rejects forged Serve headers and remote hosts" {
  let local_identity_result = service_request_identity(
    "127.0.0.1:3210",
    Some("http://127.0.0.1:3210"),
    None,
    3210,
    None,
    None,
    "local:alice",
  )
  assert_eq(local_identity_result, Ok("local:alice"))

  let forged_header = service_request_identity(
    "127.0.0.1:3210",
    Some("http://127.0.0.1:3210"),
    Some("alice@example.com"),
    3210,
    None,
    None,
    "local:alice",
  )
  assert_true(forged_header is Err(_))

  let revoked_user = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("former-owner@example.com"),
    3210,
    Some("dsh-device.example-tailnet.ts.net"),
    Some("alice@example.com"),
    "tailscale:alice@example.com",
  )
  assert_true(revoked_user is Err(_))
}
