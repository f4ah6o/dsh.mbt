import * as bridge from "/moonbit/client.js";
import { createRemoteClient } from "./remote-client.js";
import { drawSceneSnapshot } from "./canvas-renderer.js";
import {
  isBusy,
  isReadOnly,
  statusLabel,
  prettyArguments,
  runError,
  displayMessages,
  authModelRefreshKey,
  updateShellContext,
  createWorkspaceMetadataRefresher,
  updateWorkspaceMetadata,
  restoreJapaneseFont,
  setJapaneseFont,
} from "./view-model.js";

const $ = (id) => document.getElementById(id);
const isLocalDshOrigin = window.location.protocol === "http:" &&
  ["127.0.0.1", "localhost"].includes(window.location.hostname);
const client = createRemoteClient({ bridge });
const scroll = $("transcript-scroll");
const canvas = $("transcript-canvas");
const context = canvas.getContext("2d");
const state = {
  moon: null,
  sessions: [],
  id: null,
  selection: 0,
  snapshot: { messages: [], events: [] },
  client: null,
  mutation: false,
  frame: null,
  transcriptKey: "",
  statusKey: "",
  actionError: "",
  actionMessage: "",
  connectionMessage: "",
  draftScope: "",
  recoverPromise: null,
  authPoll: null,
  receiptPoll: null,
  receiptPollRunning: false,
  authModelsLoading: false,
  authModelsError: false,
  installPrompt: null,
  workspaceMetadata: null,
};

const workspaceMetadataRefresher = createWorkspaceMetadataRefresher({
  getContextKey() {
    const auth = state.client?.auth;
    return JSON.stringify([auth?.state, auth?.account?.profile_id, auth?.selected_model]);
  },
  onMetadata(metadata) {
    state.workspaceMetadata = metadata;
    renderWorkspaceContext();
  },
});
function refreshWorkspaceMetadata(options) { return workspaceMetadataRefresher.refresh(options); }

let authModelsAttemptedKey = null;
let authModelsInFlight = null;

function connectionError(error) {
  $("connection-error-text").textContent = error instanceof Error ? error.message : String(error);
  $("connection-error").hidden = false;
  updateShellContext(state.snapshot, state.client?.connection || "offline", true, document);
}

function clearConnectionError() {
  $("connection-error").hidden = true;
  updateShellContext(state.snapshot, state.client?.connection || "connecting", false, document);
}

function isTrustedAuthorizationUrl(value) {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" &&
      url.hostname === "auth.openai.com" &&
      url.port === "" &&
      url.pathname === "/api/accounts/authorize" &&
      url.username === "" &&
      url.password === "" &&
      url.hash === "";
  } catch {
    return false;
  }
}

async function localOperation(operation, input = {}) {
  const response = await fetch("/api/call", {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ operation, input }),
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error(`ホストからの応答を読み取れませんでした（HTTP ${response.status}）。`);
  }
  if (!response.ok || !payload?.ok) {
    throw new Error(payload?.error || `ホストがリクエストを拒否しました（HTTP ${response.status}）。`);
  }
  return payload.result;
}

function syncFromClient({ restoreDraft = false } = {}) {
  state.client = client.state();
  const previousScope = state.draftScope;
  state.sessions = Array.isArray(state.client.projection?.sessions)
    ? state.client.projection.sessions
    : [];
  state.id = state.client.selected_session || null;
  const selected = state.client.selected_session_projection;
  const summary = state.sessions.find((row) => row.id === state.id);
  state.snapshot = selected || summary || { messages: [], events: [] };
  if (restoreDraft || previousScope !== state.client.scope_key) {
    state.draftScope = state.client.scope_key || "";
    $("prompt").value = state.client.draft || "";
    resizeComposer();
  }
  renderSessions();
  renderControls();
  renderAccount();
  renderWorkspaceContext();
  renderAccessibleTranscript();
  syncTextView();
  schedulePaint();
}

function renderWorkspaceContext() {
  const metadata = state.workspaceMetadata;
  if (!metadata) return;
  const selectedModel = metadata.provider === "ChatGPT"
    ? state.client?.auth?.selected_model
    : null;
  updateWorkspaceMetadata({
    ...metadata,
    model: selectedModel || metadata.model,
  }, document);
}

function syncTextView() {
  const textView = Boolean(state.client?.text_view);
  $("text-view").setAttribute("aria-pressed", String(textView));
  $("text-view").textContent = textView ? "キャンバス表示" : "テキスト表示";
  scroll.hidden = textView;
  $("text-transcript").classList.toggle("sr-only", !textView);
  $("jump-latest").hidden = true;
}

function renderSessions() {
  const container = $("sessions");
  const existing = new Map([...container.querySelectorAll("button[data-id]")]
    .map((button) => [button.dataset.id, button]));
  const query = $("session-search").value.trim().toLocaleLowerCase();
  const sessions = state.sessions.filter((session) => [
    session.title,
    session.id,
    session.parent_session_id,
    statusLabel(session),
    isReadOnly(session) ? "imported read-only history" : "local conversation",
  ].some((value) => String(value || "").toLocaleLowerCase().includes(query))
    || session.id === state.id);
  if (!sessions.length) {
    container.replaceChildren();
    const empty = document.createElement("p");
    empty.className = "empty-list";
    empty.textContent = query
      ? "検索に一致する会話はありません。"
      : "会話はまだありません。メッセージを送って開始してください。";
    container.append(empty);
    return;
  }
  container.querySelector(".empty-list")?.remove();
  let cursor = container.firstElementChild;
  for (const session of [...sessions].reverse()) {
    let button = existing.get(session.id);
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "session-option";
      button.dataset.id = session.id;
      const title = document.createElement("span");
      title.className = "session-option-title";
      const status = document.createElement("span");
      status.className = "session-option-state";
      button.append(title, status);
      button.addEventListener("click", () => selectSession(session.id, { explicit: true }));
    }
    button.children[0].textContent = session.title || "無題のセッション";
    button.children[1].textContent = statusLabel(session);
    if (session.id === state.id) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
    if (button !== cursor) container.insertBefore(button, cursor);
    cursor = button.nextElementSibling;
    existing.delete(session.id);
  }
  for (const button of existing.values()) button.remove();
}

function renderControls() {
  const session = state.snapshot;
  const busy = isBusy(session);
  const readOnly = isReadOnly(session);
  const approval = session.pending_approval;
  const canPrune = Boolean(state.id) && !readOnly && !busy
    && ["idle", "completed"].includes(session.status)
    && (session.events || []).some((event) => event.type === "tool/result")
    && state.client?.connection === "synced";
  const canFork = Boolean(state.id) && !readOnly && !busy
    && ["idle", "completed", "failed", "cancelled"].includes(session.status)
    && state.client?.connection === "synced";
  $("session-title").textContent = state.id ? session.title || "無題のセッション" : "エージェントのワークスペース";
  $("status").textContent = statusLabel(session);
  $("status").dataset.state = approval ? "approval" : session.status || "idle";
  $("progress").textContent = session.turn_id > 0 ? `${session.turn_id} ターン目 · ステップ ${session.step || 0}` : "";
  $("cancel").disabled = state.mutation || !busy || !state.id;
  $("fork-session").disabled = state.mutation || !canFork;
  $("prune-results").hidden = !canPrune;
  $("prune-results").disabled = state.mutation || !canPrune;
  $("new-session").disabled = state.mutation || state.client?.connection !== "synced";
  $("prompt").disabled = readOnly || state.client?.connection !== "synced";
  $("prompt").placeholder = readOnly ? "読み込んだ履歴は読み取り専用です" : "取り組みたいことを入力してください";
  $("send").disabled = state.mutation || busy || readOnly ||
    state.client?.connection !== "synced" || !$("prompt").value.trim();
  $("composer-hint").textContent = state.connectionMessage || (readOnly
    ? "読み込んだ履歴は読み取り専用のため、続けて送信できません。"
    : approval
      ? "ツールの実行内容を確認してください。"
      : busy
        ? "エージェントが処理中です。停止するとこのターンをキャンセルします。"
        : "⌘ / Ctrl + Enter で送信");
  $("approval").hidden = !approval;
  if (approval) {
    $("approval-description").textContent = `${approval.name} の実行許可を待っています。`;
    const argumentsText = prettyArguments(approval.arguments);
    if ($("approval-arguments").textContent !== argumentsText) {
      $("approval-arguments").textContent = argumentsText;
    }
  }
  $("approve").disabled = state.mutation || !approval || !state.id;
  $("deny").disabled = state.mutation || !approval || !state.id;
  const error = state.actionError || runError(session);
  $("run-error").hidden = !error;
  $("run-error").textContent = error;
  $("action-message").hidden = !state.actionMessage;
  $("action-message").textContent = state.actionMessage;
  const statusKey = `${state.id}:${session.status}:${approval?.call_id || ""}`;
  if (state.statusKey !== statusKey) {
    $("announcement").textContent = approval ? `${approval.name} の実行許可が必要です。` : statusLabel(session);
    state.statusKey = statusKey;
  }
  updateShellContext(session, state.client?.connection || "connecting", Boolean(state.connectionMessage), document);
}

function renderAccount() {
  const auth = state.client?.auth || { state: "signed_out", models: [], account: null };
  const account = auth.account?.email || "";
  const connected = auth.state === "connected";
  const profiles = Boolean(auth.account?.profile_id);
  const models = Array.isArray(auth.models) ? auth.models : [];
  const status = $("auth-status");
  status.dataset.state = auth.state || "signed_out";
  status.textContent = ({
    connected: account ? `ChatGPT · ${account}` : "ChatGPT 接続済み",
    signing_in: "ChatGPT のサインインを待っています",
    reauth_required: "ChatGPT に再度サインインしてください",
    signed_out: "ChatGPT 未接続",
  })[auth.state] || "ChatGPT 未接続";
  const usage = auth.plan_usage === "enabled"
    ? "プランの利用状況を確認できます"
    : connected
      ? "このアカウントではプランの利用状況を確認できません。ChatGPT の設定 → 使用状況を確認してください。"
      : "プランを確認するにはサインインしてください";
  const scopes = Array.isArray(auth.scopes) && auth.scopes.length
    ? ` · ${auth.scopes.join(", ")}`
    : "";
  $("auth-detail").textContent = `${usage}${scopes}`;
  $("auth-guidance").textContent = !connected
    ? !isLocalDshOrigin
      ? auth.state === "signing_in"
        ? "ホスト Mac のブラウザーでサインインを完了してください。完了するとこのページが更新されます。"
        : "ホスト Mac で dsh を開いて、ChatGPT にサインインするかアカウントを切り替えてください。"
      : auth.state === "signing_in"
        ? "このブラウザーの新しいタブでサインインを完了してください。"
        : "サインイン用のタブが開きます。認証情報はホスト側に保存されます。"
    : models.length > 0
      ? "別のアカウントに切り替えるには、接続を解除してからサインインしてください。"
      : state.authModelsLoading
        ? "この ChatGPT アカウントのモデルを読み込んでいます…"
        : state.authModelsError
          ? "モデルを読み込めませんでした。「モデルを再読み込み」を選んで再試行してください。"
          : "このアカウントのモデルがありません。「モデルを再読み込み」を選んで再確認してください。";
  $("usage-link").hidden = !connected || auth.plan_usage === "enabled";
  $("auth-sign-in").hidden = connected;
  $("auth-sign-in").textContent = auth.state === "reauth_required" ? "再度サインイン" : "ChatGPT にサインイン";
  $("auth-sign-in").disabled = state.mutation || auth.state === "signing_in" ||
    !isLocalDshOrigin;
  $("auth-sign-out").hidden = !connected;
  $("auth-sign-out").disabled = state.mutation || !profiles;
  $("auth-models-retry").hidden = !connected || models.length > 0;
  $("auth-models-retry").disabled = state.mutation || state.authModelsLoading;

  const picker = $("model-picker");
  picker.replaceChildren();
  if (!models.length) {
    const option = document.createElement("option");
    option.textContent = connected ? "利用できるモデルがありません" : "ChatGPT に接続してモデルを表示";
    option.value = "";
    picker.append(option);
  } else {
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "モデルを選択";
    placeholder.disabled = true;
    picker.append(placeholder);
    for (const model of models) {
      const option = document.createElement("option");
      option.value = model.slug;
      option.textContent = model.display_name;
      picker.append(option);
    }
    picker.value = models.some((model) => model.slug === auth.selected_model)
      ? auth.selected_model
      : "";
  }
  picker.disabled = !connected || models.length === 0 || state.mutation;
  scheduleAuthRefresh(auth.state === "signing_in");
}

function renderAccessibleTranscript() {
  const messages = displayMessages(state.snapshot);
  const key = JSON.stringify(messages);
  if (key === state.transcriptKey) return;
  state.transcriptKey = key;
  const container = $("text-transcript");
  const wasBottom = container.scrollTop + container.clientHeight >= container.scrollHeight - 60;
  const fragment = document.createDocumentFragment();
  for (const message of messages) {
    const article = document.createElement("article");
    article.className = "text-message";
    const heading = document.createElement("h2");
    heading.textContent = message.label;
    const content = document.createElement("pre");
    content.textContent = message.text;
    article.append(heading, content);
    fragment.append(article);
  }
  if (!messages.length) {
    const empty = document.createElement("p");
    empty.textContent = "メッセージを送ると開始します。";
    fragment.append(empty);
  }
  container.replaceChildren(fragment);
  if (state.client?.follow_latest || wasBottom) container.scrollTop = container.scrollHeight;
}

function paint() {
  state.frame = null;
  if (!state.moon || state.client?.text_view) return;
  const width = Math.max(1, Math.floor(scroll.clientWidth));
  const height = Math.max(1, Math.floor(scroll.clientHeight));
  const scale = Math.min(3, window.devicePixelRatio || 1);
  try {
    const extent = state.moon.measure_ui(JSON.stringify(state.snapshot), width);
    $("scene-spacer").style.height = `${Math.max(0, extent - height)}px`;
    canvas.style.height = `${height}px`;
    if (canvas.width !== Math.round(width * scale) || canvas.height !== Math.round(height * scale)) {
      canvas.width = Math.round(width * scale);
      canvas.height = Math.round(height * scale);
    }
    if (state.client.follow_latest) scroll.scrollTop = Math.max(0, extent - height);
    const presentation = { ...state.snapshot, _ui_scroll_top: Math.round(scroll.scrollTop) };
    const scene = JSON.parse(state.moon.render_ui(JSON.stringify(presentation), width, height));
    drawSceneSnapshot(context, scene, { width, height, scale });
    $("jump-latest").hidden = state.client.follow_latest || extent <= height;
  } catch (error) {
    connectionError(new Error(`会話の描画に失敗しました: ${error.message}`));
  }
}

function schedulePaint() {
  if (state.frame === null) state.frame = requestAnimationFrame(paint);
}

function resizeComposer() {
  const prompt = $("prompt");
  if (window.matchMedia("(max-width: 560px)").matches) {
    prompt.style.height = "auto";
    prompt.style.height = `${Math.min(prompt.scrollHeight, Math.max(72, window.visualViewport?.height || innerHeight) * 0.3)}px`;
  }
}

async function refreshSnapshot({ reconnect = true, refreshAuthModels = true } = {}) {
  client.beginConnect();
  syncFromClient();
  try {
    const result = await client.snapshot();
    syncFromClient();
    void refreshWorkspaceMetadata();
    if (state.id) {
      try {
        await client.selectedSession(state.id);
        syncFromClient();
      } catch (error) {
        if (!String(error.message).includes("snapshot")) throw error;
        await client.snapshot();
        syncFromClient();
        if (state.id) {
          await client.selectedSession(state.id);
          syncFromClient();
        }
      }
    }
    if (reconnect) startStream();
    state.connectionMessage = "";
    clearConnectionError();
    if (result.result.status === "identity_changed") {
    state.actionMessage = "サインイン中のアカウントが変わりました。続ける前に現在の会話を確認してください。";
      syncFromClient();
    }
    if (refreshAuthModels) await refreshAuthCatalog();
    return result;
  } catch (error) {
    client.connectionFailed();
    syncFromClient();
    throw error;
  }
}

async function refreshAuthCatalog({ force = false } = {}) {
  const auth = client.state().auth;
  const key = authModelRefreshKey(auth);
  if (!key) {
    authModelsAttemptedKey = null;
    return;
  }
  if (authModelsInFlight) {
    if (authModelsInFlight.key === key) return authModelsInFlight.promise;
    await authModelsInFlight.promise;
    return refreshAuthCatalog({ force });
  }
  if (!force && authModelsAttemptedKey === key) return;

  authModelsAttemptedKey = key;
  state.authModelsLoading = true;
  state.authModelsError = false;
  renderAccount();

  let promise;
  promise = (async () => {
    try {
      await localOperation("auth_models");
      await refreshSnapshot({ reconnect: false, refreshAuthModels: false });
    } catch {
      state.authModelsError = true;
    } finally {
      state.authModelsLoading = false;
      if (authModelsInFlight?.promise === promise) authModelsInFlight = null;
      const activeKey = authModelRefreshKey(client.state().auth);
      if (activeKey !== key) {
        authModelsAttemptedKey = null;
        if (activeKey) void refreshAuthCatalog();
      }
      renderAccount();
    }
  })();
  authModelsInFlight = { key, promise };
  return promise;
}

let streamCleanup = null;
function startStream() {
  streamCleanup?.();
  streamCleanup = client.subscribe({
    onEvent({ result, needsSnapshot }) {
      syncFromClient();
      if (needsSnapshot) void recoverSnapshot();
      else if (result.status === "applied") {
        clearConnectionError();
        scheduleReceiptCheck();
      }
    },
    onError(error) {
      state.connectionMessage = error?.message || "";
      syncFromClient();
    },
  });
}

function scheduleReceiptCheck(delay = 6000) {
  clearTimeout(state.receiptPoll);
  const pending = client.state().pending_commands || [];
  if (!pending.some((command) => command.status !== "unconfirmed")) return;
  state.receiptPoll = setTimeout(async () => {
    if (state.receiptPollRunning) return;
    state.receiptPollRunning = true;
    try {
      await client.reconcileReceipts();
      syncFromClient();
    } catch (error) {
      state.connectionMessage = "操作の結果を確認できませんでした。再接続して結果を確認してください。";
      connectionError(error);
      renderControls();
    } finally {
      state.receiptPollRunning = false;
      scheduleReceiptCheck();
    }
  }, delay);
}

function recoverSnapshot() {
  if (state.recoverPromise) return state.recoverPromise;
  if (document.hidden) {
    client.persistNow();
    client.closeStream();
    streamCleanup = null;
    return Promise.resolve();
  }
  state.recoverPromise = (async () => {
    streamCleanup?.();
    streamCleanup = null;
    try {
      await client.reconcileReceipts();
      await refreshSnapshot({ reconnect: true });
    } catch (error) {
      connectionError(error);
      state.connectionMessage = "ワークスペースを更新できるまで、更新を一時停止しています。";
      renderControls();
    } finally {
      state.recoverPromise = null;
      scheduleReceiptCheck();
    }
  })();
  return state.recoverPromise;
}

function scheduleAuthRefresh(waiting) {
  clearTimeout(state.authPoll);
  if (!waiting) return;
  state.authPoll = setTimeout(async () => {
    try {
      await refreshSnapshot();
    } catch (error) {
      connectionError(error);
    }
  }, 2000);
}

async function mutate(body) {
  if (state.mutation) return;
  state.mutation = true;
  state.actionError = "";
  state.actionMessage = "";
  renderControls();
  renderAccount();
  try {
    await body();
    void refreshWorkspaceMetadata({ force: true });
    clearConnectionError();
  } catch (error) {
    state.actionError = error instanceof Error ? error.message : String(error);
  } finally {
    state.mutation = false;
    syncFromClient();
  }
}

async function runCommand(operation, sessionId, input, approvalRevision = -1) {
  const receipt = await client.command(operation, sessionId, input, approvalRevision);
  if (receipt.status === "rejected") {
    throw new Error(receipt.error || "ホストがこの操作を拒否しました。");
  }
  if (receipt.status === "uncertain" || receipt.status === "expired") {
    throw new Error(receipt.error || "ホストがこの操作の結果を確認できませんでした。");
  }
  state.connectionMessage = "";
  await refreshSnapshot();
  scheduleReceiptCheck();
  return receipt;
}

async function createSession(title) {
  const existing = new Set(state.sessions.map((session) => session.id));
  const receipt = await runCommand("session_create", null, title ? { title } : {});
  const receiptSession = receipt.result?.session || receipt.result;
  let sessionId = typeof receiptSession?.id === "string" ? receiptSession.id : null;
  if (!sessionId) sessionId = state.sessions.find((session) => !existing.has(session.id))?.id || null;
  if (sessionId) await selectSession(sessionId);
}

async function selectSession(id, { explicit = false } = {}) {
  if (explicit) state.selection += 1;
  const selection = state.selection;
  if (!id || id === state.id) return;
  client.select(id);
  state.actionError = "";
  state.actionMessage = "";
  syncFromClient();
  try {
    await client.selectedSession(id);
    if (selection !== state.selection) return;
    syncFromClient();
    startStream();
    clearConnectionError();
  } catch (error) {
    if (selection !== state.selection) return;
    connectionError(error);
    await recoverSnapshot();
  }
}

async function handleAuthRefresh() {
  await refreshSnapshot();
}

$("new-session").addEventListener("click", () => mutate(async () => {
  await createSession(`セッション ${state.sessions.length + 1}`);
  $("prompt").focus();
}));

$("fork-session").addEventListener("click", () => mutate(async () => {
  const sourceId = state.id;
  const selection = state.selection;
  if (!sourceId) return;
  const receipt = await runCommand("session_fork", sourceId, {});
  const child = receipt.result?.session || receipt.result;
  if (typeof child?.id !== "string") {
    throw new Error("ホストから分岐した会話が返されませんでした。");
  }
  // Selecting the fork is a convenience. A newer explicit user selection
  // always wins while the durable command is in flight.
  if (state.id === sourceId && state.selection === selection && client.state().selected_session === sourceId) {
    await selectSession(child.id);
    if (state.id === child.id) {
      state.actionMessage = `${sourceId} から会話を分岐しました。`;
      syncFromClient();
    }
  }
}));

$("prune-results").addEventListener("click", () => mutate(async () => {
  const sessionId = state.id;
  const selection = state.selection;
  if (!sessionId) return;
  let receipt;
  try {
    receipt = await runCommand("session_prune_tool_results", sessionId, {});
  } catch (error) {
    if (state.id !== sessionId || state.selection !== selection) return;
    throw error;
  }
  if (state.id !== sessionId || state.selection !== selection) return;
  const result = receipt.result?.result || receipt.result || {};
  const pruned = Array.isArray(result.pruned) ? result.pruned : [];
  state.actionMessage = pruned.length > 0
    ? `${pruned.length} 件のツール結果を今後のモデル要求向けに短縮しました。元の出力はイベント履歴に残っています。`
    : "短縮が必要な大きさのツール結果はありません。";
  syncFromClient();
}));

$("composer").addEventListener("submit", (event) => {
  event.preventDefault();
  const entered = $("prompt").value;
  const prompt = entered.trim();
  if (!prompt || isBusy(state.snapshot) || isReadOnly(state.snapshot)) return;
  mutate(async () => {
    let id = state.id;
    if (!id) {
      await createSession(prompt.slice(0, 60));
      id = state.id;
    }
    if (!id) throw new Error("新しいセッションを表示できません。更新してから再試行してください。");
    const receipt = await runCommand("session_send", id, { prompt });
    if (["accepted", "completed"].includes(receipt.status) && $("prompt").value === entered) {
      $("prompt").value = "";
      client.saveDraft("");
      resizeComposer();
    }
    client.setFollowLatest(true);
    syncFromClient();
    $("prompt").focus();
  });
});

$("prompt").addEventListener("input", () => {
  client.saveDraft($("prompt").value);
  resizeComposer();
  renderControls();
});
$("session-search").addEventListener("input", renderSessions);
$("prompt").addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && !event.isComposing) {
    event.preventDefault();
    if (!$("send").disabled) $("composer").requestSubmit();
  }
});

$("cancel").addEventListener("click", () => mutate(async () => {
  await runCommand("session_cancel", state.id, {});
}));

for (const [button, approved] of [["approve", true], ["deny", false]]) {
  $(button).addEventListener("click", () => {
    const pending = state.snapshot.pending_approval;
    if (!pending || !state.id) return;
    const session = state.sessions.find((row) => row.id === state.id);
    const revision = Number.isSafeInteger(session?.approval_revision) ? session.approval_revision : -1;
    mutate(async () => {
      await runCommand("tool_approve", state.id, { call_id: pending.call_id, approved }, revision);
    });
  });
}

$("auth-sign-in").addEventListener("click", () => {
  if (!isLocalDshOrigin) {
    state.actionError = "ホスト Mac で dsh を開いて、ChatGPT にサインインするかアカウントを切り替えてください。";
    syncFromClient();
    return;
  }
  if (state.mutation || client.state().auth?.state === "signing_in") return;
  const signInTab = window.open("about:blank", "_blank");
  if (!signInTab) {
    state.actionError = "ブラウザーがサインイン用タブをブロックしました。このローカル dsh ページのポップアップを許可して再試行してください。";
    syncFromClient();
    return;
  }
  signInTab.opener = null;
  return mutate(async () => {
    try {
      const result = await localOperation("auth_sign_in_browser", {});
      if (result?.started === false) {
        signInTab.close();
        state.actionMessage = "サインイン処理はすでに進行中です。開いているブラウザータブで完了してください。";
        await handleAuthRefresh();
        return;
      }
      if (result?.started !== true ||
        !isTrustedAuthorizationUrl(result.authorization_url)) {
        throw new Error("ホストから無効な ChatGPT 認証 URL が返されました。");
      }
      signInTab.location.replace(result.authorization_url);
    } catch (error) {
      signInTab.close();
      throw error;
    }
    await handleAuthRefresh();
  });
});
$("auth-models-retry").addEventListener("click", () => mutate(async () => {
  await refreshAuthCatalog({ force: true });
}));
$("auth-sign-out").addEventListener("click", () => mutate(async () => {
  const profileId = client.state().auth?.account?.profile_id;
  if (!profileId) throw new Error("現在の ChatGPT プロファイルを特定できません。");
  await localOperation("auth_sign_out", { profile_id: profileId });
  await refreshSnapshot();
}));
$("model-picker").addEventListener("change", () => {
  const model = $("model-picker").value;
  if (!model) return;
  return mutate(async () => {
    await localOperation("auth_select_model", { model });
    await refreshSnapshot();
    state.actionMessage = `${client.state().auth?.models?.find((entry) => entry.slug === model)?.display_name || model} を使用しています。`;
    syncFromClient();
  });
});

$("text-view").addEventListener("click", () => {
  const next = !client.state().text_view;
  client.setTextView(next);
  syncFromClient();
});
scroll.addEventListener("scroll", () => {
  const follow = scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 48;
  client.setFollowLatest(follow);
  client.setScrollAnchor(`${Math.round(scroll.scrollTop)}`);
  state.client = client.state();
  schedulePaint();
}, { passive: true });
$("text-transcript").addEventListener("scroll", () => {
  if (!state.client?.text_view) return;
  const text = $("text-transcript");
  const follow = text.scrollTop + text.clientHeight >= text.scrollHeight - 48;
  client.setFollowLatest(follow);
  state.client = client.state();
  $("jump-latest").hidden = follow;
}, { passive: true });
$("jump-latest").addEventListener("click", () => {
  client.setFollowLatest(true);
  state.client = client.state();
  if (state.client.text_view) {
    const text = $("text-transcript");
    text.scrollTop = text.scrollHeight;
    $("jump-latest").hidden = true;
  } else {
    schedulePaint();
  }
});

$("reconnect").addEventListener("click", async () => {
  $("reconnect").disabled = true;
  try {
    await refreshWorkspaceMetadata({ force: true });
    await client.reconcileReceipts();
    await refreshSnapshot();
    state.connectionMessage = "";
  } catch (error) {
    connectionError(error);
  } finally {
    $("reconnect").disabled = false;
    syncFromClient();
  }
});

$("install-app").addEventListener("click", async () => {
  if (!state.installPrompt) return;
  state.installPrompt.prompt();
  await state.installPrompt.userChoice;
  state.installPrompt = null;
  $("install-app").hidden = true;
});
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  state.installPrompt = event;
  $("install-app").hidden = false;
});
window.addEventListener("appinstalled", () => {
  state.installPrompt = null;
  $("install-app").hidden = true;
});

canvas.addEventListener("contextlost", (event) => event.preventDefault());
canvas.addEventListener("contextrestored", schedulePaint);
new ResizeObserver(schedulePaint).observe($("transcript-area"));
window.addEventListener("resize", () => {
  resizeComposer();
  schedulePaint();
});
window.visualViewport?.addEventListener("resize", () => {
  document.documentElement.style.setProperty("--visible-height", `${window.visualViewport.height}px`);
  resizeComposer();
  schedulePaint();
});
window.addEventListener("online", () => { void refreshWorkspaceMetadata({ force: true }); void recoverSnapshot(); });
window.addEventListener("pagehide", () => {
  client.persistNow();
  client.closeStream();
  streamCleanup = null;
  clearTimeout(state.authPoll);
  clearTimeout(state.receiptPoll);
});
window.addEventListener("pageshow", () => {
  if (!document.hidden) { void refreshWorkspaceMetadata({ force: true }); void recoverSnapshot(); }
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) { void refreshWorkspaceMetadata({ force: true }); void recoverSnapshot(); }
  else {
    client.persistNow();
    client.closeStream();
    streamCleanup = null;
  }
});

async function loadMoon() {
  state.moon = await import("/moonbit/app.js");
  if (typeof state.moon.render_ui !== "function" || typeof state.moon.measure_ui !== "function") {
    throw new Error("MoonBit 表示モジュールを利用できません。ブラウザー用アセットを再ビルドしてから再接続してください。");
  }
}

async function start() {
  document.documentElement.style.setProperty("--visible-height", `${window.visualViewport?.height || innerHeight}px`);
  restoreJapaneseFont(document);
  $("japanese-font").addEventListener("change", () => {
    setJapaneseFont($("japanese-font").value, document);
    schedulePaint();
  });
  setInterval(() => { if (!document.hidden) void refreshWorkspaceMetadata({ force: true }); }, 10_000);
  await loadMoon();
  syncFromClient({ restoreDraft: true });
  try {
    await refreshSnapshot();
    await client.reconcileReceipts();
    syncFromClient();
    if (!state.id && state.sessions.length) {
      await selectSession(state.sessions.at(-1).id);
    }
  } catch (error) {
    client.closeStream();
    connectionError(error);
  }
  renderControls();
  renderAccount();
}

start().catch(connectionError);
