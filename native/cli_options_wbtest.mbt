///|
test "native CLI preserves subcommand arguments and bounds retry and approval options" {
  let normalized = native_cli_normalize_args([
    "dsh-native", "run", "Find", "the", "answer", "--demo", "--json",
  ])
  assert_eq(normalized, [
    "dsh-native", "--demo", "--json", "--run", "Find the answer",
  ])
  assert_eq(
    native_cli_normalize_args(["dsh-native", "web", "--port", "3210", "--demo"]),
    ["dsh-native", "--port", "3210", "--demo", "--serve"],
  )
  assert_eq(
    native_cli_normalize_args([
      "dsh-native", "--demo", "run", "Find", "files", "--approve-writes",
    ]),
    ["dsh-native", "--demo", "--approve-writes", "--run", "Find files"],
  )
  assert_eq(native_cli_retry_limit(["dsh-native", "--max-retries", "0"]), Ok(0))
  assert_true(
    native_cli_retry_limit(["dsh-native", "--max-retries", "6"]) is Err(_),
  )
  assert_eq(
    native_cli_approved_tools(
      ["dsh-native", "--approve-writes", "--approve-tools", "edit,write"],
      false,
    ),
    Ok(["write", "edit"]),
  )
  assert_true(
    native_cli_approved_tools(["dsh-native", "--approve-tools", "bash"], false)
    is Err(_),
  )
}

///|
test "native CLI pruning budgets reject invalid bounds" {
  assert_eq(
    native_cli_prune_input(
      ["dsh-native", "--threshold-chars", "8000", "--head-chars", "4000"],
      "session-7",
    ),
    Ok({
      "session_id": "session-7",
      "threshold_chars": 8000,
      "head_chars": 4000,
    }),
  )
  assert_true(
    native_cli_prune_input(
      ["dsh-native", "--threshold-chars", "0"],
      "session-7",
    )
    is Err(_),
  )
  assert_true(
    native_cli_prune_input(
      ["dsh-native", "--tail-chars", "262145"],
      "session-7",
    )
    is Err(_),
  )
}

///|
async test "native CLI imports bounded Session v4 history without replay" {
  let fixture = @fs.tmpdir(prefix="dsh-native-cli-import")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let imported = match
      native_cli_import_action(
        runtime, "tests/fixtures/upstream-tool-call-turn/session.v4.jsonl",
      ) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(string_field(imported, "kind"), Some("import-session"))
    let session = object_field(imported, "result").unwrap()
    let id = string_field(session, "id").unwrap()
    assert_eq(
      string_field(session, "source_format"),
      Some("deepseek-session-v4"),
    )
    assert_true(string_field(session, "status") != Some("running"))
    let loaded = runtime.invoke("session_get", { "session_id": id }).unwrap().0
    assert_eq(
      string_field(loaded, "source_format"),
      Some("deepseek-session-v4"),
    )
    assert_true(@fs.exists(workspace + "/native-demo.txt") == false)
    runtime.close().unwrap()
  }
}

///|
async test "native CLI rejects oversized and nonregular Session v4 paths before reading" {
  let fixture = @fs.tmpdir(prefix="dsh-native-cli-import-bounds")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let oversized = fixture + "/oversized.jsonl"
    let data = @utf8.encode("x".repeat(1048577))
    @fs.write_file(oversized, data)
    assert_true(native_cli_read_session_v4(oversized) is Err(_))

    let fifo = fixture + "/archive.fifo"
    let created = @process.run("mkfifo", [fifo])
    assert_eq(created, 0)
    assert_true(native_cli_read_session_v4(fifo) is Err(_))
  }
}

///|
async test "native CLI explicit write approval completes the demo safely" {
  let fixture = @fs.tmpdir(prefix="dsh-native-cli-approval")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let runtime = match
      NativeRuntime::open(fixture + "/data", workspace, false, true) {
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
    assert_eq(string_field(result, "kind"), Some("run"))
    let session = object_field(result, "session").unwrap()
    assert_eq(string_field(session, "status"), Some("completed"))
    assert_true(@fs.exists(workspace + "/native-demo.txt"))
    runtime.close().unwrap()
  }
}
