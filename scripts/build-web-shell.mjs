#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const checkOnly = process.argv.includes('--check');
const buildDirectory = path.join(root, '_build/js/release/build/f4ah6o/dsh/browser');
const browserModule = path.join(buildDirectory, 'browser.js');
const serviceWorkerModule = path.join(buildDirectory, 'sw/sw.js');
const yamiSource = path.join(root, 'vendor/yami-kumo');
const shellStyles = [
  path.join(root, 'ui/yami-kumo/styles.css'),
  path.join(root, 'ui/dsh.css'),
];
const outputs = [
  {
    destination: path.join(root, 'web/moonbit/browser.js'),
    source: browserModule,
  },
  {
    destination: path.join(root, 'web/sw.js'),
    source: serviceWorkerModule,
  },
  {
    destination: path.join(root, 'web/kumo-standalone.css'),
    source: path.join(yamiSource, 'styles/kumo-standalone.css'),
  },
  {
    destination: path.join(root, 'web/yami-kumo-components.css'),
    source: path.join(yamiSource, 'styles/yami-kumo-components.css'),
  },
  {
    destination: path.join(root, 'web/yami-kumo-shell.css'),
    sources: shellStyles,
  },
];

async function expectedBytes(output) {
  if (output.sources) {
    const parts = await Promise.all(output.sources.map((source) => readFile(source)));
    return Buffer.concat(parts.flatMap((part, index) =>
      index === 0 ? [part] : [Buffer.from('\n'), part],
    ));
  }
  return readFile(output.source);
}

execFileSync('moon', ['build', 'browser', '--target', 'js', '--release'], {
  cwd: root,
  stdio: 'inherit',
});
execFileSync('moon', ['build', 'browser/sw', '--target', 'js', '--release'], {
  cwd: root,
  stdio: 'inherit',
});

if (checkOnly) {
  for (const output of outputs) {
    const actual = await readFile(output.destination).catch(() => null);
    const expected = await expectedBytes(output);
    if (!actual || !actual.equals(expected)) {
      const relative = path.relative(root, output.destination).split(path.sep).join('/');
      throw new Error(`${relative} is stale; run npm run build:shell and commit the rebuilt asset.`);
    }
  }
  process.stdout.write('MoonBit browser and service-worker modules plus pinned Yami-kumo CSS match their sources.\n');
} else {
  for (const output of outputs) {
    await mkdir(path.dirname(output.destination), { recursive: true });
    if (output.sources) {
      await writeFile(output.destination, await expectedBytes(output));
    } else if (output.source !== output.destination) {
      await copyFile(output.source, output.destination);
    }
  }
  process.stdout.write('Built web/moonbit/browser.js and web/sw.js with pinned Yami-kumo CSS assets.\n');
}
