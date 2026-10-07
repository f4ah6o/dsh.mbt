import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { startWebServer } from '../../host/server.mjs';

async function setup(t, options = {}) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'dsh-http-'));
  await fs.writeFile(path.join(dir, 'index.html'), '<h1>local UI</h1>');
  await fs.writeFile(path.join(dir, 'app.js'), 'export const module = true;');
  await fs.writeFile(path.join(dir, 'secret.txt'), 'SECRET');
  const calls = [];
  const host = {
    backend: { mode: 'demo', model: 'test' },
    state: async () => ({ sessions: [] }),
    call: async (operation, input) => { calls.push({ operation, input }); return { ok: true, result: { operation, input } }; },
    mcp: async (line) => { calls.push({ mcp: JSON.parse(line) }); const value = JSON.parse(line); return value.id === undefined ? '' : JSON.stringify({ jsonrpc: '2.0', id: value.id, result: {} }); },
  };
  const web = await startWebServer({ host, port: 0, webRoot: dir, modulePath: path.join(dir, 'app.js'), ...options });
  t.after(async () => { await web.close(); await fs.rm(dir, { recursive: true, force: true }); });
  return { web, calls };
}

function request(url, { pathname = '/', method = 'GET', headers = {}, body, chunks } = {}) {
  const target = new URL(url);
  return new Promise((resolve, reject) => {
    const outgoing = http.request({ hostname: target.hostname, port: target.port, path: pathname, method, headers }, (incoming) => {
      const pieces = [];
      incoming.on('data', (chunk) => pieces.push(chunk));
      incoming.on('end', () => resolve({ status: incoming.statusCode, headers: incoming.headers, text: Buffer.concat(pieces).toString('utf8') }));
    });
    outgoing.on('error', reject);
    if (chunks) for (const chunk of chunks) outgoing.write(chunk);
    outgoing.end(body);
  });
}

test('loopback HTTP serves only fixed UI assets and delegates semantic API requests', async (t) => {
  const { web, calls } = await setup(t);
  const health = await request(web.url, { pathname: '/health' });
  assert.equal(health.status, 200);
  assert.equal(JSON.parse(health.text).status, 'running');
  const page = await request(web.url);
  assert.equal(page.text, '<h1>local UI</h1>');
  assert.equal(page.headers['x-frame-options'], 'DENY');
  assert.match(page.headers['content-security-policy'], /frame-ancestors 'none'/);
  assert.equal((await request(web.url, { pathname: '/moonbit/app.js' })).status, 200);
  assert.equal((await request(web.url, { pathname: '/secret.txt' })).status, 404);
  assert.equal((await request(web.url, { pathname: '/web/%2e%2e/secret.txt' })).status, 400);
  assert.equal((await request(web.url, { pathname: '/%E0%A4' })).status, 400);
  const result = await request(web.url, { pathname: '/api/call', method: 'POST', headers: { 'content-type': 'application/json', origin: web.url }, body: JSON.stringify({ operation: 'session_create', input: { title: 'test' } }) });
  assert.equal(result.status, 200);
  assert.deepEqual(calls, [{ operation: 'session_create', input: { title: 'test' } }]);
  assert.equal(result.headers['access-control-allow-origin'], undefined);
});

test('Node host legacy API fallback and shared browser bridge assets are served', async (t) => {
  const host = {
    backend: { mode: 'test', model: 'fixture' },
    state: async () => ({ sessions: [] }),
    call: async () => ({ ok: true }),
    mcp: async () => '',
  };
  const web = await startWebServer({
    host,
    port: 0,
    webRoot: fileURLToPath(new URL('../../web/', import.meta.url)),
  });
  t.after(() => web.close());

  const page = await request(web.url);
  assert.equal(page.status, 200);
  assert.match(page.text, /src="\/app\.js"/);
  // The legacy Node host has no versioned snapshot endpoint, so app.js selects
  // legacy-app.js. Verify the real static carrier serves that entrypoint and
  // every module it imports, alongside the generated MoonBit client bridge.
  assert.equal((await request(web.url, { pathname: '/api/v1/snapshot' })).status, 404);
  for (const pathname of [
    '/app.js',
    '/legacy-app.js',
    '/remote-app.js',
    '/remote-client.js',
    '/canvas-renderer.js',
    '/view-model.js',
    '/style.css',
    '/icon.svg',
    '/manifest.webmanifest',
    '/sw.js',
    '/moonbit/client.js',
  ]) {
    const asset = await request(web.url, { pathname });
    assert.equal(asset.status, 200, pathname);
    assert.ok(asset.text.length > 0, pathname);
  }
  const bridge = await request(web.url, { pathname: '/moonbit/client.js' });
  assert.match(bridge.text, /client_init/);
});

test('host, origin and fetch-site checks block cross-site side effects', async (t) => {
  const { web, calls } = await setup(t);
  const basic = { pathname: '/api/call', method: 'POST', body: JSON.stringify({ operation: 'session_send', input: {} }) };
  for (const headers of [
    { 'content-type': 'application/json', origin: 'https://evil.example' },
    { 'content-type': 'application/json', host: 'evil.example' },
    { 'content-type': 'application/json', host: `127.0.0.1.evil.example:${new URL(web.url).port}` },
    { 'content-type': 'application/json', 'sec-fetch-site': 'cross-site' },
  ]) assert.equal((await request(web.url, { ...basic, headers })).status, 403);
  assert.deepEqual(calls, []);
  await assert.rejects(startWebServer({ host: {}, bind: '0.0.0.0' }), /loopback/);
});

test('malformed, wrong-type and oversized bodies produce errors without dispatch', async (t) => {
  const { web, calls } = await setup(t, { bodyLimit: 64 });
  const send = (body, headers = { 'content-type': 'application/json' }) => request(web.url, { pathname: '/api/call', method: 'POST', headers, body });
  assert.equal((await send('{')).status, 400);
  assert.equal((await send('[]')).status, 400);
  assert.equal((await send('{"operation":"x","input":null}')).status, 400);
  assert.equal((await send('{}', { 'content-type': 'text/plain' })).status, 415);
  assert.equal((await send('x'.repeat(65), { 'content-type': 'application/json', 'content-length': '65' })).status, 413);
  const chunked = await request(web.url, { pathname: '/api/call', method: 'POST', headers: { 'content-type': 'application/json' }, chunks: ['x'.repeat(32), 'x'.repeat(40)] });
  assert.equal(chunked.status, 413);
  assert.equal((await request(web.url, { pathname: '/api/call' })).status, 405);
  assert.deepEqual(calls, []);
});

test('MCP carrier forwards JSON-RPC and returns empty notification responses', async (t) => {
  const { web, calls } = await setup(t);
  const send = (body) => request(web.url, { pathname: '/mcp', method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const discover = { jsonrpc: '2.0', id: 1, method: 'server/discover', params: {} };
  const response = await send(discover);
  assert.deepEqual(JSON.parse(response.text), { jsonrpc: '2.0', id: 1, result: {} });
  const notification = await send({ jsonrpc: '2.0', method: 'notifications/test' });
  assert.equal(notification.status, 202);
  assert.equal(notification.text, '');
  assert.deepEqual(calls[0], { mcp: discover });
});
