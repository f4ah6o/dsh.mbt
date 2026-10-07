///|
#export_name("client_set_draft")
pub fn client_set_draft(handle : Int, value : String) -> String {
  match get_client(handle) {
    Some(state) => {
      state.set_draft(value)
      state.preferences_json().stringify()
    }
    None => "{}"
  }
}

///|
#export_name("client_set_selection")
pub fn client_set_selection(handle : Int, value : String) -> String {
  match get_client(handle) {
    Some(state) => {
      state.set_selected_session(if value == "" { None } else { Some(value) })
      state.preferences_json().stringify()
    }
    None => "{}"
  }
}

///|
#export_name("client_set_scroll_anchor")
pub fn client_set_scroll_anchor(handle : Int, value : String) -> String {
  match get_client(handle) {
    Some(state) => {
      state.set_scroll_anchor(if value == "" { None } else { Some(value) })
      state.preferences_json().stringify()
    }
    None => "{}"
  }
}

///|
#export_name("client_set_follow_latest")
pub fn client_set_follow_latest(handle : Int, value : String) -> String {
  match get_client(handle) {
    Some(state) => {
      state.set_follow_latest(value == "true")
      state.preferences_json().stringify()
    }
    None => "{}"
  }
}

///|
#export_name("client_set_text_view")
pub fn client_set_text_view(handle : Int, value : String) -> String {
  match get_client(handle) {
    Some(state) => {
      state.set_text_view(value == "true")
      state.preferences_json().stringify()
    }
    None => "{}"
  }
}

///|
#export_name("client_persisted_state")
pub fn client_persisted_state(handle : Int) -> String {
  match get_client(handle) {
    Some(state) => state.preferences_json().stringify()
    None => "{}"
  }
}

///|
#export_name("client_restore_preferences")
pub fn client_restore_preferences(handle : Int, raw : String) -> String {
  match get_client(handle) {
    Some(state) =>
      Json::object({
        "ok": Json::boolean(state.restore_preferences(raw)),
        "state": client_state_json(state),
      }).stringify()
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}
