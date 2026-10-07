///|
pub fn RemoteSnapshot::parse(raw : String) -> Result[RemoteSnapshot, String] {
  let root = parse_json(raw) catch { _ => return Err("invalid snapshot JSON") }
  match root {
    Json::Object(_) => ()
    _ => return Err("snapshot must be an object")
  }
  let version = int_field(root, "protocol_version")
  if version != PROTOCOL_VERSION {
    return Err("unsupported remote protocol version")
  }
  let scope = match scope_from_json(root) {
    Some(value) => value
    None => return Err("snapshot is missing its authorization scope")
  }
  let epoch = string_field(root, "epoch")
  let cursor = string_field(root, "cursor")
  let revision = int_field(root, "revision")
  if epoch == "" || cursor == "" || revision < 0 {
    return Err("snapshot has an invalid epoch, revision, or cursor")
  }
  let auth = match object_field(root, "auth") {
    Some(value) =>
      match AuthProjection::parse(value) {
        Ok(auth) => auth
        Err(error) => return Err(error)
      }
    None => return Err("snapshot is missing its auth projection")
  }
  let projection = match object_field(root, "projection") {
    Some(value) => value
    None => return Err("snapshot is missing its UI projection")
  }
  Ok({
    protocol_version: version,
    scope,
    epoch,
    revision,
    cursor,
    auth,
    projection,
  })
}

///|
pub fn ProjectionEvent::parse(raw : String) -> Result[ProjectionEvent, String] {
  let root = parse_json(raw) catch { _ => return Err("invalid event JSON") }
  let version = int_field(root, "protocol_version")
  if version != PROTOCOL_VERSION {
    return Err("unsupported remote protocol version")
  }
  let workspace_id = string_field(root, "workspace_id")
  let identity_key = string_field(root, "identity_key")
  let auth_revision = int_field(root, "auth_revision")
  let epoch = string_field(root, "epoch")
  let revision = int_field(root, "revision")
  let cursor = string_field(root, "cursor")
  let kind = string_field(root, "kind")
  if workspace_id == "" ||
    identity_key == "" ||
    auth_revision < 0 ||
    epoch == "" ||
    cursor == "" ||
    revision < 0 {
    return Err("event has an invalid workspace, epoch, revision, or cursor")
  }
  if kind != "projection" && kind != "resync" {
    return Err("event has an unknown kind")
  }
  let projection = object_field(root, "projection")
  if kind == "projection" && projection is None {
    return Err("projection event is missing its projection")
  }
  Ok({
    protocol_version: version,
    identity_key,
    auth_revision,
    workspace_id,
    epoch,
    revision,
    cursor,
    kind,
    projection,
  })
}

///|
pub fn RemoteSessionProjection::parse(
  raw : String,
) -> Result[RemoteSessionProjection, String] {
  let root = parse_json(raw) catch {
    _ => return Err("invalid session projection JSON")
  }
  let version = int_field(root, "protocol_version")
  if version != PROTOCOL_VERSION {
    return Err("unsupported remote protocol version")
  }
  let workspace_id = string_field(root, "workspace_id")
  let identity_key = string_field(root, "identity_key")
  let auth_revision = int_field(root, "auth_revision")
  let epoch = string_field(root, "epoch")
  let revision = int_field(root, "revision")
  let cursor = string_field(root, "cursor")
  let session = match
    object_field(
      object_field(root, "projection").unwrap_or(Json::null()),
      "session",
    ) {
    Some(value) => value
    None => return Err("session response is missing its UI projection")
  }
  if workspace_id == "" ||
    identity_key == "" ||
    auth_revision < 0 ||
    epoch == "" ||
    cursor == "" ||
    revision < 0 {
    return Err(
      "session response has an invalid workspace, epoch, revision, or cursor",
    )
  }
  Ok({
    protocol_version: version,
    identity_key,
    auth_revision,
    workspace_id,
    epoch,
    revision,
    cursor,
    session,
  })
}

///|
pub fn CommandReceipt::parse(raw : String) -> Result[CommandReceipt, String] {
  let root = parse_json(raw) catch {
    _ => return Err("invalid command receipt JSON")
  }
  let version = int_field(root, "protocol_version")
  if version != PROTOCOL_VERSION {
    return Err("unsupported remote protocol version")
  }
  let workspace_id = string_field(root, "workspace_id")
  let command_id = string_field(root, "command_id")
  let fingerprint = string_field(root, "payload_fingerprint")
  let status = string_field(root, "status")
  if workspace_id == "" || command_id == "" || fingerprint == "" {
    return Err("receipt is missing its workspace, command ID, or fingerprint")
  }
  if !["accepted", "completed", "rejected", "uncertain", "expired"].contains(
      status,
    ) {
    return Err("receipt has an unknown status")
  }
  Ok({
    protocol_version: version,
    workspace_id,
    command_id,
    payload_fingerprint: fingerprint,
    status,
    accepted_revision: optional_int_field(root, "accepted_revision"),
    result: optional_field(root, "result"),
    error: optional_string_field(root, "error"),
  })
}

///|
pub fn RemoteSnapshot::json(self : RemoteSnapshot) -> Json {
  Json::object({
    "protocol_version": Json::number(self.protocol_version.to_double()),
    "server_id": Json::string(self.scope.server_id),
    "identity_key": Json::string(self.scope.identity_key),
    "workspace_id": Json::string(self.scope.workspace_id),
    "auth_revision": Json::number(self.scope.auth_revision.to_double()),
    "epoch": Json::string(self.epoch),
    "revision": Json::number(self.revision.to_double()),
    "cursor": Json::string(self.cursor),
    "auth": self.auth.json(),
    "projection": self.projection,
  })
}

///|
fn AuthProjection::parse(value : Json) -> Result[AuthProjection, String] {
  if contains_auth_secret_field(value) {
    return Err("auth projection must not contain credentials or raw claims")
  }
  let state = string_field(value, "state")
  if !["signed_out", "signing_in", "connected", "reauth_required"].contains(
      state,
    ) {
    return Err("auth projection has an unknown state")
  }
  let plan_usage = string_field(value, "plan_usage")
  if plan_usage != "enabled" && plan_usage != "disabled" {
    return Err("auth projection has an invalid plan usage state")
  }
  let account = match optional_field(value, "account") {
    None | Some(Json::Null) => None
    Some(Json::Object(_)) =>
      Some({
        email: optional_string_field(value_at(value, "account"), "email"),
        profile_id: optional_string_field(
          value_at(value, "account"),
          "profile_id",
        ),
      })
    Some(_) => return Err("auth account must be an object or null")
  }
  let scopes = string_array_field(value, "scopes")
  let models_json = match optional_field(value, "models") {
    Some(Json::Array(models)) => models
    _ => return Err("auth projection is missing its model list")
  }
  let models : Array[ModelProjection] = []
  for model in models_json {
    let slug = string_field(model, "slug")
    let display_name = string_field(model, "display_name")
    if slug == "" || display_name == "" {
      return Err("model projection is missing its slug or display name")
    }
    models.push({ slug, display_name, })
  }
  let selected_model = optional_string_field(value, "selected_model")
  if selected_model is Some(slug) && !models.any(model => model.slug == slug) {
    return Err("selected model is not present in the visible account catalog")
  }
  Ok({ state, account, plan_usage, scopes, models, selected_model, })
}

///|
fn contains_auth_secret_field(value : Json) -> Bool {
  match value {
    Json::Object(fields) => {
      for key, item in fields {
        if [
            "access_token", "refresh_token", "id_token", "client_secret", "provider_token",
            "credential", "authorization", "claims", "raw_claims",
          ].contains(key) ||
          contains_auth_secret_field(item) {
          return true
        }
      }
      false
    }
    Json::Array(items) => items.any(contains_auth_secret_field)
    _ => false
  }
}

///|
pub fn AuthProjection::json(self : AuthProjection) -> Json {
  Json::object({
    "state": Json::string(self.state),
    "account": match self.account {
      None => Json::null()
      Some(account) =>
        Json::object({
          "email": optional_string_json(account.email),
          "profile_id": optional_string_json(account.profile_id),
        })
    },
    "plan_usage": Json::string(self.plan_usage),
    "scopes": Json::array(self.scopes.map(Json::string)),
    "models": Json::array(
      self.models.map(model => {
        Json::object({
          "slug": Json::string(model.slug),
          "display_name": Json::string(model.display_name),
        })
      }),
    ),
    "selected_model": optional_string_json(self.selected_model),
  })
}

///|
fn scope_from_json(root : Json) -> ClientScope? {
  let server_id = string_field(root, "server_id")
  let identity_key = string_field(root, "identity_key")
  let workspace_id = string_field(root, "workspace_id")
  let auth_revision = int_field(root, "auth_revision")
  if server_id == "" ||
    identity_key == "" ||
    workspace_id == "" ||
    auth_revision < 0 {
    None
  } else {
    Some({ server_id, identity_key, workspace_id, auth_revision, })
  }
}

///|
pub fn ClientScope::storage_key(self : ClientScope) -> String {
  "dsh-client-v1:" +
  part(self.server_id) +
  part(self.identity_key) +
  part(self.workspace_id) +
  part(self.auth_revision.to_string())
}
