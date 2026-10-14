///|
async fn native_startup_expect_failure(
  args : Array[String],
  message : String,
  exact~ : Bool = false,
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
  if exact {
    assert_eq(stderr.text(), message)
  } else {
    assert_true(stderr.text().contains(message))
  }
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
    // ACP must not disclose the data directory or recorded lock owner.
    native_startup_expect_failure(
      ["acp", "--demo", "--data-dir", data_dir, "--workspace", workspace],
      "native runtime could not start\n",
      exact=true,
    )
    assert_eq(@fs.read_file(data_dir + "/host.lock").text(), original)
    native_startup_expect_failure(["web", "--port", "65536"], "--port")
    native_startup_expect_failure(["unknown-command"], "Unknown command")
  }
}

///|
async test "Linux unbundled desktop startup gives installation guidance" {
  if native_os_is_linux() {
    native_startup_expect_failure(["desktop"], "no bundled Linux desktop")
  } else if !native_os_is_macos() {
    native_startup_expect_failure(["desktop"], "requires Linux or macOS")
  }
}

///|
async test "Linux desktop validates explicit app paths without browser fallback" {
  if native_os_is_linux() {
    native_startup_expect_failure(
      ["desktop", "--app-path"],
      "requires a nonempty absolute path",
    )
    native_startup_expect_failure(
      ["desktop", "--app-path", "relative-app"],
      "must be an absolute path",
    )
    let fixture = @fs.tmpdir(prefix="dsh-linux-desktop-startup")
    @async.with_task_group() <| group => {
      group.add_defer(() => @fs.rmdir(fixture, recursive=true))
      native_startup_expect_failure(
        ["desktop", "--app-path", fixture + "/missing"],
        "Could not start the Linux desktop executable",
      )
      let app = fixture + "/not-executable"
      @fs.write_file(app, "not an executable", permission=0o600)
      native_startup_expect_failure(
        ["desktop", "--app-path", app],
        "Linux desktop execution was denied",
      )
    }
  }
}

///|
async test "ACP invalid arguments keep stdout empty and stderr sanitized" {
  // A known invalid value reliably exercises argument validation, without
  // depending on how unknown options are handled or opening a data directory.
  native_startup_expect_failure(
    ["acp", "--hooks-dialect", "private-invalid-dialect"],
    "native ACP arguments are invalid\n",
    exact=true,
  )
}

///|
async test "malformed internal worker arguments exit normally on stderr" {
  native_startup_expect_failure(
    ["--internal-worker", "private-worker-argument"],
    "invalid internal worker arguments\n",
    exact=true,
  )
}
