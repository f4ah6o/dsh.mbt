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

async function within(promise, description, timeoutMs = 5000) {
  let settled = false;
  let value;
  let error;
  Promise.resolve(promise).then(
    (result) => { settled = true; value = result; },
    (reason) => { settled = true; error = reason; },
  );
  const deadline = Date.now() + timeoutMs;
  while (!settled && Date.now() < deadline) {
    await new Promise((resolve) => setImmediate(resolve));
  }
  if (!settled) throw new Error(`Timed out waiting for ${description}`);
  if (error) throw error;
  return value;
}

async function largeDeltaCancellationFixture(context, { rejectCancellation }) {
  const initialText = 'before checkpoint';
  const overflowText = 'B'.repeat(5000);
  const initialBytes = encoder.encode(openAIChunk({ role: 'assistant' }) + openAIChunk({ content: initialText }));
  const overflowBytes = encoder.encode(openAIChunk({ content: overflowText }));
  const terminalBytes = encoder.encode([openAIChunk({}, 'stop'), 'data: [DONE]\n\n'].join(''));
  const overflowRead = deferred();
  const terminalRead = deferred();
  const secondReadStarted = deferred();
  const thirdReadStarted = deferred();
  const checkpointSeen = deferred();
  const overflowDrained = deferred();
  const cancelDispatch = deferred();
  const projects = [];
  const projectionCheckpoints = [];
  let armCheckpoint = false;
  let checkpointPending = false;
  let awaitingProjectionCheckpoint = false;
  let cancelDispatchSeen = false;
  let overflowWasDrained = false;
  let sessionID;
  let readCount = 0;

  const reader = {
    read() {
      const index = readCount++;
      if (index === 0) return Promise.resolve({ done: false, value: initialBytes });
      if (index === 1) {
        secondReadStarted.resolve();
        return overflowRead.promise;
      }
      if (index === 2) {
        thirdReadStarted.resolve();
        return terminalRead.promise;
      }
      return Promise.resolve({ done: true });
    },
    cancel() {
      overflowRead.resolve({ done: true });
      terminalRead.resolve({ done: true });
      return Promise.resolve();
    },
    releaseLock() {},
  };
  const rawFacade = await freshFacade();
  const facade = new Proxy(rawFacade, {
    get(target, property) {
      if (property === 'snapshot') {
        return () => {
          const raw = target.snapshot();
          if (awaitingProjectionCheckpoint) {
            awaitingProjectionCheckpoint = false;
            const state = JSON.parse(raw);
            const session = state.sessions.find((item) => item.id === sessionID);
            const partial = session?.messages.find((message) => message.provisional === true);
            projectionCheckpoints.push({
              status: session?.status,
              eventCount: session?.events.length,
              streamRevision: session?.stream_revision,
              content: partial?.content,
            });
          }
          if (armCheckpoint) {
            armCheckpoint = false;
            checkpointPending = true;
            checkpointSeen.resolve();
            queueMicrotask(() => overflowRead.resolve({ done: false, value: overflowBytes }));
          }
          return raw;
        };
      }
      if (property === 'stream_project') {
        return (effectID, content, reasoning) => {
          const result = target.stream_project(effectID, content, reasoning);
          const parsed = JSON.parse(result);
          projects.push({
            content,
            reasoning,
            afterCancelDispatch: cancelDispatchSeen,
          });
          if (parsed.ok) awaitingProjectionCheckpoint = true;
          return result;
        };
      }
      if (property === 'stream_take_deltas') {
        return (handle) => {
          const result = target.stream_take_deltas(handle);
          if (checkpointPending && result.includes(overflowText.slice(0, 32))) {
            overflowWasDrained = true;
            overflowDrained.resolve();
          }
          return result;
        };
      }
      if (property === 'dispatch') {
        return (raw) => {
          const request = JSON.parse(raw);
          if (request.operation === 'session_cancel') {
            cancelDispatchSeen = true;
            if (rejectCancellation) {
              checkpointPending = false;
              cancelDispatch.resolve({
                accepted: false,
                projectCount: projects.length,
                projectionCheckpointCount: projectionCheckpoints.length,
                overflowWasDrained,
              });
              return JSON.stringify({ ok: false, error: 'fixture rejected cancellation' });
            }
            const result = target.dispatch(raw);
            const accepted = JSON.parse(result).ok;
            cancelDispatch.resolve({
              accepted,
              projectCount: projects.length,
              projectionCheckpointCount: projectionCheckpoints.length,
              overflowWasDrained,
            });
            if (accepted) checkpointPending = false;
            return result;
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
    overflowRead.resolve({ done: true });
    terminalRead.resolve({ done: true });
  });

  return {
    host,
    initialText,
    overflowText,
    projects,
    projectionCheckpoints,
    secondReadStarted: secondReadStarted.promise,
    thirdReadStarted: thirdReadStarted.promise,
    checkpointSeen: checkpointSeen.promise,
    overflowDrained: overflowDrained.promise,
    cancelDispatch: cancelDispatch.promise,
    arm(id) {
      sessionID = id;
      armCheckpoint = true;
    },
    finish() { terminalRead.resolve({ done: false, value: terminalBytes }); },
  };
}

async function assertDiskMatchesLive(context, host, id) {
  const live = await host.session(id);
  const snapshot = JSON.parse(await readFile(path.join(context.dataDir, 'sessions.json'), 'utf8'));
  const disk = snapshot.sessions.find((session) => session.id === id);
  assert.ok(disk, `expected persisted session ${id}`);
  assert.deepEqual(disk, live);
  assert.equal(disk.events.length, live.events.length);
  assert.equal(disk.status, live.status);
  return live;
}

function assertCompleteOverflowProjection(fixture, expected) {
  assert.deepEqual(fixture.projects.map((project) => project.content), [
    fixture.initialText,
    fixture.overflowText.slice(0, 4096),
    fixture.overflowText.slice(4096),
  ]);
  assert.equal(fixture.projects.every((project) => !project.afterCancelDispatch), true, 'no stream projection starts after cancellation dispatch');
  assert.deepEqual(fixture.projectionCheckpoints.map((checkpoint) => checkpoint.content), [
    fixture.initialText,
    `${fixture.initialText}${fixture.overflowText.slice(0, 4096)}`,
    expected,
  ]);
  assert.ok(fixture.projectionCheckpoints.every((checkpoint) => checkpoint.status === 'running'));
  for (let index = 1; index < fixture.projectionCheckpoints.length; index++) {
    assert.ok(fixture.projectionCheckpoints[index].eventCount > fixture.projectionCheckpoints[index - 1].eventCount, 'each saved projection advances the event log');
    assert.ok(fixture.projectionCheckpoints[index].streamRevision > fixture.projectionCheckpoints[index - 1].streamRevision, 'each saved projection advances the stream revision');
  }
  assert.equal(fixture.projectionCheckpoints.at(-1).streamRevision, expected.length);
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

test('accepted cancellation drains a 5000-unit callback before dispatch and persists the cancelled revision last', async (t) => {
  const context = await temporary(t);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const fixture = await largeDeltaCancellationFixture(context, { rejectCancellation: false });
  try {
    const id = await within(send(fixture.host, 'Cancel only after the live text checkpoint finishes.'), 'the streamed request to start');
    await within(fixture.secondReadStarted, 'the provider to begin its second read');
    const beforeCancel = await fixture.host.session(id);
    assert.equal(beforeCancel.events.some((event) => event.type === 'assistant/stream_delta'), false);

    fixture.arm(id);
    const result = await within(fixture.host.call('session_cancel', { session_id: id }), 'accepted cancellation to finish');
    t.mock.timers.reset();
    assert.equal(result.ok, true, result.error);
    assert.equal(result.result.status, 'cancelled');
    const dispatch = await within(fixture.cancelDispatch, 'the cancellation dispatch to be observed');
    assert.equal(dispatch.accepted, true);
    assert.equal(dispatch.overflowWasDrained, true, 'the provider callback was consumed before cancellation dispatch');
    assert.equal(dispatch.projectCount, 3);
    assert.equal(dispatch.projectionCheckpointCount, 3, 'all three bounded batches reached their checkpoint before cancellation');

    await waitUntil(() => fixture.host.activeCount, (activeCount) => activeCount === 0);
    const expected = `${fixture.initialText}${fixture.overflowText}`;
    const live = await assertDiskMatchesLive(context, fixture.host, id);
    assert.equal(live.status, 'cancelled');
    const partial = live.messages.find((message) => message.provisional === true);
    assert.equal(partial.stream_status, 'partial');
    assert.equal(partial.content, expected);
    assert.equal(live.events.filter((event) => event.type === 'assistant/stream_delta').map((event) => event.data.content).join(''), expected);
    assertCompleteOverflowProjection(fixture, expected);

    await new Promise((resolve) => setImmediate(resolve));
    await assertDiskMatchesLive(context, fixture.host, id);
  } finally {
    t.mock.timers.reset();
  }
});

test('rejected cancellation checkpoints the full overflow callback, resumes, and saves the completed transcript', async (t) => {
  const context = await temporary(t);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const fixture = await largeDeltaCancellationFixture(context, { rejectCancellation: true });
  try {
    const id = await within(send(fixture.host, 'Continue streaming when cancellation is rejected.'), 'the streamed request to start');
    await within(fixture.secondReadStarted, 'the provider to begin its second read');
    const beforeCancel = await fixture.host.session(id);
    assert.equal(beforeCancel.events.some((event) => event.type === 'assistant/stream_delta'), false);

    fixture.arm(id);
    const result = await within(fixture.host.call('session_cancel', { session_id: id }), 'rejected cancellation to finish');
    t.mock.timers.reset();
    assert.equal(result.ok, false);
    assert.match(result.error, /fixture rejected cancellation/);
    const dispatch = await within(fixture.cancelDispatch, 'the cancellation dispatch to be observed');
    assert.equal(dispatch.accepted, false);
    assert.equal(dispatch.overflowWasDrained, true);
    assert.equal(dispatch.projectCount, 3);
    assert.equal(dispatch.projectionCheckpointCount, 3, 'all overflow batches settle before the rejected cancel returns');

    const running = await fixture.host.session(id);
    assert.equal(running.status, 'running');
    await within(fixture.thirdReadStarted, 'the provider to resume after cancellation rejection');
    fixture.finish();
    const completed = await within(fixture.host.waitForSession(id, { signal: AbortSignal.timeout(5000) }), 'the resumed stream to complete');
    assert.equal(completed.status, 'completed');
    assert.equal(completed.messages.at(-1).content, `${fixture.initialText}${fixture.overflowText}`);
    await waitUntil(() => fixture.host.activeCount, (activeCount) => activeCount === 0);
    const live = await assertDiskMatchesLive(context, fixture.host, id);
    assert.equal(live.status, 'completed');
    assertCompleteOverflowProjection(fixture, `${fixture.initialText}${fixture.overflowText}`);
    await new Promise((resolve) => setImmediate(resolve));
    await assertDiskMatchesLive(context, fixture.host, id);
  } finally {
    t.mock.timers.reset();
  }
});

test('cancellation queued behind a snapshot does not wait on a provider flush queued behind cancellation', async (t) => {
  const context = await temporary(t);
  const initial = encoder.encode(openAIChunk({ role: 'assistant' }));
  const admittedText = 'Q'.repeat(600);
  const admitted = encoder.encode(openAIChunk({ content: admittedText }));
  const overflowRead = deferred();
  const trailingRead = deferred();
  const secondReadStarted = deferred();
  let readCount = 0;
  let injectNextSnapshot = false;
  let injectionFired = false;
  let cancelDispatchSeen = false;
  let deltaDrainedBeforeCancelDispatch = false;
  const projects = [];
  const reader = {
    read() {
      const index = readCount++;
      if (index === 0) return Promise.resolve({ done: false, value: initial });
      if (index === 1) {
        secondReadStarted.resolve();
        return overflowRead.promise;
      }
      return trailingRead.promise;
    },
    cancel() {
      overflowRead.resolve({ done: true });
      trailingRead.resolve({ done: true });
      return Promise.resolve();
    },
    releaseLock() {},
  };
  const rawFacade = await freshFacade();
  const facade = new Proxy(rawFacade, {
    get(target, property) {
      if (property === 'snapshot') {
        return () => {
          const snapshot = target.snapshot();
          if (injectNextSnapshot) {
            injectNextSnapshot = false;
            injectionFired = true;
            // Resolving synchronously queues the provider's read continuation
            // before this snapshot releases the serial action ahead of cancel.
            overflowRead.resolve({ done: false, value: admitted });
          }
          return snapshot;
        };
      }
      if (property === 'stream_take_deltas') {
        return (handle) => {
          const result = target.stream_take_deltas(handle);
          if (result.includes(admittedText.slice(0, 32)) && !cancelDispatchSeen) {
            deltaDrainedBeforeCancelDispatch = true;
          }
          return result;
        };
      }
      if (property === 'stream_project') {
        return (effectID, content, reasoning) => {
          const result = target.stream_project(effectID, content, reasoning);
          if (JSON.parse(result).ok) projects.push({ content, afterCancelDispatch: cancelDispatchSeen });
          return result;
        };
      }
      if (property === 'dispatch') {
        return (raw) => {
          const request = JSON.parse(raw);
          if (request.operation === 'session_cancel') cancelDispatchSeen = true;
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
    overflowRead.resolve({ done: true });
    trailingRead.resolve({ done: true });
  });

  const id = await within(send(host, 'Cancel while a provider delta races the serialized queue.'), 'the streamed request to start');
  await within(secondReadStarted.promise, 'the provider to begin its second read');
  const before = await host.session(id);
  assert.equal(before.events.some((event) => event.type === 'assistant/stream_delta'), false);

  injectNextSnapshot = true;
  const earlierSnapshot = host.session(id);
  // Queue cancellation behind the snapshot action. Its snapshot releases the
  // provider read, whose >=512-unit callback queues its flush behind cancel.
  const cancellation = host.call('session_cancel', { session_id: id });
  await within(earlierSnapshot, 'the preceding snapshot action to finish');
  assert.equal(injectionFired, true, 'the injected delta arrived while cancellation was already queued');
  const cancelled = await within(cancellation, 'cancellation to settle despite the queued provider flush', 3000);
  assert.equal(cancelled.ok, true, cancelled.error);
  assert.equal(cancelled.result.status, 'cancelled');
  assert.equal(deltaDrainedBeforeCancelDispatch, true, 'the provider validated the delta before engine cancellation dispatch');
  assert.ok(projects.length > 0);
  assert.equal(projects.map((project) => project.content).join(''), admittedText);
  assert.equal(projects.every((project) => !project.afterCancelDispatch), true, 'no queued flush projects after cancellation dispatch');

  await waitUntil(() => host.activeCount, (activeCount) => activeCount === 0);
  const live = await assertDiskMatchesLive(context, host, id);
  assert.equal(live.status, 'cancelled');
  assert.equal(live.messages.find((message) => message.provisional === true)?.content, admittedText);
  assert.equal(live.events.filter((event) => event.type === 'assistant/stream_delta').map((event) => event.data.content).join(''), admittedText);
  await new Promise((resolve) => setImmediate(resolve));
  await assertDiskMatchesLive(context, host, id);
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
