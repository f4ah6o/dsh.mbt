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
    for (const entry of active.values()) if (states.get(entry.effect.session_id) !== 'running') entry.controller.abort(new Error('Session is no longer running'));
    // close() can begin while the durable write above is awaiting IO. Do not
    // create a fresh controller that would miss shutdown's initial abort.
    if (closing) { changed.emit('change'); return; }
    for (const effect of effects) {
      if (states.get(effect.session_id) !== 'running') continue;
      if (active.has(effect.id)) throw new HostError('MoonBit emitted a duplicate effect ID', { status: 500 });
      const entry = { effect, controller: new AbortController(), promise: undefined };
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
        ? await provider.invoke(effect.request, { signal: controller.signal })
        : await workspaceTools.execute(effect.request, { signal: controller.signal });
    } catch (error) {
      result = { ok: false, error: provider.redact(messageOf(error)) };
    }
    if (controller.signal.aborted || closing || fatalError) return;
    await serialize(async () => {
      if (controller.signal.aborted || closing) return;
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
      const response = parseEnvelope(facade.dispatch(JSON.stringify({ operation, input })), 'dispatch');
      if (response.ok && !READ_OPERATIONS.has(operation)) await transition();
      return response;
    });
  }

  async function mcp(line) {
    return serialize(async () => {
      const response = facade.mcp_handle(line);
      if (typeof response !== 'string') throw new HostError('MoonBit returned an invalid MCP response', { status: 500 });
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
        // Abort IO promptly, then record cancellation through MoonBit. Await
        // every child/fetch before releasing this host's single-writer lock.
        for (const entry of active.values()) entry.controller.abort(new Error('Host shutdown'));
        await serial;
        for (const entry of active.values()) entry.controller.abort(new Error('Host shutdown'));
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
