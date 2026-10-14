///|
async fn desktop_run(
  config : DesktopConfig,
  start : () -> Result[Host, String],
) -> Result[Unit, String] {
  let runtime = match
    @runtime.NativeDesktop::open(
      config.data_dir,
      config.workspace,
      demo=config.demo,
      allow_shell=config.allow_shell,
      mode=config.mode,
      model=config.model,
      base_url=config.base_url,
      max_retries=config.max_retries,
      mcp_config_path=config.mcp_config_path,
      hooks_config_path=config.hooks_config_path,
      hooks_plugin_root=config.hooks_plugin_root,
      hooks_project_dir=config.hooks_project_dir,
      hooks_dialect=config.hooks_dialect,
      hooks_model=config.hooks_model,
      lsp_config_path=config.lsp_config_path,
      enable_skills=config.enable_skills,
      skill_dirs=config.skill_dirs,
      enable_subagents=config.enable_subagents,
    ) {
    Ok(value) => value
    Err(error) => return Err("dsh runtime could not start: " + error)
  }
  let host = match start() {
    Ok(value) => value
    Err(error) => {
      ignore(runtime.close())
      return Err("native desktop host could not start: " + error)
    }
  }
  let mut window : @platform.WindowId? = None
  let mut offline_session : String? = None
  let result = @async.with_task_group() <| group => {
    let created = match
      host.backend.create_window("dsh — Native Assistant", 1120.0, 760.0) {
      Ok(value) => value
      Err(error) =>
        return Err(
          "native window could not be created: " + desktop_error_text(error),
        )
    }
    match (host.initialize_window)(created) {
      Err(error) => {
        ignore(host.backend.destroy_window(created))
        return Err(desktop_error_text(error))
      }
      Ok(_) => ()
    }
    window = Some(created)
    let state = desktop_state(runtime, host, created, group, config)
    desktop_refresh(state)
    let app_result = if config.offline_e2e {
      match desktop_run_offline_e2e(state) {
        Ok(session_id) => {
          offline_session = Some(session_id)
          Ok(())
        }
        Err(error) => {
          ignore(host.backend.request_close(created))
          for _ in 0..<3 {
            ignore(desktop_pump(state, false))
          }
          Err(error)
        }
      }
    } else if config.smoke {
      desktop_run_smoke(state)
    } else {
      let mut loop_result : Result[Unit, String] = Ok(())
      while !state.done {
        match desktop_pump(state, false) {
          Ok(_) => ()
          Err(error) => {
            state.error_message = error
            loop_result = Err(error)
            ignore(host.backend.request_close(created))
            state.done = true
          }
        }
      }
      loop_result
    }
    let close_result = runtime.close()
    if app_result is Err(_) {
      app_result
    } else {
      close_result
    }
  }
  match window {
    Some(created) => ignore(host.backend.destroy_window(created))
    None => ()
  }
  let stopped = host.backend.stop()
  match result {
    Err(error) => {
      ignore(runtime.close())
      return Err(error)
    }
    Ok(_) => ()
  }
  match stopped {
    Err(error) =>
      return Err("native host shutdown failed: " + desktop_error_text(error))
    Ok(_) => ()
  }
  if config.offline_e2e {
    let session_id = match offline_session {
      Some(value) => value
      None => return Err("offline native demo completed without a session id")
    }
    match desktop_verify_persisted_reload(config, session_id) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    println(
      "DSH_DESKTOP_DEMO {\"native_events\":true,\"tool_approval\":\"approved\",\"completed\":true,\"workspace_write\":true,\"reload\":\"passed\",\"japanese_frame\":\"passed\",\"frame\":\"\{config.frame_output}\"}",
    )
  }
  Ok(())
}

///|
pub async fn run(start : () -> Result[Host, String]) -> Unit {
  let args = @env.args()
  let options = if args.length() > 1 { args[1:].to_owned() } else { [] }
  match desktop_parse_config(options) {
    Err("help") => println(desktop_usage())
    Err(error) =>
      @runtime.desktop_fail(
        "desktop option error: " + error + "\n" + desktop_usage(),
      )
    Ok(config) => {
      // Gracefully settle tools, including workers in their own sessions,
      // instead of cancelling main before NativeDesktop.close can run.
      if !@runtime.desktop_signals_start() {
        @runtime.desktop_fail("desktop could not install shutdown handlers")
      }
      @async.with_task_group() <| group => {
        group.add_defer(fn() { @runtime.desktop_signals_stop() })
        match desktop_run(config, start) {
          Ok(_) => ()
          Err(error) => @runtime.desktop_fail("desktop failed: " + error)
        }
      }
    }
  }
}
