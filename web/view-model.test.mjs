import test from "node:test";
import assert from "node:assert/strict";
import { isBusy, isReadOnly, statusLabel, sessionList, acceptsSnapshot, prettyArguments, runError, displayMessages } from "./view-model.js";
import { drawSceneSnapshot } from "./canvas-renderer.js";

test("pending approval blocks another prompt and exposes a review status", () => {
  assert.equal(isBusy({ status: "awaiting_approval" }), true);
  assert.equal(isBusy({ status: "running" }), true);
  assert.equal(isBusy({ status: "idle", pending_approval: { call_id: "c1" } }), true);
  assert.equal(isBusy({ status: "completed" }), false);
  assert.equal(statusLabel({ status: "awaiting_approval" }), "Needs approval");
});

test("imported Session v4 is visibly read-only", () => {
  const imported = { status: "completed", source_format: "deepseek-session-v4" };
  assert.equal(isReadOnly(imported), true);
  assert.equal(statusLabel(imported), "Read-only · Completed");
  assert.equal(isReadOnly({ status: "completed" }), false);
  assert.equal(statusLabel({ status: "completed" }), "Completed");
});

test("failed imported Session v4 does not suggest it can be continued", () => {
  const imported = { status: "failed", source_format: "deepseek-session-v4", events: [] };
  assert.match(runError(imported), /cannot be continued/);
  assert.doesNotMatch(runError(imported), /send another prompt/);
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
    { role: "assistant", content: "answer", reasoning: "reason", tool_calls: [{ name: "read_file", arguments: '{"path":"README.md"}' }] },
    { role: "tool", content: "result" },
  ] });
  assert.deepEqual(messages.map((item) => item.label), ["You", "Reasoning", "Assistant", "Tool request · read_file", "Tool result"]);
  assert.equal(messages.some((item) => item.text === "hidden"), false);
});

test("transcript keeps original tool output visible and labels its model projection", () => {
  const messages = displayMessages({
    events: [{ type: "tool/result/pruned", data: { call_id: "c1", result_seq: 4 } }],
    messages: [{ role: "tool", tool_call_id: "c1", content: "full original output" }],
  });
  assert.deepEqual(messages, [{
    label: "Tool result · trimmed for model context",
    text: "full original output",
  }]);
});

test("accessible transcript labels provisional reasoning and partial answer explicitly", () => {
  const rows = displayMessages({ messages: [
    { role: "assistant", content: "kept text", reasoning: "working it out", provisional: true, stream_status: "partial" },
    { role: "assistant", content: "final text", provisional: false },
  ] });
  assert.deepEqual(rows.map((item) => item.label), ["Reasoning · partial", "Assistant · partial", "Assistant"]);
});

test("Canvas leaf rejects a malformed frame before clearing an existing frame", () => {
  const context = { save() { throw new Error("paint started"); } };
  assert.throws(() => drawSceneSnapshot(context, {
    schema_version: 1, resources: [], items: [{ kind: "image" }], clip_chains: [],
    viewport: { x: 0, y: 0, width: 320, height: 200 }, scale: 1,
  }, { width: 320, height: 200, scale: 1 }), /Unsupported Canvas scene item/);
});
