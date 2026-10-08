export function authModelRefreshKey(auth) {
  if (auth?.state !== "connected") return null;
  if (Array.isArray(auth.models) && auth.models.length > 0) return null;
  const profileId = auth.account?.profile_id;
  return typeof profileId === "string" && profileId ? profileId : "connected";
}

export function isBusy(session) {
  return Boolean(session?.pending_approval)
    || ["running", "queued", "awaiting_approval"].includes(session?.status);
}

export function isReadOnly(session) {
  return session?.source_format === "deepseek-session-v4";
}

export function statusLabel(session) {
  if (session?.pending_approval || session?.status === "awaiting_approval") return "承認待ち";
  const label = ({ idle: "準備完了", running: "実行中", queued: "待機中", completed: "完了", failed: "失敗", cancelled: "キャンセル済み" })[session?.status] || session?.status || "準備完了";
  return isReadOnly(session) ? `読み取り専用 · ${label}` : label;
}

export function sessionList(result) {
  const rows = Array.isArray(result) ? result : result?.sessions;
  if (!Array.isArray(rows)) throw new Error("The server returned an invalid session list.");
  return rows.filter((row) => row && typeof row.id === "string");
}

// Session logs are append-only. A poll started before a mutation must not
// overwrite the newer response and re-enable a button for a stale state.
export function acceptsSnapshot(candidate, current) {
  if (!current || candidate.id !== current.id) return true;
  if ((candidate.turn_id || 0) < (current.turn_id || 0)) return false;
  // The host batches deltas before appending them, so two polls can have the
  // same event count while one carries newer provisional text. The revision
  // counts projected UTF-16 units. Old v1 snapshots omit it and keep the
  // historical count-only rule.
  if (Number.isSafeInteger(candidate.stream_revision) && Number.isSafeInteger(current.stream_revision)
    && (candidate.turn_id || 0) === (current.turn_id || 0)
    && candidate.stream_revision < current.stream_revision) return false;
  if (Array.isArray(candidate.events) && Array.isArray(current.events)
    && candidate.events.length < current.events.length) return false;
  return true;
}

export function prettyArguments(value) {
  if (typeof value !== "string") return JSON.stringify(value ?? {}, null, 2);
  try { return JSON.stringify(JSON.parse(value), null, 2); } catch { return value; }
}

export function runError(session) {
  if (session?.status !== "failed") return "";
  if (typeof session.error === "string") return session.error;
  const events = Array.isArray(session.events) ? session.events : [];
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const event = events[index];
    if (event.turn_id !== session.turn_id) continue;
    if (typeof event.data?.error === "string" && event.data.error) return event.data.error;
  }
  if (isReadOnly(session)) return "読み込んだ履歴のターンが失敗しました。この会話を続けることはできません。";
  return "ターンに失敗しました。会話を確認して、新しいメッセージを送信できます。";
}

export function displayMessages(session) {
  const rows = [];
  const prunedCallIds = new Set((session?.events || [])
    .filter((event) => event.type === "tool/result/pruned")
    .map((event) => event.data?.call_id)
    .filter((callId) => typeof callId === "string"));
  for (const message of session?.messages || []) {
    if (!message || ["system", "developer"].includes(message.role)) continue;
    const provisional = message.provisional === true;
    const status = message.stream_status === "partial" ? "一部表示" : "生成中";
    if (message.reasoning) rows.push({ label: provisional ? `推論 · ${status}` : "推論", text: String(message.reasoning) });
    if (message.content) rows.push({
      label: provisional && message.role === "assistant"
        ? `アシスタント · ${status}`
        : message.role === "tool" && prunedCallIds.has(message.tool_call_id)
          ? "ツール結果 · モデル入力用に短縮"
        : ({ user: "あなた", assistant: "アシスタント", tool: "ツール結果" })[message.role] || "メッセージ",
      text: String(message.content),
    });
    for (const call of message.tool_calls || []) {
      if (call.kind === "custom") {
        // Custom call arguments are provider-defined text, not JSON input.
        // The renderer assigns this string with textContent, so markup stays inert.
        rows.push({ label: `カスタム呼び出し · ${String(call.name || "")}`, text: String(call.arguments ?? "") });
      } else {
        rows.push({ label: `ツール要求 · ${String(call.name || "")}`, text: prettyArguments(call.arguments) });
      }
    }
  }
  if (session?._ui_live_text) rows.push({ label: "アシスタント · 生成中", text: session._ui_live_text });
  return rows;
}

export function updateShellContext(session, connection, hasError = false, documentRef = globalThis.document) {
  if (!documentRef) return;
  const byId = (id) => documentRef.getElementById(id);
  const active = session && typeof session.id === "string";
  const imported = isReadOnly(session);
  const messages = Array.isArray(session?.messages) ? session.messages : [];
  const events = Array.isArray(session?.events) ? session.events : [];
  const connectionLabel = ({
    synced: "接続済み · ライブ更新",
    ready: "接続済み · 更新を確認中",
    connecting: "ローカルホストに接続中…",
    offline: "切断されました · 再接続してください",
    needs_resync: "ワークスペースを更新中…",
    failed: "ローカルホストを利用できません",
  })[connection] || "ローカルホストを待っています…";

  if (active) {
    byId("context-summary").textContent = session.title || "無題の会話";
    byId("context-status").textContent = statusLabel(session);
    byId("context-turn").textContent = session.turn_id > 0
      ? `${session.turn_id} ターン目 · ステップ ${session.step || 0}`
      : "ターンはまだありません";
    byId("context-history").textContent = `${messages.length} 件のメッセージ · ${events.length} 件のイベント`;
    byId("context-source").textContent = imported
      ? "Session v4 の読み込み履歴 · 読み取り専用"
      : "ローカルの会話";
    byId("context-parent").textContent = typeof session.parent_session_id === "string"
      ? session.parent_session_id
      : "なし";
  } else {
    byId("context-summary").textContent = "会話を選ぶと現在の状態を表示します。";
    byId("context-status").textContent = "会話が選択されていません";
    byId("context-turn").textContent = "—";
    byId("context-history").textContent = "—";
    byId("context-source").textContent = "利用できません";
    byId("context-parent").textContent = "—";
  }

  byId("context-read-only").hidden = !active || !imported;
  byId("context-host-status").textContent = hasError
    ? "接続が中断されました。再接続してワークスペースを更新してください。"
    : `ローカルホスト · ${connectionLabel}`;
  byId("shell-status").textContent = hasError ? "接続が中断されました · 再接続してください" : connectionLabel;
  byId("shell-status-dot").dataset.state = hasError ? "offline" : connection || "connecting";
}

export async function loadWorkspaceMetadata(fetchImpl = globalThis.fetch) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetchImpl("/api/metadata", {
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
      signal: controller.signal,
    });
    if (!response.ok) return null;
    const payload = await response.json();
    const result = payload?.result;
    return result && typeof result === "object" ? result : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

export function createWorkspaceMetadataRefresher({
  fetchImpl = globalThis.fetch,
  onMetadata = () => {},
  getContextKey = () => null,
  intervalMs = 10_000,
  now = () => Date.now(),
} = {}) {
  let inFlight = null;
  let lastStartedAt = Number.NEGATIVE_INFINITY;
  const interval = Number.isFinite(intervalMs) && intervalMs >= 0 ? intervalMs : 10_000;

  function refresh({ force = false } = {}) {
    if (inFlight) return inFlight;
    const startedAt = now();
    if (!force && startedAt - lastStartedAt < interval) return Promise.resolve(null);
    lastStartedAt = startedAt;
    const contextKey = getContextKey();

    let request;
    request = loadWorkspaceMetadata(fetchImpl)
      .then((metadata) => {
        if (metadata && Object.is(contextKey, getContextKey())) onMetadata(metadata);
        return metadata;
      })
      .finally(() => {
        if (inFlight === request) inFlight = null;
      });
    inFlight = request;
    return request;
  }

  return { refresh };
}

export function updateWorkspaceMetadata(metadata, documentRef = globalThis.document) {
  if (!metadata || !documentRef) return;
  const byId = (id) => documentRef.getElementById(id);
  const project = typeof metadata.project === "string" && metadata.project.trim()
    ? metadata.project
    : "ワークスペース";
  const repository = metadata.repository && typeof metadata.repository === "object"
    ? metadata.repository
    : null;
  byId("project-name").textContent = project;
  byId("repository-name").textContent = repository?.name || "Git リポジトリではありません";
  byId("branch-name").textContent = typeof repository?.branch === "string"
    ? repository.detached ? `HEAD 分離 · ${repository.branch}` : repository.branch
    : repository ? "ブランチを取得できません" : "—";
  byId("provider-model").textContent = `${metadata.provider || "不明なプロバイダー"} · ${metadata.model || "モデル未選択"}`;
}

const JAPANESE_FONT_STORAGE_KEY = "dsh.display.japanese-font.v1";
export const JAPANESE_FONT_STACKS = Object.freeze({
  system: '"Hiragino Sans", "Yu Gothic UI", "Yu Gothic", Meiryo, sans-serif',
  hiragino: '"Hiragino Sans", "Yu Gothic UI", "Yu Gothic", Meiryo, sans-serif',
  yugothic: '"Yu Gothic UI", "Yu Gothic", Meiryo, "Hiragino Sans", sans-serif',
  meiryo: 'Meiryo, "Yu Gothic UI", "Hiragino Sans", sans-serif',
  noto: '"Noto Sans JP", "Hiragino Sans", "Yu Gothic UI", Meiryo, sans-serif',
});

function availableStorage(storageRef) {
  try { return storageRef || globalThis.localStorage; }
  catch { return null; }
}

export function setJapaneseFont(value, documentRef = globalThis.document, storageRef) {
  const selected = Object.hasOwn(JAPANESE_FONT_STACKS, value) ? value : "system";
  documentRef?.documentElement?.style?.setProperty("--dsh-font-family", JAPANESE_FONT_STACKS[selected]);
  const picker = documentRef?.getElementById?.("japanese-font");
  if (picker && picker.value !== selected) picker.value = selected;
  try { availableStorage(storageRef)?.setItem(JAPANESE_FONT_STORAGE_KEY, selected); }
  catch { /* Storage may be unavailable; the page-local setting still applies. */ }
  return selected;
}

export function restoreJapaneseFont(documentRef = globalThis.document, storageRef) {
  let saved = "system";
  try { saved = availableStorage(storageRef)?.getItem(JAPANESE_FONT_STORAGE_KEY) || "system"; }
  catch { /* A fresh page uses the system Japanese font stack. */ }
  return setJapaneseFont(saved, documentRef, storageRef);
}
