// A static server for the bench page, with the headers the app's dev server sends: COOP
// same-origin and COEP require-corp, so the page is cross-origin isolated as the app is.
//
// Mounts: /vm/ is web/vm/ (the host modules and web/vm/image/), /bench/ is this directory,
// /corpus/ is vm/tools/corpus/ and /bench-data/ is vm/build/bench/data/, where the runner writes
// what it derives from the bundle, such as a raw state. Everything else comes from build/web/, the
// app's last `flutter build web`, which the bench frames to measure the app beside the VM. Caching
// follows GitHub Pages, where the bundle will be served from: max-age=600 with an ETag, gzip for
// the types a CDN compresses, and a 206 for a single Range, which Pages answers too. A Range
// answer is never compressed: Pages compresses one only for a client that asks for gzip, and a
// browser asks for none with a Range.
//
// Usage: node serve.mjs [--port 8086] [--no-gzip] [--no-range]

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

const benchDir = path.dirname(new URL(import.meta.url).pathname);
const repoDir = path.resolve(benchDir, '../../..');

const MOUNTS = [
  ['/vm/', path.join(repoDir, 'web/vm')],
  ['/bench/', benchDir],
  ['/corpus/', path.join(repoDir, 'vm/tools/corpus')],
  ['/bench-data/', path.join(repoDir, 'vm/build/bench/data')],
  ['/', path.join(repoDir, 'build/web')],
];

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.py': 'text/plain; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.md': 'text/markdown; charset=utf-8',
};

const COMPRESSIBLE = new Set(['.html', '.js', '.mjs', '.json', '.wasm', '.py']);

/**
 * Starts the server. `stats` counts what was sent per mount-relative path, so a
 * caller can tell a 200 from a 304 and see bytes on the wire.
 *
 * @param {{port?: number, gzip?: boolean, ranges?: boolean}} [options] Port 0 picks a free one.
 *     `ranges` false answers every Range with the whole file, as `flutter run`'s server does;
 *     `setRanges` changes it while the server runs.
 * @returns {Promise<{url: string, close: () => Promise<void>, stats: Map<string, object>, resetStats: () => void,
 *     setRanges: (on: boolean) => void, cut: (ms: number) => void}>} `cut(ms)` drops every open
 *     connection and every new one for `ms`, as a Wi-Fi that goes away does: a response part way
 *     through ends in an error rather than stalling, which Chrome's own offline mode does not do.
 */
export function startServer({ port = 0, gzip = true, ranges = true } = {}) {
  const gzipped = new Map();
  const stats = new Map();
  const sockets = new Set();
  let downUntil = 0;

  const count = (urlPath, status, bytes) => {
    const entry = stats.get(urlPath) ?? { requests: 0, notModified: 0, partial: 0, bytes: 0 };
    entry.requests++;
    if (status === 304) entry.notModified++;
    if (status === 206) entry.partial++;
    entry.bytes += bytes;
    stats.set(urlPath, entry);
  };

  const server = http.createServer((request, response) => {
    if (Date.now() < downUntil) {
      request.socket.destroy();
      return;
    }
    const urlPath = decodeURIComponent(new URL(request.url, 'http://x').pathname);
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');

    const file = resolve(urlPath);
    let stat;
    try {
      stat = file && fs.statSync(file);
    } catch {
      stat = null;
    }
    if (!stat?.isFile()) {
      response.writeHead(404, { 'Content-Type': 'text/plain' });
      response.end('Not found');
      count(urlPath, 404, 0);
      return;
    }

    const ext = path.extname(file);
    const etag = `"${stat.size.toString(16)}-${Math.floor(stat.mtimeMs).toString(16)}"`;
    response.setHeader('Cache-Control', 'max-age=600');
    response.setHeader('ETag', etag);
    response.setHeader('Last-Modified', stat.mtime.toUTCString());
    response.setHeader('Content-Type', TYPES[ext] ?? 'application/octet-stream');
    if (request.headers['if-none-match'] === etag) {
      response.writeHead(304);
      response.end();
      count(urlPath, 304, 0);
      return;
    }

    if (ranges) response.setHeader('Accept-Ranges', 'bytes');
    const asked = ranges ? request.headers.range : undefined;
    if (asked) {
      const range = byteRange(asked, stat.size);
      if (!range) {
        response.writeHead(416, { 'Content-Range': `bytes */${stat.size}` });
        response.end();
        count(urlPath, 416, 0);
        return;
      }
      const length = range.end - range.start + 1;
      response.writeHead(206, { 'Content-Range': `bytes ${range.start}-${range.end}/${stat.size}`, 'Content-Length': length });
      if (request.method === 'HEAD') {
        response.end();
      } else {
        fs.createReadStream(file, { start: range.start, end: range.end }).pipe(response);
      }
      count(urlPath, 206, length);
      return;
    }

    let body = fs.readFileSync(file);
    if (gzip && COMPRESSIBLE.has(ext) && /\bgzip\b/.test(request.headers['accept-encoding'] ?? '')) {
      const key = `${file}:${etag}`;
      if (!gzipped.has(key)) gzipped.set(key, zlib.gzipSync(body, { level: 6 }));
      body = gzipped.get(key);
      response.setHeader('Content-Encoding', 'gzip');
      response.setHeader('Vary', 'Accept-Encoding');
    }
    response.setHeader('Content-Length', body.byteLength);
    response.writeHead(200);
    response.end(request.method === 'HEAD' ? undefined : body);
    count(urlPath, 200, body.byteLength);
  });

  server.on('connection', socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    if (Date.now() < downUntil) socket.destroy();
  });

  return new Promise((resolveStart, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => {
      const { port: bound } = server.address();
      resolveStart({
        url: `http://127.0.0.1:${bound}/`,
        stats,
        resetStats: () => stats.clear(),
        setRanges: on => { ranges = on; },
        cut: ms => {
          downUntil = Date.now() + ms;
          for (const socket of sockets) socket.destroy();
        },
        close: () => new Promise(done => {
          server.closeAllConnections();
          server.close(() => done());
        }),
      });
    });
  });
}

/** A single `bytes=START-END`, `bytes=START-` or `bytes=-SUFFIX` range within `size`, or null. */
function byteRange(header, size) {
  const found = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!found || (found[1] === '' && found[2] === '')) return null;
  if (found[1] === '') {
    const suffix = Number(found[2]);
    return suffix > 0 ? { start: Math.max(0, size - suffix), end: size - 1 } : null;
  }
  const start = Number(found[1]);
  const end = found[2] === '' ? size - 1 : Math.min(Number(found[2]), size - 1);
  return start <= end && start < size ? { start, end } : null;
}

/** The file for a request path, or null for one outside every mount. */
function resolve(urlPath) {
  for (const [prefix, dir] of MOUNTS) {
    if (!urlPath.startsWith(prefix)) continue;
    const file = path.resolve(dir, `.${urlPath.slice(prefix.length - 1)}`);
    if (file !== dir && !file.startsWith(dir + path.sep)) return null;
    return urlPath.endsWith('/') ? path.join(file, 'index.html') : file;
  }
  return null;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { values } = parseArgs({
    options: {
      port: { type: 'string', default: '8086' },
      'no-gzip': { type: 'boolean', default: false },
      'no-range': { type: 'boolean', default: false },
    },
  });
  const server = await startServer({ port: Number(values.port), gzip: !values['no-gzip'], ranges: !values['no-range'] });
  console.log(`Serving the bench page at ${server.url}bench/`);
}
