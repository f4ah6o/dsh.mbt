import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { openPersistence } from '../../host/persistence.mjs';

async function directory(t) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-persistence-'));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  return dir;
}

test('single writer lock and atomic snapshots survive clean restart', async (t) => {
  const dir = await directory(t);
  const first = await openPersistence(dir);
  t.after(() => first.close());
  await assert.rejects(openPersistence(dir), /Another host owns/);
  await first.save('{"sessions":[]}');
  assert.equal(await first.load(), '{"sessions":[]}');
  await first.save('{"sessions":[{"id":"s1"}]}');
  assert.equal(await first.load(), '{"sessions":[{"id":"s1"}]}');
  assert.ok(!(await fs.readdir(dir)).some((name) => name.endsWith('.tmp')));
  if (process.platform !== 'win32') assert.equal((await fs.stat(path.join(dir, 'sessions.json'))).mode & 0o777, 0o600);
  await first.close();
  const second = await openPersistence(dir);
  try { assert.equal(await second.load(), '{"sessions":[{"id":"s1"}]}'); } finally { await second.close(); }
});

test('only a verifiably dead local lock owner can be recovered', async (t) => {
  const dir = await directory(t);
  await fs.writeFile(path.join(dir, 'host.lock'), JSON.stringify({ pid: 2147483647, hostname: os.hostname(), token: 'dead-owner' }));
  const recovered = await openPersistence(dir);
  try {
    const current = JSON.parse(await fs.readFile(path.join(dir, 'host.lock'), 'utf8'));
    assert.equal(current.pid, process.pid);
    assert.notEqual(current.token, 'dead-owner');
    await assert.rejects(fs.stat(path.join(dir, 'host.recovery')), { code: 'ENOENT' });
  } finally { await recovered.close(); }
  await fs.writeFile(path.join(dir, 'host.lock'), JSON.stringify({ pid: 2147483647, hostname: 'unknown-other-machine', token: 'remote' }));
  await assert.rejects(openPersistence(dir), /Another host owns/);
  assert.equal(JSON.parse(await fs.readFile(path.join(dir, 'host.lock'), 'utf8')).token, 'remote');
});

test('snapshot and data-directory symlinks do not follow external files', async (t) => {
  const dir = await directory(t);
  const data = path.join(dir, 'data');
  const outside = path.join(dir, 'outside.txt');
  await fs.writeFile(outside, 'outside');
  const persistence = await openPersistence(data);
  try {
    await fs.symlink(outside, path.join(data, 'sessions.json'));
    await assert.rejects(persistence.load());
    await persistence.save('{"safe":true}');
    assert.equal(await fs.readFile(outside, 'utf8'), 'outside');
    assert.equal(await persistence.load(), '{"safe":true}');
  } finally { await persistence.close(); }
  await fs.symlink(data, path.join(dir, 'alias'));
  await assert.rejects(openPersistence(path.join(dir, 'alias')), /symbolic link/);
});
