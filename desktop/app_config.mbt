///|
priv struct DesktopConfig {
  workspace : String
  data_dir : String
  demo : Bool
  allow_shell : Bool
  mode : String
  model : String
  base_url : String
  max_retries : Int32
  mcp_config_path : String?
  hooks_config_path : String?
  hooks_plugin_root : String?
  hooks_project_dir : String?
  hooks_dialect : String
  hooks_model : String
  lsp_config_path : String?
  enable_skills : Bool
  enable_subagents : Bool
  skill_dirs : Array[String]
  smoke : Bool
  offline_e2e : Bool
  frame_output : String
}

///|
priv struct DesktopComposition {
  start : Int32
  replaced : Int32
  preedit : String
  cursor_utf16 : Int32
  send_after_commit : Bool
}

///|
priv struct DesktopState {
  runtime : @runtime.NativeDesktop
  host : Host
  window : @platform.WindowId
  group : @async.TaskGroup[Result[Unit, String]]
  config : DesktopConfig
  mut composition : DesktopComposition?
  mut composition_enabled : Bool
  mut composition_seen : Bool
  mut snapshot : Json
  mut sessions : Array[Json]
  mut selected_id : String
  mut draft : Array[Char]
  mut cursor : Int32
  mut select_all : Bool
  mut status_message : String
  mut error_message : String
  mut scroll_up : Double
  mut focused : Bool
  mut dirty : Bool
  mut done : Bool
  mut signal_requested : Bool
  mut close_requested : Bool
  mut width : Double
  mut height : Double
  mut scale : Double
  mut last_poll : Int64
  mut settings_open : Bool
  mut settings_focus : Int32
  mut settings_scroll : Int32
  mut auth_busy : Bool
  mut auth_error : String
  mut frame_completed_count : Int32
  mut render_count : Int32
  mut click_count : Int32
  mut resize_seen : Bool
  mut resize_armed : Bool
  mut resize_baseline_width : Double
  mut resize_baseline_height : Double
  mut send_seen : Bool
  mut approval_seen : Bool
  mut complete_seen : Bool
}

///|
fn desktop_parse_int(value : String) -> Int32? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for character in value {
    if character < '0' || character > '9' {
      return None
    }
    result = result * 10 + character.to_int() - '0'.to_int()
    if result > 214748364 {
      return None
    }
  }
  Some(result)
}

///|
fn desktop_state(
  runtime : @runtime.NativeDesktop,
  host : Host,
  window : @platform.WindowId,
  group : @async.TaskGroup[Result[Unit, String]],
  config : DesktopConfig,
) -> DesktopState {
  {
    runtime,
    host,
    window,
    group,
    config,
    composition: None,
    composition_enabled: false,
    composition_seen: false,
    snapshot: Json::empty_object(),
    sessions: [],
    selected_id: "",
    draft: [],
    cursor: 0,
    select_all: false,
    status_message: "",
    error_message: "",
    scroll_up: 0.0,
    focused: true,
    dirty: true,
    done: false,
    signal_requested: false,
    close_requested: false,
    width: 1120.0,
    height: 760.0,
    scale: 1.0,
    last_poll: 0L,
    frame_completed_count: 0,
    render_count: 0,
    click_count: 0,
    resize_seen: false,
    resize_armed: false,
    resize_baseline_width: 0.0,
    resize_baseline_height: 0.0,
    settings_open: false,
    settings_focus: 0,
    settings_scroll: 0,
    auth_busy: false,
    auth_error: "",
    send_seen: false,
    approval_seen: false,
    complete_seen: false,
  }
}

///|
fn desktop_argument_value(args : Array[String], name : String) -> String? {
  let mut index = 0
  while index < args.length() {
    if args[index] == name {
      return if index + 1 < args.length() {
        Some(args[index + 1])
      } else {
        None
      }
    }
    index += 1
  }
  None
}

///|
fn desktop_argument_flag(args : Array[String], name : String) -> Bool {
  args.contains(name)
}

///|
fn desktop_argument_values(
  args : Array[String],
  name : String,
) -> Array[String] {
  let values : Array[String] = []
  let mut index = 0
  while index < args.length() {
    if args[index] == name && index + 1 < args.length() {
      values.push(args[index + 1])
      index += 2
    } else {
      index += 1
    }
  }
  values
}

///|
/// Default PPM location for frame evidence. Windows keeps it inside the
/// process temp directory instead of the POSIX `/tmp` path.
fn desktop_default_frame_output() -> String {
  if @runtime.native_os_is_windows() {
    match @env.get_env_var("TEMP") {
      Some(value) if !value.is_empty() => value + "/dsh-desktop-frame.ppm"
      _ => "dsh-desktop-frame.ppm"
    }
  } else {
    "/tmp/dsh-desktop-frame.ppm"
  }
}

///|
fn desktop_parse_config(args : Array[String]) -> Result[DesktopConfig, String] {
  if desktop_argument_flag(args, "--help") || desktop_argument_flag(args, "-h") {
    return Err("help")
  }
  let home = @runtime.native_home_dir()
  let default_workspace = if home != "" {
    home
  } else {
    @env.current_dir().unwrap_or(".")
  }
  let workspace = desktop_argument_value(args, "--workspace").unwrap_or(
    default_workspace,
  )
  let data_dir = desktop_argument_value(args, "--data-dir").unwrap_or(
    workspace + "/.dsh.mbt",
  )
  let max_retries = match desktop_argument_value(args, "--max-retries") {
    None => 5
    Some(value) =>
      match desktop_parse_int(value) {
        Some(number) if number >= 0 && number <= 5 => number
        _ => return Err("--max-retries must be between 0 and 5")
      }
  }
  let offline_e2e = desktop_argument_flag(args, "--offline-e2e") ||
    desktop_argument_flag(args, "--visual-smoke")
  let frame_output = desktop_argument_value(args, "--frame-output").unwrap_or(
    desktop_default_frame_output(),
  )
  let values = [
    "--workspace", "--data-dir", "--mcp-config", "--hooks-config", "--hooks-plugin-root",
    "--hooks-project-dir", "--hooks-dialect", "--hooks-model", "--lsp-config", "--skill-dir",
    "--mode", "--model", "--base-url", "--max-retries", "--frame-output",
  ]
  let flags = [
    "--demo", "--allow-shell", "--enable-skills", "--enable-subagents", "--smoke",
    "--offline-e2e", "--visual-smoke",
  ]
  let mut index = 0
  while index < args.length() {
    let argument = args[index]
    if values.contains(argument) {
      if index + 1 >= args.length() || args[index + 1].has_prefix("--") {
        return Err(argument + " requires a value")
      }
      if args[index + 1].contains("\u0000") {
        return Err(argument + " cannot contain NUL")
      }
      index += 2
    } else if flags.contains(argument) {
      index += 1
    } else {
      return Err("unknown desktop option: " + argument)
    }
  }
  if desktop_argument_values(args, "--skill-dir").length() > 0 &&
    !desktop_argument_flag(args, "--enable-skills") {
    return Err("--skill-dir requires --enable-skills")
  }
  if desktop_argument_values(args, "--skill-dir").length() > 8 {
    return Err("--skill-dir may be specified at most 8 times")
  }
  if desktop_argument_values(args, "--hooks-config").length() > 1 {
    return Err("--hooks-config may only be specified once")
  }
  if desktop_argument_values(args, "--hooks-plugin-root").length() > 1 {
    return Err("--hooks-plugin-root may only be specified once")
  }
  if desktop_argument_values(args, "--hooks-project-dir").length() > 1 {
    return Err("--hooks-project-dir may only be specified once")
  }
  if desktop_argument_values(args, "--hooks-dialect").length() > 1 {
    return Err("--hooks-dialect may only be specified once")
  }
  if desktop_argument_values(args, "--hooks-model").length() > 1 {
    return Err("--hooks-model may only be specified once")
  }
  let hooks_config_path = desktop_argument_value(args, "--hooks-config")
  let hooks_plugin_root = desktop_argument_value(args, "--hooks-plugin-root")
  let hooks_project_dir = desktop_argument_value(args, "--hooks-project-dir")
  let hooks_dialect = desktop_argument_value(args, "--hooks-dialect").unwrap_or(
    "claude-code",
  )
  let hooks_model = desktop_argument_value(args, "--hooks-model").unwrap_or("")
  if hooks_config_path == Some("") {
    return Err("--hooks-config requires a nonempty path")
  }
  for
    (option, value) in [
      ("--hooks-config", hooks_config_path),
      ("--hooks-plugin-root", hooks_plugin_root),
      ("--hooks-project-dir", hooks_project_dir),
    ] {
    match value {
      Some(path) if path.length() > 4096 =>
        return Err(option + " must be at most 4096 characters")
      _ => ()
    }
  }
  match hooks_dialect {
    "claude-code" | "codex" => ()
    _ => return Err("--hooks-dialect must be claude-code or codex")
  }
  if desktop_argument_value(args, "--hooks-dialect") == Some("") ||
    desktop_argument_value(args, "--hooks-model") == Some("") {
    return Err("--hooks-dialect and --hooks-model require a nonempty value")
  }
  if hooks_model != "" && hooks_dialect != "codex" {
    return Err("--hooks-model requires --hooks-dialect codex")
  }
  if (
      desktop_argument_value(args, "--hooks-dialect") is Some(_) ||
      desktop_argument_value(args, "--hooks-model") is Some(_) ||
      hooks_plugin_root is Some(_) ||
      hooks_project_dir is Some(_)
    ) &&
    hooks_config_path is None {
    return Err("hook options require --hooks-config")
  }
  if (hooks_plugin_root is Some(_) || hooks_project_dir is Some(_)) &&
    hooks_dialect == "codex" {
    return Err(
      "--hooks-plugin-root and --hooks-project-dir require --hooks-dialect claude-code",
    )
  }
  if desktop_argument_values(args, "--lsp-config").length() > 1 {
    return Err("--lsp-config may only be specified once")
  }
  if desktop_argument_value(args, "--lsp-config") == Some("") {
    return Err("--lsp-config requires a nonempty path")
  }
  Ok({
    workspace,
    data_dir,
    demo: desktop_argument_flag(args, "--demo") || offline_e2e,
    allow_shell: desktop_argument_flag(args, "--allow-shell"),
    mode: desktop_argument_value(args, "--mode").unwrap_or(""),
    model: desktop_argument_value(args, "--model").unwrap_or(""),
    base_url: desktop_argument_value(args, "--base-url").unwrap_or(""),
    max_retries,
    mcp_config_path: desktop_argument_value(args, "--mcp-config"),
    hooks_config_path,
    hooks_plugin_root,
    hooks_project_dir,
    hooks_dialect,
    hooks_model,
    lsp_config_path: desktop_argument_value(args, "--lsp-config"),
    enable_skills: desktop_argument_flag(args, "--enable-skills"),
    enable_subagents: desktop_argument_flag(args, "--enable-subagents"),
    skill_dirs: desktop_argument_values(args, "--skill-dir"),
    smoke: desktop_argument_flag(args, "--smoke"),
    offline_e2e,
    frame_output,
  })
}

///|
fn desktop_usage() -> String {
  "Usage: dsh-desktop [--workspace PATH] [--data-dir PATH] [--mcp-config PATH] [--hooks-config PATH] [--hooks-plugin-root PATH] [--hooks-project-dir PATH] [--hooks-dialect claude-code|codex] [--hooks-model NAME] [--lsp-config PATH] [--enable-skills] [--enable-subagents] [--skill-dir PATH] [--mode MODE] [--model NAME] [--base-url URL] [--max-retries 0..5] [--allow-shell] [--demo]\n" +
  "       dsh-desktop --smoke [--workspace PATH] [--data-dir PATH]\n" +
  "       dsh-desktop --offline-e2e --workspace PATH --data-dir PATH [--frame-output FILE]\n\n" +
  "A native macOS conversation window backed by dsh's local runtime. Send a prompt, review tool calls, and approve or deny them in the transcript. Use Command-V to paste and Up/Down or PageUp/PageDown to scroll history. Japanese input through system IME composition is available on macOS with DSH_DESKTOP_IME=1; paste works without it."
}

///|
fn desktop_error_text(error : @diagnostics.FrameworkError) -> String {
  error.operation() + ": " + error.code().label()
}
