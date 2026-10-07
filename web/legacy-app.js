import { drawSceneSnapshot } from "./canvas-renderer.js";
import { isBusy, isReadOnly, statusLabel, sessionList, acceptsSnapshot, prettyArguments, runError, displayMessages } from "./view-model.js";

const $ = (id) => document.getElementById(id);
const state = {
  moon: null, sessions: [], id: null, snapshot: { messages: [] },
  selection: 0, mutation: false, poll: null, polling: false, lastList: 0,
  follow: true, textView: false, frame: null, transcriptKey: "", statusKey: "", actionError: "", actionMessage: "",
};
const scroll = $("transcript-scroll");
const canvas = $("transcript-canvas");
const context = canvas.getContext("2d");

function connectionError(error) {
  $("connection-error-text").textContent = error instanceof Error ? error.message : String(error);
  $("connection-error").hidden = false;
}

function clearConnectionError() { $("connection-error").hidden = true; }

async function api(operation, input = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  try {
    const response = await fetch("/api/call", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ operation, input }), signal: controller.signal,
    });
    let payload;
    try { payload = await response.json(); } catch { throw new Error(`Server response could not be read (HTTP ${response.status}).`); }
    if (!response.ok || !payload.ok) throw new Error(payload.error || `Request failed (HTTP ${response.status}).`);
    return payload.result;
  } catch (error) {
    if (error.name === "AbortError") throw new Error("The request timed out. Reconnect to check the session's current state.");
    if (error instanceof TypeError) throw new Error("Cannot reach the local server. Check that it is running, then reconnect.");
    throw error;
  } finally { clearTimeout(timeout); }
}

function renderSessions() {
  const container = $("sessions");
  // Retain focused buttons across polls. Session titles and IDs are data only.
  const existing = new Map([...container.querySelectorAll("button[data-id]")].map((button) => [button.dataset.id, button]));
  if (!state.sessions.length) {
    if (!container.querySelector(".empty-list")) {
      container.replaceChildren();
      const empty = document.createElement("p");
      empty.className = "empty-list";
      empty.textContent = "No sessions yet. Send a prompt to begin.";
      container.append(empty);
    }
    return;
  }
  container.querySelector(".empty-list")?.remove();
  let cursor = container.firstElementChild;
  for (const session of [...state.sessions].reverse()) {
    let button = existing.get(session.id);
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "session-option";
      button.dataset.id = session.id;
      const title = document.createElement("span"); title.className = "session-option-title";
      const status = document.createElement("span"); status.className = "session-option-state";
      button.append(title, status);
      button.addEventListener("click", () => selectSession(session.id));
    }
    button.children[0].textContent = session.title || "Untitled session";
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
  const canPrune = !readOnly && !busy && ["idle", "completed"].includes(session.status)
    && (session.events || []).some((event) => event.type === "tool/result");
  const canFork = Boolean(state.id) && !readOnly && !busy
    && ["idle", "completed", "failed", "cancelled"].includes(session.status);
  $("session-title").textContent = state.id ? session.title || "Untitled session" : "Agent workspace";
  $("status").textContent = statusLabel(session);
  $("status").dataset.state = approval ? "approval" : session.status || "idle";
  $("progress").textContent = session.turn_id > 0 ? `Turn ${session.turn_id} · Step ${session.step || 0}` : "";
  $("cancel").disabled = state.mutation || !busy;
  $("fork-session").disabled = state.mutation || !canFork;
  $("prune-results").hidden = !canPrune;
  $("prune-results").disabled = state.mutation || !canPrune;
  $("new-session").disabled = state.mutation;
  $("prompt").disabled = readOnly;
  $("prompt").placeholder = readOnly ? "Imported history is read-only" : "What would you like to work on?";
  $("send").disabled = state.mutation || busy || readOnly || !state.moon || !$("prompt").value.trim();
  $("composer-hint").textContent = readOnly ? "This imported history is read-only and cannot be continued." : approval ? "Review the tool request to continue." : busy ? "The agent is working. Stop to cancel this turn." : "⌘ / Ctrl + Enter to send";
  $("approval").hidden = !approval;
  if (approval) {
    $("approval-description").textContent = `${approval.name} is waiting for permission to run.`;
    const argumentsText = prettyArguments(approval.arguments);
    if ($("approval-arguments").textContent !== argumentsText) $("approval-arguments").textContent = argumentsText;
  }
  $("approve").disabled = state.mutation || !approval;
  $("deny").disabled = state.mutation || !approval;
  const error = state.actionError || runError(session);
  $("run-error").hidden = !error;
  $("run-error").textContent = error;
  $("action-message").hidden = !state.actionMessage;
  $("action-message").textContent = state.actionMessage;
  const statusKey = `${state.id}:${session.status}:${approval?.call_id || ""}`;
  if (state.statusKey !== statusKey) {
    $("announcement").textContent = approval ? `Approval required for ${approval.name}.` : statusLabel(session);
    state.statusKey = statusKey;
  }
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
    const article = document.createElement("article"); article.className = "text-message";
    const heading = document.createElement("h2"); heading.textContent = message.label;
    const content = document.createElement("pre"); content.textContent = message.text;
    article.append(heading, content); fragment.append(article);
  }
  if (!messages.length) {
    const empty = document.createElement("p"); empty.textContent = "Send a prompt to start."; fragment.append(empty);
  }
  container.replaceChildren(fragment);
  if (state.follow || wasBottom) container.scrollTop = container.scrollHeight;
}

function paint() {
  state.frame = null;
  if (!state.moon || state.textView) return;
  const width = Math.max(1, Math.floor(scroll.clientWidth));
  const height = Math.max(1, Math.floor(scroll.clientHeight));
  const scale = Math.min(3, window.devicePixelRatio || 1);
  try {
    const extent = state.moon.measure_ui(JSON.stringify(state.snapshot), width);
    $("scene-spacer").style.height = `${Math.max(0, extent - height)}px`;
    canvas.style.height = `${height}px`;
    if (canvas.width !== Math.round(width * scale) || canvas.height !== Math.round(height * scale)) {
      canvas.width = Math.round(width * scale); canvas.height = Math.round(height * scale);
    }
    if (state.follow) scroll.scrollTop = Math.max(0, extent - height);
    const presentation = { ...state.snapshot, _ui_scroll_top: Math.round(scroll.scrollTop) };
    const scene = JSON.parse(state.moon.render_ui(JSON.stringify(presentation), width, height));
    drawSceneSnapshot(context, scene, { width, height, scale });
    $("jump-latest").hidden = state.follow || extent <= height;
  } catch (error) { connectionError(new Error(`Conversation rendering failed: ${error.message}`)); }
}

function schedulePaint() {
  if (state.frame === null) state.frame = requestAnimationFrame(paint);
}

function acceptSnapshot(snapshot) {
  if (!snapshot || snapshot.id !== state.id) return;
  if (!acceptsSnapshot(snapshot, state.snapshot)) return;
  state.snapshot = snapshot;
  const index = state.sessions.findIndex((row) => row.id === snapshot.id);
  if (index >= 0) state.sessions[index] = snapshot;
  else state.sessions.push(snapshot);
  renderSessions(); renderControls(); renderAccessibleTranscript(); schedulePaint();
}

async function refresh({ list = false } = {}) {
  const selected = state.id;
  const selection = state.selection;
  if (list || Date.now() - state.lastList > 5000) {
    state.sessions = sessionList(await api("session_list"));
    state.sessions = state.sessions.map((session) => session.id === state.id
      && !acceptsSnapshot(session, state.snapshot) ? state.snapshot : session);
    state.lastList = Date.now();
    renderSessions();
    if (!state.id && state.sessions.length) {
      const latest = state.sessions.at(-1);
      state.id = latest.id; state.selection += 1; state.follow = true;
      acceptSnapshot(latest);
    }
  }
  if (selected && selected === state.id && selection === state.selection) {
    const snapshot = await api("session_get", { session_id: selected });
    if (selection === state.selection) acceptSnapshot(snapshot);
  }
  clearConnectionError();
}

function schedulePoll(delay = 1200) {
  clearTimeout(state.poll);
  state.poll = setTimeout(poll, delay);
}

async function poll() {
  if (state.polling) return;
  state.polling = true;
  try { await refresh(); }
  catch (error) { connectionError(error); }
  finally {
    state.polling = false;
    schedulePoll(document.hidden ? 5000 : isBusy(state.snapshot) ? 900 : 2000);
  }
}

async function selectSession(id) {
  const alreadySelected = id === state.id;
  state.selection += 1; state.follow = true; state.actionError = ""; state.actionMessage = "";
  if (alreadySelected) { renderControls(); return; }
  state.id = id;
  renderControls();
  const selection = state.selection;
  const cached = state.sessions.find((row) => row.id === id);
  if (cached) acceptSnapshot(cached);
  try {
    const snapshot = await api("session_get", { session_id: id });
    if (selection === state.selection) { acceptSnapshot(snapshot); clearConnectionError(); }
  } catch (error) { if (selection === state.selection) connectionError(error); }
}

async function mutate(body) {
  if (state.mutation) return;
  state.mutation = true; state.actionError = ""; state.actionMessage = ""; renderControls();
  try { await body(); clearConnectionError(); }
  catch (error) { state.actionError = error instanceof Error ? error.message : String(error); }
  finally { state.mutation = false; renderControls(); schedulePoll(100); }
}

async function createSession(title) {
  const selection = state.selection;
  const session = await api("session_create", title ? { title } : {});
  if (selection === state.selection) {
    state.id = session.id; state.selection += 1; state.follow = true;
    acceptSnapshot(session);
  } else {
    if (!state.sessions.some((row) => row.id === session.id)) state.sessions.push(session);
    renderSessions();
  }
  return session;
}

$("new-session").addEventListener("click", () => mutate(async () => {
  const session = await createSession(`Session ${state.sessions.length + 1}`);
  if (session.id === state.id) $("prompt").focus();
}));
$("fork-session").addEventListener("click", () => mutate(async () => {
  const sourceId = state.id;
  const selection = state.selection;
  if (!sourceId) return;
  const child = await api("session_fork", { session_id: sourceId });
  if (!state.sessions.some((row) => row.id === child.id)) state.sessions.push(child);
  if (state.id === sourceId && state.selection === selection) {
    state.id = child.id;
    state.selection += 1;
    state.follow = true;
    state.actionMessage = `Forked ${sourceId} as an independent conversation.`;
    acceptSnapshot(child);
  } else {
    renderSessions();
  }
}));
$("prune-results").addEventListener("click", () => mutate(async () => {
  const id = state.id;
  const selection = state.selection;
  let result;
  try { result = await api("session_prune_tool_results", { session_id: id }); }
  catch (error) {
    if (state.id !== id || state.selection !== selection) return;
    throw error;
  }
  if (state.id !== id || state.selection !== selection) return;
  if (result.session.id === id) acceptSnapshot(result.session);
  const count = result.pruned.length;
  state.actionMessage = count > 0
    ? `Trimmed ${count} tool result${count === 1 ? "" : "s"} for future model requests. Full original output remains in this session's event history.`
    : "No oversized tool results needed trimming.";
}));
$("composer").addEventListener("submit", (event) => {
  event.preventDefault();
  const entered = $("prompt").value;
  const prompt = entered.trim();
  if (!prompt || isBusy(state.snapshot) || isReadOnly(state.snapshot) || !state.moon) return;
  mutate(async () => {
    const id = state.id || (await createSession(prompt.slice(0, 60))).id;
    const snapshot = await api("session_send", { session_id: id, prompt });
    if (state.id === id) {
      if ($("prompt").value === entered) $("prompt").value = "";
      state.follow = true; acceptSnapshot(snapshot); $("prompt").focus();
    }
  });
});
$("prompt").addEventListener("input", renderControls);
$("prompt").addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && !event.isComposing) {
    event.preventDefault(); if (!$("send").disabled) $("composer").requestSubmit();
  }
});
$("cancel").addEventListener("click", () => mutate(async () => {
  const id = state.id;
  const snapshot = await api("session_cancel", { session_id: id });
  if (state.id === id) acceptSnapshot(snapshot);
}));
for (const [button, approved] of [["approve", true], ["deny", false]]) {
  $(button).addEventListener("click", () => {
    const pending = state.snapshot.pending_approval;
    const id = state.id;
    if (!pending) return;
    mutate(async () => {
      const snapshot = await api("tool_approve", { session_id: id, call_id: pending.call_id, approved });
      if (state.id === id) acceptSnapshot(snapshot);
    });
  });
}
$("text-view").addEventListener("click", () => {
  state.textView = !state.textView;
  $("text-view").setAttribute("aria-pressed", String(state.textView));
  $("text-view").textContent = state.textView ? "Canvas view" : "Text view";
  scroll.hidden = state.textView;
  $("text-transcript").classList.toggle("sr-only", !state.textView);
  $("jump-latest").hidden = true;
  if (!state.textView) schedulePaint();
});
scroll.addEventListener("scroll", () => {
  if (state.textView) return;
  state.follow = scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 48;
  schedulePaint();
}, { passive: true });
$("text-transcript").addEventListener("scroll", () => {
  if (!state.textView) return;
  const text = $("text-transcript");
  state.follow = text.scrollTop + text.clientHeight >= text.scrollHeight - 48;
  $("jump-latest").hidden = state.follow;
}, { passive: true });
$("jump-latest").addEventListener("click", () => {
  state.follow = true;
  if (state.textView) {
    const text = $("text-transcript"); text.scrollTop = text.scrollHeight; $("jump-latest").hidden = true;
  } else schedulePaint();
});
canvas.addEventListener("contextlost", (event) => { event.preventDefault(); });
canvas.addEventListener("contextrestored", schedulePaint);
new ResizeObserver(schedulePaint).observe($("transcript-area"));
window.addEventListener("resize", schedulePaint);
window.addEventListener("online", () => schedulePoll(0));
document.addEventListener("visibilitychange", () => { if (!document.hidden) schedulePoll(0); });
$("reconnect").addEventListener("click", async () => {
  $("reconnect").disabled = true;
  try { if (!state.moon) await loadMoon(); await refresh({ list: true }); schedulePaint(); }
  catch (error) { connectionError(error); }
  finally { $("reconnect").disabled = false; renderControls(); schedulePoll(100); }
});

async function loadMoon() {
  state.moon = await import("/moonbit/app.js");
  if (typeof state.moon.render_ui !== "function" || typeof state.moon.measure_ui !== "function") {
    state.moon = null;
    throw new Error("The UI build is missing. Build the MoonBit browser module, then reconnect.");
  }
}

async function start() {
  renderControls();
  try { await loadMoon(); await refresh({ list: true }); }
  catch (error) { connectionError(error); }
  finally { renderControls(); renderAccessibleTranscript(); schedulePaint(); schedulePoll(); }
}
start();
