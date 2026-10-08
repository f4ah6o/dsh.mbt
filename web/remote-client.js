const PREFERENCE_PREFIX = "dsh.client.preferences.v1:";

function decode(value) {
  return JSON.parse(value);
}

class UnconfirmedReceiptError extends Error {}

function randomEntropyHex() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function createRemoteClient({ bridge: bridgeImpl, fetchImpl = fetch, EventSourceImpl = EventSource } = {}) {
  if (!bridgeImpl) throw new Error("共有クライアントブリッジが必要です。");
  const bridge = bridgeImpl;
  const handle = bridge.client_init();
  let restoredScope = "";
  let stream = null;
  let persistTimer = null;

  function state() {
    return decode(bridge.client_state(handle));
  }

  function beginConnect() {
    bridge.client_begin_connect(handle);
  }

  function connectionFailed() {
    bridge.client_connection_failed(handle);
  }

  function writePreferences() {
    const preferences = decode(bridge.client_persisted_state(handle));
    if (!preferences.scope_key) return;
    try {
      localStorage.setItem(`${PREFERENCE_PREFIX}${preferences.scope_key}`, JSON.stringify(preferences));
    } catch {
      // Private browsing and storage limits must not prevent the live session.
    }
  }

  function persist() {
    clearTimeout(persistTimer);
    persistTimer = setTimeout(writePreferences, 180);
  }

  function persistNow() {
    clearTimeout(persistTimer);
    persistTimer = null;
    writePreferences();
  }

  function restoreForScope(current) {
    if (!current.scope_key || restoredScope === current.scope_key) return current;
    const previousScope = restoredScope;
    restoredScope = current.scope_key;
    // Preferences are private to the authenticated server identity. Remove the
    // previous scope after a verified scope transition so a shared browser
    // cannot retain another user's draft or selection under an old key.
    if (previousScope) {
      try {
        localStorage.removeItem(`${PREFERENCE_PREFIX}${previousScope}`);
      } catch {
        // Storage may be unavailable; live client state still resets in MoonBit.
      }
    }
    try {
      const raw = localStorage.getItem(`${PREFERENCE_PREFIX}${current.scope_key}`);
      if (raw) bridge.client_restore_preferences(handle, raw);
    } catch {
      // A malformed or unavailable preference store is a fresh local client.
    }
    return state();
  }

  async function request(path, init = {}) {
    let response;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20_000);
    try {
      response = await fetchImpl(path, {
        ...init,
        signal: controller.signal,
        cache: "no-store",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          ...(init.body ? { "Content-Type": "application/json" } : {}),
          ...init.headers,
        },
      });
    } catch (error) {
      if (error?.name === "AbortError") {
        throw new Error("ワークスペースへのリクエストがタイムアウトしました。再送信する前に操作の受付結果を確認してください。");
      }
      if (error instanceof TypeError) throw new Error("ワークスペースのホストに接続できません。ネットワークまたは Tailnet の接続を確認してください。");
      throw error;
    } finally {
      clearTimeout(timeout);
    }
    let payload = null;
    try {
      if (response.status !== 204) payload = await response.json();
    } catch {
      throw new Error(`ワークスペースからの応答を読み取れませんでした（HTTP ${response.status}）。`);
    }
    if (!response.ok) {
      const detail = typeof payload?.error === "string" ? payload.error : `HTTP ${response.status}`;
      const error = new Error(`ワークスペースへのリクエストに失敗しました: ${detail}`);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  async function snapshot() {
    const payload = await request("/api/v1/snapshot");
    const result = decode(bridge.client_accept_snapshot(handle, JSON.stringify(payload)));
    if (!result.ok) throw new Error(result.error || "ワークスペースのスナップショットが拒否されました。");
    const current = restoreForScope(result.state);
    persist();
    return { result, state: current, payload };
  }

  async function selectedSession(sessionId) {
    const payload = await request(`/api/v1/sessions/${encodeURIComponent(sessionId)}`);
    const result = decode(bridge.client_accept_session(handle, JSON.stringify(payload)));
    if (!result.ok) throw new Error(result.error || "選択中のセッションが変わりました。ワークスペースを更新してください。");
    return result.state;
  }

  function closeStream() {
    stream?.close();
    stream = null;
  }

  function subscribe({ onEvent, onError }) {
    closeStream();
    const current = state();
    if (!current.cursor) throw new Error("ライブ更新を開始する前にワークスペースのスナップショットが必要です。");
    const url = new URL("/api/v1/events", location.origin);
    url.searchParams.set("cursor", current.cursor);
    if (current.selected_session) url.searchParams.set("session_id", current.selected_session);
    stream = new EventSourceImpl(url.toString());
    const applyEvent = (event) => {
      const result = decode(bridge.client_accept_event(handle, event.data, event.lastEventId || ""));
      if (!result.ok || [
        "gap", "wrong_workspace", "identity_changed", "epoch_changed",
        "requires_snapshot", "cursor_mismatch",
      ].includes(result.status)) {
        onEvent?.({ result, needsSnapshot: true });
        return;
      }
      persist();
      onEvent?.({ result, needsSnapshot: false });
    };
    stream.onmessage = applyEvent;
    stream.addEventListener("projection", applyEvent);
    stream.addEventListener("resync", applyEvent);
    stream.onopen = () => {
      bridge.client_connection_restored(handle);
      onError?.(null);
    };
    stream.onerror = () => {
      bridge.client_connection_failed(handle);
      onError?.(new Error("ライブ更新を一時停止しました。ブラウザーが自動的に再接続します。"));
    };
    return closeStream;
  }

  function newCommandId() {
    const commandId = bridge.client_new_command_id(String(Date.now()), randomEntropyHex());
    if (!commandId) throw new Error("安全な操作 ID を作成できませんでした。");
    return commandId;
  }

  async function command(operation, sessionId, input, approvalRevision = -1) {
    const commandId = newCommandId();
    const queued = decode(bridge.client_queue_command(
      handle,
      commandId,
      operation,
      sessionId || "",
      JSON.stringify(input ?? {}),
      approvalRevision,
    ));
    if (!queued.ok) throw new Error(queued.error || "このワークスペースの状態では操作を実行できません。");
    const sent = queued.command;
    bridge.client_mark_command_sent(handle, commandId);
    persistNow();
    try {
      const receipt = await request("/api/v1/commands", {
        method: "POST",
        body: JSON.stringify(sent),
      });
      const applied = decode(bridge.client_apply_receipt(handle, JSON.stringify(receipt)));
      if (!applied.ok) throw new Error(applied.error || "操作の受付記録がこのリクエストと一致しません。");
      persist();
      return receipt;
    } catch (error) {
      bridge.client_mark_command_uncertain(handle, commandId);
      persistNow();
      try {
        const receipt = await receiptFor(commandId);
        if (receipt) return receipt;
        bridge.client_mark_receipt_missing(handle, commandId);
        persistNow();
        throw new UnconfirmedReceiptError("ホストは操作を受け付けたか確認できませんでした。再送信する前に受付記録を確認してください。");
      } catch (receiptError) {
        if (receiptError instanceof UnconfirmedReceiptError) throw receiptError;
        throw new Error(`${error.message} 操作がホストに届いている場合があります。再接続して受付記録を確認してください。`);
      }
    }
  }

  async function receiptFor(commandId) {
    try {
      const receipt = await request(`/api/v1/commands/${encodeURIComponent(commandId)}`);
      const applied = decode(bridge.client_apply_receipt(handle, JSON.stringify(receipt)));
      if (!applied.ok) throw new Error(applied.error || "ホストから一致しない操作受付記録が返されました。");
      persist();
      return receipt;
    } catch (error) {
      if (error.status === 404) return null;
      throw error;
    }
  }

  async function reconcileReceipts() {
    const ids = pendingIds();
    const results = [];
    for (const id of ids) {
      const receipt = await receiptFor(id);
      if (!receipt) {
        bridge.client_mark_receipt_missing(handle, id);
        persist();
        results.push({ command_id: id, status: "unconfirmed" });
      } else {
        results.push({ command_id: id, status: receipt.status });
      }
    }
    return results;
  }

  function pendingIds() {
    return decode(bridge.client_pending_ids(handle));
  }

  function saveDraft(value) {
    bridge.client_set_draft(handle, value);
    persist();
  }

  function select(sessionId) {
    bridge.client_set_selection(handle, sessionId || "");
    persist();
  }

  function setScrollAnchor(value) {
    bridge.client_set_scroll_anchor(handle, value || "");
    persist();
  }

  function setFollowLatest(value) {
    bridge.client_set_follow_latest(handle, String(Boolean(value)));
    persist();
  }

  function setTextView(value) {
    bridge.client_set_text_view(handle, String(Boolean(value)));
    persist();
  }

  return {
    state,
    beginConnect,
    connectionFailed,
    snapshot,
    selectedSession,
    subscribe,
    command,
    reconcileReceipts,
    pendingIds,
    saveDraft,
    select,
    setScrollAnchor,
    setFollowLatest,
    setTextView,
    persistNow,
    closeStream,
    dispose() {
      persistNow();
      closeStream();
      bridge.client_dispose(handle);
    },
  };
}
