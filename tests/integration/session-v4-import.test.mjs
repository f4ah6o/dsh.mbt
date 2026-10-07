import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';

const upstream = await readFile(new URL('../fixtures/upstream-tool-call-turn/session.v4.jsonl', import.meta.url), 'utf8');
const retryNativeFixture = await readFile(new URL('../fixtures/upstream-session-v4/provider-retry/native/session.v4.jsonl', import.meta.url), 'utf8');
const retryShorthandFixture = await readFile(new URL('../fixtures/upstream-session-v4/provider-retry/shorthand/session.v4.jsonl', import.meta.url), 'utf8');
const tools = [{ name: 'read', description: 'Read a text file.', parameters: { type: 'object', properties: { path: { type: 'string' } } } }];
// Adapted retry fixtures live outside the 25-row unmodified upstream catalog below.
const newlySupportedSnapshots = [
  'dynamic-tool-updates',
  'dynamic-tool-prompt-updates',
  'plugin-manager-mcp',
  'compaction-output-reserve',
  'compaction-summary-headroom',
];
const upstreamCatalogSnapshots = [
  'advanced-toolchain',
  'advanced-toolchain-runtime',
  'bash-same-mode-empty-justification',
  'bash-spill',
  'bash-tool-turn',
  'claude-code-mods',
  'compaction-output-reserve',
  'compaction-summary-headroom',
  'cordis-inspect-jsdoc',
  'cordis-inspect-liveness',
  'cordis-inspect-timeout',
  'dynamic-tool-prompt-updates',
  'dynamic-tool-updates',
  'multimodal-spill-ends',
  'multimodal-spill-middle',
  'office-skills',
  'office-skills-no-renderer',
  'parallel-tool-calls',
  'persistent-pwsh-padded-completion',
  'plugin-manager',
  'plugin-manager-mcp',
  'session-query-spill',
  'skill-load',
  'tool-call-turn',
  'windows-acl-skill',
];
const expectedCatalogShape = new Map([
  ['advanced-toolchain', [14, 5, 5]],
  ['advanced-toolchain-runtime', [12, 4, 4]],
  ['bash-same-mode-empty-justification', [6, 1, 1]],
  ['bash-spill', [6, 1, 1]],
  ['bash-tool-turn', [6, 1, 1]],
  ['claude-code-mods', [8, 2, 2]],
  ['compaction-output-reserve', [5, 1, 1]],
  ['compaction-summary-headroom', [5, 1, 1]],
  ['cordis-inspect-jsdoc', [8, 2, 2]],
  ['cordis-inspect-liveness', [11, 3, 3]],
  ['cordis-inspect-timeout', [8, 2, 2]],
  ['dynamic-tool-prompt-updates', [11, 2, 2]],
  ['dynamic-tool-updates', [10, 2, 2]],
  ['multimodal-spill-ends', [6, 1, 1]],
  ['multimodal-spill-middle', [6, 1, 1]],
  ['office-skills', [8, 2, 2]],
  ['office-skills-no-renderer', [9, 3, 3]],
  ['parallel-tool-calls', [7, 2, 2]],
  ['persistent-pwsh-padded-completion', [8, 2, 2]],
  ['plugin-manager', [8, 2, 2]],
  ['plugin-manager-mcp', [9, 2, 2]],
  ['session-query-spill', [8, 2, 2]],
  ['skill-load', [7, 1, 1]],
  ['tool-call-turn', [6, 1, 1]],
  ['windows-acl-skill', [7, 1, 1]],
]);

function row(type, data, extra = {}) { return { type, data, ...extra }; }

function archive(header, events) {
  const rows = [header, ...events.map((event, seq) => ({ ...event, seq, time: seq + 1 }))];
  return rows.map((value) => JSON.stringify(value)).join('\n');
}

function snapshotArchive(header, events) {
  const shorthandEvents = events.map((event) => {
    const { seq, time, ...shorthand } = event;
    return shorthand;
  });
  return [header, ...shorthandEvents].map((value) => JSON.stringify(value)).join('\n');
}

function retryArchive({ terminal = false, interrupted = false, started = true, attempts = 1, shorthand = false, retryAfterStepEnd = false, mutateFirstRetry, mutateSecondRetry } = {}) {
  const [header, ...sourceEvents] = retryNativeFixture.trimEnd().split('\n').map((line) => JSON.parse(line));
  let events = sourceEvents.map((event) => structuredClone(event));
  const firstSchedule = events.find((event) => event.type === 'llm/retry');
  assert.ok(firstSchedule);
  mutateFirstRetry?.(firstSchedule);
  if (attempts > 1) {
    const firstStartedIndex = events.findIndex((event) => event.type === 'llm/retry-started');
    assert.ok(firstStartedIndex >= 0);
    const secondSchedule = structuredClone(firstSchedule);
    Object.assign(secondSchedule.data, {
      retry: 2,
      delayMs: 10000.5,
      failure: {
        message: 'provider remained busy',
        code: 'RATE_LIMIT',
        status: 429,
        providerRetryAfterMs: 250.5,
        requestId: 'provider-request-2',
      },
    });
    mutateSecondRetry?.(secondSchedule);
    const secondStarted = row('llm/retry-started', {
      retryId: secondSchedule.data.retryId,
      turn: secondSchedule.data.turn,
      step: secondSchedule.data.step,
      retry: secondSchedule.data.retry,
    });
    events.splice(firstStartedIndex + 1, 0, secondSchedule, secondStarted);
  }
  if (terminal || interrupted) {
    events = events.filter((event) => ![
      'assistant/message', 'step/end', 'turn/end',
    ].includes(event.type) && (started || event.type !== 'llm/retry-started'));
    if (terminal) {
      const retries = retryAfterStepEnd
        ? events.filter((event) => ['llm/retry', 'llm/retry-started'].includes(event.type))
        : [];
      if (retryAfterStepEnd) {
        events = events.filter((event) => !['llm/retry', 'llm/retry-started'].includes(event.type));
      }
      events.push(row('step/end', { turn: 1, step: 1 }));
      events.push(...retries);
      events.push(row('turn/end', {
        turn: 1,
        reason: { kind: 'error', error: { message: 'provider retry stopped', code: 'EMPTY_RESPONSE' } },
      }));
    }
  }
  return shorthand ? snapshotArchive(header, events) : archive(header, events);
}

function mutateRetryArchive(mutator, options = {}) {
  const [header, ...events] = retryNativeFixture.trimEnd().split('\n').map((line) => JSON.parse(line));
  mutator(events);
  return options.shorthand ? snapshotArchive(header, events) : archive(header, events);
}

function encodeSnapshotRows(rows) {
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

function assertCatalogTranscriptCorrelation(session, jsonl, name) {
  const lines = jsonl.trimEnd().split('\n');
  const sourceRows = lines.map((line) => JSON.parse(line));
  const sourceEvents = session.events.filter((event) => event.type === 'upstream/event');
  assert.equal(sourceEvents.length, sourceRows.length - 1, `${name} retains every source event`);
  for (const [index, event] of sourceEvents.entries()) {
    assert.equal(event.data.source_seq, index, `${name} source sequence`);
    assert.equal(event.data.raw, lines[index + 1], `${name} raw source line ${index}`);
    assert.deepEqual(event.data.record, sourceRows[index + 1], `${name} parsed source row ${index}`);
  }

  const sourceBySeq = new Map(sourceRows.slice(1).map((record, sourceSeq) => [sourceSeq, record]));
  const projectedSeqs = new Set();
  for (const message of session.messages) {
    const source = sourceBySeq.get(message.source_event_seq);
    assert.ok(source, `${name} transcript source sequence ${message.source_event_seq} exists`);
    assert.ok(!projectedSeqs.has(message.source_event_seq), `${name} projects a surface row only once`);
    projectedSeqs.add(message.source_event_seq);
    const original = source.type === 'user/message' ? source.data : source.data.message;
    assert.equal(message.role, original.role, `${name} preserves transcript role`);
    assert.equal(message.source_message_id, original.id, `${name} preserves message identity`);
  }

  const advertised = new Map();
  for (const row of sourceRows.slice(1)) {
    if (row.type !== 'assistant/message') continue;
    for (const block of row.data.message.content) {
      if (block.type === 'tool-call') advertised.set(block.id, { name: block.name, arguments: block.arguments });
    }
  }
  const started = new Map();
  const settledCalls = new Set();
  const ptc = new Map();
  const workflowRuns = new Map();
  const workflowAgents = new Map();
  const subagentCatalog = new Set();
  for (const [index, row] of sourceRows.slice(1).entries()) {
    if (row.type === 'tool/call') {
      const call = advertised.get(row.data.callId);
      assert.deepEqual(call, { name: row.data.name, arguments: row.data.arguments }, `${name} tool/call correlation at ${index}`);
      assert.ok(!started.has(row.data.callId), `${name} starts a tool call once`);
      started.set(row.data.callId, row.data);
    } else if (row.type === 'tool/result') {
      const callId = row.data.message.toolCallId;
      assert.ok(advertised.has(callId), `${name} tool result has an advertised assistant call`);
      const call = started.get(callId);
      assert.ok(call, `${name} tool result follows tool/call`);
      assert.ok(!settledCalls.has(callId), `${name} tool call settles once`);
      assert.equal(row.data.message.source.kind, 'tool', `${name} result source kind`);
      assert.equal(row.data.message.source.callId, callId, `${name} result source call id`);
      assert.equal(row.data.message.toolCallId, callId, `${name} result message call id`);
      assert.equal(row.data.turn, call.turn, `${name} result turn`);
      assert.equal(row.data.step, call.step, `${name} result step`);
      for (const run of workflowRuns.values()) {
        if (run.ownerCallId === callId) assert.ok(run.ended, `${name} foreground workflow ends before its tool result`);
      }
      settledCalls.add(callId);
    } else if (row.type === 'tool/ptc-dispatch-start') {
      assert.ok(!ptc.has(row.data.subCallId), `${name} PTC subcall starts once`);
      assert.ok(started.has(row.data.rootCallId), `${name} PTC root call has started`);
      assert.ok(!settledCalls.has(row.data.rootCallId), `${name} PTC root is still open`);
      if (row.data.parentCallId !== row.data.rootCallId) {
        const parent = ptc.get(row.data.parentCallId);
        assert.ok(parent, `${name} PTC parent has started`);
        assert.ok(!parent.settled, `${name} PTC parent remains open`);
      }
      ptc.set(row.data.subCallId, { ...row.data, settled: false });
    } else if (row.type === 'tool/ptc-dispatch') {
      const prior = ptc.get(row.data.subCallId);
      assert.ok(prior, `${name} PTC result has a start`);
      for (const key of ['rootCallId', 'parentCallId', 'name', 'arguments']) {
        assert.deepEqual(row.data[key], prior[key], `${name} PTC result preserves ${key}`);
      }
      assert.ok(!settledCalls.has(row.data.rootCallId), `${name} PTC result has an open root`);
      if (row.data.parentCallId !== row.data.rootCallId) {
        const parent = ptc.get(row.data.parentCallId);
        assert.ok(parent && !parent.settled, `${name} PTC result has an open parent`);
      }
      assert.ok(!prior.settled, `${name} PTC result settles once`);
      for (const child of ptc.values()) {
        if (child.parentCallId === row.data.subCallId) assert.ok(child.settled, `${name} PTC parent waits for children`);
      }
      prior.settled = true;
    } else if (row.type === 'subagent/catalog') {
      assert.ok(!subagentCatalog.has(row.data.childId), `${name} child catalog appears once`);
      subagentCatalog.add(row.data.childId);
    } else if (row.type === 'tool-workflow/run-start') {
      assert.ok(!workflowRuns.has(row.data.runId), `${name} workflow run starts once`);
      const owners = [...started.entries()].filter(([callId, call]) => call.name === 'workflow' && !settledCalls.has(callId));
      assert.equal(owners.length, 1, `${name} workflow has one open owner call`);
      const [ownerCallId, ownerCall] = owners[0];
      assert.equal(JSON.parse(ownerCall.arguments).meta.name, row.data.name, `${name} workflow name matches owner meta`);
      workflowRuns.set(row.data.runId, { ownerCallId, ended: false });
    } else if (row.type === 'tool-workflow/agent-start') {
      const run = workflowRuns.get(row.data.runId);
      assert.ok(run && !run.ended, `${name} workflow agent belongs to an open run`);
      const key = `${row.data.runId}:${row.data.seq}`;
      assert.ok(!workflowAgents.has(key), `${name} workflow agent starts once`);
      assert.ok(subagentCatalog.has(row.data.childId), `${name} workflow agent has catalog metadata`);
      workflowAgents.set(key, row.data.runId);
    } else if (row.type === 'tool-workflow/agent-end') {
      const key = `${row.data.runId}:${row.data.seq}`;
      assert.ok(workflowAgents.has(key), `${name} workflow agent result has a start`);
      assert.equal(workflowAgents.get(key), row.data.runId, `${name} workflow agent result run id`);
      workflowAgents.delete(key);
    } else if (row.type === 'tool-workflow/run-end') {
      const run = workflowRuns.get(row.data.runId);
      assert.ok(run && !run.ended, `${name} workflow result has a unique start`);
      assert.ok(![...workflowAgents.values()].includes(row.data.runId), `${name} workflow run waits for agents`);
      run.ended = true;
    }
  }
  assert.equal([...ptc.values()].filter((dispatch) => !dispatch.settled).length, 0, `${name} PTC dispatches settle`);
  assert.equal([...workflowRuns.values()].filter((run) => !run.ended).length, 0, `${name} workflow runs settle`);
  assert.equal(workflowAgents.size, 0, `${name} workflow agents settle`);
  assert.equal(settledCalls.size, started.size, `${name} all started calls have one result`);
  assert.equal(session.pending_tool_calls.length, 0, `${name} has no invented pending tool work`);
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

test('catalog projection rejects altered mod admissions and malformed inert metadata atomically', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const before = await host.call('session_list');
  const claude = await readFile(
    new URL('../fixtures/upstream-session-v4/claude-code-mods/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const multimodal = await readFile(
    new URL('../fixtures/upstream-session-v4/multimodal-spill-ends/session.v4.jsonl', import.meta.url),
    'utf8',
  );
  const advanced = await readFile(
    new URL('../fixtures/upstream-session-v4/advanced-toolchain/session.v4.jsonl', import.meta.url),
    'utf8',
  );

  const modifiedAdmissions = [
    (rows) => { rows.find((row) => row.type === 'user/message' && row.data.id === '{{message:1}}').data.id = 'forged-user-id'; },
    (rows) => { rows.find((row) => row.type === 'user/message' && row.data.id === '{{message:1}}').data.source.kind = 'runtime-context'; },
    (rows) => { rows.find((row) => row.type === 'user/message' && row.data.id === '{{message:1}}').data.content[0].text = 'rewritten original prompt'; },
  ];
  for (const mutate of modifiedAdmissions) {
    const rows = structuredClone(claude.trimEnd().split('\n').map((line) => JSON.parse(line)));
    mutate(rows);
    const rejected = await host.call('session_import', { jsonl: encodeSnapshotRows(rows) });
    assert.equal(rejected.ok, false);
    assert.match(rejected.error, /inbox|claim/i);
  }

  const malformedImages = [
    (rows) => { rows.find((row) => row.type === 'tool/result').data.message.content.find((block) => block.type === 'image').attachment.mediaType = 'image/svg+xml'; },
    (rows) => { rows.find((row) => row.type === 'tool/result').data.message.content.find((block) => block.type === 'image').attachment.bytes = -1; },
    (rows) => { rows.find((row) => row.type === 'tool/result').data.message.content.find((block) => block.type === 'image').attachment.name = 'local name'; },
  ];
  for (const mutate of malformedImages) {
    const rows = structuredClone(multimodal.trimEnd().split('\n').map((line) => JSON.parse(line)));
    mutate(rows);
    const rejected = await host.call('session_import', { jsonl: encodeSnapshotRows(rows) });
    assert.equal(rejected.ok, false);
    assert.match(rejected.error, /image|attachment/i);
  }

  const badPtc = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  badPtc.find((row) => row.type === 'tool/ptc-dispatch').data.name = 'forged_tool';
  const rejectedPtc = await host.call('session_import', { jsonl: encodeSnapshotRows(badPtc) });
  assert.equal(rejectedPtc.ok, false);
  assert.match(rejectedPtc.error, /PTC dispatch result differs from its start/);

  const badPtcAlias = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  badPtcAlias.find((row) => row.type === 'tool/ptc-dispatch-start').data.subCallId = 'advanced-code';
  const rejectedPtcAlias = await host.call('session_import', { jsonl: encodeSnapshotRows(badPtcAlias) });
  assert.equal(rejectedPtcAlias.ok, false);
  assert.match(rejectedPtcAlias.error, /Malformed or duplicate Session v4 PTC dispatch start/);

  const badPtcError = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  const ptcResult = badPtcError.find((row) => row.type === 'tool/ptc-dispatch');
  ptcResult.data.error = { name: 'FixtureError', code: 'FIXTURE_ERROR' };
  const rejectedPtcError = await host.call('session_import', { jsonl: encodeSnapshotRows(badPtcError) });
  assert.equal(rejectedPtcError.ok, false);
  assert.match(rejectedPtcError.error, /PTC result has an error with isError=false/);

  const closedRootEarly = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  const earlyRootResultIndex = closedRootEarly.findIndex((row) => row.type === 'tool/result' && row.data.message.toolCallId === 'advanced-code');
  closedRootEarly.splice(earlyRootResultIndex, 1);
  const ptcResultIndex = closedRootEarly.findIndex((row) => row.type === 'tool/ptc-dispatch');
  closedRootEarly.splice(ptcResultIndex, 0, {
    ...JSON.parse(advanced.trimEnd().split('\n').find((line) => {
      const row = JSON.parse(line);
      return row.type === 'tool/result' && row.data.message.toolCallId === 'advanced-code';
    })),
  });
  const rejectedEarlyRoot = await host.call('session_import', { jsonl: encodeSnapshotRows(closedRootEarly) });
  assert.equal(rejectedEarlyRoot.ok, false);
  assert.match(rejectedEarlyRoot.error, /root tool result precedes nested PTC settlement|still-open root tool call/);

  const closedPtcParentEarly = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  const parentStartIndex = closedPtcParentEarly.findIndex((row) => row.type === 'tool/ptc-dispatch-start');
  const parentStart = structuredClone(closedPtcParentEarly[parentStartIndex]);
  const parentResultIndex = closedPtcParentEarly.findIndex((row) => row.type === 'tool/ptc-dispatch');
  const parentResult = structuredClone(closedPtcParentEarly[parentResultIndex]);
  closedPtcParentEarly.splice(parentResultIndex, 1);
  const childStart = structuredClone(parentStart);
  childStart.data.parentCallId = parentStart.data.subCallId;
  childStart.data.subCallId = 'nested-ptc-call';
  childStart.data.name = 'nested-read';
  const childResult = structuredClone(parentResult);
  childResult.data.parentCallId = parentStart.data.subCallId;
  childResult.data.subCallId = 'nested-ptc-call';
  childResult.data.name = 'nested-read';
  closedPtcParentEarly.splice(parentStartIndex + 1, 0, childStart, parentResult, childResult);
  const rejectedEarlyPtcParent = await host.call('session_import', { jsonl: encodeSnapshotRows(closedPtcParentEarly) });
  assert.equal(rejectedEarlyPtcParent.ok, false);
  assert.match(rejectedEarlyPtcParent.error, /PTC parent settles before its nested child/);

  const badWorkflow = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  badWorkflow.find((row) => row.type === 'tool-workflow/agent-end').data.runId = 'missing-run';
  const rejectedWorkflow = await host.call('session_import', { jsonl: encodeSnapshotRows(badWorkflow) });
  assert.equal(rejectedWorkflow.ok, false);
  assert.match(rejectedWorkflow.error, /workflow agent end has no open run/);

  const badWorkflowName = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  badWorkflowName.find((row) => row.type === 'tool-workflow/run-start').data.name = 'forged-workflow-name';
  const rejectedWorkflowName = await host.call('session_import', { jsonl: encodeSnapshotRows(badWorkflowName) });
  assert.equal(rejectedWorkflowName.ok, false);
  assert.match(rejectedWorkflowName.error, /workflow run name differs from owner meta\.name/);

  const earlyWorkflowResult = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  const workflowResultIndex = earlyWorkflowResult.findIndex((row) => row.type === 'tool/result' && row.data.message.toolCallId === 'advanced-workflow');
  const [workflowResult] = earlyWorkflowResult.splice(workflowResultIndex, 1);
  const workflowRunEndIndex = earlyWorkflowResult.findIndex((row) => row.type === 'tool-workflow/run-end');
  earlyWorkflowResult.splice(workflowRunEndIndex, 0, workflowResult);
  const rejectedEarlyWorkflowResult = await host.call('session_import', { jsonl: encodeSnapshotRows(earlyWorkflowResult) });
  assert.equal(rejectedEarlyWorkflowResult.ok, false);
  assert.match(rejectedEarlyWorkflowResult.error, /foreground workflow result precedes run-end/);

  const backgroundWorkflow = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  const workflowCall = backgroundWorkflow.find((row) => row.type === 'tool/call' && row.data.callId === 'advanced-workflow');
  const workflowArguments = JSON.parse(workflowCall.data.arguments);
  workflowArguments.run_in_background = true;
  workflowCall.data.arguments = JSON.stringify(workflowArguments);
  const assistantCall = backgroundWorkflow.find((row) => row.type === 'assistant/message' && row.data.message.content.some((block) => block.id === 'advanced-workflow'));
  assistantCall.data.message.content.find((block) => block.id === 'advanced-workflow').arguments = workflowCall.data.arguments;
  const rejectedBackgroundWorkflow = await host.call('session_import', { jsonl: encodeSnapshotRows(backgroundWorkflow) });
  assert.equal(rejectedBackgroundWorkflow.ok, false);
  assert.match(rejectedBackgroundWorkflow.error, /Background Session v4 workflow runs are outside the supported import subset/);

  const unknownWorkflowFamily = structuredClone(advanced.trimEnd().split('\n').map((line) => JSON.parse(line)));
  unknownWorkflowFamily.push({ type: 'tool-workflow/agent-paused', data: { runId: 'unknown' }, ignorable: true });
  const rejectedUnknownWorkflow = await host.call('session_import', { jsonl: encodeSnapshotRows(unknownWorkflowFamily) });
  assert.equal(rejectedUnknownWorkflow.ok, false);
  assert.match(rejectedUnknownWorkflow.error, /Unsupported Session v4 execution correlation/);

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
  const beforePruneAttempt = await host.session(session.id);
  const attemptedPrune = await host.call('session_prune_tool_results', { session_id: session.id });
  assert.equal(attemptedPrune.ok, false);
  assert.match(attemptedPrune.error, /read-only/i);
  assert.deepEqual(await host.session(session.id), beforePruneAttempt,
    'the native pruning operation cannot mutate imported Session v4 history');
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

test('all pinned upstream Session v4 catalog snapshots import and reopen as correlated inert transcripts', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-catalog-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const hosts = [];
  t.after(async () => {
    for (const item of hosts) await item.close();
    await rm(temporary, { recursive: true, force: true });
  });
  const first = await newHost(t, dataDir);
  hosts.push(first);
  const imported = new Map();

  for (const name of upstreamCatalogSnapshots) {
    const directory = new URL(`../fixtures/upstream-session-v4/${name}/`, import.meta.url);
    const [jsonl, provenanceText] = await Promise.all([
      readFile(new URL('session.v4.jsonl', directory), 'utf8'),
      readFile(new URL('provenance.json', directory), 'utf8'),
    ]);
    const provenance = JSON.parse(provenanceText);
    assert.equal(provenance.repository, 'https://github.com/deepseek-ai/deepseek-harness', name);
    assert.equal(provenance.commit, '5badb15009ae1756c3afe0ae0cef1faafc290ccc', name);
    assert.equal(provenance.path, `snapshots/session/${name}/session.v4.jsonl`, name);
    assert.equal(
      createHash('sha256').update(jsonl).digest('hex'),
      provenance.sha256,
      `${name} must remain byte-for-byte identical to its pinned upstream snapshot`,
    );

    const result = await first.host.call('session_import', { jsonl });
    assert.equal(result.ok, true, `${name}: ${result.error}`);
    const session = result.result;
    assert.equal(session.source_format, 'deepseek-session-v4', name);
    assert.equal(session.status, 'completed', name);
    const [expectedMessages, expectedCalls, expectedResults] = expectedCatalogShape.get(name);
    assert.equal(session.messages.length, expectedMessages, `${name} transcript size`);
    assert.equal(
      session.messages.reduce((count, message) => count + (message.tool_calls?.length ?? 0), 0),
      expectedCalls,
      `${name} advertised tool calls`,
    );
    assert.equal(session.messages.filter((message) => message.role === 'tool').length, expectedResults, `${name} tool results`);
    assertCatalogTranscriptCorrelation(session, jsonl, name);
    imported.set(name, { id: session.id, session, jsonl });
  }

  const advanced = imported.get('advanced-toolchain').session;
  const advancedTypes = advanced.events
    .filter((event) => event.type === 'upstream/event')
    .map((event) => event.data.record.type);
  for (const kind of [
    'tool/ptc-dispatch-start', 'tool/ptc-dispatch', 'subagent/catalog',
    'tool-workflow/run-start', 'tool-workflow/agent-start',
    'tool-workflow/agent-end', 'tool-workflow/run-end',
  ]) assert.ok(advancedTypes.includes(kind), `advanced-toolchain retains ${kind}`);

  const claude = imported.get('claude-code-mods').session;
  assert.ok(claude.messages.some((message) => message.role === 'user' && message.content.includes('Context from the snapshot-guard mod')));
  const multimodal = imported.get('multimodal-spill-ends').session;
  const imageResult = multimodal.messages.find((message) => message.role === 'tool');
  assert.ok(imageResult.content.includes('unresolved image attachment sha256:999f1d1527ee7e79266f16add5430fff76b1225d742464a5b1ff1f02971bb8ee'));
  assert.equal((imageResult.content.match(/unresolved image attachment/g) ?? []).length, 2);
  for (const name of ['office-skills', 'office-skills-no-renderer', 'skill-load', 'windows-acl-skill']) {
    assert.ok(imported.get(name).session.messages.some((message) => message.role === 'user' && message.content.includes('<available_skills>')), name);
  }

  assert.equal(first.host.activeCount, 0);
  assert.equal(first.fetchCalls(), 0);
  await first.close();

  const reopened = await newHost(t, dataDir);
  hosts.push(reopened);
  for (const { id, session } of imported.values()) {
    assert.deepEqual(await reopened.host.session(id), session);
  }
  assert.equal(reopened.host.activeCount, 0);
  assert.equal(reopened.fetchCalls(), 0);
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

test('Session v4 retry schedules and starts remain inert, lossless, and restorable', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-v4-retry-restore-'));
  const dataDir = path.join(temporary, '.dsh.mbt');
  const first = await newHost(t, dataDir);
  const provenance = JSON.parse(await readFile(new URL('../fixtures/upstream-session-v4/provider-retry/provenance.json', import.meta.url), 'utf8'));
  assert.equal(createHash('sha256').update(retryNativeFixture).digest('hex'), provenance.fixtures['native/session.v4.jsonl'].sha256);
  assert.equal(createHash('sha256').update(retryShorthandFixture).digest('hex'), provenance.fixtures['shorthand/session.v4.jsonl'].sha256);

  const variants = [
    ['native completed retry', retryNativeFixture, 'completed'],
    ['snapshot shorthand completed retry', retryShorthandFixture, 'completed'],
    ['completed always-mode retry', mutateRetryArchive((events) => {
      const schedule = events.find((event) => event.type === 'llm/retry');
      schedule.data.mode = 'always';
      delete schedule.data.maxRetries;
      schedule.data.delayMs = 10000.5;
    }), 'completed'],
    ['two sequential retries', retryArchive({ attempts: 2 }), 'completed'],
    ['terminal scheduled retry without start', retryArchive({ terminal: true, started: false }), 'failed'],
    ['native retry after closed assistant-less step', retryArchive({ terminal: true, retryAfterStepEnd: true }), 'failed'],
    ['shorthand retry after closed assistant-less step', retryArchive({ terminal: true, retryAfterStepEnd: true, shorthand: true }), 'failed'],
    ['interrupted retry wait', retryArchive({ interrupted: true, started: false }), 'failed'],
    ['interrupted retry after start', retryArchive({ interrupted: true, started: true }), 'failed'],
  ];
  const imported = [];
  for (const [name, jsonl, expectedStatus] of variants) {
    const result = await first.host.call('session_import', { jsonl });
    assert.equal(result.ok, true, `${name}: ${result.error}`);
    const session = result.result;
    assert.equal(session.status, expectedStatus, name);
    assert.deepEqual(session.messages.map((item) => item.role), expectedStatus === 'completed' ? ['user', 'assistant'] : ['user'], name);
    assert.deepEqual(session.pending_tool_calls, [], name);
    assertCatalogTranscriptCorrelation(session, jsonl, name);
    const sourceRows = jsonl.trimEnd().split('\n').slice(1).map((line) => JSON.parse(line));
    const sourceEvents = session.events.filter((event) => event.type === 'upstream/event');
    const attempts = sourceEvents.filter((event) => event.data.record.type === 'assistant/attempt');
    const schedules = sourceEvents.filter((event) => event.data.record.type === 'llm/retry');
    const starts = sourceEvents.filter((event) => event.data.record.type === 'llm/retry-started');
    assert.equal(schedules.length, expectedStatus === 'completed' && name === 'two sequential retries' ? 2 : 1, name);
    assert.equal(starts.length, sourceRows.filter((event) => event.type === 'llm/retry-started').length, name);
    if (name.includes('retry after closed assistant-less step')) {
      const stepEndIndex = sourceRows.findIndex((event) => event.type === 'step/end');
      const retryIndex = sourceRows.findIndex((event) => event.type === 'llm/retry');
      const startedIndex = sourceRows.findIndex((event) => event.type === 'llm/retry-started');
      assert.ok(stepEndIndex < retryIndex && retryIndex < startedIndex, name);
    }
    assert.deepEqual(schedules.map((event) => event.data.record.data.retry), schedules.map((_, index) => index + 1), name);
    for (const schedule of schedules) {
      assert.deepEqual(schedule.data.record.data.failure, sourceRows[schedule.data.source_seq].data.failure, name);
      assert.equal(schedule.data.raw, jsonl.trimEnd().split('\n')[schedule.data.source_seq + 1], name);
    }
    if (name === 'native completed retry' || name === 'snapshot shorthand completed retry') {
      assert.equal(attempts.length, 1, name);
      assert.deepEqual(attempts[0].data.record.data.stream[1].chunk.reason.failure, schedules[0].data.record.data.failure, name);
      assert.equal(session.messages[1].content, 'Recovered.', name);
    }
    if (name === 'two sequential retries') {
      assert.equal(schedules[1].data.record.data.retryId, schedules[0].data.record.data.retryId, name);
      assert.equal(schedules[1].data.record.data.delayMs, 10000.5, name);
      assert.equal(schedules[1].data.record.data.failure.providerRetryAfterMs, 250.5, name);
    }
    imported.push({ id: session.id, session, jsonl });
    assert.equal(first.host.activeCount, 0, name);
    assert.equal(first.fetchCalls(), 0, name);
  }

  const canonical = imported[0].session;
  const forged = JSON.parse(first.facade.snapshot());
  const stored = forged.sessions.find((session) => session.id === canonical.id);
  const retrySource = stored.events.find((event) => event.type === 'upstream/event' && event.data.record.type === 'llm/retry');
  retrySource.data.record.data.retry = 2;
  retrySource.data.raw = JSON.stringify(retrySource.data.record);
  const rejectedRestore = JSON.parse(first.facade.restore(JSON.stringify(forged)));
  assert.equal(rejectedRestore.ok, false);
  assert.match(rejectedRestore.error, /policy chain must begin at retry 1/);
  assert.deepEqual(await first.host.session(canonical.id), canonical);

  await first.close();
  const reopened = await newHost(t, dataDir);
  for (const { id, session } of imported) assert.deepEqual(await reopened.host.session(id), session);
  assert.equal(reopened.host.activeCount, 0);
  assert.equal(reopened.fetchCalls(), 0);
  t.after(() => rm(temporary, { recursive: true, force: true }));
});

test('Session v4 retry event correlation, ordering, and payload constraints reject atomically', async (t) => {
  const { host, fetchCalls } = await newHost(t);
  const retry = (events) => events.find((event) => event.type === 'llm/retry');
  const retryStart = (events) => events.find((event) => event.type === 'llm/retry-started');
  const invalidArchives = [
    ['provider must match request/header', mutateRetryArchive((events) => { retry(events).data.provider = 'other-provider'; }), /provider differs from the request\/header/],
    ['closed assistant-less step still validates retry correlation', retryArchive({ terminal: true, retryAfterStepEnd: true, mutateFirstRetry: (event) => { event.data.provider = 'other-provider'; } }), /provider differs from the request\/header/],
    ['ignorable does not bypass retry validation', retryArchive({ mutateFirstRetry: (event) => { event.ignorable = true; event.data.retry = 2; } }), /policy chain must begin at retry 1/],
    ['retry count starts at one', mutateRetryArchive((events) => { retry(events).data.retry = 2; }), /policy chain must begin at retry 1/],
    ['normal mode requires maxRetries', mutateRetryArchive((events) => { delete retry(events).data.maxRetries; }), /requires maxRetries/],
    ['normal maxRetries must be positive', mutateRetryArchive((events) => { retry(events).data.maxRetries = 0; }), /positive safe integer/],
    ['retry cannot exceed maxRetries', mutateRetryArchive((events) => { retry(events).data.maxRetries = 1; retry(events).data.retry = 2; }), /exceeds maxRetries/],
    ['unsupported mode is rejected', mutateRetryArchive((events) => { retry(events).data.mode = 'sometimes'; }), /mode must be normal or always/],
    ['retry identity is required', mutateRetryArchive((events) => { retry(events).data.retryId = ''; }), /retryId must not be empty/],
    ['retry step must match current step', mutateRetryArchive((events) => { retry(events).data.step = 2; }), /does not match the current turn and step/],
    ['delay must be numeric', mutateRetryArchive((events) => { retry(events).data.delayMs = '1'; }), /delayMs must be a finite number/],
    ['delay cannot be negative', mutateRetryArchive((events) => { retry(events).data.delayMs = -1; }), /delayMs must be finite and non-negative/],
    ['failure status uses an HTTP status code', mutateRetryArchive((events) => { retry(events).data.failure.status = 600; }), /retry failure status is outside the supported range/],
    ['failure retry-after must be positive', mutateRetryArchive((events) => { retry(events).data.failure.providerRetryAfterMs = 0; }), /providerRetryAfterMs must be positive and finite/],
    ['failure rejects unsupported metadata', mutateRetryArchive((events) => { retry(events).data.failure.unknown = true; }), /Unsupported Session v4 LLM retry failure field/],
    ['retry start must follow a schedule', mutateRetryArchive((events) => {
      const index = events.indexOf(retryStart(events));
      const [start] = events.splice(index, 1);
      events.splice(events.indexOf(retry(events)), 0, start);
    }), /has no prior scheduled attempt/],
    ['retry start coordinates must match its schedule', mutateRetryArchive((events) => { retryStart(events).data.step = 2; }), /changes its scheduled coordinates/],
    ['retry start cannot duplicate a schedule', mutateRetryArchive((events) => {
      const index = events.indexOf(retryStart(events));
      events.splice(index + 1, 0, structuredClone(retryStart(events)));
    }), /duplicates a scheduled attempt/],
    ['policy chain attempt counts are contiguous', retryArchive({ attempts: 2, mutateSecondRetry: (event) => { event.data.retry = 3; event.data.maxRetries = 3; } }), /continue its policy chain/],
    ['a scheduled attempt cannot be duplicated', retryArchive({ attempts: 2, mutateSecondRetry: (event) => { event.data.retry = 1; } }), /continue its policy chain/],
    ['policy chain preserves its retry identity', retryArchive({ attempts: 2, mutateSecondRetry: (event) => { event.data.retryId = 'different-retry'; } }), /continue its policy chain/],
    ['retry ids cannot be reused across policy chains', retryArchive({ attempts: 2, mutateSecondRetry: (event) => { event.data.retry = 1; event.data.policyKey = 'new-policy'; } }), /reuses a retryId across policy chains/],
    ['always mode omits maxRetries', mutateRetryArchive((events) => { retry(events).data.mode = 'always'; }), /must omit maxRetries/],
  ];
  const before = await host.call('session_list');
  for (const [name, jsonl, expected] of invalidArchives) {
    const rejected = await host.call('session_import', { jsonl });
    assert.equal(rejected.ok, false, name);
    assert.match(rejected.error, expected, name);
    assert.deepEqual(await host.call('session_list'), before, name);
  }
  assert.equal(host.activeCount, 0);
  assert.equal(fetchCalls(), 0);
});
