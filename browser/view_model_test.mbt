///|
fn parse_fixture(source : String) -> Json {
  @json.parse(source) catch {
    _ => abort("valid browser test fixture")
  }
}

///|
test "busy and read-only session status stays clear in Japanese" {
  assert_true(
    @browser.is_busy(parse_fixture("{\"status\":\"awaiting_approval\"}")),
  )
  assert_true(
    @browser.is_busy(
      parse_fixture(
        "{\"status\":\"idle\",\"pending_approval\":{\"call_id\":\"c1\"}}",
      ),
    ),
  )
  assert_false(@browser.is_busy(parse_fixture("{\"status\":\"completed\"}")))
  let imported = parse_fixture(
    "{\"status\":\"completed\",\"source_format\":\"deepseek-session-v4\"}",
  )
  assert_true(@browser.is_read_only(imported))
  assert_eq(@browser.status_label(imported), "読み取り専用 · 完了")
  assert_eq(
    @browser.status_label(parse_fixture("{\"status\":\"awaiting_approval\"}")),
    "承認待ち",
  )
}

///|
test "tool-result pruning uses a redacted presence flag or legacy result marker" {
  assert_true(
    @browser.has_tool_results(parse_fixture("{\"has_tool_results\":true}")),
  )
  assert_true(
    @browser.has_tool_results(
      parse_fixture("{\"events\":[{\"type\":\"tool/result\"}] }"),
    ),
  )
  assert_false(@browser.has_tool_results(parse_fixture("{\"events\":[]}")))
}

///|
test "old snapshots cannot replace a newer mutation or stream projection" {
  let current = parse_fixture(
    "{\"id\":\"s1\",\"turn_id\":3,\"stream_revision\":18,\"events\":[1,2,3]}",
  )
  assert_false(
    @browser.accepts_snapshot(
      parse_fixture("{\"id\":\"s1\",\"turn_id\":2,\"events\":[1,2,3]}"),
      Some(current),
    ),
  )
  assert_false(
    @browser.accepts_snapshot(
      parse_fixture(
        "{\"id\":\"s1\",\"turn_id\":3,\"stream_revision\":17,\"events\":[1,2,3]}",
      ),
      Some(current),
    ),
  )
  assert_false(
    @browser.accepts_snapshot(
      parse_fixture(
        "{\"id\":\"s1\",\"turn_id\":3,\"stream_revision\":19,\"events\":[1,2]}",
      ),
      Some(current),
    ),
  )
  assert_true(
    @browser.accepts_snapshot(
      parse_fixture(
        "{\"id\":\"s1\",\"turn_id\":3,\"stream_revision\":19,\"events\":[1,2,3,4]}",
      ),
      Some(current),
    ),
  )
  assert_true(
    @browser.accepts_snapshot(
      parse_fixture("{\"id\":\"s2\",\"turn_id\":1,\"events\":[]}"),
      Some(current),
    ),
  )
  assert_true(@browser.accepts_snapshot(current, None))
}

///|
test "failed-turn errors use only the active turn and imported sessions stay read-only" {
  let failed = parse_fixture(
    "{\"status\":\"failed\",\"turn_id\":2,\"events\":[{\"turn_id\":1,\"data\":{\"error\":\"old\"}},{\"turn_id\":2,\"data\":{\"error\":\"provider failed\"}}]}",
  )
  assert_eq(@browser.run_error(failed), "provider failed")
  assert_eq(@browser.run_error(parse_fixture("{\"status\":\"running\"}")), "")
  let imported = parse_fixture(
    "{\"status\":\"failed\",\"turn_id\":1,\"source_format\":\"deepseek-session-v4\",\"events\":[]}",
  )
  assert_true(
    @browser.run_error(imported).contains("続けることはできません"),
  )
}

///|
test "accessible transcript preserves literal content, pruning labels, and provisional state" {
  let session = parse_fixture(
    "{\"events\":[{\"type\":\"tool/result/pruned\",\"data\":{\"call_id\":\"c1\"}}],\"messages\":[{\"role\":\"system\",\"content\":\"hidden\"},{\"role\":\"assistant\",\"reasoning\":\"thinking\",\"content\":\"answer\",\"provisional\":true,\"stream_status\":\"partial\",\"tool_calls\":[{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"},{\"kind\":\"custom\",\"name\":\"terminal\",\"arguments\":\"<script>literal</script>\"}]},{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"full original output\"}]}",
  )
  let rows = @browser.display_messages(session)
  assert_eq(rows.map(message => message.label), [
    "推論 · 一部表示", "アシスタント · 一部表示", "ツール要求 · read_file",
    "カスタム呼び出し · terminal", "ツール結果 · モデル入力用に短縮",
  ])
  assert_eq(rows[1].text, "answer")
  assert_true(rows[2].text.contains("README.md"))
  assert_eq(rows[3].text, "<script>literal</script>")
  assert_eq(rows[4].text, "full original output")
}

///|
test "hook contexts retain a distinct accessible label" {
  let session = parse_fixture(
    "{\"messages\":[{\"role\":\"user\",\"content\":\"hook detail\",\"source\":{\"kind\":\"hooks-claude-code\"},\"display_label\":\"フック補足\"}]}",
  )
  let rows = @browser.display_messages(session)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].label, "フック補足")
  assert_eq(rows[0].text, "hook detail")
}

///|
test "visible task list follows selected session data and stale polls cannot erase it" {
  let selected = parse_fixture(
    "{\"id\":\"todo-ui\",\"turn_id\":2,\"events\":[1,2,3,4],\"todos\":[{\"content\":\"Implement feature\",\"status\":\"in_progress\"},{\"content\":\"Verify\",\"status\":\"pending\"}],\"messages\":[{\"role\":\"assistant\",\"content\":\"Working\"}]}",
  )
  let rows = @browser.display_messages(selected)
  assert_eq(rows[0].label, "タスク")
  assert_eq(rows[0].text, "[~] Implement feature\n[ ] Verify")
  assert_eq(rows[1].label, "アシスタント")
  let stale = parse_fixture(
    "{\"id\":\"todo-ui\",\"turn_id\":2,\"events\":[1,2,3],\"todos\":[],\"messages\":[]}",
  )
  assert_false(@browser.accepts_snapshot(stale, Some(selected)))
}

///|
test "session lists validate shape and filter malformed rows" {
  let sessions = @browser.session_list(
    parse_fixture("{\"sessions\":[{\"id\":\"s1\"},null,{}, {\"id\":3}] }"),
  )
  match sessions {
    Ok(rows) => {
      assert_eq(rows.length(), 1)
      match rows[0] {
        Json::Object(fields) =>
          assert_eq(fields.get("id"), Some(Json::string("s1")))
        _ => fail("session row should be an object")
      }
    }
    Err(_) => fail("valid session projection should be accepted")
  }
  assert_true(@browser.session_list(parse_fixture("{}")) is Err(_))
}

///|
test "auth refresh and Japanese font preferences keep stable UI choices" {
  let auth = parse_fixture(
    "{\"state\":\"connected\",\"account\":{\"profile_id\":\"profile-a\"},\"models\":[]}",
  )
  assert_eq(@browser.auth_model_refresh_key(auth), Some("profile-a"))
  assert_eq(
    @browser.auth_model_refresh_key(parse_fixture("{\"state\":\"signed_out\"}")),
    None,
  )
  assert_eq(
    @browser.auth_model_refresh_key(
      parse_fixture("{\"state\":\"connected\",\"models\":[{\"slug\":\"m\"}] }"),
    ),
    None,
  )
  assert_eq(
    @browser.auth_model_refresh_key(
      parse_fixture("{\"state\":\"connected\",\"account\":null,\"models\":[]}"),
    ),
    Some("connected"),
  )
  assert_eq(
    @browser.auth_model_refresh_key(
      parse_fixture("{\"state\":\"signing_in\",\"models\":[]}"),
    ),
    None,
  )
  assert_true(
    @browser.trusted_authorization_url(
      "https://auth.openai.com/api/accounts/authorize?client_id=fixture",
    ),
  )
  assert_false(
    @browser.trusted_authorization_url(
      "https://auth.openai.com.evil.test/api/accounts/authorize",
    ),
  )
  assert_false(
    @browser.trusted_authorization_url(
      "https://auth.openai.com/api/accounts/authorize#fragment",
    ),
  )
  assert_true(@browser.japanese_font_stack("yugothic").contains("Yu Gothic"))
  assert_true(@browser.japanese_font_stack("noto").contains("Noto Sans JP"))
  assert_eq(@browser.japanese_font_stack("unknown"), "")
  assert_eq(@browser.normalize_japanese_font("noto"), "noto")
  assert_eq(@browser.normalize_japanese_font("invalid"), "system")
}

///|
test "workspace context keeps imported histories read-only and connection state localized" {
  let session = parse_fixture(
    "{\"id\":\"s1\",\"title\":\"履歴\",\"status\":\"failed\",\"source_format\":\"deepseek-session-v4\",\"turn_id\":2,\"step\":3,\"parent_session_id\":\"parent\",\"messages\":[{},{}],\"events\":[{}]}",
  )
  let context = @browser.workspace_context(session, "offline", true)
  assert_eq(context.summary, "履歴")
  assert_eq(context.status, "読み取り専用 · 失敗")
  assert_eq(context.turn, "2 ターン目 · ステップ 3")
  assert_eq(context.history, "2 件のメッセージ · 1 件のイベント")
  assert_eq(
    context.source,
    "Session v4 の読み込み履歴 · 読み取り専用",
  )
  assert_eq(context.parent, "parent")
  assert_true(context.read_only)
  assert_true(context.host_status.contains("接続が中断"))
  assert_eq(context.connection_state, "offline")
  let empty = @browser.workspace_context(Json::object({}), "", false)
  assert_false(empty.read_only)
  assert_eq(empty.status, "会話が選択されていません")
  assert_eq(empty.connection_state, "connecting")
}

///|
test "workspace metadata validates repository and model presentation" {
  let metadata = parse_fixture(
    "{\"project\":\" sample-project \",\"repository\":{\"name\":\"repo\",\"branch\":\"0123456789ab\",\"detached\":true},\"provider\":\"ChatGPT\",\"model\":\"old\"}",
  )
  let auth = parse_fixture("{\"selected_model\":\"new\"}")
  let view = @browser.workspace_metadata(metadata, auth)
  assert_eq(view.project, "sample-project")
  assert_eq(view.repository, "repo")
  assert_eq(view.branch, "HEAD 分離 · 0123456789ab")
  assert_eq(view.provider_model, "ChatGPT · new")
  let no_repository = @browser.workspace_metadata(
    parse_fixture("{}"),
    Json::null(),
  )
  assert_eq(
    no_repository.repository,
    "Git リポジトリではありません",
  )
  assert_eq(
    no_repository.provider_model,
    "不明なプロバイダー · モデル未選択",
  )
}
