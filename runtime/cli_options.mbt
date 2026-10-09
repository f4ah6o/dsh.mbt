///|
fn native_cli_is_value_option(argument : String) -> Bool {
  [
    "--workspace", "--data-dir", "--mcp-config", "--hooks-config", "--lsp-config",
    "--skill-dir", "--mode", "--model", "--base-url", "--port", "--assets-dir", "--max-retries",
    "--host", "--session", "--title", "--threshold-chars", "--head-chars", "--tail-chars",
    "--approve-tools", "--approval-revision", "--run", "--fork", "--import-session",
    "--prune-session", "--approve-call", "--deny-call", "--select-model",
  ].contains(argument)
}

///|
fn native_cli_normalize_args(args : Array[String]) -> Array[String] {
  if args.length() < 2 {
    return args
  }
  let commands = [
    "web", "run", "import-session", "prune-session", "fork-session", "mcp", "acp",
  ]
  let value_options = [
    "--workspace", "--data-dir", "--mcp-config", "--hooks-config", "--lsp-config",
    "--skill-dir", "--mode", "--model", "--base-url", "--port", "--assets-dir", "--max-retries",
    "--host", "--session", "--title", "--threshold-chars", "--head-chars", "--tail-chars",
    "--approve-tools", "--approval-revision", "--run", "--fork", "--import-session",
    "--prune-session", "--approve-call", "--deny-call", "--select-model",
  ]
  let mut command_index = -1
  let mut scan = 1
  while scan < args.length() {
    if value_options.contains(args[scan]) {
      scan += 2
    } else if args[scan] == "--" {
      scan += 1
      if scan < args.length() && commands.contains(args[scan]) {
        command_index = scan
      }
      scan = args.length()
    } else if args[scan].has_prefix("-") {
      scan += 1
    } else {
      if commands.contains(args[scan]) {
        command_index = scan
      }
      scan = args.length()
    }
  }
  if command_index < 0 {
    return args
  }
  let reordered = [args[0], args[command_index]]
  for index = 1; index < args.length(); index = index + 1 {
    if index != command_index {
      reordered.push(args[index])
    }
  }
  let command = reordered[1]
  let normalized = [args[0]]
  let positionals : Array[String] = []
  let trailing_positionals : Array[String] = []
  let mut after_separator = false
  let mut index = 2
  let subcommand_value_options = [
    "--workspace", "--data-dir", "--mcp-config", "--hooks-config", "--lsp-config",
    "--skill-dir", "--mode", "--model", "--base-url", "--port", "--assets-dir", "--max-retries",
    "--host", "--session", "--title", "--threshold-chars", "--head-chars", "--tail-chars",
    "--approve-tools", "--approval-revision",
  ]
  while index < reordered.length() {
    let argument = reordered[index]
    if after_separator {
      trailing_positionals.push(argument)
    } else if argument == "--" {
      after_separator = true
    } else if subcommand_value_options.contains(argument) {
      normalized.push(argument)
      if index + 1 < reordered.length() && !reordered[index + 1].has_prefix("-") {
        normalized.push(reordered[index + 1])
        index += 1
      }
    } else if argument.has_prefix("-") {
      normalized.push(argument)
    } else {
      positionals.push(argument)
    }
    index += 1
  }
  match command {
    "web" => normalized.push("--serve")
    "run" =>
      if (positionals + trailing_positionals).length() > 0 {
        normalized.push("--run")
        normalized.push((positionals + trailing_positionals).join(" "))
      } else if !native_flag(args, "--help") && !native_flag(args, "-h") {
        normalized.push("--run")
        normalized.push("")
      }
    "import-session" => {
      normalized.push("--import-session")
      let all_positionals = positionals + trailing_positionals
      if all_positionals.length() > 0 {
        normalized.push(all_positionals[0])
        for rest_index = 1
            rest_index < positionals.length()
            rest_index = rest_index + 1 {
          normalized.push(positionals[rest_index])
        }
        let first_trailing = if positionals.length() == 0 { 1 } else { 0 }
        if first_trailing < trailing_positionals.length() {
          normalized.push("--")
          for rest_index = first_trailing
              rest_index < trailing_positionals.length()
              rest_index = rest_index + 1 {
            normalized.push(trailing_positionals[rest_index])
          }
        }
      } else if !native_flag(args, "--help") && !native_flag(args, "-h") {
        normalized.push("")
      }
    }
    "prune-session" => {
      normalized.push("--prune-session")
      let all_positionals = positionals + trailing_positionals
      if all_positionals.length() > 0 {
        normalized.push(all_positionals[0])
        for rest_index = 1
            rest_index < positionals.length()
            rest_index = rest_index + 1 {
          normalized.push(positionals[rest_index])
        }
        let first_trailing = if positionals.length() == 0 { 1 } else { 0 }
        if first_trailing < trailing_positionals.length() {
          normalized.push("--")
          for rest_index = first_trailing
              rest_index < trailing_positionals.length()
              rest_index = rest_index + 1 {
            normalized.push(trailing_positionals[rest_index])
          }
        }
      } else if !native_flag(args, "--help") && !native_flag(args, "-h") {
        normalized.push("")
      }
    }
    "fork-session" => {
      normalized.push("--fork")
      let all_positionals = positionals + trailing_positionals
      if all_positionals.length() > 0 {
        normalized.push(all_positionals[0])
        for rest_index = 1
            rest_index < positionals.length()
            rest_index = rest_index + 1 {
          normalized.push(positionals[rest_index])
        }
        let first_trailing = if positionals.length() == 0 { 1 } else { 0 }
        if first_trailing < trailing_positionals.length() {
          normalized.push("--")
          for rest_index = first_trailing
              rest_index < trailing_positionals.length()
              rest_index = rest_index + 1 {
            normalized.push(trailing_positionals[rest_index])
          }
        }
      } else if !native_flag(args, "--help") && !native_flag(args, "-h") {
        normalized.push("")
      }
    }
    "mcp" => normalized.push("--mcp")
    "acp" => normalized.push("--acp")
    _ => ()
  }
  if command == "web" || command == "mcp" || command == "acp" {
    for positional in positionals {
      normalized.push(positional)
    }
    if trailing_positionals.length() > 0 {
      normalized.push("--")
      for positional in trailing_positionals {
        normalized.push(positional)
      }
    }
  }
  normalized
}

///|
fn native_cli_has_unknown_command(args : Array[String]) -> Bool {
  let commands = [
    "web", "run", "import-session", "prune-session", "fork-session", "mcp", "acp",
  ]
  let mut index = 1
  while index < args.length() {
    if args[index] == "--" {
      return index + 1 < args.length() && !commands.contains(args[index + 1])
    }
    if native_cli_is_value_option(args[index]) {
      index += 2
    } else if args[index].has_prefix("-") {
      index += 1
    } else {
      return !commands.contains(args[index])
    }
  }
  false
}

///|
fn native_cli_default_web(args : Array[String]) -> Array[String] {
  if native_cli_has_unknown_command(args) ||
    native_flag(args, "--serve") ||
    native_flag(args, "--mcp") ||
    native_flag(args, "--acp") ||
    native_flag(args, "--demo") ||
    native_flag(args, "--help") ||
    native_flag(args, "-h") ||
    native_option(args, "--run") is Some(_) ||
    native_option(args, "--import-session") is Some(_) ||
    native_option(args, "--prune-session") is Some(_) ||
    native_option(args, "--fork") is Some(_) ||
    native_option(args, "--approve-call") is Some(_) ||
    native_option(args, "--deny-call") is Some(_) ||
    native_flag(args, "--auth-status") ||
    native_flag(args, "--sign-in") ||
    native_flag(args, "--sign-out") ||
    native_flag(args, "--models") ||
    native_option(args, "--select-model") is Some(_) {
    args
  } else {
    args + ["--serve"]
  }
}

///|
fn native_cli_paths(args : Array[String]) -> Result[(String, String), String] {
  let workspace = match native_option(args, "--workspace") {
    Some(value) => value
    None =>
      match @env.current_dir() {
        Some(value) => value
        None => return Err("cannot determine the default workspace directory")
      }
  }
  let data_dir = native_option(args, "--data-dir").unwrap_or(
    workspace + "/.dsh.mbt",
  )
  Ok((data_dir, workspace))
}

///|
/// Reject syntax that the former CLI parser rejected before opening the host.
/// The subcommand aliases have already been normalized to their long options.
fn native_cli_validate_args(args : Array[String]) -> Result[Unit, String] {
  let value_options = [
    "--workspace", "--data-dir", "--mcp-config", "--hooks-config", "--lsp-config",
    "--skill-dir", "--mode", "--model", "--base-url", "--port", "--assets-dir", "--max-retries",
    "--host", "--session", "--title", "--threshold-chars", "--head-chars", "--tail-chars",
    "--approve-tools", "--run", "--fork", "--import-session", "--prune-session",
    "--approve-call", "--deny-call", "--approval-revision", "--select-model",
  ]
  let boolean_options = [
    "--serve", "--mcp", "--acp", "--demo", "--enable-skills", "--allow-shell", "--approve-writes",
    "--json", "--help", "-h", "--auth-status", "--sign-in", "--sign-out", "--models",
  ]
  let positionals : Array[String] = []
  let mut after_separator = false
  let mut index = 1
  while index < args.length() {
    let argument = args[index]
    if after_separator {
      positionals.push(argument)
    } else if argument == "--" {
      after_separator = true
    } else if value_options.contains(argument) {
      if index + 1 >= args.length() ||
        (
          !["--run", "--import-session", "--prune-session", "--fork"].contains(
            argument,
          ) &&
          args[index + 1].has_prefix("-")
        ) {
        return Err("Missing value for " + argument)
      }
      index += 1
    } else if boolean_options.contains(argument) {
      ()
    } else if argument.has_prefix("-") {
      return Err("Unknown option: " + argument)
    } else {
      positionals.push(argument)
    }
    index += 1
  }
  let help = native_flag(args, "--help") || native_flag(args, "-h")
  let is_serve = native_flag(args, "--serve")
  let is_mcp = native_flag(args, "--mcp")
  let is_acp = native_flag(args, "--acp")
  if [is_serve, is_mcp, is_acp].filter(value => value).length() > 1 {
    return Err("choose only one of web, mcp, or acp mode")
  }
  let run = native_option(args, "--run")
  let hooks_config = native_option(args, "--hooks-config")
  let lsp_config = native_option(args, "--lsp-config")
  if hooks_config == Some("") {
    return Err("--hooks-config requires a nonempty path")
  }
  if native_cli_options(args, "--hooks-config").length() > 1 {
    return Err("--hooks-config may only be specified once")
  }
  if lsp_config == Some("") {
    return Err("--lsp-config requires a nonempty path")
  }
  if native_cli_options(args, "--lsp-config").length() > 1 {
    return Err("--lsp-config may only be specified once")
  }
  let imported_path = native_option(args, "--import-session")
  let prune = native_option(args, "--prune-session")
  let fork = native_option(args, "--fork")
  if run is Some("") {
    return Err("run requires a prompt")
  }
  if imported_path is Some("") || prune is Some("") || fork is Some("") {
    return Err("subcommand requires a nonempty argument")
  }
  if native_cli_has_prune_budget(args) && prune is None {
    return Err(
      "Tool-result pruning budget options require the prune-session command",
    )
  }
  if is_serve {
    match native_option(args, "--host") {
      Some(host) if !["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) =>
        return Err("--host only accepts loopback addresses")
      _ => ()
    }
  }
  match native_option(args, "--mode") {
    Some("deepseek" | "openai" | "openai-responses") | None => ()
    Some(_) =>
      return Err("--mode must be deepseek, openai, or openai-responses")
  }
  match native_cli_retry_limit(args) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match native_cli_approved_tools(args, native_flag(args, "--allow-shell")) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if native_cli_options(args, "--skill-dir").length() > 0 &&
    !native_flag(args, "--enable-skills") {
    return Err("--skill-dir requires --enable-skills")
  }
  if prune is Some(_) {
    match native_cli_prune_input(args, prune.unwrap()) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let action_count = [
      run is Some(_),
      imported_path is Some(_),
      prune is Some(_),
      fork is Some(_),
      native_option(args, "--approve-call") is Some(_),
      native_option(args, "--deny-call") is Some(_),
    ]
    .filter(value => value)
    .length()
  let service_count = [is_serve, is_mcp, is_acp].filter(value => value).length()
  if !help && hooks_config is Some(_) && run is None && service_count == 0 {
    return Err("--hooks-config requires run, web, mcp, or acp mode")
  }
  let auth_count = [
      native_flag(args, "--auth-status"),
      native_flag(args, "--sign-in"),
      native_flag(args, "--sign-out"),
      native_flag(args, "--models"),
      native_option(args, "--select-model") is Some(_),
    ]
    .filter(value => value)
    .length()
  if !help && action_count > 1 {
    return Err("choose one CLI action")
  }
  if !help && auth_count > 1 {
    return Err("choose one authentication action")
  }
  if !help && service_count > 0 && (action_count > 0 || auth_count > 0) {
    return Err("web, mcp, and acp modes cannot be combined with CLI actions")
  }
  if !help &&
    native_option(args, "--approve-call") is Some(_) &&
    native_option(args, "--deny-call") is Some(_) {
    return Err("choose either --approve-call or --deny-call")
  }
  if !help &&
    (
      native_option(args, "--approve-call") is Some(_) ||
      native_option(args, "--deny-call") is Some(_)
    ) &&
    (
      native_option(args, "--session") is None ||
      native_option(args, "--approval-revision") is None
    ) {
    return Err(
      "approval decision requires --session, --approval-revision REV, and a call ID",
    )
  }
  if !help &&
    native_option(args, "--approval-revision") is Some(_) &&
    native_option(args, "--approve-call") is None &&
    native_option(args, "--deny-call") is None {
    return Err("--approval-revision requires an approval decision")
  }
  if positionals.length() > 0 && !help {
    if !is_serve &&
      !is_mcp &&
      !is_acp &&
      action_count == 0 &&
      auth_count == 0 &&
      args.length() > 1 &&
      !args[1].has_prefix("-") {
      return Err("Unknown command: " + args[1])
    }
    return Err("Unexpected positional arguments")
  }
  if !help &&
    run is None &&
    imported_path is None &&
    prune is None &&
    fork is None &&
    native_option(args, "--approve-call") is None &&
    native_option(args, "--deny-call") is None &&
    auth_count == 0 &&
    service_count == 0 &&
    !native_flag(args, "--demo") &&
    args.length() > 1 {
    return Err("no native CLI action was selected")
  }
  Ok(())
}

///|
fn native_cli_retry_limit(args : Array[String]) -> Result[Int, String] {
  match native_option(args, "--max-retries") {
    None => Ok(5)
    Some(value) =>
      match service_parse_int(value) {
        Some(retries) if retries >= 0 && retries <= 5 => Ok(retries)
        _ => Err("--max-retries must be an integer between 0 and 5")
      }
  }
}

///|
fn native_cli_is_mcp_tool_name(name : String) -> Bool {
  if !name.has_prefix("mcp__") || name.length() <= 5 || name.length() > 64 {
    return false
  }
  for character in name {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-') {
      return false
    }
  }
  true
}

///|
fn native_cli_approved_tools(
  args : Array[String],
  allow_shell : Bool,
) -> Result[Array[String], String] {
  let approved : Array[String] = []
  if native_flag(args, "--approve-writes") {
    approved.push("write")
    approved.push("edit")
  }
  for index = 0; index + 1 < args.length(); index = index + 1 {
    if args[index] == "--approve-tools" {
      for raw_name in args[index + 1].split(",") {
        let name = raw_name.trim().to_owned()
        if name.is_empty() {
          continue
        }
        if !["write", "edit", "bash", "lsp"].contains(name) &&
          !native_cli_is_mcp_tool_name(name) {
          return Err(
            "--approve-tools accepts write, edit, bash, lsp, or exact mcp__ tool names",
          )
        }
        if !approved.contains(name) {
          approved.push(name)
        }
      }
    }
  }
  if approved.contains("bash") && !allow_shell {
    return Err("--approve-tools bash also requires --allow-shell")
  }
  Ok(approved)
}

///|
fn native_cli_prune_input(
  args : Array[String],
  session_id : String,
) -> Result[Json, String] {
  let fields : Map[String, Json] = { "session_id": session_id.to_json() }
  for
    (argument, field, minimum) in [
      ("--threshold-chars", "threshold_chars", 1),
      ("--head-chars", "head_chars", 0),
      ("--tail-chars", "tail_chars", 0),
    ] {
    match native_option(args, argument) {
      None => ()
      Some(value) => {
        let parsed = match service_parse_int(value) {
          Some(number) if number >= minimum && number <= 262144 => number
          _ =>
            return Err(
              "--" +
              (if field == "threshold_chars" {
                "threshold-chars"
              } else if field == "head_chars" {
                "head-chars"
              } else {
                "tail-chars"
              }) +
              " must be an integer between " +
              minimum.to_string() +
              " and 262144",
            )
        }
        fields[field] = parsed.to_json()
      }
    }
  }
  // The capability supplies defaults for any omitted budget field.
  Ok(Json::object(fields))
}

///|
fn native_cli_has_prune_budget(args : Array[String]) -> Bool {
  native_option(args, "--threshold-chars") is Some(_) ||
  native_option(args, "--head-chars") is Some(_) ||
  native_option(args, "--tail-chars") is Some(_)
}

///|
async fn native_cli_import_action(
  runtime : NativeRuntime,
  path : String,
) -> Result[Json, String] {
  let jsonl = match native_cli_read_session_v4(path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (imported, effects) = match
    runtime.invoke("session_import", { "jsonl": jsonl.to_json() }) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !effects.is_empty() {
    return Err("Session v4 import unexpectedly emitted runtime effects")
  }
  Ok({ "kind": "import-session", "result": imported })
}

///|
async fn native_cli_prune_action(
  runtime : NativeRuntime,
  args : Array[String],
  session_id : String,
) -> Result[Json, String] {
  let input = match native_cli_prune_input(args, session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (result, effects) = match
    runtime.invoke("session_prune_tool_results", input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !effects.is_empty() {
    return Err("tool-result pruning unexpectedly emitted runtime effects")
  }
  Ok({ "kind": "prune-session", "result": result })
}

///|
fn native_cli_approval_revision_number(session : Json) -> Int? {
  match native_cli_approval_revision(session) {
    Json::Number(value, ..) if value >= 0.0 => Some(value.to_int())
    _ => None
  }
}

///|
fn native_cli_auto_approves(
  approved_tools : Array[String],
  session : Json,
) -> Bool {
  let pending = object_field(session, "pending_approval").unwrap_or(
    Json::null(),
  )
  match string_field(pending, "name") {
    Some(name) => approved_tools.contains(name)
    None => false
  }
}

///|
fn native_cli_session_response_text(session : Json) -> String {
  let messages = match object_field(session, "messages") {
    Some(Json::Array(values)) => values
    _ => return ""
  }
  let mut last_user = -1
  for index, message in messages {
    if string_field(message, "role") == Some("user") {
      last_user = index
    }
  }
  let mut response = ""
  for index = last_user + 1; index < messages.length(); index = index + 1 {
    let message = messages[index]
    if string_field(message, "role") == Some("assistant") &&
      !native_json_true(object_field(message, "provisional")) {
      match object_field(message, "content") {
        Some(Json::String(content)) if !content.is_empty() => response = content
        Some(Json::Array(content)) if content.length() > 0 =>
          response = Json::array(content).stringify()
        _ => ()
      }
    }
  }
  response
}

///|
fn native_cli_render(args : Array[String], result : Json) -> String {
  if native_flag(args, "--json") {
    match string_field(result, "kind") {
      Some("run") =>
        object_field(result, "session").unwrap_or(result).stringify()
      Some("import-session") | Some("prune-session") =>
        object_field(result, "result").unwrap_or(result).stringify()
      Some("fork") =>
        object_field(
          object_field(result, "receipt").unwrap_or(Json::null()),
          "result",
        )
        .unwrap_or(result)
        .stringify()
      _ => result.stringify()
    }
  } else {
    match string_field(result, "kind") {
      Some("run") => {
        let session = object_field(result, "session").unwrap_or(Json::null())
        let response = native_cli_session_response_text(session)
        let status = string_field(session, "status").unwrap_or("unknown")
        if !response.is_empty() {
          println(response)
        }
        eprintln(
          "Session " +
          string_field(result, "session_id").unwrap_or("") +
          ": " +
          status,
        )
        ""
      }
      Some("import-session") => {
        let imported = object_field(result, "result").unwrap_or(Json::null())
        "Imported Session v4 as " +
        string_field(imported, "id").unwrap_or("") +
        ": " +
        string_field(imported, "title").unwrap_or("") +
        "\nRead-only history (" +
        string_field(imported, "status").unwrap_or("unknown") +
        "); recorded tools were not executed."
      }
      Some("prune-session") => {
        let pruned = object_field(result, "result").unwrap_or(Json::null())
        let entries = match object_field(pruned, "pruned") {
          Some(Json::Array(values)) => values.length()
          _ => 0
        }
        if entries == 0 {
          "No oversized tool results needed trimming. Full originals remain in session history."
        } else {
          "Trimmed " +
          entries.to_string() +
          " tool results; removed " +
          int_field(pruned, "chars_removed").unwrap_or(0).to_string() +
          " Unicode code points. Full originals remain in session history."
        }
      }
      Some("fork") => {
        let child = object_field(
          object_field(result, "receipt").unwrap_or(Json::null()),
          "result",
        ).unwrap_or(Json::null())
        "Forked " +
        string_field(result, "source_session_id").unwrap_or("") +
        " as " +
        string_field(child, "id").unwrap_or("") +
        ": " +
        string_field(child, "title").unwrap_or("")
      }
      _ => result.stringify()
    }
  }
}

///|
async fn native_cli_read_session_v4(path : String) -> Result[String, String] {
  let path_kind = @fs.kind(path) catch {
    _ => return Err("cannot read Session v4 archive at " + path)
  }
  if path_kind != @fs.Regular {
    return Err("Session v4 archive path must name a regular file")
  }
  let file = @fs.open(path, mode=@fs.ReadOnly) catch {
    _ => return Err("cannot read Session v4 archive at " + path)
  }
  defer file.close()
  if file.kind() != @fs.Regular {
    return Err("Session v4 archive path must name a regular file")
  }
  let size = file.size() catch {
    _ => return Err("cannot determine Session v4 archive size")
  }
  if size < 0L || size > 1048576L {
    return Err("Session v4 archive exceeds the 1 MiB CLI file limit")
  }
  let bytes : Array[Byte] = []
  while file.read_some(max_len=8192) is Some(chunk) {
    for byte in chunk {
      if bytes.length() >= 1048576 {
        return Err("Session v4 archive exceeds the 1 MiB CLI file limit")
      }
      bytes.push(byte)
    }
  }
  let text = @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => return Err("Session v4 archive is not valid UTF-8")
  }
  Ok(text)
}
