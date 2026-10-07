import test from 'node:test';
import assert from 'node:assert/strict';
import { createProvider, providerURL } from '../../host/provider.mjs';

const envelope = (result) => JSON.stringify({ ok: true, result });
function fixture({ content = 'streamed', deltas = [{ channel: 'content', text: content }] } = {}) {
  const fed = [];
  const aborted = [];
  let pendingDeltas = deltas;
  const facade = {
    prepare_request(mode, model, raw) { return envelope({ path: mode === 'deepseek' ? '/v1/messages' : '/v1/chat/completions', headers: { 'content-type': 'application/json', 'anthropic-version': '2023-06-01' }, body: { model, ...JSON.parse(raw) } }); },
    decode_response(_mode, raw) { return envelope({ ok: true, content: JSON.parse(raw).content, tool_calls: [] }); },
    stream_start() { return 7; },
    stream_feed(handle, chunk) { assert.equal(handle, 7); fed.push(chunk); return envelope(true); },
    stream_take_deltas(handle) { assert.equal(handle, 7); const value = pendingDeltas; pendingDeltas = []; return envelope(value); },
    stream_finish(handle) { assert.equal(handle, 7); return envelope({ ok: true, content, tool_calls: [] }); },
    stream_abort(handle) { aborted.push(handle); },
  };
  return { facade, fed, aborted };
}

test('provider URL joining preserves custom prefixes without duplicate v1 segments', () => {
  assert.equal(String(providerURL('https://api.deepseek.com/anthropic', '/v1/messages')), 'https://api.deepseek.com/anthropic/v1/messages');
  assert.equal(String(providerURL('https://api.deepseek.com/anthropic/v1/', '/v1/messages')), 'https://api.deepseek.com/anthropic/v1/messages');
  assert.equal(String(providerURL('http://localhost:1234/v1', '/v1/chat/completions')), 'http://localhost:1234/v1/chat/completions');
  for (const base of ['file:///tmp/test', 'https://user:secret@example.com', 'https://example.com?key=secret']) assert.throws(() => providerURL(base, '/v1/messages'));
});

test('API credentials are added only by the HTTP carrier, using the selected protocol', async () => {
  for (const mode of ['deepseek', 'openai']) {
    const { facade } = fixture();
    let seen;
    const provider = createProvider({ facade, mode, model: 'configured-model', apiKey: 'private-key', fetchImpl: async (url, init) => {
      seen = { url: String(url), init };
      return new Response('{"content":"ok"}', { headers: { 'content-type': 'application/json' } });
    } });
    assert.equal((await provider.invoke({ messages: [] })).content, 'ok');
    assert.equal(seen.init.headers.get(mode === 'deepseek' ? 'x-api-key' : 'authorization'), mode === 'deepseek' ? 'private-key' : 'Bearer private-key');
    assert.ok(!seen.init.body.includes('private-key'));
    assert.equal(seen.init.redirect, 'error');
    assert.match(seen.url, mode === 'deepseek' ? /anthropic\/v1\/messages$/ : /v1\/chat\/completions$/);
  }
  assert.throws(() => createProvider({ facade: fixture().facade, mode: 'openai' }), /explicit model/);
});

test('SSE handles split UTF-8 bytes and always releases its MoonBit decoder', async () => {
  const { facade, fed, aborted } = fixture({ content: 'こんにちは' });
  const raw = 'data: {"content":"こんにちは"}\r\n\r\n';
  const bytes = new TextEncoder().encode(raw);
  const projected = [];
  const provider = createProvider({ facade, apiKey: 'key', fetchImpl: async () => new Response(new ReadableStream({ start(controller) {
    for (let offset = 0; offset < bytes.length; offset += 2) controller.enqueue(bytes.subarray(offset, offset + 2));
    controller.close();
  } }), { headers: { 'content-type': 'text/event-stream' } }) });
  assert.equal((await provider.invoke({}, { onDelta: (delta) => projected.push(delta) })).content, 'こんにちは');
  assert.deepEqual(projected, [{ content: 'こんにちは', reasoning: '' }]);
  assert.equal(fed.join(''), raw);
  assert.deepEqual(aborted, [7]);
});

test('validated deltas are delivered before a later frame error and final divergence fails closed', async () => {
  const first = fixture();
  first.facade.stream_feed = () => JSON.stringify({ ok: false, error: 'malformed later frame' });
  const projected = [];
  const provider = createProvider({ facade: first.facade, apiKey: 'key', fetchImpl: async () => new Response('data: frames\n\n', { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(provider.invoke({}, { onDelta: (delta) => projected.push(delta) }), /malformed later frame/);
  assert.deepEqual(projected, [{ content: 'streamed', reasoning: '' }]);

  const divergent = fixture();
  divergent.facade.stream_finish = () => envelope({ ok: true, content: 'different', tool_calls: [] });
  const badFinal = createProvider({ facade: divergent.facade, apiKey: 'key', fetchImpl: async () => new Response('data: frame\n\n', { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(badFinal.invoke({}), /differs from its live/);
});

test('malformed or oversized streams release handles and surface a bounded failure', async () => {
  const { facade, aborted } = fixture();
  facade.stream_feed = () => JSON.stringify({ ok: false, error: 'malformed SSE' });
  const provider = createProvider({ facade, apiKey: 'key', fetchImpl: async () => new Response('data: bad\n\n', { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(provider.invoke({}), /malformed SSE/);
  assert.deepEqual(aborted, [7]);

  let bodyCancelled = false;
  const unread = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('data: bad\n\n')); },
    cancel() { bodyCancelled = true; },
  });
  const cancellingFacade = fixture().facade;
  cancellingFacade.stream_feed = () => JSON.stringify({ ok: false, error: 'malformed SSE' });
  const unreadProvider = createProvider({ facade: cancellingFacade, apiKey: 'key', fetchImpl: async () => new Response(unread, { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(unreadProvider.invoke({}), /malformed SSE/);
  assert.equal(bodyCancelled, true);

  let finishCleanup;
  let cleanupStarted = false;
  let invokeSettled = false;
  const slowCancelBody = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('data: bad\n\n')); },
    cancel() {
      cleanupStarted = true;
      return new Promise((resolve) => { finishCleanup = resolve; });
    },
  });
  const slowCancelFacade = fixture().facade;
  slowCancelFacade.stream_feed = () => JSON.stringify({ ok: false, error: 'malformed SSE' });
  const slowCancelProvider = createProvider({ facade: slowCancelFacade, apiKey: 'key', timeoutMs: 5, fetchImpl: async () => new Response(slowCancelBody, { headers: { 'content-type': 'text/event-stream' } }) });
  const pendingInvoke = slowCancelProvider.invoke({}).finally(() => { invokeSettled = true; });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(cleanupStarted, true);
  assert.equal(invokeSettled, false);
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(invokeSettled, false, 'the request deadline does not replace a parser failure during cleanup');
  finishCleanup();
  await assert.rejects(pendingInvoke, (error) => error.code === 'MALFORMED' && /malformed SSE/.test(error.message));
  assert.equal(invokeSettled, true);

  const oversized = createProvider({ facade: fixture().facade, apiKey: 'key', responseLimit: 12, fetchImpl: async () => new Response('x'.repeat(100), { headers: { 'content-type': 'application/json' } }) });
  await assert.rejects(oversized.invoke({}), /size limit/);
});

test('timeouts and HTTP failures expose stable retry metadata without echoing secrets', async () => {
  const { facade } = fixture();
  let signal;
  const timeout = createProvider({ facade, apiKey: 'test-secret', timeoutMs: 15, fetchImpl: async (_url, init) => {
    signal = init.signal;
    return new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true }));
  } });
  await assert.rejects(timeout.invoke({}), /timed out/);
  assert.equal(signal.aborted, true);
  const denied = createProvider({ facade, apiKey: 'test-secret', fetchImpl: async () => new Response('Bad key test-secret', { status: 401 }) });
  await assert.rejects(denied.invoke({}), (error) => /HTTP 401/.test(error.message)
    && error.code === 'AUTH' && !error.message.includes('Bad key') && !error.message.includes('test-secret'));

  for (const [status, code] of [[408, 'TIMEOUT'], [429, 'RATE_LIMIT'], [503, 'SERVER'], [400, 'HTTP_ERROR']]) {
    let requests = 0;
    const provider = createProvider({ facade, apiKey: 'test-secret', fetchImpl: async () => {
      requests++;
      return new Response('secret-bearing provider body', { status, headers: { 'retry-after': '0.025' } });
    } });
    await assert.rejects(provider.invoke({}), (error) => {
      assert.equal(error.code, code);
      assert.equal(error.retryAfterMs, 25);
      assert.ok(!error.message.includes('secret-bearing'));
      assert.ok(!error.message.includes('test-secret'));
      return true;
    });
    assert.equal(requests, 1, 'the provider adapter itself remains single-attempt');
  }

  let emptyRequests = 0;
  const empty = createProvider({ facade, apiKey: 'test-secret', fetchImpl: async () => {
    emptyRequests++;
    return new Response(JSON.stringify({ content: '', tool_calls: [] }), { headers: { 'content-type': 'application/json' } });
  } });
  await assert.rejects(empty.invoke({}), (error) => error.code === 'EMPTY_RESPONSE');
  assert.equal(emptyRequests, 1, 'the host engine owns retry scheduling');
});

test('delayed HTTP error-body cleanup preserves auth classification after the request deadline', async () => {
  const { facade } = fixture();
  let releaseCancellation;
  let cancellationStarted;
  const cancelStarted = new Promise((resolve) => { cancellationStarted = resolve; });
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('secret-bearing error body')); },
    cancel() {
      cancellationStarted();
      return new Promise((resolve) => { releaseCancellation = resolve; });
    },
  });
  const provider = createProvider({ facade, apiKey: 'test-secret', timeoutMs: 5, fetchImpl: async () => new Response(body, { status: 401 }) });
  const pending = provider.invoke({});
  await cancelStarted;
  await new Promise((resolve) => setTimeout(resolve, 20));
  releaseCancellation();
  await assert.rejects(pending, (error) => error.code === 'AUTH'
    && error.providerStatus === 401
    && !error.message.includes('test-secret')
    && !error.message.includes('secret-bearing'));
});

test('delayed oversized JSON cleanup preserves the size-limit failure after the request deadline', async () => {
  const { facade } = fixture();
  let releaseCancellation;
  let cancellationStarted;
  const cancelStarted = new Promise((resolve) => { cancellationStarted = resolve; });
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('x'.repeat(20))); },
    cancel() {
      cancellationStarted();
      return new Promise((resolve) => { releaseCancellation = resolve; });
    },
  });
  const provider = createProvider({
    facade,
    apiKey: 'test-secret',
    timeoutMs: 5,
    responseLimit: 12,
    fetchImpl: async () => new Response(body, { headers: { 'content-type': 'application/json' } }),
  });
  let invokeSettled = false;
  const pending = provider.invoke({}).finally(() => { invokeSettled = true; });
  await cancelStarted;
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(invokeSettled, false, 'provider invoke awaits response cleanup');
  releaseCancellation();
  await assert.rejects(pending, (error) => error.code !== 'TIMEOUT' && /size limit/.test(error.message));
  assert.equal(invokeSettled, true);
});

test('only recognized network errors are retryable and malformed UTF-8 is not transport', async () => {
  const { facade } = fixture();
  const refused = createProvider({ facade, apiKey: 'key', fetchImpl: async () => {
    throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('refused'), { code: 'ECONNREFUSED' }) });
  } });
  await assert.rejects(refused.invoke({}), (error) => error.code === 'TRANSPORT' && /transport failed/.test(error.message));

  const redirect = createProvider({ facade, apiKey: 'key', fetchImpl: async () => {
    throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('unexpected redirect'), { code: 'ERR_FR_REDIRECTION_FAILURE' }) });
  } });
  await assert.rejects(redirect.invoke({}), (error) => error.code === 'PROVIDER_ERROR');

  for (const reason of [
    Object.assign(new Error('bad port'), {}),
    Object.assign(new Error('invalid request configuration'), { code: 'ERR_INVALID_ARG_VALUE' }),
  ]) {
    const configFailure = createProvider({ facade, apiKey: 'key', fetchImpl: async () => {
      throw Object.assign(new TypeError('fetch failed'), { cause: reason });
    } });
    await assert.rejects(configFailure.invoke({}), (error) => error.code === 'PROVIDER_ERROR');
  }

  const wrappedNetwork = createProvider({ facade, apiKey: 'key', fetchImpl: async () => {
    const cause = Object.assign(new Error('connection reset'), { code: 'ECONNRESET' });
    throw Object.assign(new TypeError('fetch failed'), {
      code: 'ERR_WRAPPED_FETCH',
      cause: Object.assign(new Error('carrier wrapper'), { cause }),
    });
  } });
  await assert.rejects(wrappedNetwork.invoke({}), (error) => error.code === 'TRANSPORT');

  const bytes = Uint8Array.from([0x64, 0x61, 0x74, 0x61, 0x3a, 0x20, 0xff, 0x0a, 0x0a]);
  const malformed = createProvider({ facade, apiKey: 'key', fetchImpl: async () => new Response(bytes, { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(malformed.invoke({}), (error) => error.code === 'MALFORMED');
});
