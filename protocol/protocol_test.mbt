///|
test "command fingerprint preimage sorts object keys recursively" {
  let first = @protocol.RemoteCommand::{
    protocol_version: @protocol.PROTOCOL_VERSION,
    workspace_id: "workspace",
    command_id: "same-id",
    session_id: Some("session"),
    operation: "session_send",
    input: Json::object({
      "prompt": Json::string("日本語 🌱"),
      "options": Json::object({ "z": Json::number(2.0), "a": Json::number(1.0) }),
    }),
    approval_revision: None,
  }
  let second = @protocol.RemoteCommand::{
    protocol_version: @protocol.PROTOCOL_VERSION,
    workspace_id: "workspace",
    command_id: "different-id",
    session_id: Some("session"),
    operation: "session_send",
    input: Json::object({
      "options": Json::object({ "a": Json::number(1.0), "z": Json::number(2.0) }),
      "prompt": Json::string("日本語 🌱"),
    }),
    approval_revision: None,
  }
  let canonical = @protocol.canonical_command_payload(first)
  assert_eq(canonical, @protocol.canonical_command_payload(second))
  assert_eq(
    canonical, "{\"approval_revision\":null,\"input\":{\"options\":{\"a\":1,\"z\":2},\"prompt\":\"日本語 🌱\"},\"operation\":\"session_send\",\"protocol_version\":1,\"session_id\":\"session\",\"workspace_id\":\"workspace\"}",
  )
}

///|
test "snapshot codec accepts only credential-free auth projection" {
  let good = "{\"protocol_version\":1,\"server_id\":\"server-a\",\"identity_key\":\"user-a\",\"workspace_id\":\"work-a\",\"auth_revision\":2,\"epoch\":\"epoch-a\",\"revision\":5,\"cursor\":\"epoch-a:5\",\"auth\":{\"state\":\"connected\",\"account\":{\"email\":\"owner@example.test\",\"profile_id\":\"profile-1\"},\"plan_usage\":\"enabled\",\"scopes\":[\"resource.invoke\"],\"models\":[{\"slug\":\"gpt-test\",\"display_name\":\"GPT Test\"}],\"selected_model\":\"gpt-test\"},\"projection\":{\"sessions\":[]}}"
  let snapshot = @protocol.RemoteSnapshot::parse(good).unwrap()
  assert_eq(snapshot.auth.selected_model, Some("gpt-test"))
  assert_true(
    @protocol.RemoteSnapshot::parse(
      good.replace(
        old="gpt-test\"},\"projection",
        new="unlisted\"},\"projection",
      ),
    )
    is Err(_),
  )
  let leaked = good.replace(
    old="\"plan_usage\":",
    new="\"access_token\":\"secret\",\"plan_usage\":",
  )
  assert_true(@protocol.RemoteSnapshot::parse(leaked) is Err(_))
}

///|
test "UUIDv7 IDs encode a bounded creation time and host entropy" {
  let generated = @protocol.uuid_v7_command_id_from_entropy(
    1700000000000L, "00000000000000000000000000000000",
  )
  assert_eq(generated, Ok("018bcfe5-6800-7000-8000-000000000000"))
  let id = generated.unwrap()
  assert_true(@protocol.is_uuid_v7_command_id(id))
  assert_false(
    @protocol.is_uuid_v7_command_id("018BCFE5-6800-7000-8000-000000000000"),
  )
  assert_eq(@protocol.uuid_v7_command_timestamp_ms(id), Some(1700000000000L))
  assert_true(
    @protocol.validate_uuid_v7_command_id_time(id, 1700000000100L, 100L, 20L),
  )
  assert_false(
    @protocol.validate_uuid_v7_command_id_time(id, 1700000000101L, 100L, 20L),
  )
  assert_false(
    @protocol.validate_uuid_v7_command_id_time(id, 1699999999900L, 100L, 20L),
  )
}

///|
test "remote command parser requires exactly the v1 wire fields" {
  let valid = "{\"protocol_version\":1,\"workspace_id\":\"workspace\",\"command_id\":\"018bcfe5-6800-7000-8000-000000000000\",\"session_id\":\"session\",\"operation\":\"session_send\",\"input\":{\"prompt\":\"hello\"},\"approval_revision\":null}"
  assert_true(@protocol.RemoteCommand::parse(valid) is Ok(_))
  assert_true(
    @protocol.RemoteCommand::parse(
      valid.replace(old="\"protocol_version\":1", new="\"protocol_version\":2"),
    )
    is Err(_),
  )
  assert_true(
    @protocol.RemoteCommand::parse(
      valid.replace(
        old="\"approval_revision\":null",
        new="\"host_token\":\"x\",\"approval_revision\":null",
      ),
    )
    is Err(_),
  )
  assert_true(
    @protocol.RemoteCommand::parse(
      valid.replace(
        old="018bcfe5-6800-7000-8000-000000000000",
        new="not-a-uuid",
      ),
    )
    is Err(_),
  )
}
