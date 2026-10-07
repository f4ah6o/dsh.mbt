import http from 'node:http';
import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { HostError, messageOf } from './errors.mjs';
import { defaultModulePath } from './runtime.mjs';

const BODY_LIMIT = 1024 * 1024;
const defaultClientModulePath = fileURLToPath(new URL('../_build/js/release/build/f4ah6o/dsh/client/client.js', import.meta.url));
const ASSETS = new Map([
  ['index.html', 'text/html; charset=utf-8'],
  ['app.js', 'text/javascript; charset=utf-8'],
  ['app.mjs', 'text/javascript; charset=utf-8'],
  ['legacy-app.js', 'text/javascript; charset=utf-8'],
  ['remote-app.js', 'text/javascript; charset=utf-8'],
  ['remote-client.js', 'text/javascript; charset=utf-8'],
  ['canvas-renderer.js', 'text/javascript; charset=utf-8'],
  ['view-model.js', 'text/javascript; charset=utf-8'],
  ['style.css', 'text/css; charset=utf-8'],
  ['styles.css', 'text/css; charset=utf-8'],
  ['favicon.svg', 'image/svg+xml'],
  ['icon.svg', 'image/svg+xml'],
  ['manifest.webmanifest', 'application/manifest+json; charset=utf-8'],
  ['sw.js', 'text/javascript; charset=utf-8'],
]);

function secureHeaders(response) {
  response.setHeader('x-content-type-options', 'nosniff');
  response.setHeader('x-frame-options', 'DENY');
  response.setHeader('referrer-policy', 'no-referrer');
  response.setHeader('cache-control', 'no-store');
  response.setHeader('content-security-policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'");
}

function json(response, status, data) {
  const body = JSON.stringify(data);
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body) });
  response.end(body);
}

function endpointPath(raw) {
  if (typeof raw !== 'string' || !raw.startsWith('/') || raw.startsWith('//') || raw.length > 4096) throw new HostError('Invalid request URL');
  let pathname;
  try { pathname = decodeURIComponent(raw.split('?')[0]); } catch { throw new HostError('Invalid URL encoding'); }
  if (pathname.includes('\\') || pathname.includes('\0') || pathname.split('/').some((part) => part === '..' || part === '.')) throw new HostError('Invalid request path');
  return pathname;
}

async function readJSON(request, limit) {
  const type = (request.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/json') throw new HostError('Content-Type must be application/json', { status: 415 });
  if (request.headers['content-encoding'] && request.headers['content-encoding'] !== 'identity') throw new HostError('Compressed request bodies are not supported', { status: 415 });
  const declared = Number(request.headers['content-length']);
  if (Number.isFinite(declared) && declared > limit) throw new HostError('Request body exceeds its size limit', { status: 413 });
  const bytes = await new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      chunks.length = 0;
      reject(error);
      request.resume();
    };
    request.on('data', (chunk) => {
      if (settled) return;
      size += chunk.length;
      if (size > limit) fail(new HostError('Request body exceeds its size limit', { status: 413 }));
      else chunks.push(chunk);
    });
    request.once('error', fail);
    request.once('aborted', () => fail(new HostError('Request body was interrupted')));
    request.once('end', () => {
      if (!settled) { settled = true; resolve(Buffer.concat(chunks, size)); }
    });
  });
  let body;
  try { body = JSON.parse(bytes.toString('utf8')); } catch { throw new HostError('Malformed JSON request body'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HostError('Request body must be a JSON object');
  return body;
}

function errorStatus(response) {
  if (response.ok) return 200;
  const error = typeof response.error === 'string' ? response.error : '';
  if (/not found/i.test(error)) return 404;
  if (/busy|pending approval|does not match/i.test(error)) return 409;
  return 400;
}

export async function startWebServer({ host, port = 3080, bind = '127.0.0.1', webRoot = fileURLToPath(new URL('../web/', import.meta.url)), modulePath = defaultModulePath, clientModulePath = defaultClientModulePath, bodyLimit = BODY_LIMIT } = {}) {
  if (!host) throw new HostError('A host runtime is required');
  if (!['127.0.0.1', '::1', 'localhost'].includes(bind)) throw new HostError('The web host only binds to loopback addresses');
  if (!Number.isSafeInteger(port) || port < 0 || port > 65535) throw new HostError('port must be between 0 and 65535');
  let actualPort;
  const server = http.createServer({ maxHeaderSize: 16 * 1024, requestTimeout: 30_000, headersTimeout: 10_000 }, async (request, response) => {
    secureHeaders(response);
    request.on('error', () => {});
    try {
      const authority = request.headers.host;
      const allowed = new Set([`127.0.0.1:${actualPort}`, `localhost:${actualPort}`, `[::1]:${actualPort}`]);
      if (actualPort === 80) for (const name of ['127.0.0.1', 'localhost', '[::1]']) allowed.add(name);
      const hostCount = request.rawHeaders.filter((_, index) => index % 2 === 0 && request.rawHeaders[index].toLowerCase() === 'host').length;
      if (hostCount !== 1 || !authority || !allowed.has(authority)) throw new HostError('Host header is not a local server address', { status: 403 });
      if (request.headers.origin && request.headers.origin !== `http://${authority}`) throw new HostError('Cross-origin requests are forbidden', { status: 403 });
      if (request.headers['sec-fetch-site'] === 'cross-site') throw new HostError('Cross-site requests are forbidden', { status: 403 });
      const pathname = endpointPath(request.url);
      if (pathname === '/health' && request.method === 'GET') {
        const status = host.status ?? 'running';
        json(response, status === 'failed' ? 503 : 200, { ok: status !== 'failed', status, backend: host.backend });
        return;
      }
      if (pathname === '/api/state' && request.method === 'GET') {
        json(response, 200, { ok: true, result: await host.state() });
        return;
      }
      if (pathname === '/api/call' && request.method === 'POST') {
        const body = await readJSON(request, bodyLimit);
        if (typeof body.operation !== 'string' || !body.input || typeof body.input !== 'object' || Array.isArray(body.input)) throw new HostError('Expected {operation: string, input: object}');
        const result = await host.call(body.operation, body.input);
        json(response, errorStatus(result), result);
        return;
      }
      if (pathname === '/mcp' && request.method === 'POST') {
        const body = await readJSON(request, bodyLimit);
        const result = await host.mcp(JSON.stringify(body));
        if (!result) { response.writeHead(202); response.end(); }
        else {
          response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(result) });
          response.end(result);
        }
        return;
      }
      if (['/api/state', '/api/call', '/mcp', '/health'].includes(pathname)) throw new HostError('Method not allowed', { status: 405 });
      if (!['GET', 'HEAD'].includes(request.method)) throw new HostError('Method not allowed', { status: 405 });
      let target;
      let contentType;
      if (pathname === '/moonbit/app.js') {
        target = modulePath;
        contentType = 'text/javascript; charset=utf-8';
      } else if (pathname === '/moonbit/client.js') {
        target = clientModulePath;
        contentType = 'text/javascript; charset=utf-8';
      } else {
        const name = pathname === '/' ? 'index.html' : pathname.startsWith('/web/') ? pathname.slice(5) : pathname.slice(1);
        if (!ASSETS.has(name)) throw new HostError('Not found', { status: 404 });
        target = path.join(webRoot, name);
        contentType = ASSETS.get(name);
      }
      const file = await fs.open(target, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
      try {
        const stat = await file.stat();
        if (!stat.isFile() || stat.size > 32 * 1024 * 1024) throw new HostError('Static asset is invalid or oversized', { status: 500 });
        response.writeHead(200, { 'content-type': contentType, 'content-length': stat.size });
        if (request.method === 'HEAD') response.end();
        else response.end(await file.readFile());
      } finally { await file.close(); }
    } catch (error) {
      // Never send internal stacks, request headers, environment, or credentials.
      if (!response.headersSent) json(response, error.code === 'ENOENT' ? 404 : error.status ?? 500, { ok: false, error: error.code === 'ENOENT' ? 'Not found' : messageOf(error) });
      else response.destroy();
      request.resume();
    }
  });
  server.maxHeadersCount = 50;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, bind, () => { server.removeListener('error', reject); resolve(); });
  });
  actualPort = server.address().port;
  const display = bind === '::1' ? '[::1]' : bind;
  let closing;
  return {
    server,
    url: `http://${display}:${actualPort}`,
    close() {
      if (!closing) closing = new Promise((resolve, reject) => {
        server.close((error) => error ? reject(error) : resolve());
        server.closeAllConnections();
      });
      return closing;
    },
  };
}
