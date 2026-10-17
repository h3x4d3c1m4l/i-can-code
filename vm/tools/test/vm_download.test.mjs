// web/vm/vm_download.js and prefetchBundle(): the state in Range pieces, a
// server that does not do ranges, a download interrupted and resumed in the same
// load and in the next, what the Cache API already holds, a browser without
// room, one download shared by every caller, and the byte rate.

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { afterEach, test } from 'node:test';

import { prefetchBundle } from '../../../web/vm/vm_bundle.js';
import { pieceKey } from '../../../web/vm/vm_cache.js';
import { contentRange, RateMeter } from '../../../web/vm/vm_download.js';
import { openVm } from '../../../web/vm/vm_host.js';
import { FakeAgent } from './fake_agent.mjs';
import { FakeClock, fakeSnapshot, fakeV86 } from './fake_v86.mjs';
import { FakeServer, MemoryCache, noHooks, noise, ORIGIN } from './fake_web.mjs';

const KiB = 1024;
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

/** A state of 1 MiB in pieces of 128 KiB: eight of them. */
const PIECE = 128 * KiB;
const STATE = noise(8 * PIECE, 7);
const WASM = noise(40 * KiB, 3);
const DOWNLOAD = { pieceBytes: PIECE, parallel: 3, retryDelaysMs: [0, 0], lingerMs: 0, stallMs: 200 };

let sites = 0;
function site(state = STATE, wasm = WASM) {
  const base = `${ORIGIN}download-${++sites}/vm/image/`;
  const manifest = {
    imageId: 'img',
    agentProto: 1,
    memoryMiB: 96,
    vgaMiB: 4,
    uart1: true,
    v86: { lib: 'libv86.mjs', wasm: 'v86.wasm', wasmBytes: wasm.byteLength, wasmSha256: sha256(wasm) },
    state: { file: 'state.bin.zst', bytes: state.byteLength, sha256: sha256(state) },
    rootfs: { dir: 'rootfs/' },
  };
  return {
    base,
    manifest,
    urls: {
      manifest: `${base}manifest.json`,
      wasm: `${base}img/v86.wasm`,
      state: `${base}img/state.bin.zst`,
      lib: `${base}img/libv86.mjs`,
    },
    files: {
      [`${base}manifest.json`]: JSON.stringify(manifest),
      [`${base}img/v86.wasm`]: wasm,
      [`${base}img/state.bin.zst`]: state,
      [`${base}img/libv86.mjs`]: 'export class V86 {}',
    },
  };
}

let cache;
const saved = { caches: globalThis.caches, fetch: globalThis.fetch };
const navigatorKeys = ['storage', 'userAgentData', 'connection'];

function serve(where, options = {}) {
  const server = new FakeServer(where.files, options);
  cache ??= new MemoryCache();
  globalThis.caches = { open: async () => cache };
  globalThis.fetch = server.fetch;
  return server;
}

/** Stands in for navigator's `storage`, `userAgentData` and `connection`. */
function fakeNavigator(fields) {
  for (const [key, value] of Object.entries(fields)) {
    Object.defineProperty(globalThis.navigator, key, { value, configurable: true });
  }
}

afterEach(() => {
  globalThis.caches = saved.caches;
  globalThis.fetch = saved.fetch;
  cache = undefined;
  for (const key of navigatorKeys) {
    if (Object.getOwnPropertyDescriptor(globalThis.navigator, key)) delete globalThis.navigator[key];
  }
  delete globalThis.__iccTestV86;
});

const prefetch = (where, extra = {}) => prefetchBundle({ baseUrl: where.base, download: DOWNLOAD, ...extra });
const ranges = (server, url) => server.of(url).map(request => request.range);
const pieceBytes = (url, keys) => keys.reduce((sum, key) => {
  const [start, end] = key.slice(url.length + '?bytes='.length).split('-').map(Number);
  return sum + end - start + 1;
}, 0);

test('the state comes in Range pieces, each kept as it lands, and the whole checked', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where);
  const result = await prefetch(where);
  assert.deepEqual(result, { imageId: 'img', total: STATE.byteLength + WASM.byteLength, cached: 0, fetched: STATE.byteLength + WASM.byteLength, keeps: true });
  const asked = ranges(server, where.urls.state);
  assert.equal(asked.length, 8);
  assert.equal(asked[0], `bytes=0-${PIECE - 1}`, 'the first piece goes first, and alone');
  assert.deepEqual([...asked].sort(), Array.from({ length: 8 }, (_, i) => `bytes=${i * PIECE}-${(i + 1) * PIECE - 1}`).sort());
  assert.ok(server.of(where.urls.state).every(request => request.cache === 'no-store'), 'the HTTP cache keeps no second copy');
  assert.equal(pieceBytes(where.urls.state, cache.under(where.urls.state)), STATE.byteLength);
  assert.ok(cache.files.has(where.urls.wasm));
  assert.ok(cache.files.has(where.urls.lib));
});

test('a second download reads everything from the Cache API and asks the network for nothing but the manifest', { skip: noHooks }, async () => {
  const where = site();
  serve(where);
  await prefetch(where);
  const server = serve(where);
  const seen = [];
  const result = await prefetch(where, { onProgress: progress => seen.push(progress) });
  assert.equal(result.cached, result.total);
  assert.equal(result.fetched, 0);
  assert.deepEqual(server.requests.map(request => request.url), [where.urls.manifest]);
  assert.equal(seen.at(-1).loaded, result.total);
  assert.equal(seen.at(-1).cached, result.total);
});

test('a server that answers a Range with a 200 is read in one request, and its copy kept as one piece', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where, { ranges: false });
  const result = await prefetch(where);
  assert.equal(result.fetched, STATE.byteLength + WASM.byteLength);
  assert.equal(server.of(where.urls.state).length, 1, 'no second request once the first said no');
  assert.deepEqual(cache.under(where.urls.state), [pieceKey(where.urls.state, 0, STATE.byteLength - 1)]);
});

test('a 206 of a compressed representation is not taken for the file: it is fetched again without a Range', { skip: noHooks }, async () => {
  // GitHub Pages answers a Range on a file it gzips with a range of the gzip,
  // whose Content-Range total is the compressed size.
  const where = site();
  const server = serve(where, {
    answer: (request, self) => (request.url === where.urls.state && request.range
      ? self.respond(noise(1000), { status: 206, headers: { 'Content-Range': 'bytes 0-999/5000', 'Content-Encoding': 'gzip' } })
      : undefined),
  });
  await prefetch(where);
  assert.deepEqual(ranges(server, where.urls.state), [`bytes=0-${PIECE - 1}`, null]);
});

test('a 206 whose Content-Range total is * is a range of the file all the same', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where, {
    answer: (request, self) => {
      const found = /^bytes=(\d+)-(\d+)$/.exec(request.range ?? '');
      if (request.url !== where.urls.state || !found) return undefined;
      const [start, end] = [Number(found[1]), Number(found[2])];
      return self.respond(STATE.subarray(start, end + 1), {
        status: 206,
        headers: { 'Content-Range': `bytes ${start}-${end}/*` },
      });
    },
  });
  const result = await prefetch(where);
  assert.equal(result.fetched, STATE.byteLength + WASM.byteLength);
  assert.equal(server.of(where.urls.state).length, 8, 'ranges all the way, not one whole-file read');
  assert.equal(pieceBytes(where.urls.state, cache.under(where.urls.state)), STATE.byteLength);
});

test('a server that stops answering ranges part way fails that attempt, and one more reads the file from the start', { skip: noHooks }, async () => {
  const where = site();
  let answered = 0;
  const server = serve(where, {
    answer: (request, self) => {
      if (request.url !== where.urls.state || !request.range) return undefined;
      if (++answered === 3) return self.respond(STATE);
      return undefined;
    },
  });
  const result = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1 } });
  assert.equal(result.keeps, true);
  const asked = ranges(server, where.urls.state);
  assert.equal(asked[2], `bytes=${2 * PIECE}-${3 * PIECE - 1}`, 'the third piece came back as a 200');
  assert.equal(asked[3], `bytes=0-${PIECE - 1}`, 'the file was read again from the start');
  assert.equal(pieceBytes(where.urls.state, cache.under(where.urls.state)), STATE.byteLength);
});

test('a download cut off part way keeps its pieces, and the next one fetches only the rest', { skip: noHooks }, async () => {
  const where = site();
  let pieces = 0;
  const first = serve(where, {
    answer: request => {
      if (request.url === where.urls.state && ++pieces > 3) throw new TypeError('Failed to fetch');
      return undefined;
    },
  });
  const failed = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1, retryDelaysMs: [] } }).catch(error => error);
  assert.equal(failed.reason, 'network');
  assert.equal(ranges(first, where.urls.state).length, 4);
  const kept = pieceBytes(where.urls.state, cache.under(where.urls.state));
  assert.equal(kept, 3 * PIECE, 'the three pieces that arrived stay');
  // The failure stops the wasm too, which may or may not have landed by then.
  const wasmKept = cache.files.has(where.urls.wasm) ? WASM.byteLength : 0;

  const second = serve(where);
  const seen = [];
  const result = await prefetch(where, { onProgress: progress => seen.push(progress) });
  assert.equal(result.cached, kept + wasmKept);
  assert.equal(result.fetched, STATE.byteLength - kept + WASM.byteLength - wasmKept);
  assert.equal(ranges(second, where.urls.state).length, 5);
  assert.ok(!ranges(second, where.urls.state).includes(`bytes=0-${PIECE - 1}`));
  assert.equal(seen[0].loaded, 0);
  assert.ok(seen.some(progress => progress.cached === kept + wasmKept), 'what was kept shows as loaded before any request');
});

test('a piece whose connection drops keeps what arrived, and its retry asks for the rest', { skip: noHooks }, async () => {
  const where = site();
  let dropped = false;
  const server = serve(where, {
    chunk: 16 * KiB,
    answer: (request, self) => {
      if (request.url !== where.urls.state || request.range !== `bytes=0-${PIECE - 1}` || dropped) return undefined;
      dropped = true;
      return self.respond(STATE.subarray(0, PIECE), { status: 206, headers: { 'Content-Range': `bytes 0-${PIECE - 1}/${STATE.byteLength}` }, cutAfter: 80 * KiB });
    },
  });
  const result = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1 } });
  assert.equal(result.fetched, STATE.byteLength + WASM.byteLength);
  assert.deepEqual(ranges(server, where.urls.state).slice(0, 2), [`bytes=0-${PIECE - 1}`, `bytes=${80 * KiB}-${PIECE - 1}`]);
  assert.ok(cache.files.has(pieceKey(where.urls.state, 0, 80 * KiB - 1)), 'the 80 KiB that arrived are kept as a piece of their own');
});

test('a request that stalls is ended and tried again from where it stopped', { skip: noHooks }, async () => {
  const where = site();
  let stalled = false;
  const server = serve(where, {
    chunk: 16 * KiB,
    answer: (request, self) => {
      if (request.url !== where.urls.state || stalled) return undefined;
      stalled = true;
      return self.respond(STATE.subarray(0, PIECE), {
        status: 206,
        headers: { 'Content-Range': `bytes 0-${PIECE - 1}/${STATE.byteLength}` },
        signal: request.signal,
        stallAfter: 32 * KiB,
      });
    },
  });
  const seen = [];
  const started = Date.now();
  await prefetch(where, { download: { ...DOWNLOAD, stallMs: 150 }, onProgress: progress => seen.push(progress) });
  assert.ok(Date.now() - started < 3000);
  assert.ok(ranges(server, where.urls.state).includes(`bytes=${32 * KiB}-${PIECE - 1}`), 'the rest of the stalled piece');
});

test('a server that truncates every Range answer is given up on, not resumed for ever', { skip: noHooks }, async () => {
  const where = site();
  // Every answer is a legitimate 206 of the first 1000 bytes of what was asked
  // for: forward progress on every try, and 1000 requests for a piece.
  const server = serve(where, {
    answer: (request, self) => {
      const found = /^bytes=(\d+)-(\d+)$/.exec(request.range ?? '');
      if (request.url !== where.urls.state || !found) return undefined;
      const start = Number(found[1]);
      const end = start + 999;
      return self.respond(STATE.subarray(start, end + 1), {
        status: 206,
        headers: { 'Content-Range': `bytes ${start}-${end}/${STATE.byteLength}` },
      });
    },
  });
  const failed = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1 } }).catch(error => error);
  assert.equal(failed.reason, 'network');
  assert.match(failed.message, /answered 1000 bytes of the/);
  // One attempt and one per retry delay, for the first piece and no further.
  assert.equal(server.of(where.urls.state).length, DOWNLOAD.retryDelaysMs.length + 1);
  assert.equal(ranges(server, where.urls.state).at(-1), `bytes=2000-${PIECE - 1}`, 'each try asked for the rest');
});

test('a truncating server that still delivers a piece\'s worth per answer gets through', { skip: noHooks }, async () => {
  const where = site();
  // Half a piece at a time clears MIN_PROGRESS_BYTES, so this is a slow server
  // and not a broken one: it finishes, in two answers per piece.
  const server = serve(where, {
    answer: (request, self) => {
      const found = /^bytes=(\d+)-(\d+)$/.exec(request.range ?? '');
      if (request.url !== where.urls.state || !found) return undefined;
      const start = Number(found[1]);
      const end = Math.min(start + PIECE / 2 - 1, Number(found[2]));
      return self.respond(STATE.subarray(start, end + 1), {
        status: 206,
        headers: { 'Content-Range': `bytes ${start}-${end}/${STATE.byteLength}` },
      });
    },
  });
  const result = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1 } });
  assert.equal(result.fetched, STATE.byteLength + WASM.byteLength);
  assert.equal(server.of(where.urls.state).length, 16, 'two answers for each of the eight pieces');
});

test('a download that cannot finish in time fails on the deadline, with a reason the page retries', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where, {
    // A piece that arrives byte by byte, slowly enough that the deadline is
    // what ends it rather than the stall timer.
    pace: url => (url === where.urls.state ? { chunk: 1, delayMs: 5 } : null),
  });
  const started = Date.now();
  const failed = await prefetch(where, { download: { ...DOWNLOAD, parallel: 1, deadlineMs: 150 } }).catch(error => error);
  assert.equal(failed.reason, 'network');
  assert.match(failed.message, /did not download within/);
  assert.ok(Date.now() - started < 5000, 'it ends on the deadline, not when the file would have arrived');
  assert.ok(server.of(where.urls.state).length >= 1);
});

test('a 404 is not tried again: the deploy took the file away', { skip: noHooks }, async () => {
  const where = site();
  delete where.files[where.urls.state];
  const server = serve(where);
  const failed = await prefetch(where, { download: { ...DOWNLOAD, retryDelaysMs: [0, 0, 0] } }).catch(error => error);
  assert.equal(failed.reason, 'network');
  assert.match(failed.message, /HTTP 404/);
  assert.equal(server.of(where.urls.state).length, 1);
});

test('a network error is tried again, and a download that then gets through completes', { skip: noHooks }, async () => {
  const where = site();
  let failures = 2;
  const server = serve(where, {
    answer: request => {
      if (request.url === where.urls.state && failures-- > 0) throw new TypeError('Failed to fetch');
      return undefined;
    },
  });
  const waits = [];
  const result = await prefetch(where, { onProgress: progress => waits.push(progress.stalled) });
  assert.equal(result.fetched, STATE.byteLength + WASM.byteLength);
  assert.equal(ranges(server, where.urls.state)[0], ranges(server, where.urls.state)[2], 'the same piece, asked for three times');
  assert.ok(waits.includes(true), 'a retry waiting shows as stalled');
});

test('a browser with no room downloads all the same, keeps nothing, and says so', { skip: noHooks }, async () => {
  const where = site();
  fakeNavigator({ storage: { estimate: async () => ({ quota: 10_000_000, usage: 9_900_000 }) } });
  serve(where);
  const seen = [];
  const result = await prefetch(where, { onProgress: progress => seen.push(progress) });
  assert.equal(result.keeps, false);
  assert.equal(result.fetched, result.total);
  assert.deepEqual(cache.under(where.base), [where.urls.manifest], 'only the manifest, cached before the estimate');
  assert.equal(seen.at(-1).keeps, false);
});

test('a load the Cache API can serve does not ask for an estimate', { skip: noHooks }, async () => {
  const where = site();
  serve(where);
  await prefetch(where);
  let asked = 0;
  fakeNavigator({ storage: { estimate: async () => { asked++; return { quota: 0, usage: 0 }; } } });
  serve(where);
  const result = await prefetch(where);
  assert.equal(asked, 0);
  assert.equal(result.keeps, true);
});

test('persistence is asked for only where it does not prompt: Chromium, found by navigator.userAgentData', { skip: noHooks }, async () => {
  const room = { estimate: async () => ({ quota: 1e9, usage: 0 }), persisted: async () => false, persist: async () => { persists++; return true; } };
  let persists = 0;
  fakeNavigator({ storage: room });
  const firefox = site();
  serve(firefox);
  await prefetch(firefox);
  assert.equal(persists, 0, 'Firefox would show the student a prompt');

  fakeNavigator({ userAgentData: { brands: [] } });
  const chromium = site();
  serve(chromium);
  await prefetch(chromium);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(persists, 1);
});

test('navigator.connection that calls the line slow is passed on as a hint', { skip: noHooks }, async () => {
  const where = site();
  fakeNavigator({ connection: { effectiveType: '3g', saveData: false } });
  serve(where);
  const seen = [];
  await prefetch(where, { onProgress: progress => seen.push(progress) });
  assert.ok(seen.every(progress => progress.slowConnection === true));
});

// One download, every caller

test('two callers share one download and hear the same progress', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where, { delayMs: 2 });
  const a = [];
  const b = [];
  const [first, second] = await Promise.all([
    prefetch(where, { onProgress: progress => a.push(progress.loaded) }),
    prefetch(where, { onProgress: progress => b.push(progress.loaded) }),
  ]);
  assert.deepEqual(first, second);
  assert.equal(server.of(where.urls.state).length, 8, 'every piece once');
  assert.equal(server.of(where.urls.wasm).length, 1);
  assert.equal(a.at(-1), first.total);
  assert.equal(b.at(-1), first.total);
});

test('a caller that joins part way hears how far the download is at once', { skip: noHooks }, async () => {
  const where = site();
  serve(where, { delayMs: 5, chunk: 8 * KiB });
  const first = prefetch(where);
  await new Promise(resolve => setTimeout(resolve, 60));
  const seen = [];
  const second = prefetch(where, { onProgress: progress => seen.push(progress.loaded) });
  await Promise.all([first, second]);
  assert.ok(seen[0] > 0, `the first report of a late caller is where the download is, not 0 (${seen[0]})`);
});

test('a caller that leaves does not stop the download another still waits for', { skip: noHooks }, async () => {
  const where = site();
  serve(where, { delayMs: 2 });
  const leaving = new AbortController();
  const left = prefetch(where, { signal: leaving.signal }).catch(error => error);
  const staying = prefetch(where);
  await new Promise(resolve => setTimeout(resolve, 10));
  leaving.abort();
  assert.equal((await left).reason, 'aborted');
  const result = await staying;
  assert.equal(result.fetched + result.cached, result.total);
});

test('a download everyone left stops, keeps its pieces, and the next picks them up', { skip: noHooks }, async () => {
  const where = site();
  const first = serve(where, { delayMs: 4, chunk: 16 * KiB });
  const leaving = new AbortController();
  const left = prefetch(where, { signal: leaving.signal, download: { ...DOWNLOAD, parallel: 1 } }).catch(error => error);
  await new Promise(resolve => setTimeout(resolve, 120));
  leaving.abort();
  assert.equal((await left).reason, 'aborted');
  await new Promise(resolve => setTimeout(resolve, 60));
  const asked = first.requests.length;
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.equal(first.requests.length, asked, 'nothing more is asked for once nobody waits');
  const kept = pieceBytes(where.urls.state, cache.under(where.urls.state));
  assert.ok(kept > 0);

  serve(where);
  const result = await prefetch(where);
  assert.equal(result.fetched, STATE.byteLength - kept);
});

test('a caller that has already left starts nothing that outlives it', { skip: noHooks }, async () => {
  const where = site();
  const server = serve(where, { delayMs: 5, chunk: 16 * KiB });
  const gone = new AbortController();
  gone.abort();
  const failed = await prefetch(where, { signal: gone.signal }).catch(error => error);
  assert.equal(failed.reason, 'aborted');
  await new Promise(resolve => setTimeout(resolve, 100));
  const asked = server.requests.length;
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(server.requests.length, asked, 'nothing more is asked for');
  const result = await prefetch(where);
  assert.equal(result.fetched + result.cached, result.total, 'the next caller gets a download of its own');
});

test('a caller that comes while a download nobody wanted is stopping gets a new one, not its failure', { skip: noHooks }, async () => {
  const where = site();
  serve(where, { delayMs: 5, chunk: 16 * KiB });
  const leaving = new AbortController();
  const left = prefetch(where, { signal: leaving.signal }).catch(error => error);
  await new Promise(resolve => setTimeout(resolve, 30));
  leaving.abort();
  await left;
  await new Promise(resolve => setTimeout(resolve, 1));
  const result = await prefetch(where);
  assert.equal(result.fetched + result.cached, result.total);
});

test('prefetch, then open: the Vm starts from the Cache API without downloading again', { skip: noHooks }, async () => {
  const where = site(new Uint8Array(fakeSnapshot(66_000_000_000n)));
  serve(where);
  await prefetch(where);
  globalThis.__iccTestV86 = fakeV86(new FakeClock(), emulator => new FakeAgent(emulator));
  const server = serve(where);
  const events = [];
  const vm = openVm({ baseUrl: where.base, trackVisibility: false, download: DOWNLOAD, onEvent: event => events.push(event) });
  try {
    assert.equal((await vm.load()).type, 'ready');
    assert.deepEqual(server.requests.map(request => request.url), [where.urls.manifest]);
    const downloads = events.filter(event => event.type === 'progress' && event.phase === 'download');
    assert.equal(downloads.at(-1).cached, downloads.at(-1).total);
  } finally {
    await vm.destroy();
  }
});

test('open while a prefetch downloads: the Vm joins it and hears the same download', { skip: noHooks }, async () => {
  const where = site(new Uint8Array(fakeSnapshot(66_000_000_000n)), noise(16));
  const server = serve(where, { pace: url => (url === where.urls.manifest ? null : { delayMs: 20, chunk: 2 }) });
  const prefetched = [];
  const prefetching = prefetch(where, { onProgress: progress => prefetched.push(progress.loaded) });
  await new Promise(resolve => setTimeout(resolve, 30));
  globalThis.__iccTestV86 = fakeV86(new FakeClock(), emulator => new FakeAgent(emulator));
  const events = [];
  const vm = openVm({ baseUrl: where.base, trackVisibility: false, download: DOWNLOAD, onEvent: event => events.push(event) });
  try {
    assert.equal((await vm.load()).type, 'ready');
    await prefetching;
    assert.equal(server.of(where.urls.state).length, 1, 'one download for both');
    assert.equal(server.of(where.urls.wasm).length, 1);
    const heard = events.filter(event => event.type === 'progress' && event.phase === 'download').map(event => event.loaded);
    assert.ok(heard[0] > 0, `the Vm heard where the download was when it joined (${heard[0]})`);
    assert.equal(heard.at(-1), 24);
    assert.equal(prefetched.at(-1), 24);
  } finally {
    await vm.destroy();
  }
});

// The byte rate

test('the rate is null until two seconds and 256 KiB have been seen, then the average', () => {
  let now = 0;
  const meter = new RateMeter({ now: () => now });
  meter.add(64 * KiB);
  for (let t = 100; t <= 1900; t += 100) {
    now = t;
    meter.add(100 * KiB);
    meter.sample();
  }
  assert.equal(meter.bytesPerSecond, null, 'under two seconds');
  now = 2000;
  meter.add(100 * KiB);
  meter.sample();
  assert.equal(Math.round(meter.bytesPerSecond), 1_024_000, '100 KiB every 100 ms');
});

test('a stall pulls the rate down within seconds, and a steady line holds it', () => {
  let now = 0;
  const meter = new RateMeter({ now: () => now });
  meter.add(1);
  for (now = 100; now <= 10_000; now += 100) {
    meter.add(50 * KiB);
    meter.sample();
  }
  const steady = meter.bytesPerSecond;
  assert.ok(Math.abs(steady - 512_000) < 1000, `steady at ${steady}`);
  for (now = 10_100; now <= 13_000; now += 100) meter.sample();
  assert.ok(meter.bytesPerSecond < steady * 0.45, `three seconds of nothing leave ${meter.bytesPerSecond}`);
  assert.equal(meter.lastByteAt, 10_000);
});

test('Content-Range is read as bytes START-END/TOTAL', () => {
  assert.deepEqual(contentRange('bytes 0-99/4303440'), { start: 0, end: 99, total: 4303440 });
  assert.deepEqual(contentRange('bytes 5-7/*'), { start: 5, end: 7, total: null });
  assert.equal(contentRange('bytes */8'), null);
  assert.equal(contentRange(null), null);
  assert.equal(contentRange('bytes 9-3/10'), null);
});
