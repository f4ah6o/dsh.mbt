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
    443,
    "tailscale:alice@example.com",
  )
  assert_eq(valid, Ok(("tailscale:alice@example.com", false)))

  let missing_identity = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net"),
    None,
    3210,
    host,
    owner,
    443,
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
    443,
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
    443,
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
    443,
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
    443,
    "local:alice",
  )
  assert_eq(local_identity_result, Ok(("local:alice", true)))

  let forged_header = service_request_identity(
    "127.0.0.1:3210",
    Some("http://127.0.0.1:3210"),
    Some("alice@example.com"),
    3210,
    None,
    None,
    443,
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
    443,
    "tailscale:alice@example.com",
  )
  assert_true(revoked_user is Err(_))
}

///|
test "native Tailscale HTTPS port is strict and defaults to 443" {
  assert_eq(service_tailnet_port_from_setting(None), Ok(443))
  assert_eq(service_tailnet_port_from_setting(Some("8443")), Ok(8443))
  for raw_port in ["", "0", "65536", "-1", "8443x", "4294975739"] {
    assert_true(service_tailnet_port_from_setting(Some(raw_port)) is Err(_))
  }
  assert_true(
    service_tailnet_config_from_settings(None, None, Some("8443")) is Err(_),
  )
}

///|
test "native Serve identity binds configured nondefault HTTPS port exactly" {
  let host = Some("dsh-device.example-tailnet.ts.net")
  let owner = Some("alice@example.com")
  let valid = service_request_identity(
    "dsh-device.example-tailnet.ts.net:8443",
    Some("https://dsh-device.example-tailnet.ts.net:8443"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    8443,
    "tailscale:alice@example.com",
  )
  assert_eq(valid, Ok(("tailscale:alice@example.com", false)))

  let missing_port = service_request_identity(
    "dsh-device.example-tailnet.ts.net",
    Some("https://dsh-device.example-tailnet.ts.net:8443"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    8443,
    "tailscale:alice@example.com",
  )
  assert_true(missing_port is Err(_))

  let wrong_authority = service_request_identity(
    "dsh-device.example-tailnet.ts.net:443",
    Some("https://dsh-device.example-tailnet.ts.net:8443"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    8443,
    "tailscale:alice@example.com",
  )
  assert_true(wrong_authority is Err(_))

  let wrong_origin = service_request_identity(
    "dsh-device.example-tailnet.ts.net:8443",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    8443,
    "tailscale:alice@example.com",
  )
  assert_true(wrong_origin is Err(_))
}

///|
test "native Serve identity keeps the default HTTPS authority compatible" {
  let host = Some("dsh-device.example-tailnet.ts.net")
  let owner = Some("alice@example.com")
  let explicit_default_port = service_request_identity(
    "dsh-device.example-tailnet.ts.net:443",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    443,
    "tailscale:alice@example.com",
  )
  assert_eq(explicit_default_port, Ok(("tailscale:alice@example.com", false)))

  let wrong_port = service_request_identity(
    "dsh-device.example-tailnet.ts.net:8443",
    Some("https://dsh-device.example-tailnet.ts.net"),
    Some("alice@example.com"),
    3210,
    host,
    owner,
    443,
    "tailscale:alice@example.com",
  )
  assert_true(wrong_port is Err(_))
}
