///|
/// Windows-only coverage for the native boundary. Tests are gated with
/// #cfg(platform="windows") so POSIX CI neither compiles nor silently skips
/// them; a missing prerequisite fails the test instead of reporting success.

///|
#cfg(platform="windows")
test "windows path helpers accept drive and UNC roots" {
  assert_true(native_path_is_absolute("C:\\work"))
  assert_true(native_path_is_absolute("c:/work"))
  assert_false(native_path_is_absolute("C:"))
  assert_true(native_path_is_absolute("\\\\server\\share"))
  assert_true(native_path_is_absolute("\\\\server\\share\\dir"))
  assert_true(native_path_is_absolute("\\\\?\\C:\\work"))
  assert_true(native_path_is_absolute("\\\\?\\UNC\\server\\share\\dir"))
  assert_false(native_path_is_absolute("C:work"))
  assert_false(native_path_is_absolute("work"))
  assert_false(native_path_is_absolute("\\work"))
  assert_false(native_path_is_absolute("\\\\server"))
  assert_false(native_path_is_absolute(""))
}

///|
#cfg(platform="windows")
test "windows path normalization removes prefixes and unifies separators" {
  assert_eq(native_path_normalize("C:\\work\\a.txt"), "C:/work/a.txt")
  assert_eq(native_path_normalize("C:/work/a.txt"), "C:/work/a.txt")
  assert_eq(native_path_normalize("\\\\?\\C:\\work\\a.txt"), "C:/work/a.txt")
  assert_eq(
    native_path_normalize("\\\\?\\UNC\\server\\share\\a.txt"),
    "//server/share/a.txt",
  )
  assert_eq(native_path_normalize("\\\\server\\share"), "//server/share")
}

///|
#cfg(platform="windows")
async test "windows SafeRoot accepts safe names and rejects traversal" {
  let fixture = @fs.tmpdir(prefix="dsh-windows-saferoot")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let root = fixture + "/workspace"
    @fs.mkdir(root)
    let safe = match SafeRoot::open(root) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => safe.close())
    match safe.restrict_owner_only() {
      Ok(_) => ()
      Err(error) => fail(error)
    }
    assert_true(safe.identity() is Ok(_))

    let shared = match SafeRoot::open(root) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => shared.close())
    match shared.create_exclusive("a.txt", "hello") {
      Ok(_) => ()
      Err(error) => fail(error)
    }
    let (text, version) = match shared.read_text("a.txt") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(text, "hello")
    assert_eq(version.permission(), 0o600)
    assert_eq(version.owner_uid(), os_uid())

    match shared.write_atomic("sub/dir/b.txt", "world", create_parents=true) {
      Ok(_) => ()
      Err(error) => fail(error)
    }
    assert_eq(shared.read_text("sub/dir/b.txt").unwrap().0, "world")

    assert_true(shared.write_atomic("a.txt", "next", expected=version) is Ok(_))
    assert_true(
      shared.write_atomic("a.txt", "stale", expected=version) is Err(_),
    )
    assert_eq(shared.read_text("a.txt").unwrap().0, "next")

    assert_true(shared.read_text("../escape.txt") is Err(_))
    assert_true(shared.read_text("sub/../../escape.txt") is Err(_))
    assert_true(shared.read_text("C:/escape.txt") is Err(_))
    assert_true(shared.read_text("/escape.txt") is Err(_))
    assert_true(shared.write_atomic("bad:stream.txt", "x") is Err(_))
    assert_true(shared.write_atomic("CON.txt", "x") is Err(_))
    assert_true(shared.write_atomic("trailing.", "x") is Err(_))
    assert_true(shared.write_atomic("trailing ", "x") is Err(_))
    assert_true(shared.write_atomic("wild*card.txt", "x") is Err(_))

    let entries = match shared.list_directory(".") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_true(entries.any(entry => entry.0 == "a.txt"))
    assert_true(
      entries.any(entry => entry.0 == "sub" && entry.1 == "directory"),
    )

    match shared.unlink_missing_ok("a.txt") {
      Ok(_) => ()
      Err(error) => fail(error)
    }
    assert_true(shared.read_text("a.txt") is Err(_))
    match shared.unlink_missing_ok("a.txt") {
      Ok(_) => ()
      Err(error) => fail(error)
    }
  }
}

///|
#cfg(platform="windows")
async test "windows SafeRoot rejects junction traversal" {
  let fixture = @fs.tmpdir(prefix="dsh-windows-reparse")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let root = fixture + "/workspace"
    @fs.mkdir(root)
    let real = root + "/real"
    @fs.mkdir(real)
    @fs.write_file(real + "/secret.txt", @utf8.encode("outside"))
    let link = root + "/link"
    // Junctions do not require SeCreateSymbolicLinkPrivilege, so a normal
    // developer account can reproduce the reparse-point attack.
    let status = @process.run("cmd.exe", [
      "/c",
      "mklink",
      "/J",
      link.replace_all(old="/", new="\\"),
      real.replace_all(old="/", new="\\"),
    ])
    if status != 0 {
      fail(
        "junction prerequisite not met: mklink /J exited " + status.to_string(),
      )
    }
    let safe = match SafeRoot::open(root) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => safe.close())
    assert_true(safe.read_text("link/secret.txt") is Err(_))
    assert_true(safe.write_atomic("link/created.txt", "x") is Err(_))
    let entries = match safe.list_directory(".") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_true(!entries.any(entry => entry.0 == "link"))
    // The regular file behind the junction stays readable through its safe
    // name, proving the rejection is about the reparse point, not the content.
    assert_eq(safe.read_text("real/secret.txt").unwrap().0, "outside")
  }
}

///|
#cfg(platform="windows")
async test "windows runtime completes a demo turn and reloads without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-windows-runtime")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    let runtime = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let result = match
      native_cli_action(runtime, [
        "dsh-native", "--run", "create a demo file", "--approve-writes",
      ]) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let session = object_field(result, "session").unwrap()
    let session_id = string_field(session, "id").unwrap()
    assert_eq(string_field(session, "status"), Some("completed"))
    assert_true(@fs.exists(workspace + "/native-demo.txt"))
    runtime.close().unwrap()

    let reopened = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (reloaded, effects) = match
      reopened.invoke("session_get", { "session_id": session_id }) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    // Reload must not replay the approved write or any other effect.
    assert_true(effects.is_empty())
    assert_eq(string_field(reloaded, "status"), Some("completed"))
    reopened.close().unwrap()
  }
}

///|
#cfg(platform="windows")
async test "windows runtime rejects host capabilities without mutation" {
  let fixture = @fs.tmpdir(prefix="dsh-windows-gates")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data = fixture + "/data"
    assert_true(NativeRuntime::open(data, workspace, true, true) is Err(_))
    assert_true(!@fs.exists(data))
    assert_true(
      NativeRuntime::open(
        data,
        workspace,
        false,
        true,
        mcp_config_path=Some(fixture + "/mcp.json"),
      )
      is Err(_),
    )
    assert_true(
      NativeRuntime::open(data, workspace, false, true, enable_subagents=true)
      is Err(_),
    )
    assert_true(!@fs.exists(data))
    // The demo route itself still works after the rejected attempts.
    let runtime = match NativeRuntime::open(data, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    assert_true(runtime.auth.status() is Object(_))
    runtime.close().unwrap()
  }
}
