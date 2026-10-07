import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { EventEmitter } from 'node:events';
import { createWorkspaceTools } from './tools.mjs';
import { createProvider } from './provider.mjs';
import { openPersistence } from './persistence.mjs';
import { HostError, messageOf, parseEnvelope, unwrap } from './errors.mjs';

export const defaultModulePath = fileURLToPath(new URL('../_build/js/release/build/f4ah6o/dsh/app/app.js', import.meta.url));
const ownedFacades = new WeakSet();
const READ_OPERATIONS = new Set(['session_get', 'session_list', 'plugin_list', 'profile_stats']);
const MAX_STREAM_UNITS = 16 * 1024 * 1024;

export async function loadFacade(modulePath = defaultModulePath) {
  try {
    return await import(pathToFileURL(path.resolve(modulePath)).href);
  } catch (cause) {
    throw new HostError(`Cannot load the MoonBit runtime at ${modulePath}. Build it first with npm run build.`, { status: 500, cause });
  }
}

/** Serialize MoonBit state transitions and durable checkpoints, then perform IO. */
export async function createHost(options = {}) {
  const facade = options.facade ?? await loadFacade(options.modulePath);
  if (ownedFacades.has(facade)) throw new HostError('This MoonBit runtime is already owned by a host', { status: 409 });
  // Reserve before the first asynchronous setup step. The generated facade has
  // module-global state even when callers choose separate persistence paths.
  ownedFacades.add(facade);
  try { return await initializeHost({ ...options, facade }); } catch (error) {
    ownedFacades.delete(facade);
    throw error;
  }
}

async function initializeHost(options) {
  const facade = options.facade;
  const provider = createProvider({ ...options, facade, baseURL: options.baseURL });
  const workspace = path.resolve(options.workspace ?? process.cwd());
  const persistence = await openPersistence(options.dataDir ?? path.join(workspace, '.dsh.mbt'));
  const changed = new EventEmitter();
  changed.setMaxListeners(64);
  const active = new Map();
  const approvals = new Set(options.approveTools ?? []);
  for (const name of approvals) {
    if (!['write', 'edit', 'bash'].includes(name)) {
      await persistence.close();
      throw new HostError(`Cannot auto-approve unknown or non-mutating tool: ${name}`);
    }
  }
  if (approvals.has('bash') && !options.allowShell) {
    await persistence.close();
    throw new HostError('--approve-tools bash also requires --allow-shell');
  }
  const shellEnv = { ...(options.shellEnv ?? process.env) };
  for (const name of ['DEEPSEEK_API_KEY', 'OPENAI_API_KEY', 'DSH_API_KEY']) delete shellEnv[name];
  if (options.apiKey) for (const [name, value] of Object.entries(shellEnv)) if (value === options.apiKey) delete shellEnv[name];
  let workspaceTools;
  let serial = Promise.resolve();
  let fatalError;
  let closing = false;
  let closePromise;

  function report(error) {
    const safe = new HostError(provider.redact(messageOf(error)), { status: error.status ?? 500 });
    try { options.onError?.(safe); } catch { /* Diagnostics cannot break state. */ }
    return safe;
  }

  function serialize(action, { internal = false } = {}) {
    const next = serial.then(async () => {
      if (fatalError) throw fatalError;
      if (closing && !internal) throw new HostError('Host is closing', { status: 503 });
      return action();
    });
    serial = next.catch(() => {});
    return next;
  }

  function snapshot() {
    const state = JSON.parse(facade.snapshot());
    if (!state || !Array.isArray(state.sessions)) throw new HostError('MoonBit returned an invalid snapshot', { status: 500 });
    return state;
  }

  async function checkpoint() {
    try { await persistence.save(facade.snapshot()); } catch (error) {
      fatalError = report(error);
      for (const entry of active.values()) entry.controller.abort(new Error('Persistence failed; stopping IO'));
      changed.emit('change');
      throw fatalError;
    }
  }

  function drainEffects() {
    const effects = JSON.parse(facade.take_effects());
    if (!Array.isArray(effects) || effects.some((effect) => !effect || typeof effect.id !== 'string' || typeof effect.session_id !== 'string' || !['llm', 'tool'].includes(effect.kind))) {
      throw new HostError('MoonBit returned invalid effects', { status: 500 });
    }
    return effects;
  }

  function clearStreamTimer(entry) {
    if (entry.streamTimer) clearTimeout(entry.streamTimer);
    entry.streamTimer = undefined;
  }

  function takeStreamBatch(entry) {
    clearStreamTimer(entry);
    const content = [];
    const reasoning = [];
    let units = 0;
    while (entry.pendingStreamHead < entry.pendingStream.length && units < 4096) {
      const segment = entry.pendingStream[entry.pendingStreamHead];
      const points = [];
      let offset = 0;
      for (const point of segment.text) {
        if (units + point.length > 4096) break;
        points.push(point);
        offset += point.length;
        units += point.length;
      }
      if (points.length === 0) break;
      const prefix = points.join('');
      if (segment.channel === 'content') content.push(prefix);
      else reasoning.push(prefix);
      if (offset < segment.text.length) {
        segment.text = segment.text.slice(offset);
        break;
      }
      entry.pendingStreamHead++;
    }
    entry.pendingStreamUnits -= units;
    if (entry.pendingStreamHead === entry.pendingStream.length) {
      entry.pendingStream = [];
      entry.pendingStreamHead = 0;
    } else if (entry.pendingStreamHead >= 128 && entry.pendingStreamHead * 2 >= entry.pendingStream.length) {
      entry.pendingStream.splice(0, entry.pendingStreamHead);
      entry.pendingStreamHead = 0;
    }
    return { content: content.join(''), reasoning: reasoning.join('') };
  }

  async function applyStreamBatch(entry, batch) {
    if (!batch.content && !batch.reasoning) return;
    const response = parseEnvelope(
      facade.stream_project(entry.effect.id, batch.content, batch.reasoning),
      'stream_project',
    );
    if (!response.ok) {
      throw new HostError(typeof response.error === 'string' ? response.error : JSON.stringify(response.error), { status: 409 });
    }
    await checkpoint();
    changed.emit('change');
  }

  async function flushStreamInline(entry) {
    if (entry.applyPromise) {
      await entry.applyPromise;
      if (entry.pendingStreamUnits > 0) return flushStreamInline(entry);
      return;
    }
    const batch = takeStreamBatch(entry);
    if (!batch.content && !batch.reasoning) return;
    const applying = applyStreamBatch(entry, batch);
    entry.applyPromise = applying;
    try { await applying; } finally {
      if (entry.applyPromise === applying) entry.applyPromise = undefined;
    }
  }

  async function flushBeforeCancellation(sessionID) {
    const streaming = [...active.values()].filter((entry) => entry.effect.session_id === sessionID);
    for (const entry of streaming) {
      entry.cancelPending = true;
      clearStreamTimer(entry);
      try {
        // Provider callbacks only enqueue bounded segments; all checkpointing
        // stays inside this serialized owner. Wait for both current IO and any
        // callback that is still splitting a large validated delta.
        for (;;) {
          if (entry.applyPromise) {
            await entry.applyPromise;
            continue;
          }
          if (entry.pendingStreamUnits > 0) {
            await flushStreamInline(entry);
            continue;
          }
          if (entry.deltaTasks.size > 0) {
            await Promise.all([...entry.deltaTasks]);
            continue;
          }
          // No async gap follows this check before cancellation dispatch.
          entry.streamCutoff = true;
          break;
        }
      } catch (error) {
        // Capacity refusal ends this provider effect through the normal engine
        // cancellation path. Earlier committed batches remain durable.
        entry.streamCutoff = true;
        await Promise.allSettled([
          ...entry.deltaTasks,
          ...(entry.applyPromise ? [entry.applyPromise] : []),
        ]);
        entry.pendingStream = [];
        entry.pendingStreamHead = 0;
        entry.pendingStreamUnits = 0;
        entry.streamError = report(error);
      }
    }
    return streaming;
  }

  function resumeAfterRejectedCancellation(entries) {
    for (const entry of entries) {
      if (!entry.cancelledByEngine && !entry.streamError) {
        entry.streamCutoff = false;
        entry.cancelPending = false;
        if (entry.pendingStreamUnits > 0) scheduleStreamFlush(entry);
      }
    }
  }

  function mcpCallSucceeded(response) {
    try {
      const parsed = JSON.parse(response);
      return !parsed?.error && parsed?.result?.isError !== true;
    } catch { return false; }
  }

  function mcpCancellation(line) {
    try {
      const request = JSON.parse(line);
      const params = request?.params;
      const name = params?.name;
      const args = params?.arguments;
      if (request?.method === 'tools/call'
        && (name === 'session_cancel' || name === 'dsh.session_cancel')
        && typeof args?.session_id === 'string') return args.session_id;
    } catch { /* The MoonBit MCP server returns the protocol error. */ }
    return undefined;
  }

  function requestStreamFlush(entry) {
    clearStreamTimer(entry);
    if (entry.flushPromise) {
      return entry.flushPromise.then(() => {
        if (entry.pendingStreamUnits > 0 && !entry.cancelPending && !entry.cancelledByEngine) return requestStreamFlush(entry);
      });
    }
    if (entry.pendingStreamUnits === 0) return Promise.resolve();
    // Keep bytes attached to the effect until this action owns the serial
    // queue. A cancellation ahead of it can flush them inline before retiring
    // the effect, after which this queued action becomes a no-op.
    const pending = serialize(() => flushStreamInline(entry), { internal: true });
    const wrapped = pending.finally(() => {
      if (entry.flushPromise === wrapped) entry.flushPromise = undefined;
      if (entry.pendingStreamUnits > 0 && !entry.streamError && !entry.cancelPending && !entry.cancelledByEngine && !closing) scheduleStreamFlush(entry);
    });
    entry.flushPromise = wrapped;
    return wrapped.then(() => {
      if (entry.pendingStreamUnits > 0 && !entry.cancelPending && !entry.cancelledByEngine) return requestStreamFlush(entry);
    });
  }

  function scheduleStreamFlush(entry) {
    if (entry.streamTimer || entry.streamError || entry.cancelPending || entry.cancelledByEngine || closing) return;
    entry.streamTimer = setTimeout(() => {
      entry.streamTimer = undefined;
      requestStreamFlush(entry).catch((error) => {
        entry.streamError = report(error);
        entry.controller.abort(entry.streamError);
        changed.emit('change');
      });
    }, 100);
  }

  function queueStreamBatch(entry, content, reasoning) {
    if (entry.streamCutoff || entry.cancelledByEngine || closing) return;
    const units = content.length + reasoning.length;
    if (units === 0) return;
    if (content) entry.pendingStream.push({ channel: 'content', text: content });
    if (reasoning) entry.pendingStream.push({ channel: 'reasoning', text: reasoning });
    entry.pendingStreamUnits += units;
    if (entry.cancelPending) return;
    if (entry.pendingStreamUnits >= 512 && !entry.flushPromise) {
      requestStreamFlush(entry).catch((error) => {
        entry.streamError = report(error);
        entry.controller.abort(entry.streamError);
        changed.emit('change');
      });
    } else scheduleStreamFlush(entry);
  }

  async function queueStreamText(entry, channel, text) {
    if (!text) return;
    // Bound each durable event in UTF-16 units, matching the MoonBit session
    // capacity checks, without ever splitting a Unicode scalar value.
    let points = [];
    let units = 0;
    let chunks = 0;
    for (const point of text) {
      if (units + point.length > 4096) {
        const part = points.join('');
        queueStreamBatch(entry, channel === 'content' ? part : '', channel === 'reasoning' ? part : '');
        if (entry.streamError || entry.streamCutoff || entry.cancelledByEngine || closing) return;
        points = [];
        units = 0;
        chunks++;
        if (chunks % 16 === 0) await Promise.resolve();
      }
      points.push(point);
      units += point.length;
      if (units === 4096) {
        const part = points.join('');
        queueStreamBatch(entry, channel === 'content' ? part : '', channel === 'reasoning' ? part : '');
        if (entry.streamError || entry.streamCutoff || entry.cancelledByEngine || closing) return;
        points = [];
        units = 0;
        chunks++;
        if (chunks % 16 === 0) await Promise.resolve();
      }
    }
    if (points.length) {
      const part = points.join('');
      queueStreamBatch(entry, channel === 'content' ? part : '', channel === 'reasoning' ? part : '');
    }
  }

  async function queueStreamDeltas(entry, delta) {
    if (entry.streamError) throw entry.streamError;
    if (entry.streamCutoff || entry.cancelledByEngine || closing) return;
    if (!delta || typeof delta.content !== 'string' || typeof delta.reasoning !== 'string') {
      throw new HostError('Provider returned malformed projected text', { status: 502 });
    }
    const units = delta.content.length + delta.reasoning.length;
    if (units > MAX_STREAM_UNITS - entry.projectedStreamUnits) {
      entry.streamError = report(new HostError('Provider stream exceeds the 16 Mi unit limit', { status: 502 }));
      entry.controller.abort(entry.streamError);
      throw entry.streamError;
    }
    entry.projectedStreamUnits += units;
    await queueStreamText(entry, 'content', delta.content);
    await queueStreamText(entry, 'reasoning', delta.reasoning);
  }

  function trackStreamDeltas(entry, delta) {
    if (entry.streamError || entry.streamCutoff || entry.cancelledByEngine || closing) return Promise.resolve();
    // Register before allowing the asynchronous projection work to run.
    // Cancellation preflight also waits for this set, so no callback-owned
    // checkpoint can outlive the serialized cancellation action.
    const task = Promise.resolve().then(() => queueStreamDeltas(entry, delta));
    entry.deltaTasks.add(task);
    task.then(
      () => entry.deltaTasks.delete(task),
      () => entry.deltaTasks.delete(task),
    );
    return task;
  }

  async function transition() {
    const effects = drainEffects();
    // These approvals reflect an explicit startup policy. Browser approvals
    // still enter the same MoonBit operation, one call at a time.
    for (let round = 0; round < 32; round++) {
      const pending = snapshot().sessions.filter((session) => session.status === 'awaiting_approval' && approvals.has(session.pending_approval?.name));
      if (!pending.length) break;
      for (const session of pending) {
        unwrap(facade.dispatch(JSON.stringify({ operation: 'tool_approve', input: { session_id: session.id, call_id: session.pending_approval.call_id, approved: true } })), 'tool_approve');
        effects.push(...drainEffects());
      }
    }
    // Persist both the request event and its approval before touching the OS.
    await checkpoint();
    const states = new Map(snapshot().sessions.map((session) => [session.id, session.status]));
    for (const entry of active.values()) if (states.get(entry.effect.session_id) !== 'running') {
      entry.cancelledByEngine = true;
      entry.cancelPending = true;
      clearStreamTimer(entry);
      entry.controller.abort(new Error('Session is no longer running'));
    }
    // close() can begin while the durable write above is awaiting IO. Do not
    // create a fresh controller that would miss shutdown's initial abort.
    if (closing) { changed.emit('change'); return; }
    for (const effect of effects) {
      if (states.get(effect.session_id) !== 'running') continue;
      if (active.has(effect.id)) throw new HostError('MoonBit emitted a duplicate effect ID', { status: 500 });
      const entry = {
        effect,
        controller: new AbortController(),
        promise: undefined,
        pendingStream: [],
        pendingStreamHead: 0,
        pendingStreamUnits: 0,
        projectedStreamUnits: 0,
        streamTimer: undefined,
        flushPromise: undefined,
        applyPromise: undefined,
        deltaTasks: new Set(),
        streamError: undefined,
        cancelPending: false,
        streamCutoff: false,
        cancelledByEngine: false,
      };
      active.set(effect.id, entry);
      entry.promise = Promise.resolve().then(() => perform(entry)).catch((error) => {
        fatalError ??= report(error);
        for (const current of active.values()) current.controller.abort(new Error('Host effect settlement failed'));
        changed.emit('change');
      }).finally(() => {
        active.delete(effect.id);
        changed.emit('change');
      });
    }
    changed.emit('change');
  }

  async function perform(entry) {
    const { effect, controller } = entry;
    let result;
    try {
      result = effect.kind === 'llm'
        ? await provider.invoke(effect.request, {
          signal: controller.signal,
          onDelta: (delta) => trackStreamDeltas(entry, delta),
        })
        : await workspaceTools.execute(effect.request, { signal: controller.signal });
    } catch (error) {
      result = { ok: false, error: provider.redact(messageOf(entry.streamError ?? error)) };
    }
    try { await requestStreamFlush(entry); } catch (error) {
      result = { ok: false, error: provider.redact(messageOf(entry.streamError ?? error)) };
    }
    if ((entry.cancelledByEngine && controller.signal.aborted) || closing || fatalError) return;
    await serialize(async () => {
      if ((entry.cancelledByEngine && controller.signal.aborted) || closing) return;
      // Engine rejects stale/duplicate completions; only one serialized owner
      // is allowed to settle an effect and emit its next request.
      const response = parseEnvelope(facade.complete(effect.id, JSON.stringify(result)), 'complete');
      if (!response.ok) {
        const error = typeof response.error === 'string' ? response.error : JSON.stringify(response.error);
        // A malformed provider result still terminates the outstanding effect
        // through the engine's normal error path instead of leaving it running.
        unwrap(facade.complete(effect.id, JSON.stringify({ ok: false, error: `Invalid host completion: ${error}` })), 'complete');
      }
      await transition();
    }, { internal: true });
  }

  try {
    workspaceTools = await createWorkspaceTools({ workspace, allowShell: options.allowShell, shellEnv, protectedPaths: [persistence.directory] });
    unwrap(facade.start(), 'start');
    const previous = await persistence.load();
    if (previous !== undefined) unwrap(facade.restore(previous), 'restore');
    const unexpected = drainEffects();
    if (unexpected.length) throw new HostError('Restore unexpectedly emitted IO; refusing to replay interrupted work', { status: 500 });
    await checkpoint();
  } catch (error) {
    ownedFacades.delete(facade);
    try { facade.stop?.(); } catch { /* Preserve original failure. */ }
    await persistence.close();
    throw error;
  }

  async function call(operation, input = {}) {
    return serialize(async () => {
      let cancellationEntries = [];
      if (operation === 'session_cancel' && typeof input.session_id === 'string') {
        cancellationEntries = await flushBeforeCancellation(input.session_id);
        if (closing) {
          resumeAfterRejectedCancellation(cancellationEntries);
          throw new HostError('Host is closing', { status: 503 });
        }
      }
      const response = parseEnvelope(facade.dispatch(JSON.stringify({ operation, input })), 'dispatch');
      if (operation === 'session_cancel' && !response.ok) resumeAfterRejectedCancellation(cancellationEntries);
      if (operation === 'session_cancel' && response.ok) {
        for (const entry of active.values()) if (entry.effect.session_id === input.session_id) {
          entry.cancelledByEngine = true;
          entry.cancelPending = true;
          clearStreamTimer(entry);
          entry.controller.abort(new Error('Session was cancelled'));
        }
      }
      if (response.ok && !READ_OPERATIONS.has(operation)) await transition();
      return response;
    });
  }

  async function mcp(line) {
    return serialize(async () => {
      const cancelID = mcpCancellation(line);
      const cancellationEntries = cancelID ? await flushBeforeCancellation(cancelID) : [];
      if (cancelID && closing) {
        resumeAfterRejectedCancellation(cancellationEntries);
        throw new HostError('Host is closing', { status: 503 });
      }
      const response = facade.mcp_handle(line);
      if (typeof response !== 'string') throw new HostError('MoonBit returned an invalid MCP response', { status: 500 });
      if (cancelID) {
        if (mcpCallSucceeded(response)) for (const entry of cancellationEntries) {
          entry.cancelledByEngine = true;
          entry.cancelPending = true;
          clearStreamTimer(entry);
          entry.controller.abort(new Error('Session was cancelled'));
        } else resumeAfterRejectedCancellation(cancellationEntries);
      }
      await transition();
      return response;
    });
  }

  async function state() { return serialize(() => snapshot()); }

  async function session(id) {
    const state = await serialize(() => snapshot());
    const result = state.sessions.find((item) => item.id === id);
    if (!result) throw new HostError(`Session not found: ${id}`, { status: 404 });
    return result;
  }

  async function waitForSession(id, { signal } = {}) {
    for (;;) {
      if (signal?.aborted) throw signal.reason;
      let wake;
      const next = new Promise((resolve) => { wake = resolve; });
      changed.once('change', wake);
      signal?.addEventListener('abort', wake, { once: true });
      try {
        const current = await session(id);
        if (current.status !== 'running') return current;
        await next;
      } finally {
        changed.removeListener('change', wake);
        signal?.removeEventListener('abort', wake);
      }
    }
  }

  function close() {
    if (closePromise) return closePromise;
    closing = true;
    closePromise = (async () => {
      try {
        // Stop new deltas, but let each active provider flush its already
        // accepted batch before recording cancellation. Never leave a running
        // provider/read after the facade and its single-writer lock are closed.
        const stopping = [...active.values()];
        for (const entry of stopping) {
          entry.cancelPending = true;
          clearStreamTimer(entry);
          entry.controller.abort(new Error('Host shutdown'));
        }
        await Promise.allSettled(stopping.map((entry) => entry.promise));
        await serial;
        if (!fatalError) {
          for (const current of snapshot().sessions) {
            if (['running', 'awaiting_approval'].includes(current.status)) {
              unwrap(facade.dispatch(JSON.stringify({ operation: 'session_cancel', input: { session_id: current.id } })), 'session_cancel');
            }
          }
          drainEffects();
          await checkpoint();
        }
      } finally {
        // Even a failed final checkpoint must not release ownership while an
        // aborted child process or fetch is still cleaning up.
        for (const entry of active.values()) entry.controller.abort(new Error('Host shutdown'));
        await Promise.allSettled([...active.values()].map((entry) => entry.promise));
        try { facade.stop?.(); } finally {
          ownedFacades.delete(facade);
          await persistence.close();
          changed.emit('change');
          changed.removeAllListeners();
        }
      }
    })();
    return closePromise;
  }

  return { call, mcp, state, session, waitForSession, close, workspace: workspaceTools.workspace, dataDir: persistence.directory, backend: { mode: provider.mode, model: provider.model }, get activeCount() { return active.size; }, get status() { return fatalError ? 'failed' : closing ? 'closing' : 'running'; } };
}
