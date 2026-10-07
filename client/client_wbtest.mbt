///|
fn test_snapshot(
  revision : Int,
  epoch : String,
  identity_key : String,
  auth_revision : Int,
  sessions : String,
) -> @protocol.RemoteSnapshot {
  let raw = "{\"protocol_version\":1,\"server_id\":\"server-a\",\"identity_key\":\"" +
    identity_key +
    "\",\"workspace_id\":\"work-a\",\"auth_revision\":" +
    auth_revision.to_string() +
    ",\"epoch\":\"" +
    epoch +
    "\",\"revision\":" +
    revision.to_string() +
    ",\"cursor\":\"" +
    epoch +
    ":" +
    revision.to_string() +
    "\",\"auth\":{\"state\":\"signed_out\",\"account\":null,\"plan_usage\":\"disabled\",\"scopes\":[],\"models\":[]},\"projection\":{\"sessions\":" +
    sessions +
    "}}"
  @protocol.RemoteSnapshot::parse(raw).unwrap()
}

///|
test "snapshot and event cursors reject stale gaps and epoch changes" {
  let client = ClientState::new()
  assert_true(
    client.accept_snapshot(test_snapshot(4, "epoch-a", "user-a", 1, "[]"))
    is SnapshotAccepted,
  )
  let event = @protocol.ProjectionEvent::parse(
    "{\"protocol_version\":1,\"identity_key\":\"user-a\",\"auth_revision\":1,\"workspace_id\":\"work-a\",\"epoch\":\"epoch-a\",\"revision\":5,\"cursor\":\"epoch-a:5\",\"kind\":\"projection\",\"projection\":{\"sessions\":[]}}",
  ).unwrap()
  assert_true(client.accept_event(event) is EventApplied)
  assert_eq(client.revision, 5)
  assert_true(client.accept_event(event) is EventDuplicate)
  let gap = @protocol.ProjectionEvent::parse(
    "{\"protocol_version\":1,\"identity_key\":\"user-a\",\"auth_revision\":1,\"workspace_id\":\"work-a\",\"epoch\":\"epoch-a\",\"revision\":7,\"cursor\":\"epoch-a:7\",\"kind\":\"projection\",\"projection\":{\"sessions\":[]}}",
  ).unwrap()
  assert_true(client.accept_event(gap) is EventGap)
  assert_true(client.connection is NeedsResync)
}

///|
test "auth scope changes clear drafts selections and unresolved command IDs" {
  let client = ClientState::new()
  assert_true(
    client.accept_snapshot(
      test_snapshot(1, "epoch-a", "user-a", 1, "[{\"id\":\"s1\"}]"),
    )
    is SnapshotAccepted,
  )
  client.set_draft("private draft")
  client.set_selected_session(Some("s1"))
  let command = client
    .queue_command(
      "018bcfe5-6800-7000-8000-000000000000",
      "session_send",
      Some("s1"),
      Json::object({ "prompt": Json::string("hello") }),
      None,
    )
    .unwrap()
  assert_eq(command.command_id, "018bcfe5-6800-7000-8000-000000000000")
  assert_true(
    client.accept_snapshot(
      test_snapshot(2, "epoch-a", "user-b", 2, "[{\"id\":\"s1\"}]"),
    )
    is SnapshotIdentityChanged,
  )
  assert_eq(client.draft, "")
  assert_true(client.selected_session is None)
  assert_true(client.pending_command_ids().is_empty())
}

///|
test "approval commands are anchored to the pending call revision" {
  let summaries = "[{\"id\":\"s1\",\"pending_approval\":{\"call_id\":\"call-a\"},\"approval_revision\":9}]"
  let client = ClientState::new()
  assert_true(
    client.accept_snapshot(test_snapshot(12, "epoch-a", "user-a", 1, summaries))
    is SnapshotAccepted,
  )
  let input : Json = {
    "session_id": "s1",
    "call_id": "call-a",
    "approved": true,
  }
  let approval_id = "018bcfe5-6800-7000-8000-000000000001"
  assert_true(
    client.queue_command(
      approval_id,
      "tool_approve",
      Some("s1"),
      input,
      Some(8),
    )
    is Err(_),
  )
  let command = client
    .queue_command(approval_id, "tool_approve", Some("s1"), input, Some(9))
    .unwrap()
  assert_eq(command.approval_revision, Some(9))
  assert_true(
    client.queue_command(
      approval_id,
      "tool_approve",
      Some("s1"),
      { "call_id": "call-a", "approved": false },
      Some(9),
    )
    is Err(_),
  )
}

///|
test "persisted preferences keep only scope-bound UI and receipt metadata" {
  let client = ClientState::new()
  assert_true(
    client.accept_snapshot(
      test_snapshot(1, "epoch-a", "user-a", 3, "[{\"id\":\"s1\"}]"),
    )
    is SnapshotAccepted,
  )
  client.set_draft("draft remains local to this identity")
  client.set_selected_session(Some("s1"))
  let preferences = client.preferences_json().stringify()
  assert_true(preferences.contains("draft remains local"))
  assert_false(preferences.contains("session snapshot"))
  let restored = ClientState::new()
  assert_true(
    restored.accept_snapshot(
      test_snapshot(1, "epoch-a", "user-a", 3, "[{\"id\":\"s1\"}]"),
    )
    is SnapshotAccepted,
  )
  assert_true(restored.restore_preferences(preferences))
  assert_eq(restored.draft, "draft remains local to this identity")
  assert_eq(restored.selected_session, Some("s1"))
  assert_true(
    restored.restore_preferences(
      preferences.replace(old="user-a", new="user-b"),
    ) ==
    false,
  )
  assert_eq(restored.draft, "")
  assert_true(restored.selected_session is None)
}
