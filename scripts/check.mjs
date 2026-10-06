#!/usr/bin/env node
import { existsSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { capture, projectRoot, run, verifyEnvironment } from './verify-env.mjs';

const portablePackages = ['engine', 'provider', 'plugins', 'api', 'ui'];
const ownPackages = [...portablePackages, 'app'];

function checkPackages(packages, target) {
  const result = capture('moon', ['check', ...packages, '--target', target, '--json']);
  if (result.stderr) process.stderr.write(result.stderr);
  let report;
  try {
    report = JSON.parse(result.stdout);
  } catch {
    throw new Error('moon check did not return a complete JSON result:\n' + result.stdout);
  }
  if (report.version !== 1 || !Array.isArray(report.diagnostics)) {
    throw new Error('Unsupported moon check diagnostic format.');
  }
  // Non-source Moon warnings cannot be attributed to the pinned dependency.
  let ownWarnings = report.summary?.moon_warnings || 0;
  let errors = report.summary?.moon_errors || 0;
  let dependencyWarnings = 0;
  const displayed = new Set();
  for (const diagnostic of report.diagnostics) {
    const path = relative(projectRoot, resolve(projectRoot, diagnostic.path || '.'))
      .split(sep).join('/');
    const hotpathWarning = diagnostic.level === 'warning' &&
      path.startsWith('vendor/hotpath/');
    if (diagnostic.level === 'error') errors += 1;
    if (diagnostic.level === 'warning') {
      if (hotpathWarning) dependencyWarnings += 1;
      else ownWarnings += 1;
    }
    const key = [diagnostic.level, path, diagnostic.loc, diagnostic.message].join('\n');
    if (!displayed.has(key)) {
      const label = hotpathWarning ? 'pinned hotpath warning' : diagnostic.level;
      console.error('[' + label + '] ' + path + ':' + diagnostic.loc + '\n' +
        diagnostic.message);
      displayed.add(key);
    }
  }
  for (const message of report.messages || []) {
    console.error(typeof message === 'string' ? message : JSON.stringify(message));
  }
  if (result.status !== 0 || report.status !== 'success' || errors || ownWarnings) {
    throw new Error('MoonBit check failed for ' + packages.join(', ') + ' (' + target +
      '): ' + errors + ' errors, ' + ownWarnings + ' warnings outside pinned hotpath.');
  }
  console.log('MoonBit check: ' + packages.join(', ') + ' (' + target +
    ') passed; own warnings 0, pinned hotpath warnings ' + dependencyWarnings + '.');
}

function javascriptFiles(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return javascriptFiles(path);
      return entry.isFile() && /\.(?:mjs|cjs|js)$/.test(entry.name) ? [path] : [];
    });
}

try {
  verifyEnvironment();
  run('moon', ['fmt', '--check', ...ownPackages]);
  checkPackages(portablePackages, 'all');
  checkPackages(['app'], 'js');
  const files = ['host', 'web', 'scripts', 'tests']
    .flatMap(directory => javascriptFiles(join(projectRoot, directory)));
  for (const file of files) run(process.execPath, ['--check', file]);
  console.log('JavaScript syntax: ' + files.length + ' source and test files passed.');
} catch (error) {
  console.error('[dsh] ' + error.message);
  process.exitCode = 1;
}
