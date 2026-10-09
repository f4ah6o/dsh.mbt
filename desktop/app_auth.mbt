///|
fn desktop_auth_status(snapshot : Json) -> Json {
  desktop_json_field(snapshot, "auth").unwrap_or(Json::empty_object())
}

///|
fn desktop_auth_profile_id(auth : Json) -> String {
  let account = desktop_json_field(auth, "account").unwrap_or(Json::null())
  desktop_json_string(account, "profile_id")
}

///|
fn desktop_auth_connected(auth : Json) -> Bool {
  desktop_json_string(auth, "state") == "connected" &&
  desktop_auth_profile_id(auth) != ""
}

///|
fn desktop_auth_model_count(auth : Json) -> Int {
  desktop_json_array(auth, "models").length()
}

///|
fn desktop_auth_model_slug(auth : Json, index : Int) -> String {
  let models = desktop_json_array(auth, "models")
  if index < 0 || index >= models.length() {
    return ""
  }
  desktop_json_string(models[index], "slug")
}

///|
fn desktop_auth_focus_count(auth : Json) -> Int {
  if desktop_auth_connected(auth) {
    4 + desktop_auth_model_count(auth)
  } else {
    3
  }
}

///|
fn desktop_auth_next_focus(auth : Json, current : Int, reverse : Bool) -> Int {
  let count = desktop_auth_focus_count(auth)
  if count <= 0 {
    return 0
  }
  if reverse {
    if current <= 0 {
      count - 1
    } else {
      current - 1
    }
  } else if current + 1 >= count {
    0
  } else {
    current + 1
  }
}

///|
fn desktop_auth_scroll_for_focus(
  state : DesktopState,
  auth : Json,
  focus : Int,
) -> Unit {
  if !desktop_auth_connected(auth) || focus < 4 {
    return
  }
  let visible = desktop_settings_visible_model_rows(state.height)
  let model_index = focus - 4
  if model_index < state.settings_scroll {
    state.settings_scroll = model_index
  } else if model_index >= state.settings_scroll + visible {
    state.settings_scroll = model_index - visible + 1
  }
  state.settings_scroll = desktop_settings_clamp_scroll(
    state.settings_scroll,
    desktop_auth_model_count(auth),
    state.height,
  )
}

///|
fn desktop_auth_clamp_settings_controls(
  state : DesktopState,
  auth : Json,
) -> Unit {
  state.settings_focus = state.settings_focus
    .max(0)
    .min(desktop_auth_focus_count(auth) - 1)
  state.settings_scroll = desktop_settings_clamp_scroll(
    state.settings_scroll,
    desktop_auth_model_count(auth),
    state.height,
  )
  desktop_auth_scroll_for_focus(state, auth, state.settings_focus)
}

///|
async fn desktop_auth_finish_action(state : DesktopState) -> Unit {
  desktop_refresh(state)
  state.auth_busy = false
  let auth = desktop_auth_status(state.snapshot)
  desktop_auth_clamp_settings_controls(state, auth)
  state.dirty = true
}

///|
async fn desktop_auth_start_sign_in(state : DesktopState) -> Unit {
  if state.auth_busy {
    return
  }
  state.auth_busy = true
  state.auth_error = ""
  match state.runtime.auth_begin_sign_in() {
    Err(error) => {
      state.auth_error = error
      state.auth_busy = false
      state.dirty = true
    }
    Ok(false) => {
      state.auth_busy = false
      desktop_refresh(state)
    }
    Ok(true) => {
      desktop_refresh(state)
      state.group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        match state.runtime.auth_sign_in() {
          Err(error) => state.auth_error = error
          Ok(_) => {
            let auth = state.runtime.auth_status()
            let profile_id = desktop_auth_profile_id(auth)
            if profile_id != "" {
              match state.runtime.auth_refresh_models(profile_id) {
                Ok(_) => ()
                Err(error) => state.auth_error = error
              }
            }
          }
        }
        desktop_auth_finish_action(state)
      }
    }
  }
}

///|
fn desktop_auth_start_refresh_models(state : DesktopState) -> Unit {
  if state.auth_busy {
    return
  }
  let auth = desktop_auth_status(state.snapshot)
  let profile_id = desktop_auth_profile_id(auth)
  if !desktop_auth_connected(auth) {
    state.auth_error = "ChatGPT にサインインしてからモデルを読み込んでください。"
    state.dirty = true
    return
  }
  state.auth_busy = true
  state.auth_error = ""
  state.group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    match state.runtime.auth_refresh_models(profile_id) {
      Ok(_) => ()
      Err(error) => state.auth_error = error
    }
    desktop_auth_finish_action(state)
  }
}

///|
fn desktop_auth_start_sign_out(state : DesktopState) -> Unit {
  if state.auth_busy {
    return
  }
  let auth = desktop_auth_status(state.snapshot)
  let profile_id = desktop_auth_profile_id(auth)
  if !desktop_auth_connected(auth) {
    state.auth_error = "接続中の ChatGPT アカウントがありません。"
    state.dirty = true
    return
  }
  state.auth_busy = true
  state.auth_error = ""
  state.group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    match state.runtime.auth_sign_out(profile_id) {
      Ok(_) => ()
      Err(error) => state.auth_error = error
    }
    desktop_auth_finish_action(state)
  }
}

///|
fn desktop_auth_start_select_model(
  state : DesktopState,
  model : String,
) -> Unit {
  if state.auth_busy || model.is_empty() {
    return
  }
  let auth = desktop_auth_status(state.snapshot)
  let profile_id = desktop_auth_profile_id(auth)
  if !desktop_auth_connected(auth) {
    state.auth_error = "ChatGPT にサインインしてからモデルを選んでください。"
    state.dirty = true
    return
  }
  state.auth_busy = true
  state.auth_error = ""
  state.group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    match state.runtime.auth_select_model(profile_id, model) {
      Ok(_) => ()
      Err(error) => state.auth_error = error
    }
    desktop_auth_finish_action(state)
  }
}

///|
async fn desktop_auth_activate_focus(state : DesktopState) -> Unit {
  let auth = desktop_auth_status(state.snapshot)
  let connected = desktop_auth_connected(auth)
  if state.settings_focus == 0 {
    state.settings_open = false
    state.focused = true
    state.dirty = true
  } else if state.settings_focus == 1 {
    state.dirty = true
  } else if !connected && state.settings_focus == 2 {
    desktop_auth_start_sign_in(state)
  } else if connected && state.settings_focus == 2 {
    desktop_auth_start_refresh_models(state)
  } else if connected && state.settings_focus == 3 {
    desktop_auth_start_sign_out(state)
  } else if connected && state.settings_focus >= 4 {
    let model = desktop_auth_model_slug(auth, state.settings_focus - 4)
    desktop_auth_start_select_model(state, model)
  }
}

///|
async fn desktop_auth_handle_settings_key(
  state : DesktopState,
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
) -> Unit {
  let auth = desktop_auth_status(state.snapshot)
  desktop_auth_clamp_settings_controls(state, auth)
  match key {
    @primitives.Escape => {
      state.settings_open = false
      state.focused = true
      state.dirty = true
    }
    @primitives.Tab => {
      state.settings_focus = desktop_auth_next_focus(
        auth,
        state.settings_focus,
        modifiers.shift(),
      )
      desktop_auth_scroll_for_focus(state, auth, state.settings_focus)
      state.dirty = true
    }
    @primitives.Enter | @primitives.Space => desktop_auth_activate_focus(state)
    @primitives.ArrowDown => {
      state.settings_focus = desktop_auth_next_focus(
        auth,
        state.settings_focus,
        false,
      )
      desktop_auth_scroll_for_focus(state, auth, state.settings_focus)
      state.dirty = true
    }
    @primitives.ArrowUp => {
      state.settings_focus = desktop_auth_next_focus(
        auth,
        state.settings_focus,
        true,
      )
      desktop_auth_scroll_for_focus(state, auth, state.settings_focus)
      state.dirty = true
    }
    _ => ()
  }
}

///|
async fn desktop_auth_handle_settings_click(
  state : DesktopState,
  position : @primitives.Point,
) -> Unit {
  let auth = desktop_auth_status(state.snapshot)
  desktop_auth_clamp_settings_controls(state, auth)
  let width = state.width
  let height = state.height
  if desktop_settings_button_rect("settings-close", width, height).contains(
      position,
    ) {
    state.settings_open = false
    state.focused = true
    state.dirty = true
    return
  }
  if desktop_settings_button_rect("settings-nav-chatgpt", width, height).contains(
      position,
    ) {
    state.settings_focus = 1
    state.dirty = true
    return
  }
  if desktop_auth_connected(auth) {
    if desktop_settings_button_rect("auth-models-retry", width, height).contains(
        position,
      ) {
      state.settings_focus = 2
      desktop_auth_start_refresh_models(state)
      return
    }
    if desktop_settings_button_rect("auth-sign-out", width, height).contains(
        position,
      ) {
      state.settings_focus = 3
      desktop_auth_start_sign_out(state)
      return
    }
    for visible_index in 0..<desktop_settings_visible_model_rows(height) {
      let model_index = state.settings_scroll + visible_index
      if model_index < desktop_auth_model_count(auth) &&
        desktop_settings_model_rect(visible_index, width, height).contains(
          position,
        ) {
        state.settings_focus = model_index + 4
        let model = desktop_auth_model_slug(auth, model_index)
        if model != desktop_json_string(auth, "selected_model") {
          desktop_auth_start_select_model(state, model)
        } else {
          state.dirty = true
        }
        return
      }
    }
  } else if desktop_settings_button_rect("auth-sign-in", width, height).contains(
      position,
    ) {
    state.settings_focus = 2
    desktop_auth_start_sign_in(state)
  }
}
