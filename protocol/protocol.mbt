///|
/// Version 1 of the remote client protocol. Bump this when an incompatible
/// field or state transition is introduced; do not rely on enum serialization.
pub const PROTOCOL_VERSION : Int = 1

///|
/// Opaque authorization scope returned by the server. `identity_key` is a
/// server-derived scope identifier, never a credential and never accepted as
/// proof of identity in a request.
pub struct ClientScope {
  server_id : String
  identity_key : String
  workspace_id : String
  auth_revision : Int
}

///|
pub struct AuthAccount {
  email : String?
  profile_id : String?
}

///|
pub struct ModelProjection {
  slug : String
  display_name : String
}

///|
/// Client-safe account status. It intentionally cannot contain OAuth tokens,
/// claims, or provider credentials.
pub struct AuthProjection {
  state : String
  account : AuthAccount?
  plan_usage : String
  scopes : Array[String]
  models : Array[ModelProjection]
  selected_model : String?
}

///|
/// Workspace projection is presentation data only. Server authorization is
/// still checked for every command, receipt lookup, snapshot, and event stream.
pub struct RemoteSnapshot {
  protocol_version : Int
  scope : ClientScope
  epoch : String
  revision : Int
  cursor : String
  auth : AuthProjection
  projection : Json
}

///|
pub struct ProjectionEvent {
  protocol_version : Int
  identity_key : String
  auth_revision : Int
  workspace_id : String
  epoch : String
  revision : Int
  cursor : String
  kind : String
  projection : Json?
}

///|
pub struct RemoteSessionProjection {
  protocol_version : Int
  identity_key : String
  auth_revision : Int
  workspace_id : String
  epoch : String
  revision : Int
  cursor : String
  session : Json
}

///|
pub struct CommandReceipt {
  protocol_version : Int
  workspace_id : String
  command_id : String
  payload_fingerprint : String
  status : String
  accepted_revision : Int?
  result : Json?
  error : String?
}
