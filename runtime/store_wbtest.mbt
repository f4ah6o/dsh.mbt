///|
async test "native snapshot writes exceed the workspace file limit but stay bounded" {
  let fixture = @fs.tmpdir(prefix="dsh-native-store-limit")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let store = match NativeStore::open(fixture + "/data") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(store.close()))
    })
    let content = "x".repeat(1200000)
    let state : NativeState = {
      engine: Json(content),
      archive_objects: [],
      archive_sources: [],
      receipts: [],
      server_id: store.server_id,
      workspace_id: store.workspace_id,
      identity_key: "local:store-limit-test",
      epoch: "test-epoch",
      revision: 1,
      auth_revision: 0,
      external_mcp_catalog_hash: None,
      lsp_catalog_hash: None,
      acp_sessions: [],
    }
    assert_true(store.save(state) is Ok(_))
    let loaded = match store.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(loaded.engine, Json(content))

    let oversized : NativeState = {
      ..state,
      engine: Json("y".repeat(SNAPSHOT_LIMIT)),
      revision: 2,
    }
    assert_true(store.save(oversized) is Err(_))
    let after_rejection = match store.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(after_rejection.engine, Json(content))
  }
}

///|
async test "archive inventory charges orphans and fails closed on special entries" {
  let fixture = @fs.tmpdir(prefix="dsh-native-archive-inventory")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let store = match NativeStore::open(fixture + "/data") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(store.close()))
    })
    store.archive_root
    .write_atomic("orphan.tmp", "orphan bytes", permission=0o600)
    .unwrap()
    let (bytes, entries) = match store.archive_inventory() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(bytes, 12L)
    assert_eq(entries, 1)

    @fs.mkdir(store.archive_root.path() + "/nested")
    assert_true(store.archive_inventory() is Err(_))
    @fs.rmdir(store.archive_root.path() + "/nested")

    let external = fixture + "/external"
    @fs.mkdir(external)
    @fs.symlink(store.archive_root.path() + "/linked", target=external)
    assert_true(store.archive_inventory() is Err(_))

    assert_true(native_archive_reservation_allowed(0L, 0, 128))
    assert_false(
      native_archive_reservation_allowed(
        NATIVE_ARCHIVE_STORAGE_QUOTA - 100L,
        0,
        128,
      ),
    )
    assert_false(
      native_archive_reservation_allowed(
        0L,
        NATIVE_ARCHIVE_INVENTORY_ENTRY_LIMIT - 1,
        128,
      ),
    )
  }
}

///|
async test "v2 archive store publishes fresh objects and verifies manifest coverage on reopen" {
  let fixture = @fs.tmpdir(prefix="dsh-native-archive-reopen")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let store = match NativeStore::open(fixture + "/data") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let content = "😀archive source"[:].repeat(16).to_owned()
    let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
      content,
    )
    let object = NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan, content, projection, threshold, head, tail,
    ).unwrap()
    let engine_reference = @engine.ToolResultArchiveRef::from_json(
      object.reference().json(),
    ).unwrap()
    let source = @engine.ToolResultArchiveSource::from_object_text(
      engine_reference,
      object.encoded_object(),
    ).unwrap()

    let unknown_file_name = "a".repeat(48) + ".json"
    let unknown = store.publish_archive_object_with(object, unknown_file_name, (
      _root,
      _name,
      _raw,
      _limit,
    ) => Err(AtomicCreateNoReplaceError::OutcomeUnknown("injected")))
    assert_true(unknown is Err(_))
    assert_eq(store.archive_inventory().unwrap(), (0L, 0))

    let unknown_after_publish_name = "b".repeat(48) + ".json"
    let unknown_after_publish = store.publish_archive_object_with(
      object,
      unknown_after_publish_name,
      (root, name, raw, max_bytes) => {
        match
          root.create_atomic_no_replace(name, raw, max_bytes, permission=0o600) {
          Ok(_) =>
            Err(
              AtomicCreateNoReplaceError::OutcomeUnknown(
                "injected after publication",
              ),
            )
          Err(error) => Err(error)
        }
      },
    )
    assert_true(unknown_after_publish is Err(_))
    assert_eq(
      store.archive_inventory().unwrap(),
      (@utf8.encode(object.encoded_object()).length().to_int64(), 1),
    )
    let matching_exists = store.publish_archive_object_with(
      object,
      unknown_after_publish_name,
      (root, name, raw, max_bytes) => {
        root.create_atomic_no_replace(name, raw, max_bytes, permission=0o600)
      },
    )
    assert_true(matching_exists is Err(_))
    assert_eq(store.archive_inventory().unwrap().1, 1)

    let locator = match
      store.publish_archive_object(object, "c".repeat(48) + ".json") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(locator.object_id, object.reference().object_id())
    assert_true(locator.file_name.has_suffix(".json"))
    let compact = engine.tool_result_archive_candidate(plan, source).unwrap()
    let state : NativeState = {
      engine: compact,
      archive_objects: [locator],
      archive_sources: [source],
      receipts: [],
      acp_sessions: [],
      server_id: store.server_id,
      workspace_id: store.workspace_id,
      identity_key: "local:archive-reopen-test",
      epoch: "archive-epoch",
      revision: 1,
      auth_revision: 0,
      external_mcp_catalog_hash: None,
      lsp_catalog_hash: None,
    }
    assert_true(store.save(state) is Ok(_))
    let (serialized, _) = store.root.read_text("sessions.json").unwrap()
    assert_eq(
      int_field(parse_json(serialized).unwrap(), "format_version"),
      Some(2),
    )
    assert_true(store.close() is Ok(_))

    let reopened = match NativeStore::open(fixture + "/data") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let loaded = match reopened.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(loaded.archive_objects.length(), 1)
    assert_eq(loaded.archive_sources.length(), 1)
    assert_eq(loaded.archive_sources[0].content(), content)
    assert_eq(loaded.archive_sources[0].pruned_content(), projection)
    assert_eq(loaded.engine, compact)
    assert_eq(
      reopened
      .read_archive_object(
        locator,
        NativeToolResultArchiveRef::from_json(object.reference().json()).unwrap(),
      )
      .unwrap()
      .original_content(),
      content,
    )
    let (raw_object, _) = reopened.archive_root
      .read_text(locator.file_name, max_bytes=1048576)
      .unwrap()
    let forged = raw_object.replace_all(old="archive", new="archivE")
    assert_true(
      reopened.archive_root.write_atomic_bounded(
        locator.file_name,
        forged,
        1048576,
        permission=0o600,
      )
      is Ok(_),
    )
    assert_true(
      reopened.read_archive_object(
        locator,
        NativeToolResultArchiveRef::from_json(object.reference().json()).unwrap(),
      )
      is Err(_),
    )
  }
}
