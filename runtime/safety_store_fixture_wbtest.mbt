///|
async test "native store persists one private versioned envelope and locks writers" {
  let fixture = @fs.tmpdir(prefix="dsh-native-store-fixture")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let data_dir = fixture + "/data"
    let store = match NativeStore::open(data_dir) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => ignore(store.close()))

    let lock = match NativeStore::read_lock(store.root) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(store.root.read_text("host.lock").unwrap().1.permission(), 0o600)
    // These keys and timestamp encoding are shared with the Node host's
    // `host.lock` reader, so either host recognizes the same single-writer lock.
    assert_true(json_int(object_field(lock, "pid")) > 0)
    assert_true(json_string(object_field(lock, "hostname")) != "")
    assert_true(json_string(object_field(lock, "token")).length() >= 32)
    assert_true(json_string(object_field(lock, "created_at")).contains("T"))
    assert_true(NativeStore::open(data_dir) is Err(_))

    assert_true(
      store.root.write_atomic(
        "sessions.json",
        "{\"schema\":\"dsh.mbt-session-v1\",\"sessions\":[]}",
        permission=0o600,
      )
      is Ok(_),
    )
    let imported = match store.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(
      string_field(imported.engine, "schema"),
      Some("dsh.mbt-session-v1"),
    )
    assert_eq(imported.receipts.length(), 0)

    let state = {
      engine: Json::object({ "checkpoint": Json::string("fixture") }),
      receipts: [
        Json::object({
          "command_id": Json::string("019a-test-fixture-command"),
          "status": Json::string("accepted"),
        }),
      ],
      server_id: store.server_id,
      workspace_id: store.workspace_id,
      identity_key: "local:safety-fixture",
      epoch: "fixture-epoch",
      revision: 1,
      auth_revision: 0,
    }
    assert_true(store.save(state) is Ok(_))
    let (envelope_text, envelope_version) = match
      store.root.read_text("sessions.json") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(envelope_version.permission(), 0o600)
    let envelope = match parse_json(envelope_text) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(
      json_string(object_field(envelope, "schema")),
      NATIVE_ENVELOPE_SCHEMA,
    )
    assert_eq(json_int(object_field(envelope, "format_version")), 1)
    assert_true(object_field(envelope, "engine") is Some(_))
    assert_true(object_field(envelope, "receipts") is Some(Json::Array(_)))

    assert_true(store.close() is Ok(_))
    assert_true(!@fs.exists(data_dir + "/host.lock"))
    let reopened = match NativeStore::open(data_dir) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => ignore(reopened.close()))
    assert_true(NativeStore::open(data_dir) is Err(_))
    let restored = match reopened.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(string_field(restored.engine, "checkpoint"), Some("fixture"))
    assert_eq(restored.receipts.length(), 1)
    assert_eq(restored.revision, 1)
    assert_eq(restored.identity_key, "local:safety-fixture")

    // A separately opened SafeRoot models a second writer that does not own
    // the NativeStore lock. It may observe and mutate the file, but the stale
    // store version must never overwrite that newer snapshot.
    let competing_root = match SafeRoot::open(data_dir) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => competing_root.close())
    assert_true(
      competing_root.write_atomic(
        "sessions.json",
        "external-writer-snapshot",
        expected=competing_root.read_text("sessions.json").unwrap().1,
        permission=0o600,
      )
      is Ok(_),
    )
    let changed = {
      engine: Json::object({ "checkpoint": Json::string("stale") }),
      receipts: [],
      server_id: reopened.server_id,
      workspace_id: reopened.workspace_id,
      identity_key: "local:safety-fixture",
      epoch: "fixture-epoch",
      revision: 2,
      auth_revision: 0,
    }
    assert_true(reopened.save(changed) is Err(_))
    assert_eq(
      competing_root.read_text("sessions.json").unwrap().0,
      "external-writer-snapshot",
    )

    assert_true(reopened.close() is Ok(_))
    assert_true(!@fs.exists(data_dir + "/host.lock"))
  }
}

///|
async test "native store rejects unsupported receipt envelope versions" {
  let fixture = @fs.tmpdir(prefix="dsh-native-store-version")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let store = match NativeStore::open(fixture + "/data") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => ignore(store.close()))
    assert_true(
      store.root.write_atomic(
        "sessions.json",
        "{\"schema\":\"dsh.native-host-v1\",\"format_version\":2,\"engine\":null,\"receipts\":[]}",
        permission=0o600,
      )
      is Ok(_),
    )
    match store.load() {
      Err(error) =>
        assert_true(
          error.contains("unsupported native snapshot format version"),
        )
      Ok(_) => fail("unsupported native envelope was accepted")
    }
  }
}

///|
async test "native store recovers only a dead local lock owner" {
  let fixture = @fs.tmpdir(prefix="dsh-native-store-stale-lock")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let hostname = match os_hostname() {
      Ok(value) => value
      Err(_) => fail("native hostname fixture is unavailable")
    }
    let local_data = fixture + "/local-data"
    @fs.mkdir(local_data)
    @fs.write_file(
      local_data + "/host.lock",
      @utf8.encode(
        Json::object({
          "pid": (2147483647).to_json(),
          "hostname": hostname.to_json(),
          "token": "dead-owner".to_json(),
          "created_at": "2026-10-08T00:00:00Z".to_json(),
        }).stringify(),
      ),
    )
    let recovered = match NativeStore::open(local_data) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let replacement = match NativeStore::read_lock(recovered.root) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(string_field(replacement, "hostname"), Some(hostname))
    assert_true(string_field(replacement, "token") != Some("dead-owner"))
    assert_true(!@fs.exists(local_data + "/host.recovery"))
    recovered.close().unwrap()

    let remote_data = fixture + "/remote-data"
    @fs.mkdir(remote_data)
    @fs.write_file(
      remote_data + "/host.lock",
      @utf8.encode(
        Json::object({
          "pid": (2147483647).to_json(),
          "hostname": "unknown-other-machine".to_json(),
          "token": "remote-owner".to_json(),
          "created_at": "2026-10-08T00:00:00Z".to_json(),
        }).stringify(),
      ),
    )
    assert_true(NativeStore::open(remote_data) is Err(_))
    let remote_lock = @json.parse(
      @fs.read_file(remote_data + "/host.lock").text(),
    ) catch {
      _ => fail("remote lock marker was not valid JSON")
    }
    assert_eq(string_field(remote_lock, "token"), Some("remote-owner"))
  }
}
