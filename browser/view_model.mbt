///|
/// Safe display data extracted from a session snapshot. The browser renderer
/// receives plain text and never interprets message content as markup.
pub struct DisplayMessage {
  label : String
  text : String
}

///|
/// Safe, localized context panel values derived from a current session and
/// connection state.
pub struct WorkspaceContext {
  summary : String
  status : String
  turn : String
  history : String
  source : String
  parent : String
  read_only : Bool
  host_status : String
  shell_status : String
  connection_state : String
}

///|
/// Validated strings used by the browser's repository and provider context.
pub struct WorkspaceMetadata {
  project : String
  repository : String
  branch : String
  provider_model : String
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn string_member(value : Json, key : String) -> String {
  match field(value, key) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn number_member(value : Json, key : String) -> Double {
  match field(value, key) {
    Some(Json::Number(number, ..)) => number
    _ => 0.0
  }
}

///|
fn array_member(value : Json, key : String) -> Array[Json] {
  match field(value, key) {
    Some(Json::Array(values)) => values
    _ => []
  }
}

///|
fn has_value(value : Json?) -> Bool {
  match value {
    None | Some(Json::Null) => false
    Some(Json::False) => false
    Some(Json::True) => true
    Some(Json::String(text)) => text != ""
    Some(Json::Number(number, ..)) => number != 0.0
    Some(_) => true
  }
}

///|
fn nonempty(value : String, fallback : String) -> String {
  if value == "" {
    fallback
  } else {
    value
  }
}

///|
pub fn is_busy(session : Json) -> Bool {
  let has_approval = has_value(field(session, "pending_approval"))
  let active = match string_member(session, "status") {
    "running" | "queued" | "awaiting_approval" => true
    _ => false
  }
  has_approval || active
}

///|
pub fn is_read_only(session : Json) -> Bool {
  string_member(session, "source_format") == "deepseek-session-v4"
}

///|
pub fn has_tool_results(session : Json) -> Bool {
  let projected = field(session, "has_tool_results") is Some(Json::True)
  projected ||
  array_member(session, "events").any(event => {
    string_member(event, "type") == "tool/result"
  })
}

///|
pub fn status_label(session : Json) -> String {
  if has_value(field(session, "pending_approval")) ||
    string_member(session, "status") == "awaiting_approval" {
    return "承認待ち"
  }
  let raw = string_member(session, "status")
  let label = match raw {
    "idle" => "準備完了"
    "running" => "実行中"
    "queued" => "待機中"
    "completed" => "完了"
    "failed" => "失敗"
    "cancelled" => "キャンセル済み"
    _ if raw != "" => raw
    _ => "準備完了"
  }
  if is_read_only(session) {
    "読み取り専用 · " + label
  } else {
    label
  }
}

///|
pub fn session_list(result : Json) -> Result[Array[Json], String] {
  let rows = match result {
    Json::Array(values) => values
    _ =>
      match field(result, "sessions") {
        Some(Json::Array(values)) => values
        _ => return Err("The server returned an invalid session list.")
      }
  }
  let valid : Array[Json] = []
  for row in rows {
    match row {
      Json::Object(fields) if fields.get("id") is Some(Json::String(_)) =>
        valid.push(row)
      _ => ()
    }
  }
  Ok(valid)
}

///|
/// Reject an older poll after a newer mutation response has been accepted.
pub fn accepts_snapshot(candidate : Json, current : Json?) -> Bool {
  let current = match current {
    Some(value) => value
    None => return true
  }
  if string_member(candidate, "id") != string_member(current, "id") {
    return true
  }
  let candidate_turn = number_member(candidate, "turn_id")
  let current_turn = number_member(current, "turn_id")
  if candidate_turn < current_turn {
    return false
  }
  match
    (field(candidate, "stream_revision"), field(current, "stream_revision")) {
    (
      Some(Json::Number(candidate_revision, ..)),
      Some(Json::Number(current_revision, ..)),
    ) if candidate_turn == current_turn && candidate_revision < current_revision =>
      return false
    _ => ()
  }
  match (field(candidate, "events"), field(current, "events")) {
    (Some(Json::Array(candidate_events)), Some(Json::Array(current_events))) if candidate_events.length() <
      current_events.length() => false
    _ => true
  }
}

///|
pub fn pretty_arguments(value : Json?) -> String {
  match value {
    None | Some(Json::Null) => "{}"
    Some(Json::String(raw)) => format_json_or_original(raw)
    Some(other) => other.stringify(indent=2)
  }
}

///|
fn format_json_or_original(raw : String) -> String {
  let parsed = @json.parse(raw) catch { _ => return raw }
  parsed.stringify(indent=2)
}

///|
pub fn run_error(session : Json) -> String {
  if string_member(session, "status") != "failed" {
    return ""
  }
  match field(session, "error") {
    Some(Json::String(error)) => return error
    _ => ()
  }
  let turn = number_member(session, "turn_id")
  let events = array_member(session, "events")
  let mut index = events.length() - 1
  while index >= 0 {
    let event = events[index]
    index -= 1
    if number_member(event, "turn_id") != turn {
      continue
    }
    match field(event, "data") {
      Some(data) =>
        match field(data, "error") {
          Some(Json::String(error)) if error != "" => return error
          _ => ()
        }
      _ => ()
    }
  }
  if is_read_only(session) {
    "読み込んだ履歴のターンが失敗しました。この会話を続けることはできません。"
  } else {
    "ターンに失敗しました。会話を確認して、新しいメッセージを送信できます。"
  }
}

///|
fn pruned_call(session : Json, call_id : String) -> Bool {
  if call_id == "" {
    return false
  }
  for event in array_member(session, "events") {
    if string_member(event, "type") == "tool/result/pruned" {
      match field(event, "data") {
        Some(data) if string_member(data, "call_id") == call_id => return true
        _ => ()
      }
    }
  }
  false
}

///|
pub fn display_messages(session : Json) -> Array[DisplayMessage] {
  let rows : Array[DisplayMessage] = []
  match field(session, "todos") {
    Some(Json::Array(todos)) => {
      let lines : Array[String] = []
      if todos.is_empty() {
        lines.push("タスクはありません。")
      }
      for todo in todos {
        let marker = match string_member(todo, "status") {
          "in_progress" => "[~] "
          "completed" => "[x] "
          _ => "[ ] "
        }
        lines.push(marker + string_member(todo, "content"))
      }
      rows.push({ label: "タスク", text: lines.join("\n"), })
    }
    _ => ()
  }
  for message in array_member(session, "messages") {
    let role = string_member(message, "role")
    if role == "system" || role == "developer" {
      continue
    }
    let provisional = match field(message, "provisional") {
      Some(Json::True) => true
      _ => false
    }
    let stream_status = if string_member(message, "stream_status") == "partial" {
      "一部表示"
    } else {
      "生成中"
    }
    let reasoning = string_member(message, "reasoning")
    if reasoning != "" {
      rows.push({
        label: if provisional {
          "推論 · " + stream_status
        } else {
          "推論"
        },
        text: reasoning,
      })
    }
    let content = string_member(message, "content")
    if content != "" {
      let call_id = string_member(message, "tool_call_id")
      let display_label = string_member(message, "display_label")
      let label = if display_label != "" {
        display_label
      } else if provisional && role == "assistant" {
        "アシスタント · " + stream_status
      } else if role == "tool" && pruned_call(session, call_id) {
        "ツール結果 · モデル入力用に短縮"
      } else {
        match role {
          "user" => "あなた"
          "assistant" => "アシスタント"
          "tool" => "ツール結果"
          _ => "メッセージ"
        }
      }
      rows.push({ label, text: content, })
    }
    for call in array_member(message, "tool_calls") {
      let name = string_member(call, "name")
      let label = "ツール要求 · " + name
      let arguments = match field(call, "arguments") {
        Some(Json::String(_)) => pretty_arguments(field(call, "arguments"))
        Some(Json::Null) | None => "{}"
        Some(other) => other.stringify(indent=2)
      }
      if string_member(call, "kind") == "custom" {
        let raw = match field(call, "arguments") {
          Some(Json::String(raw)) => raw
          Some(Json::Null) | None => ""
          Some(other) => other.stringify()
        }
        rows.push({ label: "カスタム呼び出し · " + name, text: raw, })
      } else {
        rows.push({ label, text: arguments, })
      }
    }
  }
  let live_text = string_member(session, "_ui_live_text")
  if live_text != "" {
    rows.push({ label: "アシスタント · 生成中", text: live_text, })
  }
  rows
}

///|
pub fn auth_model_refresh_key(auth : Json) -> String? {
  if string_member(auth, "state") != "connected" {
    return None
  }
  match field(auth, "models") {
    Some(Json::Array(models)) if !models.is_empty() => return None
    _ => ()
  }
  match field(auth, "account") {
    Some(account) =>
      match field(account, "profile_id") {
        Some(Json::String(profile)) if profile != "" => Some(profile)
        _ => Some("connected")
      }
    _ => Some("connected")
  }
}

///|
/// Accept only the OpenAI authorization endpoint before navigating a
/// user-initiated sign-in tab.
pub fn trusted_authorization_url(value : String) -> Bool {
  let prefix = "https://auth.openai.com/api/accounts/authorize"
  value.has_prefix(prefix) &&
  (value.length() == prefix.length() || value[prefix.length()] == '?') &&
  !value.contains("#")
}

///|
pub fn japanese_font_stack(key : String) -> String {
  match key {
    "system" | "hiragino" =>
      "\"Hiragino Sans\", \"Yu Gothic UI\", \"Yu Gothic\", Meiryo, sans-serif"
    "yugothic" =>
      "\"Yu Gothic UI\", \"Yu Gothic\", Meiryo, \"Hiragino Sans\", sans-serif"
    "meiryo" => "Meiryo, \"Yu Gothic UI\", \"Hiragino Sans\", sans-serif"
    "noto" =>
      "\"Noto Sans JP\", \"Hiragino Sans\", \"Yu Gothic UI\", Meiryo, sans-serif"
    _ => ""
  }
}

///|
pub fn normalize_japanese_font(key : String) -> String {
  match key {
    "system" | "hiragino" | "yugothic" | "meiryo" | "noto" => key
    _ => "system"
  }
}

///|
pub fn workspace_context(
  session : Json,
  connection : String,
  has_error : Bool,
) -> WorkspaceContext {
  let active = string_member(session, "id") != ""
  let imported = is_read_only(session)
  let messages = array_member(session, "messages")
  let events = array_member(session, "events")
  let connection_label = match connection {
    "synced" => "接続済み · ライブ更新"
    "ready" => "接続済み · 更新を確認中"
    "connecting" => "ローカルホストに接続中…"
    "offline" => "切断されました · 再接続してください"
    "needs_resync" => "ワークスペースを更新中…"
    "failed" => "ローカルホストを利用できません"
    _ => "ローカルホストを待っています…"
  }
  let turn_count = number_member(session, "turn_id")
  let turn = if active && turn_count > 0.0 {
    "\{turn_count.to_int()} ターン目 · ステップ \{number_member(session, "step").to_int()}"
  } else if active {
    "ターンはまだありません"
  } else {
    "—"
  }
  let host_status = if has_error {
    "接続が中断されました。再接続してワークスペースを更新してください。"
  } else {
    "ローカルホスト · " + connection_label
  }
  {
    summary: if active {
      nonempty(string_member(session, "title"), "無題の会話")
    } else {
      "会話を選ぶと現在の状態を表示します。"
    },
    status: if active {
      status_label(session)
    } else {
      "会話が選択されていません"
    },
    turn,
    history: if active {
      "\{messages.length()} 件のメッセージ · \{events.length()} 件のイベント"
    } else {
      "—"
    },
    source: if active {
      if imported {
        "Session v4 の読み込み履歴 · 読み取り専用"
      } else {
        "ローカルの会話"
      }
    } else {
      "利用できません"
    },
    parent: if active {
      match field(session, "parent_session_id") {
        Some(Json::String(parent)) => parent
        _ => "なし"
      }
    } else {
      "—"
    },
    read_only: active && imported,
    host_status,
    shell_status: if has_error {
      "接続が中断されました · 再接続してください"
    } else {
      connection_label
    },
    connection_state: if has_error {
      "offline"
    } else if connection == "" {
      "connecting"
    } else {
      connection
    },
  }
}

///|
pub fn workspace_metadata(metadata : Json, auth : Json) -> WorkspaceMetadata {
  let project = string_member(metadata, "project").trim().to_owned()
  let project = if project == "" { "ワークスペース" } else { project }
  let repository = field(metadata, "repository")
  let repo_is_object = match repository {
    Some(Json::Object(_)) => true
    _ => false
  }
  let repository_name = if repo_is_object {
    match repository {
      Some(value) =>
        nonempty(string_member(value, "name"), "Git リポジトリ")
      _ => "Git リポジトリ"
    }
  } else {
    "Git リポジトリではありません"
  }
  let branch = if repo_is_object {
    match repository {
      Some(value) =>
        match field(value, "branch") {
          Some(Json::String(name)) =>
            if has_value(field(value, "detached")) {
              "HEAD 分離 · " + name
            } else {
              name
            }
          _ => "ブランチを取得できません"
        }
      _ => "ブランチを取得できません"
    }
  } else {
    "—"
  }
  let provider = nonempty(
    string_member(metadata, "provider"),
    "不明なプロバイダー",
  )
  let auth_selected_model = if provider == "ChatGPT" {
    string_member(auth, "selected_model")
  } else {
    ""
  }
  let model = nonempty(
    auth_selected_model,
    nonempty(string_member(metadata, "model"), "モデル未選択"),
  )
  {
    project,
    repository: repository_name,
    branch,
    provider_model: "\{provider} · \{model}",
  }
}
