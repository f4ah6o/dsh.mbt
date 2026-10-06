import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createHost, defaultModulePath } from '../../host/runtime.mjs';
import { pathToFileURL } from 'node:url';

const fixture = JSON.parse(await readFile(new URL('../fixtures/upstream-tool-call-turn.json', import.meta.url), 'utf8'));

async function freshFacade() {
  return import(`${pathToFileURL(defaultModulePath).href}?test=${randomUUID()}`);
}

function call(app, operation, input) {
  const reply = JSON.parse(app.dispatch(JSON.stringify({ operation, input })));
  assert.equal(reply.ok, true, reply.error);
  return reply.result;
}

function messageResponse(normalized) {
  const content = [];
  if (normalized.reasoning) content.push({ type: 'thinking', thinking: normalized.reasoning });
  if (normalized.content) content.push({ type: 'text', text: normalized.content });
  for (const tool of normalized.tool_calls) content.push({ type: 'tool_use', id: tool.id, name: tool.name, input: JSON.parse(tool.arguments) });
  return { id: 'fixture', type: 'message', role: 'assistant', content, stop_reason: normalized.tool_calls.length ? 'tool_use' : 'end_turn', usage: { input_tokens: 10, output_tokens: 10 } };
}

test('upstream fixture: Messages HTTP → approved real bash → next request → DONE → reopen', async (t) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'dsh-upstream-'));
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
  server = http.createServer(async (request, response) => {
    try {
      assert.equal(request.url, '/anthropic/v1/messages');
      assert.equal(request.method, 'POST');
      assert.equal(request.headers['anthropic-version'], '2023-06-01');
      let text = '';
      for await (const chunk of request) text += chunk;
      const body = JSON.parse(text);
      requests.push(body);
      assert.ok(consumed < fixture.completions.length, 'all fixture responses must be consumed exactly once');
      const reply = messageResponse(fixture.completions[consumed++]);
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(reply));
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
    allowShell: true, approveTools: ['bash'],
  };
  host = await createHost(options);
  const created = await host.call('session_create', { id: 'upstream-oracle', title: 'Upstream tool-call-turn' });
  assert.equal(created.ok, true);
  const sent = await host.call('session_send', { session_id: 'upstream-oracle', prompt: fixture.prompt });
  assert.equal(sent.ok, true, sent.error);
  const completed = await host.waitForSession('upstream-oracle', { signal: AbortSignal.timeout(10_000) });
  assert.ifError(serverFailure);
  assert.equal(completed.status, 'completed');
  assert.equal(consumed, 2);
  const tool = completed.messages.find((message) => message.role === 'tool');
  assert.equal(tool.tool_call_id, fixture.completions[0].tool_calls[0].id);
  assert.equal(tool.content, fixture.expected_tool_output);
  assert.equal(completed.messages.at(-1).content, 'DONE');
  assert.equal(requests[0].messages[0].content[0].text, fixture.prompt);
  const followupBlocks = requests[1].messages.flatMap((message) => message.content);
  assert.deepEqual(followupBlocks.filter((block) => block.type === 'tool_result').map((block) => block.content[0].text), [fixture.expected_tool_output]);
  assert.equal(completed.events.filter((event) => event.type === 'tool/approval/resolved').length, 1);
  const originalMessages = completed.messages;
  await host.close();
  host = await createHost(options);
  const reopened = await host.session('upstream-oracle');
  assert.equal(reopened.status, 'completed');
  assert.deepEqual(reopened.messages, originalMessages);
  assert.equal(host.activeCount, 0);
  assert.equal(consumed, 2, 'reopen must not contact the provider or rerun the shell');
});

test('old application effects cannot settle a new application lifetime', async () => {
  const app = await freshFacade();
  assert.equal(JSON.parse(app.start()).ok, true);
  call(app, 'session_create', { id: 'old' });
  call(app, 'session_send', { session_id: 'old', prompt: 'old prompt' });
  const oldEffect = JSON.parse(app.take_effects())[0];
  app.stop();
  assert.equal(JSON.parse(app.start()).ok, true);
  call(app, 'session_create', { id: 'new' });
  call(app, 'session_send', { session_id: 'new', prompt: 'new prompt' });
  const newEffect = JSON.parse(app.take_effects())[0];
  assert.notEqual(newEffect.id, oldEffect.id);
  const result = { ok: true, content: 'OLD RESPONSE', tool_calls: [], finish_reason: 'stop' };
  assert.equal(JSON.parse(app.complete(oldEffect.id, JSON.stringify(result))).ok, false);
  const current = call(app, 'session_get', { session_id: 'new' });
  assert.equal(current.status, 'running');
  assert.equal(current.messages.some((message) => message.content === 'OLD RESPONSE'), false);
  app.stop();
  assert.deepEqual(JSON.parse(app.take_effects()), []);
  assert.equal(JSON.parse(app.complete(newEffect.id, JSON.stringify(result))).ok, false);
});
