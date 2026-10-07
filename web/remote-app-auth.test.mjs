import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import {
  authModelRefreshKey,
  displayMessages,
  isBusy,
  isReadOnly,
  prettyArguments,
  runError,
  statusLabel,
} from "./view-model.js";

const appSource = readFileSync(new URL("./remote-app.js", import.meta.url), "utf8");

function fakeElement(id = "") {
  const listeners = new Map();
  const element = {
    id,
    children: [],
    dataset: {},
    style: { setProperty() {} },
    classList: { toggle() {} },
    listeners,
    hidden: false,
    disabled: false,
    value: "",
    textContent: "",
    scrollTop: 0,
    scrollHeight: 0,
    clientHeight: 0,
    clientWidth: 640,
    addEventListener(name, callback) { listeners.set(name, callback); },
    setAttribute() {},
    removeAttribute() {},
    replaceChildren(...children) { this.children = [...children]; },
    append(...children) { this.children.push(...children); },
    appendChild(child) { this.children.push(child); return child; },
    querySelector(selector) {
      if (selector === ".empty-list") return this.children.find((child) => child.className === "empty-list") || null;
      return null;
    },
    querySelectorAll() { return []; },
    focus() {},
    remove() {},
    insertBefore(child, before) {
      const index = this.children.indexOf(before);
      this.children.splice(index < 0 ? this.children.length : index, 0, child);
    },
    getContext() { return {}; },
  };
  return element;
}

function auth(state, models = [], profileId = "profile-test") {
  return {
    state,
    account: state === "connected" || state === "signing_in"
      ? { email: "owner@example.test", profile_id: profileId }
      : null,
    plan_usage: "enabled",
    scopes: [],
    models,
    selected_model: null,
  };
}

function createHarness({ failFirstModelRefresh = false, initialAuth = auth("signed_out"), deferModelRefresh = false } = {}) {
  const elements = new Map();
  const getElement = (id) => {
    if (!elements.has(id)) elements.set(id, fakeElement(id));
    return elements.get(id);
  };
  const document = {
    hidden: false,
    documentElement: { style: { setProperty() {} } },
    getElementById: getElement,
    createElement: (tag) => {
      const element = fakeElement();
      element.tagName = tag;
      return element;
    },
    createDocumentFragment: () => fakeElement(),
    addEventListener() {},
  };
  const timers = new Map();
  let timerId = 0;
  const setTimer = (callback, delay) => {
    const id = ++timerId;
    timers.set(id, { callback, delay });
    return id;
  };
  const clearTimer = (id) => timers.delete(id);

  let currentAuth = structuredClone(initialAuth);
  let backendAuth = structuredClone(initialAuth);
  let signInRequested = false;
  let postSignInSnapshots = 0;
  let modelRefreshes = 0;
  let shouldFail = failFirstModelRefresh;
  let signalModelRequestStarted;
  const modelRequestStarted = new Promise((resolve) => { signalModelRequestStarted = resolve; });
  let resolveModelResponse;
  const pendingModelResponse = new Promise((resolve) => { resolveModelResponse = resolve; });
  const client = {
    beginConnect() {},
    connectionFailed() {},
    state() {
      return {
        auth: structuredClone(currentAuth),
        projection: { sessions: [] },
        selected_session: null,
        selected_session_projection: null,
        scope_key: "test-scope",
        draft: "",
        connection: "synced",
        follow_latest: true,
        text_view: false,
        pending_commands: [],
      };
    },
    async snapshot() {
      if (signInRequested) {
        postSignInSnapshots += 1;
        currentAuth = postSignInSnapshots === 1
          ? auth("signing_in")
          : structuredClone(backendAuth.state === "connected" ? backendAuth : auth("connected"));
      } else {
        currentAuth = structuredClone(backendAuth);
      }
      return { result: { status: "applied" } };
    },
    subscribe() { return () => {}; },
    async reconcileReceipts() {},
    persistNow() {},
    closeStream() {},
    saveDraft() {},
    setFollowLatest() {},
    setScrollAnchor() {},
    setTextView() {},
  };

  const fetch = async (_url, init) => {
    const operation = JSON.parse(init.body).operation;
    if (operation === "auth_sign_in") {
      signInRequested = true;
      return {
        ok: true,
        status: 202,
        async json() { return { ok: true, result: { started: true } }; },
      };
    }
    if (operation === "auth_models") {
      modelRefreshes += 1;
      if (deferModelRefresh) {
        signalModelRequestStarted();
        return pendingModelResponse;
      }
      if (shouldFail) {
        shouldFail = false;
        return {
          ok: false,
          status: 503,
          async json() { return { ok: false, error: "fixture model request failed" }; },
        };
      }
      backendAuth = auth("connected", [
        { slug: "gpt-6-luna", display_name: "GPT-6 Luna" },
      ]);
      return {
        ok: true,
        status: 200,
        async json() { return { ok: true, result: { models: backendAuth.models } }; },
      };
    }
    throw new Error("unexpected operation: " + operation);
  };

  const window = {
    visualViewport: { height: 820, addEventListener() {} },
    matchMedia: () => ({ matches: false }),
    addEventListener() {},
  };
  const source = appSource
    .replace('import * as bridge from "/moonbit/client.js";\n', "")
    .replace('import { createRemoteClient } from "./remote-client.js";\n', "")
    .replace('import { drawSceneSnapshot } from "./canvas-renderer.js";\n', "")
    .replace(/^import \{[\s\S]*?\} from "\.\/view-model\.js";\n/m, "")
    .replace("const client = createRemoteClient({ bridge });", "const client = testClient;")
    .replace('state.moon = await import("/moonbit/app.js");', "state.moon = testMoon;")
    .replace("start().catch(connectionError);", "globalThis.__testApi = { start, refreshSnapshot }; globalThis.__appStarted = start();");
  assert.notEqual(source, appSource, "the test must instrument the actual remote app module");

  const sandbox = {
    testClient: client,
    testMoon: { render_ui() {}, measure_ui() { return 0; } },
    document,
    window,
    fetch,
    setTimeout: setTimer,
    clearTimeout: clearTimer,
    requestAnimationFrame: () => 1,
    ResizeObserver: class { observe() {} },
    innerHeight: 820,
    isBusy,
    isReadOnly,
    statusLabel,
    prettyArguments,
    runError,
    displayMessages,
    authModelRefreshKey,
  };
  vm.runInNewContext(source, sandbox, { filename: "web/remote-app.js" });

  return {
    elements,
    timers,
    get modelRefreshes() { return modelRefreshes; },
    modelRequestStarted,
    resolveModelResponse,
    async start() { await sandbox.__appStarted; },
    setAuth(value) {
      currentAuth = structuredClone(value);
      backendAuth = structuredClone(value);
    },
    async refresh() { await sandbox.__testApi.refreshSnapshot(); },
    async click(id) {
      const handler = getElement(id).listeners.get("click");
      assert.ok(handler, "expected a click handler for #" + id);
      await handler({ preventDefault() {} });
    },
    async fireAuthPoll() {
      const entry = [...timers.entries()].find(([, timer]) => timer.delay === 2000);
      assert.ok(entry, "expected a scheduled sign-in status poll");
      timers.delete(entry[0]);
      await entry[1].callback();
    },
  };
}

test("sign-in polling discovers models after the first connected snapshot", async () => {
  const app = createHarness();
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.modelRefreshes, 0, "the first sign-in response still reports signing_in");
  await app.fireAuthPoll();

  assert.equal(app.modelRefreshes, 1);
  const picker = app.elements.get("model-picker");
  assert.ok(picker.children.some((option) => option.value === "gpt-6-luna"));
  assert.equal(picker.disabled, false);
  assert.equal(app.elements.get("auth-models-retry").hidden, true);
});

test("failed model discovery is visible and waits for an explicit retry", async () => {
  const app = createHarness({ failFirstModelRefresh: true });
  await app.start();
  await app.click("auth-sign-in");
  await app.fireAuthPoll();

  assert.equal(app.modelRefreshes, 1);
  assert.match(app.elements.get("auth-guidance").textContent, /could not be loaded/i);
  assert.equal(app.elements.get("auth-models-retry").hidden, false);
  assert.equal([...app.timers.values()].filter((timer) => timer.delay === 2000).length, 0);

  await app.click("auth-models-retry");
  assert.equal(app.modelRefreshes, 2);
  assert.ok(app.elements.get("model-picker").children.some((option) => option.value === "gpt-6-luna"));
  assert.equal(app.elements.get("auth-models-retry").hidden, true);
});

test("a stale account refresh error does not hide a newer account model catalog", async () => {
  const app = createHarness({
    initialAuth: auth("connected", [], "profile-a"),
    deferModelRefresh: true,
  });
  const starting = app.start();
  await app.modelRequestStarted;

  app.setAuth(auth("connected", [
    { slug: "model-b", display_name: "Model B" },
  ], "profile-b"));
  await app.refresh();

  const picker = app.elements.get("model-picker");
  assert.ok(picker.children.some((option) => option.value === "model-b"));
  assert.equal(app.elements.get("auth-models-retry").hidden, true);
  assert.doesNotMatch(app.elements.get("auth-guidance").textContent, /loading|could not be loaded/i);

  app.resolveModelResponse({
    ok: false,
    status: 409,
    async json() { return { ok: false, error: "AUTH_ACCOUNT_CHANGED" }; },
  });
  await starting;

  assert.ok(picker.children.some((option) => option.value === "model-b"));
  assert.equal(app.elements.get("auth-models-retry").hidden, true);
  assert.doesNotMatch(app.elements.get("auth-guidance").textContent, /loading|could not be loaded/i);
});
