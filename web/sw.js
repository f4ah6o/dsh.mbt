const GENERATION_PREFIX = "dsh-shell-generation-";
const META_CACHE = "dsh-shell-meta-v1";
const STAGING_PREFIX = "/__dsh_shell_staging__/";
const SHELL_FETCH_TIMEOUT_MS = 10000;
const MAX_SHELL_ASSET_BYTES = 4 * 1024 * 1024;
const MAX_SHELL_BUNDLE_BYTES = 8 * 1024 * 1024;
const LEGACY_CACHES = new Set(["dsh-shell-v1", "dsh-shell-v2"]);
const SHELL_ASSETS = [
  "/",
  "/index.html",
  "/style.css",
  "/yami-kumo-shell.css",
  "/yami-kumo-shell.js",
  "/app.js",
  "/legacy-app.js",
  "/remote-app.js",
  "/remote-client.js",
  "/view-model.js",
  "/canvas-renderer.js",
  "/manifest.webmanifest",
  "/icon.svg",
  "/moonbit/app.js",
  "/moonbit/client.js",
];
const SHELL_PATHS = new Set(
  SHELL_ASSETS.map((asset) => new URL(asset, self.location.origin).pathname),
);
const SHELL_CONTENT_TYPES = new Set([
  "application/javascript",
  "application/manifest+json",
  "image/svg+xml",
  "text/css",
  "text/html",
  "text/javascript",
]);
const ACTIVE_KEY = new Request(`${self.location.origin}/__dsh_shell_active__`);
const PENDING_KEY = new Request(`${self.location.origin}/__dsh_shell_pending__`);
const CLIENT_PIN_PREFIX = "/__dsh_shell_client__/";

let refreshInFlight;
let generationCounter = 0;

function shellCacheKey(url) {
  return new Request(`${url.origin}${url.pathname}`, { method: "GET" });
}

function clientPinKey(clientId) {
  return new Request(
    `${self.location.origin}${CLIENT_PIN_PREFIX}${encodeURIComponent(clientId)}`,
  );
}

function generationStagingKey(generation) {
  return new Request(
    `${self.location.origin}${STAGING_PREFIX}${encodeURIComponent(generation)}`,
  );
}

function isGenerationName(name) {
  return name.startsWith(GENERATION_PREFIX) || LEGACY_CACHES.has(name);
}

function isCacheableShellResponse(request, response, requestURL) {
  if (!response.ok || response.type === "opaque") return false;
  if (request.headers.has("authorization")) return false;

  const contentType = (response.headers.get("content-type") || "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (!SHELL_CONTENT_TYPES.has(contentType)) return false;

  const cacheControl = response.headers.get("cache-control") || "";
  if (/\bprivate\b/i.test(cacheControl)) return false;
  if (response.headers.has("set-cookie")) return false;
  // The host currently sends no-store on every response, including its fixed
  // application files. Cache only these allowlisted shell MIME types; dynamic
  // API, credential, and event data never enters a generation cache.
  const vary = response.headers.get("vary");
  if (vary && vary.trim() !== "") return false;

  if (response.url) {
    const responseURL = new URL(response.url);
    if (
      responseURL.origin !== requestURL.origin ||
      responseURL.pathname !== requestURL.pathname ||
      responseURL.search !== ""
    ) {
      return false;
    }
  }
  return true;
}

async function consumeBoundedBody(response, budget) {
  const contentLength = response.headers.get("content-length");
  if (contentLength !== null) {
    const declaredLength = Number(contentLength);
    if (!Number.isSafeInteger(declaredLength) || declaredLength < 0) {
      throw new Error("Invalid shell asset content length");
    }
    if (declaredLength > MAX_SHELL_ASSET_BYTES) {
      throw new Error("Shell asset exceeds the per-asset size limit");
    }
    if (declaredLength > MAX_SHELL_BUNDLE_BYTES - budget.bytes) {
      throw new Error("Shell bundle exceeds the total size limit");
    }
  }

  const reader = response.body?.getReader();
  if (!reader) return;
  let assetBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return;
      const chunkBytes = value?.byteLength || 0;
      assetBytes += chunkBytes;
      budget.bytes += chunkBytes;
      if (assetBytes > MAX_SHELL_ASSET_BYTES) {
        throw new Error("Shell asset exceeds the per-asset size limit");
      }
      if (budget.bytes > MAX_SHELL_BUNDLE_BYTES) {
        throw new Error("Shell bundle exceeds the total size limit");
      }
    }
  } catch (error) {
    try {
      await reader.cancel(error);
    } catch {
      // The fetch abort or source stream may already have cancelled it.
    }
    throw error;
  } finally {
    reader.releaseLock();
  }
}

async function fetchAndCacheShellAsset(request, assetURL, cache, budget, generation) {
  const controller = new AbortController();
  let timeoutId;
  let timedOut = false;
  const timeout = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      timedOut = true;
      controller.abort();
      reject(new Error(`Timed out fetching shell asset: ${new URL(request.url).pathname}`));
    }, SHELL_FETCH_TIMEOUT_MS);
  });

  const work = (async () => {
    const response = await fetch(request, { signal: controller.signal });
    if (!isCacheableShellResponse(request, response, assetURL)) {
      throw new Error(`Invalid shell asset response: ${assetURL.pathname}`);
    }
    const cacheResponse = response.clone();
    await consumeBoundedBody(response, budget);
    await cache.put(shellCacheKey(assetURL), cacheResponse);
  })();

  try {
    await Promise.race([work, timeout]);
  } catch (error) {
    controller.abort();
    if (timedOut) {
      // A Cache API write cannot be cancelled. If it completes after its
      // deadline, remove the still-inactive candidate once more.
      void work.then(
        async () => { await caches.delete(generation); },
        () => undefined,
      ).catch(() => undefined);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

async function metadataCache() {
  return caches.open(META_CACHE);
}

async function readMetadata(key) {
  const cache = await metadataCache();
  const response = await cache.match(key);
  return response ? response.text() : undefined;
}

async function writeMetadata(key, value) {
  const cache = await metadataCache();
  await cache.put(key, new Response(value, {
    headers: { "content-type": "text/plain; charset=utf-8" },
  }));
}

async function readActiveGeneration() {
  const name = await readMetadata(ACTIVE_KEY);
  if (!name || !isGenerationName(name)) return undefined;
  return (await caches.keys()).includes(name) ? name : undefined;
}

async function readClientGeneration(clientId) {
  if (!clientId) return undefined;
  const name = await readMetadata(clientPinKey(clientId));
  return name && isGenerationName(name) ? name : undefined;
}

async function createShellGeneration() {
  generationCounter += 1;
  const generation =
    `${GENERATION_PREFIX}${Date.now()}-${generationCounter}-${Math.random().toString(36).slice(2)}`;
  const stagingKey = generationStagingKey(generation);
  await writeMetadata(stagingKey, "1");

  try {
    const cache = await caches.open(generation);
    const budget = { bytes: 0 };
    // Each response is bounded through body consumption and its candidate
    // cache write. The cache remains private until every asset has completed.
    const results = await Promise.allSettled(SHELL_ASSETS.map(async (asset) => {
      const assetURL = new URL(asset, self.location.origin);
      const request = new Request(assetURL.href, {
        method: "GET",
        cache: "no-cache",
        credentials: "same-origin",
        mode: "same-origin",
      });
      await fetchAndCacheShellAsset(request, assetURL, cache, budget, generation);
    }));

    const failed = results.find((result) => result.status === "rejected");
    if (failed) throw failed.reason;
    return generation;
  } catch (error) {
    await caches.delete(generation);
    await (await metadataCache()).delete(stagingKey);
    throw error;
  }
}

async function clearGenerationStaging(generation) {
  await (await metadataCache()).delete(generationStagingKey(generation));
}

async function findLegacyGeneration() {
  const names = await caches.keys();
  return [...LEGACY_CACHES].find((name) => names.includes(name));
}

async function stageForInstall() {
  const generation = await createShellGeneration();
  try {
    await writeMetadata(PENDING_KEY, generation);
  } catch (error) {
    await caches.delete(generation);
    throw error;
  } finally {
    await clearGenerationStaging(generation);
  }
}

async function activateGeneration() {
  const pendingName = await readMetadata(PENDING_KEY);
  const cachedGenerations = await caches.keys();
  const pending = pendingName && isGenerationName(pendingName) && cachedGenerations.includes(pendingName)
    ? pendingName
    : undefined;
  const current = (await readActiveGeneration()) || await findLegacyGeneration();
  const clientsBeforeClaim = await self.clients.matchAll({
    type: "window",
    includeUncontrolled: true,
  });

  // Keep already-open pages on their previous complete shell while the new
  // generation becomes active for newly opened or reloaded pages.
  if (current) {
    for (const client of clientsBeforeClaim) {
      if (!await readClientGeneration(client.id)) {
        await writeMetadata(clientPinKey(client.id), current);
      }
    }
  }

  const active = pending && isGenerationName(pending) ? pending : current;
  if (active) await writeMetadata(ACTIVE_KEY, active);
  await (await metadataCache()).delete(PENDING_KEY);
  await self.clients.claim();
  await cleanupOldGenerations(new Set(clientsBeforeClaim.map((client) => client.id)));
}

async function cleanupOldGenerations(additionalLiveClients = new Set()) {
  const meta = await metadataCache();
  const clients = await self.clients.matchAll({
    type: "window",
    includeUncontrolled: true,
  });
  const liveClients = new Set([
    ...clients.map((client) => client.id),
    ...additionalLiveClients,
  ]);
  const retained = new Set();
  const active = await readActiveGeneration();
  if (active) retained.add(active);
  const pending = await readMetadata(PENDING_KEY);
  if (pending && isGenerationName(pending)) retained.add(pending);

  for (const request of await meta.keys()) {
    const pathname = new URL(request.url).pathname;
    if (pathname.startsWith(STAGING_PREFIX)) {
      const generation = decodeURIComponent(pathname.slice(STAGING_PREFIX.length));
      if (isGenerationName(generation)) retained.add(generation);
      continue;
    }
    if (pathname.startsWith(CLIENT_PIN_PREFIX)) {
      const clientId = decodeURIComponent(pathname.slice(CLIENT_PIN_PREFIX.length));
      const generation = await readMetadata(request);
      if (!liveClients.has(clientId)) {
        await meta.delete(request);
      } else if (generation && isGenerationName(generation)) {
        retained.add(generation);
      }
    }
  }

  for (const name of await caches.keys()) {
    if (isGenerationName(name) && !retained.has(name)) {
      await caches.delete(name);
    }
  }
}

async function refreshShellGeneration() {
  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      const candidate = await createShellGeneration();
      try {
        // A single metadata write switches the complete shell after every
        // asset has been fetched, validated, and stored in the candidate.
        await writeMetadata(ACTIVE_KEY, candidate);
        return candidate;
      } catch (error) {
        await caches.delete(candidate);
        throw error;
      } finally {
        await clearGenerationStaging(candidate);
      }
    })();
  }

  const inFlight = refreshInFlight;
  try {
    return await inFlight;
  } catch {
    return await readActiveGeneration();
  } finally {
    if (refreshInFlight === inFlight) refreshInFlight = undefined;
  }
}

async function generationForClient(clientId) {
  const pinned = await readClientGeneration(clientId);
  if (pinned && (await caches.keys()).includes(pinned)) return pinned;
  return (await readActiveGeneration()) || await findLegacyGeneration();
}

async function serveFromGeneration(url, generation) {
  if (!generation) {
    return new Response("The app shell is unavailable offline.", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }
  const cache = await caches.open(generation);
  const response = await cache.match(shellCacheKey(url));
  return response || new Response("The app shell asset is unavailable.", {
    status: 503,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

async function handleShellRequest(event, requestURL) {
  let generation;
  const targetClientId = event.resultingClientId || event.clientId;
  if (event.request.mode === "navigate") {
    generation = await refreshShellGeneration();
    if (!generation) generation = await generationForClient(event.clientId);
    if (targetClientId && generation) {
      await writeMetadata(clientPinKey(targetClientId), generation);
    }
    await cleanupOldGenerations(
      targetClientId ? new Set([targetClientId]) : new Set(),
    );
  } else {
    generation = await generationForClient(event.clientId);
  }
  return serveFromGeneration(requestURL, generation);
}

self.addEventListener("install", (event) => {
  event.waitUntil(stageForInstall());
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(activateGeneration());
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const requestURL = new URL(request.url);
  if (requestURL.origin !== self.location.origin) return;
  if (!SHELL_PATHS.has(requestURL.pathname)) return;
  if (requestURL.search !== "") return;
  if (request.headers.has("authorization")) return;

  event.respondWith(handleShellRequest(event, requestURL));
});
