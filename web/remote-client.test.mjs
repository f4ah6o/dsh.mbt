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
