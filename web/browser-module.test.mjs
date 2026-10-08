import test from "node:test";
import assert from "node:assert/strict";

test("the linked MoonBit browser module mounts its Yami-kumo shell without a JS wrapper", async () => {
  const root = { innerHTML: "" };
  globalThis.document = {
    addEventListener() {},
    getElementById(id) {
      return id === "root" ? root : null;
    },
  };
  try {
    const browser = await import(`./moonbit/browser.js?fixture=${Date.now()}`);
    assert.equal(typeof browser.start, "function");
    assert.equal(typeof browser.shell_html, "function");
    assert.equal(root.innerHTML, browser.shell_html());
    assert.match(root.innerHTML, /id="transcript-canvas"/);
    assert.match(root.innerHTML, /aria-label="会話の記録"/);
    assert.doesNotMatch(root.innerHTML, /<script|\s+on\w+=/i);
  } finally {
    delete globalThis.document;
  }
});
