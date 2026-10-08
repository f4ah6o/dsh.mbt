import test from "node:test";
import assert from "node:assert/strict";
import * as bridge from "../_build/js/release/build/f4ah6o/dsh/client/client.js";
import { createRemoteClient } from "./remote-client.js";

test("remote client state reads the actual generated MoonBit bridge projection", () => {
  const client = createRemoteClient({
    bridge,
    EventSourceImpl: class {},
    fetchImpl: async () => {
      throw new Error("network must not be used by this state smoke test");
    },
  });
  const state = client.state();
  assert.equal(typeof state, "object");
  assert.equal(state.connection, "offline");
  assert.equal(state.cursor, "");
  assert.deepEqual(state.pending_commands, []);
});

test("a lost command POST with a missing receipt reports the Japanese unconfirmed state", async () => {
  const calls = [];
  const fakeBridge = {
    client_init: () => 1,
    client_new_command_id: () => "fixture-command",
    client_queue_command: () => JSON.stringify({ ok: true, command: { id: "fixture-command" } }),
    client_mark_command_sent() {},
    client_mark_command_uncertain() {},
    client_mark_receipt_missing() {},
    client_persisted_state: () => JSON.stringify({ scope_key: "" }),
    client_state: () => JSON.stringify({ pending_commands: [] }),
    client_apply_receipt: () => JSON.stringify({ ok: true }),
  };
  const client = createRemoteClient({
    bridge: fakeBridge,
    EventSourceImpl: class {},
    fetchImpl: async (url, init) => {
      calls.push({ url, method: init.method || "GET" });
      if (init.method === "POST") throw new TypeError("fixture connection lost");
      return {
        ok: false,
        status: 404,
        async json() { return { ok: false, error: "missing" }; },
      };
    },
  });

  await assert.rejects(
    client.command("session_send", "session-fixture", { prompt: "hello" }),
    /ホストは操作を受け付けたか確認できませんでした。再送信する前に受付記録を確認してください。/,
  );
  assert.deepEqual(calls, [
    { url: "/api/v1/commands", method: "POST" },
    { url: "/api/v1/commands/fixture-command", method: "GET" },
  ]);
});
