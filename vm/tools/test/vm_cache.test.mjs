// web/vm/vm_cache.js: the Cache API cleanup that leaves an image another tab
// runs alone, the pieces a download keeps, and the rootfs files kept between
// runs: bounded, least recently used first, and gone with their image.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { deletePieces, forgetOtherImages, holdImage, listPieces, pieceKey, RootfsCache } from '../../../web/vm/vm_cache.js';
import { MemoryCache } from './fake_web.mjs';

// Other tabs' images

const BASE = 'https://example.org/app/vm/image/';

class KeysCache {

  constructor(urls) {
    this.urls = new Set(urls);
  }

  async keys() {
    return [...this.urls].map(url => ({ url }));
  }

  async delete(request) {
    return this.urls.delete(request.url);
  }

}

const files = image => [`${BASE}${image}/v86.wasm`, `${BASE}${image}/state.bin.zst?bytes=0-99`, `${BASE}${image}/rootfs/0123456789.bin.zst`];

function cacheOfImages() {
  return new KeysCache([
    `${BASE}manifest.json`,
    ...files('new'),
    ...files('held'),
    ...files('old'),
    'https://example.org/preview/vm/image/other/state.bin.zst',
  ]);
}

const locks = globalThis.navigator?.locks;
const noLocks = typeof locks?.request === 'function' ? false : 'needs a Node with navigator.locks';

test('an image another tab holds keeps its files; one nobody holds loses them, pieces and rootfs files included', { skip: noLocks }, async () => {
  const cache = cacheOfImages();
  const release = await holdImage(`${BASE}held/`, locks);
  try {
    await forgetOtherImages(cache, BASE, `${BASE}new/`, locks);
    assert.deepEqual([...cache.urls].sort(), [
      ...files('held'),
      `${BASE}manifest.json`,
      ...files('new'),
      'https://example.org/preview/vm/image/other/state.bin.zst',
    ].sort());
  } finally {
    release();
  }
  // The lock goes once its callback's promise settles, a turn later.
  await new Promise(resolve => setImmediate(resolve));
  await forgetOtherImages(cache, BASE, `${BASE}new/`, locks);
  assert.equal([...cache.urls].some(url => url.includes('/held/')), false, 'once let go, the next load cleans it up');
});

test('without Web Locks every other image under the base goes, as there is no telling', async () => {
  const cache = cacheOfImages();
  await forgetOtherImages(cache, BASE, `${BASE}new/`, null);
  assert.deepEqual([...cache.urls].sort(), [
    `${BASE}manifest.json`,
    ...files('new'),
    'https://example.org/preview/vm/image/other/state.bin.zst',
  ].sort());
  assert.equal(typeof await holdImage(`${BASE}new/`, null), 'function');
});

test('a lock manager that refuses the page leaves it nothing to release but no failure', async () => {
  const refusing = { request: () => Promise.reject(new DOMException('no storage', 'SecurityError')) };
  const release = await holdImage(`${BASE}new/`, refusing);
  assert.doesNotThrow(release);
});

// Pieces

const STATE = `${BASE}new/state.bin.zst`;

test('the pieces of a file come back sorted and apart; a key that is not one, or overlaps, is deleted', async () => {
  const cache = new MemoryCache();
  for (const key of [
    pieceKey(STATE, 200, 299),
    pieceKey(STATE, 0, 99),
    pieceKey(STATE, 50, 149),
    `${STATE}?bytes=300-`,
    pieceKey(STATE, 300, 1000),
    pieceKey(`${BASE}new/v86.wasm`, 0, 9),
  ]) cache.files.set(key, new Uint8Array(1));
  const pieces = await listPieces(cache, STATE, 400);
  assert.deepEqual(pieces.map(({ start, end }) => [start, end]), [[0, 99], [200, 299]]);
  assert.deepEqual(cache.under(STATE), [pieceKey(STATE, 0, 99), pieceKey(STATE, 200, 299)]);
  assert.ok(cache.files.has(pieceKey(`${BASE}new/v86.wasm`, 0, 9)), 'another file\'s pieces are its own');
});

test('a key without a range is the whole file, and deletePieces takes it with the rest', async () => {
  const cache = new MemoryCache();
  cache.files.set(STATE, new Uint8Array(400));
  cache.files.set(pieceKey(STATE, 0, 9), new Uint8Array(10));
  const pieces = await listPieces(cache, STATE, 400);
  assert.deepEqual(pieces.map(({ start, end }) => [start, end]), [[0, 399]]);
  cache.files.set(pieceKey(STATE, 0, 9), new Uint8Array(10));
  await deletePieces(cache, STATE);
  assert.deepEqual(cache.under(STATE), []);
});

// Rootfs files

const ROOTFS = `${BASE}new/rootfs/`;
const file = name => `${ROOTFS}${name}.bin.zst`;
const bytes = size => new Uint8Array(size).fill(7);

test('a rootfs file put in comes back, and one never put in does not', async () => {
  const cache = new MemoryCache();
  const kept = new RootfsCache(cache, ROOTFS);
  await kept.put(file('a'), bytes(100));
  assert.deepEqual(await kept.get(file('a')), bytes(100));
  assert.equal(await kept.get(file('b')), null);
  assert.equal(kept.bytes, 100);
});

test('past the budget the least recently used go first, and a read counts as a use', async () => {
  const cache = new MemoryCache();
  const kept = new RootfsCache(cache, ROOTFS, { budgetBytes: 300 });
  await kept.put(file('a'), bytes(100));
  await kept.put(file('b'), bytes(100));
  await kept.put(file('c'), bytes(100));
  await kept.get(file('a'));
  await kept.put(file('d'), bytes(100));
  assert.equal(await kept.get(file('b')), null, 'b was the least recently used');
  assert.ok(await kept.get(file('a')));
  assert.ok(await kept.get(file('c')));
  assert.ok(await kept.get(file('d')));
  assert.equal(kept.bytes, 300);
  assert.equal(cache.files.has(file('b')), false);
});

test('the order survives the page: a new tab reads it from the index', async () => {
  const cache = new MemoryCache();
  const first = new RootfsCache(cache, ROOTFS, { budgetBytes: 300 });
  await first.put(file('a'), bytes(100));
  await first.put(file('b'), bytes(100));
  await first.put(file('c'), bytes(100));
  await first.get(file('a'));
  await first.flush();

  const second = new RootfsCache(cache, ROOTFS, { budgetBytes: 300 });
  await second.put(file('d'), bytes(100));
  assert.equal(await second.get(file('b')), null);
  assert.ok(await second.get(file('a')));
});

test('a file the index never heard of, from a tab closed before it wrote it, counts as the oldest', async () => {
  const cache = new MemoryCache();
  const first = new RootfsCache(cache, ROOTFS, { budgetBytes: 300 });
  await first.put(file('a'), bytes(100));
  await first.flush();
  cache.files.set(file('orphan'), bytes(100));
  await first.put(file('b'), bytes(100));
  await first.flush();

  const second = new RootfsCache(cache, ROOTFS, { budgetBytes: 300 });
  assert.ok(await second.get(file('a')), 'read first, so the orphan is older still');
  await second.put(file('c'), bytes(100));
  await second.put(file('d'), bytes(100));
  assert.equal(cache.files.has(file('orphan')), false);
  assert.equal(second.bytes, 300);
});

test('a kept file whose size is not what the index says is dropped rather than served', async () => {
  const cache = new MemoryCache();
  const kept = new RootfsCache(cache, ROOTFS);
  await kept.put(file('a'), bytes(100));
  cache.files.set(file('a'), bytes(99));
  assert.equal(await kept.get(file('a')), null);
  assert.equal(cache.files.has(file('a')), false);
});

test('a cache that may not grow reads what is kept and adds nothing', async () => {
  const cache = new MemoryCache();
  await new RootfsCache(cache, ROOTFS).put(file('a'), bytes(10));
  const readOnly = new RootfsCache(cache, ROOTFS, { writable: false });
  assert.ok(await readOnly.get(file('a')));
  await readOnly.put(file('b'), bytes(10));
  assert.equal(cache.files.has(file('b')), false);
});

test('a put the browser refuses for room stops further puts and fails nothing', async () => {
  const cache = new MemoryCache();
  const kept = new RootfsCache(cache, ROOTFS);
  cache.refusePuts = new DOMException('full', 'QuotaExceededError');
  await kept.put(file('a'), bytes(10));
  cache.refusePuts = null;
  await kept.put(file('b'), bytes(10));
  assert.deepEqual(cache.under(ROOTFS), []);
});

test('only files under its own image are kept', async () => {
  const cache = new MemoryCache();
  const kept = new RootfsCache(cache, ROOTFS);
  await kept.put(`${BASE}old/rootfs/a.bin.zst`, bytes(10));
  assert.deepEqual(cache.under(BASE), []);
});
