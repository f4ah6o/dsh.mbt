///|
async fn native_subagent_audit_inspection_test_store(
  data_dir : String,
  workspace_id~ : String = "workspace-audit-123",
  with_audit_directory~ : Bool = true,
) -> Unit {
  @fs.mkdir(data_dir, permission=0o700)
  let root = match SafeRoot::open(data_dir) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(
    root.create_exclusive("workspace-id", workspace_id, permission=0o600)
    is Ok(_),
  )
  root.close()
  if with_audit_directory {
    @fs.mkdir(data_dir + "/subagent-audits", permission=0o700)
  }
}

///|
fn native_subagent_audit_inspection_test_write(
  data_dir : String,
  record : Json,
) -> Unit raise {
  let child_id = string_field(record, "child_id").unwrap()
  let encoded = native_subagent_audit_encode(record).unwrap()
  let root = match SafeRoot::open(data_dir) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(
    root.create_exclusive(
      "subagent-audits/" + child_id + ".json",
      encoded,
      permission=0o600,
    )
    is Ok(_),
  )
  root.close()
}

///|
async fn native_subagent_audit_inspection_test_sparse_file(
  path : String,
  last_position : Int64,
) -> Unit {
  let file = @fs.open(
    path,
    mode=@fs.WriteOnly,
    create_mode=@fs.CreateNew,
    permission=0o600,
  )
  file.write_at(b"x", position=last_position)
  file.close()
  @fs.chmod(path, 0o600)
}

///|
async test "child audit inspection filters by parent and workspace without exposing snapshots in list" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-inspection")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let data_dir = fixture + "/data"
    native_subagent_audit_inspection_test_store(data_dir)
    let visible_id = "subagent-123e4567-e89b-42d3-a456-426614174000"
    let other_parent_id = "subagent-223e4567-e89b-42d3-a456-426614174000"
    let other_workspace_id = "subagent-323e4567-e89b-42d3-a456-426614174000"
    native_subagent_audit_inspection_test_write(
      data_dir,
      native_subagent_audit_test_record(
        child_id=visible_id,
        workspace_id="workspace-audit-123",
      ),
    )
    let other_parent_fields = match
      native_subagent_audit_test_record(child_id=other_parent_id) {
      Json::Object(fields) => fields
      _ => fail("audit fixture is not an object")
    }
    other_parent_fields["parent_session_id"] = Json::string(
      "parent-other-session",
    )
    native_subagent_audit_inspection_test_write(
      data_dir,
      Json::object(other_parent_fields),
    )
    native_subagent_audit_inspection_test_write(
      data_dir,
      native_subagent_audit_test_record(
        child_id=other_workspace_id,
        workspace_id="workspace-other-123",
      ),
    )

    let before = SafeRoot::open(data_dir).unwrap()
    let before_version = before.directory_version().unwrap()
    before.close()
    let listed = native_subagent_audit_inspect_data_dir(
      data_dir,
      "parent-audit-session",
      None,
    ).unwrap()
    let audits = match object_field(listed, "audits") {
      Some(Json::Array(items)) => items
      _ => fail("audit list omitted its result array")
    }
    assert_eq(audits.length(), 1)
    assert_eq(string_field(audits[0], "child_id"), Some(visible_id))
    assert_eq(object_field(audits[0], "engine_snapshot"), None)
    let visible = native_subagent_audit_inspect_data_dir(
      data_dir,
      "parent-audit-session",
      Some(visible_id),
    ).unwrap()
    let record = object_field(visible, "audit").unwrap()
    assert_eq(string_field(record, "child_id"), Some(visible_id))
    assert_true(object_field(record, "engine_snapshot") is Some(_))
    assert_true(
      native_subagent_audit_inspect_data_dir(
        data_dir,
        "parent-other-session",
        Some(visible_id),
      )
      is Err(_),
    )
    let after = SafeRoot::open(data_dir).unwrap()
    assert_true(before_version.same(after.directory_version().unwrap()))
    after.close()
    assert_false(@fs.exists(data_dir + "/host.lock"))
  }
}

///|
async test "child audit inspection reports missing directories without creating them" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-inspection-missing")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let data_dir = fixture + "/data"
    native_subagent_audit_inspection_test_store(
      data_dir,
      with_audit_directory=false,
    )
    let listed = native_subagent_audit_inspect_data_dir(
      data_dir,
      "parent-audit-session",
      None,
    ).unwrap()
    assert_eq(object_field(listed, "audits"), Some(Json::array([])))
    assert_false(@fs.exists(data_dir + "/subagent-audits"))
    assert_true(
      native_subagent_audit_inspect_data_dir(
        data_dir,
        "parent-audit-session",
        Some("subagent-123e4567-e89b-42d3-a456-426614174000"),
      )
      is Err(_),
    )
    assert_false(@fs.exists(data_dir + "/subagent-audits"))
  }
}

///|
async test "child audit inspection rejects malformed, mismatched, and oversized records" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-inspection-records")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let data_dir = fixture + "/data"
    native_subagent_audit_inspection_test_store(data_dir)
    let malformed_id = "subagent-123e4567-e89b-42d3-a456-426614174000"
    let unsupported_id = "subagent-223e4567-e89b-42d3-a456-426614174000"
    let requested_id = "subagent-323e4567-e89b-42d3-a456-426614174000"
    let envelope_id = "subagent-423e4567-e89b-42d3-a456-426614174000"
    let large_id = "subagent-523e4567-e89b-42d3-a456-426614174000"
    let root = SafeRoot::open(data_dir).unwrap()
    assert_true(
      root.create_exclusive(
        "subagent-audits/" + malformed_id + ".json",
        "not-json",
        permission=0o600,
      )
      is Ok(_),
    )
    let unsupported = match
      native_subagent_audit_test_record(child_id=unsupported_id) {
      Json::Object(fields) => fields
      _ => fail("audit fixture is not an object")
    }
    unsupported["schema"] = Json::string("future-audit-schema")
    assert_true(
      root.create_exclusive(
        "subagent-audits/" + unsupported_id + ".json",
        Json::object(unsupported).stringify(),
        permission=0o600,
      )
      is Ok(_),
    )
    assert_true(
      root.create_exclusive(
        "subagent-audits/" + requested_id + ".json",
        native_subagent_audit_encode(
          native_subagent_audit_test_record(child_id=envelope_id),
        ).unwrap(),
        permission=0o600,
      )
      is Ok(_),
    )
    root.close()
    native_subagent_audit_inspection_test_sparse_file(
      data_dir + "/subagent-audits/" + large_id + ".json",
      NATIVE_SUBAGENT_AUDIT_MAX_BYTES.to_int64(),
    )

    for child_id in [malformed_id, unsupported_id, requested_id, large_id] {
      assert_true(
        native_subagent_audit_inspect_data_dir(
          data_dir,
          "parent-audit-session",
          Some(child_id),
        )
        is Err(_),
      )
    }
  }
}

///|
async test "child audit inspection counts ignored temporary bytes against the directory cap" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-inspection-total-bytes")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let data_dir = fixture + "/data"
    native_subagent_audit_inspection_test_store(data_dir)
    if native_os_is_windows() {
      // The Windows fixture may allocate the hole physically; bound arithmetic
      // is covered by the shared metadata cap path on POSIX sparse files.
      assert_false(
        native_subagent_audit_inspection_byte_add_fits(
          NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES,
          1L,
        ),
      )
    } else {
      native_subagent_audit_inspection_test_sparse_file(
        data_dir + "/subagent-audits/..dsh-interrupted.tmp",
        NATIVE_SUBAGENT_AUDIT_MAX_TOTAL_BYTES,
      )
      assert_true(
        native_subagent_audit_inspect_data_dir(
          data_dir,
          "parent-audit-session",
          None,
        )
        is Err(_),
      )
    }
  }
}

///|
async test "subagent audit CLI inspects without opening an invalid native store" {
  if native_os_is_windows() {
    // The shared native-worker fixture currently uses POSIX absolute paths.
    ()
  } else {
    let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-cli")
    @async.with_task_group() <| group => {
      group.add_defer(() => @fs.rmdir(fixture, recursive=true))
      let data_dir = fixture + "/data"
      native_subagent_audit_inspection_test_store(data_dir)
      let child_id = "subagent-123e4567-e89b-42d3-a456-426614174000"
      native_subagent_audit_inspection_test_write(
        data_dir,
        native_subagent_audit_test_record(child_id~),
      )
      let root = SafeRoot::open(data_dir).unwrap()
      assert_true(
        root.create_exclusive("host.lock", "not-json", permission=0o600)
        is Ok(_),
      )
      root.close()
      assert_true(NativeStore::open(data_dir) is Err(_))
      let executable = safety_native_worker_launcher().unwrap()
      let parent_session_id = "parent-audit-session"
      let (list_status, list_stdout, list_stderr) = match
        @async.with_timeout_opt(10000, async fn() {
          @process.collect_output(executable, [
            "subagent-audits", "list", "--session", parent_session_id, "--data-dir",
            data_dir, "--json",
          ])
        }) {
        Some(result) => result
        None => fail("subagent audit list CLI did not exit within 10 seconds")
      }
      assert_eq(list_status, 0)
      assert_true(list_stdout.text().contains(child_id))
      assert_false(
        list_stdout.text().contains("Finish the fixture child task."),
      )
      assert_eq(list_stderr.text(), "")
      let (show_status, show_stdout, show_stderr) = match
        @async.with_timeout_opt(10000, async fn() {
          @process.collect_output(executable, [
            "subagent-audits", "show", child_id, "--session", parent_session_id,
            "--data-dir", data_dir, "--json",
          ])
        }) {
        Some(result) => result
        None => fail("subagent audit show CLI did not exit within 10 seconds")
      }
      assert_eq(show_status, 0)
      assert_true(show_stdout.text().contains("Finish the fixture child task."))
      assert_eq(show_stderr.text(), "")
      assert_eq(@fs.read_file(data_dir + "/host.lock").text(), "not-json")
      assert_false(@fs.exists(data_dir + "/sessions"))
    }
  }
}

///|
async test "child audit inspection rejects unsafe files, overfull entries, and nested directories" {
  let fixture = @fs.tmpdir(prefix="dsh-subagent-audit-inspection-bounds")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let unsafe_data_dir = fixture + "/unsafe-root"
    @fs.mkdir(unsafe_data_dir, permission=0o700)
    @fs.chmod(unsafe_data_dir, 0o755)
    assert_true(
      native_subagent_audit_inspect_data_dir(
        unsafe_data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
    let unsafe_file_data_dir = fixture + "/unsafe-file"
    native_subagent_audit_inspection_test_store(unsafe_file_data_dir)
    let unsafe_file_root = SafeRoot::open(unsafe_file_data_dir).unwrap()
    assert_true(
      unsafe_file_root.create_exclusive(
        "subagent-audits/unknown.txt",
        "not owner-only",
        permission=0o644,
      )
      is Ok(_),
    )
    unsafe_file_root.close()
    @fs.chmod(unsafe_file_data_dir + "/subagent-audits/unknown.txt", 0o644)
    assert_true(
      native_subagent_audit_inspect_data_dir(
        unsafe_file_data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
    let unsafe_audit_data_dir = fixture + "/unsafe-audit-root"
    native_subagent_audit_inspection_test_store(unsafe_audit_data_dir)
    @fs.chmod(unsafe_audit_data_dir + "/subagent-audits", 0o755)
    assert_true(
      native_subagent_audit_inspect_data_dir(
        unsafe_audit_data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
    let symlink_data_dir = fixture + "/symlink"
    let symlink_target = fixture + "/outside-audits"
    native_subagent_audit_inspection_test_store(
      symlink_data_dir,
      with_audit_directory=false,
    )
    @fs.mkdir(symlink_target, permission=0o700)
    @fs.write_file(symlink_target + "/private.json", "private audit")
    @fs.symlink(symlink_data_dir + "/subagent-audits", target=symlink_target)
    assert_true(
      native_subagent_audit_inspect_data_dir(
        symlink_data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
    let data_dir = fixture + "/bounded"
    native_subagent_audit_inspection_test_store(data_dir)
    let root = SafeRoot::open(data_dir).unwrap()
    for index = 0
        index < NATIVE_SUBAGENT_AUDIT_MAX_ENTRIES + 1
        index = index + 1 {
      assert_true(
        root.create_exclusive(
          "subagent-audits/unknown-" + index.to_string(),
          "counted",
          permission=0o600,
        )
        is Ok(_),
      )
    }
    root.close()
    assert_true(
      native_subagent_audit_inspect_data_dir(
        data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
    let nested_data_dir = fixture + "/nested"
    native_subagent_audit_inspection_test_store(nested_data_dir)
    @fs.mkdir(nested_data_dir + "/subagent-audits/nested", permission=0o700)
    assert_true(
      native_subagent_audit_inspect_data_dir(
        nested_data_dir,
        "parent-audit-session",
        None,
      )
      is Err(_),
    )
  }
}
