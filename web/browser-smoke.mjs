// Optional real-Chromium acceptance: build first, then `node web/browser-smoke.mjs`.
// All provider responses and tool writes are confined to this test's temp directory.
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { createHost } from "../host/runtime.mjs";
import { startWebServer } from "../host/server.mjs";

const { chromium } = createRequire(import.meta.url)("playwright");
const repo = fileURLToPath(new URL("../", import.meta.url));
const screenshots = path.resolve(process.env.DSH_SCREENSHOT_DIR || path.join(repo, "_build/browser-smoke"));
const workspace = await fs.mkdtemp(path.join(os.tmpdir(), "dsh-browser-"));
await fs.mkdir(screenshots, { recursive: true });
let callNumber = 0;
let providerCalls = 0;
let browser;
let host;
let web;
let page;
const failures = [];
let releaseLiveStream;
const encoder = new TextEncoder();

function completion(content, toolCalls) {
  return new Response(JSON.stringify({
    choices: [{ index: 0, finish_reason: toolCalls ? "tool_calls" : "stop", message: {
      role: "assistant", content: toolCalls ? "" : content, ...(toolCalls ? { tool_calls: toolCalls } : {}),
    } }],
  }), { headers: { "content-type": "application/json" } });
}

async function provider(_url, options) {
  providerCalls += 1;
  const request = JSON.parse(options.body);
  const messages = request.messages;
  const prompt = [...messages].reverse().find((message) => message.role === "user")?.content || "";
  const last = messages.at(-1);
  if (prompt.includes("slow request")) {
    return new Promise((_resolve, reject) => {
      if (options.signal.aborted) reject(options.signal.reason);
      else options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
    });
  }
  if (prompt.includes("live stream smoke")) {
    const initial = [
      `data: ${JSON.stringify({ choices: [{ index: 0, delta: { role: "assistant", reasoning_content: "Reasoning arrives first." }, finish_reason: null }] })}\n\n`,
      `data: ${JSON.stringify({ choices: [{ index: 0, delta: { content: "Live answer 日本語 🌱" }, finish_reason: null }] })}\n\n`,
    ].join("");
    const terminal = [
      `data: ${JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`,
      "data: [DONE]\n\n",
    ].join("");
    return new Response(new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(initial));
        let released = false;
        releaseLiveStream = () => {
          if (released) return;
          released = true;
          controller.enqueue(encoder.encode(terminal));
          controller.close();
        };
      },
    }), { headers: { "content-type": "text/event-stream" } });
  }
  if (prompt.includes("provider failure")) return new Response("Fixture provider unavailable", { status: 503 });
  if ((prompt.includes("approved.txt") || prompt.includes("denied.txt")) && last.role !== "tool") {
    const target = prompt.includes("approved.txt") ? "approved.txt" : "denied.txt";
    return completion("", [{ id: `browser-call-${++callNumber}`, type: "function", function: {
      name: "write", arguments: JSON.stringify({ file_path: target, content: "Written only after explicit browser approval.\n" }),
    } }]);
  }
  if (last.role === "tool") return completion(`The tool request settled.\n${last.content}`);
  if (prompt.includes("long transcript")) return completion(Array.from({ length: 70 }, (_, i) => `Line ${i + 1}: MoonBit owns the transcript layout. 日本語も表示できます。`).join("\n"));
  return completion(`Received: ${prompt}\nThe session completed through the MoonBit engine. <script>literal text</script>`);
}

async function waitStatus(value) {
  await page.waitForFunction((expected) => document.getElementById("status").textContent === expected, value, { timeout: 15_000 });
}

async function send(prompt) {
  await page.locator("#prompt").fill(prompt);
  await page.locator("#send").click();
}

function currentId() {
  return page.locator(".session-option[aria-current='page']").getAttribute("data-id");
}

try {
  host = await createHost({ workspace, mode: "openai", baseURL: "http://127.0.0.1:1", model: "browser-fixture", fetchImpl: provider });
  const delayedHost = { ...host, async call(operation, input) {
    const result = await host.call(operation, input);
    if (operation === "session_create" || (operation === "session_send" && input.prompt.includes("draft race"))) {
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
    return result;
  } };
  web = await startWebServer({ host: delayedHost, port: 0 });
  browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox"],
    ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}),
  });
  page = await browser.newPage({ viewport: { width: 1280, height: 820 }, deviceScaleFactor: 1 });
  page.on("pageerror", (error) => failures.push(error.message));
  await page.goto(web.url, { waitUntil: "networkidle" });
  await send("Hello from the browser");
  await waitStatus("Completed");
  assert.match(await page.locator("#text-transcript").textContent(), /MoonBit engine/);
  assert.equal(await page.locator("#text-transcript script").count(), 0);
  const firstId = await currentId();

  const finalAssistantRowsBefore = await page.locator("#text-transcript h2").filter({ hasText: /^Assistant$/ }).count();
  await send("live stream smoke");
  await page.waitForFunction(() => {
    const transcript = document.getElementById("text-transcript");
    return transcript.textContent.includes("Assistant · writing")
      && transcript.textContent.includes("Live answer 日本語 🌱");
  }, undefined, { timeout: 15_000 });
  assert.match(await page.locator("#text-transcript").textContent(), /Reasoning · writing/);
  assert.equal(await page.locator("#status").textContent(), "Running");
  releaseLiveStream();
  releaseLiveStream = undefined;
  await waitStatus("Completed");
  assert.equal(await page.locator("#text-transcript h2").filter({ hasText: /^Assistant$/ }).count(), finalAssistantRowsBefore + 1);
  assert.doesNotMatch(await page.locator("#text-transcript").textContent(), /Assistant · writing/);

  // Successful responses must preserve edits made to the next draft in flight.
  await send("draft race");
  await page.locator("#prompt").fill("Keep this next draft");
  await page.waitForFunction(() => !document.getElementById("new-session").disabled);
  await waitStatus("Completed");
  assert.equal(await page.locator("#prompt").inputValue(), "Keep this next draft");
  await page.locator("#prompt").fill("");

  await page.locator("#new-session").click();
  await page.waitForFunction((old) => document.querySelector(".session-option[aria-current='page']")?.dataset.id !== old, firstId);
  await send("Please write approved.txt");
  await waitStatus("Needs approval");
  assert.match(await page.locator("#approval-arguments").textContent(), /approved\.txt/);
  await assert.rejects(fs.access(path.join(workspace, "approved.txt")));
  await page.screenshot({ path: path.join(screenshots, "desktop-approval.png"), fullPage: true });
  await page.locator("#approve").click();
  await waitStatus("Completed");
  assert.match(await fs.readFile(path.join(workspace, "approved.txt"), "utf8"), /explicit browser approval/);

  await send("Please write denied.txt");
  await waitStatus("Needs approval");
  await page.locator("#deny").click();
  await waitStatus("Completed");
  await assert.rejects(fs.access(path.join(workspace, "denied.txt")));

  await send("slow request");
  await waitStatus("Running");
  await page.locator("#cancel").click();
  await waitStatus("Cancelled");
  await send("provider failure");
  await waitStatus("Failed");
  assert.match(await page.locator("#run-error").textContent(), /503|Fixture provider/);

  await send("long transcript");
  await waitStatus("Completed");
  await page.waitForFunction(() => document.getElementById("transcript-scroll").scrollHeight > document.getElementById("transcript-scroll").clientHeight);
  await page.evaluate(() => { document.getElementById("transcript-scroll").scrollTop = 0; });
  await page.locator("#jump-latest").waitFor({ state: "visible" });
  await page.screenshot({ path: path.join(screenshots, "desktop-transcript.png"), fullPage: true });

  await page.locator("#text-view").click();
  await page.evaluate(() => { document.getElementById("text-transcript").scrollTop = 0; });
  await page.locator("#jump-latest").waitFor({ state: "visible" });
  const activeId = await currentId();
  await host.call("session_send", { session_id: activeId, prompt: "append while reading" });
  await host.waitForSession(activeId, { signal: AbortSignal.timeout(10_000) });
  await page.waitForFunction(() => document.getElementById("text-transcript").textContent.includes("append while reading"));
  assert.equal(await page.locator("#text-transcript").evaluate((element) => element.scrollTop), 0);
  await page.locator("#text-view").click();

  const importedSource = await fs.readFile(new URL("../tests/fixtures/upstream-tool-call-turn/session.v4.jsonl", import.meta.url), "utf8");
  const imported = await host.call("session_import", { jsonl: importedSource });
  assert.equal(imported.ok, true, imported.error);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForFunction(() => document.getElementById("status").textContent === "Read-only · Completed");
  assert.equal(await page.locator("#prompt").isDisabled(), true);
  assert.equal(await page.locator("#send").isDisabled(), true);
  assert.match(await page.locator("#composer-hint").textContent(), /read-only/);
  assert.match(await page.locator("#text-transcript").textContent(), /DONE/);
  const providerCallsBeforeRejectedContinuation = providerCalls;
  const deniedContinuation = await host.call("session_send", { session_id: imported.result.id, prompt: "do not run" });
  assert.equal(deniedContinuation.ok, false);
  assert.equal(providerCalls, providerCallsBeforeRejectedContinuation);

  await page.locator(`.session-option[data-id='${firstId}']`).click();
  await page.waitForFunction(() => document.getElementById("status").textContent === "Completed");

  // A later explicit session selection wins over an earlier create request.
  await page.locator("#new-session").click();
  await page.locator(`.session-option[data-id='${firstId}']`).click();
  await page.waitForFunction(() => !document.getElementById("new-session").disabled);
  assert.equal(await currentId(), firstId);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => document.getElementById("transcript-canvas").width < 500);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth), false);
  await page.screenshot({ path: path.join(screenshots, "mobile-transcript.png"), fullPage: true });

  // Exercise the existing reconnect control without restarting or losing state.
  await page.route("**/api/call", (route) => route.abort("failed"));
  await page.locator("#connection-error").waitFor({ state: "visible", timeout: 10_000 });
  await page.unroute("**/api/call");
  await page.locator("#reconnect").click();
  await page.locator("#connection-error").waitFor({ state: "hidden" });
  assert.equal(await currentId(), firstId);
  assert.deepEqual(failures, []);
  console.log(JSON.stringify({ status: "PASS", assertions: "startup, create/select, draft preservation, submit, live provisional text/reasoning and final replacement, approval allow/deny, real file write, cancellation, provider error, literal output, scrolling, text-view follow, Session v4 read-only import/no-effect display, same-session create/select race, mobile layout, reconnect", screenshots }));
} catch (error) {
  if (page && !page.isClosed()) await page.screenshot({ path: path.join(screenshots, "failure.png"), fullPage: true }).catch(() => {});
  throw error;
} finally {
  if (browser) await browser.close();
  if (web) await web.close();
  if (host) await host.close();
  await fs.rm(workspace, { recursive: true, force: true });
}
