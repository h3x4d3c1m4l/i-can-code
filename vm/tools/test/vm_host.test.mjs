import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createVmHost } from '../../../web/vm/vm_host.js';
import { yieldThroughChannel } from '../../../web/vm/vm_machine.js';
import { FakeClock, fakeSnapshot, fakeV86, HASHED } from './fake_v86.mjs';

// The saved TSC of a snapshot taken 66 s after boot, the spike image's uptime.
const SAVED_TSC = 66_000_000_000n;
const SECOND_NS = 1_000_000_000n;

let clock;
let events;
let host;

async function makeHost(options = {}) {
  host = await createVmHost({
    V86: fakeV86(clock),
    wasm: new Uint8Array(1),
    memoryMiB: 96,
    vgaMiB: 4,
    rootfsUrl: 'rootfs/',
    onEvent: event => events.push(event),
    ...options,
  });
  return host;
}

const cpuOf = h => h.emulator.v86.cpu;

/** Mocked time moves Date to the end of a tick before the interval runs, so the
 *  watchdog has to be stepped one sample at a time. */
function advance(t, ms) {
  for (; ms >= 100; ms -= 100) t.mock.timers.tick(100);
  if (ms > 0) t.mock.timers.tick(ms);
}

beforeEach(() => {
  clock = new FakeClock();
  events = [];
});

afterEach(async () => {
  await host?.destroy();
  host = null;
});

test('six consecutive restores all land the TSC on the saved value', async () => {
  await makeHost();
  const landed = [];
  for (let i = 0; i < 6; i++) {
    clock.advance(1500);
    await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
    landed.push(cpuOf(host).tsc());
    await host.resume();
    clock.advance(1000);
    await host.pause();
  }
  assert.deepEqual(landed, Array(6).fill(SAVED_TSC));
});

test('without zeroing the offset first, every second restore lands far below the saved TSC', async () => {
  // The arithmetic restoreSnapshot works around, driven through the raw emulator.
  await makeHost();
  const emulator = host.emulator;
  const landed = [];
  for (let i = 0; i < 4; i++) {
    clock.advance(1500);
    await emulator.restore_state(fakeSnapshot(SAVED_TSC));
    landed.push(cpuOf(host).tsc() >= SAVED_TSC);
  }
  assert.deepEqual(landed, [true, false, true, false]);
});

test('the guest does not see time pass while it is parked', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  clock.advance(2000);
  await host.pause();
  clock.advance(15 * 60_000);
  await host.resume();
  assert.equal(cpuOf(host).tsc(), SAVED_TSC + 2n * SECOND_NS);
  clock.advance(500);
  assert.equal(cpuOf(host).tsc(), SAVED_TSC + 2n * SECOND_NS + SECOND_NS / 2n);
});

test('a snapshot passed as a typed array restores the same as its buffer', async () => {
  await makeHost();
  const view = new Uint8Array(16);
  view.set(new Uint8Array(fakeSnapshot(SAVED_TSC)), 4);
  await host.restoreSnapshot(view.subarray(4, 12));
  assert.equal(cpuOf(host).tsc(), SAVED_TSC);
  assert.equal(host.memoryUsage().snapshotBytes, 8);
});

test('restoreSnapshot parks the machine, and a second park reuses the kept snapshot', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  clock.advance(3000);
  const { ms, syncMs } = await host.restoreSnapshot();
  assert.equal(host.running, false);
  assert.equal(host.emulator.cpu_is_running, false);
  assert.equal(cpuOf(host).tsc(), SAVED_TSC);
  assert.ok(syncMs <= ms);
});

test('resume before any restore is refused', async () => {
  await makeHost();
  await assert.rejects(host.resume(), /restoreSnapshot\(\) must come first/);
  assert.equal(host.emulator.cpu_is_running, false);
});

test('a restore that fails leaves nothing to resume', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await assert.rejects(host.restoreSnapshot(new ArrayBuffer(4)), RangeError);
  await assert.rejects(host.resume(), /restoreSnapshot\(\) must come first/);
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  assert.equal(host.running, true);
});

test('a hidden page stops the CPU and a visible one starts it again', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  assert.equal(host.emulator.cpu_is_running, true);
  await host.setVisible(false);
  assert.equal(host.emulator.cpu_is_running, false);
  await host.setVisible(true);
  assert.equal(host.emulator.cpu_is_running, true);
});

test('becoming visible does not start a parked machine', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.setVisible(false);
  await host.setVisible(true);
  assert.equal(host.emulator.cpu_is_running, false);
});

test('resume while hidden waits for the page to become visible', async () => {
  await makeHost();
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.setVisible(false);
  await host.resume();
  assert.equal(host.emulator.cpu_is_running, false);
  await host.setVisible(true);
  assert.equal(host.emulator.cpu_is_running, true);
});

test('a backgrounded run never trips the watchdog, and a visible one still does', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  await makeHost({ now: () => Date.now() });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  let unresponsive = 0;
  host.watchdog.start(1000, () => { unresponsive++; });
  advance(t, 900);

  const hiding = host.setVisible(false);
  assert.equal(host.watchdog.counting, false, 'stops counting before the CPU stop is even queued');
  await hiding;
  advance(t, 30 * 60_000);
  assert.equal(unresponsive, 0);

  await host.setVisible(true);
  advance(t, 900);
  assert.equal(unresponsive, 0);
  advance(t, 100);
  assert.equal(unresponsive, 1);
});

test('a rootfs fetch in flight holds the watchdog until it lands', async t => {
  const { fetchFile } = fetchFrom({ 'this.bin': THIS_PY }, { delays: { 'this.bin': 50 } });
  await makeHost({ fetchFile, now: () => Date.now() });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  host.watchdog.start(1000, () => {});
  const read = host.emulator.fs9p.read('/usr/lib/this.py');
  assert.equal(host.watchdog.counting, false);
  await read;
  assert.equal(host.watchdog.counting, true);
});

test('a rootfs fetch that lands does not hand the guest a fresh deadline', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  const { fetchFile } = fetchFrom({ 'this.bin': THIS_PY });
  await makeHost({ fetchFile, now: () => Date.now() });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.resume();
  let unresponsive = 0;
  host.watchdog.start(1000, () => { unresponsive++; });
  advance(t, 900);
  await host.emulator.fs9p.read('/usr/lib/this.py');
  advance(t, 100);
  assert.equal(unresponsive, 1);
});

test('a parked machine is not watched', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  await makeHost({ now: () => Date.now() });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  let unresponsive = 0;
  host.watchdog.start(1000, () => { unresponsive++; });
  advance(t, 10 * 60_000);
  assert.equal(unresponsive, 0);
});

test('a new host destroys the previous one', async () => {
  const first = await makeHost();
  await first.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await first.resume();
  const second = await makeHost();
  assert.equal(first.emulator.destroyed, true);
  await assert.rejects(first.resume(), /destroyed/);
  assert.notEqual(second, first);
});

/** A fake v86 that loads `loadAfterMs` after it is built, and remembers every one built. */
function slowV86(emulators, loadAfterMs = 30) {
  return class extends fakeV86(clock, null, { loadAfterMs }) {

    constructor(options) {
      super(options);
      emulators.push(this);
    }

  };
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

test('a host replaced while its v86 is still loading frees that emulator once it has loaded', async () => {
  // The review's host-leak.mjs: the real starter sets `v86` only once wasm_fn resolves.
  const emulators = [];
  const options = { V86: slowV86(emulators), wasm: new Uint8Array(1), memoryMiB: 96, vgaMiB: 4, rootfsUrl: 'rootfs/', trackVisibility: false };
  const first = createVmHost(options).then(() => null, error => error);
  await sleep(5);
  host = await createVmHost(options);
  assert.match((await first)?.message ?? 'resolved', /destroyed while it loaded/);
  assert.equal(emulators.length, 2);
  assert.equal(emulators[0].destroyed, true, 'the replaced emulator was freed once it had loaded');
  assert.equal(emulators[1].destroyed, undefined);
});

test('a host destroyed while it loads adds no visibility listener', async () => {
  const listeners = [];
  globalThis.document = {
    visibilityState: 'visible',
    addEventListener: (type, listener) => listeners.push(listener),
    removeEventListener: (type, listener) => listeners.splice(listeners.indexOf(listener), 1),
  };
  try {
    const options = { V86: slowV86([]), wasm: new Uint8Array(1), memoryMiB: 96, vgaMiB: 4, rootfsUrl: 'rootfs/' };
    const first = createVmHost(options).then(() => null, error => error);
    await sleep(5);
    host = await createVmHost(options);
    assert.ok(await first instanceof Error);
    assert.equal(listeners.length, 1, 'only the live host listens');
    await host.destroy();
    assert.equal(listeners.length, 0);
  } finally {
    delete globalThis.document;
  }
});

test('a v86 that loads after the timeout is still freed', { timeout: 5000 }, async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const emulators = [];
  const creating = createVmHost({ V86: slowV86(emulators, 40_000), wasm: new Uint8Array(1), memoryMiB: 96, vgaMiB: 4, rootfsUrl: 'rootfs/', trackVisibility: false })
    .then(() => null, error => error);
  t.mock.timers.tick(30_000);
  assert.match((await creating)?.message ?? 'resolved', /did not load/);
  assert.equal(emulators[0].destroyed, undefined);
  t.mock.timers.tick(10_000);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(emulators[0].destroyed, true);
});

test('a wasm that fails to instantiate rejects creation', async () => {
  class BrokenV86 {

    constructor(options) {
      options.wasm_fn({ env: {} });
    }

    add_listener() {}

  }
  await assert.rejects(
    createVmHost({ V86: BrokenV86, wasm: new Uint8Array([1, 2, 3]), memoryMiB: 96, vgaMiB: 4, rootfsUrl: 'r/' }),
    WebAssembly.CompileError,
  );
});

// Rootfs fetches

const pending = Symbol('pending');

/** Resolves with `pending` if `promise` has not settled after `ms` of real time. */
function settledWithin(promise, ms) {
  return Promise.race([promise, new Promise(resolve => setTimeout(() => resolve(pending), ms))]);
}

function fetchFrom(files, { failures = {}, delays = {} } = {}) {
  const calls = [];
  const fetchFile = async url => {
    calls.push(url);
    const name = url.slice(url.lastIndexOf('/') + 1);
    if (delays[name]) await new Promise(resolve => setTimeout(resolve, delays[name]));
    const failure = failures[name]?.shift();
    if (failure) throw failure;
    if (!(name in files)) throw Object.assign(new Error('HTTP 404'), { status: 404 });
    return files[name];
  };
  return { fetchFile, calls };
}

const THIS_PY = new TextEncoder().encode('import antigravity');
const TEN_MIB = new Uint8Array(10 * 1024 * 1024);

test('a missing rootfs file reports fetch-failed with its guest path, at once', async () => {
  const { fetchFile, calls } = fetchFrom({});
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const read = host.emulator.fs9p.read('/usr/lib/this.py');

  assert.equal(await settledWithin(read, 100), pending, 'the guest read is never answered');
  assert.equal(calls.length, 1, 'a 404 is not retried');
  assert.deepEqual(events.filter(e => e.type === 'fetch-failed'), [{
    type: 'fetch-failed',
    path: '/usr/lib/this.py',
    url: 'rootfs/this.bin',
    status: 404,
    message: 'HTTP 404',
    attempts: 1,
  }]);
});

test('a network error is retried, and a file that then arrives is served', async () => {
  const { fetchFile, calls } = fetchFrom({ 'this.bin': THIS_PY }, {
    failures: { 'this.bin': [new TypeError('fetch failed')] },
  });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const data = await host.emulator.fs9p.read('/usr/lib/this.py');

  assert.deepEqual(data, THIS_PY);
  assert.equal(calls.length, 2);
  assert.equal(events.some(e => e.type === 'fetch-failed'), false);
  assert.equal(events.find(e => e.type === 'rootfs-fetched').path, '/usr/lib/this.py');
  assert.equal(host.stats.rootfsFetches, 1);
});

test('a file that keeps failing is given up on after the one retry', async () => {
  const offline = () => new TypeError('fetch failed');
  const { fetchFile, calls } = fetchFrom({ 'this.bin': THIS_PY }, {
    failures: { 'this.bin': [offline(), offline(), offline()] },
  });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const read = host.emulator.fs9p.read('/usr/lib/this.py');

  assert.equal(await settledWithin(read, 1300), pending);
  assert.equal(calls.length, 2);
  const failed = events.filter(e => e.type === 'fetch-failed');
  assert.equal(failed.length, 1);
  assert.equal(failed[0].attempts, 2);
  assert.equal(failed[0].status, null);
});

test('reads of one file in flight together share one fetch', async () => {
  const { fetchFile, calls } = fetchFrom({ 'this.bin': THIS_PY }, { delays: { 'this.bin': 20 } });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const fs = host.emulator.fs9p;
  const [a, b, c] = await Promise.all([fs.read('/usr/lib/this.py'), fs.read('/usr/lib/this.py'), fs.read('/usr/lib/this.py')]);

  assert.equal(calls.length, 1);
  assert.deepEqual([a, b, c], [THIS_PY, THIS_PY, THIS_PY]);
});

test('a fetch that lands after the next restore is dropped, not answered', async () => {
  const { fetchFile } = fetchFrom({ 'this.bin': THIS_PY }, { delays: { 'this.bin': 50 } });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const read = host.emulator.fs9p.read('/usr/lib/this.py');
  await host.restoreSnapshot();

  assert.equal(await settledWithin(read, 150), pending);
  assert.equal(host.stats.staleFetchesDropped, 1);
  assert.equal(host.memoryUsage().rootfsCacheFiles, 0, 'nothing of the old machine is cached');
});

test('a failure that lands after the next restore is not reported against it', async () => {
  const { fetchFile } = fetchFrom({}, { delays: { 'this.bin': 50 } });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const read = host.emulator.fs9p.read('/usr/lib/this.py');
  await host.restoreSnapshot();

  assert.equal(await settledWithin(read, 150), pending);
  assert.equal(events.some(e => e.type === 'fetch-failed'), false);
  assert.equal(host.stats.staleFetchesDropped, 1);
});

test('a rootfs file the guest closes is not fetched again', async () => {
  const { fetchFile, calls } = fetchFrom({ 'this.bin': THIS_PY });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const fs = host.emulator.fs9p;
  await fs.read('/usr/lib/this.py');
  fs.close('/usr/lib/this.py');
  await host.restoreSnapshot();
  assert.deepEqual(await fs.read('/usr/lib/this.py'), THIS_PY);
  assert.equal(calls.length, 1);
});

test('closed files are kept up to 16 MiB, the longest closed going first', async () => {
  const { fetchFile, calls } = fetchFrom({ 'big1.bin': TEN_MIB, 'big2.bin': TEN_MIB });
  await makeHost({ fetchFile });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  const fs = host.emulator.fs9p;
  await fs.read('/usr/lib/big1');
  fs.close('/usr/lib/big1');
  await fs.read('/usr/lib/big2');
  fs.close('/usr/lib/big2');
  await fs.read('/usr/lib/big2');
  assert.equal(calls.length, 2, 'big2 was kept');
  await fs.read('/usr/lib/big1');
  assert.equal(calls.length, 3, 'big1 made room for it');
});

// Rootfs files kept between visits

/** vm_cache.js's RootfsCache, as a map. */
function fileCacheOf(entries = {}) {
  const files = new Map(Object.entries(entries));
  return {
    files,
    puts: [],
    async get(url) {
      return files.get(url) ?? null;
    },
    async put(url, bytes) {
      this.puts.push(url);
      files.set(url, bytes);
    },
    async delete(url) {
      files.delete(url);
    },
  };
}

test('a rootfs file kept from an earlier visit is read without the network', async () => {
  const { fetchFile, calls } = fetchFrom({});
  const fileCache = fileCacheOf({ [`rootfs/${HASHED.name}`]: HASHED.content });
  await makeHost({ fetchFile, fileCache });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  assert.deepEqual(await host.emulator.fs9p.read(HASHED.path), HASHED.content);
  assert.equal(calls.length, 0);
  assert.equal(host.stats.rootfsCacheHits, 1);
  assert.equal(host.stats.rootfsFetches, 0, 'a file from the cache is not a fetch');
  assert.deepEqual(events.find(e => e.type === 'rootfs-cached')?.path, HASHED.path);
  assert.equal(events.some(e => e.type === 'rootfs-fetched'), false);
});

test('a fetched rootfs file is kept once its content is what its name says', async () => {
  const { fetchFile } = fetchFrom({ [HASHED.name]: HASHED.content });
  const fileCache = fileCacheOf();
  await makeHost({ fetchFile, fileCache });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.emulator.fs9p.read(HASHED.path);
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.deepEqual(fileCache.puts, [`rootfs/${HASHED.name}`]);
});

test('a fetched rootfs file whose content is not what its name says is not kept', async () => {
  const { fetchFile } = fetchFrom({ [HASHED.name]: new TextEncoder().encode('something else') });
  const fileCache = fileCacheOf();
  await makeHost({ fetchFile, fileCache });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.emulator.fs9p.read(HASHED.path);
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.deepEqual(fileCache.puts, []);
});

test('a file whose name is not its content\'s is never kept, since nothing can check it', async () => {
  const { fetchFile } = fetchFrom({ 'this.bin': THIS_PY });
  const fileCache = fileCacheOf();
  await makeHost({ fetchFile, fileCache });
  await host.restoreSnapshot(fakeSnapshot(SAVED_TSC));
  await host.emulator.fs9p.read('/usr/lib/this.py');
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.deepEqual(fileCache.puts, []);
});

// How v86 yields

/** src/main.js's v86 as a browser build leaves it: yielding through a blob worker. */
class FakeInner {

  worker = { terminated: false, terminate() { this.terminated = true; } };
  ticks = [];

  yield_callback(tick) {
    this.ticks.push(tick);
  }

  unregister_yield() {
    this.worker.terminate();
    this.worker = null;
  }

}

const macrotask = ms => new Promise(resolve => setTimeout(resolve, ms));

test('v86 yields through a MessageChannel instead of its worker', async () => {
  const inner = new FakeInner();
  const worker = inner.worker;
  assert.equal(yieldThroughChannel(inner), true);
  assert.equal(worker.terminated, true, 'the worker v86 started is gone');
  try {
    inner.yield(0, 1);
    assert.deepEqual(inner.ticks, [], 'never from inside the slice that yields');
    await macrotask(1);
    assert.deepEqual(inner.ticks, [1]);

    inner.yield(15, 2);
    await macrotask(5);
    assert.deepEqual(inner.ticks, [1], 'an idle guest waits for its timer');
    await macrotask(20);
    assert.deepEqual(inner.ticks, [1, 2]);
  } finally {
    inner.unregister_yield();
  }
});

test('a yield replaces the timer an idle guest was waiting on', async () => {
  const inner = new FakeInner();
  yieldThroughChannel(inner);
  try {
    inner.yield(10, 1);
    inner.yield(0, 2);
    await macrotask(30);
    assert.deepEqual(inner.ticks, [2]);
  } finally {
    inner.unregister_yield();
  }
});

test('a v86 that does not yield through a worker is left alone', () => {
  // Under Node v86 yields with setImmediate and starts no worker.
  const inner = { worker: null, yield() {} };
  const before = inner.yield;
  assert.equal(yieldThroughChannel(inner), false);
  assert.equal(inner.yield, before);
});
