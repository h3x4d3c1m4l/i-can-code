// The run layer of web/vm/vm_host.js (README section 9) against a fake v86 and a
// fake agent: runs, stops, parks, the watchdog and the failures it has to survive.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, test } from 'node:test';
import zlib from 'node:zlib';

import { openVm } from '../../../web/vm/vm_host.js';
import { FakeAgent } from './fake_agent.mjs';
import { FakeClock, fakeSnapshot, fakeV86 } from './fake_v86.mjs';

const SAVED_TSC = 66_000_000_000n;

let clock;
let agent;
let events;
let vm;

/** Every state the fake emulator was asked to restore, by size. */
let restoredBytes;

function open(options = {}, configure = () => {}, bundle = {}) {
  const FakeV86 = fakeV86(clock, emulator => {
    agent = new FakeAgent(emulator);
    configure(agent);
    return agent;
  });
  class V86 extends FakeV86 {

    restore_state(state) {
      restoredBytes.push(state.byteLength);
      return super.restore_state(state);
    }

  }
  vm = openVm({
    bundle: {
      manifest: { imageId: 'test', memoryMiB: 96, vgaMiB: 4, uart1: true },
      V86,
      wasm: new Uint8Array(1),
      state: fakeSnapshot(SAVED_TSC),
      rootfsUrl: 'rootfs/',
      ...bundle,
    },
    trackVisibility: false,
    onEvent: event => events.push(event),
    ...options,
  });
  return vm;
}

/** Lets the chains between the host and the fake agent run out, a park's
 *  setTimeout(0) included. */
async function settle() {
  for (let round = 0; round < 3; round++) {
    await new Promise(resolve => setTimeout(resolve, 2));
    for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
  }
}

/** Advances mocked time in watchdog samples, letting the line settle between them. */
async function tick(t, ms) {
  for (let done = 0; done < ms; done += 100) {
    t.mock.timers.tick(100);
    await settle();
  }
}

const hello = { files: { 'main.py': 'print("hello")' }, entry: 'main.py' };
const ofType = type => events.filter(event => event.type === type);
const sent = type => agent.received.filter(message => message.type === type);

beforeEach(() => {
  clock = new FakeClock();
  events = [];
  restoredBytes = [];
});

afterEach(async () => {
  await vm?.destroy();
  vm = null;
});

test('load restores the snapshot, greets the agent and parks it', async () => {
  open();
  const ready = await vm.load();
  assert.deepEqual(ready, { type: 'ready', python: 'Python 3.12.14', tk: '8.6.16', imageId: 'test' });
  assert.equal(vm.state, 'parked');
  assert.equal(vm.emulator.cpu_is_running, false);
  const [greeting] = sent('HELLO');
  assert.match(greeting.body.entropy, /^[0-9a-f]{128}$/);
  assert.ok(Math.abs(greeting.body.now_ms - Date.now()) < 1000);
});

test('loads share one attempt', async () => {
  open();
  const [a, b] = await Promise.all([vm.load(), vm.load()]);
  assert.equal(a, b);
  assert.equal(sent('HELLO').length, 1);
});

test('a run writes its files, sends RUN, and reports what the program does', async () => {
  open();
  await vm.load();
  agent.onRun = id => {
    const encoded = new TextEncoder().encode('héllo\n');
    // A character split across two frames still decodes as one.
    agent.output('stdout', encoded.subarray(0, 2));
    agent.output('stdout', encoded.subarray(2));
    agent.output('stderr', new TextEncoder().encode('careful\n'));
    agent.send('WINDOW', { windows: [{ xid: 7, title: 'tk', x: 0, y: 0, w: 200, h: 100, mapped: true, root: true, transient_for: null }] }, id);
    agent.send('HINT', { kind: 'tk_no_mainloop' }, id);
    agent.exit({ code: 0, ms: 1234 });
  };
  const run = vm.run({ files: { 'main.py': 'print(1)', 'picture.png': new Uint8Array([1, 2, 3]) }, entry: 'main.py', argv: ['one'] });
  const ended = await run.ended;
  assert.deepEqual(ended, { type: 'ended', run: run.id, reason: 'exit', code: 0, signal: null, truncated: false, ms: 1234, message: null });

  const [runMessage] = sent('RUN');
  assert.equal(runMessage.id, run.id);
  assert.deepEqual(runMessage.body, { entry: 'main.py', files: ['main.py', 'picture.png'], argv: ['one'], stdin: false, output_cap: 262144 });
  assert.ok(agent.received.indexOf(runMessage) > agent.received.indexOf(sent('HELLO').at(-1)), 'HELLO comes before RUN');

  const output = stream => ofType('output').filter(e => e.stream === stream).map(e => e.text).join('');
  assert.equal(output('stdout'), 'héllo\n');
  assert.equal(output('stderr'), 'careful\n');
  assert.equal(ofType('started')[0].warm, true);
  assert.equal(ofType('window')[0].windows[0].xid, 7);
  assert.ok(events.indexOf(ofType('hint')[0]) < events.indexOf(ended));

  await settle();
  assert.equal(vm.state, 'parked');
  assert.equal(vm.emulator.cpu_is_running, false);
  assert.equal(vm.emulator.files.size, 0, 'the park restored the snapshot');
});

test('stop() ends the run for the caller at once and parks on its EXIT', async () => {
  open();
  await vm.load();
  const run = vm.run(hello);
  await settle();
  assert.equal(vm.state, 'running');
  const parked = vm.stop();
  assert.equal(ofType('ended').length, 1, 'ended before the guest answered');
  assert.equal((await run.ended).reason, 'stopped');
  await parked;
  assert.equal(vm.state, 'parked');
  assert.equal(sent('STOP')[0].id, run.id);
  assert.notEqual(ofType('stop-answered')[0].ms, null);
  assert.equal(ofType('ended').length, 1, 'the EXIT for STOP is not reported again');
});

test('a stopped agent does not hold the park: it happens 500 ms after STOP', async () => {
  open();
  await vm.load();
  const run = vm.run(hello);
  await settle();
  agent.frozen = true;
  const started = performance.now();
  await vm.stop();
  const ms = performance.now() - started;
  assert.equal((await run.ended).reason, 'stopped');
  assert.ok(ms >= 450 && ms < 2000, `${ms} ms`);
  assert.equal(ofType('stop-answered')[0].ms, null);
  assert.equal(vm.state, 'parked');
});

test('stop() before RUN was sent sends nothing and parks', async () => {
  open();
  await vm.load();
  agent.frozen = true;
  const run = vm.run(hello);
  await settle();
  await vm.stop();
  assert.equal((await run.ended).reason, 'stopped');
  assert.equal(sent('RUN').length, 0);
  assert.equal(vm.state, 'parked');
});

test('a new run supersedes the one in progress', async () => {
  open();
  await vm.load();
  const first = vm.run(hello);
  await settle();
  let second;
  agent.onRun = id => {
    if (id === second.id) agent.exit({ code: 3 });
  };
  second = vm.run(hello);
  assert.equal((await first.ended).reason, 'stopped');
  const ended = await second.ended;
  assert.equal(ended.reason, 'exit');
  assert.equal(ended.code, 3);
  assert.deepEqual(sent('RUN').map(m => m.id), [first.id, second.id]);
});

test('a queued run replaced before it starts ends as stopped without starting', async () => {
  open();
  await vm.load();
  vm.run(hello);
  await settle();
  const queued = vm.run(hello);
  const last = vm.run(hello);
  assert.equal((await queued.ended).reason, 'stopped');
  await settle();
  await settle();
  assert.equal(sent('RUN').some(m => m.id === queued.id), false);
  assert.equal(sent('RUN').at(-1).id, last.id);
});

test('a run asked for before load() loads first, then runs', async () => {
  open({}, fake => { fake.onRun = () => fake.exit({}); });
  const run = vm.run(hello);
  assert.equal((await run.ended).reason, 'exit');
  assert.equal(ofType('ready').length, 1);
});

test('without a PONG the run ends as unresponsive, and a second expiry fails the VM', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  open({ now: () => Date.now() });
  await vm.load();
  const run = vm.run(hello);
  await settle();
  assert.equal(vm.state, 'running');
  agent.frozen = true;
  await tick(t, 2900);
  assert.equal(ofType('ended').length, 0);
  await tick(t, 200);
  assert.equal((await run.ended).reason, 'unresponsive');
  await settle();
  assert.equal(vm.state, 'parked');

  // The restored agent is as unresponsive: the next deadline is the second strike.
  agent.frozen = true;
  const next = vm.run(hello);
  await settle();
  await tick(t, 1100);
  assert.equal((await next.ended).reason, 'unresponsive');
  assert.equal(vm.state, 'failed');
  assert.equal(ofType('failed')[0].reason, 'unresponsive');
  assert.equal((await vm.run(hello).ended).reason, 'broken');
});

test('a PONG in time keeps the run going and resets the strikes', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  open({ now: () => Date.now() });
  await vm.load();
  vm.run(hello);
  await settle();
  await tick(t, 20_000);
  assert.equal(vm.state, 'running');
  assert.ok(sent('PING').length >= 9);
});

test('a hidden page stops the CPU and never trips the watchdog; coming back sets the clock', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  open({ now: () => Date.now() });
  await vm.load();
  const run = vm.run(hello);
  await settle();
  vm.setVisible(false);
  await settle();
  assert.equal(vm.emulator.cpu_is_running, false);
  await tick(t, 60_000);
  assert.equal(ofType('ended').length, 0);
  const hellos = sent('HELLO').length;
  vm.setVisible(true);
  await settle();
  assert.equal(vm.emulator.cpu_is_running, true);
  assert.equal(sent('HELLO').length, hellos + 1, 'a HELLO puts the clock right');
  assert.ok(Math.abs(sent('HELLO').at(-1).body.now_ms - Date.now()) < 1000);
  await tick(t, 5000);
  assert.equal(vm.state, 'running');
  assert.equal(ofType('ended').length, 0);
  vm.stop();
  assert.equal((await run.ended).reason, 'stopped');
});

test('a hidden page during load waits, and does not fail it', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  open({ now: () => Date.now() });
  vm.setVisible(false);
  const loading = vm.load();
  await settle();
  await tick(t, 10_000);
  vm.setVisible(true);
  await settle();
  assert.equal((await loading).type, 'ready');
});

test('the first HELLO deadline of a start parks and tries the same run again', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  open({ now: () => Date.now() });
  await vm.load();
  agent.frozen = true;
  agent.onRun = () => agent.exit({});
  const run = vm.run(hello);
  await settle();
  await tick(t, 1100);
  await settle();
  assert.equal((await run.ended).reason, 'exit');
  assert.deepEqual(sent('RUN').map(m => m.id), [run.id]);
  assert.ok(ofType('log').some(e => /trying run/.test(e.message)));
});

test('a rootfs file that cannot be fetched ends the run as fetch, and the VM stays usable', async () => {
  open({ fetchFile: async () => { throw Object.assign(new Error('HTTP 404'), { status: 404 }); } });
  await vm.load();
  agent.onRun = () => { vm.emulator.fs9p.read('/usr/lib/this.py'); };
  const run = vm.run(hello);
  const ended = await run.ended;
  assert.equal(ended.reason, 'fetch');
  assert.match(ended.message, /\/usr\/lib\/this\.py/);
  await settle();
  assert.equal(vm.state, 'parked');
  agent.onRun = () => agent.exit({});
  assert.equal((await vm.run(hello).ended).reason, 'exit');
});

test('a run the agent refuses ends as broken', async () => {
  open();
  await vm.load();
  agent.refuse = 'spawn_failed';
  const ended = await vm.run(hello).ended;
  assert.equal(ended.reason, 'broken');
  assert.match(ended.message, /spawn_failed/);
  await settle();
  assert.equal(vm.state, 'parked');
});

test('an unasked READY during a run means the agent restarted', async () => {
  open();
  await vm.load();
  const run = vm.run(hello);
  await settle();
  agent.send('READY', { agent: 'fake', python: null, tk: null, tz: 'UTC', warm: false }, 0);
  assert.equal((await run.ended).reason, 'broken');
});

test('output of a run that has ended is dropped', async () => {
  open();
  await vm.load();
  const run = vm.run(hello);
  await settle();
  agent.answersStop = false;
  vm.stop();
  await run.ended;
  agent.output('stdout', new TextEncoder().encode('te laat'));
  await settle();
  assert.equal(ofType('output').length, 0);
});

test('closeWindow sends CLOSE for the running run', async () => {
  open();
  await vm.load();
  const closed = [];
  agent.onClose = xid => closed.push(xid);
  const run = vm.run(hello);
  await settle();
  vm.closeWindow(7);
  await settle();
  assert.deepEqual(closed, [7]);
  assert.equal(sent('CLOSE')[0].id, run.id);
});

test('a program the protocol cannot carry is refused before anything is sent', async () => {
  open();
  await vm.load();
  assert.throws(() => vm.run({ files: { '../x.py': '' }, entry: '../x.py' }), TypeError);
  assert.throws(() => vm.run({ files: { 'a.py': '' }, entry: 'main.py' }), TypeError);
  assert.throws(() => vm.run({ files: { 'main.py': new Uint8Array(8 * 1024 * 1024 + 1) }, entry: 'main.py' }), TypeError);
  assert.throws(() => vm.run({ files: { 'main.py': '' }, entry: 'main.py', argv: ['x'.repeat(5000)] }), TypeError);
  assert.equal(sent('RUN').length, 0);
});

test('destroy ends the run and a queued one as stopped', async () => {
  open();
  await vm.load();
  const first = vm.run(hello);
  await settle();
  const second = vm.run(hello);
  await vm.destroy();
  assert.equal((await first.ended).reason, 'stopped');
  assert.equal((await second.ended).reason, 'stopped');
  assert.equal(vm.state, 'destroyed');
});

test('an image built for another protocol fails as incompatible before anything is fetched', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'icc-vm-'));
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ imageId: 'x', agentProto: 2 }));
  vm = openVm({ baseUrl: `${dir}/`, trackVisibility: false, onEvent: event => events.push(event) });
  const failed = await vm.load();
  assert.equal(failed.type, 'failed');
  assert.equal(failed.reason, 'incompatible');
  fs.rmSync(dir, { recursive: true });
});

test('a missing image fails as network, and the next load or run tries again', async () => {
  vm = openVm({ baseUrl: '/nonexistent/icc-vm/', trackVisibility: false, onEvent: event => events.push(event) });
  const failed = await vm.load();
  assert.equal(failed.reason, 'network');
  assert.notEqual(await vm.load(), failed);
  const ended = await vm.run(hello).ended;
  assert.equal(ended.reason, 'broken', 'the run waited for the load, which failed again');
  assert.equal(ofType('failed').length, 3);
});

test('a hint reaches the caller once per run, and only a kind README 6.8 lists', async () => {
  open();
  await vm.load();
  agent.onRun = id => {
    for (let i = 0; i < 50; i++) agent.send('HINT', { kind: 'tk_no_mainloop' }, id);
    agent.send('HINT', { kind: 'made_up' }, id);
    agent.exit({});
  };
  await vm.run(hello).ended;
  assert.deepEqual(ofType('hint').map(e => e.kind), ['tk_no_mainloop']);
  assert.equal(vm.stats.hintsDropped, 50);
  agent.onRun = id => {
    agent.send('HINT', { kind: 'tk_no_mainloop' }, id);
    agent.exit({});
  };
  await settle();
  await vm.run(hello).ended;
  assert.equal(ofType('hint').length, 2, 'the next run starts afresh');
});

const v86Wasm = new URL('../node_modules/v86/build/v86.wasm', import.meta.url);
const noDecoder = !fs.existsSync(v86Wasm) ? 'needs v86.wasm: npm ci --prefix vm/tools'
  : typeof zlib.zstdCompressSync !== 'function' ? 'needs a Node with zlib.zstdCompressSync' : false;

test('a zstd state is decompressed once, and the load and every park restore the raw one', { skip: noDecoder }, async () => {
  const raw = new Uint8Array(fakeSnapshot(SAVED_TSC));
  const compressed = zlib.zstdCompressSync(raw);
  open({}, fake => { fake.onRun = () => fake.exit({}); }, {
    manifest: { imageId: 'test', memoryMiB: 96, vgaMiB: 4, uart1: true, state: { rawBytes: raw.byteLength } },
    wasm: fs.readFileSync(v86Wasm),
    state: compressed.buffer.slice(compressed.byteOffset, compressed.byteOffset + compressed.byteLength),
  });
  assert.equal((await vm.load()).type, 'ready');
  assert.equal(vm.stats.inflate.where, 'inline');
  await vm.run(hello).ended;
  await vm.run(hello).ended;
  await settle();
  assert.equal(vm.state, 'parked');
  assert.deepEqual(restoredBytes, [8, 8, 8]);
});

test('a state that will not decompress is restored as it is', async () => {
  const compressed = new Uint8Array(fakeSnapshot(SAVED_TSC));
  compressed.set([0x28, 0xB5, 0x2F, 0xFD]);
  open({}, () => {}, {
    manifest: { imageId: 'test', memoryMiB: 96, vgaMiB: 4, uart1: true, state: { rawBytes: 1024 } },
    state: compressed.buffer,
  });
  assert.equal((await vm.load()).type, 'ready');
  assert.equal(vm.stats.inflate, null);
  assert.ok(ofType('log').some(e => e.level === 'warn' && /stays compressed/.test(e.message)));
  assert.deepEqual(restoredBytes, [8]);
});

test('destroy lets go of the image, so other tabs may clean it up', async () => {
  let released = 0;
  open({}, () => {}, { release: () => { released++; } });
  await vm.load();
  await vm.destroy();
  assert.equal(released, 1);
});

// A second openVm() on the page

test('a Vm a newer openVm() replaced tells its page, after its runs end', async () => {
  open();
  await vm.load();
  const replaced = vm;
  const run = replaced.run(hello);
  await settle();
  const before = events.length;
  const newer = open();
  assert.equal((await run.ended).reason, 'stopped');
  const heard = events.slice(before);
  assert.deepEqual(heard.map(e => e.type), ['ended', 'failed']);
  assert.equal(heard[1].reason, 'replaced');
  assert.equal(replaced.state, 'destroyed');
  assert.equal((await replaced.load()).reason, 'replaced', 'a Retry on the replaced one hears it again');
  assert.equal((await replaced.run(hello).ended).reason, 'broken');
  assert.equal((await newer.load()).type, 'ready');
});

test('a load in flight when its Vm is replaced resolves as replaced, and the page hears it once', async () => {
  const heard = [];
  const loading = openVm({
    bundle: { manifest: { imageId: 'test', memoryMiB: 96, vgaMiB: 4, uart1: true }, V86: fakeV86(clock), wasm: new Uint8Array(1), state: fakeSnapshot(SAVED_TSC), rootfsUrl: 'rootfs/' },
    trackVisibility: false,
    onEvent: event => heard.push(event),
  }).load();
  open();
  assert.equal((await loading).reason, 'replaced');
  assert.deepEqual(heard.filter(e => e.type === 'failed').map(e => e.reason), ['replaced']);
  assert.equal((await vm.load()).type, 'ready');
});

test('a Vm its own page destroys reports no failure', async () => {
  open();
  await vm.load();
  await vm.destroy();
  assert.equal(ofType('failed').length, 0);
});

// A state that does not work

/** Opens a Vm on a bundle whose V86 is `V86`, counting what the bundle is asked to let go of. */
function openOn(V86, options = {}) {
  const counts = { evicted: 0, released: 0 };
  vm = openVm({
    bundle: {
      manifest: { imageId: 'test', memoryMiB: 96, vgaMiB: 4, uart1: true },
      V86,
      wasm: new Uint8Array(1),
      state: fakeSnapshot(SAVED_TSC),
      rootfsUrl: 'rootfs/',
      evictState: async () => { counts.evicted++; },
      release: () => { counts.released++; },
    },
    trackVisibility: false,
    onEvent: event => events.push(event),
    ...options,
  });
  return counts;
}

test('a state that will not restore is dropped, cached copy and all, and the next load reads it again', async () => {
  let broken = true;
  let restores = 0;
  const counts = openOn(class extends fakeV86(clock, emulator => new FakeAgent(emulator)) {

    restore_state(state) {
      restores++;
      if (broken) throw new Error('out of bounds');
      return super.restore_state(state);
    }

  });
  const failed = await vm.load();
  assert.equal(failed.reason, 'broken');
  assert.match(failed.message, /did not restore/);
  assert.deepEqual(counts, { evicted: 1, released: 1 }, 'the image lock goes with the bundle');
  broken = false;
  assert.equal((await vm.load()).type, 'ready');
  assert.equal(restores, 2);
});

test('a state whose agent never answers HELLO is dropped as well', async t => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'] });
  const counts = openOn(fakeV86(clock, emulator => {
    const mute = new FakeAgent(emulator);
    mute.receive = () => {};
    return mute;
  }), { now: () => Date.now() });
  const loading = vm.load();
  await settle();
  await tick(t, 1100);
  await tick(t, 1100);
  const failed = await loading;
  assert.equal(failed.reason, 'unresponsive');
  assert.deepEqual(counts, { evicted: 1, released: 1 });
});

test('a failure after the load leaves the state alone', async () => {
  const counts = openOn(fakeV86(clock, emulator => {
    agent = new FakeAgent(emulator);
    agent.refuse = 'bad_run';
    return agent;
  }));
  await vm.load();
  assert.equal((await vm.run(hello).ended).reason, 'broken');
  assert.deepEqual(counts, { evicted: 0, released: 0 });
});

test('a machine rebuilt by a park the page leaves meanwhile is freed', async () => {
  const emulators = [];
  let restores = 0;
  const slow = { loadAfterMs: 0 };
  openOn(class extends fakeV86(clock, emulator => {
    agent = new FakeAgent(emulator);
    agent.onRun = () => agent.exit({});
    return agent;
  }, slow) {

    constructor(options) {
      super(options);
      emulators.push(this);
    }

    restore_state(state) {
      // The first park's restore fails, which rebuilds the emulator.
      if (++restores === 2) throw new Error('out of bounds');
      return super.restore_state(state);
    }

  });
  await vm.load();
  slow.loadAfterMs = 30;
  await vm.run(hello).ended;
  await settle();
  assert.equal(emulators.length, 2, 'the park is rebuilding');
  await vm.destroy();
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.deepEqual(emulators.map(e => e.destroyed), [true, true]);
});
