#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, sep } from 'node:path';
import { installTurtles } from './install-turtles.mjs';
import { projectRoot, verifyEnvironment } from './verify-env.mjs';

function sourceFiles(directory) {
  return readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return sourceFiles(path);
      if (!entry.isFile()) throw new Error('Mutation input must be a regular file: ' + path);
      return [path];
    });
}

function digest(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function inputHashes() {
  const files = {};
  for (const file of [
    ...sourceFiles(join(projectRoot, 'plugins')), join(projectRoot, 'turtles.toml'),
  ]) {
    files[relative(projectRoot, file).split(sep).join('/')] = digest(file);
  }
  return files;
}

let workspace;
try {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--list')) {
    throw new Error('Usage: npm run mutation -- [--list]');
  }
  const listOnly = args[0] === '--list';
  const environment = verifyEnvironment();
  const binary = installTurtles(environment);
  const output = join(projectRoot, '_build', 'mutation', 'plugins');
  mkdirSync(output, { recursive: true });
  workspace = mkdtempSync(join(tmpdir(), 'dsh-mutation-'));

  // Use the real production files and tests on every run. No maintained mirror
  // or simplified implementation can drift away from the code being shipped.
  const source = join(projectRoot, 'plugins');
  const files = inputHashes();
  cpSync(source, join(workspace, 'plugins'), { recursive: true });
  cpSync(join(projectRoot, 'turtles.toml'), join(workspace, 'turtles.toml'));
  for (const [path, hash] of Object.entries(files)) {
    if (digest(join(workspace, path)) !== hash) {
      throw new Error('Mutation input changed while copying: ' + path);
    }
  }
  writeFileSync(join(workspace, 'moon.mod'),
    'name = "f4ah6o/dsh"\nversion = "0.1.0"\npreferred_target = "native"\n');
  const manifest = {
    scope: 'plugins/plugins.mbt',
    target: 'native',
    tests: 'unchanged production plugins package tests',
    compiler_version: environment.compilerVersion,
    turtles_revision: environment.pins['tools/turtles'],
    files,
  };
  writeFileSync(join(output, listOnly ? 'inputs-list.json' : 'inputs.json'),
    JSON.stringify(manifest, null, 2) + '\n');

  const reportPath = join(output, 'report.json');
  if (!listOnly) rmSync(reportPath, { force: true });
  const turtlesArgs = [
    '--dir', workspace, '--target', 'native', '--jobs', '2', '--timeout', '120',
    '--output-dir', output,
    ...(listOnly ? ['--list'] : ['--json', reportPath]),
  ];
  const result = spawnSync(binary, turtlesArgs, listOnly
    ? { cwd: projectRoot, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }
    : { cwd: projectRoot, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (listOnly) {
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    if (!/^plugins\/plugins\.mbt:\d+:\d+:/m.test(result.stdout) ||
        /failed to parse:/.test(result.stdout + result.stderr)) {
      throw new Error('Mutation inventory is empty or includes a parser failure.');
    }
  }
  if (JSON.stringify(inputHashes()) !== JSON.stringify(files)) {
    throw new Error('Production inputs changed during mutation testing. ' +
      'Run the gate again against the current files.');
  }
  if (result.status !== 0) {
    throw new Error('Mutation gate failed with ' +
      (result.signal ? 'signal ' + result.signal : 'exit ' + result.status) +
      '. Reports, input hashes and survivor diffs: ' + output);
  }
  if (!listOnly) {
    const report = JSON.parse(readFileSync(reportPath, 'utf8'));
    if (report.schema !== 3 || report.target !== 'native' ||
        !Array.isArray(report.mutants) || report.mutants.length === 0 ||
        report.mutants.some(mutant => mutant.path !== 'plugins/plugins.mbt')) {
      throw new Error('Mutation report is empty or does not match the production plugin scope.');
    }
    if (!(report.summary?.killed > 0) || report.summary.survived !== 0 ||
        report.summary.timeout !== 0 ||
        report.mutants.some(mutant => !['KILLED', 'UNVIABLE'].includes(mutant.outcome))) {
      throw new Error('The mutation gate requires at least one viable kill and no survivors or timeouts.');
    }
    console.log('Production plugin mutation gate passed. Input hashes: ' +
      join(output, 'inputs.json'));
  }
} catch (error) {
  console.error('[dsh] ' + error.message);
  process.exitCode = 1;
} finally {
  if (workspace) rmSync(workspace, { recursive: true, force: true });
}
