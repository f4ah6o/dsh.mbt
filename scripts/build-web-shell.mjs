import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = fileURLToPath(new URL('../', import.meta.url));
const checkOnly = process.argv.includes('--check');
const outputDirectory = checkOnly
  ? await mkdtemp(path.join(os.tmpdir(), 'dsh-shell-build-'))
  : path.join(root, 'web');
const generatedFiles = ['yami-kumo-shell.js', 'yami-kumo-shell.css'];

async function compile() {
  await build({
    absWorkingDir: root,
    entryPoints: ['ui/main.tsx'],
    outfile: path.join(outputDirectory, 'yami-kumo-shell.js'),
    bundle: true,
    format: 'esm',
    platform: 'browser',
    target: ['es2022'],
    jsx: 'automatic',
    minify: true,
    legalComments: 'inline',
    treeShaking: true,
    define: { 'process.env.NODE_ENV': '"production"' },
    logLevel: 'silent',
  });
}

try {
  await compile();
  if (checkOnly) {
    for (const name of generatedFiles) {
      const actual = await readFile(path.join(root, 'web', name)).catch(() => null);
      const expected = await readFile(path.join(outputDirectory, name));
      if (!actual || !actual.equals(expected)) {
        throw new Error(`web/${name} is stale; run npm run build:shell and commit the rebuilt asset.`);
      }
    }
    process.stdout.write('Yami-kumo browser shell matches its checked-in build.\n');
  } else {
    process.stdout.write('Built web/yami-kumo-shell.js and web/yami-kumo-shell.css.\n');
  }
} finally {
  if (checkOnly) await rm(outputDirectory, { recursive: true, force: true });
}
