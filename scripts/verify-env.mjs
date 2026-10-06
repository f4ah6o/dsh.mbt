#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const projectRoot = fileURLToPath(new URL('../', import.meta.url));
const dependencyPaths = ['vendor/gpui', 'vendor/hotpath', 'tools/turtles'];
// This is the build/runner release distributed with .moonbit-version.
const expectedBuildVersion = '0.1.20260920';

export function capture(command, args, cwd = projectRoot) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) {
    throw new Error('Cannot run ' + command + ': ' + result.error.message);
  }
  return result;
}

export function run(command, args, cwd = projectRoot) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(command + ' failed with ' +
      (result.signal ? 'signal ' + result.signal : 'exit ' + result.status));
  }
}

function moduleField(path, name) {
  const expression = new RegExp('^\\s*' + name + '\\s*=\\s*"([^"]+)"', 'm');
  const value = readFileSync(path, 'utf8').match(expression)?.[1];
  if (!value) throw new Error('Missing ' + name + ' in ' + path);
  return value;
}

export function verifyEnvironment({ quiet = false } = {}) {
  if (Number(process.versions.node.split('.')[0]) < 24) {
    throw new Error('Node.js 24 or newer is required; found ' + process.versions.node +
      '. Install Node.js 24 and run this command again.');
  }

  const compilerVersion = readFileSync(join(projectRoot, '.moonbit-version'), 'utf8').trim();
  const installHint = 'Install the compiler and core version ' + compilerVersion +
    ' with the official MoonBit installer, and put its bin directory on PATH.';
  let versionResult;
  try {
    versionResult = capture('moon', ['version', '--all']);
  } catch (error) {
    throw new Error(error.message + '\n' + installHint);
  }
  if (versionResult.status !== 0) {
    throw new Error('moon version --all failed:\n' +
      (versionResult.stderr || versionResult.stdout || String(versionResult.signal)) +
      '\n' + installHint);
  }
  const versions = versionResult.stdout;
  const moonVersion = versions.match(/^moon\s+(\S+)/m)?.[1];
  const actualCompiler = versions.match(/^moonc\s+v?(\S+)/m)?.[1];
  const runnerVersion = versions.match(/^moonrun\s+(\S+)/m)?.[1];
  if (actualCompiler !== compilerVersion ||
      moonVersion !== expectedBuildVersion || runnerVersion !== expectedBuildVersion) {
    throw new Error('Toolchain pin mismatch. Expected moonc ' + compilerVersion +
      ' and moon/moonrun ' + expectedBuildVersion + '.\n' + versions + '\n' + installHint);
  }

  const moonHome = process.env.MOON_HOME || join(homedir(), '.moon');
  const coreManifest = join(moonHome, 'lib', 'core', 'moon.mod');
  if (!existsSync(coreManifest)) {
    throw new Error('Cannot verify the pinned core at ' + coreManifest +
      '. Set MOON_HOME to the installed toolchain directory.\n' + installHint);
  }
  const coreVersion = moduleField(coreManifest, 'version');
  if (coreVersion !== compilerVersion) {
    throw new Error('Core pin mismatch: expected ' + compilerVersion +
      ', found ' + coreVersion + '.\n' + installHint);
  }

  const pins = {};
  for (const path of dependencyPaths) {
    const entry = capture('git', ['ls-files', '--stage', '--', path]);
    const pin = entry.stdout.match(/^160000 ([0-9a-f]{40}) 0\t/);
    if (entry.status !== 0 || !pin) {
      throw new Error('Cannot read the pinned gitlink for ' + path +
        '. Use a Git checkout of this repository with its submodules.');
    }
    const directory = join(projectRoot, path);
    if (!existsSync(join(directory, '.git')) || !existsSync(join(directory, 'moon.mod'))) {
      throw new Error('Dependency ' + path + ' is not initialized. Run:\n' +
        '  git submodule update --init --recursive');
    }
    const head = capture('git', ['rev-parse', 'HEAD'], directory);
    if (head.status !== 0 || head.stdout.trim() !== pin[1]) {
      throw new Error('Dependency ' + path + ' does not match gitlink ' + pin[1] +
        '. Preserve any local work, then initialize the pinned checkout with:\n' +
        '  git submodule update --init --recursive -- ' + path);
    }
    const diff = capture('git', ['diff', '--quiet', 'HEAD', '--'], directory);
    if (diff.status !== 0) {
      throw new Error('Dependency ' + path +
        ' has tracked local changes or cannot be checked. Preserve those changes; ' +
        'use a separate clean checkout to verify this pinned dependency.');
    }
    const untracked = capture('git', [
      'ls-files', '--others', '--exclude-standard', '--', '.',
      ':(exclude)_build/**', ':(exclude).mooncakes/**',
      ':(exclude)target/**', ':(exclude)node_modules/**',
    ], directory);
    if (untracked.status !== 0 || untracked.stdout.trim()) {
      throw new Error('Dependency ' + path + ' has untracked inputs outside build caches:\n' +
        untracked.stdout.trim() + '\nPreserve them and use a clean pinned checkout.');
    }
    pins[path] = pin[1];
  }
  const turtlesVersion = moduleField(join(projectRoot, 'tools/turtles/moon.mod'), 'version');
  if (!quiet) {
    console.log('Environment: Node ' + process.versions.node + '; MoonBit ' +
      compilerVersion + '; core and 3 dependency pins verified.');
  }
  return { compilerVersion, moonVersion, turtlesVersion, pins };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    verifyEnvironment();
  } catch (error) {
    console.error('[dsh] ' + error.message);
    process.exitCode = 1;
  }
}
