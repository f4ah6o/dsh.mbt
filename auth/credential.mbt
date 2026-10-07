// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
/// Credential data is intentionally not printable. Use public_summary for
/// display and storage_json only for the host's protected store.
pub struct Credential {
  priv host_id : String
  priv client_id : String
  priv subject : String
  priv email : String?
  priv profile_id : String?
  priv id_token : String
  priv access_token : String
  priv refresh_token : String?
  priv scopes : Array[String]
  priv expires_at : Int
}

///|
/// Restricted context for native account reauthentication. The ID token is an
/// explicit hint and remains unavailable to presentation or client packages.
pub struct ReauthContext {
  priv host_id : String
  priv client_id : String
  priv selected_identity : String
  priv id_token_hint : String
}

///|
pub fn Credential::reauth_context(self : Credential) -> ReauthContext {
  {
    host_id: self.host_id,
    client_id: self.client_id,
    selected_identity: self.profile_id.unwrap_or(self.subject),
    id_token_hint: self.id_token,
  }
}

///|
pub fn ReauthContext::host_id_for_native(self : ReauthContext) -> String {
  self.host_id
}

///|
pub fn ReauthContext::client_id_for_native(self : ReauthContext) -> String {
  self.client_id
}

///|
pub fn ReauthContext::selected_identity_for_native(
  self : ReauthContext,
) -> String {
  self.selected_identity
}

///|
/// Return the retained token only for a native authorization URL hint.
pub fn ReauthContext::id_token_hint_for_native(self : ReauthContext) -> String {
  self.id_token_hint
}

///|
pub(all) enum RefreshDisposition {
  Reauthenticate
  ConfigurationError
  Retryable
}

///|
/// Whether inference may use the ChatGPT direct plan route.
pub fn Credential::can_use_direct(self : Credential) -> Bool {
  self.scopes.contains(DIRECT_SCOPE)
}

///|
/// Host binding checked by the native protected-store loader.
pub fn Credential::host_id_for_native(self : Credential) -> String {
  self.host_id
}

///|
/// Stable identity for account-scoped model caches and effect generations.
pub fn Credential::identity_for_native(self : Credential) -> String {
  self.profile_id.unwrap_or(self.subject)
}

///|
/// Access-token expiry used by the native refresh coordinator.
pub fn Credential::expires_at_for_native(self : Credential) -> Int {
  self.expires_at
}

///|
/// Return an access token only to the provider transport for an authenticated
/// request. The caller must never format it into diagnostics or UI data.
pub fn Credential::access_token_for_transport(self : Credential) -> String {
  self.access_token
}

///|
/// Return a user-facing account projection without credentials or claims.
pub fn Credential::public_summary(self : Credential) -> Json {
  let account : Map[String, Json] = Map([])
  match self.email {
    Some(value) => account["email"] = value.to_json()
    None => ()
  }
  match self.profile_id {
    Some(value) => account["profile_id"] = value.to_json()
    None => ()
  }
  {
    "state": "connected",
    "account": if account.is_empty() {
      Json::null()
    } else {
      Json::object(account)
    },
    "plan_usage": if self.can_use_direct() {
      "enabled"
    } else {
      "disabled"
    },
    "scopes": Json::array(self.scopes.map(scope => scope.to_json())),
    "models": Json::array([]),
  }
}

///|
/// Explicit secret-bearing representation for a native protected credential
/// store. Never pass this JSON to UI, history, diagnostics, or logs.
pub fn Credential::storage_json(self : Credential) -> Json {
  {
    "version": 1,
    "host_id": self.host_id,
    "client_id": self.client_id,
    "subject": self.subject,
    "email": match self.email {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "profile_id": match self.profile_id {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "id_token": self.id_token,
    "access_token": self.access_token,
    "refresh_token": match self.refresh_token {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "scopes": Json::array(self.scopes.map(scope => scope.to_json())),
    "expires_at": self.expires_at.to_json(),
  }
}

///|
/// Rehydrate one credential file after the native host has authenticated its
/// owner and parsed the protected store.
pub fn Credential::from_storage_json(
  value : Json,
) -> Result[Credential, String] {
  try {
    let stored = auth_object(value, "stored credential")
    if auth_integer(auth_field(stored, "version"), "credential version") != 1 {
      fail_auth("AUTH_STORE_INVALID", "unsupported credential version")
    }
    let host_id = auth_text(stored, "host_id")
    let client_id = auth_text(stored, "client_id")
    let subject = auth_text(stored, "subject")
    let id_token = auth_text(stored, "id_token")
    let access_token = auth_text(stored, "access_token")
    let refresh_token = auth_optional_text(stored, "refresh_token")
    let expires_at = auth_integer(
      auth_field(stored, "expires_at"),
      "expires_at",
    )
    let scopes = match auth_field(stored, "scopes") {
      Array(values) => values.map(value => auth_string(value, "scope"))
      _ => fail_auth("AUTH_STORE_INVALID", "scopes must be an array")
    }
    let email = auth_optional_text(stored, "email")
    let profile_id = auth_optional_text(stored, "profile_id")
    if host_id.is_empty() ||
      client_id.is_empty() ||
      subject.is_empty() ||
      id_token.is_empty() ||
      access_token.is_empty() {
      fail_auth("AUTH_STORE_INVALID", "credential identity or token is empty")
    }
    Ok({
      host_id,
      client_id,
      subject,
      email,
      profile_id,
      id_token,
      access_token,
      refresh_token,
      scopes,
      expires_at,
    })
  } catch {
    AuthError(message) => Err(message)
  }
}

///|
/// Build the refresh request for the native token transport. The returned
/// fields contain the refresh secret and must never be logged or returned.
pub fn Credential::refresh_request(self : Credential) -> Result[Json, String] {
  match self.refresh_token {
    None => Err("AUTH_REAUTH_REQUIRED: credential has no refresh token")
    Some(refresh_token) =>
      Ok({
        "url": TOKEN_ENDPOINT,
        "grant_type": "refresh_token",
        "client_id": self.client_id,
        "refresh_token": refresh_token,
        "resource": API_RESOURCE,
        "ext_agent_host_id": self.host_id,
      })
  }
}

///|
/// Apply successful refresh as one immutable rotation. The replacement refresh
/// token is required before any updated credential is returned.
pub fn Credential::accept_refresh(
  self : Credential,
  token_response : Json,
  now_seconds : Int,
) -> Result[Credential, String] {
  try {
    let tokens = auth_object(token_response, "refresh response")
    let access_token = auth_text(tokens, "access_token")
    let refresh_token = auth_text(tokens, "refresh_token")
    let token_type = auth_text(tokens, "token_type")
    if token_type.to_lower() != "bearer" {
      fail_auth("AUTH_REFRESH_INVALID", "refresh token response is not Bearer")
    }
    auth_nonempty(access_token, "access token")
    auth_nonempty(refresh_token, "replacement refresh token")
    let lifetime = auth_integer(auth_field(tokens, "expires_in"), "expires_in")
    if lifetime <= 0 || now_seconds > 2147483647 - lifetime {
      fail_auth("AUTH_REFRESH_INVALID", "access token expiry is invalid")
    }
    let scopes = match auth_optional_text(tokens, "scope") {
      Some(value) => split_scopes(value)
      None => self.scopes
    }
    Ok({
      host_id: self.host_id,
      client_id: self.client_id,
      subject: self.subject,
      email: self.email,
      profile_id: self.profile_id,
      id_token: self.id_token,
      access_token,
      refresh_token: Some(refresh_token),
      scopes,
      expires_at: now_seconds + lifetime,
    })
  } catch {
    AuthError(message) => Err(message)
  }
}

///|
/// Classify stable OAuth failures so transient transport/admission errors never
/// delete a usable credential.
pub fn classify_refresh_error(
  code : String,
  http_status : Int,
) -> RefreshDisposition {
  match code {
    "invalid_grant"
    | "refresh_token_expired"
    | "refresh_token_reused"
    | "refresh_token_revoked"
    | "access_denied" => Reauthenticate
    "invalid_client" | "unauthorized_client" | "invalid_request" =>
      ConfigurationError
    _ if http_status == 401 => Reauthenticate
    _ if http_status == 429 || http_status >= 500 || http_status == 0 =>
      Retryable
    _ => Retryable
  }
}
