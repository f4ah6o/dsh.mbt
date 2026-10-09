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
      engine: content.to_json(),
      receipts: [],
      server_id: store.server_id,
      workspace_id: store.workspace_id,
      identity_key: "local:store-limit-test",
      epoch: "test-epoch",
      revision: 1,
      auth_revision: 0,
      external_mcp_catalog_hash: None,
      lsp_catalog_hash: None,
    }
    assert_true(store.save(state) is Ok(_))
    let loaded = match store.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(loaded.engine, content.to_json())

    let oversized : NativeState = {
      ..state,
      engine: "y".repeat(SNAPSHOT_LIMIT).to_json(),
      revision: 2,
    }
    assert_true(store.save(oversized) is Err(_))
    let after_rejection = match store.load() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(after_rejection.engine, content.to_json())
  }
}
