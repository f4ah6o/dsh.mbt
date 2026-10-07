import { HostError, checkAbort, messageOf, parseEnvelope, unwrap } from './errors.mjs';

const RESPONSE_LIMIT = 16 * 1024 * 1024;
const MAX_RETRY_DELAY_MS = 10_000;
const RETRY_AFTER_TOO_LONG_MS = MAX_RETRY_DELAY_MS + 1;
const TRANSIENT_TRANSPORT_CODES = new Set([
  'ECONNRESET', 'ECONNREFUSED', 'ETIMEDOUT', 'EHOSTUNREACH', 'ENETUNREACH',
  'ENOTFOUND', 'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT', 'UND_ERR_SOCKET',
]);
const NON_TRANSIENT_TRANSPORT_REASONS = /redirect|invalid url|invalid argument|bad port|unsupported protocol|invalid protocol/;

function isTransportFailure(error) {
  let current = error;
  let recognizedNetworkCode = false;
  let informativeNonTransientCause = false;
  for (let depth = 0; current && depth < 4; depth++, current = current.cause) {
    if (TRANSIENT_TRANSPORT_CODES.has(current.code)) recognizedNetworkCode = true;
    else if (typeof current.code === 'string' && current.code) informativeNonTransientCause = true;
    if (NON_TRANSIENT_TRANSPORT_REASONS.test(messageOf(current).toLowerCase())) {
      informativeNonTransientCause = true;
    }
  }
  // A recognized socket/DNS code anywhere in the chain is stronger evidence
  // than a generic wrapper code or message. Otherwise, config/redirect causes
  // must not be promoted to transient failures by a root `fetch failed` text.
  if (recognizedNetworkCode) return true;
  if (informativeNonTransientCause) return false;
  const message = messageOf(error).toLowerCase();
  return error instanceof TypeError && /fetch failed|failed to fetch|network error|network request failed|terminated/.test(message);
}

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

  async function invoke(request, { signal, onDelta } = {}) {
    checkAbort(signal);
    if (demo) return demoResponse(request);
    const url = providerURL(base, mode === 'deepseek' ? '/v1/messages' : '/v1/chat/completions');
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (!apiKey && !local) throw new HostError(`${mode === 'deepseek' ? 'DEEPSEEK_API_KEY' : 'OPENAI_API_KEY'} is required (or use --demo)`, { code: 'AUTH' });
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
        // Error bodies can echo request data. Classification uses the status
        // and Retry-After header only, keeping credentials and prompt text out
        // of the durable retry event.
        clearTimeout(timer);
        await response.body?.cancel().catch(() => {});
        const status = response.status;
        const code = status === 408 || status === 504
          ? 'TIMEOUT'
          : status === 429
            ? 'RATE_LIMIT'
            : status >= 500
              ? 'SERVER'
              : status === 401 || status === 403
                ? 'AUTH'
                : 'HTTP_ERROR';
        throw new HostError(`Provider HTTP ${status}`, {
          status: 502,
          code,
          providerStatus: status,
          retryAfterMs: parseRetryAfter(response.headers.get('retry-after')),
        });
      }
      if ((response.headers.get('content-type') ?? '').toLowerCase().includes('text/event-stream')) {
        if (!response.body) throw new HostError('Provider returned an empty event stream', { status: 502, code: 'MALFORMED' });
        streamHandle = facade.stream_start(mode);
        if (!Number.isSafeInteger(streamHandle) || streamHandle <= 0) throw new HostError('Provider stream decoder capacity is exhausted', { status: 502 });
        const decoder = new TextDecoder('utf-8', { fatal: true });
        const observed = { content: '', reasoning: '' };
        const hasDeltaDrain = typeof facade.stream_take_deltas === 'function';
        const drainDeltas = async () => {
          if (!hasDeltaDrain) return;
          const deltas = unwrap(facade.stream_take_deltas(streamHandle), 'provider.stream_take_deltas');
          if (!Array.isArray(deltas)) throw new HostError('Provider returned malformed stream deltas', { status: 502 });
          let content = '';
          let reasoning = '';
          for (const delta of deltas) {
            if (!delta || typeof delta !== 'object' || typeof delta.text !== 'string') throw new HostError('Provider returned malformed stream delta', { status: 502 });
            if (delta.channel === 'content') content += delta.text;
            else if (delta.channel === 'reasoning') reasoning += delta.text;
            else throw new HostError('Provider returned an unsupported stream delta channel', { status: 502 });
          }
          observed.content += content;
          observed.reasoning += reasoning;
          if ((content || reasoning) && onDelta) await onDelta({ content, reasoning });
        };
        const feed = async (text) => {
          if (!text) return;
          const result = parseEnvelope(facade.stream_feed(streamHandle, text), 'provider.stream_feed');
          // One transport chunk may contain valid frames followed by a bad one.
          // Drain their validated deltas before surfacing the sticky parser error.
          await drainDeltas();
          if (!result.ok) throw new HostError(typeof result.error === 'string' ? result.error : JSON.stringify(result.error), { status: 502, code: 'MALFORMED' });
        };
        let bytes = 0;
        const reader = response.body.getReader();
        let reachedEof = false;
        let cancelPromise;
        const cancelRead = () => {
          if (cancelPromise) return;
          try { cancelPromise = reader.cancel(combined.reason ?? new Error('Provider stream processing stopped')).catch(() => {}); }
          catch { cancelPromise = Promise.resolve(); }
        };
        combined.addEventListener('abort', cancelRead, { once: true });
        try {
          for (;;) {
            checkAbort(combined);
            let read;
            try { read = await reader.read(); }
            catch (error) {
              if (isTransportFailure(error)) throw new HostError('Provider transport failed', { status: 502, code: 'TRANSPORT', cause: error });
              throw error;
            }
            const { done, value } = read;
            checkAbort(combined);
            if (done) { reachedEof = true; clearTimeout(timer); break; }
            bytes += value.byteLength;
            if (bytes > responseLimit) throw new HostError('Provider response exceeded its size limit', { status: 502 });
            let decoded;
            try { decoded = decoder.decode(value, { stream: true }); }
            catch (cause) { throw new HostError('Provider stream contains invalid UTF-8', { status: 502, code: 'MALFORMED', cause }); }
            await feed(decoded);
          }
          let decoded;
          try { decoded = decoder.decode(); }
          catch (cause) { throw new HostError('Provider stream contains incomplete UTF-8', { status: 502, code: 'MALFORMED', cause }); }
          await feed(decoded);
        } catch (error) {
          // Preserve the established parser/transport failure while awaiting
          // body cleanup. Caller cancellation still wins in the outer catch.
          clearTimeout(timer);
          throw error;
        } finally {
          combined.removeEventListener('abort', cancelRead);
          // A parser error, size-limit failure or rejected projection callback
          // can happen while the producer still has bytes to send. Stop that
          // body before releasing the reader so failed effects do not leave an
          // unread response consuming a connection in the background.
          if (!reachedEof) {
            cancelRead();
          }
          // Await the underlying source's cleanup before invoke settles. Host
          // shutdown and facade ownership must not race a still-live response.
          if (cancelPromise) await cancelPromise;
          try { reader.releaseLock(); } catch { /* A cancelled stream may still be settling. */ }
        }
        const result = unwrap(facade.stream_finish(streamHandle), 'provider.stream_finish');
        if (hasDeltaDrain) {
          const finalContent = result?.content;
          const finalReasoning = result?.reasoning ?? '';
          if (typeof finalContent !== 'string' || typeof finalReasoning !== 'string'
            || observed.content !== finalContent || observed.reasoning !== finalReasoning) {
            throw new HostError('Provider final response differs from its live text/reasoning projection', { status: 502 });
          }
        }
        if (!result.content && !(result.tool_calls?.length > 0)) {
          throw new HostError('Provider returned an empty response', { status: 502, code: 'EMPTY_RESPONSE' });
        }
        return result;
      }
      let body;
      try { body = await boundedResponseText(response, responseLimit, false, () => clearTimeout(timer)); }
      catch (error) {
        clearTimeout(timer);
        if (isTransportFailure(error)) throw new HostError('Provider transport failed', { status: 502, code: 'TRANSPORT', cause: error });
        throw error;
      }
      clearTimeout(timer);
      const result = unwrap(facade.decode_response(mode, body), 'provider.decode_response');
      if (!result.content && !(result.tool_calls?.length > 0)) {
        throw new HostError('Provider returned an empty response', { status: 502, code: 'EMPTY_RESPONSE' });
      }
      return result;
    } catch (error) {
      if (signal?.aborted) throw new HostError('Provider request cancelled', { status: 499, code: 'CANCELLED' });
      if (timeoutController.signal.aborted) throw new HostError('Provider request timed out', { status: 502, code: 'TIMEOUT' });
      if (error instanceof HostError) {
        throw new HostError(redact(messageOf(error)), {
          status: error.status ?? 502,
          code: error.code,
          providerStatus: error.providerStatus,
          retryAfterMs: error.retryAfterMs,
        });
      }
      // Only recognized network failures are retryable. Malformed facade,
      // redirect, decoder, and configuration errors fail closed.
      if (isTransportFailure(error)) {
        throw new HostError('Provider transport failed', { status: 502, code: 'TRANSPORT' });
      }
      throw new HostError('Provider request failed', { status: error.status ?? 502, code: 'PROVIDER_ERROR' });
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

function parseRetryAfter(value) {
  if (typeof value !== 'string' || !value.trim()) return undefined;
  const trimmed = value.trim();
  let delay;
  if (/^\d+(?:\.\d+)?$/.test(trimmed)) {
    const seconds = Number(trimmed);
    if (!Number.isFinite(seconds) || seconds > MAX_RETRY_DELAY_MS / 1000) {
      return RETRY_AFTER_TOO_LONG_MS;
    }
    delay = Math.ceil(seconds * 1000);
  }
  else {
    const timestamp = Date.parse(trimmed);
    if (Number.isFinite(timestamp)) delay = Math.max(0, timestamp - Date.now());
  }
  if (Number.isFinite(delay) && delay > MAX_RETRY_DELAY_MS) return RETRY_AFTER_TOO_LONG_MS;
  return Number.isSafeInteger(delay) && delay > 0 ? delay : undefined;
}

async function boundedResponseText(response, limit, truncate = false, beforeCleanup = () => {}) {
  if (!response.body) return '';
  const chunks = [];
  let bytes = 0;
  const reader = response.body.getReader();
  let reachedEof = false;
  let cancelPromise;
  const cancelRead = (reason) => {
    if (cancelPromise) return cancelPromise;
    try { cancelPromise = reader.cancel(reason).catch(() => {}); }
    catch { cancelPromise = Promise.resolve(); }
    return cancelPromise;
  };
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) {
        reachedEof = true;
        break;
      }
      if (bytes + value.byteLength > limit) {
        if (!truncate) {
          const error = new HostError('Provider response exceeded its size limit', { status: 502 });
          // Once the bounded parser has established this protocol failure, its
          // request deadline must not replace it while the source cleans up.
          beforeCleanup();
          await cancelRead(error);
          throw error;
        }
        chunks.push(value.subarray(0, limit - bytes));
        bytes = limit;
        beforeCleanup();
        await cancelRead(new Error('Provider response was truncated'));
        break;
      }
      chunks.push(value);
      bytes += value.byteLength;
    }
    return Buffer.concat(chunks, bytes).toString('utf8');
  } catch (error) {
    beforeCleanup();
    if (!reachedEof) await cancelRead(error);
    throw error;
  } finally {
    if (cancelPromise) await cancelPromise;
    try { reader.releaseLock(); } catch { /* A cancelled body may still be settling. */ }
  }
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
