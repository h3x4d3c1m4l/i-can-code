// web/vm/vm_bundle.js: the state decompressed with v86.wasm's own decoder, and
// loadBundle() and openVm() through the Cache API on a network that lies: the
// checks that keep a bad download out of the cache, a file that fails stopping
// the other, and libv86.mjs imported from its kept copy when the network is gone.

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { afterEach, test } from 'node:test';
import zlib from 'node:zlib';

import { inflateState, loadBundle, mismatch } from '../../../web/vm/vm_bundle.js';
import { pieceKey } from '../../../web/vm/vm_cache.js';
import { openVm } from '../../../web/vm/vm_host.js';
import { FakeAgent } from './fake_agent.mjs';
import { FakeClock, fakeSnapshot, fakeV86 } from './fake_v86.mjs';
import { failingImports, FakeServer, MemoryCache, noHooks, ORIGIN } from './fake_web.mjs';

const wasmPath = new URL('../node_modules/v86/build/v86.wasm', import.meta.url);
const noDecoder = !existsSync(wasmPath) ? 'needs v86.wasm: npm ci --prefix vm/tools'
  : typeof zlib.zstdCompressSync !== 'function' ? 'needs a Node with zlib.zstdCompressSync'
    : false;
const wasm = noDecoder ? null : readFileSync(wasmPath);

/** 3 MiB that compress well but not to nothing, as a machine's memory does. */
function payload() {
  const bytes = new Uint8Array(3 * 1024 * 1024);
  let x = 1;
  for (let i = 0; i < bytes.length; i++) {
    x = (Math.imul(x, 1103515245) + 12345) | 0;
    bytes[i] = (i & 4095) < 1024 ? x >>> 24 : 0;
  }
  return bytes;
}

function zstd(bytes, { checksum = false } = {}) {
  const compressed = zlib.zstdCompressSync(bytes, { params: { [zlib.constants.ZSTD_c_checksumFlag]: checksum ? 1 : 0 } });
  return compressed.buffer.slice(compressed.byteOffset, compressed.byteOffset + compressed.byteLength);
}

test('a zstd state comes back raw, through v86.wasm\'s decoder', { skip: noDecoder }, async () => {
  const raw = payload();
  const inflated = await inflateState(zstd(raw), wasm, raw.byteLength);
  assert.equal(inflated.where, 'inline', 'Node has no Worker, so it decompresses in place');
  assert.ok(inflated.state instanceof ArrayBuffer);
  assert.deepEqual(new Uint8Array(inflated.state), raw);
});

test('a raw state, or one with no size to decompress to, is left as it is', async () => {
  const raw = new ArrayBuffer(16);
  assert.deepEqual(await inflateState(raw, new Uint8Array(1), 16), { state: raw, where: null, ms: 0 });
  const compressed = new Uint8Array([0x28, 0xB5, 0x2F, 0xFD, 0, 0, 0, 0]).buffer;
  assert.equal((await inflateState(compressed, new Uint8Array(1), undefined)).state, compressed);
});

test('a state that fails its checksum rejects rather than coming back as garbage', { skip: noDecoder }, async () => {
  const broken = new Uint8Array(zstd(payload(), { checksum: true }));
  broken[64] ^= 0xFF;
  await assert.rejects(inflateState(broken.buffer, wasm, 3 * 1024 * 1024));
});

test('a state shorter than the manifest says rejects', { skip: noDecoder }, async () => {
  const raw = payload();
  await assert.rejects(inflateState(zstd(raw), wasm, raw.byteLength + 4096));
});

// What a download has to be

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

test('a file is held to the manifest\'s size and sha256', async () => {
  const bytes = new TextEncoder().encode('the state');
  const check = { bytes: bytes.byteLength, sha256: sha256(bytes) };
  assert.equal(await mismatch(bytes, check), null);
  assert.equal(await mismatch(bytes, { ...check, sha256: check.sha256.toUpperCase() }), null);
  assert.match(await mismatch(bytes.subarray(1), check), /is 8 bytes, not 9/);
  const flipped = bytes.slice();
  flipped[0] ^= 1;
  assert.match(await mismatch(flipped, check), /has sha256 [0-9a-f]{64}, not /);
  assert.equal(await mismatch(flipped, { bytes: bytes.byteLength }), null, 'a manifest without a sha256 gets the size checked');
});

// The Cache API, with a network that lies. Every test has an origin of its own,
// since downloads are shared per image across the module.

const SAVED_TSC = 66_000_000_000n;
const goodWasm = new Uint8Array([0, 0x61, 0x73, 0x6D]);
const goodState = new Uint8Array(fakeSnapshot(SAVED_TSC));
const PORTAL = new TextEncoder().encode('<html>Log in to the school Wi-Fi</html>');
const manifest = {
  imageId: 'img1',
  agentProto: 1,
  memoryMiB: 96,
  vgaMiB: 4,
  uart1: true,
  v86: { lib: 'libv86.mjs', wasm: 'v86.wasm', wasmBytes: goodWasm.byteLength, wasmSha256: sha256(goodWasm) },
  state: { file: 'state.bin.zst', bytes: goodState.byteLength, sha256: sha256(goodState) },
  rootfs: { dir: 'rootfs/' },
};

/** Test knobs for vm_download.js: no waiting between retries, no lingering. */
const DOWNLOAD = { retryDelaysMs: [0], lingerMs: 0 };

let sites = 0;
function site() {
  const base = `${ORIGIN}bundle-${++sites}/vm/image/`;
  return {
    base,
    manifest: `${base}manifest.json`,
    wasm: `${base}img1/v86.wasm`,
    state: `${base}img1/state.bin.zst`,
    lib: `${base}img1/libv86.mjs`,
    bundle: `${base}img1/`,
  };
}

let cache;
const saved = { caches: globalThis.caches, fetch: globalThis.fetch };

/** A site whose server answers `files` (defaults: the good bundle), and a fresh cache. */
function useServer(urls, files = {}, options = {}) {
  const server = new FakeServer({
    [urls.manifest]: JSON.stringify(manifest),
    [urls.wasm]: goodWasm,
    [urls.state]: goodState,
    [urls.lib]: 'export class V86 {}',
    ...files,
  }, options);
  cache = new MemoryCache();
  globalThis.caches = { open: async () => cache };
  globalThis.fetch = server.fetch;
  return server;
}

afterEach(() => {
  globalThis.caches = saved.caches;
  globalThis.fetch = saved.fetch;
  delete globalThis.__iccTestV86;
});

async function load(urls, onProgress = () => {}) {
  try {
    const bundle = await loadBundle({ baseUrl: urls.base, download: DOWNLOAD }, onProgress);
    bundle.release();
    return bundle;
  } catch (error) {
    return error;
  }
}

test('a portal page served for the state is never cached, so the next load gets the real one', { skip: noHooks }, async () => {
  // The review's cache-poison.mjs: the first load behind a portal, the second on a working network.
  const urls = site();
  const behindPortal = useServer(urls, { [urls.state]: PORTAL }, { ranges: false });
  const failed = await load(urls);
  assert.ok(failed instanceof Error);
  assert.equal(failed.reason, 'network');
  assert.match(failed.message, new RegExp(`state\\.bin\\.zst did not arrive intact: it is ${PORTAL.byteLength} bytes, not 8`));
  assert.deepEqual(cache.under(urls.state), []);
  assert.equal(behindPortal.of(urls.state).length, 2, 'fetched once more before giving up');

  const files = cache.files;
  const fixed = useServer(urls);
  cache.files = files;
  const bundle = await load(urls);
  assert.deepEqual(new Uint8Array(bundle.state), goodState);
  assert.deepEqual(cache.files.get(pieceKey(urls.state, 0, 7)), goodState);
  assert.equal(fixed.of(urls.state).length, 1);
});

test('a state of the right size with the wrong content is refused as well', { skip: noHooks }, async () => {
  const urls = site();
  const wrong = goodState.slice();
  wrong[7] ^= 0xFF;
  useServer(urls, { [urls.state]: wrong });
  const failed = await load(urls);
  assert.equal(failed.reason, 'network');
  assert.match(failed.message, /has sha256/);
  assert.deepEqual(cache.under(urls.state), [], 'the pieces of a file that failed its check are all deleted');
});

test('a bad copy already in the cache is deleted and fetched again, the good cached wasm read without a request', { skip: noHooks }, async () => {
  const urls = site();
  const server = useServer(urls);
  cache.files.set(urls.state, PORTAL.slice());
  cache.files.set(urls.wasm, goodWasm.slice());
  const bundle = await load(urls);
  assert.deepEqual(new Uint8Array(bundle.state), goodState);
  assert.equal(server.of(urls.state).length, 1);
  assert.equal(server.of(urls.wasm).length, 0);
  assert.deepEqual(cache.under(urls.state), [pieceKey(urls.state, 0, 7)]);
});

test('a bad cached copy on a network that is still bad fails the load and leaves nothing behind', { skip: noHooks }, async () => {
  const urls = site();
  const server = useServer(urls, { [urls.state]: PORTAL }, { ranges: false });
  cache.files.set(urls.state, PORTAL.slice());
  const failed = await load(urls);
  assert.equal(failed.reason, 'network');
  assert.equal(server.of(urls.state).length, 2, 'one refetch, not a loop');
  assert.deepEqual(cache.under(urls.state), []);
});

test('a ranged download cut short goes on from where it stopped, in the same load', { skip: noHooks }, async () => {
  const urls = site();
  let cut = true;
  const server = useServer(urls, {}, {
    answer: (request, self) => {
      if (request.url !== urls.state || !cut) return undefined;
      cut = false;
      return self.respond(goodState, { status: 206, headers: { 'Content-Range': 'bytes 0-7/8' }, cutAfter: 5 });
    },
  });
  server.chunk = 1;
  const progress = [];
  const bundle = await load(urls, p => progress.push([p.loaded, p.total]));
  assert.deepEqual(new Uint8Array(bundle.state), goodState);
  assert.deepEqual(server.of(urls.state).map(r => r.range), ['bytes=0-7', 'bytes=5-7']);
  assert.deepEqual(progress.at(-1), [12, 12]);
});

test('a whole-file download cut short starts over, and the bytes of the refused copy are not counted', { skip: noHooks }, async () => {
  const urls = site();
  let cut = true;
  const server = useServer(urls, {}, {
    ranges: false,
    answer: (request, self) => {
      if (request.url !== urls.state || !cut) return undefined;
      cut = false;
      return self.respond(goodState, { cutAfter: 5 });
    },
  });
  server.chunk = 1;
  const progress = [];
  const bundle = await load(urls, p => progress.push([p.loaded, p.total]));
  assert.deepEqual(new Uint8Array(bundle.state), goodState);
  assert.equal(server.of(urls.state).length, 2);
  assert.deepEqual(progress.at(-1), [12, 12]);
  assert.ok(progress.every(([loaded]) => loaded <= 12));
});

test('a portal page served for the manifest falls back to the last good one and is never cached', { skip: noHooks }, async () => {
  const urls = site();
  useServer(urls);
  await load(urls);
  const files = cache.files;
  useServer(urls, { [urls.manifest]: PORTAL });
  cache.files = files;
  const bundle = await load(urls);
  assert.equal(bundle.manifest.imageId, 'img1');
  assert.deepEqual(JSON.parse(new TextDecoder().decode(cache.files.get(urls.manifest))).imageId, 'img1');
});

test('evictState deletes every piece of the state and leaves the wasm', { skip: noHooks }, async () => {
  const urls = site();
  useServer(urls);
  const bundle = await load(urls);
  assert.notDeepEqual(cache.under(urls.state), []);
  await bundle.evictState();
  assert.deepEqual(cache.under(urls.state), []);
  assert.equal(cache.files.has(urls.wasm), true);
});

test('libv86.mjs is kept beside the rest, and imported from that copy when the network is gone', { skip: noHooks }, async () => {
  const urls = site();
  useServer(urls);
  await load(urls);
  assert.equal(new TextDecoder().decode(cache.files.get(urls.lib)), 'export class V86 {}');

  const offline = site();
  const server = useServer(offline);
  cache.files.set(offline.lib, new TextEncoder().encode('export class V86 { static kept = true; }'));
  failingImports.add(offline.lib);
  try {
    const bundle = await load(offline);
    assert.equal(bundle.V86.kept, true, 'the kept copy stood in for the import that failed');
  } finally {
    failingImports.delete(offline.lib);
  }
  assert.equal(server.of(offline.lib).length, 0, 'a kept copy is not fetched again');
});

test('a libv86.mjs answered with a page of HTML is not kept', { skip: noHooks }, async () => {
  const urls = site();
  useServer(urls, {}, {
    answer: request => (request.url === urls.lib ? new Response(PORTAL, { headers: { 'Content-Type': 'text/html' } }) : undefined),
  });
  await load(urls);
  assert.equal(cache.files.has(urls.lib), false);
});

test('a state that will not restore is evicted, and the next load downloads it again', { skip: noHooks }, async () => {
  const urls = site();
  const clock = new FakeClock();
  let restores = 0;
  let failRestore = true;
  const FakeV86 = fakeV86(clock, emulator => new FakeAgent(emulator));
  globalThis.__iccTestV86 = class extends FakeV86 {

    restore_state(state) {
      restores++;
      if (failRestore) throw new Error('out of bounds');
      return super.restore_state(state);
    }

  };
  const server = useServer(urls);
  const vm = openVm({ baseUrl: urls.base, trackVisibility: false, download: DOWNLOAD });
  try {
    const failed = await vm.load();
    assert.equal(failed.reason, 'broken', failed.message);
    assert.deepEqual(cache.under(urls.state), [], 'the state that would not restore is gone from the cache');
    assert.equal(cache.files.has(urls.wasm), true);

    failRestore = false;
    assert.equal((await vm.load()).type, 'ready');
    assert.equal(server.of(urls.state).length, 2, 'downloaded again rather than restored from memory');
    assert.equal(restores, 2);
  } finally {
    await vm.destroy();
  }
});

test('a load reports its phases in order: the download, then unpacking, then starting', { skip: noHooks }, async () => {
  const urls = site();
  globalThis.__iccTestV86 = fakeV86(new FakeClock(), emulator => new FakeAgent(emulator));
  useServer(urls);
  const events = [];
  const vm = openVm({ baseUrl: urls.base, trackVisibility: false, download: DOWNLOAD, onEvent: event => events.push(event) });
  try {
    assert.equal((await vm.load()).type, 'ready');
    const phases = events.filter(e => e.type === 'progress').map(e => e.phase);
    assert.deepEqual([...new Set(phases)], ['download', 'unpack', 'start']);
    const last = events.filter(e => e.type === 'progress').at(-1);
    assert.equal(last.loaded, last.total);
    assert.equal(typeof last.keeps, 'boolean');
  } finally {
    await vm.destroy();
  }
});

// A load that fails part way

/**
 * The manifest at once, the state as `state` says, and the wasm a byte every
 * 5 ms, the way a slow network sends a large file. Like fetch(), it errors the
 * body once its request is aborted.
 */
function slowWasm(urls, { state = goodState } = {}) {
  const server = useServer(urls, state ? {} : { [urls.state]: undefined });
  server.chunk = 1;
  const wasm = { signal: null, bytesSent: 0 };
  server.answer = request => {
    if (request.url !== urls.wasm) return undefined;
    wasm.signal = request.signal ?? null;
    return new Response(new ReadableStream({
      start(controller) {
        wasm.signal?.addEventListener('abort', () => controller.error(wasm.signal.reason));
      },
      async pull(controller) {
        await new Promise(resolve => setTimeout(resolve, 5));
        if (wasm.signal?.aborted) return;
        controller.enqueue(goodWasm.slice(wasm.bytesSent, wasm.bytesSent + 1));
        if (++wasm.bytesSent === goodWasm.byteLength) controller.close();
      },
    }));
  };
  return wasm;
}

test('a file that fails stops the other\'s download, and no progress follows the failure', { skip: noHooks }, async () => {
  // The review's fast404 probe: a state that 404s at once left the page on
  // "2,1 van 22,7 MB" for good, since the wasm went on reporting bytes.
  const urls = site();
  const wasm = slowWasm(urls, { state: null });
  const events = [];
  const vm = openVm({ baseUrl: urls.base, trackVisibility: false, download: DOWNLOAD, onEvent: event => events.push(event) });
  try {
    const failed = await vm.load();
    assert.equal(failed.reason, 'network');
    assert.match(failed.message, /HTTP 404/);
    assert.equal(wasm.signal?.aborted, true, 'the wasm download is aborted with the load');

    await new Promise(resolve => setTimeout(resolve, 40));
    const types = events.map(event => event.type);
    assert.deepEqual(types.slice(types.indexOf('failed')), ['failed'], 'nothing after the failure, progress least of all');
    assert.ok(wasm.bytesSent < goodWasm.byteLength, 'the rest of the wasm is never fetched');
  } finally {
    await vm.destroy();
  }
});

test('a file that fails stops the other\'s download in loadBundle too', { skip: noHooks }, async () => {
  const urls = site();
  const wasm = slowWasm(urls, { state: null });
  const progress = [];
  const failed = await load(urls, p => progress.push(p));
  assert.equal(failed.reason, 'network');
  const reported = progress.length;
  await new Promise(resolve => setTimeout(resolve, 40));
  assert.equal(progress.length, reported);
  assert.equal(wasm.signal?.aborted, true);
});

test('a Vm replaced while it downloads reports no more progress to its page', { skip: noHooks }, async () => {
  const urls = site();
  globalThis.__iccTestV86 = fakeV86(new FakeClock(), emulator => new FakeAgent(emulator));
  const wasm = slowWasm(urls);
  const events = [];
  const first = openVm({ baseUrl: urls.base, trackVisibility: false, download: DOWNLOAD, onEvent: event => events.push(event) });
  const loading = first.load();
  await new Promise(resolve => setTimeout(resolve, 8));
  const second = openVm({ baseUrl: `${urls.base}elsewhere/`, trackVisibility: false, download: DOWNLOAD });
  try {
    assert.equal((await loading).reason, 'replaced');
    await new Promise(resolve => setTimeout(resolve, 40));
    const types = events.map(event => event.type);
    assert.deepEqual(types.slice(types.indexOf('failed')), ['failed']);
    assert.equal(wasm.signal?.aborted, true, 'nobody waits for the download, so it stops');
  } finally {
    await second.destroy();
  }
});
