import test from 'node:test';
import assert from 'node:assert/strict';
import { createProvider, providerURL } from '../../host/provider.mjs';

const envelope = (result) => JSON.stringify({ ok: true, result });
function fixture() {
  const fed = [];
  const aborted = [];
  const facade = {
    prepare_request(mode, model, raw) { return envelope({ path: mode === 'deepseek' ? '/v1/messages' : '/v1/chat/completions', headers: { 'content-type': 'application/json', 'anthropic-version': '2023-06-01' }, body: { model, ...JSON.parse(raw) } }); },
    decode_response(_mode, raw) { return envelope({ ok: true, content: JSON.parse(raw).content, tool_calls: [] }); },
    stream_start() { return 7; },
    stream_feed(handle, chunk) { assert.equal(handle, 7); fed.push(chunk); return envelope(true); },
    stream_finish(handle) { assert.equal(handle, 7); return envelope({ ok: true, content: 'streamed', tool_calls: [] }); },
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
  const { facade, fed, aborted } = fixture();
  const raw = 'data: {"content":"こんにちは"}\r\n\r\n';
  const bytes = new TextEncoder().encode(raw);
  const provider = createProvider({ facade, apiKey: 'key', fetchImpl: async () => new Response(new ReadableStream({ start(controller) {
    for (let offset = 0; offset < bytes.length; offset += 2) controller.enqueue(bytes.subarray(offset, offset + 2));
    controller.close();
  } }), { headers: { 'content-type': 'text/event-stream' } }) });
  assert.equal((await provider.invoke({})).content, 'streamed');
  assert.equal(fed.join(''), raw);
  assert.deepEqual(aborted, [7]);
});

test('malformed or oversized streams release handles and surface a bounded failure', async () => {
  const { facade, aborted } = fixture();
  facade.stream_feed = () => JSON.stringify({ ok: false, error: 'malformed SSE' });
  const provider = createProvider({ facade, apiKey: 'key', fetchImpl: async () => new Response('data: bad\n\n', { headers: { 'content-type': 'text/event-stream' } }) });
  await assert.rejects(provider.invoke({}), /malformed SSE/);
  assert.deepEqual(aborted, [7]);
  const oversized = createProvider({ facade: fixture().facade, apiKey: 'key', responseLimit: 12, fetchImpl: async () => new Response('x'.repeat(100), { headers: { 'content-type': 'application/json' } }) });
  await assert.rejects(oversized.invoke({}), /size limit/);
});

test('timeouts abort fetch and HTTP errors redact the configured secret', async () => {
  const { facade } = fixture();
  let signal;
  const timeout = createProvider({ facade, apiKey: 'test-secret', timeoutMs: 15, fetchImpl: async (_url, init) => {
    signal = init.signal;
    return new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true }));
  } });
  await assert.rejects(timeout.invoke({}), /timed out/);
  assert.equal(signal.aborted, true);
  const denied = createProvider({ facade, apiKey: 'test-secret', fetchImpl: async () => new Response('Bad key test-secret', { status: 401 }) });
  await assert.rejects(denied.invoke({}), (error) => /HTTP 401/.test(error.message) && error.message.includes('[redacted]') && !error.message.includes('test-secret'));
});
