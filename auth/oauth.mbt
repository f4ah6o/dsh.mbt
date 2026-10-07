// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Portable SIWC OAuth request and callback semantics. Cryptography, browser,
// HTTP, and protected persistence remain explicit native host capabilities.

///|
pub const AUTHORIZE_ENDPOINT : String = "https://auth.openai.com/api/accounts/authorize"

///|
pub const TOKEN_ENDPOINT : String = "https://auth.openai.com/api/accounts/oauth/token"

///|
pub const API_RESOURCE : String = "https://api.openai.com/v1"

///|
pub const DIRECT_SCOPE : String = "chatgpt.tokens.use.direct"

///|
pub const REQUESTED_SCOPES : String = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

///|
const DYNAMIC_CLIENT_ID : String = "dynamic_agent_client"

///|
const AGENT_NAME : String = "dsh.mbt"

///|
priv suberror AuthError {
  AuthError(String)
}

///|
fn[A] fail_auth(code : String, detail : String) -> A raise AuthError {
  raise AuthError(code + ": " + detail)
}

///|
fn auth_object(
  value : Json,
  where_ : String,
) -> Map[String, Json] raise AuthError {
  match value {
    Object(fields) => fields
    _ => fail_auth("AUTH_INVALID_RESPONSE", where_ + " must be an object")
  }
}

///|
fn auth_field(fields : Map[String, Json], key : String) -> Json raise AuthError {
  match fields.get(key) {
    Some(value) => value
    None => fail_auth("AUTH_INVALID_RESPONSE", "missing " + key)
  }
}

///|
fn auth_string(value : Json, where_ : String) -> String raise AuthError {
  match value {
    String(value) => value
    _ => fail_auth("AUTH_INVALID_RESPONSE", where_ + " must be a string")
  }
}

///|
fn auth_text(
  fields : Map[String, Json],
  key : String,
) -> String raise AuthError {
  auth_string(auth_field(fields, key), key)
}

///|
fn auth_optional_text(
  fields : Map[String, Json],
  key : String,
) -> String? raise AuthError {
  match fields.get(key) {
    None | Some(Null) => None
    Some(value) => Some(auth_string(value, key))
  }
}

///|
fn auth_nonempty(value : String, name : String) -> Unit raise AuthError {
  if value.is_empty() || value.length() > 4096 {
    fail_auth("AUTH_INVALID_INPUT", name + " must be nonempty and bounded")
  }
}

///|
fn valid_base64url(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for character in value {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_') {
      return false
    }
  }
  true
}

///|
fn valid_verifier(value : String) -> Bool {
  let length = value.length()
  if length < 43 || length > 128 {
    return false
  }
  for character in value {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '.' ||
      character == '_' ||
      character == '~') {
      return false
    }
  }
  true
}

///|
fn valid_callback_uri(value : String) -> Bool {
  let prefix = "http://127.0.0.1:"
  if !value.has_prefix(prefix) {
    return false
  }
  let suffix = value[prefix.length():].to_owned()
  let (port, path) = match suffix.split_once("/") {
    Some((port, path)) => (port, "/" + path.to_owned())
    None => return false
  }
  if path != "/auth/callback" || port.is_empty() || port.length() > 5 {
    return false
  }
  let mut number = 0
  for character in port {
    if character < '0' || character > '9' {
      return false
    }
    number = number * 10 + character.to_int() - '0'.to_int()
  }
  number > 0 && number <= 65535
}

///|
/// Per-attempt OAuth material. Secret fields have no derived JSON or Show
/// implementation and are never included in a public summary.
pub struct LoginAttempt {
  priv host_id : String
  priv redirect_uri : String
  priv requested_client_id : String?
  priv selected_subject : String?
  priv id_token_hint : String?
  priv login_hint : String?
  priv state : String
  priv nonce : String
  priv verifier : String
  priv challenge : String
}

///|
/// A callback that has passed state and client registration checks.
pub enum OAuthCallback {
  Code(String, String)
}

///|
/// Construct an attempt from fresh values supplied by the host's secure random
/// source. None for requested_client_id means initial dynamic registration.
pub fn LoginAttempt::new(
  host_id : String,
  redirect_uri : String,
  requested_client_id : String?,
  selected_subject : String?,
  id_token_hint : String?,
  login_hint : String?,
  state : String,
  nonce : String,
  verifier : String,
  challenge : String,
) -> Result[LoginAttempt, String] {
  try {
    auth_nonempty(host_id, "host id")
    if !valid_callback_uri(redirect_uri) {
      fail_auth(
        "AUTH_INVALID_INPUT", "redirect URI must use the 127.0.0.1 auth callback",
      )
    }
    match requested_client_id {
      Some(value) => auth_nonempty(value, "client id")
      None => ()
    }
    match selected_subject {
      Some(value) => auth_nonempty(value, "selected subject")
      None => ()
    }
    match id_token_hint {
      Some(value) => auth_nonempty(value, "ID token hint")
      None => ()
    }
    match login_hint {
      Some(value) => auth_nonempty(value, "login hint")
      None => ()
    }
    if !valid_base64url(state) || state.length() < 32 || state.length() > 128 {
      fail_auth("AUTH_INVALID_INPUT", "state must be fresh base64url material")
    }
    if !valid_base64url(nonce) || nonce.length() < 16 || nonce.length() > 128 {
      fail_auth("AUTH_INVALID_INPUT", "nonce must be fresh base64url material")
    }
    if !valid_verifier(verifier) {
      fail_auth("AUTH_INVALID_INPUT", "PKCE verifier is malformed")
    }
    if !valid_base64url(challenge) || challenge.length() != 43 {
      fail_auth(
        "AUTH_INVALID_INPUT", "S256 challenge must be 43 base64url characters",
      )
    }
    Ok({
      host_id,
      redirect_uri,
      requested_client_id,
      selected_subject,
      id_token_hint,
      login_hint,
      state,
      nonce,
      verifier,
      challenge,
    })
  } catch {
    AuthError(message) => Err(message)
  }
}

///|
/// Build authorization parameters; the host URL-encodes these values before
/// opening the system browser. Dynamic registration hints are sent only once.
pub fn LoginAttempt::authorization_params(self : LoginAttempt) -> Json {
  let values : Map[String, Json] = {
    "client_id": self.requested_client_id.unwrap_or(DYNAMIC_CLIENT_ID).to_json(),
    "response_type": "code".to_json(),
    "redirect_uri": self.redirect_uri.to_json(),
    "scope": REQUESTED_SCOPES.to_json(),
    "resource": API_RESOURCE.to_json(),
    "ext_agent_host_id": self.host_id.to_json(),
    "state": self.state.to_json(),
    "nonce": self.nonce.to_json(),
    "code_challenge": self.challenge.to_json(),
    "code_challenge_method": "S256".to_json(),
  }
  if self.requested_client_id is None {
    values["agent_name_hint"] = AGENT_NAME.to_json()
  }
  match self.id_token_hint {
    Some(value) => values["id_token_hint"] = value.to_json()
    None => ()
  }
  match self.login_hint {
    Some(value) => values["login_hint"] = value.to_json()
    None => ()
  }
  Json::object(values)
}

///|
/// Bind native persistence and callback verification to this host identity.
pub fn LoginAttempt::host_id_for_native(self : LoginAttempt) -> String {
  self.host_id
}

///|
/// Validate state, errors, and the dynamic/returning client ID before any
/// token-exchange request is built.
pub fn LoginAttempt::validate_callback(
  self : LoginAttempt,
  callback : Json,
) -> Result[OAuthCallback, String] {
  try {
    let callback = auth_object(callback, "callback")
    let state = auth_text(callback, "state")
    if state != self.state {
      fail_auth(
        "AUTH_CALLBACK_MISMATCH", "OAuth state does not match this attempt",
      )
    }
    match auth_optional_text(callback, "error") {
      Some("access_denied") =>
        fail_auth("AUTH_ACCESS_DENIED", "authorization was denied")
      Some(error) =>
        fail_auth("AUTH_CALLBACK_ERROR", "authorization failed: " + error)
      None => ()
    }
    let code = auth_text(callback, "code")
    auth_nonempty(code, "authorization code")
    let returned_client_id = auth_optional_text(callback, "client_id")
    let client_id = match self.requested_client_id {
      Some(expected) => {
        match returned_client_id {
          Some(actual) if actual != expected =>
            fail_auth("AUTH_CALLBACK_MISMATCH", "callback client ID changed")
          _ => ()
        }
        expected
      }
      None =>
        match returned_client_id {
          Some(actual) if actual != DYNAMIC_CLIENT_ID && !actual.is_empty() =>
            actual
          _ =>
            fail_auth(
              "AUTH_CALLBACK_MISMATCH", "dynamic registration did not return an issued client ID",
            )
        }
    }
    Ok(OAuthCallback::Code(code, client_id))
  } catch {
    AuthError(message) => Err(message)
  }
}

///|
/// Build the authorization-code token request. This contains the verifier and
/// code and must only be sent directly to TOKEN_ENDPOINT by the host.
pub fn LoginAttempt::token_exchange_fields(
  self : LoginAttempt,
  callback : OAuthCallback,
) -> Result[Json, String] {
  match callback {
    Code(code, client_id) =>
      Ok({
        "grant_type": "authorization_code",
        "client_id": client_id,
        "code": code,
        "redirect_uri": self.redirect_uri,
        "code_verifier": self.verifier,
        "resource": API_RESOURCE,
        "ext_agent_host_id": self.host_id,
      })
  }
}

///|
/// Validate a native-verified ID token and bind the resulting credential to
/// this attempt. Cryptographic JWKS verification remains the native host's job.
pub fn accept_token_response(
  attempt : LoginAttempt,
  callback : OAuthCallback,
  token_response : Json,
  verified_claims : Json,
  signature_verified : Bool,
  now_seconds : Int,
) -> Result[Credential, String] {
  try {
    if !signature_verified {
      fail_auth("AUTH_TOKEN_INVALID", "ID token signature was not verified")
    }
    let (code, client_id) = match callback {
      Code(code, client_id) => (code, client_id)
    }
    if code.is_empty() {
      fail_auth("AUTH_TOKEN_INVALID", "authorization code is empty")
    }
    let claims = auth_object(verified_claims, "verified ID token claims")
    if auth_text(claims, "iss") != "https://auth.openai.com" {
      fail_auth("AUTH_TOKEN_INVALID", "ID token issuer is invalid")
    }
    let audience = auth_field(claims, "aud")
    if !audience_contains(audience, client_id) {
      fail_auth(
        "AUTH_TOKEN_INVALID", "ID token audience does not match client ID",
      )
    }
    match audience {
      Array(values) if values.length() > 1 =>
        if auth_optional_text(claims, "azp") != Some(client_id) {
          fail_auth(
            "AUTH_TOKEN_INVALID", "ID token authorized party is invalid",
          )
        }
      _ => ()
    }
    let expires = auth_integer(auth_field(claims, "exp"), "ID token expiry")
    if expires <= now_seconds {
      fail_auth("AUTH_TOKEN_INVALID", "ID token is expired")
    }
    if auth_text(claims, "nonce") != attempt.nonce {
      fail_auth(
        "AUTH_TOKEN_INVALID", "ID token nonce does not match this attempt",
      )
    }
    let subject = auth_text(claims, "sub")
    auth_nonempty(subject, "subject")
    let (email, profile_id) = identity_claims(claims)
    match auth_optional_text(claims, "ext_agent_host_id") {
      Some(value) if value != attempt.host_id =>
        fail_auth("AUTH_TOKEN_INVALID", "ID token host binding is invalid")
      _ => ()
    }
    match claims.get("https://api.openai.com/auth") {
      Some(value) => {
        let auth = auth_object(value, "OpenAI auth claims")
        match auth_optional_text(auth, "ext_agent_host_id") {
          Some(value) if value != attempt.host_id =>
            fail_auth("AUTH_TOKEN_INVALID", "ID token host binding is invalid")
          _ => ()
        }
      }
      None => ()
    }
    match attempt.selected_subject {
      Some(expected) if expected != subject && profile_id != Some(expected) =>
        fail_auth("AUTH_ACCOUNT_MISMATCH", "reauthenticated account changed")
      _ => ()
    }

    let tokens = auth_object(token_response, "token response")
    let access_token = auth_text(tokens, "access_token")
    let refresh_token = auth_optional_text(tokens, "refresh_token")
    let id_token = auth_text(tokens, "id_token")
    let token_type = auth_text(tokens, "token_type")
    if token_type.to_lower() != "bearer" {
      fail_auth("AUTH_TOKEN_INVALID", "token type is not Bearer")
    }
    auth_nonempty(access_token, "access token")
    auth_nonempty(id_token, "ID token")
    match refresh_token {
      Some(value) => auth_nonempty(value, "refresh token")
      None => ()
    }
    let lifetime = auth_integer(auth_field(tokens, "expires_in"), "expires_in")
    if lifetime <= 0 || now_seconds > 2147483647 - lifetime {
      fail_auth("AUTH_TOKEN_INVALID", "access token expiry is invalid")
    }
    let scopes = match auth_optional_text(tokens, "scope") {
      Some(value) => split_scopes(value)
      None => split_scopes(REQUESTED_SCOPES)
    }
    Ok({
      host_id: attempt.host_id,
      client_id,
      subject,
      email,
      profile_id,
      id_token,
      access_token,
      refresh_token,
      scopes,
      expires_at: now_seconds + lifetime,
    })
  } catch {
    AuthError(message) => Err(message)
  }
}

///|
fn auth_integer(value : Json, name : String) -> Int raise AuthError {
  match value {
    Number(number, ..) =>
      if number >= 0.0 &&
        number <= 2147483647.0 &&
        number.to_int().to_double() == number {
        number.to_int()
      } else {
        fail_auth(
          "AUTH_INVALID_RESPONSE",
          name + " must be a nonnegative integer",
        )
      }
    _ =>
      fail_auth(
        "AUTH_INVALID_RESPONSE",
        name + " must be a nonnegative integer",
      )
  }
}

///|
fn audience_contains(value : Json, client_id : String) -> Bool raise AuthError {
  match value {
    String(audience) => audience == client_id
    Array(audiences) => {
      for raw in audiences {
        if auth_string(raw, "audience") == client_id {
          return true
        }
      }
      false
    }
    _ => fail_auth("AUTH_INVALID_RESPONSE", "ID token audience is malformed")
  }
}

///|
fn split_scopes(value : String) -> Array[String] {
  let scopes : Array[String] = []
  let current = StringBuilder()
  let mut last_space = true
  for character in value {
    if character == ' ' || character == '\t' || character == '\n' {
      if !last_space {
        scopes.push(current.to_string())
        current.reset()
      }
      last_space = true
    } else {
      current.write_char(character)
      last_space = false
    }
  }
  if !last_space {
    scopes.push(current.to_string())
  }
  scopes
}

///|
fn identity_claims(
  claims : Map[String, Json],
) -> (String?, String?) raise AuthError {
  let email = match
    (auth_optional_text(claims, "email"), claims.get("email_verified")) {
    (Some(value), Some(True)) => Some(value)
    _ => None
  }
  let profile_id = match claims.get("https://api.openai.com/auth") {
    None | Some(Null) => None
    Some(value) => {
      let auth = auth_object(value, "OpenAI auth claims")
      let profile_id = auth_optional_text(auth, "chatgpt_account_id")
      match profile_id {
        Some(value) => {
          auth_nonempty(value, "ChatGPT account id")
          Some(value)
        }
        None => None
      }
    }
  }
  (email, profile_id)
}
