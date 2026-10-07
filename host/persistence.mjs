import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import { HostError } from './errors.mjs';

const NOFOLLOW = constants.O_NOFOLLOW ?? 0;
const SNAPSHOT_LIMIT = 32 * 1024 * 1024;

function liveProcess(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return true;
  try { process.kill(pid, 0); return true; } catch (error) { return error.code !== 'ESRCH'; }
}

async function readRegular(target, limit = SNAPSHOT_LIMIT) {
  const file = await fs.open(target, constants.O_RDONLY | NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > limit) throw new HostError('Invalid or oversized persistence file');
    const bytes = Buffer.alloc(stat.size + 1);
    const { bytesRead } = await file.read(bytes, 0, bytes.length, 0);
    if (bytesRead > limit || bytesRead !== stat.size) throw new HostError('Persistence file changed while reading it');
    return bytes.subarray(0, bytesRead).toString('utf8');
  } finally { await file.close(); }
}

function refuseNativeEnvelope(snapshot) {
  let value;
  try { value = JSON.parse(snapshot); } catch {
    throw new HostError('Persistence snapshot contains invalid JSON');
  }
  if (value?.schema === 'dsh.native-host-v1') {
    throw new HostError('This data directory uses the native receipt envelope; start the native host to preserve remote command receipts.', { status: 409 });
  }
}

/** One host owns this local directory. Snapshots are fsynced before effects run. */
export async function openPersistence(dataDir) {
  const requested = path.resolve(dataDir);
  await fs.mkdir(requested, { recursive: true, mode: 0o700 });
  const existing = await fs.lstat(requested);
  if (existing.isSymbolicLink() || !existing.isDirectory()) throw new HostError('Data directory must be a regular directory, not a symbolic link');
  const directory = await fs.realpath(requested);
  const identity = await fs.stat(directory);
  const lockPath = path.join(directory, 'host.lock');
  const snapshotPath = path.join(directory, 'sessions.json');
  const token = randomUUID();
  const owner = { pid: process.pid, hostname: os.hostname(), token, created_at: new Date().toISOString() };
  let lock;

  async function acquire() {
    try {
      lock = await fs.open(lockPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NOFOLLOW, 0o600);
      await lock.writeFile(JSON.stringify(owner));
      await lock.sync();
      return;
    } catch (error) {
      if (lock) { await lock.close(); lock = undefined; await fs.unlink(lockPath).catch(() => {}); throw error; }
      if (error.code !== 'EEXIST') throw error;
    }
    let previous;
    try { previous = JSON.parse(await readRegular(lockPath, 4096)); } catch {
      throw new HostError(`Data directory is locked or has an invalid lock: ${directory}`, { status: 409 });
    }
    if (previous.hostname !== os.hostname() || liveProcess(previous.pid)) {
      throw new HostError(`Another host owns this data directory (pid ${previous.pid ?? 'unknown'}): ${directory}`, { status: 409 });
    }
    // A separate exclusive recovery marker prevents two stale-lock reclaimers
    // from unlinking a replacement lock owned by a new live process.
    const recoveryPath = path.join(directory, 'host.recovery');
    let recovery;
    try {
      recovery = await fs.open(recoveryPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NOFOLLOW, 0o600);
      await recovery.writeFile(JSON.stringify(owner));
      const current = JSON.parse(await readRegular(lockPath, 4096));
      if (current.token !== previous.token || current.hostname !== os.hostname() || liveProcess(current.pid)) {
        throw new HostError('Host lock changed during recovery; retry starting the host', { status: 409 });
      }
      await fs.unlink(lockPath);
      // No other reclaimer can remove our new live lock. Normal contenders may
      // acquire first; O_EXCL decides which host wins without truncating it.
      lock = await fs.open(lockPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NOFOLLOW, 0o600);
      await lock.writeFile(JSON.stringify(owner));
      await lock.sync();
    } catch (cause) {
      if (cause.code === 'EEXIST') throw new HostError('Another host is acquiring or recovering the data directory; retry starting the host', { status: 409, cause });
      throw cause;
    } finally {
      if (recovery) { await recovery.close(); await fs.unlink(recoveryPath); }
    }
  }

  try { await acquire(); } catch (error) {
    if (lock) {
      const owned = await lock.stat();
      await lock.close();
      try {
        const current = await fs.lstat(lockPath);
        if (current.dev === owned.dev && current.ino === owned.ino) await fs.unlink(lockPath);
      } catch (cleanup) { if (cleanup.code !== 'ENOENT') throw cleanup; }
    }
    throw error;
  }
  let closed = false;

  async function verifyDirectory() {
    if (closed) throw new HostError('Persistence is closed', { status: 503 });
    const current = await fs.lstat(directory);
    if (current.isSymbolicLink() || current.dev !== identity.dev || current.ino !== identity.ino) throw new HostError('Data directory changed during execution', { status: 500 });
  }

  async function save(snapshot) {
    await verifyDirectory();
    if (typeof snapshot !== 'string' || Buffer.byteLength(snapshot) > SNAPSHOT_LIMIT) throw new HostError('Snapshot exceeds the persistence size limit', { status: 500 });
    JSON.parse(snapshot);
    refuseNativeEnvelope(snapshot);
    const temporary = path.join(directory, `.sessions-${token}-${randomUUID()}.tmp`);
    let file;
    try {
      file = await fs.open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NOFOLLOW, 0o600);
      await file.writeFile(snapshot, 'utf8');
      await file.sync();
      await file.close();
      file = undefined;
      await verifyDirectory();
      await fs.rename(temporary, snapshotPath);
      const parent = await fs.open(directory, constants.O_RDONLY | (constants.O_DIRECTORY ?? 0) | NOFOLLOW);
      try { await parent.sync(); } finally { await parent.close(); }
    } finally {
      await file?.close();
      await fs.unlink(temporary).catch((error) => { if (error.code !== 'ENOENT') throw error; });
    }
  }

  async function load() {
    await verifyDirectory();
    try {
      const snapshot = await readRegular(snapshotPath);
      refuseNativeEnvelope(snapshot);
      return snapshot;
    } catch (error) {
      if (error.code === 'ENOENT') return undefined;
      throw error;
    }
  }

  async function close() {
    if (closed) return;
    closed = true;
    await lock.close();
    const current = JSON.parse(await readRegular(lockPath, 4096));
    if (current.token !== token) throw new HostError('Host lock ownership changed; refusing to remove another owner’s lock', { status: 500 });
    await fs.unlink(lockPath);
  }

  return { directory, snapshotPath, load, save, close };
}
