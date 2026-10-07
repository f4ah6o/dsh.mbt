///|
const TOOL_OUTPUT_LIMIT : Int = 65536

///|
const TOOL_FILE_LIMIT : Int = 4194304

///|
const TOOL_MAX_VISITED : Int = 10000

///|
const TOOL_GLOB_MATCH_STEPS : Int = 20000000

///|
struct ToolWalkBudget {
  mut visited : Int
  mut truncated : Bool
  files : Array[String]
}

///|
struct GlobMatchBudget {
  mut steps : Int
}

///|
fn bounded_tool_text(text : String) -> String {
  let bytes = @utf8.encode(text)
  if bytes.length() <= TOOL_OUTPUT_LIMIT {
    return text
  }
  let suffix = "\n[output truncated]"
  let decoder = Utf8StreamDecoder::new()
  let prefix = match decoder.feed(bytes[:TOOL_OUTPUT_LIMIT - suffix.length()]) {
    Ok(value) => value
    Err(_) => ""
  }
  ignore(decoder.finish())
  prefix + suffix
}

///|
fn tool_error(error : String) -> Json {
  { "ok": false, "error": bounded_tool_text(error) }
}

///|
fn tool_success(content : String) -> Json {
  { "ok": true, "content": bounded_tool_text(content) }
}

///|
fn tool_arg_string(
  args : Json,
  name : String,
  maximum? : Int = TOOL_FILE_LIMIT,
) -> Result[String, String] {
  match string_field(args, name) {
    Some(value) if value.length() <= maximum => Ok(value)
    Some(_) => Err(name + " exceeds the input limit")
    None => Err(name + " must be a string")
  }
}

///|
fn tool_arg_int(
  args : Json,
  name : String,
  fallback : Int,
  minimum : Int,
  maximum : Int,
) -> Result[Int, String] {
  match object_field(args, name) {
    None => Ok(fallback)
    Some(Json::Number(value, ..)) if value >= minimum.to_double() &&
      value <= maximum.to_double() &&
      value.to_int().to_double() == value => Ok(value.to_int())
    _ =>
      Err(
        name +
        " must be an integer between " +
        minimum.to_string() +
        " and " +
        maximum.to_string(),
      )
  }
}

///|
fn tool_arg_bool(
  args : Json,
  name : String,
  fallback : Bool,
) -> Result[Bool, String] {
  match object_field(args, name) {
    None => Ok(fallback)
    Some(Json::True) => Ok(true)
    Some(Json::False) => Ok(false)
    _ => Err(name + " must be a boolean")
  }
}

///|
fn NativeTools::resolve_path(
  self : NativeTools,
  value : String,
  allow_root? : Bool = false,
) -> Result[String, String] {
  if value.length() > 4096 ||
    value.contains("\u0000") ||
    value.has_prefix("/") ||
    value.has_prefix("\\") {
    return Err("Path must be relative to the workspace")
  }
  let parts : Array[String] = []
  for part in value.split("/") {
    if part == ".." {
      return Err("Path escapes the workspace")
    }
    if part != "" && part != "." {
      if part.contains("\\") {
        return Err("Backslashes are not valid workspace path separators")
      }
      parts.push(part.to_owned())
    }
  }
  let normalized = parts.join("/")
  if normalized.is_empty() && !allow_root {
    return Err("Workspace root is not a file")
  }
  if self.blocked_path is Some(blocked) &&
    (normalized == blocked || normalized.has_prefix(blocked + "/")) {
    return Err("Host data is not accessible through workspace tools")
  }
  Ok(if normalized.is_empty() { "." } else { normalized })
}

///|
struct NativeTools {
  root : SafeRoot
  workspace : String
  blocked_path : String?
  allow_shell : Bool
  worker_launcher : String
  workspace_device : Int64
  workspace_inode : Int64
}

///|
fn NativeTools::new(
  root : SafeRoot,
  workspace : String,
  blocked_path : String?,
  allow_shell : Bool,
  worker_launcher : String,
  workspace_device : Int64,
  workspace_inode : Int64,
) -> NativeTools {
  {
    root,
    workspace,
    blocked_path,
    allow_shell,
    worker_launcher,
    workspace_device,
    workspace_inode,
  }
}

///|
fn NativeTools::walk(
  self : NativeTools,
  start : String,
  depth : Int,
  budget : ToolWalkBudget,
) -> Unit {
  if depth > 32 || budget.visited >= TOOL_MAX_VISITED {
    budget.truncated = true
    return
  }
  match self.root.list_directory(start) {
    Err(_) => ()
    Ok(entries) =>
      for (name, kind) in entries {
        if budget.visited >= TOOL_MAX_VISITED {
          budget.truncated = true
          break
        }
        budget.visited += 1
        let path = if start == "." { name } else { start + "/" + name }
        if self.blocked_path is Some(blocked) &&
          (path == blocked || path.has_prefix(blocked + "/")) {
          continue
        }
        match kind {
          "directory" => self.walk(path, depth + 1, budget)
          "file" => budget.files.push(path)
          _ => ()
        }
      }
  }
}

///|
async fn NativeTools::execute(self : NativeTools, request : Json) -> Json {
  let name = string_field(request, "name").unwrap_or("")
  let args = match string_field(request, "arguments") {
    Some(raw) =>
      match parse_json(raw) {
        Ok(value) => value
        Err(_) => return tool_error("Tool arguments are not valid JSON")
      }
    None =>
      match object_field(request, "arguments") {
        Some(value) => value
        None => return tool_error("Tool arguments are missing")
      }
  }
  let is_object = match args {
    Json::Object(_) => true
    _ => false
  }
  if !is_object {
    return tool_error("Tool arguments must be an object")
  }
  match name {
    "read" => self.read_tool(args)
    "write" => self.write_tool(args)
    "edit" => self.edit_tool(args)
    "glob" => self.glob_tool(args)
    "grep" => self.grep_tool(args)
    "bash" => self.bash_tool(args)
    _ => tool_error("Unknown tool: " + name)
  }
}

///|
fn NativeTools::read_tool(self : NativeTools, args : Json) -> Json {
  let input = match tool_arg_string(args, "file_path", maximum=4096) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let path = match self.resolve_path(input) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let (offset, limit) = match
    (
      tool_arg_int(args, "offset", 1, 1, 1000000),
      tool_arg_int(args, "limit", 200, 1, 2000),
    ) {
    (Ok(offset), Ok(limit)) => (offset, limit)
    (Err(error), _) | (_, Err(error)) => return tool_error(error)
  }
  match self.root.read_text(path, max_bytes=TOOL_FILE_LIMIT) {
    Err(error) => tool_error(error)
    Ok((text, _)) => {
      let lines = text.split("\n").to_array()
      let start = Int::min(offset - 1, lines.length())
      let stop = Int::min(start + limit, lines.length())
      let output : Array[String] = []
      for index = start; index < stop; index = index + 1 {
        output.push((index + 1).to_string() + ": " + lines[index].to_owned())
      }
      if stop < lines.length() {
        output.push("[" + (lines.length() - stop).to_string() + " more lines]")
      }
      tool_success(output.join("\n"))
    }
  }
}

///|
fn NativeTools::write_tool(self : NativeTools, args : Json) -> Json {
  let (file_path, content) = match
    (
      tool_arg_string(args, "file_path", maximum=4096),
      tool_arg_string(args, "content", maximum=1048576),
    ) {
    (Ok(path), Ok(content)) => (path, content)
    (Err(error), _) | (_, Err(error)) => return tool_error(error)
  }
  let path = match self.resolve_path(file_path) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  match self.root.write_atomic(path, content, create_parents=true) {
    Err(error) => tool_error(error)
    Ok(_) =>
      tool_success(
        "Wrote " +
        @utf8.encode(content).length().to_string() +
        " bytes to " +
        path +
        ".",
      )
  }
}

///|

///|
fn NativeTools::edit_tool(self : NativeTools, args : Json) -> Json {
  let file_path = match tool_arg_string(args, "file_path", maximum=4096) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let old_string = match tool_arg_string(args, "old_string") {
    Ok(value) if !value.is_empty() => value
    Ok(_) => return tool_error("old_string must not be empty")
    Err(error) => return tool_error(error)
  }
  let new_string = match tool_arg_string(args, "new_string") {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let replace_all = match tool_arg_bool(args, "replace_all", false) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let path = match self.resolve_path(file_path) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  match self.root.read_text(path, max_bytes=TOOL_FILE_LIMIT) {
    Err(error) => tool_error(error)
    Ok((text, version)) => {
      let parts = text.split(old_string).to_array()
      let count = parts.length() - 1
      if count == 0 {
        return tool_error("old_string was not found")
      }
      if count > 1 && !replace_all {
        return tool_error(
          "old_string is ambiguous; provide more context or set replace_all",
        )
      }
      let updated = if replace_all {
        parts.map(part => part.to_owned()).join(new_string)
      } else {
        parts[0].to_owned() + new_string + parts[1].to_owned()
      }
      match self.root.write_atomic(path, updated, expected=version) {
        Err(error) => tool_error(error)
        Ok(_) =>
          tool_success(
            "Replaced " +
            (if replace_all { count } else { 1 }).to_string() +
            " occurrence(s) in " +
            path +
            ".",
          )
      }
    }
  }
}

///|
fn glob_epsilon(pattern : Array[Char], states : FixedArray[Bool]) -> Unit {
  let mut index = 0
  while index < pattern.length() {
    if states[index] && pattern[index] == '*' {
      if index + 1 < pattern.length() && pattern[index + 1] == '*' {
        states[index + 2] = true
        if index + 2 < pattern.length() && pattern[index + 2] == '/' {
          // A leading recursive directory segment may match zero components.
          states[index + 3] = true
        }
      } else {
        states[index + 1] = true
      }
    }
    index += 1
  }
}

///|
fn glob_match_bounded(
  pattern : String,
  path : String,
  budget : GlobMatchBudget,
) -> Bool? {
  let p = pattern.to_array()
  let s = path.to_array()
  if p.length() > 1024 || s.length() > 8192 {
    return None
  }
  let mut states = FixedArray::make(p.length() + 1, false)
  let mut next_states = FixedArray::make(p.length() + 1, false)
  states[0] = true
  glob_epsilon(p, states)
  for character in s {
    budget.steps += p.length() + 1
    if budget.steps > TOOL_GLOB_MATCH_STEPS {
      return None
    }
    for index = 0; index <= p.length(); index = index + 1 {
      next_states[index] = false
    }
    for index = 0; index < p.length(); index = index + 1 {
      if !states[index] {
        continue
      }
      if p[index] == '*' {
        let recursive = index + 1 < p.length() && p[index + 1] == '*'
        if recursive || character != '/' {
          next_states[index] = true
        }
      } else if (p[index] == '?' && character != '/') || p[index] == character {
        next_states[index + 1] = true
      }
    }
    let previous_states = states
    states = next_states
    next_states = previous_states
    glob_epsilon(p, states)
  }
  Some(states[p.length()])
}

///|
fn NativeTools::glob_tool(self : NativeTools, args : Json) -> Json {
  let pattern = match tool_arg_string(args, "pattern", maximum=1024) {
    Ok(value) if !value.is_empty() => value
    Ok(_) => return tool_error("pattern must not be empty")
    Err(error) => return tool_error(error)
  }
  if pattern.has_prefix("/") ||
    pattern.split("/").contains("..") ||
    pattern.contains("\\") {
    return tool_error("glob pattern must be relative to its search path")
  }
  if pattern.contains("[") ||
    pattern.contains("]") ||
    pattern.contains("{") ||
    pattern.contains("}") {
    return tool_error(
      "native glob supports literals, *, ?, and **; character classes and brace alternatives are unsupported",
    )
  }
  let start = match tool_arg_string(args, "path", maximum=4096) {
    Ok(value) =>
      match self.resolve_path(value, allow_root=true) {
        Ok(value) => value
        Err(error) => return tool_error(error)
      }
    Err(_) => "."
  }
  let budget = { visited: 0, truncated: false, files: [], }
  self.walk(start, 0, budget)
  budget.files.sort()
  let output : Array[String] = []
  let matcher_budget = { steps: 0, }
  let mut output_bytes = 0
  let mut matching_failed = false
  for path in budget.files {
    let relative = if start == "." {
      path
    } else if path == start {
      "."
    } else {
      path[start.length() + 1:].to_owned()
    }
    match glob_match_bounded(pattern, relative, matcher_budget) {
      None => {
        budget.truncated = true
        matching_failed = true
        break
      }
      Some(true) => {
        if output_bytes + @utf8.encode(path).length() + 1 > TOOL_OUTPUT_LIMIT {
          budget.truncated = true
          break
        }
        output.push(path)
        output_bytes += @utf8.encode(path).length() + 1
      }
      Some(false) => ()
    }
    if matching_failed {
      break
    }
    if output.length() >= 1000 {
      budget.truncated = true
      break
    }
  }
  let suffix = if budget.truncated { "\n[search truncated]" } else { "" }
  tool_success(output.join("\n") + suffix)
}

///|
async fn NativeTools::grep_tool(self : NativeTools, args : Json) -> Json {
  if !os_hard_worker_memory_supported() {
    return tool_error(
      "grep is disabled because this host cannot enforce a hard worker memory limit",
    )
  }
  let pattern = match tool_arg_string(args, "pattern", maximum=1024) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let start = match tool_arg_string(args, "path", maximum=4096) {
    Ok(value) =>
      match self.resolve_path(value, allow_root=true) {
        Ok(value) => value
        Err(error) => return tool_error(error)
      }
    Err(_) => "."
  }
  let budget = { visited: 0, truncated: false, files: [], }
  let start_file = self.root.read_text(start, max_bytes=1048576)
  if start_file is Ok(_) {
    budget.files.push(start)
  } else {
    self.walk(start, 0, budget)
  }
  let output : Array[String] = []
  let mut output_bytes = 0
  let mut matches = 0
  let started = @async.now()
  for path in budget.files {
    if (@async.now() - started).to_int() >= 5000 || matches >= 1000 {
      budget.truncated = true
      break
    }
    match self.root.read_text(path, max_bytes=1048576) {
      Err(_) => ()
      Ok((text, _)) =>
        match
          self.run_process(
            "/usr/bin/grep",
            ["-E", "-n", "--", pattern],
            text,
            Int::max(1, 5000 - (@async.now() - started).to_int()),
            memory_limit_mb=256,
          ) {
          Err(_) =>
            return tool_error("grep worker failed or exceeded its time limit")
          Ok(capture) => {
            if capture.code < 0 || capture.code > 1 {
              return tool_error(
                "grep rejected the pattern or could not search a file",
              )
            }
            if capture.code == 0 {
              let lines = capture.output.split("\n").to_array()
              for line in lines {
                if line.is_empty() {
                  continue
                }
                let output_line = path + ":" + line.to_owned()
                output_bytes += @utf8.encode(output_line).length() + 1
                if output_bytes > TOOL_OUTPUT_LIMIT {
                  budget.truncated = true
                  break
                }
                output.push(output_line)
                matches += 1
              }
            }
            budget.truncated = budget.truncated || capture.truncated
          }
        }
    }
    if budget.truncated {
      break
    }
  }
  let suffix = if budget.truncated { "\n[search truncated]" } else { "" }
  tool_success(output.join("\n") + suffix)
}

///|
async fn NativeTools::bash_tool(self : NativeTools, args : Json) -> Json {
  if !self.allow_shell {
    return tool_error(
      "Shell execution is disabled; start the host with --allow-shell to enable explicitly approved bash calls",
    )
  }
  let command = match tool_arg_string(args, "command", maximum=32768) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  let timeout = match tool_arg_int(args, "timeout", 30000, 1, 120000) {
    Ok(value) => value
    Err(error) => return tool_error(error)
  }
  match
    self.run_process(
      "/bin/bash",
      ["--noprofile", "--norc", "-c", command],
      "",
      timeout,
    ) {
    Err(_) => tool_error("Command timed out or its worker could not be started")
    Ok(capture) => {
      let suffix = if capture.truncated { "\n[output truncated]" } else { "" }
      if capture.code == 0 {
        tool_success(capture.output + suffix)
      } else {
        let error_suffix = if capture.output.is_empty() {
          ""
        } else {
          "\n" + capture.output
        }
        tool_error(
          "Command exited " + capture.code.to_string() + error_suffix + suffix,
        )
      }
    }
  }
}

///|
struct ProcessCapture {
  code : Int
  output : String
  truncated : Bool
}

///|
async fn collect_process_output(
  reader : @process.ReadFromProcess,
) -> (Bytes, Bool) {
  let collected : Array[Byte] = []
  let mut truncated = false
  while reader.read_some(max_len=8192) is Some(chunk) {
    for byte in chunk {
      if collected.length() < TOOL_OUTPUT_LIMIT {
        collected.push(byte)
      } else {
        truncated = true
      }
    }
  }
  (Bytes::from_array(collected[:]), truncated)
}

///|
async fn cancel_process_group(pid : Int, leader_reaped : Ref[Bool]) -> Unit {
  if !os_kill_process_group(pid, 15) {
    // The trampoline may be cancelled before `setsid()`. Killing the leader
    // closes that startup window; a second group signal below catches workers
    // that crossed into their session during the grace period.
    if !leader_reaped.val {
      ignore(os_kill_process(pid, 15))
    }
  }
  @async.sleep(500)
  // Escalate by group id even if the leader exited: a descendant can still
  // hold the captured output pipe or keep using CPU.
  ignore(os_kill_process_group(pid, 9))
  // Once wait() reaped the leader, its PID may already belong to an unrelated
  // process. Only signal the leader while it is still our unreaped child.
  if !leader_reaped.val {
    ignore(os_kill_process(pid, 9))
  }
}

///|
async fn NativeTools::run_process(
  self : NativeTools,
  executable : String,
  arguments : Array[String],
  stdin_text : String,
  timeout_ms : Int,
  memory_limit_mb? : Int = 512,
) -> Result[ProcessCapture, String] {
  // Environment is deliberately rebuilt from a tiny allowlist. Provider
  // tokens, API keys, and host secrets never reach tool or grep subprocesses.
  let worker_env : Map[String, String] = Map([
    ("PATH", "/usr/bin:/bin"),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
  ])
  let mut worker_pid : Int? = None
  let leader_reaped = Ref(false)
  let outcome = Some(
    @async.with_timeout(timeout_ms, () => {
      @async.with_task_group() <| group => {
        let (stdin_reader, stdin_writer) = @process.write_to_process()
        let (stdout_reader, stdout_writer) = @process.read_from_process()
        defer stdout_reader.close()
        let cpu_limit_seconds = Int::max(1, (timeout_ms + 999) / 1000)
        let worker_arguments = [
          "--internal-worker",
          memory_limit_mb.to_string(),
          cpu_limit_seconds.to_string(),
          self.workspace_device.to_string(),
          self.workspace_inode.to_string(),
          self.workspace,
          executable,
          ..arguments,
        ]
        let process = @process.spawn(
          group,
          self.worker_launcher,
          worker_arguments,
          extra_env=worker_env,
          inherit_env=false,
          stdin=stdin_reader,
          stdout=stdout_writer,
          stderr=stdout_writer,
          // The trampoline opens and verifies the pinned root, then fchdir's
          // through that descriptor. Do not let spawn resolve a replaceable
          // workspace pathname before that check.
          cwd="/",
          cancel_handler=@process.CancellationHandler(async fn(pid) {
            @async.protect_from_cancel(async fn() {
              cancel_process_group(pid, leader_reaped)
            })
          }),
        )
        worker_pid = Some(process.pid)
        let input_task = group.spawn(
          () => {
            defer stdin_writer.close()
            stdin_writer.write(stdin_text) catch {
              _ => ()
            }
          },
          allow_failure=true,
        )
        let output_task = group.spawn(() => {
          collect_process_output(stdout_reader)
        })
        let code = process.wait()
        leader_reaped.val = true
        input_task.wait() catch {
          _ => ()
        }
        let (bytes, truncated) = output_task.wait()
        let output = @utf8.decode(bytes) catch {
          _ => return { code: 125, output: "", truncated: false, }
        }
        { code, output, truncated, }
      }
    }),
  ) catch {
    _ => None
  }
  match outcome {
    Some(result) => Ok(result)
    None => {
      // `with_timeout` has unwound the task group that owns @process.spawn;
      // its sole waiter has now reaped the leader. The cancellation-handler
      // path above already targeted the leader while it was still owned. Do
      // not risk signalling a PID that the OS may have reused; descendants can
      // still keep the process group alive, so the protected helper repeats
      // the group KILL after the handler's TERM/grace period.
      leader_reaped.val = true
      match worker_pid {
        Some(pid) =>
          @async.protect_from_cancel(async fn() {
            cancel_process_group(pid, leader_reaped)
          })
        None => ()
      }
      Err("worker timed out, was cancelled, or failed")
    }
  }
}
