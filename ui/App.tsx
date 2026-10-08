import { useEffect } from 'react';
import { AppShell } from './yami-kumo/AppShell';

function getShell() {
  return document.querySelector<HTMLElement>('.yk-shell');
}

function syncShellAccessibility() {
  const shell = getShell();
  if (!shell) return;
  const mobile = window.matchMedia('(max-width: 820px)').matches;
  const contextualDrawer = window.matchMedia('(max-width: 1180px)').matches;
  const sidebar = document.getElementById('yk-mobile-navigation');
  const details = document.getElementById('yk-context-panel');
  const sidebarOpen = shell.dataset.mobileSidebarOpen === 'true';
  const detailsOpen = shell.dataset.contextPanelOpen === 'true';
  const sidebarHidden = mobile
    ? !sidebarOpen
    : shell.dataset.sidebarCollapsed === 'true';
  const modalId = detailsOpen && contextualDrawer
    ? 'yk-context-panel'
    : sidebarOpen && mobile
      ? 'yk-mobile-navigation'
      : '';

  if (sidebar) {
    sidebar.setAttribute('aria-hidden', String(sidebarHidden));
    if (sidebarHidden) sidebar.setAttribute('inert', '');
    else sidebar.removeAttribute('inert');
    if (modalId === 'yk-mobile-navigation') {
      sidebar.setAttribute('role', 'dialog');
      sidebar.setAttribute('aria-modal', 'true');
    } else {
      sidebar.removeAttribute('role');
      sidebar.removeAttribute('aria-modal');
    }
  }
  if (details) {
    details.setAttribute('aria-hidden', String(!detailsOpen));
    if (!detailsOpen) details.setAttribute('inert', '');
    else details.removeAttribute('inert');
    if (modalId === 'yk-context-panel') {
      details.setAttribute('role', 'dialog');
      details.setAttribute('aria-modal', 'true');
    } else {
      details.removeAttribute('role');
      details.removeAttribute('aria-modal');
    }
  }

  if (modalId) {
    for (const target of document.querySelectorAll<HTMLElement>(
      '.yk-topbar, .yk-workspace, .yk-bottom-bar, #yk-mobile-navigation, #yk-context-panel',
    )) {
      if (target.id === modalId) target.removeAttribute('inert');
      else target.setAttribute('inert', '');
    }
  } else {
    for (const target of document.querySelectorAll<HTMLElement>(
      '.yk-topbar, .yk-workspace, .yk-bottom-bar',
    )) target.removeAttribute('inert');
  }
}

function setRegionOpen(
  region: 'mobileSidebarOpen' | 'contextPanelOpen',
  open: boolean,
  triggerId: string,
  panelId: string,
  restoreFocus = false,
) {
  const shell = getShell();
  const trigger = document.getElementById(triggerId);
  const panel = document.getElementById(panelId);
  if (!shell || !panel) return;

  if (open && region === 'mobileSidebarOpen') {
    shell.dataset.contextPanelOpen = 'false';
    document.getElementById('context-toggle')?.setAttribute('aria-expanded', 'false');
  }
  if (open && region === 'contextPanelOpen') {
    shell.dataset.mobileSidebarOpen = 'false';
    document.getElementById('navigation-toggle')?.setAttribute('aria-expanded', 'false');
  }

  shell.dataset[region] = String(open);
  trigger?.setAttribute('aria-expanded', String(open));
  syncShellAccessibility();

  if (open) panel.querySelector<HTMLElement>('button, input, select, [tabindex="0"]')?.focus();
  else if (restoreFocus) trigger?.focus();
}

function trapFocus(event: KeyboardEvent, panelId: string) {
  if (event.key !== 'Tab') return;
  const panel = document.getElementById(panelId);
  if (!panel) return;
  const focusable = [...panel.querySelectorAll<HTMLElement>(
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
  )].filter((element) => element.getClientRects().length > 0 && !element.hasAttribute('inert'));
  if (focusable.length === 0) {
    event.preventDefault();
    panel.focus();
    return;
  }
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && (document.activeElement === first || !panel.contains(document.activeElement))) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && (document.activeElement === last || !panel.contains(document.activeElement))) {
    event.preventDefault();
    first.focus();
  }
}

function App() {
  useEffect(() => {
    const mobile = window.matchMedia('(max-width: 820px)');
    const contextualDrawer = window.matchMedia('(max-width: 1180px)');

    const onSessionSelected = (event: Event) => {
      if (mobile.matches && (event.target as Element | null)?.closest('.session-option, #new-session')) {
        setRegionOpen('mobileSidebarOpen', false, 'navigation-toggle', 'yk-mobile-navigation', true);
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      const shell = getShell();
      const contextOpen = shell?.dataset.contextPanelOpen === 'true';
      const sidebarOpen = shell?.dataset.mobileSidebarOpen === 'true';
      const activeModal = contextOpen && contextualDrawer.matches
        ? 'yk-context-panel'
        : sidebarOpen && mobile.matches
          ? 'yk-mobile-navigation'
          : '';
      if (event.key === 'Escape' && contextOpen) {
        setRegionOpen('contextPanelOpen', false, 'context-toggle', 'yk-context-panel', true);
      } else if (event.key === 'Escape' && sidebarOpen) {
        setRegionOpen('mobileSidebarOpen', false, 'navigation-toggle', 'yk-mobile-navigation', true);
      } else if (activeModal) {
        trapFocus(event, activeModal);
      }
    };
    const onViewportChange = () => {
      if (mobile.matches && getShell()?.dataset.sidebarCollapsed === 'true') {
        const shell = getShell();
        if (shell) shell.dataset.sidebarCollapsed = 'false';
        const toggle = document.getElementById('sidebar-toggle');
        if (toggle) {
          toggle.setAttribute('aria-pressed', 'false');
          toggle.textContent = 'ナビゲーションを隠す';
        }
      }
      syncShellAccessibility();
    };

    syncShellAccessibility();
    document.addEventListener('click', onSessionSelected);
    document.addEventListener('keydown', onKeyDown);
    mobile.addEventListener('change', onViewportChange);
    contextualDrawer.addEventListener('change', onViewportChange);

    // The existing imperative controllers require their DOM to exist first.
    // AppShell mounts synchronously; loading the controllers here keeps React
    // out of their session, transcript and form state.
    const controller = document.createElement('script');
    controller.type = 'module';
    controller.src = '/app.js';
    document.head.append(controller);

    return () => {
      document.removeEventListener('click', onSessionSelected);
      document.removeEventListener('keydown', onKeyDown);
      mobile.removeEventListener('change', onViewportChange);
      contextualDrawer.removeEventListener('change', onViewportChange);
      controller.remove();
    };
  }, []);

  const toggleSidebar = () => {
    const shell = getShell();
    const next = shell?.dataset.sidebarCollapsed !== 'true';
    if (shell) shell.dataset.sidebarCollapsed = String(next);
    const button = document.getElementById('sidebar-toggle');
    if (button) {
      button.setAttribute('aria-pressed', String(next));
      button.textContent = next ? 'ナビゲーションを表示' : 'ナビゲーションを隠す';
    }
    syncShellAccessibility();
    if (next) button?.focus();
  };
  const toggleMobileSidebar = () => {
    const open = getShell()?.dataset.mobileSidebarOpen !== 'true';
    setRegionOpen('mobileSidebarOpen', open, 'navigation-toggle', 'yk-mobile-navigation');
  };
  const toggleContext = () => {
    const open = getShell()?.dataset.contextPanelOpen !== 'true';
    setRegionOpen('contextPanelOpen', open, 'context-toggle', 'yk-context-panel');
  };
  const closeSidebar = () => setRegionOpen('mobileSidebarOpen', false, 'navigation-toggle', 'yk-mobile-navigation', true);
  const closeContext = () => setRegionOpen('contextPanelOpen', false, 'context-toggle', 'yk-context-panel', true);

  return (
    <AppShell
      navigationTrigger={
        <button
          id="navigation-toggle"
          type="button"
          className="icon-button mobile-navigation-toggle"
          aria-label="会話ナビゲーションを開く"
          aria-controls="yk-mobile-navigation"
          aria-expanded="false"
          onClick={toggleMobileSidebar}
        >
          <span aria-hidden="true">☰</span>
        </button>
      }
      brand={
        <a className="dsh-brand" href="/" aria-label="dsh.mbt ホーム">
          <span className="dsh-brand-mark" aria-hidden="true">d</span>
          <strong>dsh.mbt</strong>
        </a>
      }
      globalSearch={
        <label className="session-search" htmlFor="session-search">
          <span className="sr-only">会話を検索</span>
          <span className="session-search-icon" aria-hidden="true">⌕</span>
          <input id="session-search" type="search" placeholder="会話を検索" autoComplete="off" />
        </label>
      }
      headerActions={
        <button
          id="sidebar-toggle"
          type="button"
          className="quiet-button sidebar-toggle"
          aria-pressed="false"
          onClick={toggleSidebar}
        >
          ナビゲーションを隠す
        </button>
      }
      accountMenu={
        <button
          id="context-toggle"
          type="button"
          className="quiet-button context-toggle"
          aria-controls="yk-context-panel"
          aria-expanded="false"
          onClick={toggleContext}
        >
          詳細
        </button>
      }
      sidebar={
        <div className="dsh-sidebar">
          <div className="sidebar-heading">
            <div>
              <span className="eyebrow">プロジェクト</span>
              <strong id="project-name">ワークスペース</strong>
            </div>
            <button
              type="button"
              className="icon-button mobile-navigation-close"
              aria-label="会話ナビゲーションを閉じる"
              onClick={closeSidebar}
            >
              ×
            </button>
          </div>
          <button id="new-session" className="new-session" type="button">
            <span aria-hidden="true">＋</span> 新しい会話
          </button>
          <div className="sidebar-heading session-list-heading">
            <span className="eyebrow">最近の会話</span>
          </div>
          <nav id="sessions" className="session-list" aria-label="会話の一覧">
            <p className="empty-list">会話を読み込んでいます…</p>
          </nav>
          <p className="sidebar-note">ローカルエージェントのワークスペース</p>
        </div>
      }
      contextPanel={
        <div className="context-content">
          <div className="context-heading">
            <div>
              <span className="eyebrow">現在の会話</span>
              <h2 id="context-title">会話の詳細</h2>
            </div>
            <button
              id="context-close"
              type="button"
              className="icon-button"
              aria-label="会話の詳細を閉じる"
              onClick={closeContext}
            >
              ×
            </button>
          </div>
          <p id="context-summary" className="context-summary">会話を選ぶと現在の状態が表示されます。</p>
          <dl className="context-facts">
            <div><dt>状態</dt><dd id="context-status">会話が選択されていません</dd></div>
            <div><dt>ターン</dt><dd id="context-turn">—</dd></div>
            <div><dt>履歴</dt><dd id="context-history">—</dd></div>
            <div><dt>保存元</dt><dd id="context-source">ローカルの会話</dd></div>
            <div><dt>親セッション</dt><dd id="context-parent">なし</dd></div>
            <div><dt>リポジトリ</dt><dd id="repository-name">取得中…</dd></div>
            <div><dt>ブランチ</dt><dd id="branch-name">—</dd></div>
          </dl>
          <p id="context-read-only" className="context-note" hidden>
            読み込んだ履歴は読み取り専用です。会話を確認できますが、送信やターンのキャンセルはできません。
          </p>
          <label className="font-control" htmlFor="japanese-font">
            <span>日本語フォント</span>
            <select id="japanese-font">
              <option value="system">システム標準</option>
              <option value="hiragino">ヒラギノ角ゴ</option>
              <option value="yugothic">游ゴシック</option>
              <option value="meiryo">メイリオ</option>
              <option value="noto">Noto Sans JP</option>
            </select>
          </label>
          <p className="context-note">セッションログの外部アップロード機能はありません（既定で無効です）。</p>
          <p id="context-host-status" className="context-host-status">ローカルホストに接続中…</p>
        </div>
      }
      contextPanelLabel="会話の詳細"
      bottomBar={
        <div className="workspace-status">
          <span id="shell-status-dot" className="workspace-status-dot" data-state="connecting" aria-hidden="true" />
          <span id="shell-status" role="status" aria-live="polite">ローカルホストに接続中…</span>
        </div>
      }
      onMobileSidebarDismiss={closeSidebar}
      onContextPanelDismiss={closeContext}
    >
      <div className="dsh-workspace">
        <a className="skip-link" href="#transcript-scroll">会話へ移動</a>
        <header className="session-header">
          <div className="session-heading">
            <h1 id="session-title">エージェントのワークスペース</h1>
            <div className="status-row">
              <span id="status" className="status-pill" data-state="idle">準備完了</span>
              <span id="progress" className="progress" />
              <span id="provider-model" className="provider-model">プロバイダーを確認中…</span>
            </div>
          </div>
          <div className="header-actions">
            <button id="text-view" className="quiet-button" type="button" aria-pressed="false">テキスト表示</button>
            <button id="fork-session" className="quiet-button" type="button" disabled>会話を分岐</button>
            <button id="prune-results" className="quiet-button" type="button" hidden>出力を整理</button>
            <button id="cancel" className="quiet-button" type="button" disabled>停止</button>
          </div>
        </header>

        <section className="account-bar" aria-label="ChatGPT アカウントとモデル">
          <div className="account-summary">
            <span id="auth-status" className="account-status" data-state="signed_out">ChatGPT 未接続</span>
            <span id="auth-detail" className="account-detail" />
            <span id="auth-guidance" className="account-detail" />
            <a id="usage-link" className="account-link" href="https://chatgpt.com" target="_blank" rel="noopener noreferrer" hidden>
              ChatGPT を開く · 設定 → 使用状況
            </a>
          </div>
          <div className="account-actions">
            <label className="model-control" htmlFor="model-picker">
              <span>モデル</span>
              <select id="model-picker" disabled><option>ChatGPT に接続してモデルを表示</option></select>
            </label>
            <button id="auth-sign-in" className="quiet-button" type="button">ChatGPT にサインイン</button>
            <button id="auth-models-retry" className="quiet-button" type="button" hidden>モデルを再読み込み</button>
            <button id="auth-sign-out" className="quiet-button" type="button" hidden>接続を解除</button>
            <button id="install-app" className="quiet-button" type="button" hidden>インストール</button>
          </div>
        </section>

        <div id="connection-error" className="notice error-notice" role="alert" hidden>
          <span id="connection-error-text" />
          <button id="reconnect" type="button">再接続</button>
        </div>
        <div id="run-error" className="notice error-notice" role="alert" hidden />
        <div id="action-message" className="notice success-notice" role="status" aria-live="polite" hidden />

        <section id="transcript-area" className="transcript-area" aria-label="会話">
          <div id="transcript-scroll" className="transcript-scroll" tabIndex={0} role="region" aria-label="会話の記録" aria-describedby="transcript-help">
            <canvas id="transcript-canvas" aria-hidden="true" />
            <div id="scene-spacer" aria-hidden="true" />
          </div>
          <div id="text-transcript" className="text-transcript sr-only" role="log" aria-label="選択可能な会話の記録" aria-live="off" />
          <p id="transcript-help" className="sr-only">スクロールして会話を読めます。テキスト表示では文字を選択でき、スクリーンリーダーでも読み上げられます。</p>
          <button id="jump-latest" className="jump-latest" type="button" hidden>↓ 最新へ</button>
        </section>

        <section id="approval" className="approval" aria-labelledby="approval-title" hidden>
          <div className="approval-heading">
            <div><h2 id="approval-title">ツールの実行許可が必要です</h2><p id="approval-description" /></div>
            <span className="approval-tag">確認</span>
          </div>
          <pre id="approval-arguments" tabIndex={0} aria-label="ツールへの引数" />
          <div className="approval-actions">
            <button id="deny" className="quiet-button" type="button">拒否</button>
            <button id="approve" className="primary-button" type="button">今回のみ許可</button>
          </div>
        </section>

        <form id="composer" className="composer">
          <label htmlFor="prompt" className="sr-only">エージェントへのメッセージ</label>
          <textarea id="prompt" name="prompt" rows={3} maxLength={16384} placeholder="取り組みたいことを入力してください" autoComplete="off" spellCheck={true} required />
          <div className="composer-footer">
            <p id="composer-hint">⌘ / Ctrl + Enter で送信</p>
            <button id="send" className="primary-button" type="submit">送信 <span aria-hidden="true">↑</span></button>
          </div>
        </form>
      </div>
    </AppShell>
  );
}

export default App;
