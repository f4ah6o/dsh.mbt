///|
async test "auto archive storage quota refusal runs no prompt hook" {
  let fixture = @fs.tmpdir(prefix="dsh-native-auto-archive-storage-quota")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let marker = workspace + "/hook-count.txt"
    let hooks_path = fixture + "/hooks.json"
    let hook = "cat >/dev/null; printf x >> \"${CLAUDE_PROJECT_DIR}/hook-count.txt\"; printf '{}'"
    @fs.write_file(
      hooks_path,
      @utf8.encode(native_hook_test_config("UserPromptSubmit", "*", hook)),
    )
    let runtime = NativeRuntime::open(
      fixture + "/data",
      workspace,
      false,
      true,
      hooks_config_path=Some(hooks_path),
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let original = "capacity".repeat(1000)
    let (seed, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
      original,
    )
    runtime.api.restore(seed.snapshot()).unwrap()
    runtime.checkpoint_locked().unwrap()
    let object = NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan, original, projection, threshold, head, tail,
    ).unwrap()
    let object_bytes = @utf8.encode(object.encoded_object()).length().to_int64()
    let padding_bytes = NATIVE_ARCHIVE_STORAGE_QUOTA - object_bytes * 2L + 1L
    @fs.write_file(
      runtime.store.archive_root.path() + "/quota-padding",
      @utf8.encode("p".repeat(padding_bytes.to_int())),
      permission=0o600,
    )
    let inventory = runtime.store.archive_inventory().unwrap()
    assert_eq(inventory.1, 1)
    assert_true(inventory.0 < NATIVE_ARCHIVE_STORAGE_QUOTA)
    let before = runtime.api.snapshot()
    let command_id = native_command_id().unwrap()
    let command = native_runtime_session_operation_command(
      runtime.state.workspace_id,
      "archive-codec",
      command_id,
      "session_send",
      {
        "prompt": "This send must fail quota admission before hooks",
        "auto_prune_tool_results": true,
      },
    )
    let identity = runtime.state.identity_key
    let (receipt, effects, started, control) = runtime
      .accept_remote_command(command, identity)
      .unwrap()
    assert_eq(string_field(receipt, "status"), Some("rejected"))
    assert_true(string_field(receipt, "error").unwrap_or("").contains("quota"))
    assert_true(effects.is_empty())
    assert_false(started)
    assert_true(control is None)
    assert_eq(runtime.api.snapshot(), before)
    assert_true(runtime.api.take_typed_effects().is_empty())
    assert_eq(runtime.state.archive_objects.length(), 0)
    assert_eq(runtime.store.archive_inventory().unwrap(), inventory)
    assert_false(@fs.exists(marker))
    assert_true(runtime.scheduler.active.get("archive-codec") is None)
  }
}
