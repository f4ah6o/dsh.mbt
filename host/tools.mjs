import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { Worker } from 'node:worker_threads';
import { HostError, checkAbort, messageOf } from './errors.mjs';

const OUTPUT_LIMIT = 64 * 1024;
const FILE_LIMIT = 4 * 1024 * 1024;
const WRITE_LIMIT = 1024 * 1024;
const MAX_VISITED = 10_000;
const NOFOLLOW = constants.O_NOFOLLOW ?? 0;
const DIRECTORY = constants.O_DIRECTORY ?? 0;

function requiredString(value, name, maximum = FILE_LIMIT) {
  if (typeof value !== 'string' || value.length > maximum) throw new HostError(`${name} must be a string of at most ${maximum} characters`);
  return value;
}

function integer(value, fallback, minimum, maximum, name) {
  const candidate = value ?? fallback;
  if (!Number.isSafeInteger(candidate) || candidate < minimum || candidate > maximum) {
    throw new HostError(`${name} must be an integer between ${minimum} and ${maximum}`);
  }
  return candidate;
}

function inside(root, target) {
  const relative = path.relative(root, target);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function sameFile(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function sameVersion(left, right) {
  return sameFile(left, right) && left.size === right.size && left.mtimeMs === right.mtimeMs && left.ctimeMs === right.ctimeMs;
}

async function canonicalizePathWithMissingTail(target) {
  let current = path.resolve(target);
  const suffix = [];
  while (true) {
    try {
      const resolved = await fs.realpath(current);
      return path.join(resolved, ...suffix.reverse());
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
      const parent = path.dirname(current);
      if (parent === current) throw error;
      suffix.push(path.basename(current));
      current = parent;
    }
  }
}

function bounded(text, maximum = OUTPUT_LIMIT) {
  const bytes = Buffer.from(text);
  if (bytes.length <= maximum) return text;
  const suffix = '\n[output truncated]';
  if (maximum <= suffix.length) return suffix.slice(0, maximum);
  // Streaming decode omits an incomplete trailing UTF-8 sequence. The marker
  // is included in the budget accepted by MoonBit's tool-completion schema.
  return new TextDecoder().decode(bytes.subarray(0, maximum - suffix.length), { stream: true }) + suffix;
}

async function maybeStat(target) {
  try { return await fs.lstat(target); } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

/** IO boundary only. Approval and the agent loop belong to the MoonBit engine. */
export async function createWorkspaceTools({ workspace, allowShell = false, protectedPaths = [], shellEnv = process.env, outputLimit = OUTPUT_LIMIT, grepTimeoutMs = 3000 } = {}) {
  const root = await fs.realpath(path.resolve(workspace ?? process.cwd()));
  const rootIdentity = await fs.lstat(root);
  if (!rootIdentity.isDirectory()) throw new HostError('Workspace must be a directory');
  const blocked = await Promise.all(protectedPaths.map(canonicalizePathWithMissingTail));
  const useDirectoryFD = process.platform === 'linux';

  function resolveWorkspace(input, { directory = false } = {}) {
    const value = requiredString(input, directory ? 'path' : 'file_path', 4096);
    if (value.includes('\0') || (!directory && !value)) throw new HostError('Invalid workspace path');
    const target = path.resolve(root, value || '.');
    if (!inside(root, target) || (!directory && target === root)) throw new HostError('Path escapes the workspace');
    if (blocked.some((item) => inside(item, target))) throw new HostError('Host data is not accessible through workspace tools');
    return target;
  }

  async function assertRoot() {
    const current = await fs.lstat(root);
    if (current.isSymbolicLink() || !sameFile(rootIdentity, current)) throw new HostError('Workspace directory changed during execution');
  }

  function anchor(handle, target) {
    return useDirectoryFD ? `/proc/self/fd/${handle.fd}` : target;
  }

  async function verifyDirectory(handle, expected) {
    await assertRoot();
    const actual = await fs.realpath(anchor(handle, expected));
    if (actual !== expected || !inside(root, actual)) throw new HostError('Workspace ancestor changed during execution');
    const live = await fs.lstat(expected);
    if (live.isSymbolicLink() || !sameFile(await handle.stat(), live)) throw new HostError('Workspace ancestor changed during execution');
  }

  async function openDirectory(target, create = false) {
    await assertRoot();
    let handle = await fs.open(root, constants.O_RDONLY | DIRECTORY | NOFOLLOW);
    let current = root;
    try {
      const components = path.relative(root, target).split(path.sep).filter(Boolean);
      for (const component of components) {
        await verifyDirectory(handle, current);
        const nextPath = path.join(anchor(handle, current), component);
        if (create) {
          try { await fs.mkdir(nextPath, { mode: 0o755 }); } catch (error) {
            if (error.code !== 'EEXIST') throw error;
          }
        }
        const observed = await fs.lstat(nextPath);
        if (observed.isSymbolicLink() || !observed.isDirectory()) throw new HostError('Symbolic links and non-directory ancestors are not allowed');
        const next = await fs.open(nextPath, constants.O_RDONLY | DIRECTORY | NOFOLLOW);
        if (!sameFile(observed, await next.stat())) {
          await next.close();
          throw new HostError('Workspace ancestor changed during execution');
        }
        await handle.close();
        handle = next;
        current = path.join(current, component);
      }
      await verifyDirectory(handle, current);
      return { handle, target: current, anchor: anchor(handle, current) };
    } catch (error) {
      await handle.close();
      throw error;
    }
  }

  async function readText(target, signal, maximum = FILE_LIMIT) {
    checkAbort(signal);
    const parent = await openDirectory(path.dirname(target));
    let file;
    try {
      const anchored = path.join(parent.anchor, path.basename(target));
      const before = await fs.lstat(anchored);
      if (before.isSymbolicLink() || !before.isFile()) throw new HostError('Only regular files can be read; symbolic links are not allowed');
      file = await fs.open(anchored, constants.O_RDONLY | NOFOLLOW);
      const opened = await file.stat();
      if (!sameFile(before, opened)) throw new HostError('File changed while opening it');
      if (opened.size > maximum) throw new HostError(`File exceeds the ${maximum} byte read limit`);
      await verifyDirectory(parent.handle, parent.target);
      const chunks = [];
      let size = 0;
      while (size <= maximum) {
        checkAbort(signal);
        const chunk = Buffer.allocUnsafe(Math.min(16 * 1024, maximum + 1 - size));
        const { bytesRead } = await file.read(chunk, 0, chunk.length, size);
        if (!bytesRead) break;
        chunks.push(chunk.subarray(0, bytesRead));
        size += bytesRead;
      }
      if (size > maximum) throw new HostError(`File exceeds the ${maximum} byte read limit`);
      if (!sameVersion(opened, await file.stat())) throw new HostError('File changed while reading it; retry the read');
      await verifyDirectory(parent.handle, parent.target);
      const bytes = Buffer.concat(chunks, size);
      if (bytes.includes(0)) throw new HostError('Binary files are not supported by the text read tool');
      return { text: bytes.toString('utf8'), stat: opened };
    } finally {
      await file?.close();
      await parent.handle.close();
    }
  }

  async function writeAtomic(target, content, signal, expected) {
    checkAbort(signal);
    if (Buffer.byteLength(content) > WRITE_LIMIT) throw new HostError(`Content exceeds the ${WRITE_LIMIT} byte write limit`);
    const parent = await openDirectory(path.dirname(target), expected === undefined);
    const anchored = path.join(parent.anchor, path.basename(target));
    const temporary = path.join(parent.anchor, `.dsh-${randomUUID()}.tmp`);
    let file;
    let created = false;
    try {
      const before = await maybeStat(anchored);
      if (before && (before.isSymbolicLink() || !before.isFile())) throw new HostError('Only regular files can be replaced; symbolic links are not allowed');
      if (expected && (!before || !sameVersion(expected, before))) throw new HostError('File changed since it was read; retry the edit');
      await verifyDirectory(parent.handle, parent.target);
      file = await fs.open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NOFOLLOW, before ? before.mode & 0o777 : 0o644);
      created = true;
      await file.writeFile(content, { encoding: 'utf8', signal });
      await file.sync();
      await file.close();
      file = undefined;
      checkAbort(signal);
      await verifyDirectory(parent.handle, parent.target);
      const current = await maybeStat(anchored);
      if (current && (current.isSymbolicLink() || !current.isFile())) throw new HostError('Target changed to a symbolic link or non-file');
      if (expected && (!current || !sameVersion(expected, current))) throw new HostError('File changed since it was read; retry the edit');
      await fs.rename(temporary, anchored);
      created = false;
      await parent.handle.sync();
      return Buffer.byteLength(content);
    } finally {
      await file?.close();
      if (created) await fs.unlink(temporary).catch(() => {});
      await parent.handle.close();
    }
  }

  async function* walk(start, signal, budget = { visited: 0, truncated: false }, depth = 0) {
    checkAbort(signal);
    if (depth > 32 || budget.visited >= MAX_VISITED) { budget.truncated = true; return; }
    const opened = await openDirectory(start);
    let directory;
    try {
      directory = await fs.opendir(opened.anchor);
      for await (const entry of directory) {
        checkAbort(signal);
        if (++budget.visited > MAX_VISITED) { budget.truncated = true; break; }
        const target = path.join(start, entry.name);
        if (entry.isSymbolicLink() || blocked.some((item) => inside(item, target))) continue;
        if (entry.isDirectory()) {
          yield* walk(target, signal, budget, depth + 1);
        } else if (entry.isFile()) {
          yield target;
        }
      }
      directory = undefined; // for-await closes its directory, including on break.
      await verifyDirectory(opened.handle, opened.target);
    } finally {
      await directory?.close().catch(() => {});
      await opened.handle.close();
    }
  }

  async function grep(args, signal) {
    const pattern = requiredString(args.pattern, 'pattern', 1024);
    const start = resolveWorkspace(args.path ?? '.', { directory: true });
    const matcher = new Worker(new URL('./regex-worker.mjs', import.meta.url), {
      workerData: { pattern, ignoreCase: args.ignore_case === true },
      resourceLimits: { maxOldGenerationSizeMb: 32 },
    });
    let pending;
    let terminalError;
    let sequence = 0;
    const fail = (error) => { terminalError = error; pending?.reject(error); pending = undefined; };
    const timer = setTimeout(() => { fail(new HostError('grep exceeded its time limit')); void matcher.terminate(); }, grepTimeoutMs);
    const abort = () => { fail(signal.reason ?? new Error('Operation aborted')); void matcher.terminate(); };
    signal?.addEventListener('abort', abort, { once: true });
    matcher.on('error', fail);
    matcher.on('exit', (code) => { if (pending) fail(new HostError(`grep worker stopped (exit ${code})`)); });
    matcher.on('message', (message) => {
      if (message.error) { fail(new HostError(`Invalid grep pattern: ${message.error}`)); return; }
      if (pending) { const waiter = pending; pending = undefined; waiter.resolve(message); }
    });
    const receive = () => terminalError ? Promise.reject(terminalError) : new Promise((resolve, reject) => { pending = { resolve, reject }; });
    try {
      await receive();
      checkAbort(signal);
      const output = [];
      let outputBytes = 0;
      let matches = 0;
      const budget = { visited: 0, truncated: false };
      const startStat = await fs.lstat(start);
      if (startStat.isSymbolicLink()) throw new HostError('Symbolic links are not allowed');
      const files = startStat.isFile() ? (async function* () { yield start; })() : walk(start, signal, budget);
      for await (const filePath of files) {
        let text;
        try { ({ text } = await readText(filePath, signal, 1024 * 1024)); } catch (error) {
          checkAbort(signal);
          if (/Binary files|read limit/.test(messageOf(error))) continue;
          throw error;
        }
        const reply = receive();
        matcher.postMessage({ id: ++sequence, text, limit: 1000 - matches });
        const result = await reply;
        for (const match of result.matches) {
          const line = `${path.relative(root, filePath)}:${match.line}:${match.text}`;
          output.push(line);
          outputBytes += Buffer.byteLength(line) + 1;
          matches++;
        }
        if (matches >= 1000 || outputBytes > outputLimit) { budget.truncated = true; break; }
      }
      return bounded(`${output.join('\n')}${budget.truncated ? '\n[search truncated]' : ''}`, outputLimit);
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      await matcher.terminate();
    }
  }

  async function execute(request, { signal } = {}) {
    try {
      checkAbort(signal);
      if (!request || typeof request !== 'object') throw new HostError('Invalid tool request');
      const args = typeof request.arguments === 'string' ? JSON.parse(request.arguments) : request.arguments;
      if (!args || typeof args !== 'object' || Array.isArray(args)) throw new HostError('Tool arguments must be an object');
      let content;
      switch (request.name) {
        case 'read': {
          const target = resolveWorkspace(args.file_path);
          const { text } = await readText(target, signal);
          const offset = integer(args.offset1 ?? args.offset, 1, 1, 1_000_000, 'offset1');
          const limit = integer(args.limit, 200, 1, 2000, 'limit');
          const lines = text.split('\n');
          content = lines.slice(offset - 1, offset - 1 + limit).map((line, index) => `${offset + index}: ${line}`).join('\n');
          if (offset - 1 + limit < lines.length) content += `\n[${lines.length - (offset - 1 + limit)} more lines]`;
          break;
        }
        case 'write': {
          const target = resolveWorkspace(args.file_path);
          const bytes = await writeAtomic(target, requiredString(args.content, 'content'), signal);
          content = `Wrote ${bytes} bytes to ${path.relative(root, target)}.`;
          break;
        }
        case 'edit': {
          const target = resolveWorkspace(args.file_path);
          const oldString = requiredString(args.old_string, 'old_string');
          const newString = requiredString(args.new_string, 'new_string');
          if (!oldString) throw new HostError('old_string must not be empty');
          const { text, stat } = await readText(target, signal);
          const first = text.indexOf(oldString);
          if (first < 0) throw new HostError('old_string was not found');
          if (args.replace_all !== true && text.indexOf(oldString, first + oldString.length) >= 0) throw new HostError('old_string is ambiguous; provide more context or set replace_all');
          const replacements = args.replace_all === true ? text.split(oldString) : undefined;
          const updated = replacements ? replacements.join(newString) : text.slice(0, first) + newString + text.slice(first + oldString.length);
          await writeAtomic(target, updated, signal, stat);
          content = `Replaced ${replacements ? replacements.length - 1 : 1} occurrence(s) in ${path.relative(root, target)}.`;
          break;
        }
        case 'glob': {
          const pattern = requiredString(args.pattern, 'pattern', 1024);
          if (path.isAbsolute(pattern) || pattern.split(/[\\/]/).includes('..')) throw new HostError('glob pattern must be relative to its search path');
          const start = resolveWorkspace(args.path ?? '.', { directory: true });
          const results = [];
          const budget = { visited: 0, truncated: false };
          for await (const filePath of walk(start, signal, budget)) {
            if (path.matchesGlob(path.relative(start, filePath), pattern)) results.push(path.relative(root, filePath));
            if (results.length >= 1000) { budget.truncated = true; break; }
          }
          content = `${results.sort().join('\n')}${budget.truncated ? '\n[search truncated]' : ''}`;
          break;
        }
        case 'grep': content = await grep(args, signal); break;
        case 'bash': {
          if (!allowShell) throw new HostError('Shell execution is disabled; start the host with --allow-shell to enable explicitly approved bash calls');
          const command = requiredString(args.command, 'command', 32 * 1024);
          const timeout = integer(args.timeout, 30_000, 1, 120_000, 'timeout');
          const result = await runCommand(command, { cwd: root, env: shellEnv, signal, timeout, outputLimit });
          return result;
        }
        default: throw new HostError(`Unknown tool: ${String(request.name)}`);
      }
      return { ok: true, content: bounded(content, outputLimit) };
    } catch (error) {
      return { ok: false, error: bounded(messageOf(error), outputLimit) };
    }
  }

  return { execute, workspace: root };
}

/** Approved shell calls are unrestricted OS commands, not a filesystem sandbox. */
export function runCommand(command, { cwd, env = process.env, signal, timeout = 30_000, outputLimit = OUTPUT_LIMIT } = {}) {
  checkAbort(signal);
  return new Promise((resolve) => {
    const child = spawn(process.platform === 'win32' ? 'cmd.exe' : '/bin/bash', process.platform === 'win32' ? ['/d', '/s', '/c', command] : ['-c', command], {
      cwd, env, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
    });
    const chunks = [];
    let bytes = 0;
    let truncated = false;
    let stopReason;
    let spawnError;
    let escalation;
    const kill = (signalName) => {
      if (!child.pid) return;
      try {
        if (process.platform !== 'win32') process.kill(-child.pid, signalName);
        else child.kill(signalName);
      } catch (error) { if (error.code !== 'ESRCH') spawnError ??= error; }
    };
    const stop = (reason) => {
      if (stopReason) return;
      stopReason = reason;
      kill('SIGTERM');
      escalation = setTimeout(() => kill('SIGKILL'), 250);
    };
    const timer = setTimeout(() => stop(`Command timed out after ${timeout} ms`), timeout);
    const abort = () => stop('Command cancelled');
    signal?.addEventListener('abort', abort, { once: true });
    const collect = (chunk) => {
      const remaining = outputLimit - bytes;
      if (remaining > 0) { const kept = chunk.subarray(0, remaining); chunks.push(kept); bytes += kept.length; }
      if (chunk.length > remaining) truncated = true;
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    child.once('error', (error) => { spawnError = error; });
    child.once('exit', () => {
      // A background grandchild can keep pipes or CPU alive after the shell exits.
      // Every tool call owns its process group; it never leaves a daemon behind.
      kill('SIGKILL');
    });
    child.once('close', (code, killedBy) => {
      clearTimeout(timer);
      clearTimeout(escalation);
      signal?.removeEventListener('abort', abort);
      const content = bounded(`${Buffer.concat(chunks, bytes).toString('utf8')}${truncated ? '\n[output truncated]' : ''}`, outputLimit);
      if (stopReason || spawnError || code !== 0) {
        resolve({ ok: false, error: bounded(`${stopReason ?? (spawnError ? messageOf(spawnError) : `Command exited ${code ?? killedBy}`)}${content ? `\n${content}` : ''}`, outputLimit) });
      } else resolve({ ok: true, content });
    });
    if (signal?.aborted) abort();
  });
}
