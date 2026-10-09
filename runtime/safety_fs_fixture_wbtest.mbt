///|
async test "native SafeRoot rejects symlinks, protects files, and detects conflicts" {
  let fixture = @fs.tmpdir(prefix="dsh-safe-root-fixture")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let outside = fixture + "/outside"
    @fs.mkdir(workspace)
    @fs.mkdir(outside)
    @fs.write_file(outside + "/secret.txt", "outside-secret")
    @fs.symlink(workspace + "/linked-file.txt", target=outside + "/secret.txt")
    @fs.symlink(workspace + "/linked-directory", target=outside)

    let root = match SafeRoot::open(workspace) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => root.close())
    assert_true(root.read_text("linked-file.txt") is Err(_))
    assert_true(root.write_atomic("linked-file.txt", "overwrite") is Err(_))
    assert_true(
      root.write_atomic(
        "linked-directory/escape.txt",
        "escape",
        create_parents=true,
      )
      is Err(_),
    )
    assert_true(!@fs.exists(outside + "/escape.txt"))
    assert_eq(@fs.read_file(outside + "/secret.txt").text(), "outside-secret")

    assert_true(root.restrict_owner_only() is Ok(_))
    assert_true(
      root.write_atomic_protected("credentials.json", "opaque") is Ok(_),
    )
    let (protected_text, version) = match root.read_text("credentials.json") {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_eq(protected_text, "opaque")
    assert_eq(version.permission(), 0o600)
    assert_eq(root.read_protected_text("credentials.json"), Ok(Some("opaque")))
    assert_true(root.read_text("credentials.json", max_bytes=3) is Err(_))
    assert_true(
      root.read_protected_text("credentials.json", max_bytes=3) is Err(_),
    )

    let initial = "first version"
    assert_true(root.write_atomic("conflict.txt", initial) is Ok(_))
    let old_version = match root.read_text("conflict.txt") {
      Ok((_, observed)) => observed
      Err(error) => fail(error)
    }
    @fs.write_file(workspace + "/conflict.txt", "external writer")
    assert_true(
      root.write_atomic("conflict.txt", "stale writer", expected=old_version)
      is Err(_),
    )
    assert_eq(root.read_text("conflict.txt").unwrap().0, "external writer")

    let oversized = "x".repeat(1048577)
    assert_true(root.write_atomic("too-large.txt", oversized) is Err(_))
    assert_true(!@fs.exists(workspace + "/too-large.txt"))
  }
}

///|
async test "native SafeRoot does not follow a swapped nested ancestor" {
  let fixture = @fs.tmpdir(prefix="dsh-safe-root-race")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let outside = fixture + "/attacker"
    @fs.mkdir(workspace)
    @fs.mkdir(workspace + "/nested")
    @fs.mkdir(outside)
    @fs.write_file(outside + "/sentinel.txt", "attacker-sentinel")

    let root = match SafeRoot::open(workspace) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    group.add_defer(() => root.close())

    let swap_script = "cd \"$1\" || exit 2\n" +
      "printf ready > ready\n" +
      "while [ ! -f start ]; do sleep 0.005; done\n" +
      "i=0\n" +
      "while [ ! -f stop ]; do\n" +
      "  mv workspace/nested workspace/detached 2>/dev/null || continue\n" +
      "  printf x >> swaps\n" +
      "  ln -s ../attacker workspace/nested 2>/dev/null || true\n" +
      "  sleep 0.002\n" +
      "  rm -f workspace/nested\n" +
      "  mkdir workspace/nested 2>/dev/null || true\n" +
      "  mv workspace/detached \"attacker/detached-$i\" 2>/dev/null || true\n" +
      "  i=$((i + 1))\n" +
      "done\n"
    let successful_attempts : Array[String] = []
    let write_errors : Array[(String, String)] = []
    let data = "r".repeat(1048576)
    @async.with_task_group() <| workers => {
      let swapper = @process.spawn(
        workers,
        "/bin/sh",
        ["-c", swap_script, "safe-root-race", fixture],
        cwd=fixture,
        extra_env=Map([("PATH", "/bin:/usr/bin")]),
        inherit_env=false,
      )
      let mut swapper_stopped = false
      workers.add_defer(() => {
        @async.protect_from_cancel(() => {
          if !swapper_stopped {
            @fs.write_file(fixture + "/stop", "stop")
            ignore(swapper.wait())
            swapper_stopped = true
          }
        })
      })
      let mut ready = false
      for _ in 0..<100 {
        if @fs.exists(fixture + "/ready") {
          ready = true
          break
        }
        @async.sleep(5)
      }
      assert_true(ready)
      @fs.write_file(fixture + "/start", "start")
      for index in 0..<24 {
        let attempt = "attempt-" + index.to_string() + ".txt"
        let path = "nested/" + attempt
        match root.write_atomic(path, data) {
          Ok(_) => successful_attempts.push(attempt)
          Err(error) => write_errors.push((attempt, error))
        }
      }
      @fs.write_file(fixture + "/stop", "stop")
      ignore(swapper.wait())
      swapper_stopped = true
      assert_true(write_errors.length() > 0)
    }
    // A successful call must leave one complete file in the opened subtree.
    // An error may occur after rename (for example, a parent fsync or a
    // detected concurrent move), so an error may have zero or one complete
    // file. Such a file is an uncertain commit, not an escaped symlink write.
    let found_attempts : Array[(String, String)] = []
    @fs.walk(fixture, (directory, names) => {
      for name in names {
        if name.has_prefix("attempt-") {
          found_attempts.push((name, directory + "/" + name))
        }
      }
    })
    for attempt in successful_attempts {
      let mut matches = 0
      for (name, path) in found_attempts {
        if name == attempt {
          matches += 1
          assert_eq(@fs.read_file(path).text(), data)
        }
      }
      assert_eq(matches, 1)
    }
    for (attempt, error) in write_errors {
      let mut matches = 0
      for (name, path) in found_attempts {
        if name == attempt {
          matches += 1
          assert_eq(@fs.read_file(path).text(), data)
          // The direct attacker directory is reached only through the
          // transient symlink. Files under a moved detached subtree are valid.
          assert_true(path != outside + "/" + attempt)
        }
      }
      if matches > 1 {
        fail(
          "duplicate attempt file after write error: " + attempt + ": " + error,
        )
      }
    }
    for (attempt, path) in found_attempts {
      let mut was_attempted = successful_attempts.contains(attempt)
      for (failed_attempt, _) in write_errors {
        if failed_attempt == attempt {
          was_attempted = true
        }
      }
      assert_true(was_attempted)
      assert_true(path != outside + "/" + attempt)
    }
    assert_eq(
      @fs.read_file(outside + "/sentinel.txt").text(),
      "attacker-sentinel",
    )
    assert_true(@fs.read_file(fixture + "/swaps").text().length() > 0)
  }
}
