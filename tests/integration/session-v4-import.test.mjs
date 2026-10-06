import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';

const upstream = await readFile(new URL('../fixtures/upstream-tool-call-turn/session.v4.jsonl', import.meta.url), 'utf8');
const tools = [{ name: 'read', description: 'Read a text file.', parameters: { type: 'object', properties: { path: { type: 'string' } } } }];

function row(type, data, extra = {}) { return { type, data, ...extra }; }

function archive(header, events) {
  const rows = [header, ...events.map((event, seq) => ({ ...event, seq, time: seq + 1 }))];
  return rows.map((value) => JSON.stringify(value)).join('\n');
}

function message(role, id, source, content, extra = {}) {
  return { role, id, source, content, ...extra };
}

function requestRows(events, turn, step, reason = 'initial') {
  events.push(row('request/header', {
    reason,
    header: {
      config: { provider: 'fixture', model: 'fixture-model' },
      tools,
    },
  }));
  events.push(row('request/context', { provider: 'fixture', model: 'fixture-model' }));
}

function multiTurnInboxArchive() {
  const events = [];
  const prompt = message('user', 'user-1', { kind: 'user' }, [{ type: 'text', text: 'Read one file.' }]);
  events.push(row('agent/inbox/spliced', { target: 'next-turn', start: 0, inserted: [prompt] }));
  events.push(row('turn/start', { turn: 1 }));
  events.push(row('agent/inbox/spliced', { target: 'next-turn', start: 0, removedCount: 1, inserted: [] }));
  events.push(row('step/start', { turn: 1, step: 1 }));
  events.push(row('user/message', prompt, { surfaceOp: 'append' }));
  requestRows(events, 1, 1);
  events.push(row('session/title', { title: 'Read one file', messageSeqs: [4], source: { kind: 'fallback' } }));
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'assistant-call', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'tool-call', id: 'read-one', name: 'read', arguments: '{"path":"note.txt"}' },
    ]),
  }, { surfaceOp: 'append' }));
  const callSeq = events.push(row('tool/call', { turn: 1, step: 1, callId: 'read-one', name: 'read', arguments: '{"path":"note.txt"}' })) - 1;
  events.push(row('tool/result', {
    turn: 1,
    step: 1,
    message: message('tool', 'result-one', { kind: 'tool', callId: 'read-one' }, [{ type: 'text', text: 'note contents' }], { toolCallId: 'read-one', isError: false }),
  }, { sourceEventSeqs: [callSeq], surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('step/start', { turn: 1, step: 2 }));
  requestRows(events, 1, 2, 'resume');
  events.push(row('assistant/message', {
    turn: 1,
    step: 2,
    message: message('assistant', 'assistant-final', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [{ type: 'text', text: 'First turn completed.' }]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 2 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'completed' } }));
  const secondPrompt = message('user', 'user-2', { kind: 'user' }, [{ type: 'text', text: 'Summarize the result.' }]);
  events.push(row('agent/inbox/spliced', {
    target: 'next-turn', start: 0, inserted: [secondPrompt],
  }));
  events.push(row('turn/start', { turn: 2 }));
  events.push(row('agent/inbox/spliced', { target: 'next-turn', start: 0, removedCount: 1, inserted: [] }));
  events.push(row('step/start', { turn: 2, step: 1 }));
  events.push(row('user/message', secondPrompt, { surfaceOp: 'append' }));
  requestRows(events, 2, 1);
  events.push(row('assistant/message', {
    turn: 2,
    step: 1,
    message: message('assistant', 'assistant-second-turn', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [{ type: 'text', text: 'Second turn completed.' }]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 2, step: 1 }));
  events.push(row('turn/end', { turn: 2, reason: { kind: 'completed' } }));
  events.push(row('agent/inbox/spliced', {
    target: 'next-turn', start: 0,
    inserted: [message('user', 'queued-user', { kind: 'user' }, [{ type: 'text', text: 'Keep this queued.' }])],
  }));
  const header = { type: 'session', version: 4, id: 'fixture-multi', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 };
  return archive(header, events);
}

function forkArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'fork-user', { kind: 'user' }, [{ type: 'text', text: 'Read a file.' }]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'fork-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'tool-call', id: 'read-one', name: 'read', arguments: '{}' },
      { type: 'tool-call', id: 'write-two', name: 'write', arguments: '{"path":"side-effect"}' },
    ]),
  }, { surfaceOp: 'append' }));
  const startedCallSeq = events.push(row('tool/call', {
    turn: 1, step: 1, callId: 'write-two', name: 'write', arguments: '{"path":"side-effect"}',
  })) - 1;
  events.push(row('session/end-seed', { inherited: true }));
  const resultSeq = events.length;
  events.push(row('tool/result', {
    turn: 1,
    step: 1,
    error: { name: 'ToolNotStartedError', code: 'TOOL_NOT_STARTED' },
    message: message('tool', `forked-tool-result-read-one-${resultSeq}`, { kind: 'tool', callId: 'read-one' }, [
      { type: 'text', text: 'The parent session may have executed it after the fork point.' },
    ], { toolCallId: 'read-one', isError: true }),
  }, { surfaceOp: 'append' }));
  events.push(row('tool/result', {
    turn: 1,
    step: 1,
    error: { name: 'ToolOutcomeUnknownError', code: 'TOOL_OUTCOME_UNKNOWN' },
    message: message('tool', 'forked-unknown-result', { kind: 'tool', callId: 'write-two' }, [
      { type: 'text', text: 'The parent session may have executed this call; verify before retrying.' },
    ], { toolCallId: 'write-two', isError: true }),
  }, { sourceEventSeqs: [startedCallSeq], surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'forked' } }));
  const header = { type: 'session', version: 4, id: 'fixture-fork', createdAt: 1, cwd: '/workspace', parentSession: 'fixture-parent', isSeeded: true, delegationDepth: 0 };
  return archive(header, events);
}

function interruptedArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'interrupted-user', { kind: 'user' }, [{ type: 'text', text: 'Read a file.' }]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'interrupted-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'tool-call', id: 'not-started', name: 'read', arguments: '{}' },
      { type: 'tool-call', id: 'outcome-unknown', name: 'read', arguments: '{"path":"side-effect"}' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('tool/call', { turn: 1, step: 1, callId: 'outcome-unknown', name: 'read', arguments: '{"path":"side-effect"}' }));
  const header = { type: 'session', version: 4, id: 'fixture-interrupted', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 };
  return archive(header, events);
}

function assistantlessFailureArchive(reason) {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'error-user', { kind: 'user' }, [
      { type: 'text', text: 'A provider request that fails before a response.' },
    ]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('turn/end', { turn: 1, reason }));
  const header = { type: 'session', version: 4, id: 'fixture-step-error', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 };
  return archive(header, events);
}

function inboxArchiveBeforeAbort({ closeTurn }) {
  const pending = message('user', 'unadmitted-user', { kind: 'user' }, [
    { type: 'text', text: 'This was claimed but never admitted to a model request.' },
  ]);
  const events = [
    row('agent/inbox/spliced', { target: 'next-turn', start: 0, inserted: [pending] }),
    row('turn/start', { turn: 1 }),
    row('agent/inbox/spliced', { target: 'next-turn', start: 0, removedCount: 1, inserted: [] }),
  ];
  if (closeTurn) events.push(row('turn/end', { turn: 1, reason: { kind: 'aborted', reason: { kind: 'user' } } }));
  const header = { type: 'session', version: 4, id: closeTurn ? 'fixture-abort-before-step' : 'fixture-eof-before-step', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 };
  return archive(header, events);
}

async function newHost(t, dataDir) {
  const workspace = await mkdtemp(path.join(os.tmpdir(), 'dsh-session-v4-'));
  const selectedDataDir = dataDir ?? path.join(workspace, '.dsh.mbt');
  let fetchCalls = 0;
  const facade = await import(`${pathToFileURL(defaultModulePath).href}?test=${randomUUID()}`);
  const host = await createHost({
    facade,
    workspace,
    dataDir: selectedDataDir,
    mode: 'deepseek',
    model: 'fixture-model',
    baseURL: 'http://127.0.0.1:1',
    fetchImpl: async () => { fetchCalls += 1; throw new Error('unexpected provider access'); },
  });
  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    await host.close();
  }
  t.after(async () => {
    try { await close(); }
    finally { await rm(workspace, { recursive: true, force: true }); }
  });
  return { host, facade, close, fetchCalls: () => fetchCalls };
}

test('unmodified upstream snapshot imports as an inert read-only history and survives restore', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const first = await newHost(t, dataDir);
  const imported = await first.host.call('session_import', { jsonl: upstream });
  assert.equal(imported.ok, true, imported.error);
  assert.equal(imported.result.source_format, 'deepseek-session-v4');
  assert.equal(imported.result.status, 'completed');
  assert.equal(imported.result.messages.length, 6);
  assert.ok(imported.result.messages.every((item) => typeof item.content === 'string'));
  assert.deepEqual(imported.result.messages.map((item) => item.role), ['system', 'user', 'user', 'assistant', 'tool', 'assistant']);
  assert.equal(first.host.activeCount, 0);
  assert.equal(first.fetchCalls(), 0);

  const before = await first.host.session(imported.result.id);
  const forged = JSON.parse(first.facade.snapshot());
  forged.sessions[0].messages[0].content = 'a forged derived transcript';
  const rejected = JSON.parse(first.facade.restore(JSON.stringify(forged)));
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /projection disagrees/);
  assert.deepEqual(await first.host.session(imported.result.id), before);

  const forgedCreation = JSON.parse(first.facade.snapshot());
  forgedCreation.sessions[0].events[0].seq = 999;
  const rejectedCreation = JSON.parse(first.facade.restore(JSON.stringify(forgedCreation)));
  assert.equal(rejectedCreation.ok, false);
  assert.match(rejectedCreation.error, /creation event is not canonical/);
  assert.deepEqual(await first.host.session(imported.result.id), before);

  await first.close();
  const second = await newHost(t, dataDir);
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const reopened = await second.host.session(imported.result.id);
  assert.deepEqual(reopened, before);
  assert.equal(second.host.activeCount, 0);
  assert.equal(second.fetchCalls(), 0);
  const deniedSend = await second.host.call('session_send', { session_id: imported.result.id, prompt: 'continue' });
  const deniedCancel = await second.host.call('session_cancel', { session_id: imported.result.id });
  assert.equal(deniedSend.ok, false);
  assert.equal(deniedCancel.ok, false);
  assert.deepEqual(await second.host.session(imported.result.id), before);
  assert.equal(second.fetchCalls(), 0);
});

test('physical V4 replay validates dense calls, turns, title citations and inert inbox state', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const imported = await host.call('session_import', { jsonl: multiTurnInboxArchive() });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  assert.equal(session.status, 'completed');
  assert.equal(session.title, 'Read one file');
  assert.deepEqual(session.messages.filter((item) => item.role === 'assistant').map((item) => item.content), ['', 'First turn completed.', 'Second turn completed.']);
  assert.equal(session.turn_id, 2);
  assert.equal(session.messages.find((item) => item.role === 'tool').tool_call_id, 'read-one');
  assert.equal(session.pending_tool_calls.length, 0);
  assert.equal(session.pending_inbox.next_turn[0].content[0].text, 'Keep this queued.');
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);

  const before = await host.session(session.id);
  const malformed = multiTurnInboxArchive().replace('"callId":"read-one"', '"callId":"different"');
  const rejected = await host.call('session_import', { jsonl: malformed });
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /advertised assistant call/);
  assert.deepEqual(await host.session(session.id), before);
  assert.equal((await host.call('session_list')).result.length, 1);
});

test('seeded fork closures preserve branch error records without execution', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const imported = await host.call('session_import', { jsonl: forkArchive() });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  assert.equal(session.status, 'failed');
  assert.equal(session.messages.at(-2).source_message_id, 'forked-tool-result-read-one-8');
  assert.equal(session.messages.at(-2).is_error, true);
  assert.equal(session.messages.at(-1).source_message_id, 'forked-unknown-result');
  assert.equal(session.messages.at(-1).is_error, true);
  assert.equal(session.messages.at(-1).tool_call_id, 'write-two');
  const unknownResult = session.events.find((event) => event.type === 'upstream/event' && event.data.record.type === 'tool/result' && event.data.record.data.message.toolCallId === 'write-two');
  assert.equal(unknownResult.data.record.data.error.code, 'TOOL_OUTCOME_UNKNOWN');
  assert.deepEqual(session.pending_tool_calls, []);
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('open imported turns expose unstarted and unknown outcomes without repairing the archive', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const jsonl = interruptedArchive();
  const imported = await host.call('session_import', { jsonl });
  assert.equal(imported.ok, true, imported.error);
  assert.equal(imported.result.status, 'failed');
  assert.deepEqual(imported.result.pending_tool_calls.map((call) => [call.id, call.state]), [
    ['not-started', 'not_started'],
    ['outcome-unknown', 'outcome_unknown'],
  ]);
  assert.equal(imported.result.events.filter((event) => event.type === 'tool/result').length, 0);
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('provider errors, pre-step cancellation and interrupted inbox claims restore inertly', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-terminal-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const first = await newHost(t, dataDir);
  const providerFailure = await first.host.call('session_import', { jsonl: assistantlessFailureArchive({ kind: 'error', error: { message: 'provider unavailable', code: 'CONNECTION' } }) });
  assert.equal(providerFailure.ok, true, providerFailure.error);
  assert.equal(providerFailure.result.status, 'failed');
  assert.ok(!providerFailure.result.messages.some((item) => item.role === 'assistant'));

  const aborted = await first.host.call('session_import', { jsonl: inboxArchiveBeforeAbort({ closeTurn: true }) });
  assert.equal(aborted.ok, true, aborted.error);
  assert.equal(aborted.result.status, 'cancelled');
  assert.equal(aborted.result.pending_inbox.unadmitted_turn[0].id, 'unadmitted-user');

  const interrupted = await first.host.call('session_import', { jsonl: inboxArchiveBeforeAbort({ closeTurn: false }) });
  assert.equal(interrupted.ok, true, interrupted.error);
  assert.equal(interrupted.result.status, 'failed');
  assert.equal(interrupted.result.pending_inbox.unadmitted_turn[0].id, 'unadmitted-user');
  assert.equal(first.host.activeCount, 0);
  assert.equal(first.fetchCalls(), 0);

  const malformedSuccess = await first.host.call('session_import', {
    jsonl: assistantlessFailureArchive({ kind: 'completed' }),
  });
  assert.equal(malformedSuccess.ok, false);
  assert.match(malformedSuccess.error, /successfully end a step without an assistant/);
  assert.equal((await first.host.call('session_list')).result.length, 3);

  await first.close();
  const reopened = await newHost(t, dataDir);
  assert.equal((await reopened.host.session(providerFailure.result.id)).status, 'failed');
  assert.equal((await reopened.host.session(aborted.result.id)).pending_inbox.unadmitted_turn[0].id, 'unadmitted-user');
  assert.equal((await reopened.host.session(interrupted.result.id)).pending_inbox.unadmitted_turn[0].id, 'unadmitted-user');
  assert.equal(reopened.host.activeCount, 0);
  assert.equal(reopened.fetchCalls(), 0);
  t.after(() => rm(temporary, { recursive: true, force: true }));
});

test('native physical envelope and fork admission failures are atomic', async (t) => {
  const { host } = await newHost(t);
  const before = await host.call('session_list');
  const invalid = forkArchive().replace('"isSeeded":true', '"isSeeded":false');
  const rejected = await host.call('session_import', { jsonl: invalid });
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /isSeeded|inherited end-seed/);
  assert.deepEqual(await host.call('session_list'), before);
  assert.equal(host.activeCount, 0);
});
