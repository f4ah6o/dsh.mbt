import { HostError, checkAbort, messageOf, unwrap } from './errors.mjs';

const RESPONSE_LIMIT = 16 * 1024 * 1024;

export function providerURL(baseURL, providerPath) {
  const base = new URL(baseURL);
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search || base.hash) throw new HostError('Provider base URL must be an HTTP(S) URL without credentials, query, or fragment');
  if (typeof providerPath !== 'string' || !providerPath.startsWith('/v1/')) throw new HostError('Provider returned an unexpected API path', { status: 500 });
  let prefix = base.pathname.replace(/\/+$/, '');
  if (prefix.endsWith('/v1')) prefix = prefix.slice(0, -3);
  base.pathname = `${prefix}${providerPath}`;
  return base;
}

export function createProvider({ facade, mode = 'deepseek', model, baseURL, apiKey, fetchImpl = globalThis.fetch, timeoutMs = 120_000, responseLimit = RESPONSE_LIMIT, demo = false } = {}) {
  if (!['deepseek', 'openai'].includes(mode)) throw new HostError('mode must be deepseek or openai');
  if (mode === 'openai' && !demo && !model) throw new HostError('OpenAI-compatible mode requires an explicit model: set --model NAME or DSH_MODEL');
  model ??= mode === 'deepseek' ? 'deepseek-flash' : 'offline-demo';
  if (typeof model !== 'string' || !model.trim()) throw new HostError('model must be a nonempty string');
  const base = baseURL ?? (mode === 'deepseek' ? 'https://api.deepseek.com/anthropic' : 'https://api.openai.com');
  const redact = (message) => apiKey ? message.split(apiKey).join('[redacted]') : message;

  async function invoke(request, { signal } = {}) {
    checkAbort(signal);
    if (demo) return demoResponse(request);
    const url = providerURL(base, mode === 'deepseek' ? '/v1/messages' : '/v1/chat/completions');
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (!apiKey && !local) throw new HostError(`${mode === 'deepseek' ? 'DEEPSEEK_API_KEY' : 'OPENAI_API_KEY'} is required (or use --demo)`);
    const prepared = unwrap(facade.prepare_request(mode, model, JSON.stringify(request)), 'provider.prepare_request');
    if (!prepared || typeof prepared.body !== 'object' || !prepared.body) throw new HostError('Provider returned an invalid request', { status: 500 });
    const endpoint = providerURL(base, prepared.path);
    const headers = new Headers(prepared.headers ?? {});
    if (apiKey) headers.set(mode === 'deepseek' ? 'x-api-key' : 'authorization', mode === 'deepseek' ? apiKey : `Bearer ${apiKey}`);
    const timeoutController = new AbortController();
    const timer = setTimeout(() => timeoutController.abort(new Error(`Provider request timed out after ${timeoutMs} ms`)), timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timeoutController.signal]) : timeoutController.signal;
    let streamHandle;
    try {
      const response = await fetchImpl(endpoint, { method: 'POST', headers, body: JSON.stringify(prepared.body), signal: combined, redirect: 'error' });
      if (!response.ok) {
        const errorBody = await boundedResponseText(response, Math.min(responseLimit, 4096), true);
        throw new HostError(`Provider HTTP ${response.status}: ${redact(errorBody)}`, { status: 502 });
      }
      if ((response.headers.get('content-type') ?? '').toLowerCase().includes('text/event-stream')) {
        if (!response.body) throw new HostError('Provider returned an empty event stream', { status: 502 });
        streamHandle = facade.stream_start(mode);
        const decoder = new TextDecoder();
        let bytes = 0;
        for await (const chunk of response.body) {
          checkAbort(combined);
          bytes += chunk.byteLength;
          if (bytes > responseLimit) throw new HostError('Provider response exceeded its size limit', { status: 502 });
          unwrap(facade.stream_feed(streamHandle, decoder.decode(chunk, { stream: true })), 'provider.stream_feed');
        }
        const tail = decoder.decode();
        if (tail) unwrap(facade.stream_feed(streamHandle, tail), 'provider.stream_feed');
        const result = unwrap(facade.stream_finish(streamHandle), 'provider.stream_finish');
        return result;
      }
      const body = await boundedResponseText(response, responseLimit);
      return unwrap(facade.decode_response(mode, body), 'provider.decode_response');
    } catch (error) {
      if (combined.aborted) throw new HostError(redact(messageOf(combined.reason)), { status: 499 });
      throw new HostError(redact(messageOf(error)), { status: error.status ?? 502 });
    } finally {
      clearTimeout(timer);
      if (streamHandle !== undefined) {
        // Abort is idempotent after finish and also releases failed streams.
        try { facade.stream_abort(streamHandle); } catch { /* Keep original failure. */ }
      }
    }
  }

  return { invoke, mode: demo ? 'demo' : mode, model, redact };
}

async function boundedResponseText(response, limit, truncate = false) {
  if (!response.body) return '';
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body) {
    if (bytes + chunk.byteLength > limit) {
      if (!truncate) throw new HostError('Provider response exceeded its size limit', { status: 502 });
      chunks.push(chunk.subarray(0, limit - bytes));
      bytes = limit;
      break;
    }
    chunks.push(chunk);
    bytes += chunk.byteLength;
  }
  return Buffer.concat(chunks, bytes).toString('utf8');
}

/** A disclosed offline fixture. It goes through the real engine/tool boundary. */
export function demoResponse(request) {
  const messages = Array.isArray(request?.messages) ? request.messages : [];
  let lastUser = -1;
  for (let index = 0; index < messages.length; index++) if (messages[index].role === 'user') lastUser = index;
  const recent = messages.slice(lastUser + 1);
  const result = recent.find((message) => message.role === 'tool');
  if (!result) {
    return { ok: true, content: '', tool_calls: [{ id: `demo-glob-${messages.length}`, name: 'glob', arguments: JSON.stringify({ pattern: '*' }) }], finish_reason: 'tool_calls' };
  }
  const content = typeof result.content === 'string' ? result.content : JSON.stringify(result.content);
  return { ok: true, content: `Offline demo: I ran the glob tool in this workspace.\n\n${content || '(No files matched.)'}\n\nThis is a deterministic fixture; no model service was contacted.`, tool_calls: [], finish_reason: 'stop' };
}
