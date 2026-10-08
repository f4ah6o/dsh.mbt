import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const ORIGIN = "https://dsh.test";
const ASSETS = [
  "/", "/index.html", "/kumo-standalone.css",
  "/yami-kumo-components.css", "/yami-kumo-shell.css",
  "/manifest.webmanifest", "/icon.svg", "/moonbit/browser.js",
];
const ACTIVE_URL = `${ORIGIN}/__dsh_shell_active__`;
const LEGACY_NAME = "dsh-shell-v1";

class MemoryCache {
  entries = new Map();

  key(request) {
    return request instanceof Request ? request.url : new Request(request).url;
  }

  async match(request) {
    const value = this.entries.get(this.key(request));
    return value?.clone();
  }

  async put(request, response) {
    const key = this.key(request);
    const stored = response.clone();
    await response.clone().arrayBuffer();
    this.entries.set(key, stored);
  }

  async delete(request) {
    return this.entries.delete(this.key(request));
  }

  async keys() {
    return [...this.entries.keys()].map((url) => new Request(url));
  }
}

class MemoryCacheStorage {
  caches = new Map();

  async open(name) {
    if (!this.caches.has(name)) this.caches.set(name, new MemoryCache());
    return this.caches.get(name);
  }

  async delete(name) {
    return this.caches.delete(name);
  }

  async keys() {
    return [...this.caches.keys()];
  }
}

function contentType(path) {
  if (path === "/" || path.endsWith(".html")) return "text/html; charset=utf-8";
  if (path.endsWith(".css")) return "text/css; charset=utf-8";
  if (path.endsWith(".webmanifest")) return "application/manifest+json";
  if (path.endsWith(".svg")) return "image/svg+xml";
  return "text/javascript; charset=utf-8";
}

function shellResponse(path, version, headers = {}) {
  return new Response(`${version}:${path}`, {
    headers: { "content-type": contentType(path), ...headers },
  });
}

async function seedGeneration(caches, name, version) {
  const cache = await caches.open(name);
  for (const path of ASSETS) {
    await cache.put(new Request(`${ORIGIN}${path}`), shellResponse(path, version));
  }
}

async function seedActiveGeneration(caches, name) {
  const meta = await caches.open("dsh-shell-meta-v1");
  await meta.put(
    new Request(ACTIVE_URL),
    new Response(name, { headers: { "content-type": "text/plain" } }),
  );
}

async function readActiveGeneration(caches) {
  const meta = await caches.open("dsh-shell-meta-v1");
  const response = await meta.match(new Request(ACTIVE_URL));
  return response?.text();
}

async function assertClientBundle(worker, clientId, version) {
  for (const path of ASSETS) {
    const response = await shellFetch(worker, path, { clientId });
    assert.ok(response, `${path} is served from the pinned shell`);
    assert.equal(await response.text(), `${version}:${path}`, `${path} belongs to ${version}`);
  }
}

function createWorker({ fetchImpl, clients = [], timeoutMs, cacheStorage: sharedCacheStorage } = {}) {
  const script = SW_SCRIPT;
  const cacheStorage = sharedCacheStorage || new MemoryCacheStorage();
  const listeners = new Map();
  const liveClients = [...clients];
  let deadlineTimerFired = false;
  let abortCalls = 0;
  const controllers = [];
  class TrackingAbortController extends AbortController {
    constructor() {
      super();
      controllers.push(this);
    }
    abort(...args) {
      abortCalls += 1;
      return super.abort(...args);
    }
  }
  const self = {
    location: { origin: ORIGIN },
    addEventListener(name, callback) { listeners.set(name, callback); },
    skipWaiting() { return Promise.resolve(); },
    clients: {
      async matchAll() { return [...liveClients]; },
      async claim() {},
    },
  };
  const nativeSetTimeout = globalThis.setTimeout;
  const context = {
    self,
    caches: cacheStorage,
    fetch: (input, init) => {
      const request = new Request(input, init);
      return fetchImpl(request, { signal: init?.signal ?? request.signal });
    },
    Request,
    Response,
    Headers,
    URL,
    AbortController: TrackingAbortController,
    setTimeout: (callback, milliseconds) =>
      nativeSetTimeout(
        () => {
          if (milliseconds >= 1000) deadlineTimerFired = true;
          callback();
        },
        timeoutMs === undefined || milliseconds < 1000 ? milliseconds : timeoutMs,
      ),
    clearTimeout: globalThis.clearTimeout,
  };
  vm.runInNewContext(script, context, { filename: "web/sw.js" });
  return {
    listeners,
    caches: cacheStorage,
    liveClients,
    deadlineFired: () => deadlineTimerFired,
    abortCalls: () => abortCalls,
    controllerSignals: () => controllers.map((controller) => controller.signal),
  };
}

const SW_SOURCE = await readFile(new URL("./sw.js", import.meta.url), "utf8");
const SW_SCRIPT = SW_SOURCE.replace(/^export \{[^\n]+\}\s*$/m, "");
assert.notEqual(SW_SCRIPT, SW_SOURCE, "generated service worker export is removed only for isolated vm execution");

function lifecycle(worker, name) {
  let pending;
  worker.listeners.get(name)({ waitUntil(value) { pending = value; } });
  assert.ok(pending, `${name} handler should register its lifecycle work`);
  return pending;
}

function shellFetch(worker, path, {
  clientId,
  resultingClientId,
  mode = "same-origin",
  method = "GET",
  authorization,
} = {}) {
  const url = new URL(path, ORIGIN);
  const headers = new Headers();
  if (authorization) headers.set("authorization", authorization);
  let response;
  worker.listeners.get("fetch")({
    request: { url: url.href, method, mode, headers },
    clientId,
    resultingClientId,
    respondWith(value) { response = Promise.resolve(value); },
  });
  return response;
}

function versionedFetcher(getVersion) {
  return async (request) => {
    const url = new URL(request.url);
    return shellResponse(url.pathname, getVersion());
  };
}

test("reload updates same-URL assets and keeps each page on a coherent offline generation", async () => {
  let version = "v1";
  let offline = false;
  const worker = createWorker({
    fetchImpl: async (request) => {
      if (offline) throw new Error("offline");
      return versionedFetcher(() => version)(request);
    },
    clients: [{ id: "existing-page" }],
  });
  await seedGeneration(worker.caches, LEGACY_NAME, "v0");

  await lifecycle(worker, "install");
  await lifecycle(worker, "activate");
  await assertClientBundle(worker, "existing-page", "v0");

  let response = await shellFetch(worker, "/", {
    clientId: "existing-page",
    resultingClientId: "page-v1",
    mode: "navigate",
  });
  assert.equal(await response.text(), "v1:/");
  await assertClientBundle(worker, "page-v1", "v1");

  version = "v2";
  response = await shellFetch(worker, "/", {
    clientId: "page-v1",
    resultingClientId: "page-v2",
    mode: "navigate",
  });
  assert.equal(await response.text(), "v2:/");
  await assertClientBundle(worker, "page-v2", "v2");

  offline = true;
  const offlineResponse = await shellFetch(worker, "/", {
    clientId: "page-v2",
    resultingClientId: "page-offline",
    mode: "navigate",
  });
  assert.equal(await offlineResponse.text(), "v2:/");
  await assertClientBundle(worker, "page-offline", "v2");
});

test("refresh stages the whole bundle before switching and keeps the prior bundle on partial failure", async () => {
  let version = "v2";
  let blockApplicationAsset = true;
  let releaseApplicationAsset;
  let signalApplicationAsset;
  const applicationAssetStarted = new Promise((resolve) => { signalApplicationAsset = resolve; });
  const blockedApplicationAsset = new Promise((resolve) => { releaseApplicationAsset = resolve; });
  let failBridge = false;
  const fetchImpl = async (request) => {
    const path = new URL(request.url).pathname;
    if (path === "/moonbit/browser.js" && blockApplicationAsset) {
      signalApplicationAsset();
      return blockedApplicationAsset;
    }
    if (path === "/yami-kumo-components.css" && failBridge) {
      throw new Error("bridge unavailable during partial deployment");
    }
    return shellResponse(path, version);
  };
  const worker = createWorker({
    fetchImpl,
    clients: [{ id: "old-page" }],
  });
  const previous = "dsh-shell-generation-previous";
  await seedGeneration(worker.caches, previous, "v1");
  await seedActiveGeneration(worker.caches, previous);
  await lifecycle(worker, "activate");

  const navigationPromise = shellFetch(worker, "/", {
    clientId: "old-page",
    resultingClientId: "new-page",
    mode: "navigate",
  });
  await applicationAssetStarted;

  await assertClientBundle(worker, "old-page", "v1");
  assert.equal(await readActiveGeneration(worker.caches), previous);

  blockApplicationAsset = false;
  releaseApplicationAsset(shellResponse("/moonbit/browser.js", version));
  assert.equal(await (await navigationPromise).text(), "v2:/");
  const complete = await readActiveGeneration(worker.caches);
  assert.notEqual(complete, previous);
  await assertClientBundle(worker, "new-page", "v2");

  version = "v3";
  failBridge = true;
  const failedNavigation = await shellFetch(worker, "/", {
    clientId: "new-page",
    resultingClientId: "failed-refresh-page",
    mode: "navigate",
  });
  assert.equal(await failedNavigation.text(), "v2:/");
  assert.equal(await readActiveGeneration(worker.caches), complete);
  await assertClientBundle(worker, "failed-refresh-page", "v2");
  assert.deepEqual(
    (await worker.caches.keys()).filter((name) => name.startsWith("dsh-shell-generation-")).sort(),
    [complete, previous].sort(),
  );
});

test("an active worker's cleanup preserves a newer worker's in-flight generation", async () => {
  const sharedCaches = new MemoryCacheStorage();
  const oldWorker = createWorker({
    fetchImpl: versionedFetcher(() => "v1"),
    clients: [{ id: "old-page" }],
    cacheStorage: sharedCaches,
  });
  const previous = "dsh-shell-generation-previous";
  await seedGeneration(sharedCaches, previous, "v0");
  await seedActiveGeneration(sharedCaches, previous);
  await lifecycle(oldWorker, "activate");

  let releaseApplicationAsset;
  let signalApplicationAsset;
  const applicationAssetStarted = new Promise((resolve) => { signalApplicationAsset = resolve; });
  const blockedApplicationAsset = new Promise((resolve) => { releaseApplicationAsset = resolve; });
  const newWorker = createWorker({
    fetchImpl: async (request) => {
      const path = new URL(request.url).pathname;
      if (path === "/moonbit/browser.js") {
        signalApplicationAsset();
        return blockedApplicationAsset;
      }
      return shellResponse(path, "v2");
    },
    clients: [{ id: "old-page" }],
    cacheStorage: sharedCaches,
  });
  const installPromise = lifecycle(newWorker, "install");
  await applicationAssetStarted;
  const staged = (await sharedCaches.keys()).find(
    (name) => name.startsWith("dsh-shell-generation-") && name !== previous,
  );
  assert.ok(staged, "new worker creates an isolated candidate cache");

  const oldNavigation = await shellFetch(oldWorker, "/", {
    clientId: "old-page",
    resultingClientId: "old-page-next",
    mode: "navigate",
  });
  assert.equal(await oldNavigation.text(), "v1:/");
  oldWorker.liveClients.push({ id: "old-page-next" });
  newWorker.liveClients.push({ id: "old-page-next" });
  assert.ok((await sharedCaches.keys()).includes(staged), "old-worker cleanup preserves staged generation");

  releaseApplicationAsset(shellResponse("/moonbit/browser.js", "v2"));
  await installPromise;
  await lifecycle(newWorker, "activate");
  assert.equal(await readActiveGeneration(sharedCaches), staged);
  await assertClientBundle(newWorker, "old-page-next", "v1");
});

test("a response body that never closes times out and falls back to the complete active bundle", async () => {
  let stalledFetchAborted = false;
  let stalledFetchRequested = false;
  const stalledSignals = [];
  let streamController;
  const worker = createWorker({
    // Keep the synthetic deadline long enough that unrelated Node event-loop
    // scheduling from preceding tests cannot win the race with AbortSignal's
    // event delivery. The product deadline remains 10 seconds.
    timeoutMs: 100,
    fetchImpl: async (request, { signal }) => {
      const path = new URL(request.url).pathname;
      if (path === "/moonbit/browser.js") {
        stalledFetchRequested = true;
        stalledSignals.push(signal);
        const body = new ReadableStream({
          start(controller) {
            streamController = controller;
            controller.enqueue(new TextEncoder().encode("headers arrived; body remains open"));
          },
        });
        signal.addEventListener("abort", () => {
          stalledFetchAborted = true;
          streamController.error(new Error("fetch aborted"));
        });
        return new Response(body, {
          headers: { "content-type": "text/javascript; charset=utf-8" },
        });
      }
      return shellResponse(path, "v1");
    },
    clients: [{ id: "known-page" }],
  });
  const known = "dsh-shell-generation-known";
  await seedGeneration(worker.caches, known, "v1");
  await seedActiveGeneration(worker.caches, known);
  await lifecycle(worker, "activate");

  const timedOut = await shellFetch(worker, "/", {
    clientId: "known-page",
    resultingClientId: "timeout-page",
    mode: "navigate",
  });
  assert.equal(await timedOut.text(), "v1:/");
  assert.equal(stalledFetchRequested, true, "the browser module is included in the generated cache candidate");
  assert.equal(stalledSignals.length, 1, "one browser module fetch participates in this refresh");
  assert.equal(worker.deadlineFired(), true, "the per-asset deadline elapsed");
  assert.ok(worker.abortCalls() > 0, "the deadline aborts its fetch controller");
  assert.equal(worker.controllerSignals().some((signal) => signal.aborted), true, "an asset controller is aborted");
  assert.equal(
    stalledSignals.some((signal) => signal.aborted),
    true,
    `the generated fetch signal is aborted (fetch signals: ${stalledSignals.map((signal) => signal.aborted).join(",")}; asset controller signals: ${worker.controllerSignals().map((signal) => signal.aborted).join(",")})`,
  );
  assert.equal(stalledFetchAborted, true, "the deadline remains active after response headers arrive");
  assert.equal(await readActiveGeneration(worker.caches), known);
  await assertClientBundle(worker, "timeout-page", "v1");
}, { timeout: 5000 });

test("oversized shell assets cannot replace the active generation", async () => {
  const worker = createWorker({
    fetchImpl: async (request) => {
      const path = new URL(request.url).pathname;
      if (path === "/moonbit/browser.js") {
        const body = new ReadableStream({
          start(controller) {
            controller.enqueue(new Uint8Array(4 * 1024 * 1024 + 1));
            controller.close();
          },
        });
        return new Response(body, {
          headers: {
            "content-type": "text/javascript; charset=utf-8",
          },
        });
      }
      return shellResponse(path, "v2");
    },
    clients: [{ id: "known-page" }],
  });
  const known = "dsh-shell-generation-known";
  await seedGeneration(worker.caches, known, "v1");
  await seedActiveGeneration(worker.caches, known);
  await lifecycle(worker, "activate");

  const fallback = await shellFetch(worker, "/", {
    clientId: "known-page",
    resultingClientId: "oversize-page",
    mode: "navigate",
  });
  assert.equal(await fallback.text(), "v1:/");
  assert.equal(await readActiveGeneration(worker.caches), known);
  await assertClientBundle(worker, "oversize-page", "v1");
});

test("API, event, command, and credential paths bypass shell caches", async () => {
  const worker = createWorker({
    timeoutMs: 10,
    fetchImpl: async (request) => shellResponse(new URL(request.url).pathname, "v1"),
    clients: [{ id: "known-page" }],
  });
  const known = "dsh-shell-generation-known";
  await seedGeneration(worker.caches, known, "v1");
  await seedActiveGeneration(worker.caches, known);
  await lifecycle(worker, "activate");

  const before = await worker.caches.keys();
  for (const request of [
    { path: "/api/v1/snapshot" },
    { path: "/api/v1/events?cursor=7" },
    { path: "/api/v1/commands/cmd-1" },
    { path: "/api/call", method: "POST" },
    { path: "/auth/callback?code=oauth-secret" },
    { path: "/moonbit/browser.js?code=oauth-secret" },
    { path: "/moonbit/browser.js", authorization: "Bearer credential-secret" },
    { path: "https://other.test/moonbit/browser.js" },
  ]) {
    assert.equal(shellFetch(worker, request.path, request), undefined, `${request.path} bypasses the SW`);
  }
  assert.deepEqual(await worker.caches.keys(), before);

  const leakingWorker = createWorker({
    fetchImpl: async (request) => {
      const path = new URL(request.url).pathname;
      if (path === "/moonbit/browser.js") {
        return new Response('{"access_token":"never-cache-this"}', {
          headers: { "content-type": "application/json" },
        });
      }
      return shellResponse(path, "v2");
    },
  });
  await seedGeneration(leakingWorker.caches, known, "v1");
  await seedActiveGeneration(leakingWorker.caches, known);
  const failedInstall = await lifecycle(leakingWorker, "install").then(
    () => undefined,
    (error) => error,
  );
  assert.ok(failedInstall, "non-shell credential-shaped data fails whole-shell validation");

  const cachedBodies = [];
  for (const name of await leakingWorker.caches.keys()) {
    for (const key of await (await leakingWorker.caches.open(name)).keys()) {
      cachedBodies.push(await (await (await leakingWorker.caches.open(name)).match(key)).text());
    }
  }
  assert.ok(!cachedBodies.some((body) => body.includes("never-cache-this")));
  assert.ok(!cachedBodies.some((body) => body.includes("oauth-secret")));
  assert.ok(!cachedBodies.some((body) => body.includes("credential-secret")));
});
