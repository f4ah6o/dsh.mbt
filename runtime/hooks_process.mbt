///|
const NATIVE_HOOK_STDIN_LIMIT : Int = 65536

///|
const NATIVE_HOOK_OUTPUT_LIMIT : Int = 16384

///|
const NATIVE_HOOK_DEFAULT_TIMEOUT_MS : Int = 10000

///|
const NATIVE_HOOK_MAX_TIMEOUT_MS : Int = 120000

///|
priv struct NativeHookCapture {
  exit_code : Int
  stdout : String
  stderr : String
  truncated : Bool
}

///|
priv struct NativeHookChildOutput {
  code : Int
  stdout : String
  stderr : String
  truncated : Bool
}

///|
async fn collect_hook_output(
  reader : @process.ReadFromProcess,
  overflowed : Ref[Bool],
) -> Bytes {
  let collected : Array[Byte] = []
  while reader.read_some(max_len=8192) is Some(chunk) {
    for byte in chunk {
      if collected.length() < NATIVE_HOOK_OUTPUT_LIMIT {
        collected.push(byte)
      } else {
        overflowed.val = true
      }
    }
  }
  Bytes::from_array(collected[:])
}

///|
async fn native_run_hook_command(
  tools : NativeTools,
  hook : NativeHookCommand,
  stdin_text : String,
) -> Result[NativeHookCapture, String] {
  let stdin_bytes = @utf8.encode(stdin_text)
  if stdin_bytes.length() > NATIVE_HOOK_STDIN_LIMIT {
    return Err("hooks stdin exceeds the 64 KiB limit")
  }
  let worker_env : Map[String, String] = Map([
    ("PATH", "/usr/bin:/bin"),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
    ("CLAUDE_PROJECT_DIR", tools.workspace),
  ])
  let mut worker_pid : Int? = None
  let leader_reaped = Ref(false)
  let output_overflowed = Ref(false)
  let outcome = @async.handle_cancellation(async fn() {
    Some(
      @async.with_timeout(hook.timeout_ms, () => {
        @async.with_task_group() <| group => {
          let (stdin_reader, stdin_writer) = @process.write_to_process()
          let (stdout_reader, stdout_writer) = @process.read_from_process()
          let (stderr_reader, stderr_writer) = @process.read_from_process()
          defer stdout_reader.close()
          defer stderr_reader.close()
          let cpu_limit_seconds = Int::max(1, (hook.timeout_ms + 999) / 1000)
          let worker_arguments = [
            "--internal-worker",
            "512",
            cpu_limit_seconds.to_string(),
            tools.workspace_device.to_string(),
            tools.workspace_inode.to_string(),
            tools.workspace,
            "/bin/sh",
            "-c",
            hook.command,
          ]
          let process = @process.spawn(
            group,
            tools.worker_launcher,
            worker_arguments,
            extra_env=worker_env,
            inherit_env=false,
            stdin=stdin_reader,
            stdout=stdout_writer,
            stderr=stderr_writer,
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
          let stdout_task = group.spawn(() => {
            collect_hook_output(stdout_reader, output_overflowed)
          })
          let stderr_task = group.spawn(() => {
            collect_hook_output(stderr_reader, output_overflowed)
          })
          let exit_code = process.wait()
          leader_reaped.val = true
          input_task.wait() catch {
            _ => ()
          }
          let stdout_bytes = stdout_task.wait()
          let stderr_bytes = stderr_task.wait()
          let stdout = @utf8.decode(stdout_bytes) catch {
            _ =>
              return NativeHookChildOutput::{
                code: exit_code,
                stdout: "",
                stderr: "",
                truncated: true,
              }
          }
          let stderr = @utf8.decode(stderr_bytes) catch {
            _ =>
              return NativeHookChildOutput::{
                code: exit_code,
                stdout: "",
                stderr: "",
                truncated: true,
              }
          }
          NativeHookChildOutput::{
            code: exit_code,
            stdout,
            stderr,
            truncated: output_overflowed.val,
          }
        }
      }),
    ) catch {
      _ => None
    }
  })
  match outcome {
    Some(Some(value)) =>
      Ok({
        exit_code: value.code,
        stdout: value.stdout,
        stderr: value.stderr,
        truncated: value.truncated,
      })
    Some(None) | None => {
      leader_reaped.val = true
      match worker_pid {
        Some(pid) =>
          @async.protect_from_cancel(async fn() {
            cancel_process_group(pid, leader_reaped)
          })
        None => ()
      }
      if @async.is_being_cancelled() {
        @async.pause()
      }
      if output_overflowed.val {
        Ok({ exit_code: 124, stdout: "", stderr: "", truncated: true, })
      } else {
        Err("hook timed out, was cancelled, or could not be started")
      }
    }
  }
}
