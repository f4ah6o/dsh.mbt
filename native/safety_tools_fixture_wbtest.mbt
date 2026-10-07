///|
fn safety_tool_request(name : String, arguments : Json) -> Json {
  Json::object({ "name": Json::string(name), "arguments": arguments })
}

///|
fn safety_tool_ok(result : Json) -> Bool {
  object_field(result, "ok") is Some(Json::True)
}

///|
fn safety_tool_content(result : Json) -> String {
  string_field(result, "content").unwrap_or("")
}

///|
fn safety_tool_error(result : Json) -> String {
  string_field(result, "error").unwrap_or("")
}

///|
fn safety_native_worker_launcher() -> Result[String, String] {
  match @env.get_env_var("DSH_NATIVE_WORKER_BIN") {
    Some(path) if path.has_prefix("/") => Ok(path)
    Some(_) => Err("DSH_NATIVE_WORKER_BIN must be an absolute native CLI path")
    None =>
      Err(
        "process fixtures require DSH_NATIVE_WORKER_BIN pointing to the built native CLI",
      )
  }
}

///|
/// On hosts with a hard worker-memory limit, `grep` exercises POSIX ERE. The
/// fixture covers a shared subset and does not claim JavaScript RegExp parity.
async test "native workspace tools preserve file and process behavior" {
  let fixture = @fs.tmpdir(prefix="dsh-native-tools-fixture")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let root = match SafeRoot::open(workspace) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => root.close())
    let (device, inode) = match root.identity() {
      Ok(value) => value
      Err(error) => fail(error)
    }
    let tools = NativeTools::new(
      root,
      workspace,
      None,
      true,
      match safety_native_worker_launcher() {
        Ok(path) => path
        Err(error) => fail(error)
      },
      device,
      inode,
    )
    let shell_result = tools.execute(
      safety_tool_request(
        "bash",
        Json::object({
          "command": Json::string("printf shell-ok"),
          "timeout": Json::number(3000.0),
        }),
      ),
    )
    assert_true(safety_tool_ok(shell_result))
    assert_eq(safety_tool_content(shell_result), "shell-ok")

    let write_result = tools.execute(
      safety_tool_request(
        "write",
        Json::object({
          "file_path": Json::string("nested/a.txt"),
          "content": Json::string("alpha\nbeta"),
        }),
      ),
    )
    assert_true(safety_tool_ok(write_result))
    let read_result = tools.execute(
      safety_tool_request(
        "read",
        Json::object({ "file_path": Json::string("nested/a.txt") }),
      ),
    )
    assert_true(safety_tool_ok(read_result))
    assert_eq(safety_tool_content(read_result), "1: alpha\n2: beta")

    let edit_result = tools.execute(
      safety_tool_request(
        "edit",
        Json::object({
          "file_path": Json::string("nested/a.txt"),
          "old_string": Json::string("beta"),
          "new_string": Json::string("gamma"),
        }),
      ),
    )
    assert_true(safety_tool_ok(edit_result))
    assert_eq(root.read_text("nested/a.txt").unwrap().0, "alpha\ngamma")

    assert_eq(
      glob_match_bounded("**/*.txt", "a.txt", { steps: 0, }),
      Some(true),
    )
    let glob_result = tools.execute(
      safety_tool_request(
        "glob",
        Json::object({ "pattern": Json::string("**/*.txt") }),
      ),
    )
    assert_true(safety_tool_ok(glob_result))
    assert_eq(safety_tool_content(glob_result), "nested/a.txt")

    // `gamm[ae]` is a POSIX extended regular expression consumed by grep -E.
    // The fixture intentionally does not imply full JS-RegExp compatibility.
    let grep_result = tools.execute(
      safety_tool_request(
        "grep",
        Json::object({
          "pattern": Json::string("gamm[ae]"),
          "path": Json::string("."),
        }),
      ),
    )
    if !os_hard_worker_memory_supported() {
      assert_true(!safety_tool_ok(grep_result))
      assert_eq(
        safety_tool_error(grep_result),
        "grep is disabled because this host cannot enforce a hard worker memory limit",
      )
    } else {
      assert_true(safety_tool_ok(grep_result))
      assert_eq(safety_tool_content(grep_result), "nested/a.txt:2:gamma")
    }

    let bounded_result = tools.execute(
      safety_tool_request(
        "bash",
        Json::object({
          "command": Json::string("yes x | head -c 100000"),
          "timeout": Json::number(5000.0),
        }),
      ),
    )
    assert_true(safety_tool_ok(bounded_result))
    let bounded_output = safety_tool_content(bounded_result)
    assert_true(bounded_output.length() <= TOOL_OUTPUT_LIMIT)
    assert_true(bounded_output.contains("[output truncated]"))

    // The shell leader exits immediately. Its delayed child retains the
    // captured output pipe; the timeout must kill the whole worker session.
    let timeout_result = tools.execute(
      safety_tool_request(
        "bash",
        Json::object({
          "command": Json::string(
            "(sleep 0.7; printf escaped > descendant-alive.txt) & exit 0",
          ),
          "timeout": Json::number(150.0),
        }),
      ),
    )
    assert_true(!safety_tool_ok(timeout_result))
    @async.sleep(900)
    assert_true(!@fs.exists(workspace + "/descendant-alive.txt"))

    // Explicit caller cancellation must finish the same process-group cleanup
    // as timeout cancellation. The child ignores TERM, so only group KILL can
    // prevent its delayed marker from appearing.
    let cancellation_task = group.spawn(
      async fn() {
        tools.execute(
          safety_tool_request(
            "bash",
            Json::object({
              "command": Json::string(
                "printf started > cancel-started.txt; (trap '' TERM; sleep 2; printf escaped > cancel-descendant-alive.txt) & wait",
              ),
              "timeout": Json::number(10000.0),
            }),
          ),
        )
      },
      no_wait=true,
      allow_failure=true,
    )
    let mut cancellation_started = false
    for _ in 0..<100 {
      if @fs.exists(workspace + "/cancel-started.txt") {
        cancellation_started = true
        break
      }
      @async.sleep(10)
    }
    assert_true(cancellation_started)
    cancellation_task.cancel()
    ignore(cancellation_task.wait()) catch {
      @async.WaitedTaskAlreadyCancelled => ()
      _ => ()
    }
    @async.sleep(2300)
    assert_true(!@fs.exists(workspace + "/cancel-descendant-alive.txt"))
  }
}
