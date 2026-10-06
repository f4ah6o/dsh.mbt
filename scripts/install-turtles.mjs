#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { capture, projectRoot, run, verifyEnvironment } from './verify-env.mjs';

function digest(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

export function installTurtles(environment = verifyEnvironment()) {
  const directory = join(projectRoot, '_build', 'tools');
  const binary = join(directory, process.platform === 'win32' ? 'turtles.exe' : 'turtles');
  const provenance = join(directory, 'turtles-build.json');
  const expected = {
    source_revision: environment.pins['tools/turtles'],
    compiler_version: environment.compilerVersion,
    moon_version: environment.moonVersion,
    turtles_version: environment.turtlesVersion,
  };
  let cached;
  try {
    cached = JSON.parse(readFileSync(provenance, 'utf8'));
  } catch {
    cached = null;
  }
  if (cached && existsSync(binary) &&
      Object.entries(expected).every(([key, value]) => cached[key] === value) &&
      cached.sha256 === digest(binary)) {
    const version = capture(binary, ['--version']);
    if (version.status === 0 &&
        version.stdout.trim() === 'turtles ' + environment.turtlesVersion) {
      console.log('Using turtles ' + environment.turtlesVersion + ' from source ' +
        expected.source_revision + '.');
      return binary;
    }
  }

  mkdirSync(directory, { recursive: true });
  // A fresh official toolchain has no registry index for turtles' dependencies.
  run('moon', ['update']);
  run('moon', ['install', './tools/turtles/cmd/turtles', '--bin', directory]);
  const version = capture(binary, ['--version']);
  if (version.status !== 0 ||
      version.stdout.trim() !== 'turtles ' + environment.turtlesVersion) {
    throw new Error('The installed turtles binary does not match its pinned source version.');
  }
  writeFileSync(provenance, JSON.stringify({ ...expected, sha256: digest(binary) }, null, 2) + '\n');
  return binary;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    installTurtles();
  } catch (error) {
    console.error('[dsh] ' + error.message);
    process.exitCode = 1;
  }
}
