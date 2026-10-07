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

function auth(state, models = [], profileId = "profile-test", selectedModel = null) {
  return {
    state,
    account: state === "connected" || state === "signing_in"
      ? { email: "owner@example.test", profile_id: profileId }
      : null,
    plan_usage: "enabled",
    scopes: [],
    models,
    selected_model: selectedModel,
  };
}

function createHarness({
  failFirstModelRefresh = false,
  initialAuth = auth("signed_out"),
  deferModelRefresh = false,
  origin = "http://127.0.0.1:3210",
  popupBlocked = false,
  signInResult = {
    started: true,
    authorization_url: "https://auth.openai.com/api/accounts/authorize?client_id=fixture",
  },
  signInFailure = null,
  failPostSignInSnapshot = false,
  failSelectModel = false,
  deferSelectModel = false,
} = {}) {
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
  let signInRequests = 0;
  const selectedModelRequests = [];
  let signalSelectModelRequestStarted;
  const selectModelRequestStarted = new Promise((resolve) => { signalSelectModelRequestStarted = resolve; });
  let resolveSelectModelResponse;
  const pendingSelectModelResponse = new Promise((resolve) => { resolveSelectModelResponse = resolve; });
  const operations = [];
  const openedTabs = [];
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
        if (failPostSignInSnapshot) throw new Error("fixture snapshot failed");
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
    const payload = JSON.parse(init.body);
    const operation = payload.operation;
    operations.push(operation);
    if (operation === "auth_sign_in_browser") {
      signInRequests += 1;
      if (signInFailure) {
        return {
          ok: false,
          status: signInFailure.status || 503,
          async json() { return { ok: false, error: signInFailure.error || "fixture sign-in preparation failed" }; },
        };
      }
      signInRequested = true;
      return {
        ok: true,
        status: 202,
        async json() { return { ok: true, result: structuredClone(signInResult) }; },
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
    if (operation === "auth_select_model") {
      const model = payload.input.model;
      selectedModelRequests.push(model);
      if (deferSelectModel) {
        signalSelectModelRequestStarted();
        return pendingSelectModelResponse.then((response) => {
          if (response.ok) backendAuth.selected_model = model;
          return response;
        });
      }
      if (failSelectModel) {
        return {
          ok: false,
          status: 503,
          async json() { return { ok: false, error: "fixture model selection failed" }; },
        };
      }
      backendAuth.selected_model = model;
      return {
        ok: true,
        status: 200,
        async json() { return { ok: true, result: { ok: true, model } }; },
      };
    }
    throw new Error("unexpected operation: " + operation);
  };

  const window = {
    location: new URL(origin),
    visualViewport: { height: 820, addEventListener() {} },
    matchMedia: () => ({ matches: false }),
    addEventListener() {},
    open(url, target) {
      if (popupBlocked) return null;
      const tab = {
        opener: window,
        closed: false,
        replacedUrl: null,
        close() { this.closed = true; },
        location: { replace(value) { tab.replacedUrl = value; } },
      };
      openedTabs.push({ url, target, tab });
      return tab;
    },
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
    URL,
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
    get signInRequests() { return signInRequests; },
    get selectedModelRequests() { return selectedModelRequests; },
    get operations() { return operations; },
    get openedTabs() { return openedTabs; },
    modelRequestStarted,
    resolveModelResponse,
    selectModelRequestStarted,
    resolveSelectionResponse(model) {
      resolveSelectModelResponse({
        ok: true,
        status: 200,
        async json() { return { ok: true, result: { ok: true, model } }; },
      });
    },
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
    async changeModel(value) {
      const picker = getElement("model-picker");
      const handler = picker.listeners.get("change");
      assert.ok(handler, "expected a change handler for #model-picker");
      picker.value = value;
      await handler();
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

  assert.equal(app.signInRequests, 1);
  assert.deepEqual(app.openedTabs.map(({ url, target }) => [url, target]), [["about:blank", "_blank"]]);
  assert.equal(app.openedTabs[0].tab.opener, null);
  assert.equal(app.openedTabs[0].tab.replacedUrl, "https://auth.openai.com/api/accounts/authorize?client_id=fixture");
  assert.equal(app.modelRefreshes, 0, "the first sign-in response still reports signing_in");
  await app.fireAuthPoll();

  assert.equal(app.modelRefreshes, 1);
  const picker = app.elements.get("model-picker");
  assert.ok(picker.children.some((option) => option.value === "gpt-6-luna"));
  assert.equal(picker.disabled, false);
  assert.equal(app.elements.get("auth-models-retry").hidden, true);
});

for (const selectedModel of [null, "gpt-6-luna"]) {
  test(`model picker applies a new selection when the current model is ${selectedModel || "unset"}`, async () => {
    const models = [
      { slug: "gpt-6-luna", display_name: "GPT-6 Luna" },
      { slug: "gpt-6-astra", display_name: "GPT-6 Astra" },
    ];
    const app = createHarness({
      initialAuth: auth("connected", models, "profile-test", selectedModel),
    });
    await app.start();

    await app.changeModel("gpt-6-astra");

    assert.deepEqual(app.selectedModelRequests, ["gpt-6-astra"]);
    assert.equal(app.elements.get("model-picker").value, "gpt-6-astra");
    assert.equal(app.elements.get("action-message").textContent, "Using GPT-6 Astra.");
  });
}

test("empty model selection makes no host request", async () => {
  const app = createHarness({
    initialAuth: auth("connected", [
      { slug: "gpt-6-luna", display_name: "GPT-6 Luna" },
    ]),
  });
  await app.start();

  await app.changeModel("");

  assert.deepEqual(app.selectedModelRequests, []);
});

test("failed model selection restores the previously active model", async () => {
  const models = [
    { slug: "gpt-6-luna", display_name: "GPT-6 Luna" },
    { slug: "gpt-6-astra", display_name: "GPT-6 Astra" },
  ];
  const app = createHarness({
    initialAuth: auth("connected", models, "profile-test", "gpt-6-luna"),
    failSelectModel: true,
  });
  await app.start();

  await app.changeModel("gpt-6-astra");

  assert.deepEqual(app.selectedModelRequests, ["gpt-6-astra"]);
  assert.equal(app.elements.get("model-picker").value, "gpt-6-luna");
  assert.match(app.elements.get("run-error").textContent, /fixture model selection failed/i);
});

test("busy model selection ignores another picker change", async () => {
  const models = [
    { slug: "gpt-6-luna", display_name: "GPT-6 Luna" },
    { slug: "gpt-6-astra", display_name: "GPT-6 Astra" },
  ];
  const app = createHarness({
    initialAuth: auth("connected", models, "profile-test", "gpt-6-luna"),
    deferSelectModel: true,
  });
  await app.start();

  const selection = app.changeModel("gpt-6-astra");
  await app.selectModelRequestStarted;
  assert.equal(app.elements.get("model-picker").disabled, true);
  await app.changeModel("gpt-6-luna");
  assert.deepEqual(app.selectedModelRequests, ["gpt-6-astra"]);

  app.resolveSelectionResponse("gpt-6-astra");
  await selection;
  assert.equal(app.elements.get("model-picker").value, "gpt-6-astra");
});

test("blocked sign-in pop-up makes no host request", async () => {
  const app = createHarness({ popupBlocked: true });
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.openedTabs.length, 0);
  assert.equal(app.signInRequests, 0);
  assert.equal(app.operations.includes("auth_sign_in_browser"), false);
  assert.match(app.elements.get("run-error").textContent, /blocked the sign-in tab/i);
});

test("failed browser preparation closes the reserved tab", async () => {
  const app = createHarness({ signInFailure: { status: 503, error: "fixture preparation failed" } });
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.signInRequests, 1);
  assert.equal(app.openedTabs[0].tab.opener, null);
  assert.equal(app.openedTabs[0].tab.closed, true);
  assert.equal(app.openedTabs[0].tab.replacedUrl, null);
  assert.match(app.elements.get("run-error").textContent, /fixture preparation failed/i);
});

test("duplicate browser sign-in closes the reserved tab", async () => {
  const app = createHarness({ signInResult: { started: false } });
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.signInRequests, 1);
  assert.equal(app.openedTabs[0].tab.closed, true);
  assert.equal(app.openedTabs[0].tab.replacedUrl, null);
  assert.match(app.elements.get("action-message").textContent, /already in progress/i);
});

test("untrusted authorization URL closes the reserved tab", async () => {
  const app = createHarness({
    signInResult: { started: true, authorization_url: "https://attacker.example/authorize" },
  });
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.openedTabs[0].tab.closed, true);
  assert.equal(app.openedTabs[0].tab.replacedUrl, null);
  assert.match(app.elements.get("run-error").textContent, /invalid ChatGPT authorization URL/i);
});

test("a refresh failure after navigation leaves the OAuth tab open", async () => {
  const app = createHarness({ failPostSignInSnapshot: true });
  await app.start();
  await app.click("auth-sign-in");

  assert.equal(app.openedTabs[0].tab.closed, false);
  assert.equal(app.openedTabs[0].tab.replacedUrl, "https://auth.openai.com/api/accounts/authorize?client_id=fixture");
  assert.match(app.elements.get("run-error").textContent, /fixture snapshot failed/i);
});

test("Tailnet UI disables sign-in and never requests a host browser handoff", async () => {
  const app = createHarness({ origin: "https://machine.example-tailnet.ts.net:8443" });
  await app.start();

  assert.equal(app.elements.get("auth-sign-in").disabled, true);
  await app.click("auth-sign-in");
  assert.equal(app.openedTabs.length, 0);
  assert.equal(app.signInRequests, 0);
  assert.match(app.elements.get("run-error").textContent, /host Mac/i);
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
