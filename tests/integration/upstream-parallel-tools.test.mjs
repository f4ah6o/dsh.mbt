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

test('upstream parallel tool fixture: read calls settle into model history in call order', async (t) => {
  assert.equal(parallelCalls.length, 2);
  assert.ok(parallelCalls.every((tool) => tool.name === 'read'));
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-upstream-parallel-'));
  await writeFile(path.join(temporary, 'a.txt'), 'alpha\n');
  await writeFile(path.join(temporary, 'b.txt'), 'beta\n');
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
  assert.ok(results[0].content.includes('1: alpha'));
  assert.ok(results[1].content.includes('1: beta'));

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

  const originalMessages = completed.messages;
  await host.close();
  host = await createHost(options);
  const reopened = await host.session('upstream-parallel');
  assert.equal(reopened.status, 'completed');
  assert.deepEqual(reopened.messages, originalMessages);
  assert.equal(host.activeCount, 0);
  assert.equal(consumed, 2, 'reopen must not contact the provider or rerun either read');
});
