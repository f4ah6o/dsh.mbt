// Native-v1 browser acceptance. scripts/test-browser-smoke.sh supplies a
// temporary native demo host URL and the cached Chromium executable.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright-core");
const baseURL = process.env.DSH_BROWSER_URL;
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ||
  chromium.executablePath();
assert.ok(baseURL, "DSH_BROWSER_URL must point to the running native demo host");

const repo = fileURLToPath(new URL("../", import.meta.url));
const screenshotDirectory = path.resolve(
  process.env.DSH_SCREENSHOT_DIR || path.join(repo, "_build/browser-smoke"),
);
const failures = [];
const contexts = [];
const pages = [];
let browser;
let settingsScreenshotSaved = false;

function observePage(page) {
  pages.push(page);
  page.on("pageerror", (error) => failures.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") {
      const text = message.text();
      if (!/Failed to load resource: net::ERR_(FAILED|INTERNET_DISCONNECTED)$/.test(text)) {
        failures.push(text);
      }
    }
  });
}

async function waitForConnectedWorkspace(page) {
  await page.waitForFunction(
    () => {
      const project = document.getElementById("project-name")?.textContent || "";
      const status = document.getElementById("shell-status")?.textContent || "";
      const provider = document.getElementById("provider-model")?.textContent || "";
      return project !== "取得中…" &&
        provider !== "プロバイダーを確認中…" &&
        !status.includes("接続中");
    },
    null,
    { timeout: 20_000 },
  );
}

async function openSettings(page) {
  await page.waitForFunction(
    () => document.getElementById("settings-page")?.hidden === true &&
      document.getElementById("account-bar")?.hidden === true,
  );
  await page.locator("#settings-open").click();
  await page.waitForFunction(
    () => document.getElementById("settings-page")?.hidden === false &&
      document.getElementById("conversation-page")?.hidden === true &&
      document.getElementById("account-bar")?.hidden === false,
  );
  assert.equal(
    await page.locator("#settings-close").evaluate((node) => document.activeElement === node),
    true,
    "opening Settings moves focus to its close control",
  );
  if (!settingsScreenshotSaved) {
    await mkdir(screenshotDirectory, { recursive: true });
    await page.screenshot({
      path: path.join(screenshotDirectory, "settings.png"),
      fullPage: true,
    });
    settingsScreenshotSaved = true;
  }
}

async function postNativeCommand(page, operation, sessionId, input) {
  return page.evaluate(async ({ operation, sessionId, input }) => {
    const snapshotResponse = await fetch("/api/v1/snapshot", { cache: "no-store" });
    if (!snapshotResponse.ok) throw new Error("native snapshot failed");
    const snapshot = await snapshotResponse.json();
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    let timestamp = BigInt(Date.now());
    for (let index = 5; index >= 0; index -= 1) {
      bytes[index] = Number(timestamp & 255n);
      timestamp >>= 8n;
    }
    bytes[6] = 0x70 | (bytes[6] & 0x0f);
    bytes[8] = 0x80 | (bytes[8] & 0x3f);
    const id = Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
    const commandId = `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`;
    const response = await fetch("/api/v1/commands", {
      method: "POST",
      cache: "no-store",
      credentials: "same-origin",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        protocol_version: 1,
        workspace_id: snapshot.workspace_id,
        command_id: commandId,
        session_id: sessionId,
        operation,
        input,
        approval_revision: null,
      }),
    });
    return { status: response.status, receipt: await response.json() };
  }, { operation, sessionId, input });
}

const longImportedText = "Older archived transcript content. ".repeat(1800);
const importedAssistantRow = JSON.stringify({
  type: "assistant/message",
  data: {
    turn: 1,
    step: 1,
    message: {
      role: "assistant",
      id: "import-assistant",
      source: { kind: "model", provider: "fixture", model: "fixture-model" },
      content: [{
        type: "text",
        text: "Imported history stays read only. " + longImportedText,
      }],
    },
  },
  surfaceOp: "append",
});
const importedHistoryJsonl = [
  '{"type":"session","version":4,"id":"browser-import-fixture","createdAt":1,"isSeeded":false,"delegationDepth":0}',
  '{"type":"turn/start","data":{"turn":1}}',
  '{"type":"step/start","data":{"turn":1,"step":1}}',
  '{"type":"user/message","data":{"role":"user","id":"import-user","source":{"kind":"user"},"content":[{"type":"text","text":"Imported Japanese history"}]},"surfaceOp":"append"}',
  '{"type":"request/header","data":{"reason":"initial","header":{"config":{"provider":"fixture","model":"fixture-model"}}}}',
  '{"type":"request/context","data":{"provider":"fixture","model":"fixture-model"}}',
  importedAssistantRow,
  '{"type":"step/end","data":{"turn":1,"step":1}}',
  '{"type":"turn/end","data":{"turn":1,"reason":{"kind":"completed"}}}',
].join("\n");

async function assertHeaderFitsViewport(page) {
  const layout = await page.evaluate(() => {
    const brand = document.querySelector(".yk-brand-group").getBoundingClientRect();
    const search = document.querySelector(".yk-global-search").getBoundingClientRect();
    const actions = document.querySelector(".yk-header-end").getBoundingClientRect();
    return {
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: window.innerWidth,
      brandRight: brand.right,
      searchLeft: search.left,
      searchRight: search.right,
      actionsLeft: actions.left,
    };
  });
  assert.equal(
    layout.documentWidth,
    layout.viewportWidth,
    `the header has no horizontal overflow: ${JSON.stringify(layout)}`,
  );
  assert.ok(
    layout.brandRight <= layout.searchLeft + 1,
    `search does not cover the brand: ${JSON.stringify(layout)}`,
  );
  assert.ok(
    layout.searchRight <= layout.actionsLeft + 1,
    `header actions do not overlap search: ${JSON.stringify(layout)}`,
  );
}

async function assertReadableSessionOption(page, selector) {
  await page.waitForFunction((target) => {
    const button = document.querySelector(target);
    const title = button?.querySelector(".session-option-title");
    const status = button?.querySelector(".session-option-state");
    return (button?.getBoundingClientRect().height || 0) >= 50 &&
      (title?.getBoundingClientRect().height || 0) >= 12 &&
      (status?.getBoundingClientRect().height || 0) >= 9;
  }, selector, { timeout: 10_000 });
  const label = await page.locator(selector).evaluate((button) => {
    const title = button.querySelector(".session-option-title");
    const status = button.querySelector(".session-option-state");
    return {
      title: title?.textContent || "",
      titleHeight: title?.getBoundingClientRect().height || 0,
      statusHeight: status?.getBoundingClientRect().height || 0,
      buttonHeight: button.getBoundingClientRect().height,
    };
  });
  assert.match(label.title, /.+/, "the session title is present");
  assert.ok(label.titleHeight >= 12, `the session title has readable line height: ${JSON.stringify(label)}`);
  assert.ok(label.statusHeight >= 9, `the session status has readable line height: ${JSON.stringify(label)}`);
  assert.ok(label.buttonHeight >= 50, `the two-line session row is tall enough: ${JSON.stringify(label)}`);
}

async function waitForActiveShellWorker(page) {
  await page.waitForFunction(
    async () => {
      const registration = await navigator.serviceWorker.getRegistration("/");
      return Boolean(registration?.active && navigator.serviceWorker.controller);
    },
    null,
    { timeout: 30_000 },
  );
  const assets = await page.evaluate(async () => {
    const names = (await caches.keys()).filter((name) =>
      name.startsWith("dsh-shell-generation-"),
    );
    const requests = [];
    for (const name of names) {
      const cache = await caches.open(name);
      for (const request of await cache.keys()) {
        requests.push(new URL(request.url).pathname);
      }
    }
    return requests;
  });
  for (const asset of [
    "/index.html",
    "/kumo-standalone.css",
    "/yami-kumo-components.css",
    "/yami-kumo-shell.css",
    "/moonbit/browser.js",
  ]) {
    assert.ok(assets.includes(asset), `the active shell generation contains ${asset}`);
  }
}

async function testNativeDemo(browserInstance) {
  const context = await browserInstance.newContext({
    locale: "ja-JP",
    viewport: { width: 1280, height: 820 },
    deviceScaleFactor: 1,
  });
  contexts.push(context);
  const page = await context.newPage();
  observePage(page);
  const sentCommands = [];
  const receiptLookups = [];
  let droppedSendResponse = false;
  await page.route("**/api/v1/commands", async (route) => {
    const command = JSON.parse(route.request().postData() || "{}");
    sentCommands.push(command);
    const response = await route.fetch();
    if (command.operation === "session_send" && !droppedSendResponse) {
      droppedSendResponse = true;
      await route.abort("failed");
      return;
    }
    await route.fulfill({ response });
  });
  await page.route("**/api/v1/commands/*", async (route) => {
    receiptLookups.push(new URL(route.request().url()).pathname.split("/").at(-1));
    await route.continue();
  });
  await page.addInitScript(() => {
    window.__dshCspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.__dshCspViolations.push({
        directive: event.violatedDirective,
        blockedURI: event.blockedURI,
      });
    });
  });

  const moduleResponse = page.waitForResponse((response) =>
    response.url().endsWith("/moonbit/browser.js"),
  );
  const response = await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  assert.equal(response.status(), 200, "the native service serves the app shell");
  const csp = response.headers()["content-security-policy"] || "";
  assert.ok(csp.includes("script-src 'self'"), "the native shell has a script CSP");
  assert.ok(csp.includes("style-src 'self'"), "the native shell has a style CSP");
  assert.doesNotMatch(csp, /unsafe-inline/i, "the shell does not permit inline code or styles");
  assert.equal((await moduleResponse).status(), 200, "the compiled MoonBit browser module loads");
  await page.locator("#transcript-canvas").waitFor({ state: "attached" });
  await waitForConnectedWorkspace(page);
  assert.match(await page.locator("#provider-model").textContent(), /デモ/);
  assert.equal(await page.locator(".session-option").count(), 0);
  assert.match(await page.locator(".empty-list").textContent(), /会話はまだありません/);
  await assertHeaderFitsViewport(page);

  await waitForActiveShellWorker(page);
  const registration = await page.evaluate(async () => {
    const value = await navigator.serviceWorker.getRegistration("/");
    return {
      scriptURL: value?.active?.scriptURL || "",
      scope: value?.scope || "",
    };
  });
  assert.ok(registration.scriptURL.endsWith("/sw.js"), "the compiled module service worker is active");
  assert.ok(registration.scope.endsWith("/"), "the app shell is scoped to the native origin");

  await page.locator("#new-session").click();
  await page.waitForFunction(
    () => document.querySelectorAll(".session-option[aria-current='page']").length === 1,
    null,
    { timeout: 15_000 },
  );
  await assertReadableSessionOption(
    page,
    ".session-option[aria-current='page']",
  );
  await page.locator("#prompt").fill("keep this draft while changing settings");
  await openSettings(page);
  await page.keyboard.press("Escape");
  await page.waitForFunction(() => document.getElementById("settings-page")?.hidden === true);
  assert.equal(
    await page.locator("#prompt").inputValue(),
    "keep this draft while changing settings",
    "closing Settings preserves the conversation draft",
  );
  assert.equal(
    await page.locator("#settings-open").evaluate((node) => document.activeElement === node),
    true,
    "closing Settings restores focus to the toolbar launcher",
  );
  await page.locator("#prompt").fill("Browser smoke 日本語");
  await page.locator("#send").click();
  await page.locator("#approval").waitFor({ state: "visible", timeout: 20_000 });
  const sendCommands = sentCommands.filter((command) => command.operation === "session_send");
  assert.equal(sendCommands.length, 1, "a dropped command response does not replay the command");
  assert.ok(
    receiptLookups.includes(sendCommands[0].command_id),
    "the client recovers the accepted command through its durable receipt",
  );
  assert.match(await page.locator("#approval-arguments").textContent(), /native-demo\.txt/);
  assert.equal(await page.locator("#send").isDisabled(), true);
  await page.locator("#approve").click();
  await page.waitForFunction(
    () => document.getElementById("status")?.textContent?.includes("完了"),
    null,
    { timeout: 30_000 },
  );
  const transcript = await page.locator("#text-transcript").textContent();
  assert.match(transcript, /Browser smoke 日本語/);
  assert.match(transcript, /durable native tool result/);
  assert.match(transcript, /Offline demo finished/);

  await page.waitForFunction(
    () => document.getElementById("transcript-canvas")?.width > 0,
    null,
    { timeout: 10_000 },
  );
  const canvas = await page.locator("#transcript-canvas").evaluate((element) => {
    const context = element.getContext("2d");
    const image = context.getImageData(0, 0, element.width, element.height).data;
    let painted = false;
    for (let index = 3; index < image.length; index += 4) {
      if (image[index] !== 0) {
        painted = true;
        break;
      }
    }
    return { width: element.width, height: element.height, painted };
  });
  assert.ok(canvas.painted, `the MoonBit renderer paints the transcript canvas: ${JSON.stringify(canvas)}`);

  await page.locator("#text-view").click();
  await page.waitForFunction(
    () => !document.getElementById("text-transcript")?.classList.contains("sr-only"),
  );
  await page.locator("#japanese-font").selectOption("noto");
  const font = await page.evaluate(() => ({
    selected: document.getElementById("japanese-font").value,
    family: getComputedStyle(document.documentElement).getPropertyValue("--dsh-font-family"),
    saved: localStorage.getItem("dsh.display.japanese-font.v1"),
  }));
  assert.equal(font.selected, "noto");
  assert.equal(font.saved, "noto");
  assert.match(font.family, /Noto Sans JP/);

  await page.locator("#prune-results").waitFor({ state: "visible" });
  await page.locator("#prune-results").click();
  await page.waitForFunction(
    () => document.getElementById("action-message")?.textContent?.includes("短縮が必要な大きさのツール結果はありません") ||
      document.getElementById("action-message")?.textContent?.includes("件のツール結果を今後のモデル要求向けに短縮"),
    null,
    { timeout: 20_000 },
  );
  assert.ok(
    sentCommands.some((command) => command.operation === "session_prune_tool_results"),
    "the browser sends the native tool-result pruning command",
  );
  await page.locator("#fork-session").click();
  await page.waitForFunction(
    () => document.querySelectorAll(".session-option").length === 2 &&
      document.querySelector("#action-message")?.textContent?.includes("から会話を分岐しました"),
    null,
    { timeout: 20_000 },
  );
  assert.ok(
    sentCommands.some((command) => command.operation === "session_fork"),
    "the browser sends the native fork command",
  );

  await page.locator("#context-toggle").click();
  assert.equal(await page.locator("#context-toggle").getAttribute("aria-expanded"), "true");
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("#context-toggle").getAttribute("aria-expanded"), "false");
  await page.locator("#sidebar-toggle").click();
  assert.equal(await page.locator(".yk-shell").getAttribute("data-sidebar-collapsed"), "true");
  await page.locator("#sidebar-toggle").click();

  await page.setViewportSize({ width: 390, height: 844 });
  const navigation = page.locator("#yk-mobile-navigation");
  await page.waitForFunction(
    () => document.getElementById("yk-mobile-navigation")?.getAttribute("aria-hidden") === "true",
  );
  assert.equal(await navigation.getAttribute("aria-hidden"), "true");
  assert.notEqual(await navigation.getAttribute("inert"), null);
  const contextPanel = page.locator("#yk-context-panel");
  assert.equal(await contextPanel.getAttribute("aria-hidden"), "true");
  assert.notEqual(await contextPanel.getAttribute("inert"), null);
  await page.locator("#navigation-toggle").focus();
  for (let index = 0; index < 24; index += 1) {
    await page.keyboard.press("Tab");
    assert.equal(
      await page.evaluate(() =>
        Boolean(document.activeElement?.closest("#yk-mobile-navigation")),
      ),
      false,
      "Tab never enters the closed, inert mobile navigation",
    );
  }
  await page.locator("#navigation-toggle").click();
  assert.equal(await navigation.getAttribute("aria-modal"), "true");
  assert.equal(await navigation.getAttribute("aria-hidden"), "false");
  assert.equal(await navigation.getAttribute("inert"), null);
  assert.equal(await page.locator("#navigation-toggle").getAttribute("aria-expanded"), "true");
  const focusable = navigation.locator(
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
  );
  const focusableCount = await focusable.count();
  assert.ok(focusableCount >= 2, "the mobile navigation has focusable controls");
  await focusable.first().focus();
  await page.keyboard.press("Shift+Tab");
  assert.equal(await focusable.last().evaluate((element) => element === document.activeElement), true,
    "Shift+Tab wraps from the first mobile navigation control to the last");
  await page.keyboard.press("Tab");
  assert.equal(await focusable.first().evaluate((element) => element === document.activeElement), true,
    "Tab wraps from the last mobile navigation control to the first");
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("#navigation-toggle").getAttribute("aria-expanded"), "false");
  assert.equal(await page.evaluate(() => document.activeElement?.id), "navigation-toggle");
  assert.equal(await navigation.getAttribute("aria-hidden"), "true");
  assert.notEqual(await navigation.getAttribute("inert"), null);
  for (let index = 0; index < 24; index += 1) {
    await page.keyboard.press("Tab");
    assert.equal(
      await page.evaluate(() =>
        Boolean(document.activeElement?.closest("#yk-mobile-navigation")),
      ),
      false,
      "Tab never enters the closed mobile navigation after Escape",
    );
  }
  await page.setViewportSize({ width: 1280, height: 844 });
  await page.waitForFunction(
    () => document.getElementById("yk-mobile-navigation")?.getAttribute("aria-hidden") === "false",
  );
  assert.equal(await navigation.getAttribute("inert"), null);
  await page.locator("#new-session").focus();
  assert.equal(
    await page.evaluate(() => document.activeElement?.id),
    "new-session",
    "the desktop sidebar is visible and keyboard-focusable after resizing",
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(
    () => document.getElementById("yk-mobile-navigation")?.getAttribute("aria-hidden") === "true",
  );

  await page.locator("#prompt").fill("未送信の下書き");
  await page.waitForTimeout(300);
  await page.reload({ waitUntil: "domcontentloaded" });
  await waitForConnectedWorkspace(page);
  await page.waitForFunction(
    () => document.getElementById("prompt")?.value === "未送信の下書き",
    null,
    { timeout: 15_000 },
  );
  assert.equal(
    await page.locator("#japanese-font").inputValue(),
    "noto",
    "the Japanese font preference survives reload",
  );

  await context.setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.locator("#transcript-canvas").waitFor({ state: "attached", timeout: 20_000 });
  assert.equal(await page.locator("#prompt").count(), 1, "the cached app shell mounts offline after reload");
  assert.equal(
    await page.evaluate(async () => {
      try {
        await fetch("/api/v1/snapshot", { cache: "no-store" });
        return false;
      } catch {
        return true;
      }
    }),
    true,
    "the native API is unreachable while the cached shell still mounts",
  );
  await page.locator("#connection-error").waitFor({ state: "visible", timeout: 20_000 });
  await page.evaluate(() => {
    window.__dshOnlineEventCount = 0;
    window.addEventListener("online", () => { window.__dshOnlineEventCount += 1; });
  });
  const recoveredSnapshot = page.waitForResponse((response) => {
    const url = new URL(response.url());
    return url.pathname === "/api/v1/snapshot" && response.status() === 200;
  }, { timeout: 20_000 });
  await context.setOffline(false);
  // Allow a real Chromium online event to reach the page before using the
  // fallback for builds where the emulation only changes network reachability.
  await page.waitForTimeout(100);
  const onlineState = await page.evaluate(() => ({
    online: navigator.onLine,
    eventCount: window.__dshOnlineEventCount,
  }));
  assert.equal(onlineState.online, true, "the browser network is restored before recovery");
  // Playwright's offline emulation does not dispatch Window.online on every
  // pinned Chromium build. Drive that standard browser event only when absent.
  if (onlineState.eventCount === 0) {
    await page.evaluate(() => window.dispatchEvent(new Event("online")));
  }
  const recoveredResponse = await recoveredSnapshot;
  assert.equal(recoveredResponse.ok(), true, "the online handler receives a fresh native snapshot");
  await waitForConnectedWorkspace(page);
  await page.waitForFunction(
    () => document.getElementById("connection-error")?.hidden === true,
    null,
    { timeout: 20_000 },
  );

  const imported = await postNativeCommand(page, "session_import", null, {
    jsonl: importedHistoryJsonl,
  });
  assert.equal(imported.status, 202, "the native host accepts a v4 history import");
  assert.equal(imported.receipt.status, "accepted");
  await page.waitForFunction(async () => {
    const response = await fetch("/api/v1/snapshot", { cache: "no-store" });
    const snapshot = await response.json();
    return snapshot.projection.sessions.some((session) =>
      session.source_format === "deepseek-session-v4",
    );
  }, null, { timeout: 20_000 });
  const importedSession = await page.evaluate(async () => {
    const response = await fetch("/api/v1/snapshot", { cache: "no-store" });
    const snapshot = await response.json();
    return snapshot.projection.sessions.find((session) =>
      session.source_format === "deepseek-session-v4",
    );
  });
  assert.ok(importedSession?.id, "the imported session appears in the native projection");
  await page.locator("#navigation-toggle").click();
  await page.locator(`.session-option[data-session-id="${importedSession.id}"]`).click();
  await page.waitForFunction(
    (id) => document.querySelector(`.session-option[data-session-id="${CSS.escape(id)}"]`)?.getAttribute("aria-current") === "page" &&
      document.getElementById("prompt")?.disabled === true,
    importedSession.id,
    { timeout: 15_000 },
  );
  assert.match(await page.locator("#composer-hint").textContent(), /読み取り専用/);
  assert.match(await page.locator("#text-transcript").textContent(), /Imported history stays read only/);
  assert.equal(await page.locator("#send").isDisabled(), true);
  const transcriptScroll = page.locator("#transcript-scroll");
  if (await page.locator("#text-view").getAttribute("aria-pressed") === "true") {
    await page.locator("#text-view").click();
  }
  await page.waitForFunction(
    () => document.getElementById("transcript-scroll")?.hidden === false,
  );
  await page.waitForFunction(
    () => {
      const scroll = document.getElementById("transcript-scroll");
      const spacer = document.getElementById("scene-spacer");
      return scroll && spacer &&
        Number.parseFloat(spacer.style.height) > scroll.clientHeight &&
        scroll.scrollHeight > scroll.clientHeight;
    },
    null,
    { timeout: 20_000 },
  );
  const longHistory = await transcriptScroll.evaluate((scroll) => {
    const spacer = document.getElementById("scene-spacer");
    return {
      clientHeight: scroll.clientHeight,
      scrollHeight: scroll.scrollHeight,
      scrollTop: scroll.scrollTop,
      spacerHeight: Number.parseFloat(spacer.style.height),
    };
  });
  assert.ok(
    longHistory.spacerHeight > longHistory.clientHeight,
    "the measured canvas extent creates a spacer taller than the viewport: " + JSON.stringify(longHistory),
  );
  assert.ok(
    longHistory.scrollHeight > longHistory.clientHeight,
    "long imported history creates a nonzero scroll range: " + JSON.stringify(longHistory),
  );
  await transcriptScroll.evaluate((scroll) => {
    scroll.scrollTop = Math.floor((scroll.scrollHeight - scroll.clientHeight) / 2);
    scroll.dispatchEvent(new Event("scroll"));
  });
  await page.waitForFunction(
    () => document.getElementById("jump-latest")?.hidden === false &&
      document.getElementById("jump-latest")?.disabled === false,
    null,
    { timeout: 10_000 },
  );
  const olderPosition = await transcriptScroll.evaluate((scroll) => ({
    scrollTop: scroll.scrollTop,
    maxScroll: scroll.scrollHeight - scroll.clientHeight,
  }));
  assert.ok(
    olderPosition.scrollTop > 0 && olderPosition.scrollTop < olderPosition.maxScroll,
    "the canvas can scroll to older transcript content: " + JSON.stringify(olderPosition),
  );
  await page.locator("#jump-latest").click();
  await page.waitForFunction(() => {
    const scroll = document.getElementById("transcript-scroll");
    return scroll && scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 2;
  }, null, { timeout: 10_000 });

  const violations = await page.evaluate(() => window.__dshCspViolations);
  assert.deepEqual(violations, [], `no CSP violations occur: ${JSON.stringify(violations)}`);
}

async function testCompiledAuthModelFlow(browserInstance) {
  const context = await browserInstance.newContext({
    locale: "ja-JP",
    viewport: { width: 1280, height: 820 },
  });
  contexts.push(context);
  const page = await context.newPage();
  observePage(page);
  let connected = false;
  let modelsLoaded = false;
  let selectedModel = "";
  let modelRefreshes = 0;
  let signInRequests = 0;
  let invalidAuthorizationUrl = false;
  let failFirstModelRefresh = true;
  let rejectNextModel = false;
  let holdNextModelRejection = false;
  let releaseRejectedModel;
  let signalRejectedModel;
  const rejectedModelStarted = new Promise((resolve) => { signalRejectedModel = resolve; });
  const rejectedModelGate = new Promise((resolve) => { releaseRejectedModel = resolve; });
  await page.addInitScript(() => {
    window.__dshBlockPopup = false;
    window.__dshAuthTabs = [];
    window.open = () => {
      if (window.__dshBlockPopup) return null;
      const tab = {
        href: "about:blank",
        closed: false,
        opener: window,
        location: { replace(value) { tab.href = value; } },
        close() { tab.closed = true; },
      };
      window.__dshAuthTabs.push(tab);
      return tab;
    };
  });
  await page.route("**/api/v1/snapshot", async (route) => {
    const response = await route.fetch();
    const snapshot = await response.json();
    snapshot.auth = connected
      ? {
        state: "connected",
        account: { profile_id: "profile-fixture", email: "fixture@example.test" },
        plan_usage: "disabled",
        scopes: [],
        models: modelsLoaded
          ? [
            { slug: "fixture-model", display_name: "Fixture model" },
            { slug: "alternate-model", display_name: "Alternate model" },
          ]
          : [],
        selected_model: selectedModel || null,
      }
      : {
        state: "signed_out",
        account: null,
        plan_usage: "disabled",
        scopes: [],
        models: [],
        selected_model: null,
      };
    await route.fulfill({ response, body: JSON.stringify(snapshot) });
  });
  await page.route("**/api/call", async (route) => {
    const request = JSON.parse(route.request().postData() || "{}");
    const operation = request.operation;
    const input = request.input || {};
    if (operation === "auth_sign_in_browser") {
      signInRequests += 1;
      connected = true;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          ok: true,
          result: {
            started: true,
            authorization_url: invalidAuthorizationUrl
              ? "https://auth.openai.com.evil.test/api/accounts/authorize"
              : "https://auth.openai.com/api/accounts/authorize?client_id=fixture",
          },
        }),
      });
      return;
    }
    if (operation === "auth_models") {
      modelRefreshes += 1;
      if (failFirstModelRefresh) {
        failFirstModelRefresh = false;
        await route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({ ok: false, error: "fixture model catalog unavailable" }),
        });
        return;
      }
      modelsLoaded = true;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true, result: {} }),
      });
      return;
    }
    if (operation === "auth_select_model") {
      if (rejectNextModel) {
        rejectNextModel = false;
        if (holdNextModelRejection) {
          holdNextModelRejection = false;
          signalRejectedModel();
          await rejectedModelGate;
        }
        await route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({ ok: false, error: "fixture selection rejected" }),
        });
        return;
      }
      selectedModel = input.model;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true, result: { selected_model: selectedModel } }),
      });
      return;
    }
    await route.continue();
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await waitForConnectedWorkspace(page);
  await openSettings(page);
  await page.evaluate(() => { window.__dshBlockPopup = true; });
  await page.locator("#auth-sign-in").click();
  await page.waitForFunction(
    () => {
      const error = document.getElementById("settings-error");
      return error?.hidden === false && error.textContent?.includes("ポップアップ");
    },
  );
  assert.equal(await page.locator("#settings-error").isVisible(), true, "blocked-popup errors are visible in Settings");
  assert.equal(signInRequests, 0, "a blocked popup does not ask the host to start sign-in");

  await page.evaluate(() => { window.__dshBlockPopup = false; });
  invalidAuthorizationUrl = true;
  await page.locator("#auth-sign-in").click();
  await page.waitForFunction(
    () => {
      const error = document.getElementById("settings-error");
      return error?.hidden === false && error.textContent?.includes("無効な ChatGPT 認証 URL");
    },
  );
  assert.equal(await page.locator("#settings-error").isVisible(), true, "rejected authorization URLs are visible in Settings");
  assert.equal(signInRequests, 1);
  assert.deepEqual(
    await page.evaluate(() => window.__dshAuthTabs.map((tab) => tab.closed)),
    [true],
    "an untrusted authorization URL closes the reserved tab",
  );

  invalidAuthorizationUrl = false;
  await page.locator("#auth-sign-in").click();
  await page.waitForFunction(
    () => document.getElementById("auth-guidance")?.textContent?.includes("モデルを読み込めませんでした"),
    null,
    { timeout: 20_000 },
  );
  assert.equal(signInRequests, 2);
  assert.equal(modelRefreshes, 1, "the connected account automatically refreshes its model catalog");
  assert.equal(await page.locator("#auth-models-retry").isHidden(), false);
  await page.locator("#auth-models-retry").click();
  await page.waitForFunction(
    () => document.querySelector("#model-picker option[value='fixture-model']"),
    null,
    { timeout: 20_000 },
  );
  assert.equal(modelRefreshes, 2, "failed discovery waits for an explicit retry");
  assert.match(await page.locator("#auth-status").textContent(), /ChatGPT/);
  assert.equal(await page.locator("#auth-sign-in").isHidden(), true);
  assert.equal(await page.locator("#model-picker").isDisabled(), false);
  const tabs = await page.evaluate(() => window.__dshAuthTabs.map((tab) => ({
    href: tab.href,
    opener: tab.opener,
    closed: tab.closed,
  })));
  assert.equal(tabs.length, 2);
  assert.equal(tabs[0].closed, true);
  assert.equal(tabs[1].href, "https://auth.openai.com/api/accounts/authorize?client_id=fixture");
  assert.equal(tabs[1].opener, null, "the authorization window has no opener");

  await page.locator("#model-picker").selectOption("fixture-model");
  await page.waitForFunction(
    () => document.getElementById("model-picker")?.value === "fixture-model",
  );
  rejectNextModel = true;
  await page.locator("#model-picker").selectOption("alternate-model");
  await page.waitForFunction(
    () => {
      const error = document.getElementById("settings-error");
      return error?.hidden === false && error.textContent?.includes("fixture selection rejected");
    },
  );
  assert.equal(await page.locator("#settings-error").isVisible(), true, "rejected model selections are visible in Settings");
  assert.equal(
    await page.locator("#model-picker").inputValue(),
    "fixture-model",
    "a failed remote model selection restores the previously active model",
  );

  holdNextModelRejection = true;
  rejectNextModel = true;
  await page.locator("#model-picker").selectOption("alternate-model");
  await rejectedModelStarted;
  await page.locator("#settings-close").click();
  await page.waitForFunction(() => document.getElementById("settings-page")?.hidden === true);
  releaseRejectedModel();
  await page.locator("#run-error").waitFor({ state: "visible" });
  await page.waitForFunction(
    () => {
      const error = document.getElementById("run-error");
      return error?.hidden === false && error.textContent?.includes("fixture selection rejected");
    },
  );
  assert.equal(await page.locator("#run-error").isVisible(), true, "a model-selection error remains visible after Settings closes");
}

async function testCorruptSnapshotRecovery(browserInstance) {
  const context = await browserInstance.newContext({ locale: "ja-JP" });
  contexts.push(context);
  const page = await context.newPage();
  observePage(page);
  let snapshotRequests = 0;
  await page.route("**/api/v1/snapshot", async (route) => {
    snapshotRequests += 1;
    if (snapshotRequests <= 2) {
      await route.fulfill({ status: 200, contentType: "application/json", body: "{bad json" });
      return;
    }
    await route.continue();
  });
  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await page.locator("#connection-error").waitFor({ state: "visible", timeout: 15_000 });
  await page.locator("#reconnect").click();
  await waitForConnectedWorkspace(page);
  await page.waitForFunction(() => document.getElementById("connection-error")?.hidden === true);
  assert.ok(snapshotRequests >= 3, "the explicit recovery requests a fresh valid snapshot after malformed responses");
  assert.equal(await page.locator("#provider-model").textContent().then((text) => text.includes("デモ")), true);
}

async function testStaleAuthCatalogCannotOverwriteNewAccount(browserInstance) {
  const context = await browserInstance.newContext({
    locale: "ja-JP",
    viewport: { width: 1280, height: 820 },
  });
  contexts.push(context);
  const page = await context.newPage();
  observePage(page);
  let connectedProfile = "";
  let profileBModelsLoaded = false;
  let authModelRequests = 0;
  let releaseProfileA;
  let resolveProfileAStarted;
  const profileAResultGate = new Promise((resolve) => { releaseProfileA = resolve; });
  const profileAStarted = new Promise((resolve) => { resolveProfileAStarted = resolve; });
  await page.addInitScript(() => {
    window.open = () => ({
      href: "about:blank",
      closed: false,
      opener: null,
      location: { replace(value) { this.href = value; } },
      close() { this.closed = true; },
    });
  });
  await page.route("**/api/v1/snapshot", async (route) => {
    const response = await route.fetch();
    const snapshot = await response.json();
    snapshot.auth = connectedProfile
      ? {
        state: "connected",
        account: { profile_id: connectedProfile, email: `${connectedProfile}@example.test` },
        plan_usage: "disabled",
        scopes: [],
        models: profileBModelsLoaded && connectedProfile === "profile-b"
          ? [{ slug: "model-b", display_name: "Model B" }]
          : [],
        selected_model: null,
      }
      : { state: "signed_out", account: null, plan_usage: "disabled", scopes: [], models: [], selected_model: null };
    await route.fulfill({ response, body: JSON.stringify(snapshot) });
  });
  await page.route("**/api/call", async (route) => {
    const request = JSON.parse(route.request().postData() || "{}");
    if (request.operation === "auth_sign_in_browser") {
      connectedProfile = "profile-a";
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          ok: true,
          result: { started: true, authorization_url: "https://auth.openai.com/api/accounts/authorize?client_id=race" },
        }),
      });
      return;
    }
    if (request.operation === "auth_models") {
      authModelRequests += 1;
      if (connectedProfile === "profile-a") {
        resolveProfileAStarted();
        await profileAResultGate;
        await route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({ ok: false, error: "stale profile A catalog failure" }),
        });
        return;
      }
      profileBModelsLoaded = true;
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ ok: true, result: {} }),
      });
      return;
    }
    await route.continue();
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await waitForConnectedWorkspace(page);
  await openSettings(page);
  await page.locator("#auth-sign-in").click();
  await profileAStarted;
  connectedProfile = "profile-b";
  await page.evaluate(() => window.dispatchEvent(new Event("pageshow")));
  await page.waitForFunction(
    () => Boolean(document.querySelector("#model-picker option[value='model-b']")),
    null,
    { timeout: 20_000 },
  );
  assert.ok(authModelRequests >= 2, "profile B starts its own model catalog request while A is pending");
  releaseProfileA();
  await page.waitForTimeout(300);
  assert.equal(await page.locator("#model-picker option[value='model-b']").count(), 1);
  assert.equal(await page.locator("#model-picker").isDisabled(), false);
  assert.equal(await page.locator("#auth-models-retry").isHidden(), true);
  assert.doesNotMatch(await page.locator("#auth-guidance").textContent(), /モデルを読み込めませんでした/);
}

try {
  browser = await chromium.launch({
    headless: true,
    executablePath,
    args: ["--no-sandbox"],
  });
  await testNativeDemo(browser);
  await testCorruptSnapshotRecovery(browser);
  await testCompiledAuthModelFlow(browser);
  await testStaleAuthCatalogCannotOverwriteNewAccount(browser);
  assert.deepEqual(failures, [], `the browser reports no runtime or console errors: ${JSON.stringify(failures)}`);
  process.stdout.write("Native-host Chromium smoke passed: CSP, MoonBit UI/transport, Canvas, command receipts, fork/prune/import, offline shell, accessibility, auth races, and compiled service-worker cache.\n");
} catch (error) {
  await mkdir(screenshotDirectory, { recursive: true });
  await Promise.all(
    pages.map((page, index) =>
      page.screenshot({ path: path.join(screenshotDirectory, `failure-${index + 1}.png`), fullPage: true })
        .catch(() => undefined),
    ),
  );
  throw error;
} finally {
  for (const context of contexts) await context.close().catch(() => undefined);
  await browser?.close().catch(() => undefined);
}
