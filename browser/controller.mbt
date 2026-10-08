///|
priv struct BrowserApp {
  client : RemoteClient
  mut sessions : Array[Json]
  mut id : String
  mut selection : Int
  mut snapshot : Json
  mut mutation : Bool
  mut frame : Int?
  mut transcript_key : String
  mut status_key : String
  mut action_error : String
  mut action_message : String
  mut connection_message : String
  mut draft_scope : String
  mut recovering : Bool
  mut auth_poll : Int?
  mut receipt_poll : Int?
  mut receipt_poll_running : Bool
  mut auth_models_loading : Bool
  mut auth_models_error : Bool
  mut auth_attempted_key : String
  mut install_prompt : BrowserValue?
  mut workspace_metadata : Json?
  mut metadata_context_key : String
  mut metadata_last_started : Double
  mut metadata_in_flight : Bool
  mut sidebar_collapsed : Bool
  mut mobile_sidebar_open : Bool
  mut context_panel_open : Bool
  mut auth_models_in_flight_key : String?
}

///|
let browser_app : Ref[BrowserApp?] = Ref(None)

///|
fn BrowserApp::new() -> BrowserApp {
  {
    client: RemoteClient::new(),
    sessions: [],
    id: "",
    selection: 0,
    snapshot: Json::object({
      "messages": Json::array([]),
      "events": Json::array([]),
    }),
    mutation: false,
    frame: None,
    transcript_key: "",
    status_key: "",
    action_error: "",
    action_message: "",
    connection_message: "",
    draft_scope: "",
    recovering: false,
    auth_poll: None,
    receipt_poll: None,
    receipt_poll_running: false,
    auth_models_loading: false,
    auth_models_error: false,
    auth_attempted_key: "",
    install_prompt: None,
    workspace_metadata: None,
    metadata_context_key: "",
    metadata_last_started: -1_000_000.0,
    metadata_in_flight: false,
    sidebar_collapsed: false,
    mobile_sidebar_open: false,
    context_panel_open: false,
    auth_models_in_flight_key: None,
  }
}

///|
fn string_array(value : Json, key : String) -> Array[String] {
  match field(value, key) {
    Some(Json::Array(values)) =>
      values.map(item => {
        match item {
          Json::String(text) => text
          _ => ""
        }
      })
    _ => []
  }
}

///|
fn json_object(value : Json?) -> Json {
  match value {
    Some(Json::Object(fields)) => Json::object(fields)
    _ => Json::empty_object()
  }
}

///|
fn find_session(sessions : Array[Json], id : String) -> Json? {
  for session in sessions {
    if string_member(session, "id") == id {
      return Some(session)
    }
  }
  None
}

///|
fn object_string(value : Json, key : String, fallback : String) -> String {
  nonempty(string_member(value, key), fallback)
}

///|
fn app_connection(app : BrowserApp) -> String {
  string_member(app.client.state(), "connection")
}

///|
fn app_auth(app : BrowserApp) -> Json {
  json_object(field(app.client.state(), "auth"))
}

///|
fn app_auth_context_key(app : BrowserApp) -> String {
  let auth = app_auth(app)
  Json::array([
    field(auth, "state").unwrap_or(Json::null()),
    field(json_object(field(auth, "account")), "profile_id").unwrap_or(
      Json::null(),
    ),
    field(auth, "selected_model").unwrap_or(Json::null()),
  ]).stringify()
}

///|
fn connection_error(app : BrowserApp, message : String) -> Unit {
  app.connection_message = message
  dom_set_text("connection-error-text", message)
  dom_set_boolean_property("connection-error", "hidden", false)
  let session = app.snapshot
  render_workspace_context(app, session, true)
}

///|
fn clear_connection_error(app : BrowserApp) -> Unit {
  app.connection_message = ""
  dom_set_boolean_property("connection-error", "hidden", true)
  render_workspace_context(app, app.snapshot, false)
}

///|
fn sync_from_client(app : BrowserApp, restore_draft? : Bool = false) -> Unit {
  let client_state = app.client.state()
  let previous_scope = app.draft_scope
  let projection = json_object(field(client_state, "projection"))
  let sessions = match session_list(projection) {
    Ok(rows) => rows
    Err(_) => []
  }
  app.sessions = sessions
  app.id = string_member(client_state, "selected_session")
  let selected = field(client_state, "selected_session_projection")
  let summary = find_session(app.sessions, app.id)
  app.snapshot = match selected {
    Some(Json::Object(_)) => selected.unwrap_or(Json::null())
    _ =>
      summary.unwrap_or(
        Json::object({ "messages": Json::array([]), "events": Json::array([]) }),
      )
  }
  let scope = string_member(client_state, "scope_key")
  if restore_draft || previous_scope != scope {
    app.draft_scope = scope
    dom_set_value("prompt", string_member(client_state, "draft"))
    resize_composer()
  }
  render_sessions(app)
  render_controls(app)
  render_account(app)
  render_workspace_context(app, app.snapshot, app.connection_message != "")
  render_accessible_transcript(app)
  sync_text_view(app)
  schedule_paint(app)
}

///|
fn render_workspace_context(
  app : BrowserApp,
  session : Json,
  has_error : Bool,
) -> Unit {
  let context = workspace_context(session, app_connection(app), has_error)
  dom_set_text("context-summary", context.summary)
  dom_set_text("context-status", context.status)
  dom_set_text("context-turn", context.turn)
  dom_set_text("context-history", context.history)
  dom_set_text("context-source", context.source)
  dom_set_text("context-parent", context.parent)
  dom_set_boolean_property("context-read-only", "hidden", !context.read_only)
  dom_set_text("context-host-status", context.host_status)
  dom_set_text("shell-status", context.shell_status)
  dom_set_attribute("shell-status-dot", "data-state", context.connection_state)
  match app.workspace_metadata {
    Some(metadata) => {
      let view = workspace_metadata(metadata, app_auth(app))
      dom_set_text("project-name", view.project)
      dom_set_text("repository-name", view.repository)
      dom_set_text("branch-name", view.branch)
      dom_set_text("provider-model", view.provider_model)
    }
    None => ()
  }
}

///|
fn render_sessions(app : BrowserApp) -> Unit {
  let query = dom_value("session-search").trim().to_lower().to_owned()
  let filtered = app.sessions.filter(session => {
    let searchable = [
      string_member(session, "title"),
      string_member(session, "id"),
      string_member(session, "parent_session_id"),
      status_label(session),
      if is_read_only(session) {
        "imported read-only history"
      } else {
        "local conversation"
      },
    ]
    session_list_matches(searchable, query) ||
    string_member(session, "id") == app.id
  })
  let children : Array[@yami_kumo.Html] = []
  if filtered.is_empty() {
    let empty = if query != "" {
      "検索に一致する会話はありません。"
    } else if app.sessions.is_empty() {
      "会話はまだありません。メッセージを送って開始してください。"
    } else {
      "会話はありません。"
    }
    children.push(
      html_element("p", [html_class("empty-list")], [html_text(empty)]),
    )
  } else {
    for session in filtered {
      let id = string_member(session, "id")
      let title = object_string(session, "title", "無題のセッション")
      let attrs = [
        action_attribute("select-session"),
        html_attribute("data-session-id", id),
        html_attribute("data-id", id),
        html_class("session-option"),
        html_attribute("type", "button"),
      ]
      let attributes = if id == app.id {
        attrs + [html_attribute("aria-current", "page")]
      } else {
        attrs
      }
      let label = @yami_kumo.fragment([
        html_element("span", [html_class("session-option-title")], [
          html_text(title),
        ]),
        html_element("span", [html_class("session-option-state")], [
          html_text(status_label(session)),
        ]),
      ])
      children.push(
        @yami_kumo.button(
          label,
          variant=@yami_kumo.ButtonVariant::Secondary,
          class_name="session-option",
          attrs=attributes,
        ),
      )
    }
  }
  let html = match @yami_kumo.render_html(@yami_kumo.fragment(children)) {
    Ok(value) => value
    Err(_) => ""
  }
  dom_set_html("sessions", html)
}

///|
fn session_list_matches(values : Array[String], query : String) -> Bool {
  if query == "" {
    return true
  }
  values.any(value => value.to_lower().contains(query))
}

///|
fn join_strings(values : Array[String], separator : String) -> String {
  let mut output = ""
  for value in values {
    if value == "" {
      continue
    }
    if output != "" {
      output = output + separator
    }
    output = output + value
  }
  output
}

///|
fn render_controls(app : BrowserApp) -> Unit {
  let session = app.snapshot
  let busy = is_busy(session)
  let read_only = is_read_only(session)
  let approval = field(session, "pending_approval").unwrap_or(Json::null())
  let has_approval = has_value(Some(approval))
  let connection = app_connection(app)
  let can_prune = app.id != "" &&
    !read_only &&
    !busy &&
    (
      string_member(session, "status") == "idle" ||
      string_member(session, "status") == "completed"
    ) &&
    has_tool_results(session) &&
    connection == "synced"
  let session_status = string_member(session, "status")
  let can_fork = app.id != "" &&
    !read_only &&
    !busy &&
    (
      session_status == "idle" ||
      session_status == "completed" ||
      session_status == "failed" ||
      session_status == "cancelled"
    ) &&
    connection == "synced"
  dom_set_text(
    "session-title",
    if app.id == "" {
      "エージェントのワークスペース"
    } else {
      object_string(session, "title", "無題のセッション")
    },
  )
  dom_set_text("status", status_label(session))
  dom_set_attribute(
    "status",
    "data-state",
    if has_approval {
      "approval"
    } else {
      nonempty(session_status, "idle")
    },
  )
  dom_set_text(
    "progress",
    if number_member(session, "turn_id") > 0.0 {
      "\{number_member(session, "turn_id").to_int()} ターン目 · ステップ \{number_member(session, "step").to_int()}"
    } else {
      ""
    },
  )
  dom_set_boolean_property(
    "cancel",
    "disabled",
    app.mutation || !busy || app.id == "",
  )
  dom_set_boolean_property(
    "fork-session",
    "disabled",
    app.mutation || !can_fork,
  )
  dom_set_boolean_property("prune-results", "hidden", !can_prune)
  dom_set_boolean_property(
    "prune-results",
    "disabled",
    app.mutation || !can_prune,
  )
  dom_set_boolean_property(
    "new-session",
    "disabled",
    app.mutation || connection != "synced",
  )
  dom_set_boolean_property(
    "prompt",
    "disabled",
    read_only || connection != "synced",
  )
  dom_set_attribute(
    "prompt",
    "placeholder",
    if read_only {
      "読み込んだ履歴は読み取り専用です"
    } else {
      "取り組みたいことを入力してください"
    },
  )
  dom_set_boolean_property(
    "send",
    "disabled",
    app.mutation ||
    busy ||
    read_only ||
    connection != "synced" ||
    dom_value("prompt").trim().is_empty(),
  )
  let hint = if app.connection_message != "" {
    app.connection_message
  } else if read_only {
    "読み込んだ履歴は読み取り専用のため、続けて送信できません。"
  } else if has_approval {
    "ツールの実行内容を確認してください。"
  } else if busy {
    "エージェントが処理中です。停止するとこのターンをキャンセルします。"
  } else {
    "⌘ / Ctrl + Enter で送信"
  }
  dom_set_text("composer-hint", hint)
  dom_set_boolean_property("approval", "hidden", !has_approval)
  if has_approval {
    let approval_name = object_string(approval, "name", "ツール")
    dom_set_text(
      "approval-description",
      "\{approval_name} の実行許可を待っています。",
    )
    let arguments = pretty_arguments(field(approval, "arguments"))
    if dom_text("approval-arguments") != arguments {
      dom_set_text("approval-arguments", arguments)
    }
  }
  dom_set_boolean_property(
    "approve",
    "disabled",
    app.mutation || !has_approval || app.id == "",
  )
  dom_set_boolean_property(
    "deny",
    "disabled",
    app.mutation || !has_approval || app.id == "",
  )
  let error = if app.action_error != "" {
    app.action_error
  } else {
    run_error(session)
  }
  dom_set_boolean_property("run-error", "hidden", error == "")
  dom_set_text("run-error", error)
  dom_set_boolean_property("action-message", "hidden", app.action_message == "")
  dom_set_text("action-message", app.action_message)
  let status_key = "\{app.id}:\{session_status}:\{string_member(approval, "call_id")}"
  if app.status_key != status_key {
    dom_set_text(
      "announcement",
      if has_approval {
        "\{object_string(approval, "name", "ツール")} の実行許可が必要です。"
      } else {
        status_label(session)
      },
    )
    app.status_key = status_key
  }
}

///|
fn render_account(app : BrowserApp) -> Unit {
  let auth = app_auth(app)
  let auth_state = nonempty(string_member(auth, "state"), "signed_out")
  let account = json_object(field(auth, "account"))
  let email = string_member(account, "email")
  let connected = auth_state == "connected"
  let has_profile = string_member(account, "profile_id") != ""
  let models = array_member(auth, "models")
  let model_count = models.length()
  let status = match auth_state {
    "connected" =>
      if email != "" {
        "ChatGPT · " + email
      } else {
        "ChatGPT 接続済み"
      }
    "signing_in" => "ChatGPT のサインインを待っています"
    "reauth_required" => "ChatGPT に再度サインインしてください"
    _ => "ChatGPT 未接続"
  }
  dom_set_attribute("auth-status", "data-state", auth_state)
  dom_set_text("auth-status", status)
  let usage = if string_member(auth, "plan_usage") == "enabled" {
    "プランの利用状況を確認できます"
  } else if connected {
    "このアカウントではプランの利用状況を確認できません。ChatGPT の設定 → 使用状況を確認してください。"
  } else {
    "プランを確認するにはサインインしてください"
  }
  let scopes = join_strings(string_array(auth, "scopes"), ", ")
  dom_set_text(
    "auth-detail",
    usage + (if scopes == "" { "" } else { " · " + scopes }),
  )
  let guidance = if !connected {
    if !browser_is_local_origin() {
      if auth_state == "signing_in" {
        "ホスト Mac のブラウザーでサインインを完了してください。完了するとこのページが更新されます。"
      } else {
        "ホスト Mac で dsh を開いて、ChatGPT にサインインするかアカウントを切り替えてください。"
      }
    } else if auth_state == "signing_in" {
      "このブラウザーの新しいタブでサインインを完了してください。"
    } else {
      "サインイン用のタブが開きます。認証情報はホスト側に保存されます。"
    }
  } else if model_count > 0 {
    "別のアカウントに切り替えるには、接続を解除してからサインインしてください。"
  } else if app.auth_models_loading {
    "この ChatGPT アカウントのモデルを読み込んでいます…"
  } else if app.auth_models_error {
    "モデルを読み込めませんでした。「モデルを再読み込み」を選んで再試行してください。"
  } else {
    "このアカウントのモデルがありません。「モデルを再読み込み」を選んで再確認してください。"
  }
  dom_set_text("auth-guidance", guidance)
  dom_set_boolean_property(
    "usage-link",
    "hidden",
    !connected || string_member(auth, "plan_usage") == "enabled",
  )
  dom_set_boolean_property("auth-sign-in", "hidden", connected)
  dom_set_text(
    "auth-sign-in",
    if auth_state == "reauth_required" {
      "再度サインイン"
    } else {
      "ChatGPT にサインイン"
    },
  )
  dom_set_boolean_property(
    "auth-sign-in",
    "disabled",
    app.mutation || auth_state == "signing_in" || !browser_is_local_origin(),
  )
  dom_set_boolean_property("auth-sign-out", "hidden", !connected)
  dom_set_boolean_property(
    "auth-sign-out",
    "disabled",
    app.mutation || !has_profile,
  )
  dom_set_boolean_property(
    "auth-models-retry",
    "hidden",
    !connected || model_count > 0,
  )
  dom_set_boolean_property(
    "auth-models-retry",
    "disabled",
    app.mutation || app.auth_models_loading,
  )
  let options : Array[@yami_kumo.Html] = []
  if model_count == 0 {
    let label = if connected {
      "利用できるモデルがありません"
    } else {
      "ChatGPT に接続してモデルを表示"
    }
    options.push(
      html_element("option", [html_attribute("value", "")], [html_text(label)]),
    )
  } else {
    options.push(
      html_element(
        "option",
        [html_attribute("value", ""), html_boolean_attribute("disabled")],
        [html_text("モデルを選択")],
      ),
    )
    for model in models {
      let slug = string_member(model, "slug")
      if slug != "" {
        options.push(
          html_element("option", [html_attribute("value", slug)], [
            html_text(object_string(model, "display_name", slug)),
          ]),
        )
      }
    }
  }
  let option_html = match @yami_kumo.render_html(@yami_kumo.fragment(options)) {
    Ok(value) => value
    Err(_) => ""
  }
  dom_set_html("model-picker", option_html)
  let selected_model = string_member(auth, "selected_model")
  let selected_is_available = models.any(model => {
    string_member(model, "slug") == selected_model
  })
  dom_set_value(
    "model-picker",
    if selected_is_available {
      selected_model
    } else {
      ""
    },
  )
  dom_set_boolean_property(
    "model-picker",
    "disabled",
    !connected || model_count == 0 || app.mutation,
  )
  dom_set_boolean_property("install-app", "hidden", app.install_prompt is None)
  schedule_auth_refresh(app, auth_state == "signing_in")
}

///|
fn sync_text_view(app : BrowserApp) -> Unit {
  let text_view = browser_json_bool(app.client.state(), "text_view")
  dom_set_attribute("text-view", "aria-pressed", text_view.to_string())
  dom_set_text(
    "text-view",
    if text_view {
      "キャンバス表示"
    } else {
      "テキスト表示"
    },
  )
  dom_set_boolean_property("transcript-scroll", "hidden", text_view)
  dom_toggle_class("text-transcript", "sr-only", !text_view)
  dom_set_boolean_property("jump-latest", "hidden", true)
}

///|
fn render_accessible_transcript(app : BrowserApp) -> Unit {
  let messages = display_messages(app.snapshot)
  let key = Json::array(
    messages.map(message => {
      Json::object({
        "label": Json::string(message.label),
        "text": Json::string(message.text),
      })
    }),
  ).stringify()
  if app.transcript_key == key {
    return
  }
  app.transcript_key = key
  let was_bottom = dom_scroll_top("text-transcript") +
    dom_measure("text-transcript", "clientHeight") >=
    dom_scroll_height("text-transcript") - 60.0
  let children : Array[@yami_kumo.Html] = []
  if messages.is_empty() {
    children.push(
      html_element("p", [], [
        html_text("メッセージを送ると開始します。"),
      ]),
    )
  } else {
    for message in messages {
      children.push(
        html_element("article", [html_class("text-message")], [
          html_element("h2", [], [html_text(message.label)]),
          html_element("pre", [], [html_text(message.text)]),
        ]),
      )
    }
  }
  let html = match @yami_kumo.render_html(@yami_kumo.fragment(children)) {
    Ok(value) => value
    Err(_) => ""
  }
  dom_set_html("text-transcript", html)
  if browser_json_bool(app.client.state(), "follow_latest") || was_bottom {
    dom_scroll_to_bottom("text-transcript")
  }
}

///|
fn current_browser_app() -> BrowserApp? {
  browser_app.val
}

///|
fn render_shell_context(app : BrowserApp) -> Unit {
  render_workspace_context(app, app.snapshot, app.connection_message != "")
}

///|
fn schedule_paint(app : BrowserApp) -> Unit {
  if app.frame is Some(_) {
    return
  }
  app.frame = Some(dom_request_frame(() => paint(app)))
}

///|
fn paint(app : BrowserApp) -> Unit {
  app.frame = None
  if browser_json_bool(app.client.state(), "text_view") {
    return
  }
  let width = dom_measure("transcript-scroll", "clientWidth").to_int().max(1)
  let height = dom_measure("transcript-scroll", "clientHeight").to_int().max(1)
  let scale = browser_device_scale().min(3.0)
  let snapshot_json = app.snapshot.stringify()
  let extent = @app.measure_ui(snapshot_json, width).max(0)
  let spacer_height = (extent - height).max(0)
  dom_set_element_style("scene-spacer", "height", "\{spacer_height}px")
  dom_set_element_style("transcript-canvas", "height", "\{height}px")
  if dom_measure("transcript-canvas", "width").to_int() !=
    (width.to_double() * scale).round().to_int() ||
    dom_measure("transcript-canvas", "height").to_int() !=
    (height.to_double() * scale).round().to_int() {
    dom_set_numeric_property(
      "transcript-canvas",
      "width",
      (width.to_double() * scale).round(),
    )
    dom_set_numeric_property(
      "transcript-canvas",
      "height",
      (height.to_double() * scale).round(),
    )
  }
  if browser_json_bool(app.client.state(), "follow_latest") {
    let top = (extent - height).max(0)
    dom_set_numeric_property("transcript-scroll", "scrollTop", top.to_double())
  }
  let scroll_top = dom_scroll_top("transcript-scroll").to_int()
  let presentation = match app.snapshot {
    Json::Object(fields) => {
      fields["_ui_scroll_top"] = Json::number(scroll_top.to_double())
      Json::object(fields)
    }
    _ => app.snapshot
  }
  if !browser_canvas_context_available("transcript-canvas") {
    connection_error(
      app, "会話の描画に失敗しました: Canvas 2D コンテキストを利用できません。",
    )
    return
  }
  let context = browser_canvas_context("transcript-canvas")
  let scene = match
    browser_json(@app.render_ui(presentation.stringify(), width, height)) {
    Ok(value) => value
    Err(_) => {
      connection_error(
        app, "会話の描画に失敗しました: MoonBit の会話シーンを読み取れませんでした。",
      )
      return
    }
  }
  match
    draw_scene_snapshot(
      context,
      scene,
      width.to_double(),
      height.to_double(),
      scale,
    ) {
    Ok(_) => ()
    Err(error) =>
      connection_error(
        app,
        "会話の描画に失敗しました: " + error.message(),
      )
  }
  let follow = browser_json_bool(app.client.state(), "follow_latest")
  dom_set_boolean_property("jump-latest", "disabled", extent <= height)
  dom_set_boolean_property("jump-latest", "hidden", follow || extent <= height)
}

///|
fn resize_composer() -> Unit {
  if browser_media_matches("(max-width: 560px)") {
    dom_set_element_style("prompt", "height", "auto")
    let prompt_height = dom_measure("prompt", "scrollHeight")
    let viewport_limit = (browser_viewport_height() * 0.3).max(72.0)
    let height = prompt_height.min(viewport_limit)
    dom_set_element_style("prompt", "height", "\{height}px")
  }
}

///|
fn active_metadata_key(app : BrowserApp) -> String {
  app_auth_context_key(app)
}

///|
async fn refresh_workspace_metadata(
  app : BrowserApp,
  force? : Bool = false,
) -> Unit {
  let now = browser_now_epoch()
  if app.metadata_in_flight ||
    (!force && now - app.metadata_last_started < 10_000.0) {
    return
  }
  app.metadata_last_started = now
  app.metadata_in_flight = true
  let context_key = active_metadata_key(app)
  app.metadata_context_key = context_key
  match request_json("/api/metadata", timeout_ms=5_000) {
    Ok(payload) =>
      match field(payload, "result") {
        Some(metadata) =>
          match metadata {
            Json::Object(_) if active_metadata_key(app) == context_key &&
              app.metadata_context_key == context_key => {
              app.workspace_metadata = Some(metadata)
              render_shell_context(app)
            }
            _ => ()
          }
        _ => ()
      }
    Err(_) => ()
  }
  app.metadata_in_flight = false
}

///|
fn apply_panel_state(app : BrowserApp, focus? : Bool = false) -> Unit {
  let mobile_sidebar = browser_media_matches("(max-width: 820px)")
  let mobile_context = browser_media_matches("(max-width: 1180px)")
  if app.mobile_sidebar_open && app.context_panel_open {
    app.context_panel_open = false
  }
  browser_set_shell_data(
    ".yk-shell",
    "sidebarCollapsed",
    app.sidebar_collapsed.to_string(),
  )
  browser_set_shell_data(
    ".yk-shell",
    "mobileSidebarOpen",
    app.mobile_sidebar_open.to_string(),
  )
  browser_set_shell_data(
    ".yk-shell",
    "contextPanelOpen",
    app.context_panel_open.to_string(),
  )
  dom_set_attribute(
    "navigation-toggle",
    "aria-expanded",
    app.mobile_sidebar_open.to_string(),
  )
  dom_set_attribute(
    "mobile-navigation-close",
    "aria-expanded",
    app.mobile_sidebar_open.to_string(),
  )
  dom_set_attribute(
    "sidebar-toggle",
    "aria-pressed",
    app.sidebar_collapsed.to_string(),
  )
  dom_set_text(
    "sidebar-toggle",
    if app.sidebar_collapsed {
      "ナビゲーションを表示"
    } else {
      "ナビゲーションを隠す"
    },
  )
  dom_set_attribute(
    "context-toggle",
    "aria-expanded",
    app.context_panel_open.to_string(),
  )
  dom_set_attribute(
    "context-close",
    "aria-expanded",
    app.context_panel_open.to_string(),
  )

  let modal_sidebar = app.mobile_sidebar_open && mobile_sidebar
  let modal_context = app.context_panel_open && mobile_context
  let sidebar_hidden = if mobile_sidebar {
    !app.mobile_sidebar_open
  } else {
    app.sidebar_collapsed
  }
  let context_hidden = !app.context_panel_open
  apply_panel_accessibility(
    "yk-mobile-navigation", sidebar_hidden, modal_sidebar,
  )
  apply_panel_accessibility("yk-context-panel", context_hidden, modal_context)
  if modal_sidebar {
    set_shell_inert("yk-mobile-navigation")
    if focus {
      focus_panel_item("yk-mobile-navigation", 0)
    }
  } else if modal_context {
    set_shell_inert("yk-context-panel")
    if focus {
      focus_panel_item("yk-context-panel", 0)
    }
  } else {
    clear_shell_inert()
  }
}

///|
let panel_focusable_selector : String = "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex=\"-1\"])"

///|
let modal_shell_targets_selector : String = ".yk-topbar, .yk-workspace, .yk-bottom-bar, #yk-mobile-navigation, #yk-context-panel"

///|
let nonmodal_shell_targets_selector : String = ".yk-topbar, .yk-workspace, .yk-bottom-bar"

///|
fn apply_panel_accessibility(
  panel_id : String,
  hidden : Bool,
  modal : Bool,
) -> Unit {
  if !dom_element_exists(panel_id) {
    return
  }
  dom_set_attribute(panel_id, "aria-hidden", hidden.to_string())
  if hidden {
    dom_set_attribute(panel_id, "inert", "")
  } else {
    dom_remove_attribute(panel_id, "inert")
  }
  if modal {
    dom_set_attribute(panel_id, "role", "dialog")
    dom_set_attribute(panel_id, "aria-modal", "true")
  } else {
    dom_remove_attribute(panel_id, "role")
    dom_remove_attribute(panel_id, "aria-modal")
  }
}

///|
fn panel_focusable_elements(panel_id : String) -> Array[BrowserValue] {
  let focusable = []
  for node in browser_query_nodes(panel_id, panel_focusable_selector) {
    if browser_node_has_visible_rect(node) &&
      !browser_node_has_attribute(node, "inert") {
      focusable.push(node)
    }
  }
  focusable
}

///|
fn focus_panel_item(panel_id : String, index : Int) -> Unit {
  let focusable = panel_focusable_elements(panel_id)
  if index >= 0 && index < focusable.length() {
    browser_node_focus(focusable[index])
  } else {
    dom_focus(panel_id)
  }
}

///|
fn set_shell_inert(modal_id : String) -> Unit {
  for target in browser_query_selector_all(modal_shell_targets_selector) {
    if browser_node_id(target) == modal_id {
      browser_remove_node_attribute(target, "inert")
    } else {
      browser_set_node_attribute(target, "inert", "")
    }
  }
}

///|
fn clear_shell_inert() -> Unit {
  for target in browser_query_selector_all(nonmodal_shell_targets_selector) {
    browser_remove_node_attribute(target, "inert")
  }
}

///|
fn close_panels(app : BrowserApp, restore_focus : Bool) -> Unit {
  let sidebar_was_open = app.mobile_sidebar_open
  let context_was_open = app.context_panel_open
  app.mobile_sidebar_open = false
  app.context_panel_open = false
  apply_panel_state(app)
  if restore_focus {
    if sidebar_was_open {
      dom_focus("navigation-toggle")
    } else if context_was_open {
      dom_focus("context-toggle")
    }
  }
}

///|
fn set_japanese_font(key : String) -> Unit {
  let selected = normalize_japanese_font(key)
  let stack = japanese_font_stack(selected)
  if stack != "" {
    dom_set_root_style("--dsh-font-family", stack)
    browser_local_storage_set("dsh.display.japanese-font.v1", selected)
  }
  dom_set_value("japanese-font", selected)
}

///|
fn restore_japanese_font() -> Unit {
  let selected = match
    browser_local_storage_get("dsh.display.japanese-font.v1") {
    Some(key) => normalize_japanese_font(key)
    None => "system"
  }
  set_japanese_font(selected)
}

///|
async fn local_operation(
  operation : String,
  input : Json,
) -> Result[Json, String] {
  let payload = match
    request_json(
      "/api/call",
      http_method="POST",
      body=Json::object({ "operation": Json::string(operation), "input": input }).stringify(),
    ) {
    Ok(value) => value
    Err(error) => return Err(error.message)
  }
  if !browser_json_bool(payload, "ok") {
    return Err(
      nonempty(
        browser_json_string(payload, "error"),
        "ホストがリクエストを拒否しました。",
      ),
    )
  }
  Ok(browser_json_field(payload, "result").unwrap_or(Json::null()))
}

///|
fn launch_browser_task(action : async () -> Unit) -> Unit {
  ignore(@js_async.Promise::from_async(action))
}

///|
fn launch_metadata_refresh(app : BrowserApp, force : Bool) -> Unit {
  launch_browser_task(async fn() {
    refresh_workspace_metadata(app, force~) catch {
      _ => ()
    }
  })
}

///|
fn launch_recovery(app : BrowserApp) -> Unit {
  launch_browser_task(async fn() { recover_snapshot(app) catch { _ => () } })
}

///|
fn start_stream(app : BrowserApp) -> Unit {
  match
    app.client.subscribe(
      (result, needs_snapshot) => {
        sync_from_client(app)
        if needs_snapshot {
          launch_recovery(app)
        } else if browser_json_string(result, "status") == "applied" {
          clear_connection_error(app)
          schedule_receipt_check(app)
        }
      },
      error => {
        app.connection_message = error.unwrap_or("")
        sync_from_client(app)
      },
    ) {
    Ok(_) => ()
    Err(error) => connection_error(app, error)
  }
}

///|
fn has_pending_receipt(app : BrowserApp) -> Bool {
  array_member(app.client.state(), "pending_commands").any(command => {
    string_member(command, "status") != "unconfirmed"
  })
}

///|
fn schedule_receipt_check(app : BrowserApp, delay? : Int = 6_000) -> Unit {
  match app.receipt_poll {
    Some(timer) => browser_clear_timeout(timer)
    None => ()
  }
  app.receipt_poll = None
  if !has_pending_receipt(app) {
    return
  }
  app.receipt_poll = Some(
    browser_timeout(
      () => {
        if !app.receipt_poll_running {
          app.receipt_poll_running = true
          launch_browser_task(async fn() {
            reconcile_receipts(app) catch {
              _ => app.receipt_poll_running = false
            }
          })
        }
      },
      delay,
    ),
  )
}

///|
async fn reconcile_receipts(app : BrowserApp) -> Unit {
  match app.client.reconcile_receipts() {
    Ok(_) => sync_from_client(app)
    Err(error) => {
      app.connection_message = "操作の結果を確認できませんでした。再接続して結果を確認してください。"
      connection_error(app, error)
      render_controls(app)
    }
  }
  app.receipt_poll_running = false
  schedule_receipt_check(app)
}

///|
async fn refresh_auth_catalog(app : BrowserApp, force? : Bool = false) -> Unit {
  let auth = app_auth(app)
  let key = auth_model_refresh_key(auth)
  match key {
    None => {
      app.auth_attempted_key = ""
      match app.auth_models_in_flight_key {
        Some(_) => {
          app.auth_models_in_flight_key = None
          app.auth_models_loading = false
          app.auth_models_error = false
          render_account(app)
        }
        None => ()
      }
      return
    }
    Some(value) => {
      match app.auth_models_in_flight_key {
        Some(in_flight) if in_flight == value => return
        _ => ()
      }
      if !force && app.auth_attempted_key == value {
        return
      }
      app.auth_attempted_key = value
      app.auth_models_in_flight_key = Some(value)
      app.auth_models_loading = true
      app.auth_models_error = false
      render_account(app)
      match local_operation("auth_models", Json::empty_object()) {
        Ok(_) =>
          match
            refresh_snapshot(app, reconnect=false, refresh_auth_models=false) {
            Ok(_) => ()
            Err(_) =>
              if app.auth_models_in_flight_key == Some(value) &&
                auth_model_refresh_key(app_auth(app)) == Some(value) {
                app.auth_models_error = true
              }
          }
        Err(_) =>
          if app.auth_models_in_flight_key == Some(value) &&
            auth_model_refresh_key(app_auth(app)) == Some(value) {
            app.auth_models_error = true
          }
      }
      if app.auth_models_in_flight_key == Some(value) {
        let next_key = auth_model_refresh_key(app_auth(app))
        app.auth_models_loading = false
        app.auth_models_in_flight_key = None
        if next_key is Some(next_value) && next_value != value {
          app.auth_attempted_key = ""
          ignore(refresh_auth_catalog(app))
        }
        render_account(app)
      }
    }
  }
}

///|
async fn refresh_snapshot(
  app : BrowserApp,
  reconnect? : Bool = true,
  refresh_auth_models? : Bool = true,
) -> Result[Json, String] {
  app.client.begin_connect()
  sync_from_client(app)
  let result = match app.client.snapshot() {
    Ok((_, accepted)) => accepted
    Err(error) => {
      app.client.connection_failed()
      sync_from_client(app)
      return Err(error)
    }
  }
  sync_from_client(app)
  launch_metadata_refresh(app, false)
  if app.id != "" {
    match app.client.selected_session(app.id) {
      Ok(_) => sync_from_client(app)
      Err(error) if error.contains("snapshot") =>
        match app.client.snapshot() {
          Ok(_) => {
            sync_from_client(app)
            if app.id != "" {
              match app.client.selected_session(app.id) {
                Ok(_) => sync_from_client(app)
                Err(retry_error) => return Err(retry_error)
              }
            }
          }
          Err(retry_error) => return Err(retry_error)
        }
      Err(error) => return Err(error)
    }
  }
  if reconnect {
    start_stream(app)
  }
  app.connection_message = ""
  clear_connection_error(app)
  if browser_json_string(result, "status") == "identity_changed" {
    app.action_message = "サインイン中のアカウントが変わりました。続ける前に現在の会話を確認してください。"
    sync_from_client(app)
  }
  if refresh_auth_models {
    ignore(refresh_auth_catalog(app))
  }
  Ok(result)
}

///|
async fn recover_snapshot(app : BrowserApp) -> Unit {
  if app.recovering {
    return
  }
  if browser_document_hidden() {
    app.client.persist_now()
    app.client.close_stream()
    return
  }
  app.recovering = true
  app.client.close_stream()
  match app.client.reconcile_receipts() {
    Ok(_) =>
      match refresh_snapshot(app) {
        Ok(_) => ()
        Err(error) => {
          connection_error(app, error)
          app.connection_message = "ワークスペースを更新できるまで、更新を一時停止しています。"
          render_controls(app)
        }
      }
    Err(error) => {
      connection_error(app, error)
      app.connection_message = "ワークスペースを更新できるまで、更新を一時停止しています。"
      render_controls(app)
    }
  }
  app.recovering = false
  schedule_receipt_check(app)
}

///|
fn schedule_auth_refresh(app : BrowserApp, waiting : Bool) -> Unit {
  match app.auth_poll {
    Some(timer) => browser_clear_timeout(timer)
    None => ()
  }
  app.auth_poll = None
  if waiting {
    app.auth_poll = Some(
      browser_timeout(
        () => {
          launch_browser_task(async fn() {
            match refresh_snapshot(app) {
              Ok(_) => ()
              Err(error) => connection_error(app, error)
            }
          })
        },
        2_000,
      ),
    )
  }
}

///|
async fn run_command(
  app : BrowserApp,
  operation : String,
  session_id : String?,
  input : Json,
  approval_revision? : Int = -1,
) -> Result[Json, String] {
  let receipt = match
    app.client.command(operation, session_id, input, approval_revision~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let status = browser_json_string(receipt, "status")
  if status == "rejected" {
    return Err(
      nonempty(
        browser_json_string(receipt, "error"),
        "ホストがこの操作を拒否しました。",
      ),
    )
  }
  if status == "uncertain" || status == "expired" {
    return Err(
      nonempty(
        browser_json_string(receipt, "error"),
        "ホストがこの操作の結果を確認できませんでした。",
      ),
    )
  }
  app.connection_message = ""
  match refresh_snapshot(app) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  schedule_receipt_check(app)
  Ok(receipt)
}

///|
async fn select_session(
  app : BrowserApp,
  id : String,
  explicit? : Bool = false,
) -> Unit {
  if explicit {
    app.selection += 1
  }
  let selection = app.selection
  if id == "" || id == app.id {
    return
  }
  app.client.select(Some(id))
  app.action_error = ""
  app.action_message = ""
  close_panels(app, false)
  sync_from_client(app)
  match app.client.selected_session(id) {
    Ok(_) if selection == app.selection => {
      sync_from_client(app)
      start_stream(app)
      clear_connection_error(app)
    }
    Ok(_) => ()
    Err(error) if selection == app.selection => {
      connection_error(app, error)
      launch_recovery(app)
    }
    Err(_) => ()
  }
}

///|
fn launch_select_session(
  app : BrowserApp,
  id : String,
  explicit : Bool,
) -> Unit {
  launch_browser_task(async fn() {
    select_session(app, id, explicit~) catch {
      error => connection_error(app, error.to_string())
    }
  })
}

///|
async fn create_session(
  app : BrowserApp,
  title : String,
) -> Result[Unit, String] {
  let previous_ids = app.sessions.map(session => string_member(session, "id"))
  let input = if title == "" {
    Json::empty_object()
  } else {
    Json::object({ "title": Json::string(title) })
  }
  let receipt = match run_command(app, "session_create", None, input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result = field(receipt, "result").unwrap_or(Json::null())
  let result_session = field(result, "session").unwrap_or(result)
  let mut session_id = string_member(result_session, "id")
  if session_id == "" {
    for row in app.sessions {
      let candidate = string_member(row, "id")
      if !previous_ids.contains(candidate) {
        session_id = candidate
        break
      }
    }
  }
  if session_id != "" {
    select_session(app, session_id)
  }
  Ok(())
}

///|
fn mutate(
  app : BrowserApp,
  action : async () -> Result[Unit, String],
  fence_selection? : Bool = false,
) -> Unit {
  if app.mutation {
    return
  }
  app.mutation = true
  app.action_error = ""
  app.action_message = ""
  let selected_id = app.id
  let selection = app.selection
  render_controls(app)
  render_account(app)
  launch_browser_task(async fn() {
    let result = action() catch { error => Err(error.to_string()) }
    match result {
      Ok(_) => {
        launch_metadata_refresh(app, true)
        clear_connection_error(app)
      }
      Err(error) =>
        if !fence_selection ||
          (app.id == selected_id && app.selection == selection) {
          app.action_error = error
        }
    }
    app.mutation = false
    sync_from_client(app)
  })
}

///|
fn approve_tool(app : BrowserApp, approved : Bool) -> Unit {
  let pending = field(app.snapshot, "pending_approval")
  if !has_value(pending) || app.id == "" {
    return
  }
  let session = find_session(app.sessions, app.id).unwrap_or(app.snapshot)
  let revision_number = number_member(session, "approval_revision")
  let revision = if revision_number.trunc() == revision_number {
    revision_number.to_int()
  } else {
    -1
  }
  let approval = pending.unwrap_or(Json::null())
  let call_id = string_member(approval, "call_id")
  mutate(app, async fn() {
    match
      run_command(
        app,
        "tool_approve",
        Some(app.id),
        Json::object({
          "call_id": Json::string(call_id),
          "approved": approved.to_json(),
        }),
        approval_revision=revision,
      ) {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  })
}

///|

///|
fn click_action(app : BrowserApp, event : BrowserValue) -> Unit {
  let action = dom_event_action(event)
  match action {
    "new-session" =>
      mutate(app, async fn() {
        let title = "セッション \{app.sessions.length() + 1}"
        match create_session(app, title) {
          Ok(_) => {
            dom_focus("prompt")
            Ok(())
          }
          Err(error) => Err(error)
        }
      })
    "select-session" =>
      launch_select_session(
        app,
        dom_event_attribute(event, "data-session-id"),
        true,
      )
    "fork-session" =>
      mutate(
        app,
        async fn() {
          let source_id = app.id
          let selection = app.selection
          if source_id == "" {
            return Ok(())
          }
          let receipt = match
            run_command(
              app,
              "session_fork",
              Some(source_id),
              Json::empty_object(),
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          let result = field(receipt, "result").unwrap_or(Json::null())
          let child = field(result, "session").unwrap_or(result)
          let child_id = string_member(child, "id")
          if child_id == "" {
            return Err(
              "ホストから分岐した会話が返されませんでした。",
            )
          }
          if app.id == source_id &&
            app.selection == selection &&
            string_member(app.client.state(), "selected_session") == source_id {
            select_session(app, child_id)
            if app.id == child_id {
              app.action_message = "\{source_id} から会話を分岐しました。"
              sync_from_client(app)
            }
          }
          Ok(())
        },
        fence_selection=true,
      )
    "prune-results" =>
      mutate(
        app,
        async fn() {
          let session_id = app.id
          let selection = app.selection
          if session_id == "" {
            return Ok(())
          }
          let receipt = match
            run_command(
              app,
              "session_prune_tool_results",
              Some(session_id),
              Json::empty_object(),
            ) {
            Ok(value) => value
            Err(error) => {
              if app.id != session_id || app.selection != selection {
                return Ok(())
              }
              return Err(error)
            }
          }
          if app.id != session_id || app.selection != selection {
            return Ok(())
          }
          let result = field(receipt, "result").unwrap_or(Json::null())
          let result = field(result, "result").unwrap_or(result)
          let pruned = array_member(result, "pruned")
          app.action_message = if pruned.length() > 0 {
            "\{pruned.length()} 件のツール結果を今後のモデル要求向けに短縮しました。元の出力はイベント履歴に残っています。"
          } else {
            "短縮が必要な大きさのツール結果はありません。"
          }
          sync_from_client(app)
          Ok(())
        },
        fence_selection=true,
      )
    "cancel" =>
      mutate(app, async fn() {
        match
          run_command(app, "session_cancel", Some(app.id), Json::empty_object()) {
          Ok(_) => Ok(())
          Err(error) => Err(error)
        }
      })
    "approve" => approve_tool(app, true)
    "deny" => approve_tool(app, false)
    "text-view" => {
      app.client.set_text_view(
        !browser_json_bool(app.client.state(), "text_view"),
      )
      sync_from_client(app)
    }
    "jump-latest" => {
      app.client.set_follow_latest(true)
      let client_state = app.client.state()
      if browser_json_bool(client_state, "text_view") {
        dom_scroll_to_bottom("text-transcript")
        dom_set_boolean_property("jump-latest", "hidden", true)
      } else {
        schedule_paint(app)
      }
    }
    "reconnect" => {
      dom_set_boolean_property("reconnect", "disabled", true)
      launch_browser_task(async fn() {
        reconnect(app) catch {
          error => connection_error(app, error.to_string())
        }
      })
    }
    "navigation-toggle" => {
      app.mobile_sidebar_open = !app.mobile_sidebar_open
      if app.mobile_sidebar_open {
        app.context_panel_open = false
      }
      apply_panel_state(app, focus=app.mobile_sidebar_open)
    }
    "sidebar-close" | "sidebar-scrim" => close_panels(app, true)
    "sidebar-toggle" => {
      app.sidebar_collapsed = !app.sidebar_collapsed
      apply_panel_state(app)
    }
    "context-toggle" => {
      app.context_panel_open = !app.context_panel_open
      if app.context_panel_open {
        app.mobile_sidebar_open = false
      }
      apply_panel_state(
        app,
        focus=app.context_panel_open &&
          browser_media_matches("(max-width: 1180px)"),
      )
    }
    "context-close" | "context-scrim" => close_panels(app, true)
    "auth-sign-in" => start_sign_in(app)
    "auth-sign-out" =>
      mutate(app, async fn() {
        let profile_id = string_member(
          json_object(field(app_auth(app), "account")),
          "profile_id",
        )
        if profile_id == "" {
          return Err(
            "現在の ChatGPT プロファイルを特定できません。",
          )
        }
        match
          local_operation(
            "auth_sign_out",
            Json::object({ "profile_id": Json::string(profile_id) }),
          ) {
          Ok(_) =>
            match refresh_snapshot(app) {
              Ok(_) => Ok(())
              Err(error) => Err(error)
            }
          Err(error) => Err(error)
        }
      })
    "auth-models-retry" =>
      mutate(app, async fn() {
        refresh_auth_catalog(app, force=true)
        Ok(())
      })
    "install-app" => install_app(app)
    _ => ()
  }
}

///|
fn start_sign_in(app : BrowserApp) -> Unit {
  if !browser_is_local_origin() {
    app.action_error = "ホスト Mac で dsh を開いて、ChatGPT にサインインするかアカウントを切り替えてください。"
    sync_from_client(app)
    return
  }
  if app.mutation || string_member(app_auth(app), "state") == "signing_in" {
    return
  }
  let sign_in_tab = browser_open_tab("about:blank", "_blank")
  if dom_value_is_null(sign_in_tab) {
    app.action_error = "ブラウザーがサインイン用タブをブロックしました。このローカル dsh ページのポップアップを許可して再試行してください。"
    sync_from_client(app)
    return
  }
  browser_disown_tab(sign_in_tab)
  mutate(app, async fn() {
    let result = match
      local_operation("auth_sign_in_browser", Json::empty_object()) {
      Ok(value) => value
      Err(error) => {
        browser_close_tab(sign_in_tab)
        return Err(error)
      }
    }
    let started = field(result, "started")
    if started is Some(Json::False) {
      browser_close_tab(sign_in_tab)
      app.action_message = "サインイン処理はすでに進行中です。開いているブラウザータブで完了してください。"
      return match refresh_snapshot(app) {
        Ok(_) => Ok(())
        Err(error) => Err(error)
      }
    }
    let authorization_url = browser_json_string(result, "authorization_url")
    if !(started is Some(Json::True)) ||
      !trusted_authorization_url(authorization_url) {
      browser_close_tab(sign_in_tab)
      return Err(
        "ホストから無効な ChatGPT 認証 URL が返されました。",
      )
    }
    browser_navigate_tab(sign_in_tab, authorization_url)
    match refresh_snapshot(app) {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  })
}

///|
async fn reconnect(app : BrowserApp) -> Unit {
  launch_metadata_refresh(app, true)
  match app.client.reconcile_receipts() {
    Err(error) => connection_error(app, error)
    Ok(_) =>
      match refresh_snapshot(app) {
        Ok(_) => app.connection_message = ""
        Err(error) => connection_error(app, error)
      }
  }
  dom_set_boolean_property("reconnect", "disabled", false)
  sync_from_client(app)
}

///|
fn submit_prompt(app : BrowserApp, event : BrowserValue) -> Unit {
  dom_prevent_default(event)
  let entered = dom_value("prompt")
  let prompt = entered.trim().to_owned()
  if prompt == "" || is_busy(app.snapshot) || is_read_only(app.snapshot) {
    return
  }
  mutate(app, async fn() {
    let mut session_id = app.id
    if session_id == "" {
      match create_session(app, prompt) {
        Ok(_) => session_id = app.id
        Err(error) => return Err(error)
      }
    }
    if session_id == "" {
      return Err(
        "新しいセッションを表示できません。更新してから再試行してください。",
      )
    }
    let receipt = match
      run_command(
        app,
        "session_send",
        Some(session_id),
        Json::object({ "prompt": Json::string(prompt) }),
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let status = browser_json_string(receipt, "status")
    if (status == "accepted" || status == "completed") &&
      dom_value("prompt") == entered {
      dom_set_value("prompt", "")
      app.client.save_draft("")
      resize_composer()
    }
    app.client.set_follow_latest(true)
    sync_from_client(app)
    dom_focus("prompt")
    Ok(())
  })
}

///|
fn on_document_click(app : BrowserApp, event : BrowserValue) -> Unit {
  click_action(app, event)
}

///|
fn on_keyboard(app : BrowserApp, event : BrowserValue) -> Unit {
  let key = dom_event_string(event, "key")
  if key == "Escape" && (app.mobile_sidebar_open || app.context_panel_open) {
    dom_prevent_default(event)
    close_panels(app, true)
    return
  }
  if key == "Tab" {
    let panel_id = if app.mobile_sidebar_open &&
      browser_media_matches("(max-width: 820px)") {
      "yk-mobile-navigation"
    } else if app.context_panel_open &&
      browser_media_matches("(max-width: 1180px)") {
      "yk-context-panel"
    } else {
      ""
    }
    if panel_id != "" {
      let focusable = panel_focusable_elements(panel_id)
      let count = focusable.length()
      let mut position = -1
      for index in 0..<count {
        if browser_node_is_active(focusable[index]) {
          position = index
          break
        }
      }
      let reverse = dom_event_boolean(event, "shiftKey")
      if count == 0 ||
        (reverse && position <= 0) ||
        (!reverse && position == count - 1) {
        dom_prevent_default(event)
        focus_panel_item(panel_id, if reverse { (count - 1).max(0) } else { 0 })
      }
    }
  }
}

///|
fn on_scroll(app : BrowserApp, event : BrowserValue) -> Unit {
  let text_view = browser_json_bool(app.client.state(), "text_view")
  if dom_event_target_id(event) == "text-transcript" {
    if !text_view {
      return
    }
    let follow = dom_scroll_top("text-transcript") +
      dom_measure("text-transcript", "clientHeight") >=
      dom_scroll_height("text-transcript") - 48.0
    app.client.set_follow_latest(follow)
    dom_set_boolean_property("jump-latest", "hidden", follow)
  } else {
    let follow = dom_scroll_top("transcript-scroll") +
      dom_measure("transcript-scroll", "clientHeight") >=
      dom_scroll_height("transcript-scroll") - 48.0
    app.client.set_follow_latest(follow)
    app.client.set_scroll_anchor(
      Some(dom_scroll_top("transcript-scroll").round().to_int().to_string()),
    )
    if !text_view {
      schedule_paint(app)
    }
  }
}

///|
fn install_app(app : BrowserApp) -> Unit {
  match app.install_prompt {
    Some(prompt) =>
      launch_browser_task(async fn() {
        install_prompt_choice(app, prompt) catch {
          _ => ()
        }
      })
    None => ()
  }
}

///|
async fn install_prompt_choice(app : BrowserApp, prompt : BrowserValue) -> Unit {
  ignore(@js_async.Promise::wait(browser_install_prompt(prompt)))
  app.install_prompt = None
  dom_set_boolean_property("install-app", "hidden", true)
}

///|
fn handle_model_change(app : BrowserApp) -> Unit {
  let model = dom_value("model-picker")
  if model == "" {
    return
  }
  mutate(app, async fn() {
    match
      local_operation(
        "auth_select_model",
        Json::object({ "model": Json::string(model) }),
      ) {
      Ok(_) =>
        match refresh_snapshot(app) {
          Ok(_) => {
            let mut display_name = model
            for entry in array_member(app_auth(app), "models") {
              if string_member(entry, "slug") == model {
                display_name = object_string(entry, "display_name", model)
              }
            }
            app.action_message = "\{display_name} を使用しています。"
            sync_from_client(app)
            Ok(())
          }
          Err(error) => Err(error)
        }
      Err(error) => Err(error)
    }
  })
}

///|
fn initialize_browser(app : BrowserApp) -> Unit {
  dom_set_root_style("--visible-height", "\{browser_viewport_height()}px")
  restore_japanese_font()
  dom_on_document("click", event => on_document_click(app, event))
  dom_on_document("keydown", event => on_keyboard(app, event))
  dom_on_id("composer", "submit", event => submit_prompt(app, event), false)
  dom_on_id(
    "prompt",
    "input",
    _event => {
      app.client.save_draft(dom_value("prompt"))
      resize_composer()
      render_controls(app)
    },
    false,
  )
  dom_on_id(
    "prompt",
    "keydown",
    event => {
      let enter = dom_event_string(event, "key") == "Enter"
      let shortcut = dom_event_boolean(event, "metaKey") ||
        dom_event_boolean(event, "ctrlKey")
      if enter && shortcut && !dom_event_boolean(event, "isComposing") {
        dom_prevent_default(event)
        if !dom_boolean_property("send", "disabled") {
          dom_request_submit("composer")
        }
      }
    },
    false,
  )
  dom_on_id("session-search", "input", _event => render_sessions(app), false)
  dom_on_id(
    "japanese-font",
    "change",
    _event => set_japanese_font(dom_value("japanese-font")),
    false,
  )
  dom_on_id("model-picker", "change", _event => handle_model_change(app), false)
  dom_on_id("transcript-scroll", "scroll", event => on_scroll(app, event), true)
  dom_on_id("text-transcript", "scroll", event => on_scroll(app, event), true)
  dom_on_id("canvas", "contextlost", event => dom_prevent_default(event), false)
  dom_on_id(
    "transcript-canvas",
    "contextlost",
    event => dom_prevent_default(event),
    false,
  )
  dom_on_id(
    "transcript-canvas",
    "contextrestored",
    _event => schedule_paint(app),
    false,
  )
  if dom_element_exists("transcript-area") {
    dom_resize_observer(dom_element("transcript-area"), () => {
      schedule_paint(app)
    })
  }
  dom_on_window(
    "resize",
    _event => {
      resize_composer()
      schedule_paint(app)
      apply_panel_state(app)
    },
    false,
  )
  browser_on_visual_resize(() => {
    dom_set_root_style("--visible-height", "\{browser_viewport_height()}px")
    resize_composer()
    schedule_paint(app)
  })
  dom_on_window(
    "online",
    _event => {
      launch_metadata_refresh(app, true)
      launch_recovery(app)
    },
    false,
  )
  dom_on_window(
    "beforeinstallprompt",
    event => {
      browser_event_prevent_default(event)
      app.install_prompt = Some(browser_event_prompt(event))
      dom_set_boolean_property("install-app", "hidden", false)
    },
    false,
  )
  dom_on_window(
    "appinstalled",
    _event => {
      app.install_prompt = None
      dom_set_boolean_property("install-app", "hidden", true)
    },
    false,
  )
  dom_on_window(
    "pagehide",
    _event => {
      app.client.persist_now()
      app.client.close_stream()
      match app.auth_poll {
        Some(timer) => browser_clear_timeout(timer)
        None => ()
      }
      match app.receipt_poll {
        Some(timer) => browser_clear_timeout(timer)
        None => ()
      }
    },
    false,
  )
  dom_on_window("unload", _event => app.client.dispose(), false)
  dom_on_window(
    "pageshow",
    _event => {
      if !browser_document_hidden() {
        launch_metadata_refresh(app, true)
        launch_recovery(app)
      }
    },
    false,
  )
  dom_on_document("visibilitychange", _event => {
    if !browser_document_hidden() {
      launch_metadata_refresh(app, true)
      launch_recovery(app)
    } else {
      app.client.persist_now()
      app.client.close_stream()
    }
  })
  dom_on_media("(max-width: 820px)", () => apply_panel_state(app))
  dom_on_media("(max-width: 1180px)", () => apply_panel_state(app))
  apply_panel_state(app)
  ignore(
    dom_interval(
      () => if !browser_document_hidden() { launch_metadata_refresh(app, true) },
      10_000,
    ),
  )
  if browser_service_worker_available() {
    launch_browser_task(async fn() {
      register_service_worker() catch {
        _ => ()
      }
    })
  }
  sync_from_client(app, restore_draft=true)
  launch_browser_task(async fn() {
    initial_snapshot(app) catch {
      error => connection_error(app, error.to_string())
    }
  })
}

///|
async fn register_service_worker() -> Unit {
  ignore(
    @js_async.Promise::wait(
      browser_service_worker_register("/sw.js", "/", "module"),
    ),
  )
}

///|
async fn initial_snapshot(app : BrowserApp) -> Unit {
  match refresh_snapshot(app) {
    Ok(_) => {
      match app.client.reconcile_receipts() {
        Ok(_) => sync_from_client(app)
        Err(error) => connection_error(app, error)
      }
      if app.id == "" && !app.sessions.is_empty() {
        let mut latest = ""
        for session in app.sessions {
          latest = string_member(session, "id")
        }
        select_session(app, latest)
      }
    }
    Err(error) => {
      app.client.close_stream()
      connection_error(app, error)
    }
  }
  render_controls(app)
  render_account(app)
}
