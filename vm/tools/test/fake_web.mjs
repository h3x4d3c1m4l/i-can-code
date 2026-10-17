// The browser around web/vm's loaders, as far as they use it: a server that
// answers Range requests the way GitHub Pages does, or ignores them the way
// `flutter run`'s dev server does, and the Cache API in memory. Importing it
// also registers import hooks, so that a bundle's libv86.mjs under ORIGIN, and
// a blob: URL made from a kept copy of it, import as a small module whose V86
// is globalThis.__iccTestV86.

import module from 'node:module';

export const ORIGIN = 'https://example.test/';

const LIB_SOURCE = 'export class V86 { constructor(options) { return new globalThis.__iccTestV86(options); } }';

export const noHooks = typeof module.registerHooks === 'function' ? false : 'needs a Node with module.registerHooks';

/** libv86.mjs URLs whose import fails, as it does offline. */
export const failingImports = new Set();

/** Sources of blob: URLs, which a synchronous load hook cannot read from the Blob. */
const blobSources = new Map();

if (!noHooks) {
  const createObjectURL = URL.createObjectURL;
  URL.createObjectURL = blob => {
    const url = createObjectURL.call(URL, blob);
    if (blob?.iccSource !== undefined) blobSources.set(url, blob.iccSource);
    return url;
  };
  const NativeBlob = globalThis.Blob;
  globalThis.Blob = class extends NativeBlob {

    constructor(parts = [], options) {
      super(parts, options);
      const decoder = new TextDecoder();
      this.iccSource = parts.map(part => (typeof part === 'string' ? part : decoder.decode(part))).join('');
    }

  };
  module.registerHooks({
    resolve(specifier, context, next) {
      if (specifier.startsWith(ORIGIN) || specifier.startsWith('blob:')) return { url: specifier, shortCircuit: true };
      return next(specifier, context);
    },
    load(url, context, next) {
      if (url.startsWith(ORIGIN)) {
        if (failingImports.has(url)) throw new TypeError(`Failed to fetch dynamically imported module: ${url}`);
        return { format: 'module', source: LIB_SOURCE, shortCircuit: true };
      }
      if (url.startsWith('blob:')) return { format: 'module', source: blobSources.get(url) ?? '', shortCircuit: true };
      return next(url, context);
    },
  });
}

/** The Cache API's `icc-vm` cache, as a map of URL to bytes. */
export class MemoryCache {

  files = new Map();
  puts = 0;

  /** A put that throws this, as a browser out of room does. */
  refusePuts = null;

  async match(request) {
    const bytes = this.files.get(urlOf(request));
    return bytes ? new Response(bytes.slice()) : undefined;
  }

  async put(request, response) {
    if (this.refusePuts) throw this.refusePuts;
    const bytes = new Uint8Array(await response.arrayBuffer());
    this.files.set(urlOf(request), bytes);
    this.puts++;
  }

  async keys(request, { ignoreSearch = false } = {}) {
    let urls = [...this.files.keys()];
    if (request !== undefined) {
      const wanted = urlOf(request);
      urls = urls.filter(url => (ignoreSearch ? url.split('?')[0] === wanted.split('?')[0] : url === wanted));
    }
    return urls.map(url => new Request(url));
  }

  async delete(request) {
    return this.files.delete(urlOf(request));
  }

  /** Every key under `prefix`, sorted. */
  under(prefix) {
    return [...this.files.keys()].filter(url => url.startsWith(prefix)).sort();
  }

}

function urlOf(request) {
  return String(request?.url ?? request);
}

/**
 * A server of `files` (URL to bytes or text). Every request is recorded with
 * its Range header and cache mode.
 *
 * - `ranges`: answer a Range request with a 206, as GitHub Pages does; without
 *   it every answer is a 200 of the whole file, as `flutter run`'s is.
 * - `chunk`, `delayMs`: the body arrives in chunks of that size, that far apart.
 *   `pace(url)` may return other ones for one file.
 * - `answer(request)`: returns a Response for a request it wants to answer
 *   itself, or undefined for the usual one.
 */
export class FakeServer {

  requests = [];
  offline = false;

  constructor(files = {}, { ranges = true, chunk = 64 * 1024, delayMs = 0, answer = null, pace = null } = {}) {
    this.files = files;
    this.ranges = ranges;
    this.chunk = chunk;
    this.delayMs = delayMs;
    this.answer = answer;
    this.pace = pace;
  }

  fetch = async (url, init = {}) => {
    url = String(url);
    const request = { url, range: new Headers(init.headers).get('Range'), cache: init.cache ?? 'default', signal: init.signal };
    this.requests.push(request);
    if (init.signal?.aborted) throw init.signal.reason;
    if (this.offline) throw new TypeError('Failed to fetch');
    const answered = this.answer?.(request, this);
    if (answered) return answered;
    const file = this.files[url];
    if (file === undefined) return new Response('Not found', { status: 404, headers: { 'Content-Type': 'text/html' } });
    const bytes = typeof file === 'string' ? new TextEncoder().encode(file) : file;
    const type = url.endsWith('.mjs') ? 'text/javascript' : 'application/octet-stream';
    const found = /^bytes=(\d+)-(\d*)$/.exec(request.range ?? '');
    if (found && this.ranges) {
      const start = Number(found[1]);
      const end = Math.min(found[2] === '' ? bytes.length - 1 : Number(found[2]), bytes.length - 1);
      if (start >= bytes.length) return new Response('', { status: 416, headers: { 'Content-Range': `bytes */${bytes.length}` } });
      return this.respond(bytes.subarray(start, end + 1), {
        status: 206,
        headers: { 'Content-Type': type, 'Content-Range': `bytes ${start}-${end}/${bytes.length}` },
        signal: init.signal,
        ...this.pace?.(url),
      });
    }
    return this.respond(bytes, { status: 200, headers: { 'Content-Type': type }, signal: init.signal, ...this.pace?.(url) });
  };

  /**
   * A Response whose body streams `bytes` in chunks. `cutAfter` errors the
   * body once that many bytes are out, and `stallAfter` stops sending without
   * ending it, as a connection that drops does.
   */
  respond(bytes, { status = 200, headers = {}, signal, cutAfter = null, stallAfter = null, chunk = this.chunk, delayMs = this.delayMs } = {}) {
    let sent = 0;
    const body = new ReadableStream({
      start(controller) {
        signal?.addEventListener('abort', () => controller.error(signal.reason), { once: true });
      },
      async pull(controller) {
        if (delayMs > 0) await new Promise(resolve => setTimeout(resolve, delayMs));
        if (signal?.aborted) return;
        if (cutAfter !== null && sent >= cutAfter) {
          controller.error(new TypeError('network error'));
          return;
        }
        if (stallAfter !== null && sent >= stallAfter) return new Promise(() => {});
        const limit = Math.min(bytes.length, cutAfter ?? Infinity, stallAfter ?? Infinity);
        const next = bytes.slice(sent, Math.min(limit, sent + chunk));
        sent += next.length;
        if (next.length) controller.enqueue(next);
        if (sent >= bytes.length) controller.close();
      },
    });
    return new Response(body, { status, headers });
  }

  /** The requests for `url`. */
  of(url) {
    return this.requests.filter(request => request.url === url);
  }

}

/** `count` bytes that do not compress to nothing, from `seed`. */
export function noise(count, seed = 1) {
  const bytes = new Uint8Array(count);
  let x = seed;
  for (let i = 0; i < count; i++) {
    x = (Math.imul(x, 1103515245) + 12345) | 0;
    bytes[i] = x >>> 24;
  }
  return bytes;
}
