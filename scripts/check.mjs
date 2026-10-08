#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { capture, projectRoot, run, verifyEnvironment } from './verify-env.mjs';

const portablePackages = [
  'engine', 'provider', 'auth', 'protocol', 'client', 'plugins', 'api', 'ui',
  'verification/retry_math',
];
const ownPackages = [...portablePackages, 'app', 'native', 'browser', 'browser/sw'];

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

function sourceFiles(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return sourceFiles(path);
      return entry.isFile() && /\.(?:js|mjs|cjs|ts|tsx|jsx|mts|cts)$/.test(entry.name)
        ? [path]
        : [];
    });
}

function moonBitFiles(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(entry => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return moonBitFiles(path);
      return entry.isFile() && entry.name.endsWith('.mbt') ? [path] : [];
    });
}

function checkPureMoonBitInventory() {
  const generated = new Set(['web/moonbit/browser.js', 'web/sw.js']);
  const testOnly = path => /(?:\.test\.|\.spec\.)[cm]?js$/.test(path) ||
    path === 'web/browser-smoke.mjs';
  const forbidden = [];
  for (const directory of [
    'app', 'auth', 'browser', 'client', 'engine', 'host', 'native', 'plugins',
    'provider', 'protocol', 'ui', 'web',
  ]) {
    forbidden.push(...sourceFiles(join(projectRoot, directory)).map(file =>
      relative(projectRoot, file).split(sep).join('/')).filter(path => {
        return !generated.has(path) && !testOnly(path);
      }));
  }
  if (forbidden.length) {
    throw new Error('Handwritten production JavaScript/TypeScript remains: ' +
      forbidden.sort().join(', '));
  }
  const html = readFileSync(join(projectRoot, 'web/index.html'), 'utf8');
  const scriptSources = [...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi)]
    .map(match => match[1]);
  const inlineScripts = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>/gi)];
  if (inlineScripts.length || scriptSources.length !== 1 ||
      scriptSources[0] !== '/moonbit/browser.js') {
    throw new Error('web/index.html must load only the compiled MoonBit browser module.');
  }
  console.log('Pure MoonBit product source inventory passed; web JS is compiler output only.');
}

function checkFfiInventory() {
  const auditedSymbols = [
    'dsh_auth_open_url', 'dsh_auth_random', 'dsh_auth_unix_time',
    'dsh_crypto_sha256', 'dsh_crypto_verify_rs256', 'dsh_exec_worker',
    'dsh_fs_atomic_write', 'dsh_fs_close', 'dsh_fs_create_exclusive',
    'dsh_fs_list_dir', 'dsh_fs_mapping_matches', 'dsh_fs_open_file',
    'dsh_fs_open_root', 'dsh_fs_read_fd', 'dsh_fs_root_matches',
    'dsh_fs_set_root_mode', 'dsh_fs_stat_fd', 'dsh_fs_stat_root', 'dsh_fs_unlink',
    'dsh_kill_process', 'dsh_kill_process_group', 'dsh_os_flush_stderr',
    'dsh_os_flush_stdout', 'dsh_os_hard_worker_memory_supported', 'dsh_os_hostname',
    'dsh_os_pid', 'dsh_os_process_alive', 'dsh_os_stdin_is_terminal',
    'dsh_os_timestamp', 'dsh_os_uid', 'dsh_service_signals_install',
    'dsh_service_signals_requested', 'dsh_service_signals_restore',
  ].sort();
  const declarations = [];
  for (const file of moonBitFiles(join(projectRoot, 'native'))) {
    const source = readFileSync(file, 'utf8');
    for (const match of source.matchAll(/extern\s+"C"\s+fn[\s\S]*?=\s*"(dsh_[^"]+)"/g)) {
      declarations.push(match[1]);
    }
  }
  const unexpectedFfi = [];
  for (const directory of [
    'app', 'auth', 'browser', 'client', 'engine', 'plugins', 'provider',
    'protocol', 'ui', 'verification',
  ]) {
    for (const file of moonBitFiles(join(projectRoot, directory))) {
      const source = readFileSync(file, 'utf8');
      if (/extern\s+"C"\s+fn/.test(source) ||
          (directory !== 'browser' && /extern\s+"js"\s+fn/.test(source))) {
        unexpectedFfi.push(relative(projectRoot, file).split(sep).join('/'));
      }
    }
  }
  if (unexpectedFfi.length) {
    throw new Error('Foreign-function declarations moved outside their audited packages: ' +
      unexpectedFfi.sort().join(', '));
  }
  const actual = [...new Set(declarations)].sort();
  if (JSON.stringify(actual) !== JSON.stringify(auditedSymbols)) {
    throw new Error('Native C FFI changed; update and review docs/ffi-boundary.md.\n' +
      'Expected: ' + auditedSymbols.join(', ') + '\nFound: ' + actual.join(', '));
  }
  const cSources = ['native/host_os.c', 'native/oauth_os.c', 'native/signal_os.c']
    .map(path => readFileSync(join(projectRoot, path), 'utf8')).join('\n');
  const missing = auditedSymbols.filter(symbol =>
    !new RegExp('\\b' + symbol + '\\s*\\(').test(cSources));
  if (missing.length) throw new Error('Native C FFI symbols have no implementation: ' + missing.join(', '));
  console.log('Native C FFI inventory passed; no unreviewed extern declarations.');
}

try {
  verifyEnvironment();
  run('moon', ['fmt', '--check', ...ownPackages]);
  checkPackages(portablePackages, 'all');
  checkPackages(['app'], 'js');
  checkPackages(['native'], 'native');
  checkPackages(['browser', 'browser/sw'], 'js');
  checkPureMoonBitInventory();
  checkFfiInventory();
  const files = ['web', 'scripts', 'tests']
    .flatMap(directory => javascriptFiles(join(projectRoot, directory)));
  for (const file of files) run(process.execPath, ['--check', file]);
  console.log('JavaScript syntax: ' + files.length + ' source and test files passed.');
} catch (error) {
  console.error('[dsh] ' + error.message);
  process.exitCode = 1;
}
