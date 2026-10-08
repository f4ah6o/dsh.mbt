import { execFile as nodeExecFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';

const execFile = promisify(nodeExecFile);
const GIT_TIMEOUT_MS = 1000;
const GIT_OUTPUT_LIMIT = 4096;

function cleanDisplayValue(value, fallback) {
  if (typeof value !== 'string' || !value.trim()) return fallback;
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return cleaned.slice(0, 128) || fallback;
}

export function modelDisplayName(value) {
  const model = cleanDisplayValue(value, '未選択');
  // Model identifiers are useful context, but arbitrary environment strings
  // should not become a place where pasted credentials appear in the UI.
  const looksLikeCredential = /(?:^sk[-_]|api[-_]?key|token|secret|password)/i.test(model)
    || /^[A-Za-z0-9_-]{40,}$/.test(model);
  return /^[A-Za-z0-9_.:/+-]{1,128}$/.test(model) && !looksLikeCredential ? model : 'カスタムモデル';
}

export function providerDisplayName(mode, authMode = 'api-key', baseURL) {
  if (mode === 'demo') return 'デモ';
  if (authMode === 'chatgpt') return 'ChatGPT';
  const fallback = mode === 'deepseek'
    ? 'https://api.deepseek.com/anthropic'
    : 'https://api.openai.com';
  let hostname;
  try {
    const url = new URL(baseURL || fallback);
    if (!['http:', 'https:'].includes(url.protocol)) return protocolLabel(mode);
    hostname = url.hostname.toLowerCase().replace(/\.$/, '');
  } catch {
    return protocolLabel(mode);
  }
  if (hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]') return 'ローカル API';
  if (hostname === 'api.deepseek.com' || hostname.endsWith('.deepseek.com')) return 'DeepSeek';
  if (hostname === 'api.openai.com' || hostname.endsWith('.openai.com')) {
    return mode === 'openai-responses' ? 'OpenAI Responses API' : 'OpenAI';
  }
  if (!/^(?:[a-z0-9.-]{1,253}|\[[0-9a-f:]{2,45}\])$/.test(hostname)
    || /(?:^|[.-])sk(?:-|_)/i.test(hostname)
    || /(?:api[-_]?key|token|secret|password)/i.test(hostname)
    || /[a-f0-9]{32,}/i.test(hostname)) return protocolLabel(mode);
  return hostname;
}

function protocolLabel(mode) {
  if (mode === 'deepseek') return 'DeepSeek API';
  if (mode === 'openai-responses') return 'OpenAI Responses API';
  if (mode === 'openai') return 'OpenAI 互換 API';
  return '不明なプロバイダー';
}

async function gitOutput(workspace, args) {
  try {
    const { stdout } = await execFile('git', ['-C', workspace, ...args], {
      cwd: workspace,
      encoding: 'utf8',
      timeout: GIT_TIMEOUT_MS,
      maxBuffer: GIT_OUTPUT_LIMIT,
      windowsHide: true,
      env: {
        PATH: process.env.PATH || '/usr/bin:/bin',
        GIT_CONFIG_NOSYSTEM: '1',
        GIT_OPTIONAL_LOCKS: '0',
        GIT_TERMINAL_PROMPT: '0',
      },
    });
    return stdout.trim();
  } catch {
    return null;
  }
}

export async function resolveWorkspaceMetadata(workspace) {
  const project = cleanDisplayValue(path.basename(workspace) || 'ワークスペース', 'ワークスペース');
  const repositoryPath = await gitOutput(workspace, ['rev-parse', '--show-toplevel']);
  if (!repositoryPath || !path.isAbsolute(repositoryPath)) {
    return { project, repository: null };
  }

  // A linked worktree's top level is the worktree directory itself. The
  // shared Git directory identifies the original repository without exposing
  // its remote URL (which may contain credentials).
  const commonDirValue = await gitOutput(workspace, ['rev-parse', '--git-common-dir']);
  const commonDir = commonDirValue ? path.resolve(workspace, commonDirValue) : null;
  const commonDirName = commonDir ? path.basename(commonDir) : '';
  const repositoryName = commonDirName === '.git'
    ? path.basename(path.dirname(commonDir))
    : commonDirName.endsWith('.git')
      ? commonDirName.slice(0, -4)
      : path.basename(repositoryPath);
  const repository = cleanDisplayValue(repositoryName || path.basename(repositoryPath) || 'Git リポジトリ', 'Git リポジトリ');
  const branchName = await gitOutput(workspace, ['symbolic-ref', '--quiet', '--short', 'HEAD']);
  if (branchName && branchName.length <= 128 && !/[\u0000-\u001f\u007f]/.test(branchName)) {
    return { project, repository: { name: repository, branch: branchName, detached: false } };
  }

  const commit = await gitOutput(workspace, ['rev-parse', '--short=12', 'HEAD']);
  const shortCommit = commit && /^[0-9a-f]{4,40}$/i.test(commit) ? commit : null;
  return {
    project,
    repository: {
      name: repository,
      branch: shortCommit,
      detached: Boolean(shortCommit),
    },
  };
}
