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
  let skill_args = native_cli_normalize_args([
    "dsh-native", "run", "Use a skill", "--enable-skills", "--skill-dir", "tools/skills",
    "--skill-dir", "extra/skills",
  ])
  assert_eq(skill_args, [
    "dsh-native", "--enable-skills", "--skill-dir", "tools/skills", "--skill-dir",
    "extra/skills", "--run", "Use a skill",
  ])
  assert_eq(native_cli_options(skill_args, "--skill-dir"), [
    "tools/skills", "extra/skills",
  ])
  assert_true(
    native_cli_validate_args([
      "dsh-native", "--skill-dir", "tools/skills", "--run", "Use a skill",
    ])
    is Err(_),
  )
  assert_true(native_cli_validate_args(skill_args) is Ok(_))
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
async test "native CLI product imports the pinned Session v4 catalog inertly and restores it" {
  let fixture = @fs.tmpdir(prefix="dsh-native-cli-v4-catalog")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let current_dir = @env.current_dir().unwrap_or_else(() => {
      fail("cannot resolve test checkout")
    })
    let catalog = current_dir + "/tests/fixtures/upstream-session-v4"
    let archives : Array[String] = []
    @fs.walk(catalog, (directory, names) => {
      if !directory.contains("/provider-retry") {
        for name in names {
          if name == "session.v4.jsonl" {
            archives.push(directory + "/" + name)
          }
        }
      }
    })
    assert_eq(archives.length(), 25)

    let data_dir = fixture + "/data"
    let runtime = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let imported_ids : Array[(String, String)] = []
    for archive_path in archives {
      let archive = @fs.read_file(archive_path).text()
      let (imported, effects) = match
        runtime.invoke("session_import", { "jsonl": archive.to_json() }) {
        Ok(value) => value
        Err(error) => fail(archive_path + ": " + error)
      }
      assert_true(effects.is_empty())
      assert_eq(
        string_field(imported, "source_format"),
        Some("deepseek-session-v4"),
      )
      let status = string_field(imported, "status").unwrap_or("")
      assert_true(status != "running")
      imported_ids.push((string_field(imported, "id").unwrap(), status))
    }
    assert_eq(imported_ids.length(), 25)
    runtime.close().unwrap()

    let restored = match NativeRuntime::open(data_dir, workspace, false, true) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(restored.close()))
    })
    for (session_id, status) in imported_ids {
      let (session, effects) = restored
        .invoke("session_get", { "session_id": session_id.to_json() })
        .unwrap()
      assert_true(effects.is_empty())
      assert_eq(
        string_field(session, "source_format"),
        Some("deepseek-session-v4"),
      )
      assert_eq(string_field(session, "status"), Some(status))
    }
    restored.close().unwrap()
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

///|
async test "native CLI cancels a pending approval when stdin is noninteractive" {
  let fixture = @fs.tmpdir(prefix="dsh-native-cli-noninteractive-approval")
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
    let session_id = "noninteractive-approval-session"
    let (_, create_effects) = runtime
      .invoke("session_create", { "id": session_id, "title": "Approval" })
      .unwrap()
    assert_true(create_effects.is_empty())
    let result = native_cli_action(runtime, [
      "dsh-native", "--run", "create a demo file", "--session", session_id,
    ])
    assert_true(result is Err(_))
    assert_true(!@fs.exists(workspace + "/native-demo.txt"))
    let (session, effects) = runtime
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(effects.is_empty())
    assert_eq(string_field(session, "status"), Some("cancelled"))
    runtime.close().unwrap()
  }
}
