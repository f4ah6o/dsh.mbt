// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Small strict JWT/JWKS verifier for the native SIWC callback.

///|
async fn native_verify_id_token(
  endpoints : AuthEndpoints,
  token : String,
) -> Result[Json, String] {
  native_verify_id_token_with(endpoints, token, async fn(
    endpoint,
    kind,
    headers,
  ) {
    oauth_get_json(endpoints, endpoint, kind, headers~)
  })
}

///|
/// Run the same strict OIDC verifier against an injected HTTPS transport. The
/// callback exists to make discovery/JWKS rotation deterministic in native
/// tests; endpoint allowlisting and all token checks remain in this function.
async fn native_verify_id_token_with(
  endpoints : AuthEndpoints,
  token : String,
  fetch_json : async (String, String, @http.Headers) -> Result[
    (Int, Json),
    String,
  ],
) -> Result[Json, String] {
  if token.is_empty() || token.length() > 32768 {
    return Err("AUTH_TOKEN_INVALID: ID token is empty or too large")
  }
  let (header_part, rest) = match token.split_once(".") {
    Some(value) => value
    None => return Err("AUTH_TOKEN_INVALID: ID token is malformed")
  }
  let (payload_part, signature_part) = match rest.split_once(".") {
    Some(value) if !value.1.contains(".") => value
    _ => return Err("AUTH_TOKEN_INVALID: ID token is malformed")
  }
  let header = match native_jwt_json(header_part.to_owned()) {
    Ok(value) => value
    Err(_) => return Err("AUTH_TOKEN_INVALID: ID token header is malformed")
  }
  let header_fields = match header {
    Object(fields) => fields
    _ => return Err("AUTH_TOKEN_INVALID: ID token header is malformed")
  }
  if native_auth_string(header_fields.get("alg")) != "RS256" {
    return Err("AUTH_TOKEN_INVALID: ID token algorithm is not RS256")
  }
  let kid = native_auth_string(header_fields.get("kid"))
  if kid.is_empty() || kid.length() > 256 {
    return Err("AUTH_TOKEN_INVALID: ID token signing key is missing")
  }
  let payload = match native_jwt_json(payload_part.to_owned()) {
    Ok(value) => value
    Err(_) => return Err("AUTH_TOKEN_INVALID: ID token claims are malformed")
  }
  let claims = match payload {
    Object(fields) => fields
    _ => return Err("AUTH_TOKEN_INVALID: ID token claims are malformed")
  }
  if native_auth_string(claims.get("iss")) != "https://auth.openai.com" {
    return Err("AUTH_TOKEN_INVALID: ID token issuer is invalid")
  }
  if !native_auth_endpoint_allowed(endpoints, endpoints.discovery, "discovery") {
    return Err(
      "AUTH_ENDPOINT_INVALID: identity discovery endpoint is not trusted",
    )
  }
  let discovery_result = fetch_json(endpoints.discovery, "discovery", Map([]))
  let (discovery_status, discovery) = match discovery_result {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if discovery_status < 200 || discovery_status >= 300 {
    return Err("AUTH_DISCOVERY_FAILED: OpenAI identity metadata is unavailable")
  }
  let discovery_fields = match discovery {
    Object(fields) => fields
    _ => return Err("AUTH_DISCOVERY_INVALID: identity metadata is malformed")
  }
  if native_auth_string(discovery_fields.get("issuer")) !=
    "https://auth.openai.com" {
    return Err("AUTH_DISCOVERY_INVALID: identity issuer does not match")
  }
  let jwks_uri = native_auth_string(discovery_fields.get("jwks_uri"))
  if !native_auth_endpoint_allowed(endpoints, jwks_uri, "jwks") {
    return Err("AUTH_DISCOVERY_INVALID: signing keys are not hosted by OpenAI")
  }
  let keys_first = fetch_json(jwks_uri, "jwks", Map([]))
  let first = match keys_first {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let key = match native_jwks_find(first, kid) {
    Some(value) => value
    None => {
      // A key-id miss can be a legitimate JWKS rotation. Fetch once more
      // before rejecting rather than retaining stale cached key material.
      let second = match fetch_json(jwks_uri, "jwks", Map([])) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match native_jwks_find(second, kid) {
        Some(value) => value
        None =>
          return Err("AUTH_TOKEN_INVALID: ID token signing key was not found")
      }
    }
  }
  let key_fields = match key {
    Object(fields) => fields
    _ => return Err("AUTH_JWKS_INVALID: signing key is malformed")
  }
  if native_auth_string(key_fields.get("kty")) != "RSA" ||
    (
      native_auth_optional_string(key_fields.get("alg")) is Some(alg) &&
      alg != "RS256"
    ) ||
    (
      native_auth_optional_string(key_fields.get("use")) is Some(use_) &&
      use_ != "sig"
    ) {
    return Err("AUTH_JWKS_INVALID: signing key is not an RS256 key")
  }
  let modulus = match
    native_base64url_decode(native_auth_string(key_fields.get("n")), limit=8192) {
    Ok(value) => value
    Err(_) => return Err("AUTH_JWKS_INVALID: RSA modulus is malformed")
  }
  let exponent = match
    native_base64url_decode(native_auth_string(key_fields.get("e")), limit=32) {
    Ok(value) => value
    Err(_) => return Err("AUTH_JWKS_INVALID: RSA exponent is malformed")
  }
  if modulus.length() < 256 || modulus.length() > 1024 || exponent.is_empty() {
    return Err("AUTH_JWKS_INVALID: RSA key size is outside the allowed range")
  }
  let signature = match
    native_base64url_decode(signature_part.to_owned(), limit=2048) {
    Ok(value) => value
    Err(_) => return Err("AUTH_TOKEN_INVALID: ID token signature is malformed")
  }
  let message = @utf8.encode(
    header_part.to_owned() + "." + payload_part.to_owned(),
  )
  if !SafeRoot::verify_rs256(modulus, exponent, message, signature) {
    return Err("AUTH_TOKEN_INVALID: ID token signature verification failed")
  }
  Ok(Json::object(claims))
}

///|
fn native_jwt_json(segment : String) -> Result[Json, String] {
  let bytes = match native_base64url_decode(segment, limit=16384) {
    Ok(value) => value
    Err(_) => return Err("malformed JWT encoding")
  }
  let text = @utf8.decode(bytes) catch { _ => return Err("malformed JWT text") }
  let value = @json.parse(text) catch { _ => return Err("malformed JWT JSON") }
  Ok(value)
}

///|
fn native_jwks_find(response : (Int, Json), kid : String) -> Json? {
  let (status, value) = response
  if status < 200 || status >= 300 {
    return None
  }
  let fields = match value {
    Object(fields) => fields
    _ => return None
  }
  let keys = match fields.get("keys") {
    Some(Array(keys)) if keys.length() <= 128 => keys
    _ => return None
  }
  for key in keys {
    match key {
      Object(key_fields) if native_auth_string(key_fields.get("kid")) == kid =>
        return Some(key)
      _ => ()
    }
  }
  None
}
