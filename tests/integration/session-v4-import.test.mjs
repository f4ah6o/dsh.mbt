import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';

const upstream = await readFile(new URL('../fixtures/upstream-tool-call-turn/session.v4.jsonl', import.meta.url), 'utf8');
const tools = [{ name: 'read', description: 'Read a text file.', parameters: { type: 'object', properties: { path: { type: 'string' } } } }];
const newlySupportedSnapshots = [
  'dynamic-tool-updates',
  'dynamic-tool-prompt-updates',
  'plugin-manager-mcp',
  'compaction-output-reserve',
  'compaction-summary-headroom',
];

function row(type, data, extra = {}) { return { type, data, ...extra }; }

function archive(header, events) {
  const rows = [header, ...events.map((event, seq) => ({ ...event, seq, time: seq + 1 }))];
  return rows.map((value) => JSON.stringify(value)).join('\n');
}

function snapshotArchive(header, events) {
  return [header, ...events].map((value) => JSON.stringify(value)).join('\n');
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

function compactionSnapshotWithHistoricalSurfaceRewrite(jsonl) {
  const [header, ...events] = jsonl.trimEnd().split('\n').map((line) => JSON.parse(line));
  const seqOf = (predicate) => events.findIndex(predicate);
  const summarySeq = seqOf((event) => event.type === 'compaction/summary');
  const checkpointSeq = seqOf((event) => event.type === 'user/message' && event.data.source.kind === 'compact-checkpoint');
  const assistantSeq = seqOf((event) => event.type === 'assistant/message');
  const resultSeq = seqOf((event) => event.type === 'tool/result');
  const lastAssistantSeq = events.findLastIndex((event) => event.type === 'assistant/message');
  assert.ok(summarySeq >= 0 && checkpointSeq > summarySeq && assistantSeq >= 0 && resultSeq > assistantSeq);

  events.push(row('turn/start', { turn: 2 }));
  events.push(row('step/start', { turn: 2, step: 1 }));
  events.push(row('user/message', message('user', 'rewrite-user-2', { kind: 'user' }, [
    { type: 'text', text: 'Continue after the imported compaction.' },
  ]), { surfaceOp: 'append' }));
  const rewrittenSeq = events.length;
  events.push(row('user/message', {
    turn: 2,
    step: 1,
    ...message('user', 'rewrite-runtime-context', { kind: 'runtime-context' }, [
      { type: 'text', text: 'A read-only replacement over historical context.' },
    ]),
  }, {
    sourceEventSeqs: [summarySeq, checkpointSeq, assistantSeq, resultSeq],
    surfaceOp: { op: 'replace', startSeq: checkpointSeq, endSeq: resultSeq },
  }));
  requestRows(events, 2, 1);
  events.push(row('assistant/message', {
    turn: 2,
    step: 1,
    message: message('assistant', 'rewrite-assistant-2', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: 'Historical replacement preserved.' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 2, step: 1 }));
  events.push(row('turn/end', { turn: 2, reason: { kind: 'completed' } }));
  return {
    jsonl: snapshotArchive(header, events),
    lastAssistantSeq,
    rewrittenSeq,
    summarySeq,
    checkpointSeq,
    assistantSeq,
    resultSeq,
  };
}

function compactionSnapshotWithOlderToolResultPruned(jsonl) {
  const [header, ...events] = jsonl.trimEnd().split('\n').map((line) => JSON.parse(line));
  const resultSeq = events.findIndex((event) => event.type === 'tool/result');
  const original = events[resultSeq];
  assert.ok(original);
  const replacementData = structuredClone(original.data);
  replacementData.message.content = [{ type: 'text', text: '[older tool output pruned]' }];

  events.push(row('turn/start', { turn: 2 }));
  events.push(row('step/start', { turn: 2, step: 1 }));
  events.push(row('compaction/prune', {
    shadowedRange: { start: resultSeq, end: resultSeq },
    shadowedSeqs: [resultSeq],
    shadowedTokenCount: 37,
  }));
  const replacementSeq = events.length;
  events.push(row('tool/result', replacementData, {
    sourceEventSeqs: [resultSeq],
    surfaceOp: { op: 'replace', startSeq: resultSeq, endSeq: resultSeq },
  }));
  events.push(row('user/message', message('user', 'prune-user-2', { kind: 'user' }, [
    { type: 'text', text: 'Continue after pruning the earlier result.' },
  ]), { surfaceOp: 'append' }));
  requestRows(events, 2, 1);
  events.push(row('assistant/message', {
    turn: 2,
    step: 1,
    message: message('assistant', 'prune-assistant-2', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: 'The older result remains a transcript record only.' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 2, step: 1 }));
  events.push(row('turn/end', { turn: 2, reason: { kind: 'completed' } }));
  return { jsonl: snapshotArchive(header, events), resultSeq, replacementSeq };
}

function assistantAttemptArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'attempt-user', { kind: 'user' }, [
      { type: 'text', text: 'Answer without running a tool.' },
    ]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/attempt', {
    turn: 1,
    step: 1,
    stream: [{
      type: 'chunk', time: 1,
      chunk: { type: 'block-end', index: 0, block: { type: 'tool-call', id: 'diagnostic-only', name: 'read', arguments: '{}' } },
    }],
  }));
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'attempt-final', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: 'No tool ran.' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'completed' } }));
  return archive({ type: 'session', version: 4, id: 'fixture-attempt', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 }, events);
}

function manualCompactionArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('system/message', {
      turn: 1, step: 1,
      message: message('system', 'manual-system', { kind: 'system-prompt' }, [{ type: 'text', text: 'System prompt.' }]),
    }, { surfaceOp: 'append' }),
    row('user/message', message('user', 'manual-user', { kind: 'user' }, [{ type: 'text', text: 'A prompt to compact later.' }]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1, step: 1,
    message: message('assistant', 'manual-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [{ type: 'text', text: 'Completed before manual compaction.' }]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'completed' } }));
  const userSeq = events.findIndex((event) => event.type === 'user/message');
  const startSeq = events.length;
  events.push(row('compaction/start', { compactionId: 'manual-compact', turn: null }));
  const summarySeq = events.length;
  events.push(row('compaction/summary', {
    compactionId: 'manual-compact',
    summary: [{ type: 'text', text: 'A standalone manual summary.' }],
    shadowedRange: { start: userSeq, end: userSeq },
    shadowedSeqs: [userSeq],
    shadowedTokenCount: 42,
    provider: 'fixture', model: 'fixture-model',
  }));
  events.push(row('user/message', message('user', 'manual-checkpoint', {
    kind: 'compact-checkpoint', compactionId: 'manual-compact',
  }, [{ type: 'text', text: 'A standalone manual checkpoint.' }]), {
    sourceEventSeqs: [startSeq, summarySeq, userSeq],
    surfaceOp: { op: 'replace', startSeq: userSeq, endSeq: userSeq },
  }));
  events.push(row('compaction/end', { compactionId: 'manual-compact', turn: null }));
  return archive({ type: 'session', version: 4, id: 'fixture-manual-compaction', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 }, events);
}

function seededCutAfterCompactionSummaryArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'fork-compact-user', { kind: 'user' }, [{ type: 'text', text: 'Fork during compaction.' }]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1, step: 1,
    message: message('assistant', 'fork-compact-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [{ type: 'text', text: 'Before summary.' }]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  const userSeq = events.findIndex((event) => event.type === 'user/message');
  events.push(row('compaction/start', { compactionId: 'fork-summary-compact', turn: 1 }));
  events.push(row('compaction/summary', {
    compactionId: 'fork-summary-compact',
    summary: [{ type: 'text', text: 'Compaction summary at the fork cut.' }],
    shadowedRange: { start: userSeq, end: userSeq },
    shadowedSeqs: [userSeq],
    shadowedTokenCount: 24,
    provider: 'fixture', model: 'fixture-model',
  }));
  events.push(row('session/end-seed', { inherited: true }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'forked' } }));
  return archive({ type: 'session', version: 4, id: 'fixture-seed-summary', createdAt: 1, cwd: '/workspace', parentSession: 'fixture-parent', isSeeded: true, delegationDepth: 1 }, events);
}

function seededCutAfterCompactionPruneArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('user/message', message('user', 'fork-prune-user', { kind: 'user' }, [{ type: 'text', text: 'Fork during pruning.' }]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1, step: 1,
    message: message('assistant', 'fork-prune-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'tool-call', id: 'fork-prune-call', name: 'read', arguments: '{}' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('tool/call', { turn: 1, step: 1, callId: 'fork-prune-call', name: 'read', arguments: '{}' }));
  const resultSeq = events.length;
  events.push(row('tool/result', {
    turn: 1, step: 1,
    message: message('tool', 'fork-prune-result', { kind: 'tool', callId: 'fork-prune-call' }, [{ type: 'text', text: 'result' }], { toolCallId: 'fork-prune-call', isError: false }),
  }, { sourceEventSeqs: [resultSeq - 1], surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('compaction/prune', {
    shadowedRange: { start: resultSeq, end: resultSeq },
    shadowedSeqs: [resultSeq], shadowedTokenCount: 12,
  }));
  events.push(row('session/end-seed', { inherited: true }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'forked' } }));
  return archive({ type: 'session', version: 4, id: 'fixture-seed-prune', createdAt: 1, cwd: '/workspace', parentSession: 'fixture-parent', isSeeded: true, delegationDepth: 1 }, events);
}

function emptyBlockProjectionArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('system/message', {
      turn: 1,
      step: 1,
      message: message('system', 'empty-system-block', { kind: 'system-prompt' }, [
        { type: 'text', text: '' },
      ]),
    }, { surfaceOp: 'append' }),
    row('user/message', message('user', 'empty-content-user', { kind: 'user' }, [
      { type: 'text', text: 'Keep empty source blocks distinct from no blocks.' },
    ]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'empty-assistant-block', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: '' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('step/start', { turn: 1, step: 2 }));
  requestRows(events, 1, 2, 'resume');
  const emptyArrayAssistantSeq = events.length;
  events.push(row('assistant/message', {
    turn: 1,
    step: 2,
    message: message('assistant', 'empty-assistant-array', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, []),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 2 }));
  events.push(row('step/start', { turn: 1, step: 3 }));
  events.push(row('user/message', message('user', 'replacement-for-empty-node', { kind: 'runtime-context' }, [
    { type: 'text', text: 'The empty assistant surface node was present for replacement.' },
  ]), {
    sourceEventSeqs: [emptyArrayAssistantSeq],
    surfaceOp: { op: 'replace', startSeq: emptyArrayAssistantSeq, endSeq: emptyArrayAssistantSeq },
  }));
  requestRows(events, 1, 3, 'resume');
  events.push(row('assistant/message', {
    turn: 1,
    step: 3,
    message: message('assistant', 'empty-projection-final', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: 'Finished.' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 3 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'completed' } }));
  return archive({ type: 'session', version: 4, id: 'fixture-empty-blocks', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 }, events);
}

function legacyEmptyProjectionArchive() {
  const events = [
    row('turn/start', { turn: 1 }),
    row('step/start', { turn: 1, step: 1 }),
    row('system/message', {
      turn: 1,
      step: 1,
      message: message('system', 'legacy-empty-system', { kind: 'system-prompt' }, []),
    }, { surfaceOp: 'append' }),
    row('user/message', message('user', 'legacy-user', { kind: 'user' }, [
      { type: 'text', text: 'Restore an earlier canonical projection.' },
    ]), { surfaceOp: 'append' }),
  ];
  requestRows(events, 1, 1);
  events.push(row('assistant/message', {
    turn: 1,
    step: 1,
    message: message('assistant', 'legacy-assistant-step-1', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, [
      { type: 'text', text: 'First step.' },
    ]),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 1 }));
  events.push(row('step/start', { turn: 1, step: 2 }));
  events.push(row('assistant/message', {
    turn: 1,
    step: 2,
    message: message('assistant', 'legacy-empty-assistant', { kind: 'model', provider: 'fixture', model: 'fixture-model' }, []),
  }, { surfaceOp: 'append' }));
  events.push(row('step/end', { turn: 1, step: 2 }));
  events.push(row('turn/end', { turn: 1, reason: { kind: 'max-tokens' } }));
  return archive({ type: 'session', version: 4, id: 'fixture-legacy-empty-projection', createdAt: 1, cwd: '/workspace', isSeeded: false, delegationDepth: 0 }, events);
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

test('developer header updates and compaction surface snapshots import inertly and survive reopen', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-parity-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const first = await newHost(t, dataDir);
  const imported = [];
  for (const name of newlySupportedSnapshots) {
    const directory = new URL(`../fixtures/upstream-session-v4/${name}/`, import.meta.url);
    const [jsonl, provenanceText] = await Promise.all([
      readFile(new URL('session.v4.jsonl', directory), 'utf8'),
      readFile(new URL('provenance.json', directory), 'utf8'),
    ]);
    const provenance = JSON.parse(provenanceText);
    assert.equal(provenance.repository, 'https://github.com/deepseek-ai/deepseek-harness');
    assert.equal(provenance.commit, '5badb15009ae1756c3afe0ae0cef1faafc290ccc');
    assert.equal(
      createHash('sha256').update(jsonl).digest('hex'),
      provenance.sha256,
      `${name} must remain byte-for-byte identical to its pinned upstream snapshot`,
    );
    const result = await first.host.call('session_import', { jsonl });
    assert.equal(result.ok, true, `${name}: ${result.error}`);
    assert.equal(result.result.source_format, 'deepseek-session-v4');
    assert.equal(result.result.status, 'completed');
    imported.push({ name, session: result.result });
  }

  for (const { name, session } of imported) {
    assert.deepEqual(session.pending_tool_calls, [], name);
  }
  for (const name of ['dynamic-tool-updates', 'dynamic-tool-prompt-updates']) {
    const session = imported.find((item) => item.name === name).session;
    const changes = session.messages.flatMap((message) => message.tool_changes ?? []);
    assert.ok(changes.some((change) => change.type === 'tool-addition' && change.tool_name === 'snapshot_ping'), name);
    assert.ok(changes.some((change) => change.type === 'tool-removal' && change.tool_name === 'snapshot_ping'), name);
  }

  for (const name of ['compaction-output-reserve', 'compaction-summary-headroom']) {
    const session = imported.find((item) => item.name === name).session;
    const users = session.messages.filter((message) => message.role === 'user');
    assert.ok(users.some((message) => message.content.includes('<compacted-summary>')), name);
    assert.ok(!users.some((message) => message.content.includes('Establish a durable compaction premise')), name);
    assert.ok(session.messages.some((message) => message.role === 'tool' && message.content === 'alpha\n'), name);
    const surfaceSeqs = session.messages.map((message) => message.source_event_seq);
    assert.ok(surfaceSeqs.indexOf(19) > surfaceSeqs.indexOf(7), `${name} checkpoint stays after the protected system head`);
    assert.ok(surfaceSeqs.indexOf(19) < surfaceSeqs.indexOf(13), `${name} projection follows current surface order after replacement`);
    if (name === 'compaction-output-reserve') {
      const rawTypes = session.events
        .filter((event) => event.type === 'upstream/event')
        .map((event) => event.data.record.type);
      const start = rawTypes.indexOf('compaction/start');
      assert.deepEqual(rawTypes.slice(start - 1, start + 5), [
        'step/end',
        'compaction/start',
        'compaction/summary',
        'user/message',
        'compaction/end',
        'step/start',
      ]);
    }
  }

  assert.equal(first.host.activeCount, 0);
  assert.equal(first.fetchCalls(), 0);
  const saved = new Map(imported.map(({ session }) => [session.id, session]));
  await first.close();

  const reopened = await newHost(t, dataDir);
  t.after(() => rm(temporary, { recursive: true, force: true }));
  for (const [id, before] of saved) {
    assert.deepEqual(await reopened.host.session(id), before);
  }
  assert.equal(reopened.host.activeCount, 0);
  assert.equal(reopened.fetchCalls(), 0);
});

test('new snapshot projections reject forged developer and compaction relationships atomically', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const before = await host.call('session_list');
  const dynamic = await readFile(
    new URL('../fixtures/upstream-session-v4/dynamic-tool-updates/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const alteredHeaderRef = dynamic.replace('"headerSeq":18', '"headerSeq":0');
  assert.notEqual(alteredHeaderRef, dynamic);
  const rejectedHeader = await host.call('session_import', { jsonl: alteredHeaderRef });
  assert.equal(rejectedHeader.ok, false);
  assert.match(rejectedHeader.error, /headerSeq/);

  const compaction = await readFile(
    new URL('../fixtures/upstream-session-v4/compaction-output-reserve/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const rows = compaction.trimEnd().split('\n').map((line) => JSON.parse(line));
  const checkpoint = rows.find((row) => row.type === 'user/message' && row.data.source.kind === 'compact-checkpoint');
  assert.ok(checkpoint);
  checkpoint.surfaceOp.startSeq = checkpoint.surfaceOp.endSeq;
  const rejectedSpan = await host.call('session_import', { jsonl: rows.map((row) => JSON.stringify(row)).join('\n') });
  assert.equal(rejectedSpan.ok, false);
  assert.match(rejectedSpan.error, /summary span|shadowed|sourceEventSeqs/);
  assert.deepEqual(await host.call('session_list'), before);
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('surface replacement uses current positions and may cite shadowed assistant events', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const source = await readFile(
    new URL('../fixtures/upstream-session-v4/compaction-output-reserve/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const rewritten = compactionSnapshotWithHistoricalSurfaceRewrite(source);
  const imported = await host.call('session_import', { jsonl: rewritten.jsonl });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  const projectedSeqs = session.messages.map((message) => message.source_event_seq);
  assert.ok(rewritten.rewrittenSeq > rewritten.lastAssistantSeq);
  assert.ok(projectedSeqs.indexOf(rewritten.rewrittenSeq) < projectedSeqs.indexOf(rewritten.lastAssistantSeq));
  assert.ok(!projectedSeqs.includes(rewritten.assistantSeq));
  assert.ok(!projectedSeqs.includes(rewritten.resultSeq));
  const rewriteEvent = session.events.find((event) => event.type === 'upstream/event' && event.data.record.data.id === 'rewrite-runtime-context');
  assert.deepEqual(rewriteEvent.data.record.sourceEventSeqs, [
    rewritten.summarySeq,
    rewritten.checkpointSeq,
    rewritten.assistantSeq,
    rewritten.resultSeq,
  ]);
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('tool-result pruning rewrites an earlier turn without replaying its tool lifecycle', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const source = await readFile(
    new URL('../fixtures/upstream-session-v4/compaction-output-reserve/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const rewritten = compactionSnapshotWithOlderToolResultPruned(source);
  const imported = await host.call('session_import', { jsonl: rewritten.jsonl });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  const prunedResult = session.messages.find((message) => message.role === 'tool');
  assert.ok(prunedResult);
  assert.equal(prunedResult.content, '[older tool output pruned]');
  assert.equal(prunedResult.source_message_id, '{{message:5}}');
  assert.ok(!session.messages.some((message) => message.content === 'alpha\n'));
  assert.equal(session.pending_tool_calls.length, 0);
  assert.ok(session.messages.some((message) => message.source_event_seq === rewritten.replacementSeq));
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('assistant attempt streams remain diagnostic and do not create tool calls', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const imported = await host.call('session_import', { jsonl: assistantAttemptArchive() });
  assert.equal(imported.ok, true, imported.error);
  assert.deepEqual(imported.result.pending_tool_calls, []);
  assert.deepEqual(imported.result.messages.map((message) => message.content), [
    'Answer without running a tool.',
    'No tool ran.',
  ]);
  assert.equal(imported.result.events.filter((event) => event.type === 'upstream/event' && event.data.record.type === 'assistant/attempt').length, 1);
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('standalone turn-null compaction replaces the current surface without reviving old prompts', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const imported = await host.call('session_import', { jsonl: manualCompactionArchive() });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  assert.equal(session.status, 'completed');
  assert.ok(session.messages.some((message) => message.content === 'A standalone manual checkpoint.'));
  assert.ok(!session.messages.some((message) => message.content === 'A prompt to compact later.'));
  assert.ok(session.events.some((event) => event.type === 'upstream/event' && event.data.record.type === 'compaction/summary'));
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('a seeded fork cut may abandon an inherited compaction summary or prune transaction', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  for (const jsonl of [seededCutAfterCompactionSummaryArchive(), seededCutAfterCompactionPruneArchive()]) {
    const imported = await host.call('session_import', { jsonl });
    assert.equal(imported.ok, true, imported.error);
    assert.equal(imported.result.status, 'failed');
    assert.equal(
      imported.result.events.at(-1).data.record.type,
      'turn/end',
    );
  }
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('empty text blocks remain visible while empty block arrays omit only the derived message', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const imported = await host.call('session_import', { jsonl: emptyBlockProjectionArchive() });
  assert.equal(imported.ok, true, imported.error);
  const session = imported.result;
  assert.ok(session.messages.some((message) => message.source_message_id === 'empty-system-block' && message.role === 'system' && message.content === ''));
  assert.ok(session.messages.some((message) => message.source_message_id === 'empty-assistant-block' && message.role === 'assistant' && message.content === ''));
  assert.ok(!session.messages.some((message) => message.source_message_id === 'empty-assistant-array'));
  assert.ok(session.messages.some((message) => message.source_message_id === 'replacement-for-empty-node'));
  assert.ok(session.events.some((event) => event.type === 'upstream/event' && event.data.record.type === 'assistant/message' && event.data.record.data.message.id === 'empty-assistant-array'));
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});

test('legacy v1 snapshots migrate the exact prior empty-array projection on restore and reopen', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-legacy-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const first = await newHost(t, dataDir);
  const imported = await first.host.call('session_import', { jsonl: legacyEmptyProjectionArchive() });
  assert.equal(imported.ok, true, imported.error);
  const id = imported.result.id;
  assert.deepEqual(imported.result.messages.map((item) => item.role), ['user', 'assistant']);

  const legacySnapshot = JSON.parse(first.facade.snapshot());
  const legacySession = legacySnapshot.sessions.find((item) => item.id === id);
  assert.ok(legacySession);
  legacySession.messages.unshift({
    role: 'system', content: '', source_message_id: 'legacy-empty-system', source_event_seq: 2,
  });
  legacySession.messages.push({
    role: 'assistant', content: '', source_message_id: 'legacy-empty-assistant', source_event_seq: 9,
  });
  assert.deepEqual(legacySession.messages.map((item) => item.role), ['system', 'user', 'assistant', 'assistant']);

  const before = await first.host.session(id);
  const wrongContent = structuredClone(legacySnapshot);
  wrongContent.sessions[0].messages[0].content = 'forged';
  const wrongId = structuredClone(legacySnapshot);
  wrongId.sessions[0].messages[0].source_message_id = 'different-source';
  const wrongSequence = structuredClone(legacySnapshot);
  wrongSequence.sessions[0].messages[0].source_event_seq = 3;
  const mixedLegacyVector = structuredClone(legacySnapshot);
  mixedLegacyVector.sessions[0].messages.splice(0, 1);
  for (const forged of [wrongContent, wrongId, wrongSequence, mixedLegacyVector]) {
    const rejected = JSON.parse(first.facade.restore(JSON.stringify(forged)));
    assert.equal(rejected.ok, false);
    assert.match(rejected.error, /projection disagrees/);
    assert.deepEqual(await first.host.session(id), before);
  }

  const restored = JSON.parse(first.facade.restore(JSON.stringify(legacySnapshot)));
  assert.equal(restored.ok, true, restored.error);
  const canonical = await first.host.session(id);
  assert.deepEqual(canonical.messages.map((item) => item.role), ['user', 'assistant']);
  assert.equal(canonical.messages[0].source_message_id, 'legacy-user');
  assert.equal(canonical.messages[1].source_message_id, 'legacy-assistant-step-1');
  assert.ok(!canonical.messages.some((item) => item.source_message_id === 'legacy-empty-assistant'));
  assert.equal(first.host.activeCount, 0);
  assert.equal(first.fetchCalls(), 0);
  await first.close();

  const reopened = await newHost(t, dataDir);
  t.after(() => rm(temporary, { recursive: true, force: true }));
  assert.deepEqual(await reopened.host.session(id), canonical);
  assert.equal(reopened.host.activeCount, 0);
  assert.equal(reopened.fetchCalls(), 0);
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
