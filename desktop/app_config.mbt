///|
priv struct DesktopConfig {
  workspace : String
  data_dir : String
  demo : Bool
  allow_shell : Bool
  mode : String
  model : String
  base_url : String
  max_retries : Int
  smoke : Bool
  offline_e2e : Bool
  frame_output : String
}

///|
priv struct DesktopState {
  runtime : @runtime.NativeDesktop
  host : @macos.Host
  window : @platform.WindowId
  group : @async.TaskGroup[Result[Unit, String]]
  config : DesktopConfig
  mut snapshot : Json
  mut sessions : Array[Json]
  mut selected_id : String
  mut draft : Array[Char]
  mut cursor : Int
  mut select_all : Bool
  mut status_message : String
  mut error_message : String
  mut scroll_up : Double
  mut focused : Bool
  mut dirty : Bool
  mut done : Bool
  mut close_requested : Bool
  mut width : Double
  mut height : Double
  mut scale : Double
  mut last_poll : Int64
  mut settings_open : Bool
  mut settings_focus : Int
  mut settings_scroll : Int
  mut auth_busy : Bool
  mut auth_error : String
  mut render_count : Int
  mut click_count : Int
  mut resize_seen : Bool
  mut resize_armed : Bool
  mut resize_baseline_width : Double
  mut resize_baseline_height : Double
  mut send_seen : Bool
  mut approval_seen : Bool
  mut complete_seen : Bool
}

///|
fn desktop_parse_int(value : String) -> Int? {
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
  host : @macos.Host,
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
    close_requested: false,
    width: 1120.0,
    height: 760.0,
    scale: 1.0,
    last_poll: 0L,
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
fn desktop_parse_config(args : Array[String]) -> Result[DesktopConfig, String] {
  if desktop_argument_flag(args, "--help") || desktop_argument_flag(args, "-h") {
    return Err("help")
  }
  let home = @env.get_env_var("HOME").unwrap_or("")
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
    "/tmp/dsh-desktop-frame.ppm",
  )
  let values = [
    "--workspace", "--data-dir", "--mode", "--model", "--base-url", "--max-retries",
    "--frame-output",
  ]
  let flags = [
    "--demo", "--allow-shell", "--smoke", "--offline-e2e", "--visual-smoke",
  ]
  let mut index = 0
  while index < args.length() {
    let argument = args[index]
    if values.contains(argument) {
      if index + 1 >= args.length() || args[index + 1].has_prefix("--") {
        return Err(argument + " requires a value")
      }
      index += 2
    } else if flags.contains(argument) {
      index += 1
    } else {
      return Err("unknown desktop option: " + argument)
    }
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
    smoke: desktop_argument_flag(args, "--smoke"),
    offline_e2e,
    frame_output,
  })
}

///|
fn desktop_usage() -> String {
  "Usage: dsh-desktop [--workspace PATH] [--data-dir PATH] [--mode MODE] [--model NAME] [--base-url URL] [--max-retries 0..5] [--allow-shell] [--demo]\n" +
  "       dsh-desktop --smoke [--workspace PATH] [--data-dir PATH]\n" +
  "       dsh-desktop --offline-e2e --workspace PATH --data-dir PATH [--frame-output FILE]\n\n" +
  "A native macOS conversation window backed by dsh's local runtime. Send a prompt, review tool calls, and approve or deny them in the transcript. Use Command-V to paste and Up/Down or PageUp/PageDown to scroll history. Japanese input through system IME composition is not supported by the current GPUI text host; paste works."
}

///|
fn desktop_error_text(error : @diagnostics.FrameworkError) -> String {
  error.operation() + ": " + error.code().label()
}
