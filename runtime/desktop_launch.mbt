///|
priv struct NativeDesktopLaunchOptions {
  app_path : String?
  app_args : Array[String]
}

///|
fn native_desktop_parse_launch_args(
  args : Array[String],
) -> Result[NativeDesktopLaunchOptions, String] {
  let mut app_path : String? = None
  let app_args : Array[String] = []
  let mut after_separator = false
  let mut index = 0
  while index < args.length() {
    let argument = args[index]
    if argument.contains("\u0000") {
      return Err("desktop arguments cannot contain NUL")
    }
    if after_separator {
      app_args.push(argument)
    } else if argument == "--" {
      after_separator = true
    } else if argument == "--app-path" {
      if app_path is Some(_) {
        return Err("--app-path may only be specified once")
      }
      if index + 1 >= args.length() || args[index + 1] == "" {
        return Err("--app-path requires a nonempty absolute path")
      }
      let value = args[index + 1]
      if value.contains("\u0000") || !value.has_prefix("/") {
        return Err("--app-path must be an absolute path")
      }
      app_path = Some(value)
      index += 1
    } else {
      app_args.push(argument)
    }
    index += 1
  }
  Ok({ app_path, app_args, })
}

///|
fn native_desktop_default_app_paths(home : String?) -> Array[String] {
  let paths = ["/Applications/Dsh.app"]
  match home {
    Some(path) if path.has_prefix("/") =>
      paths.push(path + "/Applications/Dsh.app")
    _ => ()
  }
  paths
}

///|
fn native_desktop_select_app_path(
  explicit_path : String?,
  candidates : Array[String],
  canonical_paths : Array[String?],
) -> Result[String, String] {
  let mut index = 0
  for candidate in candidates {
    let selected = match canonical_paths[index] {
      Some(path) if explicit_path is None || explicit_path == Some(candidate) =>
        Some(path)
      _ => None
    }
    match selected {
      Some(path) => return Ok(path)
      None => ()
    }
    index += 1
  }
  match explicit_path {
    Some(_) => Err("--app-path does not point to a complete Dsh.app bundle")
    None =>
      Err(
        "Dsh.app was not found in /Applications or ~/Applications; install it there or pass --app-path /absolute/path/to/Dsh.app",
      )
  }
}

///|
fn native_desktop_open_arguments(
  app_path : String,
  app_args : Array[String],
) -> Array[String] {
  let arguments = ["-n", "-a", app_path]
  if app_args.length() > 0 {
    arguments.push("--args")
    for argument in app_args {
      arguments.push(argument)
    }
  }
  arguments
}

///|
async fn native_desktop_complete_bundle(path : String) -> Bool {
  @fs.exists(path + "/Contents/Info.plist") &&
  @fs.can_execute(path + "/Contents/MacOS/dsh-desktop") &&
  @fs.can_execute(path + "/Contents/Helpers/dsh") &&
  @fs.exists(path + "/Contents/Frameworks/libgpui_macos.dylib")
}

///|
async fn native_desktop_canonical_bundle(path : String) -> String? {
  let canonical = @fs.realpath(path) catch { _ => "" }
  if canonical != "" && native_desktop_complete_bundle(canonical) {
    Some(canonical)
  } else {
    None
  }
}

///|
async fn native_desktop_resolve_app_path(
  explicit_path : String?,
  home : String?,
) -> Result[String, String] {
  match explicit_path {
    Some(path) if !path.has_prefix("/") =>
      return Err("--app-path must be an absolute path")
    _ => ()
  }
  let candidates = match explicit_path {
    Some(path) => [path]
    None => native_desktop_default_app_paths(home)
  }
  native_desktop_resolve_candidates(explicit_path, candidates)
}

///|
async fn native_desktop_resolve_candidates(
  explicit_path : String?,
  candidates : Array[String],
) -> Result[String, String] {
  let canonical_paths : Array[String?] = []
  for candidate in candidates {
    canonical_paths.push(native_desktop_canonical_bundle(candidate))
  }
  native_desktop_select_app_path(explicit_path, candidates, canonical_paths)
}

///|
async fn native_desktop_launch(args : Array[String]) -> Result[Unit, String] {
  if !@fs.can_execute("/usr/bin/open") {
    return Err("dsh desktop requires macOS LaunchServices (/usr/bin/open)")
  }
  let options = match native_desktop_parse_launch_args(args) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let home = @env.get_env_var("HOME")
  let app_path = match native_desktop_resolve_app_path(options.app_path, home) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let open_args = native_desktop_open_arguments(app_path, options.app_args)
  let status = @process.run("/usr/bin/open", open_args) catch {
    _ => return Err("macOS LaunchServices could not be started")
  }
  if status == 0 {
    Ok(())
  } else {
    Err("LaunchServices failed to open Dsh.app (exit status \{status})")
  }
}
