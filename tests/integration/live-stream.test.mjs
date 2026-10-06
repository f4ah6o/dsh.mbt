import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';

const encoder = new TextEncoder();

async function freshFacade() {
  return import(`${pathToFileURL(defaultModulePath).href}?test=${randomUUID()}`);
}

async function temporary(t) {
  const workspace = await mkdtemp(path.join(os.tmpdir(), 'dsh-live-stream-'));
  const dataDir = path.join(workspace, '.dsh.mbt');
  const hosts = [];
  const cleanups = [];
  t.after(async () => {
    for (const cleanup of cleanups) {
      try { cleanup(); } catch { /* Preserve the test result. */ }
    }
    await Promise.allSettled(hosts.map((host) => host.close()));
    await rm(workspace, { recursive: true, force: true });
  });
  return {
    workspace,
    dataDir,
    addCleanup(cleanup) { cleanups.push(cleanup); },
    async host(fetchImpl, facadeOverride) {
      const host = await createHost({
        facade: facadeOverride ?? await freshFacade(),
        workspace,
        dataDir,
        mode: 'openai',
        model: 'fixture-model',
        baseURL: 'http://127.0.0.1:1/v1',
        fetchImpl,
      });
      hosts.push(host);
      return host;
    },
  };
}

function openAIChunk(delta, finishReason) {
  const choice = { index: 0, delta };
  if (finishReason !== undefined) choice.finish_reason = finishReason;
  return `data: ${JSON.stringify({ choices: [choice] })}\n\n`;
}

function openAIStream(content, reasoning = '') {
  return [
    openAIChunk({ role: 'assistant', ...(reasoning ? { reasoning_content: reasoning } : {}) }),
    openAIChunk({ content }),
    openAIChunk({}, 'stop'),
    'data: [DONE]\n\n',
  ].join('');
}

function jsonResponse(content) {
  return new Response(JSON.stringify({
    choices: [{ message: { role: 'assistant', content }, finish_reason: 'stop' }],
  }), { headers: { 'content-type': 'application/json' } });
}

function streamResponse(raw, chunkBytes = Number.POSITIVE_INFINITY) {
  const bytes = encoder.encode(raw);
  const body = new ReadableStream({
    start(controller) {
      for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
        controller.enqueue(bytes.subarray(offset, Math.min(offset + chunkBytes, bytes.length)));
      }
      controller.close();
    },
  });
  return new Response(body, { headers: { 'content-type': 'text/event-stream' } });
}

function streamResponseSplitInside(raw, scalar, splitWithinScalar) {
  const bytes = encoder.encode(raw);
  const needle = encoder.encode(scalar);
  const offset = Buffer.from(bytes).indexOf(Buffer.from(needle));
  assert.ok(offset >= 0, `expected ${scalar} in the encoded response`);
  const split = offset + splitWithinScalar;
  assert.ok(split > offset && split < offset + needle.length);
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(bytes.subarray(0, split));
      controller.enqueue(bytes.subarray(split));
      controller.close();
    },
  });
  return new Response(body, { headers: { 'content-type': 'text/event-stream' } });
}

async function send(host, prompt) {
  const created = await host.call('session_create', {});
  assert.equal(created.ok, true, created.error);
  const sent = await host.call('session_send', { session_id: created.result.id, prompt });
  assert.equal(sent.ok, true, sent.error);
  return created.result.id;
}

async function waitUntil(read, predicate, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await read();
    if (predicate(value)) return value;
    if (Date.now() >= deadline) throw new Error('Timed out waiting for the live stream state');
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

test('text and reasoning are durable before SSE EOF, then the final message replaces the provisional projection', async (t) => {
  const context = await temporary(t);
  const initial = [
    openAIChunk({ role: 'assistant', reasoning_content: 'thinking live' }),
    openAIChunk({ content: 'answer live' }),
  ].join('');
  const terminal = [openAIChunk({}, 'stop'), 'data: [DONE]\n\n'].join('');
  let controller;
  let releaseTail;
  let tailSent = false;
  const host = await context.host(async () => new Response(new ReadableStream({
    start(value) {
      controller = value;
      value.enqueue(encoder.encode(initial));
      releaseTail = () => {
        if (tailSent) return;
        tailSent = true;
        value.enqueue(encoder.encode(terminal));
        value.close();
      };
    },
  }), { headers: { 'content-type': 'text/event-stream' } }));
  context.addCleanup(() => releaseTail?.());

  const id = await send(host, 'Show the answer as it arrives.');
  const writing = await waitUntil(() => host.session(id), (session) =>
    session.events.some((event) => event.type === 'assistant/stream_delta'));
  assert.equal(tailSent, false, 'projection must be visible while the provider body is still open');
  assert.equal(writing.status, 'running');
  const provisional = writing.messages.find((message) => message.role === 'assistant');
  assert.equal(provisional.provisional, true);
  assert.equal(provisional.stream_status, 'writing');
  assert.equal(provisional.content, 'answer live');
  assert.equal(provisional.reasoning, 'thinking live');

  const disk = JSON.parse(await readFile(path.join(context.dataDir, 'sessions.json'), 'utf8'));
  assert.ok(disk.sessions[0].events.some((event) => event.type === 'assistant/stream_delta'), 'the live projection is checkpointed before EOF');

  releaseTail();
  const completed = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(completed.status, 'completed');
  const assistant = completed.messages.filter((message) => message.role === 'assistant');
  assert.equal(assistant.length, 1);
  assert.equal(assistant[0].content, 'answer live');
  assert.equal(assistant[0].reasoning, 'thinking live');
  assert.equal(assistant[0].provisional, undefined);
  const deltas = completed.events.filter((event) => event.type === 'assistant/stream_delta');
  assert.equal(deltas.length, 1);
  assert.equal(deltas[0].data.content, assistant[0].content);
  assert.equal(deltas[0].data.reasoning, assistant[0].reasoning);
});

test('split UTF-8 and a delta larger than 4096 units persist in scalar-safe batches without duplicating final text', async (t) => {
  const context = await temporary(t);
  const content = `${'a'.repeat(4095)}🪴${'b'.repeat(5000)}`;
  const raw = openAIStream(content);
  const host = await context.host(async () => streamResponseSplitInside(raw, '🪴', 2));
  const id = await send(host, 'Return a large streamed answer.');
  const completed = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });

  assert.equal(completed.status, 'completed');
  const assistant = completed.messages.filter((message) => message.role === 'assistant');
  assert.equal(assistant.length, 1);
  assert.equal(assistant[0].content, content);
  const deltas = completed.events.filter((event) => event.type === 'assistant/stream_delta');
  assert.ok(deltas.length >= 3, 'large provider deltas are persisted as bounded batches');
  const batches = deltas.map((event) => event.data.content);
  assert.ok(batches.every((batch) => batch.length <= 4096));
  assert.ok(batches.every((batch) => !/[\uD800-\uDBFF]$/.test(batch)), 'a batch never ends with half of a surrogate pair');
  assert.ok(batches.every((batch) => !/^[\uDC00-\uDFFF]/.test(batch)), 'a batch never starts with half of a surrogate pair');
  assert.equal(batches.join(''), content);
});

test('truncated streams keep durable partial text across reopen and never execute an incomplete tool call', async (t) => {
  const context = await temporary(t);
  let requests = 0;
  const truncated = [
    openAIChunk({ role: 'assistant' }),
    openAIChunk({ content: 'partial before broken tool' }),
    openAIChunk({ tool_calls: [{
      index: 0,
      id: 'incomplete-write',
      type: 'function',
      function: { name: 'write', arguments: '{"file_path":"must-not-exist.txt","content":"not complete' },
    }] }),
  ].join('');
  const host = await context.host(async () => {
    requests++;
    return streamResponse(truncated);
  });
  const id = await send(host, 'Write only after a complete tool call.');
  const failed = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });

  assert.equal(failed.status, 'failed');
  const partial = failed.messages.find((message) => message.role === 'assistant');
  assert.equal(partial.content, 'partial before broken tool');
  assert.equal(partial.provisional, true);
  assert.equal(partial.stream_status, 'partial');
  assert.ok(failed.events.some((event) => event.type === 'assistant/attempt'));
  assert.equal(failed.events.some((event) => event.type === 'tool/call'), false);
  await assert.rejects(readFile(path.join(context.workspace, 'must-not-exist.txt')), { code: 'ENOENT' });

  await host.close();
  const reopenedHost = await context.host(async () => {
    requests++;
    throw new Error('reopen must not contact the provider');
  });
  const reopened = await reopenedHost.session(id);
  assert.equal(reopened.status, 'failed');
  assert.deepEqual(reopened.messages, failed.messages);
  assert.deepEqual(reopened.events, failed.events);
  assert.equal(reopenedHost.activeCount, 0);
  assert.equal(requests, 1);
});

test('cancel fences a late stream result and the next provider request omits the partial projection', async (t) => {
  const context = await temporary(t);
  const requests = [];
  const firstRead = encoder.encode(openAIChunk({ role: 'assistant' }) + openAIChunk({ content: 'CANCEL_ONLY_PARTIAL' }));
  const lateRead = deferred();
  const cancelStarted = deferred();
  const cancelCleanup = deferred();
  let reads = 0;
  const reader = {
    read() {
      reads++;
      if (reads === 1) return Promise.resolve({ done: false, value: firstRead });
      return lateRead.promise;
    },
    cancel() {
      cancelStarted.resolve();
      return cancelCleanup.promise;
    },
    releaseLock() {},
  };
  const lateResponse = {
    ok: true,
    headers: new Headers({ 'content-type': 'text/event-stream' }),
    body: { getReader: () => reader },
  };
  const host = await context.host(async (_url, init) => {
    requests.push(JSON.parse(init.body));
    if (requests.length === 1) return lateResponse;
    return jsonResponse('fresh answer');
  });
  context.addCleanup(() => {
    lateRead.resolve({ done: true });
    cancelCleanup.resolve();
  });

  const id = await send(host, 'Start a turn that will be cancelled.');
  const writing = await waitUntil(() => host.session(id), (session) =>
    session.events.some((event) => event.type === 'assistant/stream_delta'));
  assert.equal(writing.messages.find((message) => message.role === 'assistant').content, 'CANCEL_ONLY_PARTIAL');
  await waitUntil(async () => reads, (count) => count >= 2);

  const cancelled = await host.call('session_cancel', { session_id: id });
  assert.equal(cancelled.ok, true, cancelled.error);
  assert.equal(cancelled.result.status, 'cancelled');
  await cancelStarted.promise;
  lateRead.resolve({
    done: false,
    value: encoder.encode(openAIStream('MUST_NOT_APPEAR_AFTER_CANCELLATION')),
  });
  cancelCleanup.resolve();
  await waitUntil(() => host.activeCount, (activeCount) => activeCount === 0);

  const afterLateResponse = await host.session(id);
  assert.equal(afterLateResponse.status, 'cancelled');
  assert.equal(JSON.stringify(afterLateResponse).includes('MUST_NOT_APPEAR_AFTER_CANCELLATION'), false);

  const sent = await host.call('session_send', { session_id: id, prompt: 'Start a clean turn.' });
  assert.equal(sent.ok, true, sent.error);
  const completed = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(completed.status, 'completed');
  assert.equal(requests.length, 2);
  assert.equal(JSON.stringify(requests[1].messages).includes('CANCEL_ONLY_PARTIAL'), false);
  assert.equal(completed.messages.some((message) => message.content === 'CANCEL_ONLY_PARTIAL' && message.stream_status === 'partial'), true);
  assert.equal(completed.messages.at(-1).content, 'fresh answer');
});

test('a rejected cancel retains a delta received during its preflight checkpoint', async (t) => {
  const context = await temporary(t);
  const checkpointSeen = deferred();
  const duringRead = deferred();
  const terminalRead = deferred();
  const deltaFedDuringCheckpoint = deferred();
  const cancelDispatch = deferred();
  const readsStarted = [deferred(), deferred(), deferred()];
  const first = encoder.encode(openAIChunk({ role: 'assistant' }) + openAIChunk({ content: 'before checkpoint' }));
  const during = encoder.encode(openAIChunk({ content: ' during checkpoint' }));
  const terminal = encoder.encode([openAIChunk({}, 'stop'), 'data: [DONE]\n\n'].join(''));
  const reader = {
    read() {
      const index = reader.readCount++;
      readsStarted[index]?.resolve();
      if (index === 0) return Promise.resolve({ done: false, value: first });
      if (index === 1) return duringRead.promise;
      if (index === 2) return terminalRead.promise;
      return Promise.resolve({ done: true });
    },
    readCount: 0,
    cancel() { return Promise.resolve(); },
    releaseLock() {},
  };

  const rawFacade = await freshFacade();
  let armCheckpoint = false;
  let checkpointPending = false;
  let rejectNextCancel = false;
  const facade = new Proxy(rawFacade, {
    get(target, property) {
      if (property === 'snapshot') {
        return () => {
          const snapshot = target.snapshot();
          if (armCheckpoint) {
            armCheckpoint = false;
            checkpointPending = true;
            checkpointSeen.resolve();
            queueMicrotask(() => duringRead.resolve({ done: false, value: during }));
          }
          return snapshot;
        };
      }
      if (property === 'stream_feed') {
        return (handle, chunk) => {
          const result = target.stream_feed(handle, chunk);
          if (checkpointPending && chunk.includes('during checkpoint')) deltaFedDuringCheckpoint.resolve();
          return result;
        };
      }
      if (property === 'dispatch') {
        return (raw) => {
          const request = JSON.parse(raw);
          if (request.operation === 'session_cancel' && rejectNextCancel) {
            rejectNextCancel = false;
            checkpointPending = false;
            cancelDispatch.resolve();
            return JSON.stringify({ ok: false, error: 'fixture rejected cancellation' });
          }
          return target.dispatch(raw);
        };
      }
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  const host = await context.host(async () => ({
    ok: true,
    headers: new Headers({ 'content-type': 'text/event-stream' }),
    body: { getReader: () => reader },
  }), facade);
  context.addCleanup(() => {
    duringRead.resolve({ done: true });
    terminalRead.resolve({ done: true });
  });

  const id = await send(host, 'Keep streaming if cancellation is rejected.');
  await readsStarted[1].promise;
  const beforeCancel = await host.session(id);
  assert.equal(beforeCancel.events.some((event) => event.type === 'assistant/stream_delta'), false, 'the initial short delta is still waiting in the host buffer');

  armCheckpoint = true;
  rejectNextCancel = true;
  const cancellation = host.call('session_cancel', { session_id: id });
  await checkpointSeen.promise;
  await deltaFedDuringCheckpoint.promise;
  const rejected = await cancellation;
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /fixture rejected cancellation/);
  await cancelDispatch.promise;
  await readsStarted[2].promise;
  terminalRead.resolve({ done: false, value: terminal });

  const completed = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(completed.status, 'completed');
  const assistant = completed.messages.filter((message) => message.role === 'assistant');
  assert.equal(assistant.length, 1);
  assert.equal(assistant[0].content, 'before checkpoint during checkpoint');
  assert.equal(host.status, 'running');
});

test('a timed stream flush queued behind cancellation becomes harmless after the preflight owns its batch', async (t) => {
  const context = await temporary(t);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const readPending = deferred();
  const secondReadStarted = deferred();
  let readCount = 0;
  const reader = {
    read() {
      readCount++;
      if (readCount === 1) return Promise.resolve({
        done: false,
        value: encoder.encode(openAIChunk({ role: 'assistant' }) + openAIChunk({ content: 'timer race partial' })),
      });
      secondReadStarted.resolve();
      return readPending.promise;
    },
    cancel() {
      readPending.resolve({ done: true });
      return Promise.resolve();
    },
    releaseLock() {},
  };
  const host = await context.host(async () => ({
    ok: true,
    headers: new Headers({ 'content-type': 'text/event-stream' }),
    body: { getReader: () => reader },
  }));
  context.addCleanup(() => readPending.resolve({ done: true }));

  try {
    const id = await send(host, 'Cancel while the short-delta timer is pending.');
    await secondReadStarted.promise;
    const beforeCancel = await host.session(id);
    assert.equal(beforeCancel.events.some((event) => event.type === 'assistant/stream_delta'), false);

    const cancellation = host.call('session_cancel', { session_id: id });
    // No microtask can enter the serialized cancel callback until this stack
    // returns, so the due timer queues its flush behind that cancellation.
    t.mock.timers.tick(100);
    t.mock.timers.reset();
    const cancelled = await cancellation;
    assert.equal(cancelled.ok, true, cancelled.error);
    assert.equal(cancelled.result.status, 'cancelled');
    await waitUntil(() => host.activeCount, (activeCount) => activeCount === 0);
    const state = await host.session(id);
    assert.equal(state.status, 'cancelled');
    assert.equal(state.messages.find((message) => message.role === 'assistant').content, 'timer race partial');
    assert.equal(state.events.filter((event) => event.type === 'assistant/stream_delta').length, 1);
    assert.equal(host.status, 'running', 'the stale queued flush cannot fail the host');
  } finally {
    t.mock.timers.reset();
  }
});

test('host shutdown waits for asynchronous provider body cancellation cleanup', async (t) => {
  const context = await temporary(t);
  const pendingRead = deferred();
  const cancelStarted = deferred();
  const cancelCleanup = deferred();
  let reads = 0;
  const reader = {
    read() {
      reads++;
      if (reads === 1) return Promise.resolve({
        done: false,
        value: encoder.encode(openAIChunk({ role: 'assistant' }) + openAIChunk({ content: 'shutdown partial' })),
      });
      return pendingRead.promise;
    },
    cancel() {
      cancelStarted.resolve();
      pendingRead.resolve({ done: true });
      return cancelCleanup.promise;
    },
    releaseLock() {},
  };
  const host = await context.host(async () => ({
    ok: true,
    headers: new Headers({ 'content-type': 'text/event-stream' }),
    body: { getReader: () => reader },
  }));
  context.addCleanup(() => {
    pendingRead.resolve({ done: true });
    cancelCleanup.resolve();
  });

  const id = await send(host, 'Stop while the provider body is open.');
  await waitUntil(() => host.session(id), (session) =>
    session.events.some((event) => event.type === 'assistant/stream_delta'));
  await waitUntil(async () => reads, (count) => count >= 2);

  let closed = false;
  const closing = host.close().then(() => { closed = true; });
  await cancelStarted.promise;
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(closed, false, 'the host remains open while the provider body cleanup is unsettled');
  cancelCleanup.resolve();
  await closing;
  assert.equal(closed, true);
});
