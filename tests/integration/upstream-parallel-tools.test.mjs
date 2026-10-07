import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';
import { pathToFileURL } from 'node:url';

const upstreamPath = '../fixtures/upstream-session-v4/parallel-tool-calls/session.v4.jsonl';
const upstreamEvents = (await readFile(new URL(upstreamPath, import.meta.url), 'utf8'))
  .trimEnd().split('\n').map((line) => JSON.parse(line));
const inbox = upstreamEvents.find((event) => event.type === 'agent/inbox/spliced' && event.data.inserted?.length);
const prompt = inbox.data.inserted[0].content.find((block) => block.type === 'text').text;
const modelMessages = upstreamEvents
  .filter((event) => event.type === 'assistant/message')
  .map((event) => event.data.message);
const parallelCalls = modelMessages[0].content
  .filter((block) => block.type === 'tool-call')
  .map((block) => ({ id: block.id, name: block.name, input: JSON.parse(block.arguments) }));
const finalText = modelMessages[1].content.find((block) => block.type === 'text').text;

async function freshFacade() {
  return import(`${pathToFileURL(defaultModulePath).href}?test=${randomUUID()}`);
}

function messageResponse(normalized) {
  const content = [];
  if (normalized.reasoning) content.push({ type: 'thinking', thinking: normalized.reasoning });
  if (normalized.content) content.push({ type: 'text', text: normalized.content });
  for (const tool of normalized.tool_calls) content.push({ type: 'tool_use', ...tool });
  return {
    id: 'parallel-fixture', type: 'message', role: 'assistant', content,
    stop_reason: normalized.tool_calls.length ? 'tool_use' : 'end_turn',
    usage: { input_tokens: 10, output_tokens: 5 },
  };
}

test('parallel tool results can be pruned for future requests without changing history or replaying IO', async (t) => {
  assert.equal(parallelCalls.length, 2);
  assert.ok(parallelCalls.every((tool) => tool.name === 'read'));
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-upstream-parallel-'));
  await writeFile(path.join(temporary, 'a.txt'), `${'a'.repeat(10_000)}\n`);
  await writeFile(path.join(temporary, 'b.txt'), `${'b'.repeat(10_000)}\n`);
  let host;
  let server;
  t.after(async () => {
    try { await host?.close(); }
    finally {
      try { if (server?.listening) await new Promise((resolve) => server.close(resolve)); }
      finally { await rm(temporary, { recursive: true, force: true }); }
    }
  });

  let consumed = 0;
  let serverFailure;
  const requests = [];
  const completions = [
    { content: '', tool_calls: parallelCalls, finish_reason: 'tool_calls' },
    { content: finalText, tool_calls: [], finish_reason: 'stop' },
    { content: 'continued after pruning', tool_calls: [], finish_reason: 'stop' },
    { content: 'continued after reload', tool_calls: [], finish_reason: 'stop' },
  ];
  server = http.createServer(async (request, response) => {
    try {
      assert.equal(request.url, '/anthropic/v1/messages');
      assert.equal(request.method, 'POST');
      let text = '';
      for await (const chunk of request) text += chunk;
      requests.push(JSON.parse(text));
      assert.ok(consumed < completions.length, 'all fixture responses must be consumed exactly once');
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(messageResponse(completions[consumed++])));
    } catch (error) {
      serverFailure = error;
      response.writeHead(500, { 'content-type': 'text/plain' });
      response.end(error.message);
    }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');

  const facade = await freshFacade();
  const options = {
    facade, workspace: temporary, dataDir: path.join(temporary, '.dsh.mbt'),
    mode: 'deepseek', model: 'fixture-model',
    baseURL: `http://127.0.0.1:${server.address().port}/anthropic`,
  };
  host = await createHost(options);
  assert.equal((await host.call('session_create', { id: 'upstream-parallel' })).ok, true);
  assert.equal((await host.call('session_send', { session_id: 'upstream-parallel', prompt })).ok, true);
  const completed = await host.waitForSession('upstream-parallel', { signal: AbortSignal.timeout(10_000) });

  assert.ifError(serverFailure);
  assert.equal(completed.status, 'completed');
  assert.equal(consumed, 2);
  assert.equal(completed.messages.at(-1).content, finalText);
  const results = completed.messages.filter((message) => message.role === 'tool');
  assert.deepEqual(results.map((message) => message.tool_call_id), parallelCalls.map((tool) => tool.id));
  assert.ok(results[0].content.includes(`1: ${'a'.repeat(100)}`));
  assert.ok(results[1].content.includes(`1: ${'b'.repeat(100)}`));
  assert.ok(results.every((message) => [...message.content].length > 8192));

  const callIndexes = parallelCalls.map((tool) => completed.events.findIndex((event) =>
    event.type === 'tool/call' && event.data.id === tool.id));
  const resultIndexes = parallelCalls.map((tool) => completed.events.findIndex((event) =>
    event.type === 'tool/result' && event.data.tool_call_id === tool.id));
  assert.ok(callIndexes.every((index) => index >= 0));
  assert.ok(resultIndexes.every((index) => index >= 0));
  assert.ok(Math.max(...callIndexes) < Math.min(...resultIndexes));
  const followupBlocks = requests[1].messages.flatMap((message) => message.content ?? []);
  assert.deepEqual(
    followupBlocks.filter((block) => block.type === 'tool_result').map((block) => block.content[0].text),
    results.map((message) => message.content),
  );
  assert.deepEqual(
    followupBlocks.filter((block) => block.type === 'tool_result').map((block) => block.tool_use_id),
    parallelCalls.map((tool) => tool.id),
  );

  const threshold = 120;
  const head = 30;
  const tail = 20;
  const pruned = await host.call('session_prune_tool_results', {
    session_id: 'upstream-parallel',
    threshold_chars: threshold,
    head_chars: head,
    tail_chars: tail,
  });
  assert.equal(pruned.ok, true, pruned.error);
  assert.equal(pruned.result.pruned.length, 2);
  assert.deepEqual(
    pruned.result.pruned.map((entry) => entry.call_id),
    parallelCalls.map((tool) => tool.id),
  );
  assert.equal(consumed, 2, 'the manual pruning operation must not contact the provider');

  const rawAfterPrune = await host.session('upstream-parallel');
  const rawResults = rawAfterPrune.messages.filter((message) => message.role === 'tool');
  assert.deepEqual(rawResults, results, 'raw transcript keeps each full original tool result');
  assert.ok(rawResults.every((message) => [...message.content].length > 8192));
  const persisted = JSON.parse(await readFile(path.join(temporary, '.dsh.mbt', 'sessions.json'), 'utf8'));
  const durable = persisted.sessions.find((session) => session.id === 'upstream-parallel');
  assert.equal(durable.events.filter((event) => event.type === 'tool/result/pruned').length, 2,
    'host.call resolves only after the pruning events are checkpointed');

  assert.equal((await host.call('session_send', {
    session_id: 'upstream-parallel', prompt: 'Continue with the shortened tool results.',
  })).ok, true);
  const afterPrune = await host.waitForSession('upstream-parallel', { signal: AbortSignal.timeout(10_000) });
  assert.equal(afterPrune.status, 'completed');
  assert.equal(consumed, 3);
  const postPruneBlocks = requests[2].messages.flatMap((message) => message.content ?? []);
  const projectedResults = postPruneBlocks.filter((block) => block.type === 'tool_result');
  assert.deepEqual(projectedResults.map((block) => block.tool_use_id), parallelCalls.map((tool) => tool.id));
  assert.equal(projectedResults.length, 2);
  assert.ok(projectedResults.every((block) => [...block.content[0].text].length <= threshold));
  assert.ok(projectedResults.every((block) => block.content[0].text.includes('\n\n[... tool result middle pruned ...]\n\n')));
  assert.ok(projectedResults[0].content[0].text.startsWith(rawResults[0].content.slice(0, head)));
  assert.ok(projectedResults[1].content[0].text.endsWith(rawResults[1].content.slice(-tail)));
  assert.deepEqual(
    (await host.session('upstream-parallel')).messages.filter((message) => message.role === 'tool'),
    results,
    'provider projection does not replace raw transcript content',
  );

  const originalMessages = afterPrune.messages;
  await host.close();
  host = await createHost(options);
  const reopened = await host.session('upstream-parallel');
  assert.equal(reopened.status, 'completed');
  assert.deepEqual(reopened.messages, originalMessages);
  assert.equal(host.activeCount, 0);
  assert.equal(consumed, 3, 'reopen must not contact the provider or rerun either read');

  assert.equal((await host.call('session_send', {
    session_id: 'upstream-parallel', prompt: 'Check the saved projection after reload.',
  })).ok, true);
  const afterReload = await host.waitForSession('upstream-parallel', { signal: AbortSignal.timeout(10_000) });
  assert.equal(afterReload.status, 'completed');
  assert.equal(consumed, 4);
  const afterReloadBlocks = requests[3].messages.flatMap((message) => message.content ?? []);
  const reloadedResults = afterReloadBlocks.filter((block) => block.type === 'tool_result');
  assert.deepEqual(
    reloadedResults.map((block) => block.content[0].text),
    projectedResults.map((block) => block.content[0].text),
    'restore reconstructs the same provider-only projection',
  );
  assert.deepEqual(
    afterReload.events.filter((event) => event.type === 'tool/call').map((event) => event.data.id),
    parallelCalls.map((tool) => tool.id),
    'neither initial parallel read is replayed after reload',
  );
  assert.equal(afterReload.events.filter((event) => event.type === 'tool/result/pruned').length, 2);
});
