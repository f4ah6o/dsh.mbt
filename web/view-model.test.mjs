import test from "node:test";
import assert from "node:assert/strict";
import { authModelRefreshKey, isBusy, isReadOnly, statusLabel, sessionList, acceptsSnapshot, prettyArguments, runError, displayMessages, loadWorkspaceMetadata, createWorkspaceMetadataRefresher, updateWorkspaceMetadata, JAPANESE_FONT_STACKS, setJapaneseFont, restoreJapaneseFont } from "./view-model.js";
import { drawSceneSnapshot } from "./canvas-renderer.js";

test("connected accounts without a model catalog are eligible for one refresh", () => {
  const auth = {
    state: "connected",
    account: { profile_id: "profile-a" },
    models: [],
  };
  assert.equal(authModelRefreshKey({ ...auth, state: "signing_in" }), null);
  assert.equal(authModelRefreshKey(auth), "profile-a");
  assert.equal(authModelRefreshKey({ ...auth, models: [{ slug: "model-a" }] }), null);
  assert.equal(authModelRefreshKey({ ...auth, account: null }), "connected");
});

test("pending approval blocks another prompt and exposes a review status", () => {
  assert.equal(isBusy({ status: "awaiting_approval" }), true);
  assert.equal(isBusy({ status: "running" }), true);
  assert.equal(isBusy({ status: "idle", pending_approval: { call_id: "c1" } }), true);
  assert.equal(isBusy({ status: "completed" }), false);
  assert.equal(statusLabel({ status: "awaiting_approval" }), "承認待ち");
});

test("imported Session v4 is visibly read-only", () => {
  const imported = { status: "completed", source_format: "deepseek-session-v4" };
  assert.equal(isReadOnly(imported), true);
  assert.equal(statusLabel(imported), "読み取り専用 · 完了");
  assert.equal(isReadOnly({ status: "completed" }), false);
  assert.equal(statusLabel({ status: "completed" }), "完了");
});

test("failed imported Session v4 does not suggest it can be continued", () => {
  const imported = { status: "failed", source_format: "deepseek-session-v4", events: [] };
  assert.match(runError(imported), /続けることはできません/);
  assert.doesNotMatch(runError(imported), /新しいメッセージを送信できます/);
});

test("a stale poll cannot replace a newer mutation response", () => {
  const current = { id: "s1", turn_id: 2, status: "cancelled", events: [1, 2, 3, 4] };
  assert.equal(acceptsSnapshot({ id: "s1", turn_id: 1, events: [1, 2, 3, 4] }, current), false);
  assert.equal(acceptsSnapshot({ id: "s1", turn_id: 2, status: "running", events: [1, 2, 3] }, current), false);
  assert.equal(acceptsSnapshot({ ...current, events: [1, 2, 3, 4, 5] }, current), true);
  assert.equal(acceptsSnapshot({ id: "s2", turn_id: 1, events: [] }, current), true);
  const projected = { id: "s1", turn_id: 3, events: [1, 2], stream_revision: 18, messages: [] };
  assert.equal(acceptsSnapshot({ ...projected, stream_revision: 12 }, projected), false);
  assert.equal(acceptsSnapshot({ ...projected, stream_revision: 19 }, projected), true);
  // Legacy session-v1 snapshots have no revision and retain their old rule.
  assert.equal(acceptsSnapshot({ id: "s1", turn_id: 3, events: [1, 2] }, { id: "s1", turn_id: 3, events: [1, 2] }), true);
});

test("provider errors are selected from the active failed turn only", () => {
  const session = { status: "failed", turn_id: 2, events: [
    { turn_id: 1, data: { error: "old" } },
    { turn_id: 2, type: "turn/end", data: { error: "Provider authentication failed" } },
  ] };
  assert.equal(runError(session), "Provider authentication failed");
  assert.equal(runError({ ...session, status: "running" }), "");
  assert.notEqual(runError({ ...session, turn_id: 3 }), "old");
});

test("arguments remain literal data and invalid JSON remains reviewable", () => {
  assert.equal(prettyArguments("<script>alert(1)</script>"), "<script>alert(1)</script>");
  assert.equal(prettyArguments({ command: "printf hi" }), '{\n  "command": "printf hi"\n}');
  assert.throws(() => sessionList({}), /invalid session list/);
  assert.deepEqual(sessionList([{ id: "s1" }, null, {}]), [{ id: "s1" }]);
});

test("accessible transcript includes reasoning and tool arguments without system prompts", () => {
  const messages = displayMessages({ messages: [
    { role: "system", content: "hidden" },
    { role: "user", content: "hello" },
    { role: "assistant", content: "answer", reasoning: "reason", tool_calls: [
      { name: "read_file", arguments: '{"path":"README.md"}' },
      { kind: "custom", name: "terminal", arguments: '{"command":"<script>literal</script>"}' },
    ] },
    { role: "tool", content: "result" },
  ] });
  assert.deepEqual(messages.map((item) => item.label), ["あなた", "推論", "アシスタント", "ツール要求 · read_file", "カスタム呼び出し · terminal", "ツール結果"]);
  assert.equal(messages[4].text, '{"command":"<script>literal</script>"}');
  assert.equal(messages.some((item) => item.text === "hidden"), false);
});

test("transcript keeps original tool output visible and labels its model projection", () => {
  const messages = displayMessages({
    events: [{ type: "tool/result/pruned", data: { call_id: "c1", result_seq: 4 } }],
    messages: [{ role: "tool", tool_call_id: "c1", content: "full original output" }],
  });
  assert.deepEqual(messages, [{
    label: "ツール結果 · モデル入力用に短縮",
    text: "full original output",
  }]);
});

test("accessible transcript labels provisional reasoning and partial answer explicitly", () => {
  const rows = displayMessages({ messages: [
    { role: "assistant", content: "kept text", reasoning: "working it out", provisional: true, stream_status: "partial" },
    { role: "assistant", content: "final text", provisional: false },
  ] });
  assert.deepEqual(rows.map((item) => item.label), ["推論 · 一部表示", "アシスタント · 一部表示", "アシスタント"]);
});

test("workspace metadata uses a same-origin no-store read and updates project/provider context", async () => {
  let request;
  const metadata = await loadWorkspaceMetadata(async (url, options) => {
    request = { url, options };
    return { ok: true, json: async () => ({ ok: true, result: {
      project: "sample-project",
      repository: { name: "sample-repository", branch: "feature/context", detached: false },
      provider: "provider.example",
      model: "model-fixture",
    } }) };
  });
  assert.equal(request.url, "/api/metadata");
  assert.equal(request.options.cache, "no-store");
  assert.equal(request.options.credentials, "same-origin");
  assert.equal(metadata.repository.branch, "feature/context");

  const elements = new Map(["project-name", "repository-name", "branch-name", "provider-model"]
    .map((id) => [id, { textContent: "" }]));
  updateWorkspaceMetadata(metadata, { getElementById: (id) => elements.get(id) });
  assert.equal(elements.get("project-name").textContent, "sample-project");
  assert.equal(elements.get("repository-name").textContent, "sample-repository");
  assert.equal(elements.get("branch-name").textContent, "feature/context");
  assert.equal(elements.get("provider-model").textContent, "provider.example · model-fixture");
  updateWorkspaceMetadata({ ...metadata, repository: { name: "repo", branch: "0123456789ab", detached: true } }, {
    getElementById: (id) => elements.get(id),
  });
  assert.equal(elements.get("branch-name").textContent, "HEAD 分離 · 0123456789ab");
  assert.equal(await loadWorkspaceMetadata(async () => ({ ok: false })), null);
});

test("workspace metadata refresh coalesces requests and ignores stale account context", async () => {
  let now = 0;
  let context = "profile-a";
  let requests = 0;
  let resolveRequest;
  const updates = [];
  const refresher = createWorkspaceMetadataRefresher({
    intervalMs: 10_000,
    now: () => now,
    getContextKey: () => context,
    onMetadata: (metadata) => updates.push(metadata),
    fetchImpl: () => {
      requests += 1;
      return new Promise((resolve) => { resolveRequest = resolve; });
    },
  });
  const first = refresher.refresh({ force: true });
  assert.equal(refresher.refresh({ force: true }), first, "simultaneous refreshes share one request");
  assert.equal(requests, 1);
  context = "profile-b";
  resolveRequest({
    ok: true,
    async json() { return { ok: true, result: { provider: "old-provider", model: "old-model" } }; },
  });
  await first;
  assert.deepEqual(updates, [], "a response from the previous auth context is discarded");

  now = 10_001;
  const second = refresher.refresh();
  assert.equal(requests, 2);
  resolveRequest({
    ok: true,
    async json() { return { ok: true, result: { provider: "new-provider", model: "new-model" } }; },
  });
  await second;
  assert.deepEqual(updates, [{ provider: "new-provider", model: "new-model" }]);
  assert.equal(await refresher.refresh(), null, "ordinary polls are rate limited");
});

test("Japanese font preference is validated, applied to CSS, and restored", () => {
  let stored = null;
  let fontFamily = "";
  const picker = { value: "" };
  const documentRef = {
    documentElement: { style: { setProperty: (name, value) => { if (name === "--dsh-font-family") fontFamily = value; } } },
    getElementById: (id) => id === "japanese-font" ? picker : null,
  };
  const storage = { setItem: (_key, value) => { stored = value; }, getItem: () => stored };
  assert.equal(setJapaneseFont("noto", documentRef, storage), "noto");
  assert.equal(picker.value, "noto");
  assert.match(fontFamily, /Noto Sans JP/);
  assert.equal(restoreJapaneseFont(documentRef, storage), "noto");
  assert.equal(setJapaneseFont("unexpected-font", documentRef, storage), "system");
  assert.equal(picker.value, "system");
  assert.equal(Object.hasOwn(JAPANESE_FONT_STACKS, "noto"), true);
});

test("Canvas leaf rejects a malformed frame before clearing an existing frame", () => {
  const context = { save() { throw new Error("paint started"); } };
  assert.throws(() => drawSceneSnapshot(context, {
    schema_version: 1, resources: [], items: [{ kind: "image" }], clip_chains: [],
    viewport: { x: 0, y: 0, width: 320, height: 200 }, scale: 1,
}, { width: 320, height: 200, scale: 1 }), /Unsupported Canvas scene item/);
});

test("Canvas transcript paint honors the selected Japanese font stack", () => {
  let selectedFont = "";
  const context = {
    canvas: { ownerDocument: {
      documentElement: {},
      defaultView: { getComputedStyle: () => ({ getPropertyValue: () => '"Noto Sans JP", sans-serif' }) },
    } },
    save() {}, restore() {}, setTransform() {}, clearRect() {}, beginPath() {}, rect() {}, clip() {},
    transform() {}, fillRect() {}, fillText() {},
  };
  drawSceneSnapshot(context, {
    schema_version: 1,
    resources: [],
    items: [{
      id: 1, kind: "text", text: "日本語", font_size: 14,
      bounds: { x: 0, y: 0, width: 100, height: 20 },
      transform: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 },
      opacity: 1, color: { red: 0, green: 0, blue: 0, alpha: 255 }, clip_chain_id: null,
    }],
    clip_chains: [],
    viewport: { x: 0, y: 0, width: 100, height: 30 },
    scale: 1,
  }, { width: 100, height: 30, scale: 1 });
  selectedFont = context.font;
  assert.equal(selectedFont, '14px "Noto Sans JP", sans-serif');
});
