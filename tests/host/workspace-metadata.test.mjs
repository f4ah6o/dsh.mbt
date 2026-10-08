import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { modelDisplayName, providerDisplayName, resolveWorkspaceMetadata } from '../../host/workspace-metadata.mjs';

function git(directory, ...args) {
  return execFileSync('git', ['-C', directory, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

async function temporaryDirectory(t, name = 'dsh metadata ') {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), name));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

async function makeRepository(directory) {
  await fs.mkdir(directory, { recursive: true });
  git(directory, 'init', '--quiet', '-b', 'main');
  git(directory, 'config', 'user.name', 'Metadata Test');
  git(directory, 'config', 'user.email', 'metadata@example.invalid');
  await fs.writeFile(path.join(directory, 'README.md'), 'metadata fixture\n');
  git(directory, 'add', 'README.md');
  git(directory, 'commit', '--quiet', '-m', 'initial');
}

test('non-Git workspaces keep their project name and report no repository', async (t) => {
  const workspace = await temporaryDirectory(t, 'dsh plain project ');
  const metadata = await resolveWorkspaceMetadata(workspace);
  assert.equal(metadata.project, path.basename(workspace));
  assert.equal(metadata.repository, null);
});

test('Git worktrees expose only repository name and the active branch', async (t) => {
  const parent = await temporaryDirectory(t, 'dsh git metadata ');
  const repository = path.join(parent, 'sample-repository');
  const worktree = path.join(parent, 'sample-worktree');
  await makeRepository(repository);
  git(repository, 'branch', 'worktree/context');
  git(repository, 'worktree', 'add', '--quiet', worktree, 'worktree/context');

  const metadata = await resolveWorkspaceMetadata(worktree);
  assert.equal(metadata.project, 'sample-worktree');
  assert.deepEqual(metadata.repository, {
    name: 'sample-repository',
    branch: 'worktree/context',
    detached: false,
  });
  assert.equal(await fs.readFile(path.join(worktree, '.git'), 'utf8').then(() => true, () => false), true,
    'the fixture uses Git’s .git file worktree layout');
});

test('detached HEAD and branch changes are reflected by a fresh metadata read', async (t) => {
  const repository = path.join(await temporaryDirectory(t, 'dsh git branch '), 'project');
  await makeRepository(repository);

  const first = await resolveWorkspaceMetadata(repository);
  assert.equal(first.repository.branch, 'main');
  git(repository, 'branch', '-m', 'changed-branch');
  const changed = await resolveWorkspaceMetadata(repository);
  assert.equal(changed.repository.branch, 'changed-branch');

  git(repository, 'checkout', '--quiet', '--detach', 'HEAD');
  const detached = await resolveWorkspaceMetadata(repository);
  assert.equal(detached.repository.detached, true);
  assert.match(detached.repository.branch, /^[0-9a-f]{12}$/);
});

test('provider and model labels come from safe identifiers without endpoint credentials', () => {
  const secret = 'sk-test-secret-value';
  assert.equal(providerDisplayName('deepseek'), 'DeepSeek');
  assert.equal(providerDisplayName('openai'), 'OpenAI');
  assert.equal(providerDisplayName('openai', 'api-key', 'https://user:password@provider.example/private/path?api_key=secret'), 'provider.example');
  assert.equal(providerDisplayName('openai', 'api-key', 'https://sk-live-secret-value.example/v1'), 'OpenAI 互換 API');
  assert.equal(providerDisplayName('openai-responses', 'chatgpt'), 'ChatGPT');
  assert.equal(providerDisplayName('demo'), 'デモ');
  assert.equal(modelDisplayName('gpt-5.1-codex'), 'gpt-5.1-codex');
  assert.equal(modelDisplayName(secret), 'カスタムモデル');
  assert.doesNotMatch(providerDisplayName('openai'), new RegExp(secret));
});
