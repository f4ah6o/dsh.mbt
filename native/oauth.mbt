// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Native SIWC lifecycle and protected ChatGPT account state.

///|
#borrow(out)
extern "C" fn c_auth_random(out : FixedArray[Byte], length : Int) -> Int = "dsh_auth_random"

///|
#borrow(url)
extern "C" fn c_auth_open_url(url : Bytes) -> Int = "dsh_auth_open_url"

///|
extern "C" fn c_auth_unix_time() -> Int64 = "dsh_auth_unix_time"

///|
const NATIVE_AUTH_HTTP_TIMEOUT_MS : Int = 15000

///|
const NATIVE_AUTH_RESPONSE_BYTE_LIMIT : Int = 1048576

///|
struct AuthEndpoints {
  authorize : String
  token : String
  discovery : String
  models : String
  test_mode : Bool
}

///|
fn AuthEndpoints::production() -> AuthEndpoints {
  {
    authorize: @auth.AUTHORIZE_ENDPOINT,
    token: @auth.TOKEN_ENDPOINT,
    discovery: "https://auth.openai.com/.well-known/openid-configuration",
    models: "https://api.openai.com/v1/models",
    test_mode: false,
  }
}

///|
/// Captured provider selection. The generation binds the request to the
/// account active when the engine dispatched it.
pub struct NativeProviderSelection {
  priv generation : String
  priv model : String
  priv account_identity : String
  priv protocol : NativeProtocol
  priv auth_mode : NativeAuthMode
  priv base_url : String
}

///|
/// Provider wire protocol captured when an engine effect is dispatched.
pub(all) enum NativeProtocol {
  DeepSeekMessages
  OpenAIChatCompletions
  OpenAIResponses
} derive(Eq)

///|
/// Credential source captured with the provider protocol. API keys are passed
/// separately to the runner and are never stored in this selection.
pub(all) enum NativeAuthMode {
  ApiKey
  ChatGPT
} derive(Eq)

///|
pub fn NativeProviderSelection::model(self : NativeProviderSelection) -> String {
  self.model
}

///|
pub fn NativeProviderSelection::generation(
  self : NativeProviderSelection,
) -> String {
  self.generation
}

///|
pub fn NativeProviderSelection::protocol(
  self : NativeProviderSelection,
) -> NativeProtocol {
  self.protocol
}

///|
pub fn NativeProviderSelection::auth_mode(
  self : NativeProviderSelection,
) -> NativeAuthMode {
  self.auth_mode
}

///|
pub fn NativeProviderSelection::base_url(
  self : NativeProviderSelection,
) -> String {
  self.base_url
}

///|
/// Build an explicit API-key selection. The key itself is supplied to the
/// provider runner from a runtime secret snapshot and never enters this value.
pub fn NativeProviderSelection::api_key(
  protocol : NativeProtocol,
  model : String,
  base_url : String?,
  generation : String,
) -> Result[NativeProviderSelection, String] {
  if model.is_empty() || model.length() > 256 {
    return Err(
      "INVALID_MODEL: model must be nonempty and at most 256 characters",
    )
  }
  if generation.is_empty() || generation.length() > 256 {
    return Err("INVALID_SELECTION: provider generation must be nonempty")
  }
  let url = base_url.unwrap_or(
    if protocol == DeepSeekMessages {
      "https://api.deepseek.com/anthropic"
    } else {
      "https://api.openai.com"
    },
  )
  match native_provider_base_url(url) {
    Ok(_) =>
      Ok({
        generation,
        model,
        account_identity: "",
        protocol,
        auth_mode: ApiKey,
        base_url: url,
      })
    Err(error) => Err(error)
  }
}

///|
/// Native credential coordinator. The protected file is the single durable
/// unit for credentials, generation, selected model, and account-scoped model
/// catalog.
pub struct NativeAuth {
  root : SafeRoot
  host_id : String
  gate : @async.Mutex
  login_gate : @async.Mutex
  endpoints : AuthEndpoints
  mut credential : @auth.Credential?
  mut generation : String
  mut selected_model : String?
  mut model_identity : String?
  mut models : Array[Json]
  mut login_state : String
  mut pending_checkpoint : Bool
  mut closed : Bool
}

///|
fn NativeAuth::open(store : NativeStore) -> Result[NativeAuth, String] {
  let root = match SafeRoot::open(store.path()) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  let host_id = store.host_id()
  let state = match native_auth_load(root, host_id) {
    Ok(state) => state
    Err(error) => {
      root.close()
      return Err(error)
    }
  }
  let auth = {
    root,
    host_id,
    gate: @async.Mutex::Mutex(),
    login_gate: @async.Mutex::Mutex(),
    endpoints: AuthEndpoints::production(),
    credential: state.credential,
    generation: state.generation,
    selected_model: state.selected_model,
    model_identity: state.model_identity,
    models: state.models,
    login_state: state.login_state,
    pending_checkpoint: false,
    closed: false,
  }
  if state.was_missing {
    match auth.persist_locked() {
      Ok(_) => ()
      Err(error) => {
        auth.root.close()
        auth.closed = true
        return Err(error)
      }
    }
  }
  Ok(auth)
}

///|
struct NativeAuthLoaded {
  credential : @auth.Credential?
  generation : String
  selected_model : String?
  model_identity : String?
  models : Array[Json]
  login_state : String
  was_missing : Bool
}

///|
fn native_auth_load(
  root : SafeRoot,
  host_id : String,
) -> Result[NativeAuthLoaded, String] {
  let text = match
    root.read_protected_text("siwc-auth.json", max_bytes=1048576) {
    Ok(value) => value
    Err(_) => return Err("protected ChatGPT credential file could not be read")
  }
  let text = match text {
    None =>
      return Ok({
        credential: None,
        generation: "signed-out",
        selected_model: None,
        model_identity: None,
        models: [],
        login_state: "signed_out",
        was_missing: true,
      })
    Some(text) => text
  }
  let raw = @json.parse(text) catch {
    _ => return Err("protected ChatGPT credential file is invalid")
  }
  let fields = match raw {
    Object(fields) => fields
    _ => return Err("protected ChatGPT credential file is invalid")
  }
  let version = native_auth_int(fields.get("version"), 0)
  if version != 1 {
    return Err("unsupported protected ChatGPT credential format")
  }
  let credential = match fields.get("credential") {
    None | Some(Null) => None
    Some(value) => {
      let credential = match @auth.Credential::from_storage_json(value) {
        Ok(value) => value
        Err(_) => return Err("protected ChatGPT credential data is invalid")
      }
      if credential.host_id_for_native() != host_id {
        return Err("protected ChatGPT credential belongs to a different host")
      }
      Some(credential)
    }
  }
  let generation = native_auth_string(fields.get("generation"))
  if generation.is_empty() || generation.length() > 128 {
    return Err("protected ChatGPT account generation is invalid")
  }
  let selected_model = native_auth_optional_string(fields.get("selected_model"))
  let model_identity = native_auth_optional_string(fields.get("model_identity"))
  let models = match fields.get("models") {
    Some(Array(values)) => {
      if values.length() > 500 {
        return Err("protected ChatGPT model cache is too large")
      }
      values
    }
    _ => return Err("protected ChatGPT model cache is invalid")
  }
  let stored_login_state = native_auth_string(fields.get("login_state"))
  let login_state = match credential {
    Some(_) => "connected"
    None if stored_login_state == "reauth_required" => "reauth_required"
    None => "signed_out"
  }
  let current_identity = match credential {
    Some(value) => Some(value.identity_for_native())
    None => None
  }
  if current_identity != model_identity {
    return Ok({
      credential,
      generation,
      selected_model: None,
      model_identity: None,
      models: [],
      login_state,
      was_missing: false,
    })
  }
  Ok({
    credential,
    generation,
    selected_model,
    model_identity,
    models,
    login_state,
    was_missing: false,
  })
}

///|
fn native_auth_int(value : Json?, fallback : Int) -> Int {
  match value {
    Some(Number(number, ..)) if number >= 0.0 &&
      number <= 2147483647.0 &&
      number.to_int().to_double() == number => number.to_int()
    _ => fallback
  }
}

///|
fn native_auth_string(value : Json?) -> String {
  match value {
    Some(String(text)) => text
    _ => ""
  }
}

///|
fn native_auth_optional_string(value : Json?) -> String? {
  match value {
    Some(String(text)) if !text.is_empty() => Some(text)
    _ => None
  }
}

///|
fn NativeAuth::persist_locked(self : NativeAuth) -> Result[Unit, String] {
  let credential = match self.credential {
    Some(value) => value.storage_json()
    None => Json::null()
  }
  let content = Json::object({
    "version": 1,
    "credential": credential,
    "generation": self.generation.to_json(),
    "selected_model": match self.selected_model {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "model_identity": match self.model_identity {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "models": Json::array(self.models),
    "login_state": self.login_state.to_json(),
  }).stringify()
  match self.root.write_atomic_protected("siwc-auth.json", content) {
    Ok(_) => Ok(())
    Err(_) => Err("protected ChatGPT credential checkpoint failed")
  }
}

///|
/// Credential-free projection for local UI and v1 snapshots.
pub fn NativeAuth::status(self : NativeAuth) -> Json {
  if self.closed {
    return {
      "state": "signed_out",
      "account": Json::null(),
      "plan_usage": "disabled",
      "scopes": Json::array([]),
      "models": Json::array([]),
      "selected_model": Json::null(),
    }
  }
  match self.credential {
    None =>
      {
        "state": self.login_state.to_json(),
        "account": Json::null(),
        "plan_usage": "disabled",
        "scopes": Json::array([]),
        "models": Json::array([]),
        "selected_model": match self.selected_model {
          Some(model) => model.to_json()
          None => Json::null()
        },
      }
    Some(credential) => {
      let raw = credential.public_summary()
      let fields = match raw {
        Object(fields) => fields
        _ => Map([])
      }
      fields["models"] = Json::array(self.visible_models())
      fields["state"] = self.login_state.to_json()
      fields["selected_model"] = match self.selected_model {
        Some(model) => model.to_json()
        None => Json::null()
      }
      Json::object(fields)
    }
  }
}

///|
/// Mark an OAuth attempt before handing it to a host-owned background task.
/// Repeated requests do not start a second browser flow.
pub fn NativeAuth::begin_sign_in(self : NativeAuth) -> Result[Json, String] {
  if self.closed {
    return Err("AUTH_CLOSED: authentication manager is closed")
  }
  if self.login_state == "signing_in" {
    return Ok({ "started": false })
  }
  self.login_state = "signing_in"
  Ok({ "started": true })
}

///|
fn NativeAuth::visible_models(self : NativeAuth) -> Array[Json] {
  match self.credential {
    Some(credential) if self.model_identity ==
      Some(credential.identity_for_native()) => self.models
    _ => []
  }
}

///|
/// Refresh the account-visible model catalog. The Responses provider only
/// accepts models returned for this credential and marked `visibility=list`.
pub async fn NativeAuth::models(self : NativeAuth) -> Result[Json, String] {
  self.models_with(async fn(endpoints, token) {
    oauth_fetch_models(endpoints, token)
  })
}

///|
/// Fetch and atomically publish one account-scoped model catalog. The fetch
/// callback is private so fixtures can exercise stale-response and persistence
/// behavior without making a live provider request.
async fn NativeAuth::models_with(
  self : NativeAuth,
  fetch : async (AuthEndpoints, String) -> Result[Array[Json], String],
) -> Result[Json, String] {
  let selection = match self.credential_snapshot() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let credential = match self.credential_for_selection(selection) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let rows = match
    fetch(self.endpoints, credential.access_token_for_transport()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.generation != selection.generation {
    return Err("AUTH_ACCOUNT_CHANGED: account changed while listing models")
  }
  let old_models = self.models
  let old_identity = self.model_identity
  let old_selected_model = self.selected_model
  let old_generation = self.generation
  let selected_is_visible = match self.selected_model {
    Some(selected) =>
      rows.any(row => {
        match row {
          Object(fields) => native_auth_string(fields.get("slug")) == selected
          _ => false
        }
      })
    None => true
  }
  let selected_model = if selected_is_visible {
    self.selected_model
  } else {
    None
  }
  let generation = if selected_model == self.selected_model {
    self.generation
  } else {
    match native_auth_random_id() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  self.models = rows
  self.model_identity = Some(selection.account_identity)
  self.selected_model = selected_model
  self.generation = generation
  match self.persist_locked() {
    Err(error) => {
      self.models = old_models
      self.model_identity = old_identity
      self.selected_model = old_selected_model
      self.generation = old_generation
      Err(error)
    }
    Ok(_) =>
      Ok({
        "models": Json::array(rows),
        "selected_model": match self.selected_model {
          Some(model) => model.to_json()
          None => Json::null()
        },
      })
  }
}

///|
/// Persist a model only after the selected account's fresh model list confirms
/// it. The UI selection then changes the next provider effect's request.
pub async fn NativeAuth::select_model(
  self : NativeAuth,
  model : String,
) -> Result[Json, String] {
  if model.is_empty() || model.length() > 256 {
    return Err("INVALID_MODEL: model slug is empty or too long")
  }
  let listed = match self.models() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let model_list = match listed {
    Object(fields) =>
      match fields.get("models") {
        Some(Array(rows)) => rows
        _ => []
      }
    _ => []
  }
  let mut found = false
  for row in model_list {
    match row {
      Object(fields) if native_auth_string(fields.get("slug")) == model =>
        found = true
      _ => ()
    }
  }
  if !found {
    return Err("INVALID_MODEL: model is not visible to the connected account")
  }
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.credential is None {
    return Err("AUTH_REQUIRED: connect a ChatGPT account first")
  }
  let credential = self.credential.unwrap()
  if self.model_identity != Some(credential.identity_for_native()) {
    return Err("AUTH_ACCOUNT_CHANGED: model catalog belongs to another account")
  }
  if self.selected_model == Some(model) {
    return Ok({ "ok": true, "model": model.to_json() })
  }
  let old_model = self.selected_model
  let old_generation = self.generation
  let generation = match native_auth_random_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.selected_model = Some(model)
  self.generation = generation
  match self.persist_locked() {
    Err(error) => {
      self.selected_model = old_model
      self.generation = old_generation
      Err(error)
    }
    Ok(_) => Ok({ "ok": true, "model": self.selected_model.unwrap().to_json() })
  }
}

///|
/// Capture immutable provider selection at engine effect dispatch.
pub fn NativeAuth::provider_selection(
  self : NativeAuth,
) -> Result[NativeProviderSelection, String] {
  if self.closed {
    return Err("AUTH_REQUIRED: authentication manager is closed")
  }
  let credential = match self.credential {
    Some(value) => value
    None => return Err("AUTH_REQUIRED: connect a ChatGPT account first")
  }
  if !credential.can_use_direct() {
    return Err(
      "AUTH_DIRECT_SCOPE_REQUIRED: direct ChatGPT inference is not enabled",
    )
  }
  let model = match self.selected_model {
    Some(value) => value
    None => return Err("MODEL_REQUIRED: choose an account-visible model first")
  }
  if self.model_identity != Some(credential.identity_for_native()) ||
    !self
    .visible_models()
    .any(row => {
      match row {
        Object(fields) => native_auth_string(fields.get("slug")) == model
        _ => false
      }
    }) {
    return Err("MODEL_REQUIRED: selected model is not in the account catalog")
  }
  Ok({
    generation: self.generation,
    model,
    account_identity: credential.identity_for_native(),
    protocol: OpenAIResponses,
    auth_mode: ChatGPT,
    base_url: "https://api.openai.com",
  })
}

///|
/// Copy the authorized credential and refresh it before expiry. Concurrent
/// requests serialize refresh rotation and persist the replacement before it
/// can be used by another call.
pub async fn NativeAuth::credential_for_selection(
  self : NativeAuth,
  selection : NativeProviderSelection,
) -> Result[@auth.Credential, String] {
  self.credential_for_selection_with(selection, fn() { self.persist_locked() })
}

///|
/// Inject the checkpoint operation so fixtures can exercise a failed flush
/// without relying on filesystem permission behavior that differs for root.
async fn NativeAuth::credential_for_selection_with(
  self : NativeAuth,
  selection : NativeProviderSelection,
  persist : () -> Result[Unit, String],
) -> Result[@auth.Credential, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.generation != selection.generation {
    return Err("AUTH_ACCOUNT_CHANGED: account changed before provider dispatch")
  }
  if self.pending_checkpoint {
    match persist() {
      Err(_) =>
        return Err(
          "AUTH_STORE_ERROR: rotated ChatGPT credential is not durably saved",
        )
      Ok(_) => self.pending_checkpoint = false
    }
  }
  let credential = match self.credential {
    Some(value) if value.identity_for_native() == selection.account_identity =>
      value
    _ =>
      return Err("AUTH_ACCOUNT_CHANGED: selected account is no longer active")
  }
  let now = native_auth_now()
  if credential.expires_at_for_native() > now + 90 {
    return Ok(credential)
  }
  self.refresh_locked(credential, now)
}

///|
async fn NativeAuth::refresh_locked(
  self : NativeAuth,
  credential : @auth.Credential,
  now : Int,
) -> Result[@auth.Credential, String] {
  self.refresh_locked_with(
    credential,
    now,
    async fn(endpoints, endpoint, form) {
      oauth_post_form(endpoints, endpoint, form)
    },
    fn() { self.persist_locked() },
  )
}

///|
/// Keep the rotation/persistence sequence independently fixture-testable.
async fn NativeAuth::refresh_locked_with(
  self : NativeAuth,
  credential : @auth.Credential,
  now : Int,
  post_form : async (AuthEndpoints, String, String) -> Result[
    (Int, Json),
    String,
  ],
  persist : () -> Result[Unit, String],
) -> Result[@auth.Credential, String] {
  let fields = match credential.refresh_request() {
    Ok(value) =>
      match value {
        Object(fields) => fields
        _ => return Err("AUTH_REFRESH_INVALID: refresh request is malformed")
      }
    Err(error) => return Err(error)
  }
  let form = oauth_form([
    ("grant_type", native_auth_string(fields.get("grant_type"))),
    ("client_id", native_auth_string(fields.get("client_id"))),
    ("refresh_token", native_auth_string(fields.get("refresh_token"))),
    ("resource", native_auth_string(fields.get("resource"))),
    ("ext_agent_host_id", native_auth_string(fields.get("ext_agent_host_id"))),
  ])
  let response = match post_form(self.endpoints, self.endpoints.token, form) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (status, body) = response
  if status < 200 || status >= 300 {
    let code = oauth_remote_error_code(body)
    match @auth.classify_refresh_error(code, status) {
      @auth.RefreshDisposition::Reauthenticate => {
        self.credential = None
        self.login_state = "reauth_required"
        self.generation = match native_auth_random_id() {
          Ok(value) => value
          Err(_) => "signed-out"
        }
        self.selected_model = None
        self.model_identity = None
        self.models = []
        self.pending_checkpoint = true
        match self.persist_locked() {
          Ok(_) => self.pending_checkpoint = false
          Err(_) =>
            return Err("AUTH_STORE_ERROR: cannot clear revoked credentials")
        }
        return Err("AUTH_REAUTH_REQUIRED: ChatGPT authorization expired")
      }
      @auth.RefreshDisposition::ConfigurationError =>
        return Err("AUTH_CONFIGURATION_ERROR: ChatGPT refresh was rejected")
      @auth.RefreshDisposition::Retryable =>
        return Err("AUTH_RETRYABLE: ChatGPT refresh request failed")
    }
  }
  let rotated = match credential.accept_refresh(body, now) {
    Ok(value) => value
    Err(_) =>
      return Err("AUTH_REFRESH_INVALID: ChatGPT refresh response is invalid")
  }
  self.credential = Some(rotated)
  self.pending_checkpoint = true
  match persist() {
    Err(_) =>
      Err("AUTH_STORE_ERROR: rotated ChatGPT credential is not durably saved")
    Ok(_) => {
      self.pending_checkpoint = false
      Ok(rotated)
    }
  }
}

///|
/// Reject a late HTTP result when sign-out, reauthorization, or account switch
/// changed the selected generation while the effect was in flight.
pub fn NativeAuth::validate_generation(
  self : NativeAuth,
  selection : NativeProviderSelection,
) -> Result[Unit, String] {
  if self.closed || self.generation != selection.generation {
    Err("AUTH_ACCOUNT_CHANGED: provider result belongs to a previous account")
  } else {
    Ok(())
  }
}

///|
fn NativeAuth::credential_snapshot(
  self : NativeAuth,
) -> Result[NativeProviderSelection, String] {
  if self.closed {
    return Err("AUTH_REQUIRED: authentication manager is closed")
  }
  let credential = match self.credential {
    Some(value) => value
    None => return Err("AUTH_REQUIRED: connect a ChatGPT account first")
  }
  Ok({
    generation: self.generation,
    model: self.selected_model.unwrap_or(""),
    account_identity: credential.identity_for_native(),
    protocol: OpenAIResponses,
    auth_mode: ChatGPT,
    base_url: "https://api.openai.com",
  })
}

///|
pub async fn NativeAuth::sign_in(self : NativeAuth) -> Result[Json, String] {
  self.login_gate.acquire()
  defer self.login_gate.release()
  if self.closed {
    return Err("AUTH_CLOSED: authentication manager is closed")
  }
  self.login_state = "signing_in"
  let result = self.sign_in_flow()
  match result {
    Ok(_) => {
      self.login_state = "connected"
      Ok(self.status())
    }
    Err(error) => {
      self.login_state = if self.credential is Some(_) {
        "connected"
      } else if error.has_prefix("AUTH_REAUTH_REQUIRED") {
        "reauth_required"
      } else {
        "signed_out"
      }
      Err(error)
    }
  }
}

///|
async fn NativeAuth::sign_in_flow(self : NativeAuth) -> Result[Json, String] {
  self.gate.acquire()
  if self.closed {
    self.gate.release()
    return Err("AUTH_CLOSED: authentication manager is closed")
  }
  let expected_generation = self.generation
  let reauth_credential = self.credential
  self.gate.release()
  let server = match native_callback_server() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let redirect_uri = "http://127.0.0.1:\{server.addr.port()}/auth/callback"
  let random_state = match native_auth_random_token(32) {
    Ok(value) => value
    Err(error) => {
      server.close()
      return Err(error)
    }
  }
  let nonce = match native_auth_random_token(24) {
    Ok(value) => value
    Err(error) => {
      server.close()
      return Err(error)
    }
  }
  let verifier = match native_auth_random_token(32) {
    Ok(value) => value
    Err(error) => {
      server.close()
      return Err(error)
    }
  }
  let challenge = match native_auth_challenge(verifier) {
    Ok(value) => value
    Err(error) => {
      server.close()
      return Err(error)
    }
  }
  let reauth = reauth_credential.map(value => value.reauth_context())
  let requested_client_id = reauth.map(value => value.client_id_for_native())
  let selected_subject = reauth.map(value => {
    value.selected_identity_for_native()
  })
  let id_token_hint = reauth.map(value => value.id_token_hint_for_native())
  let attempt = match
    @auth.LoginAttempt::new(
      self.host_id,
      redirect_uri,
      requested_client_id,
      selected_subject,
      id_token_hint,
      None,
      random_state,
      nonce,
      verifier,
      challenge,
    ) {
    Ok(value) => value
    Err(_) => {
      server.close()
      return Err("AUTH_INPUT_INVALID: cannot construct a safe sign-in attempt")
    }
  }
  if !native_auth_endpoint_allowed(
      self.endpoints,
      self.endpoints.authorize,
      "authorize",
    ) {
    server.close()
    return Err("AUTH_ENDPOINT_INVALID: authorization endpoint is not trusted")
  }
  let authorization_url = native_authorization_url(
    self.endpoints.authorize,
    attempt.authorization_params(),
  )
  let open_status = c_auth_open_url(@utf8.encode(authorization_url + "\u0000"))
  if open_status != 0 {
    server.close()
    return Err("AUTH_BROWSER_ERROR: could not open the system browser")
  }
  let callback = match native_wait_for_callback(server) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let checked_callback = match attempt.validate_callback(callback) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fields = match attempt.token_exchange_fields(checked_callback) {
    Ok(value) =>
      match value {
        Object(fields) => fields
        _ =>
          return Err("AUTH_TOKEN_INVALID: authorization exchange is malformed")
      }
    Err(_) =>
      return Err("AUTH_TOKEN_INVALID: authorization exchange is invalid")
  }
  let token_response = match
    oauth_post_form(
      self.endpoints,
      self.endpoints.token,
      oauth_form([
        ("grant_type", native_auth_string(fields.get("grant_type"))),
        ("client_id", native_auth_string(fields.get("client_id"))),
        ("code", native_auth_string(fields.get("code"))),
        ("redirect_uri", native_auth_string(fields.get("redirect_uri"))),
        ("code_verifier", native_auth_string(fields.get("code_verifier"))),
        ("resource", native_auth_string(fields.get("resource"))),
        (
          "ext_agent_host_id",
          native_auth_string(fields.get("ext_agent_host_id")),
        ),
      ]),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (status, token_response) = token_response
  if status < 200 || status >= 300 {
    return Err("AUTH_TOKEN_EXCHANGE_FAILED: ChatGPT authorization was rejected")
  }
  let id_token = match token_response {
    Object(fields) => native_auth_string(fields.get("id_token"))
    _ => ""
  }
  let verified_claims = match native_verify_id_token(self.endpoints, id_token) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let credential = match
    @auth.accept_token_response(
      attempt,
      checked_callback,
      token_response,
      verified_claims,
      true,
      native_auth_now(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if credential.host_id_for_native() != self.host_id {
    return Err("AUTH_HOST_MISMATCH: ChatGPT credential belongs to another host")
  }
  self.commit_sign_in(credential, expected_generation)
}

///|
async fn NativeAuth::commit_sign_in(
  self : NativeAuth,
  credential : @auth.Credential,
  expected_generation : String,
) -> Result[Json, String] {
  self.commit_sign_in_with(credential, expected_generation, fn() {
    self.persist_locked()
  })
}

///|
/// Keep the account replacement transaction independently fixture-testable.
async fn NativeAuth::commit_sign_in_with(
  self : NativeAuth,
  credential : @auth.Credential,
  expected_generation : String,
  persist : () -> Result[Unit, String],
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed || self.generation != expected_generation {
    return Err(
      "AUTH_ACCOUNT_CHANGED: sign-in was superseded by another account change",
    )
  }
  // Browser and OAuth network work may take minutes. Refresh/model state can
  // advance while that work is in flight, so rollback snapshots under this
  // final commit lock instead of restoring a pre-browser copy.
  let rollback_credential = self.credential
  let rollback_generation = self.generation
  let rollback_selected_model = self.selected_model
  let rollback_model_identity = self.model_identity
  let rollback_models = self.models.copy()
  let rollback_login_state = self.login_state
  let rollback_pending_checkpoint = self.pending_checkpoint
  let generation = match native_auth_random_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.credential = Some(credential)
  self.generation = generation
  self.selected_model = None
  self.model_identity = None
  self.models = []
  self.login_state = "connected"
  self.pending_checkpoint = false
  match persist() {
    Err(error) => {
      self.credential = rollback_credential
      self.generation = rollback_generation
      self.selected_model = rollback_selected_model
      self.model_identity = rollback_model_identity
      self.models = rollback_models
      self.login_state = rollback_login_state
      self.pending_checkpoint = rollback_pending_checkpoint
      Err(error)
    }
    Ok(_) => Ok(self.status())
  }
}

///|
pub async fn NativeAuth::sign_out(self : NativeAuth) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed {
    return Err("AUTH_CLOSED: authentication manager is closed")
  }
  let old_credential = self.credential
  let old_generation = self.generation
  let old_selected_model = self.selected_model
  let old_model_identity = self.model_identity
  let old_models = self.models.copy()
  let old_login_state = self.login_state
  let new_generation = match native_auth_random_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.credential = None
  self.login_state = "signed_out"
  self.generation = new_generation
  self.selected_model = None
  self.model_identity = None
  self.models = []
  match self.persist_locked() {
    Err(error) => {
      self.credential = old_credential
      self.generation = old_generation
      self.selected_model = old_selected_model
      self.model_identity = old_model_identity
      self.models = old_models
      self.login_state = old_login_state
      Err(error)
    }
    Ok(_) => Ok({ "cleared": true })
  }
}

///|
pub fn NativeAuth::close(self : NativeAuth) -> Unit {
  if !self.closed {
    if self.pending_checkpoint {
      match self.persist_locked() {
        Ok(_) => self.pending_checkpoint = false
        Err(_) => ()
      }
    }
    self.closed = true
    self.root.close()
  }
}

///|
fn native_auth_now() -> Int {
  let value = c_auth_unix_time()
  if value < 0L || value > 2147483647L {
    0
  } else {
    value.to_int()
  }
}

///|
fn native_auth_random_bytes(length : Int) -> Result[Bytes, String] {
  if length < 1 || length > 4096 {
    return Err("AUTH_RANDOM_ERROR: invalid random byte request")
  }
  let output : FixedArray[Byte] = FixedArray::make(length, b'\x00')
  if c_auth_random(output, length) != 0 {
    return Err("AUTH_RANDOM_ERROR: operating-system entropy is unavailable")
  }
  let bytes : Array[Byte] = []
  for index = 0; index < length; index = index + 1 {
    bytes.push(output[index])
  }
  Ok(Bytes::from_array(bytes[:]))
}

///|
fn native_auth_random_token(length : Int) -> Result[String, String] {
  match native_auth_random_bytes(length) {
    Ok(bytes) => Ok(native_base64url_encode(bytes))
    Err(error) => Err(error)
  }
}

///|
fn native_auth_random_id() -> Result[String, String] {
  native_auth_random_token(24)
}

///|
fn native_auth_challenge(verifier : String) -> Result[String, String] {
  match SafeRoot::sha256(@utf8.encode(verifier)) {
    Ok(digest) => Ok(native_base64url_encode(digest))
    Err(_) => Err("AUTH_RANDOM_ERROR: SHA-256 provider is unavailable")
  }
}

///|
fn native_base64url_encode(bytes : Bytes) -> String {
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  let output = StringBuilder()
  let mut index = 0
  while index + 2 < bytes.length() {
    let value = (bytes[index].to_int() << 16) |
      (bytes[index + 1].to_int() << 8) |
      bytes[index + 2].to_int()
    output.write_char(alphabet[(value >> 18) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[(value >> 12) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[(value >> 6) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[value & 63].to_char().unwrap_or('A'))
    index += 3
  }
  if index + 1 == bytes.length() {
    let value = bytes[index].to_int() << 16
    output.write_char(alphabet[(value >> 18) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[(value >> 12) & 63].to_char().unwrap_or('A'))
  } else if index + 2 == bytes.length() {
    let value = (bytes[index].to_int() << 16) | (bytes[index + 1].to_int() << 8)
    output.write_char(alphabet[(value >> 18) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[(value >> 12) & 63].to_char().unwrap_or('A'))
    output.write_char(alphabet[(value >> 6) & 63].to_char().unwrap_or('A'))
  }
  output.to_string()
}

///|
fn native_base64url_value(character : Char) -> Int? {
  match character {
    'A'..='Z' => Some(character.to_int() - 'A'.to_int())
    'a'..='z' => Some(character.to_int() - 'a'.to_int() + 26)
    '0'..='9' => Some(character.to_int() - '0'.to_int() + 52)
    '-' => Some(62)
    '_' => Some(63)
    _ => None
  }
}

///|
fn native_base64url_decode(
  value : String,
  limit? : Int = 65536,
) -> Result[Bytes, String] {
  if value.is_empty() || value.length() % 4 == 1 || value.length() > limit {
    return Err("malformed base64url input")
  }
  let output : Array[Byte] = []
  let mut buffer = 0
  let mut bits = 0
  for character in value {
    let digit = match native_base64url_value(character) {
      Some(value) => value
      None => return Err("malformed base64url input")
    }
    buffer = (buffer << 6) | digit
    bits += 6
    if bits >= 8 {
      bits -= 8
      output.push(((buffer >> bits) & 255).to_byte())
      buffer = buffer & ((1 << bits) - 1)
    }
  }
  if bits > 0 && buffer != 0 {
    return Err("noncanonical base64url input")
  }
  Ok(Bytes::from_array(output[:]))
}

///|
fn oauth_form(fields : Array[(String, String)]) -> String {
  let output = StringBuilder()
  for index = 0; index < fields.length(); index = index + 1 {
    if index > 0 {
      output.write_char('&')
    }
    output.write_string(native_percent_encode(fields[index].0))
    output.write_char('=')
    output.write_string(native_percent_encode(fields[index].1))
  }
  output.to_string()
}

///|
fn native_percent_encode(value : String) -> String {
  let hex = "0123456789ABCDEF"
  let output = StringBuilder()
  for byte in @utf8.encode(value) {
    let value = byte.to_int()
    if (value >= 'a'.to_int() && value <= 'z'.to_int()) ||
      (value >= 'A'.to_int() && value <= 'Z'.to_int()) ||
      (value >= '0'.to_int() && value <= '9'.to_int()) ||
      value == '-'.to_int() ||
      value == '_'.to_int() ||
      value == '.'.to_int() ||
      value == '~'.to_int() {
      output.write_char(value.to_char().unwrap_or('!'))
    } else {
      output.write_char('%')
      output.write_char(hex[value >> 4].to_char().unwrap_or('0'))
      output.write_char(hex[value & 15].to_char().unwrap_or('0'))
    }
  }
  output.to_string()
}

///|
fn native_percent_decode(value : String) -> Result[String, String] {
  let output : Array[Byte] = []
  let chars = value.to_array()
  let mut index = 0
  while index < chars.length() {
    match chars[index] {
      '+' => {
        output.push(b' ')
        index += 1
      }
      '%' => {
        if index + 2 >= chars.length() {
          return Err("malformed percent encoding")
        }
        let high = native_hex(chars[index + 1])
        let low = native_hex(chars[index + 2])
        match (high, low) {
          (Some(high), Some(low)) => output.push(((high << 4) | low).to_byte())
          _ => return Err("malformed percent encoding")
        }
        index += 3
      }
      character => {
        let encoded = @utf8.encode(character.to_string())
        for byte in encoded {
          output.push(byte)
        }
        index += 1
      }
    }
  }
  let bytes = Bytes::from_array(output[:])
  let text = @utf8.decode(bytes) catch {
    _ => return Err("callback query is not valid UTF-8")
  }
  Ok(text)
}

///|
fn native_hex(value : Char) -> Int? {
  match value {
    '0'..='9' => Some(value.to_int() - '0'.to_int())
    'a'..='f' => Some(value.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(value.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
fn native_parse_callback_query(path : String) -> Result[Json, String] {
  if path.length() > 16384 || !path.has_prefix("/auth/callback?") {
    return Err("AUTH_CALLBACK_INVALID: unexpected OAuth callback path")
  }
  let query = path["/auth/callback?".length():].to_owned()
  let values : Map[String, Json] = Map([])
  for pair in query.split("&") {
    if pair.is_empty() {
      continue
    }
    let (key, value) = match pair.split_once("=") {
      Some((key, value)) => (key, value.to_owned())
      None => (pair, "")
    }
    let key = match native_percent_decode(key.to_owned()) {
      Ok(value) => value
      Err(_) =>
        return Err("AUTH_CALLBACK_INVALID: OAuth callback query is malformed")
    }
    let value = match native_percent_decode(value) {
      Ok(value) => value
      Err(_) =>
        return Err("AUTH_CALLBACK_INVALID: OAuth callback query is malformed")
    }
    if values.contains(key) {
      return Err("AUTH_CALLBACK_INVALID: duplicate OAuth callback field")
    }
    values[key] = value.to_json()
  }
  Ok(Json::object(values))
}

///|
fn native_authorization_url(endpoint : String, params : Json) -> String {
  let fields = match params {
    Object(fields) => fields
    _ => Map([])
  }
  let pairs : Array[(String, String)] = []
  for (key, value) in fields.iter() {
    match value {
      String(value) => pairs.push((key, value))
      _ => ()
    }
  }
  endpoint + "?" + oauth_form(pairs)
}

///|
async fn native_callback_server() -> Result[@http.Server, String] {
  let address = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => return Err("AUTH_CALLBACK_ERROR: loopback address is unavailable")
  }
  Ok(@http.Server::Server(address, reuse_addr=false)) catch {
    _ => Err("AUTH_CALLBACK_ERROR: could not bind the local callback port")
  }
}

///|
async fn native_wait_for_callback(
  server : @http.Server,
) -> Result[Json, String] {
  native_wait_for_callback_timeout(server, 180000)
}

///|
/// Bound both accepting a callback and consuming the complete HTTP request
/// headers. An accepted socket that never finishes its header cannot hold a
/// sign-in task open indefinitely.
async fn native_wait_for_callback_timeout(
  server : @http.Server,
  timeout_ms : Int,
) -> Result[Json, String] {
  let connection : Ref[@http.ServerConnection?] = Ref(None)
  defer {
    server.close()
    match connection.val {
      Some(value) => value.close()
      None => ()
    }
  }
  let callback = @async.with_timeout_opt(timeout_ms, async fn() {
    let (accepted, peer) = server.accept()
    connection.val = Some(accepted)
    server.close()
    if !peer.to_string().has_prefix("127.0.0.1:") {
      return Err("AUTH_CALLBACK_INVALID: callback did not come from localhost")
    }
    let request = accepted.read_request() catch {
      _ => return Err("AUTH_CALLBACK_INVALID: callback request is malformed")
    }
    if request.meth != @http.Get {
      ignore(accepted.send_response(405, "Method Not Allowed"))
      return Err("AUTH_CALLBACK_INVALID: callback method is not GET")
    }
    let query = match native_parse_callback_query(request.path) {
      Ok(value) => value
      Err(error) => {
        ignore(accepted.send_response(400, "Bad Request"))
        return Err(error)
      }
    }
    ignore(
      accepted.send_response(
        200,
        "Sign-in response received. You may close this browser tab.",
        extra_headers={
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
        },
      ),
    )
    accepted.end_response()
    Ok(query)
  }) catch {
    _ => return Err("AUTH_CALLBACK_ERROR: local sign-in callback failed")
  }
  match callback {
    None => Err("AUTH_TIMEOUT: sign-in callback did not finish in time")
    Some(result) => result
  }
}

///|
async fn oauth_post_form(
  endpoints : AuthEndpoints,
  endpoint : String,
  body : String,
  timeout_ms? : Int = NATIVE_AUTH_HTTP_TIMEOUT_MS,
) -> Result[(Int, Json), String] {
  if !native_auth_endpoint_allowed(endpoints, endpoint, "token") {
    return Err("AUTH_ENDPOINT_INVALID: token endpoint is not trusted")
  }
  let headers : @http.Headers = {
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
  }
  let result = @async.with_timeout_opt(timeout_ms, async fn() {
    let client = @http.post_stream(endpoint, headers~)
    defer client.close()
    client.write(body)
    let response = client.end_request()
    let parsed = match oauth_read_json_response(client) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    Ok((response.code, parsed))
  }) catch {
    _ => return Err("AUTH_TRANSPORT: HTTPS token request failed")
  }
  match result {
    None => Err("AUTH_TIMEOUT: token endpoint timed out")
    Some(value) => value
  }
}

///|
async fn oauth_get_json(
  endpoints : AuthEndpoints,
  endpoint : String,
  kind : String,
  headers? : @http.Headers = Map([]),
  timeout_ms? : Int = NATIVE_AUTH_HTTP_TIMEOUT_MS,
) -> Result[(Int, Json), String] {
  if !native_auth_endpoint_allowed(endpoints, endpoint, kind) {
    return Err("AUTH_ENDPOINT_INVALID: HTTPS endpoint is not trusted")
  }
  let result = @async.with_timeout_opt(timeout_ms, async fn() {
    let (response, client) = @http.get_stream(endpoint, headers~)
    defer client.close()
    match oauth_read_json_response(client) {
      Ok(value) => Ok((response.code, value))
      Err(error) => Err(error)
    }
  }) catch {
    _ => return Err("AUTH_TRANSPORT: HTTPS request failed")
  }
  match result {
    None => Err("AUTH_TIMEOUT: HTTPS endpoint timed out")
    Some(value) => value
  }
}

///|
/// Consume an OAuth JSON response incrementally. Both total request timeout
/// and response bytes are bounded before the parser sees provider data.
async fn oauth_read_json_response(
  client : @http.Client,
) -> Result[Json, String] {
  let bytes : Array[Byte] = []
  while client.read_some(max_len=16384) is Some(chunk) {
    if bytes.length() > NATIVE_AUTH_RESPONSE_BYTE_LIMIT - chunk.length() {
      return Err(
        "AUTH_RESPONSE_TOO_LARGE: HTTPS response exceeds the size limit",
      )
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  let body = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("AUTH_RESPONSE_INVALID: HTTPS response is not valid UTF-8")
  }
  let parsed = @json.parse(body) catch {
    _ =>
      return Err("AUTH_RESPONSE_INVALID: HTTPS endpoint returned invalid JSON")
  }
  Ok(parsed)
}

///|
async fn oauth_fetch_models(
  endpoints : AuthEndpoints,
  access_token : String,
) -> Result[Array[Json], String] {
  let headers : @http.Headers = {
    "Accept": "application/json",
    "Authorization": "Bearer " + access_token,
  }
  let response = match
    oauth_get_json(endpoints, endpoints.models, "models", headers~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (status, body) = response
  if status == 401 || status == 403 {
    return Err("AUTH_REAUTH_REQUIRED: account model access was rejected")
  }
  if status < 200 || status >= 300 {
    return Err("MODEL_LIST_FAILED: ChatGPT model list request failed")
  }
  match @provider.decode_models(body) {
    Ok(value) => Ok(value)
    Err(_) => Err("MODEL_LIST_INVALID: account model list is malformed")
  }
}

///|
fn native_auth_endpoint_allowed(
  endpoints : AuthEndpoints,
  endpoint : String,
  kind : String,
) -> Bool {
  if endpoint.length() > 2048 ||
    endpoint.contains("@") ||
    endpoint.contains("#") ||
    endpoint.contains("\\") ||
    endpoint.contains("..") {
    return false
  }
  if endpoints.test_mode {
    endpoint.has_prefix("http://127.0.0.1:") ||
    endpoint.has_prefix("https://127.0.0.1:")
  } else {
    match kind {
      "authorize" => endpoint == @auth.AUTHORIZE_ENDPOINT
      "token" => endpoint == @auth.TOKEN_ENDPOINT
      "discovery" | "jwks" =>
        endpoint.has_prefix("https://auth.openai.com/") &&
        !endpoint.contains("?")
      "models" => endpoint == "https://api.openai.com/v1/models"
      _ => false
    }
  }
}

///|
fn oauth_remote_error_code(body : Json) -> String {
  let fields = match body {
    Object(fields) => fields
    _ => return "provider_error"
  }
  let raw = match fields.get("error") {
    Some(String(value)) => value
    Some(Object(error_fields)) => native_auth_string(error_fields.get("code"))
    _ => "provider_error"
  }
  if raw.is_empty() || raw.length() > 64 {
    return "provider_error"
  }
  for character in raw {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-') {
      return "provider_error"
    }
  }
  raw
}
