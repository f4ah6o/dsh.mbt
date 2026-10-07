import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as fs from 'node:fs/promises';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';

async function freshFacade() {
  return import(`${pathToFileURL(defaultModulePath).href}?test=${randomUUID()}`);
}

async function temporary(t) {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-provider-retry-'));
  const dataDir = path.join(workspace, '.dsh.mbt');
  const hosts = [];
  t.after(async () => {
    await Promise.allSettled(hosts.map((host) => host.close()));
    await fs.rm(workspace, { recursive: true, force: true });
  });
  return { workspace, dataDir, hosts };
}

function providerResponse(content = 'done', toolCalls = []) {
  return new Response(JSON.stringify({
    choices: [{
      message: {
        role: 'assistant',
        content,
        ...(toolCalls.length ? {
          tool_calls: toolCalls.map((call) => ({
            id: call.id,
            type: 'function',
            function: { name: call.name, arguments: JSON.stringify(call.arguments) },
          })),
        } : {}),
      },
      finish_reason: toolCalls.length ? 'tool_calls' : 'stop',
    }],
  }), { headers: { 'content-type': 'application/json' } });
}

async function start(host, prompt = 'retry fixture') {
  const created = await host.call('session_create', {});
  assert.equal(created.ok, true, created.error);
  const sent = await host.call('session_send', { session_id: created.result.id, prompt });
  assert.equal(sent.ok, true, sent.error);
  return created.result.id;
}

async function until(predicate, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('Timed out waiting for the provider retry fixture');
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function hostOptions(workspace, dataDir, options = {}) {
  return {
    workspace,
    dataDir,
    mode: 'openai',
    model: 'retry-fixture-model',
    baseURL: 'http://127.0.0.1:1/v1',
    maxRetries: 1,
    retryInitialDelayMs: 0,
    retryMaxDelayMs: 10,
    ...options,
  };
}

test('retry schedule and start are checkpointed before the identical next provider request', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  const bodies = [];
  let secondAttemptEvents;
  const host = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async (_url, init) => {
      bodies.push(init.body);
      const durable = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8')).sessions[0];
      if (bodies.length === 1) {
        assert.ok(durable.events.some((event) => event.type === 'llm/request'));
        return new Response('private response body', { status: 503 });
      }
      secondAttemptEvents = durable.events.map((event) => event.type);
      assert.ok(secondAttemptEvents.includes('llm/retry'));
      assert.ok(secondAttemptEvents.includes('llm/retry-started'));
      assert.equal(secondAttemptEvents.filter((type) => type === 'llm/request').length, 1);
      return providerResponse('recovered');
    },
  }));
  hosts.push(host);
  const id = await start(host);
  const final = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(final.status, 'completed');
  assert.equal(final.messages.at(-1).content, 'recovered');
  assert.equal(bodies.length, 2);
  assert.equal(bodies[0], bodies[1], 'the retry reuses the frozen request body');
  assert.ok(secondAttemptEvents.includes('llm/retry-started'));
  assert.equal(final.events.filter((event) => event.type === 'llm/request').length, 1);
  const scheduled = final.events.find((event) => event.type === 'llm/retry');
  assert.equal(scheduled.data.failure.code, 'SERVER');
  assert.equal(scheduled.data.failure.status, 503);
  await host.close();
  const reopened = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => { throw new Error('completed work must not replay'); },
  }));
  hosts.push(reopened);
  assert.equal((await reopened.session(id)).status, 'completed');
  assert.equal(reopened.activeCount, 0);
});

test('retry capacity refusal closes only the large turn and leaves the host recoverable', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  let requests = 0;
  const host = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => {
      requests++;
      if (requests === 1) return providerResponse('A'.repeat(65_000));
      if (requests === 2) return providerResponse('B'.repeat(64_000));
      if (requests === 3) return new Response('private response body', { status: 503 });
      return providerResponse('another session completed');
    },
  }));
  hosts.push(host);

  const created = await host.call('session_create', { max_steps: 1 });
  assert.equal(created.ok, true, created.error);
  const id = created.result.id;
  const sendFirst = await host.call('session_send', { session_id: id, prompt: 'seed first large answer' });
  assert.equal(sendFirst.ok, true, sendFirst.error);
  assert.equal((await host.waitForSession(id, { signal: AbortSignal.timeout(5000) })).status, 'completed');
  const sendSecond = await host.call('session_send', { session_id: id, prompt: 'seed second large answer' });
  assert.equal(sendSecond.ok, true, sendSecond.error);
  assert.equal((await host.waitForSession(id, { signal: AbortSignal.timeout(5000) })).status, 'completed');

  // Leave enough room to admit the new turn, but not the larger retry marker
  // plus its guaranteed terminal/interruption closure.
  const nearCapacitySend = await host.call('session_send', { session_id: id, prompt: 'x'.repeat(600) });
  assert.equal(nearCapacitySend.ok, true, nearCapacitySend.error);
  const boundedFailure = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(boundedFailure.status, 'failed');
  assert.equal(boundedFailure.events.findLast((event) => event.type === 'turn/end').data.reason, 'provider_error');
  assert.equal(boundedFailure.events.filter((event) => event.type === 'llm/retry').length, 0);
  assert.equal(requests, 3, 'capacity refusal does not launch a retry request');
  assert.equal(host.status, 'running');

  const other = await start(host, 'A separate session still works.');
  const otherFinal = await host.waitForSession(other, { signal: AbortSignal.timeout(5000) });
  assert.equal(otherFinal.status, 'completed');
  assert.equal(requests, 4);
  await host.close();

  const reopened = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => { throw new Error('restored sessions must not replay'); },
  }));
  hosts.push(reopened);
  assert.equal((await reopened.session(id)).status, 'failed');
  assert.equal((await reopened.session(other)).status, 'completed');
  assert.equal(reopened.activeCount, 0);
});

test('oversized numeric and date Retry-After values fail one turn without breaking the host', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  const values = [
    '3000000',
    '999999999999999999999999999999999999',
    new Date(Date.now() + 60_000).toUTCString(),
  ];
  let currentHeader;
  let requests = 0;
  const host = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => {
      requests++;
      return new Response('private response body', {
        status: 503,
        headers: { 'retry-after': currentHeader },
      });
    },
  }));
  hosts.push(host);

  for (let index = 0; index < values.length; index++) {
    currentHeader = values[index];
    const before = requests;
    const id = await start(host, `retry-after case ${index}`);
    await until(() => host.activeCount === 0);
    const final = await host.session(id);
    assert.equal(final.status, 'failed');
    assert.equal(final.events.filter((event) => event.type === 'llm/retry').length, 0);
    assert.equal(requests - before, 1, 'oversized advice never falls back to local backoff');
    assert.equal(host.status, 'running');
    const usable = await host.call('session_create', {});
    assert.equal(usable.ok, true, usable.error);
  }
});

test('real redirect and blocked-port fetch failures are not retried', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  let redirectRequests = 0;
  const server = createServer((_request, response) => {
    redirectRequests++;
    response.writeHead(302, { location: '/redirect-target' });
    response.end();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(async () => new Promise((resolve) => server.close(resolve)));

  let fetchCalls = 0;
  const port = server.address().port;
  const redirectHost = await createHost(hostOptions(workspace, path.join(workspace, 'redirect-data'), {
    baseURL: `http://127.0.0.1:${port}/v1`,
    fetchImpl: (...args) => { fetchCalls++; return fetch(...args); },
  }));
  hosts.push(redirectHost);
  const redirectID = await start(redirectHost, 'redirect fixture');
  const redirected = await redirectHost.waitForSession(redirectID, { signal: AbortSignal.timeout(5000) });
  assert.equal(redirected.status, 'failed');
  assert.equal(redirectRequests, 1);
  assert.equal(fetchCalls, 1);
  assert.equal(redirected.events.filter((event) => event.type === 'llm/retry').length, 0);
  assert.equal(redirectHost.status, 'running');
  await redirectHost.close();

  let blockedPortCalls = 0;
  const blockedPortHost = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: (...args) => { blockedPortCalls++; return fetch(...args); },
  }));
  hosts.push(blockedPortHost);
  const blockedPortID = await start(blockedPortHost, 'blocked port fixture');
  const blockedPort = await blockedPortHost.waitForSession(blockedPortID, { signal: AbortSignal.timeout(5000) });
  assert.equal(blockedPort.status, 'failed');
  assert.equal(blockedPortCalls, 1);
  assert.equal(blockedPort.events.filter((event) => event.type === 'llm/retry').length, 0);
  assert.equal(blockedPortHost.status, 'running');
});

test('retry after a later provider failure does not repeat an already executed tool', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  await fs.writeFile(path.join(workspace, 'fixture.txt'), 'read once');
  const bodies = [];
  let requests = 0;
  const host = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async (_url, init) => {
      requests++;
      bodies.push(init.body);
      if (requests === 1) return providerResponse('', [
        { id: 'read-once', name: 'read', arguments: { file_path: 'fixture.txt' } },
      ]);
      if (requests === 2) return new Response('private response body', { status: 503 });
      return providerResponse('tool result survived retry');
    },
  }));
  hosts.push(host);
  const id = await start(host, 'Read fixture.txt and summarize it.');
  const final = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(final.status, 'completed');
  assert.equal(requests, 3);
  assert.equal(bodies[1], bodies[2], 'only the failed provider request is repeated');
  assert.equal(final.events.filter((event) => event.type === 'tool/call').length, 1);
  assert.equal(final.events.filter((event) => event.type === 'tool/result').length, 1);
  assert.equal(final.events.filter((event) => event.type === 'llm/request').length, 2);
  assert.equal(final.events.filter((event) => event.type === 'llm/retry').length, 1);
  assert.equal(final.events.filter((event) => event.type === 'llm/retry-started').length, 1);
  assert.equal(final.messages.filter((message) => message.role === 'tool').length, 1);
});

test('a queued partial stream delta is checkpointed and blocks transport retry', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  let requests = 0;
  const partial = 'accepted before disconnect';
  const host = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => {
      requests++;
      const body = new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(
            `data: ${JSON.stringify({ choices: [{ index: 0, delta: { role: 'assistant', content: partial } }] })}\n\n`,
          ));
        },
        pull(controller) {
          controller.error(Object.assign(new Error('socket reset'), { code: 'ECONNRESET' }));
        },
      });
      return new Response(body, { headers: { 'content-type': 'text/event-stream' } });
    },
  }));
  hosts.push(host);
  const id = await start(host, 'Stream a short answer.');
  const final = await host.waitForSession(id, { signal: AbortSignal.timeout(5000) });
  assert.equal(final.status, 'failed');
  assert.equal(requests, 1);
  assert.equal(final.events.filter((event) => event.type === 'assistant/stream_delta').length, 1);
  assert.equal(final.events.filter((event) => event.type === 'llm/retry').length, 0);
  assert.equal(final.messages.find((message) => message.role === 'assistant').content, partial);
});

test('cancellation during backoff prevents retry start and restore never replays it', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  let requests = 0;
  const host = await createHost(hostOptions(workspace, dataDir, {
    retryInitialDelayMs: 1000,
    retryMaxDelayMs: 1000,
    fetchImpl: async () => {
      requests++;
      return new Response('private response body', { status: 503 });
    },
  }));
  hosts.push(host);
  const id = await start(host);
  await until(() => {
    try {
      const durable = JSON.parse(readFileSync(path.join(dataDir, 'sessions.json'), 'utf8'));
      return durable.sessions[0].events.some((event) => event.type === 'llm/retry');
    } catch { return false; }
  });
  const cancelled = await host.call('session_cancel', { session_id: id });
  assert.equal(cancelled.ok, true, cancelled.error);
  assert.equal(cancelled.result.status, 'cancelled');
  await until(() => host.activeCount === 0);
  const state = await host.session(id);
  assert.equal(state.events.filter((event) => event.type === 'llm/retry').length, 1);
  assert.equal(state.events.filter((event) => event.type === 'llm/retry-started').length, 0);
  assert.equal(requests, 1);

  await host.close();
  const reopened = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => { requests++; throw new Error('cancelled work must not replay'); },
  }));
  hosts.push(reopened);
  assert.equal((await reopened.session(id)).status, 'cancelled');
  assert.equal(reopened.activeCount, 0);
  assert.equal(requests, 1);
});

test('shutdown during retry-start checkpoint never begins the next request', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  const rawFacade = await freshFacade();
  let host;
  let closePromise;
  const facade = new Proxy(rawFacade, {
    get(target, property) {
      if (property === 'snapshot') return () => {
        const snapshot = target.snapshot();
        const state = JSON.parse(snapshot);
        if (!closePromise && state.sessions.some((session) => session.events.some((event) => event.type === 'llm/retry-started'))) {
          closePromise = host.close();
        }
        return snapshot;
      };
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  let requests = 0;
  host = await createHost(hostOptions(workspace, dataDir, {
    facade,
    fetchImpl: async () => { requests++; return new Response('private response body', { status: 503 }); },
  }));
  hosts.push(host);
  const id = await start(host);
  await until(() => closePromise !== undefined);
  await closePromise;
  assert.equal(requests, 1);
  const durable = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8')).sessions[0];
  assert.equal(durable.status, 'cancelled');
  assert.ok(durable.events.some((event) => event.type === 'llm/retry-started'));
});

test('a failed retry-start checkpoint prevents provider IO and leaves only the durable schedule', async (t) => {
  const { workspace, dataDir, hosts } = await temporary(t);
  const rawFacade = await freshFacade();
  let failStartCheckpoint = false;
  const facade = new Proxy(rawFacade, {
    get(target, property) {
      if (property === 'retry_started') return (...args) => {
        const result = target.retry_started(...args);
        failStartCheckpoint = true;
        return result;
      };
      if (property === 'snapshot') return () => {
        if (failStartCheckpoint) {
          failStartCheckpoint = false;
          throw new Error('retry start checkpoint fixture failure');
        }
        return target.snapshot();
      };
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  let requests = 0;
  const host = await createHost(hostOptions(workspace, dataDir, {
    facade,
    fetchImpl: async () => { requests++; return new Response('private response body', { status: 503 }); },
  }));
  hosts.push(host);
  const id = await start(host);
  await until(() => host.status === 'failed' && host.activeCount === 0);
  assert.equal(requests, 1);
  assert.equal(host.status, 'failed');
  await host.close();
  const durable = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8')).sessions[0];
  assert.equal(durable.status, 'running');
  assert.equal(durable.events.filter((event) => event.type === 'llm/retry').length, 1);
  assert.equal(durable.events.filter((event) => event.type === 'llm/retry-started').length, 0);

  const reopened = await createHost(hostOptions(workspace, dataDir, {
    fetchImpl: async () => { requests++; throw new Error('interrupted retry must not replay'); },
  }));
  hosts.push(reopened);
  const interrupted = await reopened.session(id);
  assert.equal(interrupted.status, 'failed');
  assert.equal(reopened.activeCount, 0);
  assert.equal(requests, 1);
});
