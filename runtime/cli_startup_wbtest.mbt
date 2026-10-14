///|
async fn native_startup_expect_failure(
  args : Array[String],
  message : String,
) -> Unit {
  let executable = safety_native_worker_launcher().unwrap()
  let (status, stdout, stderr) = match
    @async.with_timeout_opt(10000, async fn() {
      @process.collect_output(executable, args)
    }) {
    Some(result) => result
    None => fail("CLI startup failure did not exit within 10 seconds")
  }
  // A signal death is not a normal status 1, even if a diagnostic was printed.
  assert_eq(status, 1)
  assert_eq(stdout.text(), "")
  assert_true(stderr.text().contains(message))
}

///|
async test "CLI startup errors exit normally on stderr without changing a live lock" {
  let fixture = @fs.tmpdir(prefix="dsh-cli-startup")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let data_dir = fixture + "/data"
    @fs.mkdir(workspace)
    let store = NativeStore::open(data_dir).unwrap()
    group.add_defer(() => ignore(store.close()))
    let original = @fs.read_file(data_dir + "/host.lock").text()
    for command in ["web", "mcp", "--auth-status"] {
      native_startup_expect_failure(
        [command, "--demo", "--data-dir", data_dir, "--workspace", workspace],
        "--data-dir PATH",
      )
      assert_eq(@fs.read_file(data_dir + "/host.lock").text(), original)
    }
    native_startup_expect_failure(["web", "--port", "65536"], "--port")
    native_startup_expect_failure(["unknown-command"], "Unknown command")
  }
}

///|
async test "non macOS desktop startup rejects the platform before app lookup" {
  if !native_os_is_macos() {
    native_startup_expect_failure(["desktop"], "use dsh web")
    native_startup_expect_failure(
      ["desktop", "--app-path", "/Applications/Dsh.app"],
      "supported only on macOS",
    )
  }
}
