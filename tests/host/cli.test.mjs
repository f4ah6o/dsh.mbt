import test from 'node:test';
import assert from 'node:assert/strict';
import { Readable, Writable } from 'node:stream';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { parseCLI, serveMcp } from '../../host/cli.mjs';

const execute = promisify(execFile);
const repository = fileURLToPath(new URL('../../', import.meta.url));

test('CLI options preserve explicit provider and approval policy', () => {
  const defaults = parseCLI([], {});
  assert.equal(defaults.command, 'web');
  assert.equal(defaults.options.mode, 'deepseek');
  assert.equal(defaults.options.model, 'deepseek-flash');
  assert.deepEqual(defaults.options.approveTools, []);
  const explicit = parseCLI(['run', 'Hello', '--mode', 'openai', '--model', 'my-model', '--allow-shell', '--approve-tools', 'bash', '--approve-writes', '--json'], { OPENAI_API_KEY: 'from-env' });
  assert.equal(explicit.prompt, 'Hello');
  assert.equal(explicit.options.apiKey, 'from-env');
  assert.deepEqual(explicit.options.approveTools, ['bash', 'write', 'edit']);
  assert.equal(explicit.options.allowShell, true);
  assert.throws(() => parseCLI(['--mode', 'openai'], {}), /--model NAME or DSH_MODEL/);
  assert.equal(parseCLI(['--mode', 'openai'], { DSH_MODEL: 'chosen' }).options.model, 'chosen');
  assert.throws(() => parseCLI(['run'], {}), /requires a prompt/);
  assert.throws(() => parseCLI(['--port'], {}), /Missing value/);
  assert.throws(() => parseCLI(['--unknown'], {}), /Unknown option/);
});

test('stdio MCP separates lines, handles UTF-8 chunks and emits no notification bytes', async () => {
  const lines = [];
  let output = '';
  const host = { mcp: async (line) => {
    lines.push(JSON.parse(line));
    return lines.at(-1).id ? JSON.stringify({ jsonrpc: '2.0', id: lines.at(-1).id, result: {} }) : '';
  } };
  const data = Buffer.from('{"jsonrpc":"2.0","id":1,"method":"日本語"}\n{"jsonrpc":"2.0","method":"notify"}\r\n{"jsonrpc":"2.0","id":2,"method":"last"}');
  const input = Readable.from([...data].map((byte) => Buffer.from([byte])));
  const sink = new Writable({ write(chunk, _encoding, next) { output += chunk.toString(); next(); } });
  await serveMcp(host, input, sink);
  assert.equal(lines[0].method, '日本語');
  assert.equal(lines.length, 3);
  assert.deepEqual(output.trim().split('\n').map((line) => JSON.parse(line).id), [1, 2]);
});

test('oversized MCP lines are rejected once and the next request still works', async () => {
  const received = [];
  let output = '';
  const host = { mcp: async (line) => { received.push(line); return '{"id":1,"result":{}}'; } };
  const input = Readable.from([Buffer.from('x'.repeat(1024 * 1024 + 1)), Buffer.from('discarded tail\n{"id":1}\n')]);
  const sink = new Writable({ write(chunk, _encoding, next) { output += chunk.toString(); next(); } });
  await serveMcp(host, input, sink);
  assert.deepEqual(received, ['{"id":1}']);
  const messages = output.trim().split('\n').map(JSON.parse);
  assert.equal(messages.length, 2);
  assert.equal(messages[0].error.code, -32700);
  assert.equal(messages[1].id, 1);
});

test('CLI offline run completes the real tool turn and leaves no live host lock', async (t) => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-cli-'));
  t.after(() => fs.rm(workspace, { recursive: true, force: true }));
  await fs.writeFile(path.join(workspace, 'demo.mbt'), 'demo');
  const { stdout, stderr } = await execute(process.execPath, ['host/cli.mjs', 'run', 'List files', '--demo', '--workspace', workspace, '--json'], { cwd: repository, timeout: 15_000, env: { ...process.env, DSH_API_KEY: 'never-display-this-secret' } });
  const final = JSON.parse(stdout);
  assert.equal(final.status, 'completed');
  assert.ok(final.messages.some((message) => message.role === 'tool' && message.content.includes('demo.mbt')));
  assert.ok(!(stdout + stderr).includes('never-display-this-secret'));
  await assert.rejects(fs.stat(path.join(workspace, '.dsh.mbt/host.lock')), { code: 'ENOENT' });
  const saved = JSON.parse(await fs.readFile(path.join(workspace, '.dsh.mbt/sessions.json'), 'utf8'));
  assert.equal(saved.sessions[0].status, 'completed');
});
