import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createHost, loadFacade } from '../../host/runtime.mjs';

async function temporary(t) {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-runtime-'));
  const hosts = [];
  t.after(async () => {
    for (const host of hosts) await host.close();
    await fs.rm(workspace, { recursive: true, force: true });
  });
  return { workspace, hosts, dataDir: path.join(workspace, '.dsh.mbt') };
}

function response(content = 'done', toolCalls = []) {
  return new Response(JSON.stringify({ choices: [{ message: { role: 'assistant', content, ...(toolCalls.length ? { tool_calls: toolCalls.map((call) => ({ id: call.id, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } })) } : {}) }, finish_reason: toolCalls.length ? 'tool_calls' : 'stop' }] }), { headers: { 'content-type': 'application/json' } });
}

async function send(host, prompt = 'test') {
  const created = await host.call('session_create', {});
  assert.equal(created.ok, true);
  const sent = await host.call('session_send', { session_id: created.result.id, prompt });
  assert.equal(sent.ok, true);
  return created.result.id;
}

async function until(predicate) {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error('Condition did not become true');
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

test('offline fixture performs a real tool turn and restores the completed transcript', async (t) => {
  const { workspace, hosts, dataDir } = await temporary(t);
  await fs.writeFile(path.join(workspace, 'example.mbt'), 'MoonBit');
  const host = await createHost({ workspace, demo: true });
  hosts.push(host);
  const id = await send(host, 'List files');
  const final = await host.waitForSession(id);
  assert.equal(final.status, 'completed');
  assert.equal(final.messages.filter((message) => message.role === 'tool').length, 1);
  assert.match(final.messages.find((message) => message.role === 'tool').content, /example\.mbt/);
  assert.match(final.messages.at(-1).content, /deterministic fixture/);
  const disk = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8'));
  assert.equal(disk.sessions[0].status, 'completed');
  await host.close();
  const restored = await createHost({ workspace, demo: true });
  hosts.push(restored);
  assert.deepEqual((await restored.session(id)).messages, final.messages);
  assert.equal(restored.activeCount, 0);
});

test('real provider carrier persists before IO, requires per-call write approval, then settles the tool result', async (t) => {
  const { workspace, hosts, dataDir } = await temporary(t);
  let requests = 0;
  const host = await createHost({ workspace, mode: 'openai', model: 'test-model', baseURL: 'http://127.0.0.1:1/v1', fetchImpl: async (_url, init) => {
    requests++;
    const durable = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8')).sessions[0];
    assert.equal(durable.status, 'running');
    assert.equal(durable.events.at(-1).type, 'llm/request');
    const body = JSON.parse(init.body);
    assert.equal(body.model, 'test-model');
    if (requests === 1) return response('', [{ id: 'write-one', name: 'write', arguments: { file_path: 'approved.txt', content: 'approved content' } }]);
    assert.equal(await fs.readFile(path.join(workspace, 'approved.txt'), 'utf8'), 'approved content');
    assert.ok(durable.events.some((event) => event.type === 'tool/result'));
    assert.ok(body.messages.some((message) => message.role === 'tool'));
    return response('Written.');
  } });
  hosts.push(host);
  const id = await send(host);
  const pending = await host.waitForSession(id);
  assert.equal(pending.status, 'awaiting_approval');
  assert.equal(pending.pending_approval.call_id, 'write-one');
  await assert.rejects(fs.stat(path.join(workspace, 'approved.txt')), { code: 'ENOENT' });
  const wrong = await host.call('tool_approve', { session_id: id, call_id: 'different-call', approved: true });
  assert.equal(wrong.ok, false);
  assert.equal(requests, 1);
  const approved = await host.call('tool_approve', { session_id: id, call_id: 'write-one', approved: true });
  assert.equal(approved.ok, true);
  const final = await host.waitForSession(id);
  assert.equal(final.status, 'completed');
  assert.equal(requests, 2);
  assert.equal(final.messages.find((message) => message.role === 'tool').is_error, false);
});

test('cancel aborts the in-flight provider and rejects a late settlement', async (t) => {
  const { workspace, hosts } = await temporary(t);
  let fetchSignal;
  let release;
  const host = await createHost({ workspace, mode: 'openai', model: 'test-model', baseURL: 'http://127.0.0.1:1', fetchImpl: async (_url, init) => {
    fetchSignal = init.signal;
    return new Promise((resolve) => { release = resolve; });
  } });
  hosts.push(host);
  const id = await send(host);
  await until(() => fetchSignal);
  const cancelled = await host.call('session_cancel', { session_id: id });
  assert.equal(cancelled.result.status, 'cancelled');
  assert.equal(fetchSignal.aborted, true);
  release(response('Late content must be ignored'));
  await until(() => host.activeCount === 0);
  const state = await host.session(id);
  assert.equal(state.status, 'cancelled');
  assert.ok(!state.messages.some((message) => message.content?.includes('Late content')));
});

test('restoring an interrupted approved tool fails the turn without replaying IO', async (t) => {
  const { workspace, hosts, dataDir } = await temporary(t);
  const facade = await loadFacade();
  facade.start();
  try {
    const id = JSON.parse(facade.dispatch(JSON.stringify({ operation: 'session_create', input: {} }))).result.id;
    facade.dispatch(JSON.stringify({ operation: 'session_send', input: { session_id: id, prompt: 'write' } }));
    const [effect] = JSON.parse(facade.take_effects());
    const completion = { ok: true, content: '', tool_calls: [{ id: 'interrupted-write', name: 'write', arguments: '{"file_path":"never-write.txt","content":"unsafe replay"}' }], finish_reason: 'tool_calls' };
    assert.equal(JSON.parse(facade.complete(effect.id, JSON.stringify(completion))).ok, true);
    assert.equal(JSON.parse(facade.dispatch(JSON.stringify({ operation: 'tool_approve', input: { session_id: id, call_id: 'interrupted-write', approved: true } }))).ok, true);
    const queued = JSON.parse(facade.take_effects());
    assert.equal(queued[0].kind, 'tool');
    await fs.mkdir(dataDir);
    await fs.writeFile(path.join(dataDir, 'sessions.json'), facade.snapshot());
  } finally { facade.stop(); }
  const restored = await createHost({ workspace, demo: true });
  hosts.push(restored);
  const state = await restored.state();
  assert.equal(state.sessions[0].status, 'failed');
  assert.match(JSON.stringify(state.sessions[0].events), /interrupted/i);
  assert.equal(restored.activeCount, 0);
  await assert.rejects(fs.stat(path.join(workspace, 'never-write.txt')), { code: 'ENOENT' });
});

test('concurrent hosts cannot share a module-global facade even with separate data directories', async (t) => {
  const { workspace, hosts } = await temporary(t);
  const facade = await loadFacade();
  const results = await Promise.allSettled([
    createHost({ workspace, dataDir: path.join(workspace, 'data-a'), facade, demo: true }),
    createHost({ workspace, dataDir: path.join(workspace, 'data-b'), facade, demo: true }),
  ]);
  const fulfilled = results.filter((result) => result.status === 'fulfilled');
  for (const result of fulfilled) hosts.push(result.value);
  assert.equal(fulfilled.length, 1);
  assert.match(results.find((result) => result.status === 'rejected').reason.message, /already owned/);
  assert.equal((await fulfilled[0].value.call('session_create', {})).ok, true);
});

test('shutdown during checkpoint never starts new provider IO', async (t) => {
  const { workspace, hosts, dataDir } = await temporary(t);
  let requests = 0;
  const host = await createHost({ workspace, mode: 'openai', model: 'test-model', baseURL: 'http://127.0.0.1:1', timeoutMs: 50, fetchImpl: async () => { requests++; return response('should not run'); } });
  hosts.push(host);
  const created = await host.call('session_create', {});
  const sending = host.call('session_send', { session_id: created.result.id, prompt: 'race' });
  await Promise.resolve();
  const closing = host.close();
  await Promise.all([sending, closing]);
  assert.equal(requests, 0);
  const durable = JSON.parse(await fs.readFile(path.join(dataDir, 'sessions.json'), 'utf8'));
  assert.equal(durable.sessions[0].status, 'cancelled');
});

test('oversized read and bash output still settle as bounded successful tool results', { skip: process.platform === 'win32' }, async (t) => {
  const { workspace, hosts } = await temporary(t);
  await fs.writeFile(path.join(workspace, 'large.txt'), 'x'.repeat(70_000));
  let requests = 0;
  const calls = [
    { id: 'large-read', name: 'read', arguments: { file_path: 'large.txt' } },
    { id: 'large-bash', name: 'bash', arguments: { command: 'printf "%070000d" 0' } },
  ];
  const host = await createHost({ workspace, mode: 'openai', model: 'test-model', baseURL: 'http://127.0.0.1:1', allowShell: true, approveTools: ['bash'], fetchImpl: async () => {
    requests++;
    if (requests % 2 === 1) return response('', [calls[Math.floor((requests - 1) / 2)]]);
    return response('Large outputs processed.');
  } });
  hosts.push(host);
  // Each output gets its own session: duplicating two 64 KiB results into both
  // events and messages would intentionally exceed the 256 KiB session cap.
  for (const call of calls) {
    const final = await host.waitForSession(await send(host, call.name));
    assert.equal(final.status, 'completed', JSON.stringify(final.events.at(-1)));
    const results = final.messages.filter((message) => message.role === 'tool');
    assert.equal(results.length, 1);
    const result = results[0];
    assert.equal(result.is_error, false, result.content);
    assert.ok(Buffer.byteLength(result.content) <= 65536);
    assert.match(result.content, /output truncated/);
  }
});

test('invalid saved data is preserved and releases both lock and facade ownership', async (t) => {
  const { workspace, hosts, dataDir } = await temporary(t);
  await fs.mkdir(dataDir);
  const snapshotPath = path.join(dataDir, 'sessions.json');
  await fs.writeFile(snapshotPath, 'invalid JSON');
  await assert.rejects(createHost({ workspace, demo: true }), /invalid JSON/i);
  assert.equal(await fs.readFile(snapshotPath, 'utf8'), 'invalid JSON');
  await assert.rejects(fs.stat(path.join(dataDir, 'host.lock')), { code: 'ENOENT' });
  await fs.unlink(snapshotPath);
  const host = await createHost({ workspace, demo: true });
  hosts.push(host);
  assert.equal((await host.state()).sessions.length, 0);
});
