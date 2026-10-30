///|
// Keep this regression in its own native test process. The C implementation's
// staging-name serial is process-global, and this fixture fills a known range.
async test "SafeRoot atomically creates complete immutable files without replacement" {
  let fixture = @fs.tmpdir(prefix="dsh-safe-root-atomic-create")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let outside = fixture + "/outside"
    @fs.mkdir(workspace)
    @fs.mkdir(outside)
    @fs.symlink(workspace + "/linked-directory", target=outside)
    let root = match @runtime.SafeRoot::open(workspace) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => root.close())

    assert_true(
      root.create_atomic_no_replace("linked-directory/escape.txt", "escape", 32)
      is Err(_),
    )
    assert_true(!@fs.exists(outside + "/escape.txt"))

    match root.create_atomic_no_replace("serial-seed.bin", "seed", 8) {
      Ok(_) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Failed(error)) => fail(error)
      Err(@runtime.AtomicCreateNoReplaceError::Exists) =>
        fail("unexpected existing file")
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
    }
    let process_id = @runtime.os_pid().to_string()
    let leaf_collision = ".DSH-" + process_id + "-2.TMP"
    match root.create_atomic_no_replace(leaf_collision, "target", 16) {
      Ok(_) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Failed(error)) => fail(error)
      Err(@runtime.AtomicCreateNoReplaceError::Exists) =>
        fail("unexpected existing file")
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
    }
    assert_eq(@fs.read_file(workspace + "/" + leaf_collision).text(), "target")

    let temp_collision = ".dsh-" + process_id + "-3.tmp"
    @fs.write_file(workspace + "/" + temp_collision, "keep")
    let complete = "immutable-" + "x".repeat(1048576)
    match
      root.create_atomic_no_replace("archive.bin", complete, complete.length()) {
      Ok(_) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Failed(error)) => fail(error)
      Err(@runtime.AtomicCreateNoReplaceError::Exists) =>
        fail("unexpected existing file")
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
    }
    let (stored, version) = match
      root.read_text("archive.bin", max_bytes=complete.length()) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(stored, complete)
    assert_eq(version.permission(), 0o600)
    assert_true(root.file_version("archive.bin").unwrap().same(version))

    match root.create_atomic_no_replace("archive.bin", "replacement", 64) {
      Err(@runtime.AtomicCreateNoReplaceError::Exists) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Failed(error)) => fail(error)
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
      Ok(_) => fail("atomic no-replace create replaced an existing file")
    }
    assert_eq(
      root.read_text("archive.bin", max_bytes=complete.length()).unwrap().0,
      complete,
    )

    match root.create_atomic_no_replace("too-large.bin", "éé", 3) {
      Err(@runtime.AtomicCreateNoReplaceError::Failed(_)) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Exists) =>
        fail("unexpected existing file")
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
      Ok(_) => fail("atomic create accepted content over its UTF-8 byte limit")
    }
    assert_true(!@fs.exists(workspace + "/too-large.bin"))
    assert_eq(@fs.read_file(workspace + "/" + temp_collision).text(), "keep")
    assert_false(@fs.exists(workspace + "/..dsh-" + process_id + "-2.tmp"))
    assert_false(@fs.exists(workspace + "/.dsh-" + process_id + "-4.tmp"))
    assert_false(@fs.exists(workspace + "/.dsh-" + process_id + "-5.tmp"))

    for index = 6; index <= 37; index = index + 1 {
      let candidate = ".dsh-" + process_id + "-" + index.to_string() + ".tmp"
      @fs.write_file(workspace + "/" + candidate, "collision")
    }
    match root.create_atomic_no_replace("exhausted.bin", "content", 16) {
      Err(@runtime.AtomicCreateNoReplaceError::Failed(_)) => ()
      Err(@runtime.AtomicCreateNoReplaceError::Exists) =>
        fail(
          "temporary-name exhaustion was reported as a destination collision",
        )
      Err(@runtime.AtomicCreateNoReplaceError::OutcomeUnknown(error)) =>
        fail(error)
      Ok(_) => fail("atomic create succeeded without a temporary name")
    }
    assert_true(!@fs.exists(workspace + "/exhausted.bin"))
  }
}
