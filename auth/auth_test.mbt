///|
fn auth_attempt(
  client_id : String?,
  selected_subject : String?,
) -> @auth.LoginAttempt raise {
  match
    @auth.LoginAttempt::new(
      "host-stable-id",
      "http://127.0.0.1:43127/auth/callback",
      client_id,
      selected_subject,
      None,
      None,
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "abcdefghijklmnopqrstuv",
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"[:43].to_owned(),
    ) {
    Ok(attempt) => attempt
    Err(error) => fail(error)
  }
}

///|
fn auth_json_field(value : Json, key : String) -> Json raise {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(value) => value
        None => fail("missing " + key)
      }
    _ => fail("expected object")
  }
}

///|
fn auth_has_secret(value : Json) -> Bool {
  match value {
    Object(fields) => {
      for key, nested in fields {
        if [
            "access_token", "refresh_token", "id_token", "client_secret", "authorization",
            "nonce", "code_verifier",
          ].contains(key) ||
          auth_has_secret(nested) {
          return true
        }
      }
      false
    }
    Array(values) => values.any(auth_has_secret)
    _ => false
  }
}

///|
fn auth_claims(subject : String, client_id : String) -> Json {
  {
    "iss": "https://auth.openai.com",
    "aud": client_id,
    "exp": 2000,
    "nonce": "abcdefghijklmnopqrstuv",
    "sub": subject,
    "email": "owner@example.invalid",
    "email_verified": true,
    "https://api.openai.com/auth": {
      "chatgpt_account_id": "profile-1",
      "chatgpt_plan_type": "plus",
    },
  }
}

///|
fn auth_token_response(scope : String) -> Json {
  {
    "token_type": "Bearer",
    "access_token": "access-secret-fixture",
    "refresh_token": "refresh-secret-fixture",
    "id_token": "id-secret-fixture",
    "expires_in": 3600,
    "scope": scope,
  }
}

///|
test "SIWC authorization request uses dynamic registration only for new clients" {
  let initial = auth_attempt(None, None)
  let initial_params = initial.authorization_params()
  assert_true(
    auth_json_field(initial_params, "client_id") == "dynamic_agent_client",
  )
  assert_true(auth_json_field(initial_params, "agent_name_hint") == "dsh.mbt")
  assert_true(
    auth_json_field(initial_params, "scope") ==
    "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
  )
  assert_true(
    auth_json_field(initial_params, "resource") == "https://api.openai.com/v1",
  )
  assert_true(
    auth_json_field(initial_params, "code_challenge_method") == "S256",
  )
  assert_true(
    auth_json_field(initial_params, "redirect_uri") ==
    "http://127.0.0.1:43127/auth/callback",
  )

  let returning = auth_attempt(Some("registered-client"), Some("subject-1"))
  let returning_params = returning.authorization_params()
  assert_true(
    auth_json_field(returning_params, "client_id") == "registered-client",
  )
  match returning_params {
    Object(fields) => assert_true(!fields.contains("agent_name_hint"))
    _ => fail("expected authorization parameter object")
  }
}

///|
test "SIWC login attempt rejects non-loopback callbacks and malformed PKCE material" {
  assert_true(
    @auth.LoginAttempt::new(
      "host",
      "http://localhost:43127/auth/callback",
      None,
      None,
      None,
      None,
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "abcdefghijklmnopqrstuv",
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"[:43].to_owned(),
    )
    is Err(_),
  )
  assert_true(
    @auth.LoginAttempt::new(
      "host",
      "http://127.0.0.1:70000/auth/callback",
      None,
      None,
      None,
      None,
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "abcdefghijklmnopqrstuv",
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
    )
    is Err(_),
  )
}

///|
test "SIWC callback checks state, dynamic client issuance, and access denial" {
  let initial = auth_attempt(None, None)
  assert_true(
    initial.validate_callback({
      "state": "incorrect",
      "code": "authorization-code",
      "client_id": "registered-client",
    })
    is Err(_),
  )
  assert_true(
    initial.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
    })
    is Err(_),
  )
  assert_true(
    initial.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "error": "access_denied",
    })
    is Err(_),
  )
  assert_true(
    initial.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
      "client_id": "registered-client",
    })
    is Ok(_),
  )

  let returning = auth_attempt(Some("registered-client"), Some("subject-1"))
  assert_true(
    returning.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
    })
    is Ok(_),
  )
  assert_true(
    returning.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
      "client_id": "changed-client",
    })
    is Err(_),
  )
}

///|
test "SIWC token validation binds issuer audience nonce identity and direct scope" {
  let attempt = auth_attempt(None, None)
  let callback = match
    attempt.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
      "client_id": "registered-client",
    }) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let tokens = auth_token_response(
    "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
  )
  let credential = match
    @auth.accept_token_response(
      attempt,
      callback,
      tokens,
      auth_claims("subject-1", "registered-client"),
      true,
      1000,
    ) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(credential.can_use_direct())
  let summary = credential.public_summary()
  assert_true(auth_json_field(summary, "state") == "connected")
  assert_true(auth_json_field(summary, "plan_usage") == "enabled")
  assert_true(
    auth_json_field(auth_json_field(summary, "account"), "email") ==
    "owner@example.invalid",
  )
  assert_true(!auth_has_secret(summary))
  let stored = credential.storage_json()
  assert_true(
    auth_json_field(stored, "access_token") == "access-secret-fixture",
  )
  let reloaded = match @auth.Credential::from_storage_json(stored) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(reloaded.public_summary() == summary)
}

///|
test "SIWC retains identity-only grant but disables direct inference" {
  let attempt = auth_attempt(None, None)
  let callback = match
    attempt.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
      "client_id": "registered-client",
    }) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let credential = match
    @auth.accept_token_response(
      attempt,
      callback,
      auth_token_response("openid profile email"),
      auth_claims("subject-1", "registered-client"),
      true,
      1000,
    ) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(!credential.can_use_direct())
  assert_true(
    auth_json_field(credential.public_summary(), "plan_usage") == "disabled",
  )
}

///|
test "SIWC rejects unverifiable expired mismatched and unselected ID tokens" {
  let cases : Array[(Bool, Json, String)] = [
    (false, auth_claims("subject-1", "registered-client"), "subject-1"),
    (true, auth_claims("subject-1", "wrong-client"), "subject-1"),
    (
      true,
      {
        "iss": "https://attacker.example",
        "aud": "registered-client",
        "exp": 2000,
        "nonce": "abcdefghijklmnopqrstuv",
        "sub": "subject-1",
      },
      "subject-1",
    ),
    (
      true,
      {
        "iss": "https://auth.openai.com",
        "aud": "registered-client",
        "exp": 2000,
        "nonce": "wrong-nonce",
        "sub": "subject-1",
      },
      "subject-1",
    ),
    (
      true,
      {
        "iss": "https://auth.openai.com",
        "aud": "registered-client",
        "exp": 900,
        "nonce": "abcdefghijklmnopqrstuv",
        "sub": "subject-1",
      },
      "subject-1",
    ),
    (true, auth_claims("different-subject", "registered-client"), "subject-1"),
  ]
  for (signature_verified, claims, selected_subject) in cases {
    let attempt = auth_attempt(None, Some(selected_subject))
    let callback = match
      attempt.validate_callback({
        "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
        "code": "authorization-code",
        "client_id": "registered-client",
      }) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_true(
      @auth.accept_token_response(
        attempt,
        callback,
        auth_token_response("openid profile"),
        claims,
        signature_verified,
        1000,
      )
      is Err(_),
    )
  }
}

///|
test "SIWC refresh rotates tokens atomically and keeps transient failures" {
  let attempt = auth_attempt(None, None)
  let callback = match
    attempt.validate_callback({
      "state": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO",
      "code": "authorization-code",
      "client_id": "registered-client",
    }) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let credential = match
    @auth.accept_token_response(
      attempt,
      callback,
      auth_token_response(
        "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
      ),
      auth_claims("subject-1", "registered-client"),
      true,
      1000,
    ) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let refresh_request = match credential.refresh_request() {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(auth_json_field(refresh_request, "grant_type") == "refresh_token")
  assert_true(
    auth_json_field(refresh_request, "refresh_token") ==
    "refresh-secret-fixture",
  )
  let refreshed = match
    credential.accept_refresh(
      {
        "token_type": "Bearer",
        "access_token": "rotated-access",
        "refresh_token": "rotated-refresh",
        "expires_in": 3600,
      },
      2000,
    ) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(
    auth_json_field(refreshed.storage_json(), "access_token") ==
    "rotated-access",
  )
  assert_true(
    auth_json_field(refreshed.storage_json(), "refresh_token") ==
    "rotated-refresh",
  )
  assert_true(refreshed.can_use_direct())
  assert_true(refreshed.access_token_for_transport() == "rotated-access")
  assert_true(
    @auth.classify_refresh_error("invalid_grant", 400) is @auth.Reauthenticate,
  )
  assert_true(
    @auth.classify_refresh_error("server_error", 503) is @auth.Retryable,
  )
  assert_true(
    @auth.classify_refresh_error("invalid_client", 400)
    is @auth.ConfigurationError,
  )
}
