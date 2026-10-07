#!/usr/bin/env node
import { pathToFileURL } from 'node:url';
import { createInterface } from 'node:readline/promises';
import { StringDecoder } from 'node:string_decoder';
import { constants as fsConstants } from 'node:fs';
import { open } from 'node:fs/promises';
import { createHost } from './runtime.mjs';
import { startWebServer } from './server.mjs';
import { HostError, messageOf } from './errors.mjs';

const HELP = `dsh.mbt — MoonBit agent runtime

Usage:
  node host/cli.mjs [web] [options]
  node host/cli.mjs run "prompt" [options]
  node host/cli.mjs import-session SESSION.v4.jsonl [options]
  node host/cli.mjs mcp [options]

Options:
  --demo                  Offline fixture with a real workspace glob tool turn
  --workspace PATH        Workspace for file tools (default: current directory)
  --data-dir PATH         Local session directory (default: WORKSPACE/.dsh.mbt)
  --mode deepseek|openai  Provider protocol (default: deepseek)
  --model NAME            Model (DeepSeek default: deepseek-flash; required for openai)
  --base-url URL          Provider API root (supports a trailing /v1)
  --max-retries NUMBER    Bounded transient provider retries (default: 5, maximum: 5)
  --port NUMBER           Web port (default: 3080)
  --host ADDRESS          Loopback only (default: 127.0.0.1)
  --allow-shell           Enable bash capability; approval is still required
  --approve-tools NAMES   Explicit auto-approval for write,edit,bash (comma list)
  --approve-writes        Explicit auto-approval for write and edit
  --session ID            Send the run prompt to an existing session
  --json                  Print the final or imported session as JSON
  --title TEXT            Title for a new run session
  --help                  Show this help

import-session accepts a native Session v4 JSONL file and creates a read-only history.
It does not resume the turn, execute recorded tools, or activate imported permissions.

Credentials remain in the host process: DEEPSEEK_API_KEY or OPENAI_API_KEY.
DSH_API_KEY, DSH_MODEL, DSH_BASE_URL, and DSH_MODE override the provider defaults.
The MCP carrier passes gpui.mbt JSON-RPC messages through without protocol translation.
`;

export function parseCLI(argv, env = process.env) {
  const options = { mode: env.DSH_MODE ?? 'deepseek', model: env.DSH_MODEL, baseURL: env.DSH_BASE_URL, approveTools: [] };
  const positionals = [];
  const values = new Map([
    ['--workspace', 'workspace'], ['--data-dir', 'dataDir'], ['--mode', 'mode'], ['--model', 'model'],
    ['--base-url', 'baseURL'], ['--port', 'port'], ['--max-retries', 'maxRetries'], ['--host', 'bind'], ['--session', 'sessionID'], ['--title', 'title'],
  ]);
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === '--') { positionals.push(...argv.slice(index + 1)); break; }
    if (values.has(argument) || argument === '--approve-tools') {
      const value = argv[++index];
      if (value === undefined || value.startsWith('--')) throw new HostError(`Missing value for ${argument}`);
      if (argument === '--approve-tools') options.approveTools.push(...value.split(',').map((item) => item.trim()).filter(Boolean));
      else options[values.get(argument)] = argument === '--port' || argument === '--max-retries' ? Number(value) : value;
    } else if (argument === '--approve-writes') options.approveTools.push('write', 'edit');
    else if (argument === '--demo') options.demo = true;
    else if (argument === '--allow-shell') options.allowShell = true;
    else if (argument === '--json') options.json = true;
    else if (argument === '--help' || argument === '-h') options.help = true;
    else if (argument.startsWith('-')) throw new HostError(`Unknown option: ${argument}`);
    else positionals.push(argument);
  }
  const command = positionals.shift() ?? 'web';
  if (!['web', 'run', 'import-session', 'mcp'].includes(command) && !options.help) throw new HostError(`Unknown command: ${command}`);
  if (command !== 'run' && command !== 'import-session' && positionals.length) throw new HostError('Unexpected positional arguments');
  if (command === 'run' && !positionals.length && !options.help) throw new HostError('run requires a prompt');
  if (command === 'import-session' && positionals.length !== 1 && !options.help) throw new HostError('import-session requires one Session v4 JSONL path');
  if (options.mode === 'openai' && !options.demo && !options.model && !options.help) throw new HostError('OpenAI-compatible mode requires an explicit model: set --model NAME or DSH_MODEL');
  if (options.maxRetries !== undefined && (!Number.isSafeInteger(options.maxRetries) || options.maxRetries < 0 || options.maxRetries > 5)) {
    throw new HostError('--max-retries must be an integer between 0 and 5');
  }
  if (options.mode === 'deepseek') options.model ??= 'deepseek-flash';
  options.apiKey = env.DSH_API_KEY ?? (options.mode === 'openai' ? env.OPENAI_API_KEY : env.DEEPSEEK_API_KEY);
  return { command, prompt: command === 'run' ? positionals.join(' ') : '', sessionPath: command === 'import-session' ? positionals[0] : undefined, options };
}

export async function serveMcp(host, input = process.stdin, output = process.stdout) {
  const decoder = new StringDecoder('utf8');
  let buffered = '';
  let discarding = false;
  const limit = 1024 * 1024;
  const write = async (line) => {
    if (!line) return;
    if (!output.write(`${line}\n`)) await new Promise((resolve, reject) => {
      const done = () => { output.removeListener('error', fail); resolve(); };
      const fail = (error) => { output.removeListener('drain', done); reject(error); };
      output.once('drain', done);
      output.once('error', fail);
    });
  };
  const tooLarge = () => write(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'MCP line exceeds the 1 MiB limit' } }));
  async function accept(text, end = false) {
    buffered += text;
    for (;;) {
      const newline = buffered.indexOf('\n');
      if (newline < 0) break;
      const line = buffered.slice(0, newline).replace(/\r$/, '');
      buffered = buffered.slice(newline + 1);
      if (discarding) { discarding = false; continue; }
      if (Buffer.byteLength(line) > limit) { await tooLarge(); continue; }
      if (line.trim()) await write(await host.mcp(line));
    }
    if (Buffer.byteLength(buffered) > limit) {
      if (!discarding) await tooLarge();
      buffered = '';
      discarding = true;
    }
    if (end && buffered.trim() && !discarding) await write(await host.mcp(buffered));
  }
  for await (const chunk of input) await accept(decoder.write(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
  await accept(decoder.end(), true);
}

async function runPrompt(host, prompt, options, signal) {
  let current;
  if (options.sessionID) current = await host.session(options.sessionID);
  else {
    const created = await host.call('session_create', { title: options.title ?? prompt.slice(0, 80) });
    if (!created.ok) throw new HostError(created.error);
    current = created.result;
  }
  const sent = await host.call('session_send', { session_id: current.id, prompt });
  if (!sent.ok) throw new HostError(sent.error);
  current = await host.waitForSession(current.id, { signal });
  while (current.status === 'awaiting_approval') {
    const approval = current.pending_approval;
    if (!process.stdin.isTTY) {
      process.stderr.write(`Tool ${approval.name} requires approval. Use an interactive terminal, the web UI, or explicit --approve-tools options. This noninteractive turn is cancelled.\n`);
      const cancelled = await host.call('session_cancel', { session_id: current.id });
      current = cancelled.result;
      process.exitCode = 2;
      break;
    }
    process.stderr.write(`\nApprove ${approval.name} for session ${current.id}?\n${JSON.stringify(approval.arguments, null, 2)}\n`);
    const reader = createInterface({ input: process.stdin, output: process.stderr });
    let answer;
    try { answer = await reader.question('Allow once? [y/N] ', { signal }); } finally { reader.close(); }
    const decided = await host.call('tool_approve', { session_id: current.id, call_id: approval.call_id, approved: /^y(?:es)?$/i.test(answer.trim()) });
    if (!decided.ok) throw new HostError(decided.error);
    current = await host.waitForSession(current.id, { signal });
  }
  if (options.json) process.stdout.write(`${JSON.stringify(current)}\n`);
  else {
    const messages = current.messages ?? [];
    const lastUser = messages.findLastIndex((message) => message.role === 'user');
    // Live provider text is presentation-only until a completion event closes
    // the step; keep run-mode stdout to the final assistant response.
    const response = messages.slice(lastUser + 1).findLast((message) => message.role === 'assistant' && !message.provisional && message.content);
    if (response) process.stdout.write(`${typeof response.content === 'string' ? response.content : JSON.stringify(response.content)}\n`);
    process.stderr.write(`Session ${current.id}: ${current.status}\n`);
    if (current.status === 'failed') {
      const end = [...(current.events ?? [])].reverse().find((event) => event.data?.error);
      if (end) process.stderr.write(`${end.data.error}\n`);
    }
  }
  if (current.status !== 'completed') process.exitCode ||= 1;
}

async function importSession(host, sourcePath, options, signal) {
  const maxBytes = 1024 * 1024;
  let file;
  try { file = await open(sourcePath, fsConstants.O_RDONLY | (fsConstants.O_NONBLOCK ?? 0)); }
  catch (cause) { throw new HostError(`Cannot read Session v4 archive at ${sourcePath}`, { cause }); }
  let bytes;
  try {
    signal.throwIfAborted();
    const info = await file.stat();
    if (!info.isFile()) throw new HostError('Session v4 archive path must name a regular file');
    if (info.size > maxBytes) throw new HostError('Session v4 archive exceeds the 1 MiB CLI file limit');
    const buffer = Buffer.alloc(maxBytes + 1);
    let total = 0;
    while (total < buffer.length) {
      signal.throwIfAborted();
      const { bytesRead } = await file.read(buffer, total, buffer.length - total, total);
      if (bytesRead === 0) break;
      total += bytesRead;
    }
    if (total > maxBytes) throw new HostError('Session v4 archive exceeds the 1 MiB CLI file limit');
    bytes = buffer.subarray(0, total);
  } finally { await file.close(); }
  let jsonl;
  try { jsonl = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch (cause) { throw new HostError('Session v4 archive is not valid UTF-8', { cause }); }
  signal.throwIfAborted();
  const imported = await host.call('session_import', { jsonl });
  if (!imported.ok) throw new HostError(imported.error);
  if (options.json) process.stdout.write(`${JSON.stringify(imported.result)}\n`);
  else process.stdout.write(`Imported Session v4 as ${imported.result.id}: ${imported.result.title}\nRead-only history (${imported.result.status}); recorded tools were not executed.\n`);
}

export async function main(argv = process.argv.slice(2)) {
  const { command, prompt, sessionPath, options } = parseCLI(argv);
  if (options.help) { process.stdout.write(HELP); return; }
  const controller = new AbortController();
  const interrupt = () => { process.exitCode = 130; controller.abort(new Error('Interrupted')); };
  const terminate = () => { process.exitCode = 143; controller.abort(new Error('Terminated')); };
  process.once('SIGINT', interrupt);
  process.once('SIGTERM', terminate);
  let host;
  let web;
  try {
    host = await createHost({ ...options, onError: (error) => process.stderr.write(`Host error: ${error.message}\n`) });
    if (controller.signal.aborted) return;
    if (command === 'web') {
      web = await startWebServer({ host, port: options.port, bind: options.bind });
      process.stderr.write(`dsh.mbt web running at ${web.url}\nBackend: ${host.backend.mode}${host.backend.mode === 'demo' ? ' (offline deterministic fixture)' : ` / ${host.backend.model}`}\nWorkspace: ${host.workspace}\n`);
      await new Promise((resolve) => {
        if (controller.signal.aborted) resolve();
        else controller.signal.addEventListener('abort', resolve, { once: true });
      });
    } else if (command === 'mcp') {
      const abortInput = () => process.stdin.destroy();
      controller.signal.addEventListener('abort', abortInput, { once: true });
      try { await serveMcp(host); } finally { controller.signal.removeEventListener('abort', abortInput); }
    } else if (command === 'import-session') await importSession(host, sessionPath, options, controller.signal);
    else await runPrompt(host, prompt, options, controller.signal);
  } finally {
    try { await web?.close(); } finally {
      try { await host?.close(); } finally {
        process.removeListener('SIGINT', interrupt);
        process.removeListener('SIGTERM', terminate);
      }
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { process.stderr.write(`${messageOf(error)}\n`); process.exitCode ||= 1; });
}
