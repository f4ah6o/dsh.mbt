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
  if (session?.pending_approval || session?.status === "awaiting_approval") return "Needs approval";
  const label = ({ idle: "Ready", running: "Running", queued: "Queued", completed: "Completed", failed: "Failed", cancelled: "Cancelled" })[session?.status] || session?.status || "Ready";
  return isReadOnly(session) ? `Read-only · ${label}` : label;
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
  if (isReadOnly(session)) return "This imported history records a failed turn and cannot be continued.";
  return "The turn failed. You can review the conversation and send another prompt.";
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
    const status = message.stream_status === "partial" ? "partial" : "writing";
    if (message.reasoning) rows.push({ label: provisional ? `Reasoning · ${status}` : "Reasoning", text: String(message.reasoning) });
    if (message.content) rows.push({
      label: provisional && message.role === "assistant"
        ? `Assistant · ${status}`
        : message.role === "tool" && prunedCallIds.has(message.tool_call_id)
          ? "Tool result · trimmed for model context"
        : ({ user: "You", assistant: "Assistant", tool: "Tool result" })[message.role] || "Message",
      text: String(message.content),
    });
    for (const call of message.tool_calls || []) {
      if (call.kind === "custom") {
        // Custom call arguments are provider-defined text, not JSON input.
        // The renderer assigns this string with textContent, so markup stays inert.
        rows.push({ label: `Custom call · ${String(call.name || "")}`, text: String(call.arguments ?? "") });
      } else {
        rows.push({ label: `Tool request · ${String(call.name || "")}`, text: prettyArguments(call.arguments) });
      }
    }
  }
  if (session?._ui_live_text) rows.push({ label: "Assistant · writing", text: session._ui_live_text });
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
    synced: "Connected · live updates",
    ready: "Connected · polling for updates",
    connecting: "Connecting to the local host…",
    offline: "Disconnected · reconnect to resume",
    needs_resync: "Refreshing workspace state…",
    failed: "The local host is unavailable",
  })[connection] || "Waiting for the local host…";

  if (active) {
    byId("context-summary").textContent = session.title || "Untitled conversation";
    byId("context-status").textContent = statusLabel(session);
    byId("context-turn").textContent = session.turn_id > 0
      ? `Turn ${session.turn_id} · Step ${session.step || 0}`
      : "No turns yet";
    byId("context-history").textContent = `${messages.length} messages · ${events.length} events`;
    byId("context-source").textContent = imported
      ? "Imported Session v4 · read-only"
      : "Local conversation";
    byId("context-parent").textContent = typeof session.parent_session_id === "string"
      ? session.parent_session_id
      : "None";
  } else {
    byId("context-summary").textContent = "Select a conversation to view its current state.";
    byId("context-status").textContent = "No conversation selected";
    byId("context-turn").textContent = "—";
    byId("context-history").textContent = "—";
    byId("context-source").textContent = "Not available";
    byId("context-parent").textContent = "—";
  }

  byId("context-read-only").hidden = !active || !imported;
  byId("context-host-status").textContent = hasError
    ? "Connection interrupted. Reconnect to refresh the current workspace state."
    : `Local host · ${connectionLabel.toLowerCase()}`;
  byId("shell-status").textContent = hasError ? "Connection interrupted · reconnect to resume" : connectionLabel;
  byId("shell-status-dot").dataset.state = hasError ? "offline" : connection || "connecting";
}
