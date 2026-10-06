import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createWorkspaceTools, runCommand } from '../../host/tools.mjs';

async function setup(t, options = {}) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-tools-'));
  const workspace = path.join(base, 'workspace');
  const outside = path.join(base, 'outside');
  await fs.mkdir(workspace);
  await fs.mkdir(outside);
  t.after(() => fs.rm(base, { recursive: true, force: true }));
  const tools = await createWorkspaceTools({ workspace, ...options });
  return { base, workspace, outside, tools };
}

test('read, atomic write and edit preserve line numbers and reject ambiguous edits', async (t) => {
  const { tools, workspace } = await setup(t);
  const written = await tools.execute({ name: 'write', arguments: { file_path: 'src/main.mbt', content: 'first\nsecond\nfirst\n' } });
  assert.equal(written.ok, true);
  assert.equal((await tools.execute({ name: 'read', arguments: { file_path: 'src/main.mbt', offset1: 2, limit: 1 } })).content, '2: second\n[2 more lines]');
  const ambiguous = await tools.execute({ name: 'edit', arguments: { file_path: 'src/main.mbt', old_string: 'first', new_string: 'updated' } });
  assert.equal(ambiguous.ok, false);
  assert.match(ambiguous.error, /ambiguous/);
  assert.equal((await tools.execute({ name: 'edit', arguments: { file_path: 'src/main.mbt', old_string: 'first', new_string: 'updated', replace_all: true } })).ok, true);
  assert.equal(await fs.readFile(path.join(workspace, 'src/main.mbt'), 'utf8'), 'updated\nsecond\nupdated\n');
  assert.deepEqual((await fs.readdir(path.join(workspace, 'src'))).sort(), ['main.mbt']);
});

test('all file access rejects escapes and final or ancestor symlinks', async (t) => {
  const { tools, workspace, outside } = await setup(t);
  await fs.writeFile(path.join(outside, 'secret.txt'), 'outside sentinel');
  await fs.symlink(outside, path.join(workspace, 'linked-directory'));
  await fs.symlink(path.join(outside, 'secret.txt'), path.join(workspace, 'linked-file'));
  await fs.writeFile(path.join(workspace, 'inside.txt'), 'inside');
  await fs.symlink('inside.txt', path.join(workspace, 'internal-link'));
  for (const file_path of ['../outside/secret.txt', path.join(outside, 'secret.txt'), 'linked-directory/secret.txt', 'linked-file', 'internal-link']) {
    for (const [name, extra] of [['read', {}], ['write', { content: 'overwritten' }], ['edit', { old_string: 'outside', new_string: 'overwritten' }]]) {
      const result = await tools.execute({ name, arguments: { file_path, ...extra } });
      assert.equal(result.ok, false, `${name} ${file_path}`);
    }
  }
  assert.equal((await tools.execute({ name: 'write', arguments: { file_path: 'linked-directory/new.txt', content: 'escape' } })).ok, false);
  assert.equal(await fs.readFile(path.join(outside, 'secret.txt'), 'utf8'), 'outside sentinel');
  await assert.rejects(fs.stat(path.join(outside, 'new.txt')), { code: 'ENOENT' });
  assert.equal(await fs.readFile(path.join(workspace, 'inside.txt'), 'utf8'), 'inside');
});

test('glob and regex grep are bounded and exclude protected host state and symlinks', async (t) => {
  const { workspace, outside } = await setup(t);
  const data = path.join(workspace, '.dsh.mbt');
  await fs.mkdir(data);
  await fs.writeFile(path.join(data, 'sessions.json'), 'secret');
  await fs.mkdir(path.join(workspace, 'src'));
  await fs.writeFile(path.join(workspace, 'src/a.mbt'), 'alpha\nbeta 42\ngamma\n');
  await fs.writeFile(path.join(workspace, 'b.mbt'), 'beta 7\n');
  await fs.writeFile(path.join(outside, 'escape.mbt'), 'beta SECRET');
  await fs.symlink(outside, path.join(workspace, 'link'));
  const tools = await createWorkspaceTools({ workspace, protectedPaths: [data] });
  assert.equal((await tools.execute({ name: 'glob', arguments: { pattern: '**/*.mbt' } })).content, 'b.mbt\nsrc/a.mbt');
  const result = await tools.execute({ name: 'grep', arguments: { pattern: '^beta \\d+$' } });
  assert.equal(result.ok, true, result.error);
  assert.deepEqual(result.content.split('\n').sort(), ['b.mbt:1:beta 7', 'src/a.mbt:2:beta 42']);
  assert.equal((await tools.execute({ name: 'read', arguments: { file_path: '.dsh.mbt/sessions.json' } })).ok, false);
  assert.equal((await tools.execute({ name: 'grep', arguments: { pattern: '[' } })).ok, false);
  assert.equal((await tools.execute({ name: 'glob', arguments: { pattern: '../*' } })).ok, false);
});

test('protected paths canonicalize symlink aliases and missing descendants', async (t) => {
  const { base, workspace } = await setup(t);
  const protectedDirectory = path.join(workspace, '.dsh.mbt');
  await fs.mkdir(protectedDirectory);
  const alias = path.join(base, 'workspace-alias');
  await fs.symlink(workspace, alias);
  const tools = await createWorkspaceTools({
    workspace,
    protectedPaths: [path.join(alias, '.dsh.mbt', 'sessions.json')],
  });
  const result = await tools.execute({ name: 'read', arguments: { file_path: '.dsh.mbt/sessions.json' } });
  assert.equal(result.ok, false);
  assert.match(result.error, /Host data is not accessible/);
});

test('catastrophic regular expressions cannot block the host event loop', { timeout: 4000 }, async (t) => {
  const { workspace } = await setup(t);
  await fs.writeFile(path.join(workspace, 'long.txt'), `${'a'.repeat(50_000)}!`);
  const tools = await createWorkspaceTools({ workspace, grepTimeoutMs: 250 });
  let ticked = false;
  const timer = setTimeout(() => { ticked = true; }, 50);
  const result = await tools.execute({ name: 'grep', arguments: { pattern: '(a+)+$' } });
  clearTimeout(timer);
  assert.equal(ticked, true);
  assert.equal(result.ok, false);
  assert.match(result.error, /time limit/);
});

test('output limits and aborted file operations are explicit', async (t) => {
  const { workspace } = await setup(t);
  await fs.writeFile(path.join(workspace, 'large.txt'), 'x'.repeat(400));
  const tools = await createWorkspaceTools({ workspace, outputLimit: 64 });
  const result = await tools.execute({ name: 'read', arguments: { file_path: 'large.txt' } });
  assert.equal(result.ok, true);
  assert.match(result.content, /output truncated/);
  const controller = new AbortController();
  controller.abort(new Error('test abort'));
  const write = await tools.execute({ name: 'write', arguments: { file_path: 'cancelled', content: 'x' } }, { signal: controller.signal });
  assert.equal(write.ok, false);
  await assert.rejects(fs.stat(path.join(workspace, 'cancelled')), { code: 'ENOENT' });
});

test('bash requires capability enablement and bounds output, duration and cancellation', { skip: process.platform === 'win32', timeout: 5000 }, async (t) => {
  const { tools, workspace } = await setup(t);
  const disabled = await tools.execute({ name: 'bash', arguments: { command: 'printf denied' } });
  assert.equal(disabled.ok, false);
  assert.match(disabled.error, /disabled/);
  assert.deepEqual(await runCommand('printf success', { cwd: workspace }), { ok: true, content: 'success' });
  const huge = await runCommand('printf "%01000d" 0', { cwd: workspace, outputLimit: 40 });
  assert.equal(huge.ok, true);
  assert.match(huge.content, /output truncated/);
  const timeout = await runCommand('sleep 30 & wait', { cwd: workspace, timeout: 30 });
  assert.equal(timeout.ok, false);
  assert.match(timeout.error, /timed out/);
  const controller = new AbortController();
  const pending = runCommand('sleep 30 & wait', { cwd: workspace, signal: controller.signal });
  setTimeout(() => controller.abort(), 30);
  const cancelled = await pending;
  assert.equal(cancelled.ok, false);
  assert.match(cancelled.error, /cancelled/);
});
