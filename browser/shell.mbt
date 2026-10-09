///|
fn html_attribute(name : String, value : String) -> @yami_kumo.Attribute {
  match @yami_kumo.attr(name, value) {
    Ok(attribute) => attribute
    Err(_) => abort("static dsh HTML attribute is valid")
  }
}

///|
fn html_boolean_attribute(name : String) -> @yami_kumo.Attribute {
  match @yami_kumo.boolean_attr(name) {
    Ok(attribute) => attribute
    Err(_) => abort("static dsh HTML boolean attribute is valid")
  }
}

///|
fn html_element(
  tag : String,
  attributes : Array[@yami_kumo.Attribute],
  children : Array[@yami_kumo.Html],
) -> @yami_kumo.Html {
  match @yami_kumo.element(tag, attributes, children) {
    Ok(node) => node
    Err(_) => abort("static dsh HTML tree is safe")
  }
}

///|
fn html_text(value : String) -> @yami_kumo.Html {
  @yami_kumo.text(value)
}

///|
fn html_class(value : String) -> @yami_kumo.Attribute {
  html_attribute("class", value)
}

///|
fn html_id(value : String) -> @yami_kumo.Attribute {
  html_attribute("id", value)
}

///|
fn action_attribute(value : String) -> @yami_kumo.Attribute {
  html_attribute("data-action", value)
}

///|
fn html_button(
  id : String,
  action : String,
  label : String,
  class_name : String,
  variant : @yami_kumo.ButtonVariant,
  disabled? : Bool = false,
  button_type? : String = "button",
  extra_attrs? : Array[@yami_kumo.Attribute] = [],
) -> @yami_kumo.Html {
  let attributes = [html_id(id), action_attribute(action)]
  attributes.append(extra_attrs)
  @yami_kumo.button(
    html_text(label),
    variant~,
    disabled~,
    button_type~,
    class_name~,
    attrs=attributes,
  )
}

///|
fn sr_only(label : String) -> @yami_kumo.Html {
  html_element("span", [html_class("sr-only")], [html_text(label)])
}

///|
fn eyebrow(label : String) -> @yami_kumo.Html {
  html_element("span", [html_class("eyebrow")], [html_text(label)])
}

///|
fn definition_row(
  label : String,
  id : String,
  initial : String,
) -> @yami_kumo.Html {
  html_element("div", [], [
    html_element("dt", [], [html_text(label)]),
    html_element("dd", [html_id(id)], [html_text(initial)]),
  ])
}

///|
fn search_field() -> @yami_kumo.Html {
  let input = @yami_kumo.input(
    id="session-search",
    placeholder="会話を検索",
    class_name="session-search-input",
    attrs=[
      html_attribute("type", "search"),
      html_id("session-search"),
      html_attribute("autocomplete", "off"),
    ],
  )
  html_element("label", [html_class("session-search")], [
    sr_only("会話を検索"),
    html_element(
      "span",
      [html_class("session-search-icon"), html_attribute("aria-hidden", "true")],
      [html_text("⌕")],
    ),
    input,
  ])
}

///|
fn navigation_sidebar() -> @yami_kumo.Html {
  html_element("div", [html_class("dsh-sidebar")], [
    html_element("div", [html_class("sidebar-heading")], [
      html_element("div", [], [
        eyebrow("プロジェクト"),
        html_element("strong", [html_id("project-name")], [
          html_text("ワークスペース"),
        ]),
      ]),
      html_button(
        "mobile-navigation-close",
        "sidebar-close",
        "×",
        "icon-button mobile-navigation-close",
        @yami_kumo.ButtonVariant::Ghost,
        extra_attrs=[
          html_attribute(
            "aria-label", "会話ナビゲーションを閉じる",
          ),
          html_attribute("aria-controls", "yk-mobile-navigation"),
          html_attribute("aria-expanded", "false"),
        ],
      ),
    ]),
    html_button(
      "new-session",
      "new-session",
      "＋ 新しい会話",
      "new-session",
      @yami_kumo.ButtonVariant::Primary,
    ),
    html_element("div", [html_class("sidebar-heading session-list-heading")], [
      eyebrow("最近の会話"),
    ]),
    html_element(
      "nav",
      [
        html_id("sessions"),
        html_class("session-list"),
        html_attribute("aria-label", "会話の一覧"),
      ],
      [
        html_element("p", [html_class("empty-list")], [
          html_text("会話を読み込んでいます…"),
        ]),
      ],
    ),
    html_button(
      "settings-open-sidebar",
      "settings-open",
      "⚙  設定",
      "settings-nav-trigger",
      @yami_kumo.ButtonVariant::Ghost,
      extra_attrs=[
        html_attribute("aria-controls", "settings-page"),
        html_attribute("aria-expanded", "false"),
      ],
    ),
    html_element("p", [html_class("sidebar-note")], [
      html_text("ローカルエージェントのワークスペース"),
    ]),
  ])
}

///|
fn context_panel() -> @yami_kumo.Html {
  html_element("div", [html_class("context-content")], [
    html_element("div", [html_class("context-heading")], [
      html_element("div", [], [
        eyebrow("現在の会話"),
        html_element("h2", [html_id("context-title")], [
          html_text("会話の詳細"),
        ]),
      ]),
      html_button(
        "context-close",
        "context-close",
        "×",
        "icon-button",
        @yami_kumo.ButtonVariant::Ghost,
        extra_attrs=[
          html_attribute("aria-label", "会話の詳細を閉じる"),
          html_attribute("aria-controls", "yk-context-panel"),
          html_attribute("aria-expanded", "false"),
        ],
      ),
    ]),
    html_element(
      "p",
      [html_id("context-summary"), html_class("context-summary")],
      [html_text("会話を選ぶと現在の状態が表示されます。")],
    ),
    html_element("dl", [html_class("context-facts")], [
      definition_row(
        "状態", "context-status", "会話が選択されていません",
      ),
      definition_row("ターン", "context-turn", "—"),
      definition_row("履歴", "context-history", "—"),
      definition_row("保存元", "context-source", "ローカルの会話"),
      definition_row("親セッション", "context-parent", "なし"),
      definition_row("リポジトリ", "repository-name", "取得中…"),
      definition_row("ブランチ", "branch-name", "—"),
    ]),
    html_element(
      "p",
      [
        html_id("context-read-only"),
        html_class("context-note"),
        html_boolean_attribute("hidden"),
      ],
      [
        html_text(
          "読み込んだ履歴は読み取り専用です。会話を確認できますが、送信やターンのキャンセルはできません。",
        ),
      ],
    ),
    html_element(
      "label",
      [html_class("font-control"), html_attribute("for", "japanese-font")],
      [
        html_element("span", [], [html_text("日本語フォント")]),
        html_element(
          "select",
          [html_id("japanese-font"), action_attribute("font-change")],
          [
            html_element("option", [html_attribute("value", "system")], [
              html_text("システム標準"),
            ]),
            html_element("option", [html_attribute("value", "hiragino")], [
              html_text("ヒラギノ角ゴ"),
            ]),
            html_element("option", [html_attribute("value", "yugothic")], [
              html_text("游ゴシック"),
            ]),
            html_element("option", [html_attribute("value", "meiryo")], [
              html_text("メイリオ"),
            ]),
            html_element("option", [html_attribute("value", "noto")], [
              html_text("Noto Sans JP"),
            ]),
          ],
        ),
      ],
    ),
    html_element("p", [html_class("context-note")], [
      html_text(
        "セッションログの外部アップロード機能はありません（既定で無効です）。",
      ),
    ]),
    html_element(
      "p",
      [html_id("context-host-status"), html_class("context-host-status")],
      [html_text("ローカルホストに接続中…")],
    ),
  ])
}

///|
fn chatgpt_account_panel() -> @yami_kumo.Html {
  html_element(
    "section",
    [
      html_id("account-bar"),
      html_class("account-bar settings-account-card"),
      html_attribute("aria-label", "ChatGPT アカウントとモデル"),
      html_boolean_attribute("hidden"),
    ],
    [
      html_element("div", [html_class("account-summary")], [
        html_element(
          "span",
          [
            html_id("auth-status"),
            html_class("account-status"),
            html_attribute("data-state", "signed_out"),
          ],
          [html_text("ChatGPT 未接続")],
        ),
        html_element(
          "span",
          [html_id("auth-detail"), html_class("account-detail")],
          [],
        ),
        html_element(
          "span",
          [html_id("auth-guidance"), html_class("account-detail")],
          [],
        ),
        html_element(
          "a",
          [
            html_id("usage-link"),
            html_class("account-link"),
            html_attribute("href", "https://chatgpt.com/settings/usage"),
            html_attribute("target", "_blank"),
            html_attribute("rel", "noopener noreferrer"),
            html_boolean_attribute("hidden"),
          ],
          [html_text("ChatGPT の利用状況を開く")],
        ),
      ]),
      html_element("div", [html_class("account-actions")], [
        html_element(
          "label",
          [html_class("model-control"), html_attribute("for", "model-picker")],
          [
            html_element("span", [], [html_text("使用するモデル")]),
            html_element(
              "select",
              [
                html_id("model-picker"),
                action_attribute("model-change"),
                html_boolean_attribute("disabled"),
              ],
              [
                html_element("option", [html_attribute("value", "")], [
                  html_text("ChatGPT に接続してモデルを表示"),
                ]),
              ],
            ),
          ],
        ),
        html_button(
          "auth-sign-in",
          "auth-sign-in",
          "ChatGPT にサインイン",
          "quiet-button",
          @yami_kumo.Secondary,
        ),
        html_button(
          "auth-models-retry",
          "auth-models-retry",
          "モデルを再読み込み",
          "quiet-button",
          @yami_kumo.Secondary,
          disabled=true,
        ),
        html_button(
          "auth-sign-out",
          "auth-sign-out",
          "接続を解除",
          "quiet-button",
          @yami_kumo.Secondary,
          disabled=true,
        ),
        html_button(
          "install-app",
          "install-app",
          "アプリをインストール",
          "quiet-button",
          @yami_kumo.Secondary,
        ),
      ]),
    ],
  )
}

///|
fn conversation_page() -> @yami_kumo.Html {
  html_element(
    "div",
    [html_id("conversation-page"), html_class("conversation-page")],
    [
      html_element(
        "a",
        [html_class("skip-link"), html_attribute("href", "#transcript-scroll")],
        [html_text("会話へ移動")],
      ),
      html_element("header", [html_class("session-header")], [
        html_element("div", [html_class("session-heading")], [
          html_element("h1", [html_id("session-title")], [
            html_text("エージェントのワークスペース"),
          ]),
          html_element("div", [html_class("status-row")], [
            html_element(
              "span",
              [
                html_id("status"),
                html_class("status-pill"),
                html_attribute("data-state", "idle"),
              ],
              [html_text("準備完了")],
            ),
            html_element(
              "span",
              [html_id("progress"), html_class("progress")],
              [],
            ),
            html_element(
              "span",
              [html_id("provider-model"), html_class("provider-model")],
              [html_text("プロバイダーを確認中…")],
            ),
          ]),
        ]),
        html_element("div", [html_class("header-actions")], [
          html_button(
            "text-view",
            "text-view",
            "テキスト表示",
            "quiet-button",
            @yami_kumo.ButtonVariant::Secondary,
          ),
          html_button(
            "fork-session",
            "fork-session",
            "会話を分岐",
            "quiet-button",
            @yami_kumo.ButtonVariant::Secondary,
            disabled=true,
          ),
          html_button(
            "prune-results",
            "prune-results",
            "出力を整理",
            "quiet-button",
            @yami_kumo.ButtonVariant::Secondary,
            disabled=true,
          ),
          html_button(
            "cancel",
            "cancel",
            "停止",
            "quiet-button",
            @yami_kumo.ButtonVariant::Secondary,
            disabled=true,
          ),
        ]),
      ]),
      html_element("div", [html_id("chatgpt-account-anchor")], [
        chatgpt_account_panel(),
      ]),
      html_element(
        "div",
        [
          html_id("connection-error"),
          html_class("notice error-notice"),
          html_attribute("role", "alert"),
          html_boolean_attribute("hidden"),
        ],
        [
          html_element("span", [html_id("connection-error-text")], []),
          html_button(
            "reconnect",
            "reconnect",
            "再接続",
            "quiet-button",
            @yami_kumo.ButtonVariant::Secondary,
          ),
        ],
      ),
      html_element(
        "div",
        [
          html_id("run-error"),
          html_class("notice error-notice"),
          html_attribute("role", "alert"),
          html_boolean_attribute("hidden"),
        ],
        [],
      ),
      html_element(
        "div",
        [
          html_id("action-message"),
          html_class("notice success-notice"),
          html_attribute("role", "status"),
          html_attribute("aria-live", "polite"),
          html_boolean_attribute("hidden"),
        ],
        [],
      ),
      html_element(
        "section",
        [
          html_id("transcript-area"),
          html_class("transcript-area"),
          html_attribute("aria-label", "会話"),
        ],
        [
          html_element(
            "div",
            [
              html_id("transcript-scroll"),
              html_class("transcript-scroll"),
              html_attribute("tabindex", "0"),
              html_attribute("role", "region"),
              html_attribute("aria-label", "会話の記録"),
              html_attribute("aria-describedby", "transcript-help"),
            ],
            [
              html_element(
                "canvas",
                [
                  html_id("transcript-canvas"),
                  html_attribute("aria-hidden", "true"),
                ],
                [],
              ),
              html_element(
                "div",
                [html_id("scene-spacer"), html_attribute("aria-hidden", "true")],
                [],
              ),
            ],
          ),
          html_element(
            "div",
            [
              html_id("text-transcript"),
              html_class("text-transcript sr-only"),
              html_attribute("role", "log"),
              html_attribute("aria-label", "選択可能な会話の記録"),
              html_attribute("aria-live", "off"),
            ],
            [],
          ),
          html_element(
            "p",
            [html_id("transcript-help"), html_class("sr-only")],
            [
              html_text(
                "スクロールして会話を読めます。テキスト表示では文字を選択でき、スクリーンリーダーでも読み上げられます。",
              ),
            ],
          ),
          html_button(
            "jump-latest",
            "jump-latest",
            "↓ 最新へ",
            "jump-latest",
            @yami_kumo.ButtonVariant::Secondary,
            disabled=true,
          ),
        ],
      ),
      html_element(
        "section",
        [
          html_id("approval"),
          html_class("approval"),
          html_attribute("aria-labelledby", "approval-title"),
          html_boolean_attribute("hidden"),
        ],
        [
          html_element("div", [html_class("approval-heading")], [
            html_element("div", [], [
              html_element("h2", [html_id("approval-title")], [
                html_text("ツールの実行許可が必要です"),
              ]),
              html_element("p", [html_id("approval-description")], []),
            ]),
            html_element("span", [html_class("approval-tag")], [
              html_text("確認"),
            ]),
          ]),
          html_element(
            "pre",
            [
              html_id("approval-arguments"),
              html_attribute("tabindex", "0"),
              html_attribute("aria-label", "ツールへの引数"),
            ],
            [],
          ),
          html_element("div", [html_class("approval-actions")], [
            html_button(
              "deny",
              "deny",
              "拒否",
              "quiet-button",
              @yami_kumo.ButtonVariant::SecondaryDestructive,
            ),
            html_button(
              "approve",
              "approve",
              "今回のみ許可",
              "primary-button",
              @yami_kumo.ButtonVariant::Primary,
            ),
          ]),
        ],
      ),
      html_element("form", [html_id("composer"), html_class("composer")], [
        html_element(
          "label",
          [html_attribute("for", "prompt"), html_class("sr-only")],
          [html_text("エージェントへのメッセージ")],
        ),
        html_element(
          "textarea",
          [
            html_id("prompt"),
            html_attribute("name", "prompt"),
            html_attribute("rows", "3"),
            html_attribute("maxlength", "16384"),
            html_attribute(
              "placeholder", "取り組みたいことを入力してください",
            ),
            html_attribute("autocomplete", "off"),
            html_attribute("spellcheck", "true"),
            html_boolean_attribute("required"),
          ],
          [],
        ),
        html_element("div", [html_class("composer-footer")], [
          html_element("p", [html_id("composer-hint")], [
            html_text("⌘ / Ctrl + Enter で送信"),
          ]),
          @yami_kumo.button(
            @yami_kumo.fragment([
              html_text("送信 "),
              html_element("span", [html_attribute("aria-hidden", "true")], [
                html_text("↑"),
              ]),
            ]),
            variant=@yami_kumo.ButtonVariant::Primary,
            button_type="submit",
            class_name="primary-button",
            attrs=[html_id("send"), action_attribute("send")],
          ),
        ]),
      ]),
    ],
  )
}

///|
fn settings_page() -> @yami_kumo.Html {
  html_element(
    "section",
    [
      html_id("settings-page"),
      html_class("settings-page"),
      html_attribute("aria-hidden", "true"),
      html_attribute("inert", ""),
      html_boolean_attribute("hidden"),
      html_attribute("aria-labelledby", "settings-title"),
    ],
    [
      html_element("header", [html_class("settings-page-header")], [
        html_element("div", [], [
          eyebrow("ワークスペース"),
          html_element(
            "h1",
            [html_id("settings-title"), html_attribute("tabindex", "-1")],
            [html_text("設定")],
          ),
        ]),
        html_button(
          "settings-close",
          "settings-close",
          "×  閉じる",
          "quiet-button settings-close",
          @yami_kumo.ButtonVariant::Secondary,
          extra_attrs=[html_attribute("aria-label", "設定を閉じる")],
        ),
      ]),
      html_element("div", [html_class("settings-layout")], [
        html_element(
          "nav",
          [
            html_class("settings-nav"),
            html_attribute("aria-label", "設定セクション"),
          ],
          [
            html_element("p", [html_class("settings-nav-title")], [
              html_text("設定"),
            ]),
            html_button(
              "settings-nav-chatgpt",
              "settings-nav-chatgpt",
              "◉  ChatGPT",
              "settings-nav-item",
              @yami_kumo.ButtonVariant::Ghost,
              extra_attrs=[html_attribute("aria-current", "page")],
            ),
          ],
        ),
        html_element("div", [html_class("settings-content")], [
          html_element(
            "div",
            [
              html_id("settings-error"),
              html_class("notice error-notice settings-error"),
              html_attribute("role", "alert"),
              html_boolean_attribute("hidden"),
            ],
            [],
          ),
          html_element("header", [html_class("settings-section-heading")], [
            html_element("h2", [], [html_text("ChatGPT プラン")]),
            html_element("p", [], [
              html_text(
                "ChatGPT アカウントと、Responses API で使用するモデルを管理します。認証情報はこのホストの保護されたストアに保存されます。",
              ),
            ]),
          ]),
          html_element("div", [html_class("settings-card")], [
            html_element("div", [html_class("settings-card-heading")], [
              html_element("h3", [], [html_text("アカウントとモデル")]),
            ]),
            html_element("div", [html_id("chatgpt-settings-slot")], []),
          ]),
        ]),
      ]),
    ],
  )
}

///|
fn workspace_main() -> @yami_kumo.Html {
  html_element("div", [html_class("dsh-workspace")], [
    html_element(
      "div",
      [
        html_id("announcement"),
        html_class("sr-only"),
        html_attribute("role", "status"),
        html_attribute("aria-live", "polite"),
      ],
      [],
    ),
    conversation_page(),
    settings_page(),
  ])
}

///|
/// Build the static application shell with Yami-kumo's safe MoonBit HTML tree.
#export_name("shell_html")
pub fn shell_html() -> String {
  let brand = html_element(
    "a",
    [
      html_class("dsh-brand"),
      html_attribute("href", "/"),
      html_attribute("aria-label", "dsh.mbt ホーム"),
    ],
    [
      html_element(
        "span",
        [html_class("dsh-brand-mark"), html_attribute("aria-hidden", "true")],
        [html_text("d")],
      ),
      html_element("strong", [], [html_text("dsh.mbt")]),
    ],
  )
  let navigation_trigger = html_button(
    "navigation-toggle",
    "navigation-toggle",
    "☰",
    "icon-button mobile-navigation-toggle",
    @yami_kumo.ButtonVariant::Ghost,
    extra_attrs=[
      html_attribute("aria-label", "会話ナビゲーションを開く"),
      html_attribute("aria-controls", "yk-mobile-navigation"),
      html_attribute("aria-expanded", "false"),
    ],
  )
  let settings_button = html_button(
    "settings-open",
    "settings-open",
    "設定",
    "quiet-button settings-open-trigger",
    @yami_kumo.ButtonVariant::Secondary,
    extra_attrs=[
      html_attribute("aria-controls", "settings-page"),
      html_attribute("aria-expanded", "false"),
      html_attribute("aria-pressed", "false"),
    ],
  )
  let sidebar_toggle = html_button(
    "sidebar-toggle",
    "sidebar-toggle",
    "ナビゲーションを隠す",
    "quiet-button sidebar-toggle",
    @yami_kumo.ButtonVariant::Secondary,
    extra_attrs=[
      html_attribute("aria-label", "ナビゲーションを隠す"),
      html_attribute("aria-controls", "yk-mobile-navigation"),
      html_attribute("aria-pressed", "false"),
    ],
  )
  let header_actions = @yami_kumo.fragment([settings_button, sidebar_toggle])
  let context_toggle = html_button(
    "context-toggle",
    "context-toggle",
    "詳細",
    "quiet-button context-toggle",
    @yami_kumo.ButtonVariant::Secondary,
    extra_attrs=[
      html_attribute("aria-controls", "yk-context-panel"),
      html_attribute("aria-expanded", "false"),
    ],
  )
  let bottom_bar = html_element("div", [html_class("workspace-status")], [
    html_element(
      "span",
      [
        html_id("shell-status-dot"),
        html_class("workspace-status-dot"),
        html_attribute("data-state", "connecting"),
        html_attribute("aria-hidden", "true"),
      ],
      [],
    ),
    html_element(
      "span",
      [
        html_id("shell-status"),
        html_attribute("role", "status"),
        html_attribute("aria-live", "polite"),
      ],
      [html_text("ローカルホストに接続中…")],
    ),
  ])
  let shell = @yami_kumo.app_shell(
    brand,
    workspace_main(),
    navigation_trigger~,
    global_search=search_field(),
    header_actions~,
    account_menu=context_toggle,
    sidebar=navigation_sidebar(),
    context_panel=context_panel(),
    context_panel_label="会話の詳細",
    bottom_bar~,
    primary_navigation_label="メインナビゲーション",
    workspace_navigation_label="ワークスペースのナビゲーション",
    close_workspace_navigation_label="ワークスペースのナビゲーションを閉じる",
  )
  match @yami_kumo.render_html(shell) {
    Ok(html) => html
    Err(_) => abort("dsh shell serializes as safe HTML")
  }
}
