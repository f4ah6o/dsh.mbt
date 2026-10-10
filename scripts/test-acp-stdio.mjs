import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';

const binaryArgument = process.argv[2];
assert.ok(binaryArgument, 'pass the built native dsh executable as argv[2]');
const binary = path.resolve(binaryArgument);

const root = await mkdtemp(path.join(tmpdir(), 'dsh-acp-stdio-'));

function launch(name, options = {}) {
  const data = options.dataDir ?? path.join(root, `${name}-data`);
  const workspace = options.workspaceDir ?? path.join(root, `${name}-workspace`);
  return mkdir(workspace, { recursive: true }).then(() => {
    const args = ['acp'];
    if (options.provider !== true) args.push('--demo');
    if (options.provider === true) {
      args.push(
        '--mode', options.mode ?? 'openai',
        '--model', options.model ?? 'fixture-model',
        '--max-retries', String(options.maxRetries ?? 0),
      );
      if (options.baseURL) args.push('--base-url', options.baseURL);
    }
    args.push('--data-dir', data, '--workspace', workspace);
    if (options.extraArgs) args.push(...options.extraArgs);
    const env = { ...process.env, ...(options.env ?? {}), DSH_NATIVE_WORKER_BIN: binary };
    if (options.provider === true) {
      for (const key of ['DSH_MODE', 'DSH_MODEL', 'DSH_BASE_URL']) delete env[key];
      env.DSH_AUTH = 'api-key';
    }
    if (options.clearProviderKeys) {
      for (const key of ['DSH_API_KEY', 'DEEPSEEK_API_KEY', 'OPENAI_API_KEY']) delete env[key];
    }
    const child = spawn(binary, args, {
      cwd: workspace,
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const messages = [];
    const waiters = new Set();
    let buffer = '';
    let stderr = '';
    let exit = null;
    let resolveExit;
    const exited = new Promise(resolve => { resolveExit = resolve; });

    function settleWaiters() {
      for (const waiter of [...waiters]) {
        const match = messages.find(entry => !entry.used && waiter.predicate(entry.value));
        if (!match) continue;
        match.used = true;
        clearTimeout(waiter.timer);
        waiters.delete(waiter);
        waiter.resolve(match.value);
      }
    }

    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      buffer += chunk;
      for (;;) {
        const newline = buffer.indexOf('\n');
        if (newline < 0) break;
        const line = buffer.slice(0, newline).replace(/\r$/, '');
        buffer = buffer.slice(newline + 1);
        let value;
        try {
          value = JSON.parse(line);
        } catch (error) {
          child.kill('SIGKILL');
          throw new Error(`ACP stdout was not JSON: ${line}`, { cause: error });
        }
        messages.push({ value, used: false });
        settleWaiters();
      }
    });
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('close', (code, signal) => {
      exit = { code, signal };
      resolveExit(exit);
      for (const waiter of [...waiters]) {
        clearTimeout(waiter.timer);
        waiters.delete(waiter);
        waiter.reject(new Error(`ACP process exited early (${code ?? signal}): ${stderr}`));
      }
    });

    function waitFor(predicate, timeoutMs = 15000, label = 'ACP output') {
      const existing = messages.find(entry => !entry.used && predicate(entry.value));
      if (existing) {
        existing.used = true;
        return Promise.resolve(existing.value);
      }
      return new Promise((resolve, reject) => {
        const waiter = {
          predicate,
          resolve,
          reject,
          timer: setTimeout(() => {
            waiters.delete(waiter);
            reject(new Error(`timed out waiting for ${name} ${label}; stderr: ${stderr}; recent stdout: ${JSON.stringify(messages.slice(-5).map(entry => entry.value))}`));
          }, timeoutMs),
        };
        waiters.add(waiter);
        settleWaiters();
      });
    }

    let nextId = 100;
    function sendRequest(method, params) {
      const id = nextId++;
      const response = waitFor(value => value.id === id
        && value.method === undefined
        && ('result' in value || 'error' in value), 15000, `response to ${method} id ${id}`);
      child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
      return { id, response };
    }

    function sendNotification(method, params) {
      child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
    }

    function sendResponse(id, result) {
      child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
    }

    async function closeAndCheck() {
      child.stdin.end();
      if (exit === null) {
        let timer;
        try {
          await Promise.race([
            new Promise(resolve => child.once('close', resolve)),
            new Promise((_, reject) => {
              timer = setTimeout(
                () => reject(new Error(`ACP process did not stop at EOF: ${stderr}`)),
                15000,
              );
            }),
          ]);
        } finally {
          clearTimeout(timer);
        }
      }
      assert.equal(exit?.code, 0, stderr);
    }

    function waitForExit() {
      return exit === null ? exited : Promise.resolve(exit);
    }

    return {
      child,
      messages,
      waitFor,
      sendRequest,
      sendNotification,
      sendResponse,
      closeAndCheck,
      waitForExit,
      workspace,
      stderr: () => stderr,
    };
  });
}

try {
  const invalidArgsAgent = await launch('invalid-args', {
    extraArgs: ['--unknown-acp-option'],
  });
  invalidArgsAgent.child.stdin.end();
  const invalidArgsExit = await invalidArgsAgent.waitForExit();
  assert.equal(invalidArgsExit.code, 1);
  assert.equal(invalidArgsExit.signal, null);
  assert.deepEqual(invalidArgsAgent.messages, []);
  assert.match(invalidArgsAgent.stderr(), /native ACP arguments are invalid/);

  const agent = await launch('main');
  const beforeInitialize = agent.sendRequest('session/new', {
    cwd: agent.workspace,
    mcpServers: [],
  });
  assert.equal((await beforeInitialize.response).error.code, -32002);

  const initialize = agent.sendRequest('initialize', { protocolVersion: 1 });
  const initialized = await initialize.response;
  assert.equal(initialized.result.protocolVersion, 1);
  assert.deepEqual(
    Object.keys(initialized.result.agentCapabilities.sessionCapabilities).sort(),
    ['close', 'list', 'resume'],
  );
  assert.deepEqual(initialized.result.agentCapabilities.promptCapabilities, {
    image: false,
    audio: false,
    embeddedContext: false,
  });
  const repeatedInitialize = agent.sendRequest('initialize', { protocolVersion: 1 });
  assert.equal((await repeatedInitialize.response).error.code, -32600);

  agent.child.stdin.write(`${JSON.stringify({
    jsonrpc: '2.0', id: 77, result: {}, error: { code: -1, message: 'malformed response' },
  })}\n`);
  const deep = `[`.repeat(25) + '0' + `]`.repeat(25);
  agent.child.stdin.write(`{"jsonrpc":"2.0","id":78,"method":"initialize","params":{"nested":${deep}}}\n`);
  const depthError = await agent.waitFor(value => value.id === null && value.error?.code === -32700);
  assert.equal(depthError.error.message, 'ACP JSON exceeds the nesting limit');
  agent.child.stdin.write('x'.repeat(1048577) + '\n');
  const sizeError = await agent.waitFor(value => value.id === null && value.error?.code === -32700);
  assert.equal(sizeError.error.message, 'ACP line exceeds the 1 MiB limit');

  const unsupportedWorkspace = agent.sendRequest('session/new', {
    cwd: agent.workspace,
    additionalDirectories: [agent.workspace],
    mcpServers: [],
  });
  assert.equal((await unsupportedWorkspace.response).error.code, -32602);
  const relativeWorkspace = agent.sendRequest('session/new', {
    cwd: '.',
    mcpServers: [],
  });
  assert.equal((await relativeWorkspace.response).error.code, -32602);
  const malformedResume = agent.sendRequest('session/resume', {
    sessionId: '',
    cwd: agent.workspace,
    mcpServers: [],
  });
  assert.equal((await malformedResume.response).error.code, -32602);
  const unknownResume = agent.sendRequest('session/resume', {
    sessionId: 'acp-unknown-session',
    cwd: agent.workspace,
    mcpServers: [],
  });
  assert.equal((await unknownResume.response).error.code, -32602);
  const foreignResume = agent.sendRequest('session/resume', {
    sessionId: 'acp-unknown-session',
    cwd: path.dirname(agent.workspace),
    mcpServers: [],
  });
  assert.equal((await foreignResume.response).error.code, -32602);

  const sessionAResponse = agent.sendRequest('session/new', {
    cwd: agent.workspace,
    mcpServers: [],
  });
  const sessionBResponse = agent.sendRequest('session/new', {
    cwd: agent.workspace,
    mcpServers: [],
  });
  const sessionA = (await sessionAResponse.response).result.sessionId;
  const sessionB = (await sessionBResponse.response).result.sessionId;

  const promptA = agent.sendRequest('session/prompt', {
    sessionId: sessionA,
    prompt: [{ type: 'text', text: 'write the offline demo file' }],
  });
  const promptB = agent.sendRequest('session/prompt', {
    sessionId: sessionB,
    prompt: [
      { type: 'text', text: 'read the result: ' },
      { type: 'resource_link', name: 'workspace note', uri: 'file:///native-demo.txt' },
    ],
  });
  const permissionA = await agent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === sessionA);
  const permissionB = await agent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === sessionB);
  agent.child.stdin.write('{not-json}\n');
  const concurrentParseError = await agent.waitFor(value => value.id === null
    && value.error?.code === -32700);
  assert.equal(concurrentParseError.error.message, 'ACP JSON-RPC line is malformed JSON');
  assert.deepEqual(permissionA.params.options.map(option => option.optionId), [
    'allow-once', 'reject-once',
  ]);
  const busyPrompt = agent.sendRequest('session/prompt', {
    sessionId: sessionA,
    prompt: [{ type: 'text', text: 'the active prompt must retain its slot' }],
  });
  assert.equal((await busyPrompt.response).error.code, -32602);
  const busyResume = agent.sendRequest('session/resume', {
    sessionId: sessionA,
    cwd: agent.workspace,
    mcpServers: [],
  });
  assert.equal((await busyResume.response).error.code, -32602);

  agent.sendNotification('session/cancel', { sessionId: sessionA });
  const closeA1 = agent.sendRequest('session/close', { sessionId: sessionA });
  const closeA2 = agent.sendRequest('session/close', { sessionId: sessionA });
  const [closedA1, closedA2] = await Promise.all([closeA1.response, closeA2.response]);
  assert.deepEqual(closedA1.result, {});
  assert.deepEqual(closedA2.result, {}, JSON.stringify(closedA2));
  const promptAResult = await promptA.response;
  assert.equal(promptAResult.result.stopReason, 'cancelled');
  // A late answer for a cancelled permission is an ignored client response.
  agent.sendResponse(permissionA.id, {
    outcome: { outcome: 'selected', optionId: 'allow-once' },
  });

  agent.sendResponse(permissionB.id, {
    outcome: { outcome: 'selected', optionId: 'allow-once' },
  });
  const promptBResult = await promptB.response;
  assert.equal(promptBResult.result.stopReason, 'end_turn');
  const closeB = agent.sendRequest('session/close', { sessionId: sessionB });
  assert.deepEqual((await closeB.response).result, {});
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(agent.messages.some(entry => entry.value.id === 77
    && entry.value.method === undefined), false);
  assert.equal(agent.messages.some(entry => entry.value.id === permissionA.id
    && entry.value.method === undefined), false);
  await agent.closeAndCheck();

  assert.equal(await readFile(path.join(agent.workspace, 'native-demo.txt'), 'utf8'),
    'durable native tool result');
  const updateMessages = agent.messages.map(entry => entry.value)
    .filter(value => value.method === 'session/update');
  const updatesA = updateMessages.filter(value => value.params.sessionId === sessionA)
    .map(value => value.params.update.sessionUpdate);
  const updatesB = updateMessages.filter(value => value.params.sessionId === sessionB)
    .map(value => value.params.update.sessionUpdate);
  assert.ok(updatesA.includes('tool_call'));
  assert.ok(updatesA.includes('tool_call_update'));
  assert.ok(updatesB.includes('tool_call'));
  assert.ok(updatesB.includes('tool_call_update'));
  assert.ok(updatesB.includes('agent_message_chunk'));
  assert.equal(agent.messages.some(entry => JSON.stringify(entry.value).includes('assistant/stream_delta')),
    false);

  // A registered ACP session can be listed and resumed by a new process using
  // the same data directory. Resuming restores only the native engine state;
  // the connection starts after the historical event log without old updates.
  const resumeData = path.join(root, 'resume-data');
  const resumeWorkspace = path.join(root, 'resume-workspace');
  const firstResumeAgent = await launch('resume-first', {
    dataDir: resumeData,
    workspaceDir: resumeWorkspace,
  });
  const firstResumeInit = firstResumeAgent.sendRequest('initialize', { protocolVersion: 1 });
  await firstResumeInit.response;
  const createdForResume = firstResumeAgent.sendRequest('session/new', {
    cwd: firstResumeAgent.workspace,
    mcpServers: [],
  });
  const resumeSessionId = (await createdForResume.response).result.sessionId;
  const firstPrompt = firstResumeAgent.sendRequest('session/prompt', {
    sessionId: resumeSessionId,
    prompt: [{ type: 'text', text: 'write the offline demo file' }],
  });
  const firstPermission = await firstResumeAgent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === resumeSessionId);
  firstResumeAgent.sendResponse(firstPermission.id, {
    outcome: { outcome: 'selected', optionId: 'allow-once' },
  });
  assert.equal((await firstPrompt.response).result.stopReason, 'end_turn');
  const oldUpdates = firstResumeAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId);
  assert.ok(oldUpdates.some(entry => entry.value.params.update.sessionUpdate === 'tool_call'));
  const firstClose = firstResumeAgent.sendRequest('session/close', {
    sessionId: resumeSessionId,
  });
  assert.deepEqual((await firstClose.response).result, {});
  await firstResumeAgent.closeAndCheck();

  const resumedAgent = await launch('resume-second', {
    dataDir: resumeData,
    workspaceDir: resumeWorkspace,
  });
  const resumedInit = resumedAgent.sendRequest('initialize', { protocolVersion: 1 });
  await resumedInit.response;
  const listed = resumedAgent.sendRequest('session/list', {});
  const listedResult = (await listed.response).result;
  assert.equal(listedResult.sessions.length, 1);
  assert.equal(listedResult.sessions[0].sessionId, resumeSessionId);
  assert.equal(listedResult.sessions[0].cwd, await realpath(resumedAgent.workspace));
  assert.equal(typeof listedResult.sessions[0].updatedAt, 'string');
  assert.equal(listedResult.sessions[0].updatedAt.length, 20);
  const beforeResumeUpdates = resumedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId).length;
  const resume = resumedAgent.sendRequest('session/resume', {
    sessionId: resumeSessionId,
    cwd: resumedAgent.workspace,
    mcpServers: [],
  });
  assert.equal((await resume.response).result.configOptions[0].id, 'model');
  const duplicateResume = resumedAgent.sendRequest('session/resume', {
    sessionId: resumeSessionId,
    cwd: resumedAgent.workspace,
    mcpServers: [],
  });
  assert.equal((await duplicateResume.response).error.code, -32602);
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(resumedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId).length, beforeResumeUpdates);
  const continuedPrompt = resumedAgent.sendRequest('session/prompt', {
    sessionId: resumeSessionId,
    prompt: [{ type: 'text', text: 'continue from saved context' }],
  });
  assert.equal((await continuedPrompt.response).result.stopReason, 'end_turn');
  const continuedUpdates = resumedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId)
    .map(entry => entry.value.params.update);
  assert.equal(continuedUpdates.some(update => update.sessionUpdate === 'tool_call'), false);
  assert.ok(continuedUpdates.some(update => update.sessionUpdate === 'agent_message_chunk'
    && JSON.stringify(update).includes('Offline demo finished after the approved workspace write.')));
  const resumedClose = resumedAgent.sendRequest('session/close', {
    sessionId: resumeSessionId,
  });
  assert.deepEqual((await resumedClose.response).result, {});
  const resumeAfterClose = resumedAgent.sendRequest('session/resume', {
    sessionId: resumeSessionId,
    cwd: resumedAgent.workspace,
    mcpServers: [],
  });
  assert.equal((await resumeAfterClose.response).result.configOptions[0].id, 'model');
  const updateCountAfterCloseResume = resumedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId).length;
  await new Promise(resolve => setTimeout(resolve, 25));
  assert.equal(resumedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === resumeSessionId).length, updateCountAfterCloseResume);
  const finalClose = resumedAgent.sendRequest('session/close', {
    sessionId: resumeSessionId,
  });
  assert.deepEqual((await finalClose.response).result, {});
  await resumedAgent.closeAndCheck();
  assert.equal(await readFile(path.join(resumedAgent.workspace, 'native-demo.txt'), 'utf8'),
    'durable native tool result');

  const listAgent = await launch('list-pagination');
  const listInit = listAgent.sendRequest('initialize', { protocolVersion: 1 });
  await listInit.response;
  const createdIds = [];
  for (let index = 0; index < 18; index += 1) {
    const created = listAgent.sendRequest('session/new', {
      cwd: listAgent.workspace,
      mcpServers: [],
    });
    createdIds.push((await created.response).result.sessionId);
  }
  const alias = path.join(root, 'list-workspace-alias');
  await symlink(listAgent.workspace, alias);
  const firstPage = listAgent.sendRequest('session/list', { cwd: alias });
  const firstPageResult = (await firstPage.response).result;
  assert.equal(firstPageResult.sessions.length, 16);
  assert.equal(firstPageResult.sessions[0].sessionId, createdIds.at(-1));
  assert.equal(typeof firstPageResult.nextCursor, 'string');
  const wrongCursorType = listAgent.sendRequest('session/list', { cursor: 123 });
  assert.equal((await wrongCursorType.response).error.code, -32602);
  const nullFilters = listAgent.sendRequest('session/list', {
    cursor: null,
    cwd: null,
  });
  assert.equal((await nullFilters.response).result.sessions.length, 16);
  const secondPage = listAgent.sendRequest('session/list', {
    cwd: listAgent.workspace,
    cursor: firstPageResult.nextCursor,
  });
  const secondPageResult = (await secondPage.response).result;
  assert.equal(secondPageResult.sessions.length, 2);
  assert.equal(secondPageResult.sessions[0].sessionId, createdIds[1]);
  assert.equal(secondPageResult.sessions[1].sessionId, createdIds[0]);
  assert.equal('nextCursor' in secondPageResult, false);
  const foreignList = listAgent.sendRequest('session/list', { cwd: agent.workspace });
  assert.deepEqual((await foreignList.response).result.sessions, []);
  const repeatPage = listAgent.sendRequest('session/list', {
    cwd: listAgent.workspace,
    cursor: firstPageResult.nextCursor,
  });
  // A read-only list leaves its cursor valid for the next page.
  assert.equal((await repeatPage.response).result.sessions.length, 2);
  const wrongWorkspaceCursor = listAgent.sendRequest('session/list', {
    cwd: agent.workspace,
    cursor: firstPageResult.nextCursor,
  });
  assert.equal((await wrongWorkspaceCursor.response).error.code, -32602);
  const malformedCursor = listAgent.sendRequest('session/list', {
    cwd: listAgent.workspace,
    cursor: 'not-a-cursor',
  });
  assert.equal((await malformedCursor.response).error.code, -32602);
  const staleCursor = listAgent.sendRequest('session/list', {
    cwd: listAgent.workspace,
    cursor: firstPageResult.nextCursor,
  });
  assert.equal((await staleCursor.response).result.sessions.length, 2);
  const eighteenthClose = listAgent.sendRequest('session/close', {
    sessionId: createdIds[17],
  });
  assert.deepEqual((await eighteenthClose.response).result, {});
  // A committed mutation invalidates a cursor bound to the earlier revision.
  const staleAfterMutation = listAgent.sendRequest('session/list', {
    cwd: listAgent.workspace,
    cursor: firstPageResult.nextCursor,
  });
  assert.equal((await staleAfterMutation.response).error.code, -32602);
  await listAgent.closeAndCheck();

  const eofAgent = await launch('eof-pending-permission');
  const eofInitialize = eofAgent.sendRequest('initialize', { protocolVersion: 1 });
  await eofInitialize.response;
  const eofSessionRequest = eofAgent.sendRequest('session/new', {
    cwd: eofAgent.workspace,
    mcpServers: [],
  });
  const eofSession = (await eofSessionRequest.response).result.sessionId;
  const eofPrompt = eofAgent.sendRequest('session/prompt', {
    sessionId: eofSession,
    prompt: [{ type: 'text', text: 'leave permission pending until EOF' }],
  });
  await eofAgent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === eofSession);
  await eofAgent.closeAndCheck();
  assert.equal((await eofPrompt.response).result.stopReason, 'cancelled');
  assert.equal(await readFile(path.join(eofAgent.workspace, 'native-demo.txt'), 'utf8').catch(() => null), null);

  const rejectAgent = await launch('reject-once');
  const rejectInitialize = rejectAgent.sendRequest('initialize', { protocolVersion: 1 });
  await rejectInitialize.response;
  const rejectSessionRequest = rejectAgent.sendRequest('session/new', {
    cwd: rejectAgent.workspace,
    mcpServers: [],
  });
  const rejectSession = (await rejectSessionRequest.response).result.sessionId;
  const rejectPrompt = rejectAgent.sendRequest('session/prompt', {
    sessionId: rejectSession,
    prompt: [{ type: 'text', text: 'deny the offline demo write' }],
  });
  const rejectPermission = await rejectAgent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === rejectSession);
  rejectAgent.sendResponse(rejectPermission.id, {
    outcome: { outcome: 'selected', optionId: 'reject-once' },
  });
  const rejected = await rejectPrompt.response;
  assert.equal(rejected.result.stopReason, 'end_turn');
  assert.equal(await readFile(path.join(rejectAgent.workspace, 'native-demo.txt'), 'utf8').catch(() => null), null);
  const malformedSessionRequest = rejectAgent.sendRequest('session/new', {
    cwd: rejectAgent.workspace,
    mcpServers: [],
  });
  const malformedSession = (await malformedSessionRequest.response).result.sessionId;
  const malformedPrompt = rejectAgent.sendRequest('session/prompt', {
    sessionId: malformedSession,
    prompt: [{ type: 'text', text: 'reject a malformed live permission response' }],
  });
  const malformedPermission = await rejectAgent.waitFor(value => value.method === 'session/request_permission'
    && value.params?.sessionId === malformedSession);
  rejectAgent.child.stdin.write(`${JSON.stringify({
    jsonrpc: '2.0',
    id: malformedPermission.id,
    result: { outcome: { outcome: 'selected', optionId: 'allow-once' } },
    error: { code: -1, message: 'invalid response shape' },
  })}\n`);
  assert.equal((await malformedPrompt.response).result.stopReason, 'end_turn');
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(rejectAgent.messages.some(entry => entry.value.id === malformedPermission.id
    && entry.value.method === undefined), false);
  assert.equal(await readFile(path.join(rejectAgent.workspace, 'native-demo.txt'), 'utf8').catch(() => null), null);
  const malformedClose = rejectAgent.sendRequest('session/close', { sessionId: malformedSession });
  assert.deepEqual((await malformedClose.response).result, {});
  const rejectClose = rejectAgent.sendRequest('session/close', { sessionId: rejectSession });
  assert.deepEqual((await rejectClose.response).result, {});
  await rejectAgent.closeAndCheck();

  const missingKeyAgent = await launch('missing-provider-key', {
    provider: true,
    clearProviderKeys: true,
  });
  const missingInitialize = missingKeyAgent.sendRequest('initialize', { protocolVersion: 1 });
  await missingInitialize.response;
  const missingSessionRequest = missingKeyAgent.sendRequest('session/new', {
    cwd: missingKeyAgent.workspace,
    mcpServers: [],
  });
  const missingSession = (await missingSessionRequest.response).result.sessionId;
  const missingPrompt = missingKeyAgent.sendRequest('session/prompt', {
    sessionId: missingSession,
    prompt: [{ type: 'text', text: 'the provider has no configured key' }],
  });
  const missingResult = await missingPrompt.response;
  assert.equal(missingResult.error?.code, -32603);
  assert.equal(missingResult.error?.message, 'native provider turn failed');
  const missingClose = missingKeyAgent.sendRequest('session/close', { sessionId: missingSession });
  assert.deepEqual((await missingClose.response).result, {});
  await missingKeyAgent.closeAndCheck();

  const providerRequests = [];
  const provider = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    providerRequests.push(body);
    assert.equal(request.headers.authorization, 'Bearer acp-fixture-key');
    const promptText = JSON.stringify(body.messages ?? []);
    if (promptText.includes('return a controlled provider failure')) {
      response.writeHead(503, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ error: { message: 'fixture provider failure with acp-fixture-key' } }));
      return;
    }
    const delta = JSON.stringify({
      choices: [{ index: 0, delta: { role: 'assistant', content: 'bounded response' }, finish_reason: null }],
    });
    const finish = JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: 'length' }] });
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(`data: ${delta}\r\n\r\ndata: ${finish}\r\n\r\ndata: [DONE]\r\n\r\n`);
  });
  await new Promise((resolve, reject) => {
    provider.once('error', reject);
    provider.listen(0, '127.0.0.1', resolve);
  });
  try {
    const baseURL = `http://127.0.0.1:${provider.address().port}`;
    const providerAgent = await launch('provider-status', {
      provider: true,
      baseURL,
      env: { DSH_API_KEY: 'acp-fixture-key' },
    });
    const providerInitialize = providerAgent.sendRequest('initialize', { protocolVersion: 1 });
    await providerInitialize.response;
    const failedSessionRequest = providerAgent.sendRequest('session/new', {
      cwd: providerAgent.workspace,
      mcpServers: [],
    });
    const failedSession = (await failedSessionRequest.response).result.sessionId;
    const failedPrompt = providerAgent.sendRequest('session/prompt', {
      sessionId: failedSession,
      prompt: [{ type: 'text', text: 'return a controlled provider failure' }],
    });
    const failedResult = await failedPrompt.response;
    assert.equal(failedResult.error?.code, -32603);
    assert.equal(failedResult.error?.message, 'native provider turn failed');
    assert.equal(JSON.stringify(failedResult).includes('acp-fixture-key'), false);
    assert.equal(JSON.stringify(failedResult).includes('fixture provider failure'), false);
    const failedClose = providerAgent.sendRequest('session/close', { sessionId: failedSession });
    assert.deepEqual((await failedClose.response).result, {});

    const cappedSessionRequest = providerAgent.sendRequest('session/new', {
      cwd: providerAgent.workspace,
      mcpServers: [],
    });
    const cappedSession = (await cappedSessionRequest.response).result.sessionId;
    const cappedPrompt = providerAgent.sendRequest('session/prompt', {
      sessionId: cappedSession,
      prompt: [{ type: 'text', text: 'return a max-token response' }],
    });
    assert.equal((await cappedPrompt.response).result.stopReason, 'max_tokens');
    const cappedClose = providerAgent.sendRequest('session/close', { sessionId: cappedSession });
    assert.deepEqual((await cappedClose.response).result, {});
    await providerAgent.closeAndCheck();
    assert.equal(providerRequests.length, 2);
  } finally {
    await new Promise(resolve => provider.close(resolve));
  }

  let firstAlternateRequestResolve;
  const firstAlternateRequest = new Promise(resolve => {
    firstAlternateRequestResolve = resolve;
  });
  let releaseFirstAlternateResolve;
  const holdFirstAlternate = new Promise(resolve => {
    releaseFirstAlternateResolve = resolve;
  });
  const configuredRequests = [];
  let heldAlternateAttempt = false;
  const configuredProvider = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    configuredRequests.push(body);
    assert.equal(request.headers.authorization, 'Bearer acp-fixture-key');
    const latestMessage = JSON.stringify(body.messages?.at(-1)?.content ?? '');
    if (latestMessage.includes('hold this configured model turn')) {
      if (!heldAlternateAttempt) {
        heldAlternateAttempt = true;
        firstAlternateRequestResolve();
        await holdFirstAlternate;
        response.writeHead(503, { 'content-type': 'application/json' });
        response.end(JSON.stringify({ error: { message: 'retry the configured model turn' } }));
        return;
      }
    }
    const delta = JSON.stringify({
      choices: [{ index: 0, delta: { role: 'assistant', content: 'configured response' }, finish_reason: null }],
    });
    const finish = JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(`data: ${delta}\r\n\r\ndata: ${finish}\r\n\r\ndata: [DONE]\r\n\r\n`);
  });
  await new Promise((resolve, reject) => {
    configuredProvider.once('error', reject);
    configuredProvider.listen(0, '127.0.0.1', resolve);
  });
  const configuredData = path.join(root, 'configured-model-data');
  const configuredWorkspace = path.join(root, 'configured-model-workspace');
  const alternateValue = JSON.stringify(['openai', 'alternate-model']);
  const defaultValue = JSON.stringify(['openai', 'fixture-model']);
  try {
    const baseURL = `http://127.0.0.1:${configuredProvider.address().port}`;
    const configuredAgent = await launch('configured-model', {
      dataDir: configuredData,
      workspaceDir: configuredWorkspace,
      provider: true,
      baseURL,
      maxRetries: 1,
      env: {
        DSH_API_KEY: 'acp-fixture-key',
        DSH_ACP_MODELS: JSON.stringify(['fixture-model', 'alternate-model']),
      },
    });
    const configuredInitialize = configuredAgent.sendRequest('initialize', { protocolVersion: 1 });
    await configuredInitialize.response;
    const createConfiguredSession = async () => {
      const request = configuredAgent.sendRequest('session/new', {
        cwd: configuredAgent.workspace,
        mcpServers: [],
      });
      return (await request.response).result;
    };
    const configuredA = await createConfiguredSession();
    const configuredB = await createConfiguredSession();
    const configuredAId = configuredA.sessionId;
    const configuredBId = configuredB.sessionId;
    const initialModelOption = configuredA.configOptions.find(option => option.id === 'model');
    assert.equal(initialModelOption.currentValue, defaultValue);
    assert.deepEqual(
      initialModelOption.options[0].options.map(option => option.name),
      ['fixture-model', 'alternate-model'],
    );
    const configureA = configuredAgent.sendRequest('session/set_config_option', {
      sessionId: configuredAId,
      configId: 'model',
      value: alternateValue,
    });
    assert.equal((await configureA.response).result.configOptions[0].currentValue, alternateValue);
    const configUpdateIndex = configuredAgent.messages.findIndex(entry =>
      entry.value.method === 'session/update'
        && entry.value.params?.sessionId === configuredAId
        && entry.value.params?.update?.sessionUpdate === 'config_option_update');
    const configResponseIndex = configuredAgent.messages.findIndex(entry => entry.value.id === configureA.id);
    assert.ok(configUpdateIndex >= 0 && configUpdateIndex < configResponseIndex);
    const unknownConfig = configuredAgent.sendRequest('session/set_config_option', {
      sessionId: configuredAId,
      configId: 'reasoning',
      value: 'high',
    });
    assert.equal((await unknownConfig.response).error.code, -32602);
    const unavailableModel = configuredAgent.sendRequest('session/set_config_option', {
      sessionId: configuredAId,
      configId: 'model',
      value: JSON.stringify(['openai', 'not-advertised']),
    });
    assert.equal((await unavailableModel.response).error.code, -32602);

    const pinnedPrompt = configuredAgent.sendRequest('session/prompt', {
      sessionId: configuredAId,
      prompt: [{ type: 'text', text: 'hold this configured model turn' }],
    });
    await firstAlternateRequest;
    const busyConfiguration = configuredAgent.sendRequest('session/set_config_option', {
      sessionId: configuredAId,
      configId: 'model',
      value: defaultValue,
    });
    assert.equal((await busyConfiguration.response).error.code, -32602);
    const parallelPrompt = configuredAgent.sendRequest('session/prompt', {
      sessionId: configuredBId,
      prompt: [{ type: 'text', text: 'keep the other session on its default model' }],
    });
    assert.equal((await parallelPrompt.response).result.stopReason, 'end_turn');
    releaseFirstAlternateResolve();
    assert.equal((await pinnedPrompt.response).result.stopReason, 'end_turn');
    const configuredCloseA = configuredAgent.sendRequest('session/close', { sessionId: configuredAId });
    const configuredCloseB = configuredAgent.sendRequest('session/close', { sessionId: configuredBId });
    assert.deepEqual((await configuredCloseA.response).result, {});
    assert.deepEqual((await configuredCloseB.response).result, {});
    await configuredAgent.closeAndCheck();

    const narrowedAgent = await launch('configured-model-narrowed', {
      dataDir: configuredData,
      workspaceDir: configuredWorkspace,
      provider: true,
      baseURL,
      env: { DSH_API_KEY: 'acp-fixture-key', DSH_ACP_MODELS: '[]' },
    });
    const narrowedInitialize = narrowedAgent.sendRequest('initialize', { protocolVersion: 1 });
    await narrowedInitialize.response;
    const updatesBeforeRefusal = narrowedAgent.messages.filter(entry => entry.value.method === 'session/update'
      && entry.value.params?.sessionId === configuredAId).length;
    const unavailableResume = narrowedAgent.sendRequest('session/resume', {
      sessionId: configuredAId,
      cwd: narrowedAgent.workspace,
      mcpServers: [],
    });
    assert.equal((await unavailableResume.response).error.code, -32602);
    const listAfterRefusal = narrowedAgent.sendRequest('session/list', {});
    assert.ok((await listAfterRefusal.response).result.sessions.some(session => session.sessionId === configuredAId));
    assert.equal(narrowedAgent.messages.filter(entry => entry.value.method === 'session/update'
      && entry.value.params?.sessionId === configuredAId).length, updatesBeforeRefusal);
    await narrowedAgent.closeAndCheck();

    const restoredAgent = await launch('configured-model-restored', {
      dataDir: configuredData,
      workspaceDir: configuredWorkspace,
      provider: true,
      baseURL,
      env: {
        DSH_API_KEY: 'acp-fixture-key',
        DSH_ACP_MODELS: JSON.stringify(['alternate-model']),
      },
    });
    const restoredInitialize = restoredAgent.sendRequest('initialize', { protocolVersion: 1 });
    await restoredInitialize.response;
    const updatesBeforeResume = restoredAgent.messages.filter(entry => entry.value.method === 'session/update'
      && entry.value.params?.sessionId === configuredAId).length;
    const restoredResume = restoredAgent.sendRequest('session/resume', {
      sessionId: configuredAId,
      cwd: restoredAgent.workspace,
      mcpServers: [],
    });
    assert.equal((await restoredResume.response).result.configOptions[0].currentValue, alternateValue);
    assert.equal(restoredAgent.messages.filter(entry => entry.value.method === 'session/update'
      && entry.value.params?.sessionId === configuredAId).length, updatesBeforeResume);
    const reopenedPrompt = restoredAgent.sendRequest('session/prompt', {
      sessionId: configuredAId,
      prompt: [{ type: 'text', text: 'continue with the stored model selection' }],
    });
    assert.equal((await reopenedPrompt.response).result.stopReason, 'end_turn');
    assert.equal(configuredRequests.filter(body => body.model === 'alternate-model').length, 3);
    assert.equal(configuredRequests.filter(body => body.model === 'fixture-model').length, 1);
    const pinnedBodies = configuredRequests.filter(body => JSON.stringify(
      body.messages?.at(-1)?.content ?? '',
    ).includes('hold this configured model turn'));
    assert.equal(pinnedBodies.length, 2);
    assert.equal(pinnedBodies[0].model, 'alternate-model');
    assert.deepEqual(pinnedBodies[0], pinnedBodies[1]);
    const configuredCloseRestored = restoredAgent.sendRequest('session/close', { sessionId: configuredAId });
    assert.deepEqual((await configuredCloseRestored.response).result, {});
    await restoredAgent.closeAndCheck();

    const malformedModelsAgent = await launch('malformed-model-catalog', {
      provider: true,
      env: { DSH_ACP_MODELS: '["unterminated"' },
    });
    const malformedModelsInitialize = malformedModelsAgent.sendRequest('initialize', { protocolVersion: 1 });
    assert.equal((await malformedModelsInitialize.response).error.code, -32603);
    await malformedModelsAgent.closeAndCheck();
  } finally {
    releaseFirstAlternateResolve();
    configuredProvider.closeAllConnections();
    await new Promise(resolve => configuredProvider.close(resolve));
  }

  let pendingProviderRequests = 0;
  const pendingProviderWaiters = [];
  function waitForPendingProviderRequest(count) {
    if (pendingProviderRequests >= count) return Promise.resolve();
    return new Promise(resolve => pendingProviderWaiters.push({ count, resolve }));
  }
  const pendingProvider = createServer((request, _response) => {
    assert.equal(request.url, '/v1/chat/completions');
    request.on('end', () => {
      pendingProviderRequests += 1;
      for (const waiter of [...pendingProviderWaiters]) {
        if (pendingProviderRequests < waiter.count) continue;
        pendingProviderWaiters.splice(pendingProviderWaiters.indexOf(waiter), 1);
        waiter.resolve();
      }
    });
    request.resume();
  });
  await new Promise((resolve, reject) => {
    pendingProvider.once('error', reject);
    pendingProvider.listen(0, '127.0.0.1', resolve);
  });
  try {
    const baseURL = `http://127.0.0.1:${pendingProvider.address().port}`;
    const cancelAgent = await launch('provider-active-cancel', {
      provider: true,
      baseURL,
      env: { DSH_API_KEY: 'acp-fixture-key' },
    });
    const cancelInitialize = cancelAgent.sendRequest('initialize', { protocolVersion: 1 });
    await cancelInitialize.response;
    const cancelSessionRequest = cancelAgent.sendRequest('session/new', {
      cwd: cancelAgent.workspace,
      mcpServers: [],
    });
    const cancelSession = (await cancelSessionRequest.response).result.sessionId;
    const cancelPrompt = cancelAgent.sendRequest('session/prompt', {
      sessionId: cancelSession,
      prompt: [{ type: 'text', text: 'hold the provider request until cancellation' }],
    });
    await waitForPendingProviderRequest(1);
    cancelAgent.sendNotification('session/cancel', { sessionId: cancelSession });
    assert.equal((await cancelPrompt.response).result.stopReason, 'cancelled');
    const cancelClose = cancelAgent.sendRequest('session/close', { sessionId: cancelSession });
    assert.deepEqual((await cancelClose.response).result, {});
    await cancelAgent.closeAndCheck();

    const closeAgent = await launch('provider-active-close', {
      provider: true,
      baseURL,
      env: { DSH_API_KEY: 'acp-fixture-key' },
    });
    const closeInitialize = closeAgent.sendRequest('initialize', { protocolVersion: 1 });
    await closeInitialize.response;
    const closeSessionRequest = closeAgent.sendRequest('session/new', {
      cwd: closeAgent.workspace,
      mcpServers: [],
    });
    const closeSession = (await closeSessionRequest.response).result.sessionId;
    const closePrompt = closeAgent.sendRequest('session/prompt', {
      sessionId: closeSession,
      prompt: [{ type: 'text', text: 'hold the provider request until session close' }],
    });
    await waitForPendingProviderRequest(2);
    const closeRequest = closeAgent.sendRequest('session/close', { sessionId: closeSession });
    const [closed, closePromptResult] = await Promise.all([closeRequest.response, closePrompt.response]);
    assert.deepEqual(closed.result, {});
    assert.equal(closePromptResult.result.stopReason, 'cancelled');
    await closeAgent.closeAndCheck();

    const eofProviderAgent = await launch('provider-active-eof', {
      provider: true,
      baseURL,
      env: { DSH_API_KEY: 'acp-fixture-key' },
    });
    const eofProviderInitialize = eofProviderAgent.sendRequest('initialize', { protocolVersion: 1 });
    await eofProviderInitialize.response;
    const eofProviderSessionRequest = eofProviderAgent.sendRequest('session/new', {
      cwd: eofProviderAgent.workspace,
      mcpServers: [],
    });
    const eofProviderSession = (await eofProviderSessionRequest.response).result.sessionId;
    const eofProviderPrompt = eofProviderAgent.sendRequest('session/prompt', {
      sessionId: eofProviderSession,
      prompt: [{ type: 'text', text: 'hold the provider request until stdio EOF' }],
    });
    await waitForPendingProviderRequest(3);
    await eofProviderAgent.closeAndCheck();
    assert.equal((await eofProviderPrompt.response).result.stopReason, 'cancelled');
  } finally {
    pendingProvider.closeAllConnections();
    await new Promise(resolve => pendingProvider.close(resolve));
  }

  const failedDataDir = path.join(root, 'checkpoint-failure-data');
  const failedAgent = await launch('checkpoint-failure', {
    dataDir: failedDataDir,
    provider: true,
    clearProviderKeys: true,
    env: { DSH_ACP_MODELS: JSON.stringify(['alternate-model']) },
  });
  const failedInitialize = failedAgent.sendRequest('initialize', { protocolVersion: 1 });
  await failedInitialize.response;
  const failedSessionRequest = failedAgent.sendRequest('session/new', {
    cwd: failedAgent.workspace,
    mcpServers: [],
  });
  const failedSessionId = (await failedSessionRequest.response).result.sessionId;
  const snapshotPath = path.join(failedDataDir, 'sessions.json');
  const snapshotBeforeConflict = await readFile(snapshotPath, 'utf8');
  await writeFile(snapshotPath, snapshotBeforeConflict + '\n');
  const failedConfig = failedAgent.sendRequest('session/set_config_option', {
    sessionId: failedSessionId,
    configId: 'model',
    value: JSON.stringify(['openai', 'alternate-model']),
  });
  assert.equal((await failedConfig.response).error.code, -32603);
  assert.equal(failedAgent.messages.filter(entry => entry.value.method === 'session/update'
    && entry.value.params?.sessionId === failedSessionId
    && entry.value.params?.update?.sessionUpdate === 'config_option_update').length, 0);
  const failedPrompt = failedAgent.sendRequest('session/prompt', {
    sessionId: failedSessionId,
    prompt: [{ type: 'text', text: 'runtime remains fenced after checkpoint conflict' }],
  });
  assert.equal((await failedPrompt.response).error.code, -32603);
  const persistedAfterConflict = JSON.parse(await readFile(snapshotPath, 'utf8'));
  assert.equal(
    persistedAfterConflict.acp_sessions.find(session => session.session_id === failedSessionId)?.model,
    'fixture-model',
  );
  failedAgent.child.stdin.end();
  const failedExit = await failedAgent.waitForExit();
  assert.equal(failedExit.code, 1);
  assert.equal(failedExit.signal, null);
  assert.match(failedAgent.stderr(), /native runtime shutdown failed/);

console.log('ACP native stdio integration passed: negotiation, persistent list/resume, per-session model configuration and update ordering, simultaneous routes, busy-change refusal, retries, catalog refusal/recovery, saved-context continuation and no replay, approvals, cancellation/EOF, and framing bounds.');
} finally {
  await rm(root, { recursive: true, force: true });
}
