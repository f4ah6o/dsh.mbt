///|
test "desktop launcher consumes app path but preserves argv boundaries" {
  let parsed = native_desktop_parse_launch_args([
    "--demo", "--app-path", "/Applications/Dsh Builds/Dsh.app", "--workspace", "/tmp/work space; still one argument",
    "--", "--provider-flag", "two words",
  ])
  match parsed {
    Ok(options) => {
      assert_eq(options.app_path, Some("/Applications/Dsh Builds/Dsh.app"))
      assert_eq(options.app_args, [
        "--demo", "--workspace", "/tmp/work space; still one argument", "--provider-flag",
        "two words",
      ])
      assert_eq(
        native_desktop_open_arguments(
          "/Applications/Dsh Builds/Dsh.app",
          options.app_args,
        ),
        [
          "-n", "-a", "/Applications/Dsh Builds/Dsh.app", "--args", "--demo", "--workspace",
          "/tmp/work space; still one argument", "--provider-flag", "two words",
        ],
      )
    }
    Err(error) => fail(error)
  }
}

///|
test "desktop launcher rejects missing, relative, repeated and NUL app paths" {
  assert_true(native_desktop_parse_launch_args(["--app-path"]) is Err(_))
  assert_true(
    native_desktop_parse_launch_args(["--app-path", "Applications/Dsh.app"])
    is Err(_),
  )
  assert_true(
    native_desktop_parse_launch_args([
      "--app-path", "/Applications/Dsh.app", "--app-path", "/tmp/Other.app",
    ])
    is Err(_),
  )
  assert_true(
    native_desktop_parse_launch_args(["--mode", "unsafe\u0000value"]) is Err(_),
  )
}

///|
test "desktop app lookup is absolute and checks system then user install paths" {
  let candidates = native_desktop_default_app_paths(Some("/Users/ada"))
  assert_eq(candidates, [
    "/Applications/Dsh.app", "/Users/ada/Applications/Dsh.app",
  ])
  assert_eq(native_desktop_default_app_paths(Some("relative-home")), [
    "/Applications/Dsh.app",
  ])
  assert_eq(
    native_desktop_select_app_path(None, candidates, [
      None,
      Some("/Users/ada/Applications/Dsh.app"),
    ]),
    Ok("/Users/ada/Applications/Dsh.app"),
  )
  assert_eq(
    native_desktop_select_app_path(None, candidates, [
      Some("/Applications/Dsh.app"),
      Some("/Users/ada/Applications/Dsh.app"),
    ]),
    Ok("/Applications/Dsh.app"),
  )
  assert_true(
    native_desktop_select_app_path(Some("/tmp/missing.app"), candidates, [
      Some("/Applications/Dsh.app"),
      None,
    ])
    is Err(_),
  )
}

///|
async test "desktop resolver finds a user-installed app after an absent system app" {
  let fixture = @fs.tmpdir(prefix="dsh-desktop-app-lookup")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let system_app = fixture + "/system/Applications/Dsh.app"
    let user_app = fixture + "/home/Applications/Dsh.app"
    @fs.mkdir(user_app + "/Contents/MacOS", recursive=true)
    @fs.mkdir(user_app + "/Contents/Helpers", recursive=true)
    @fs.mkdir(user_app + "/Contents/Frameworks", recursive=true)
    @fs.write_file(user_app + "/Contents/Info.plist", "fixture")
    @fs.write_file(
      user_app + "/Contents/MacOS/dsh-desktop",
      "fixture executable",
      permission=0o755,
    )
    @fs.write_file(
      user_app + "/Contents/Helpers/dsh",
      "fixture helper",
      permission=0o755,
    )
    @fs.write_file(
      user_app + "/Contents/Frameworks/libgpui_macos.dylib",
      "fixture dylib",
    )
    let resolved = native_desktop_resolve_candidates(None, [
      system_app, user_app,
    ])
    let expected = @fs.realpath(user_app) catch {
      _ => fail("could not canonicalize desktop lookup fixture")
    }
    assert_eq(resolved, Ok(expected))
  }
}
