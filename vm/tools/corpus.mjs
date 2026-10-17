// The corpus: student programs from corpus/ run through web/vm/vm_host.js on the image bundle,
// the way the page runs them, each held to what the student should see. It also covers what the
// host has to survive: a stop, a lost agent, a rootfs file that cannot be fetched, a hidden page
// and a long park. Writes vm/build/corpus.json and exits 1 if any case failed.
//
// Usage: node corpus.mjs [--only NAME]... [--park-minutes N] [--image DIR] [--debug-image DIR]
//                        [--out FILE]
//
// The `park` and `park-detectors` cases wait --park-minutes (15) each, so they only run when named
// with --only. `agent-stopped` and `park-detectors` need the debug bundle, `just build-vm-state
// --debug-shell`, because nothing in the shipped image gives a check a root shell.

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

import { openVm } from '../../web/vm/vm_host.js';
import { crc32, decodeMessage, FrameDecoder, MAX_PAYLOAD_TO_HOST } from '../../web/vm/vm_protocol.js';
import { loadBundle, openHost, restoreAndGreet } from './lib/bundle.mjs';
import { ConsoleShell } from './lib/console_shell.mjs';
import { buildDir, imageDir } from './lib/dirs.mjs';

const toolsDir = path.dirname(new URL(import.meta.url).pathname);

const { values: opts } = parseArgs({
  options: {
    only: { type: 'string', multiple: true },
    'park-minutes': { type: 'string', default: '15' },
    image: { type: 'string', default: imageDir },
    'debug-image': { type: 'string', default: path.join(buildDir, 'debug-image') },
    out: { type: 'string' },
  },
});

const LONG = ['park', 'park-detectors'];
const wanted = name => (opts.only ? opts.only.includes(name) : !LONG.includes(name));
const parkMinutes = Number(opts['park-minutes']);

setTimeout(() => {
  console.error('corpus: gave up after 60 minutes');
  process.exit(2);
}, (60 + parkMinutes) * 60_000).unref();

const program = name => fs.readFileSync(path.join(toolsDir, 'corpus', name), 'utf8');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const round = value => (value === null || value === undefined ? null : Math.round(value));

/** What the kernel's lockup, stall and hung-task detectors print. */
const ALARM = /soft lockup|hard lockup|rcu.{0,40}stall|stall.{0,40}rcu|self-detected|blocked for more than|watchdog: BUG|hung_task/i;

// US-layout scancodes (set 1) for what the cases type.
const SCANCODES = {
  ...Object.fromEntries([...'qwertyuiop'].map((c, i) => [c, 0x10 + i])),
  ...Object.fromEntries([...'asdfghjkl'].map((c, i) => [c, 0x1E + i])),
  ...Object.fromEntries([...'zxcvbnm'].map((c, i) => [c, 0x2C + i])),
  ...Object.fromEntries([...'1234567890'].map((c, i) => [c, 0x02 + i])),
  ' ': 0x39,
  '\n': 0x1C,
};

/** One open VM and everything it reported, with what the cases do to it. */
class Session {

  events = [];
  #waiters = new Set();

  constructor(baseUrl, options = {}) {
    this.vm = openVm({ baseUrl, trackVisibility: false, onEvent: event => this.#push(event), ...options });
  }

  get emulator() {
    return this.vm.emulator;
  }

  #push(event) {
    event.at = performance.now();
    this.events.push(event);
    if (event.type === 'log' && event.level !== 'debug') console.log(`  agent ${event.level}: ${event.message}`);
    for (const waiter of [...this.#waiters]) {
      if (!waiter.test(event)) continue;
      this.#waiters.delete(waiter);
      clearTimeout(waiter.timer);
      waiter.resolve(event);
    }
  }

  /** The first event from index `from` on that `test` accepts. */
  waitFor(test, { from = 0, timeoutMs = 20_000, what = 'the event' } = {}) {
    const found = this.events.slice(from).find(test);
    if (found) return Promise.resolve(found);
    return new Promise((resolve, reject) => {
      const waiter = { test, resolve };
      waiter.timer = setTimeout(() => {
        this.#waiters.delete(waiter);
        reject(new Error(`no ${what} within ${timeoutMs} ms`));
      }, timeoutMs);
      this.#waiters.add(waiter);
    });
  }

  start(files, argv = []) {
    const from = this.events.length;
    const t0 = performance.now();
    const handle = this.vm.run({ files, entry: 'main.py', argv });
    return { id: handle.id, ended: handle.ended, t0, from };
  }

  output(run, stream = 'stdout') {
    return this.events.filter(e => e.type === 'output' && e.run === run.id && e.stream === stream).map(e => e.text).join('');
  }

  /** Resolves once the run's output matches `pattern`, with the match. */
  async waitForOutput(run, pattern, { stream = 'stdout', timeoutMs = 20_000 } = {}) {
    const matches = () => this.output(run, stream).match(pattern);
    if (!matches()) {
      await this.waitFor(e => e.type === 'output' && e.run === run.id && e.stream === stream && Boolean(matches()),
        { from: run.from, timeoutMs, what: `output matching ${pattern}` });
    }
    return matches();
  }

  /** The first JSON line on the run's stdout that has `key`. */
  async json(run, key, timeoutMs = 20_000) {
    const find = () => this.output(run).split('\n').map(line => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    }).find(value => value && typeof value === 'object' && key in value);
    if (!find()) {
      await this.waitFor(e => e.type === 'output' && e.run === run.id && Boolean(find()),
        { from: run.from, timeoutMs, what: `a JSON line with ${key}` });
    }
    return find();
  }

  /** The first WINDOW of the run that holds a window `test` accepts. */
  window(run, test, timeoutMs = 20_000) {
    return this.waitFor(e => e.type === 'window' && e.run === run.id && e.windows.some(test),
      { from: run.from, timeoutMs, what: 'the window' }).then(event => ({ event, window: event.windows.find(test) }));
  }

  windows(run) {
    return this.events.filter(e => e.type === 'window' && e.run === run.id);
  }

  /** What v86 would draw: the pixel at (x, y) of the guest's framebuffer. */
  pixel(x, y) {
    const vga = this.emulator.v86.cpu.devices.vga;
    const at = (vga.svga_offset + y * vga.svga_width + x) * 4;
    return '#' + [2, 1, 0].map(i => vga.svga_memory[at + i].toString(16).padStart(2, '0')).join('');
  }

  /** Resolves with the ms from `since` until pixel (x, y) is `colour`, or null. A colour
   *  that starts with `!` waits for the pixel to be anything else. */
  async drawn(x, y, colour, since, timeoutMs = 10_000) {
    const until = performance.now() + timeoutMs;
    const matches = colour.startsWith('!')
      ? pixel => pixel !== colour.slice(1)
      : pixel => pixel === colour;
    while (performance.now() < until) {
      if (matches(this.pixel(Math.round(x), Math.round(y)))) return performance.now() - since;
      await sleep(5);
    }
    return null;
  }

  async click(x, y) {
    this.emulator.bus.send('mouse-absolute', [Math.round(x), Math.round(y), 800, 600]);
    await sleep(150);
    this.emulator.bus.send('mouse-click', [true, false, false]);
    await sleep(100);
    this.emulator.bus.send('mouse-click', [false, false, false]);
    await sleep(100);
  }

  async type(text) {
    const codes = [];
    for (const c of text) {
      const code = SCANCODES[c];
      if (code === undefined) throw new Error(`no scancode for ${JSON.stringify(c)}`);
      codes.push(code, code | 0x80);
    }
    await this.emulator.keyboard_send_scancodes(codes, 30);
  }

  /** Rootfs files fetched since event `from`. */
  fetched(from) {
    return this.events.slice(from).filter(e => e.type === 'rootfs-fetched').map(e => e.path);
  }

}

/**
 * What the agent sends on the control line, read beside the host rather than through it: the host
 * reports no PONG, and a HINT the host dropped would hide one the agent should not have sent.
 */
class LineTap {

  /** PONG, HINT, WINDOW and EXIT frames with the host time they arrived. */
  frames = [];
  #decoder = new FrameDecoder({ maxPayload: MAX_PAYLOAD_TO_HOST });
  #pending = [];

  constructor(emulator) {
    emulator.add_listener('serial1-output-byte', byte => {
      if (this.#pending.push(byte) === 1) queueMicrotask(() => this.#flush());
    });
  }

  #flush() {
    const bytes = Uint8Array.from(this.#pending);
    this.#pending.length = 0;
    const at = performance.now();
    for (const event of this.#decoder.push(bytes)) {
      // A park cuts the line mid-frame now and then; the next frame decodes again.
      if (event.error) continue;
      const decoded = decodeMessage(event.frame, { from: 'agent' });
      if (decoded.error || !['PONG', 'HINT', 'WINDOW', 'EXIT'].includes(decoded.message.type)) continue;
      this.frames.push({ ...decoded.message, at });
    }
  }

  of(type, { id, from = 0, to = Infinity } = {}) {
    return this.frames.filter(f => f.type === type && f.at >= from && f.at <= to && (id === undefined || f.id === id));
  }

}

const results = [];

function record(result) {
  results.push(result);
  const extra = [
    result.windowMs !== undefined && `window ${round(result.windowMs)} ms`,
    result.drawnMs !== undefined && `drawn ${round(result.drawnMs)} ms`,
    result.peakKb !== undefined && `memory.peak ${result.peakKb} kB`,
    `${result.fetches} fetches${result.fetches ? ` (${result.fetched.join(' ')})` : ''}`,
  ].filter(Boolean).join(', ');
  console.log(`${result.passed ? 'PASS' : 'FAIL'}  ${result.name}: ${result.detail} [${extra}]`);
}

/** Runs one case on `session`, and parks it afterwards so the next starts from the snapshot. */
async function runCase(session, name, body) {
  if (!wanted(name)) return;
  const from = session.events.length;
  let outcome;
  try {
    outcome = await body();
  } catch (error) {
    outcome = { passed: false, detail: `threw: ${error.stack ?? error}` };
  }
  await session.vm.stop();
  const fetched = session.fetched(from);
  // The agent LOGs what the run's cgroup held at most, at debug level, before each EXIT.
  const peaks = session.events.slice(from).map(e => e.type === 'log' && /^memory\.peak (\d+) kB$/.exec(e.message)).filter(Boolean);
  const peakKb = peaks.length ? Math.max(...peaks.map(match => Number(match[1]))) : undefined;
  record({ name, ...outcome, fetches: fetched.length, fetched, peakKb });
}

function withTimeout(promise, ms, what) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`no ${what} within ${ms} ms`)), ms); }),
  ]).finally(() => clearTimeout(timer));
}

const describe = ended => ended ? `ended ${ended.reason} code ${ended.code} signal ${ended.signal}${ended.truncated ? ' truncated' : ''}` : 'not ended';

/** A PNG whose left half is `left` and right half `right`, both '#rrggbb'. */
function png(width, height, left, right) {
  const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  const rows = [];
  for (let y = 0; y < height; y++) {
    rows.push(0);
    for (let x = 0; x < width; x++) rows.push(...rgb(x < width / 2 ? left : right));
  }
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 2, 0, 0, 0], 8);
  return new Uint8Array(Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(Buffer.from(rows))),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

function hostOffset() {
  const minutes = -new Date().getTimezoneOffset();
  const sign = minutes < 0 ? '-' : '+';
  const abs = Math.abs(minutes);
  return `${sign}${String(Math.floor(abs / 60)).padStart(2, '0')}${String(abs % 60).padStart(2, '0')}`;
}

/** Host wall-clock time at performance.now() value `at`. */
const wallAt = at => Date.now() - (performance.now() - at);

const summary = {};

// The shipped bundle

const imageBase = opts.image.endsWith('/') ? opts.image : `${opts.image}/`;
const main = new Session(imageBase);
{
  const started = performance.now();
  const ready = await main.vm.load();
  summary.load = { event: ready, ms: round(performance.now() - started), manifest: main.vm.manifest };
  console.log(`loaded ${JSON.stringify(ready)} in ${summary.load.ms} ms`);
  if (ready.type !== 'ready') {
    console.error('The bundle did not load; nothing else can run.');
    process.exit(1);
  }
}
const tap = new LineTap(main.emulator);

await runCase(main, 'label', async () => {
  const run = main.start({ 'main.py': program('label.py') });
  const { event, window } = await main.window(run, w => w.title === 'Label' && w.mapped && w.root);
  const drawnMs = await main.drawn(window.x + 5, window.y + 5, '#3366cc', run.t0);
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  const out = main.output(run);
  return {
    passed: drawnMs !== null && ended.reason === 'exit' && ended.code === 0 && out.includes('mainloop is done'),
    detail: `${window.w}x${window.h} "${window.title}"; CLOSE: ${describe(ended)}, stdout ${JSON.stringify(out)}`,
    windowMs: event.at - run.t0,
    drawnMs,
  };
});

await runCase(main, 'button', async () => {
  const run = main.start({ 'main.py': program('button.py') });
  const { event } = await main.window(run, w => w.mapped && w.root);
  const { button: [x, y, w, h] } = await main.json(run, 'button');
  await main.click(x + w / 2, y + h / 2);
  await main.waitForOutput(run, /clicked 1/, { timeoutMs: 5000 });
  await main.click(x + w / 2, y + h / 2);
  await main.waitForOutput(run, /clicked 2/, { timeoutMs: 5000 });
  return { passed: true, detail: 'two synthetic clicks ran the command twice', windowMs: event.at - run.t0 };
});

await runCase(main, 'entry', async () => {
  const run = main.start({ 'main.py': program('entry.py') });
  const { event } = await main.window(run, w => w.title === 'Second window' && w.mapped);
  const { name: [x, y, w, h] } = await main.json(run, 'name');
  await sleep(300);
  // Nothing clicked: the keys go to the newest window, whose Entry has Tk's focus (F4).
  await main.type('amsterdam');
  // A click into the first window gives it the keyboard.
  await main.click(x + w / 2, y + h / 2);
  await sleep(200);
  await main.type('sanne\n');
  const typed = await main.json(run, 'city', 5000).catch(() => null);
  return {
    passed: typed?.name === 'sanne' && typed?.city === 'amsterdam',
    detail: `typed without a click, then after one: ${JSON.stringify(typed)}`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'canvas', async () => {
  const run = main.start({ 'main.py': program('canvas.py') });
  const { event } = await main.window(run, w => w.title === 'Canvas' && w.mapped);
  const drawnMs = await main.drawn(100, 70, '#22aa44', run.t0);
  const orange = await main.drawn(300, 80, '#ffa500', run.t0, 3000);
  // Somewhere along the bold word's stroke the navy fill shows. Tk draws the text after the
  // oval, so it can still be missing the moment the oval is there.
  const navyPixels = () => {
    let count = 0;
    for (let x = 100; x < 300; x++) if (main.pixel(x, 222) === '#000080') count++;
    return count;
  };
  let navy = navyPixels();
  for (const until = performance.now() + 3000; navy <= 5 && performance.now() < until; navy = navyPixels()) await sleep(50);
  return {
    passed: drawnMs !== null && orange !== null && navy > 5,
    detail: `rectangle and oval in their colours; ${navy} navy pixels across the bold text`,
    windowMs: event.at - run.t0,
    drawnMs,
  };
});

await runCase(main, 'ttk', async () => {
  const run = main.start({ 'main.py': program('ttk_widgets.py') });
  const { event, window } = await main.window(run, w => w.title === 'ttk' && w.mapped);
  await main.waitForOutput(run, /done/);
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  const stderr = main.output(run, 'stderr');
  return {
    passed: ended.reason === 'exit' && ended.code === 0 && stderr === '',
    detail: `${window.w}x${window.h}; ${describe(ended)}; stderr ${JSON.stringify(stderr.slice(0, 300))}`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'messagebox-close', async () => {
  const run = main.start({ 'main.py': program('messagebox_close.py') });
  const { event, window } = await main.window(run, w => w.mapped && !w.root);
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  const out = main.output(run);
  return {
    passed: ended.reason === 'exit' && ended.code === 0 && out.trim() === 'answer: False',
    detail: `dialog "${window.title}" ${window.w}x${window.h} at ${window.x},${window.y}; CLOSE made it answer ${JSON.stringify(out.trim())}; ${describe(ended)}`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'withdraw-dialog', async () => {
  const run = main.start({ 'main.py': program('withdraw_dialog.py') });
  const { event, window } = await main.window(run, w => w.mapped && !w.root);
  const inside = [window.x + window.w / 2, window.y + window.h - 5];
  const dialogMs = await main.drawn(...inside, '!#000000', run.t0, 5000);
  const outside = window.x > 20 ? [10, 10] : [790, 590];
  const background = main.pixel(...outside);
  const rootShown = main.windows(run).some(e => e.windows.some(w => w.root && w.mapped));
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  return {
    passed: !rootShown && background === '#000000' && dialogMs !== null && main.output(run).trim() === 'closed' && ended.code === 0,
    detail: `only "${window.title}" mapped (root mapped in any WINDOW: ${rootShown}); the screen at ${outside} is ${background}; ${describe(ended)}`,
    windowMs: event.at - run.t0,
    drawnMs: dialogMs,
  };
});

await runCase(main, 'askstring', async () => {
  const run = main.start({ 'main.py': program('askstring.py') });
  const { event } = await main.window(run, w => w.title === 'Name' && w.mapped);
  await sleep(300);
  // No click: the dialog got the keyboard because it is the newest window (F4).
  await main.type('sanne\n');
  const ended = await withTimeout(run.ended, 10_000, 'the end');
  const out = main.output(run).trim();
  return { passed: out === 'Hello sanne' && ended.code === 0, detail: `stdout ${JSON.stringify(out)}; ${describe(ended)}`, windowMs: event.at - run.t0 };
});

await runCase(main, 'animation', async () => {
  const run = main.start({ 'main.py': program('animation.py') });
  const { event } = await main.window(run, w => w.title === 'Animation' && w.mapped);
  await main.waitForOutput(run, /^10 /m);
  const firstAt = performance.now();
  await sleep(3000);
  const lines = main.output(run).trim().split('\n').map(line => line.split(' ').map(Number));
  const [first, last] = [lines[0], lines.at(-1)];
  const rate = (last[0] - first[0]) / (last[1] - first[1]);
  const guestS = last[1] - first[1];
  const hostS = (performance.now() - firstAt) / 1000;
  const lastEvent = main.events.filter(e => e.type === 'output' && e.run === run.id).at(-1);
  const clockOff = last[2] * 1000 - wallAt(lastEvent.at);
  return {
    passed: rate > 12 && Math.abs(clockOff) < 2000 && guestS > 0.5 * hostS,
    detail: `${round(rate)} steps/s at after(50) (20 at most); guest monotonic ${guestS.toFixed(2)} s over about ${hostS.toFixed(2)} s; wall clock ${round(clockOff)} ms off`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'dice', async () => {
  const outputs = [];
  for (let i = 0; i < 3; i++) {
    const run = main.start({ 'main.py': program('dice.py') });
    await withTimeout(run.ended, 10_000, 'the end');
    outputs.push(main.output(run).trim());
    await main.vm.stop();
  }
  const dice = outputs.map(o => o.split(' ').slice(0, -1).join(' '));
  const random = outputs.map(o => o.split(' ').at(-1));
  return {
    passed: new Set(dice).size === 3 && new Set(random).size === 3,
    detail: outputs.map(o => JSON.stringify(o)).join(', '),
  };
});

await runCase(main, 'clock', async () => {
  const run = main.start({ 'main.py': program('clock.py') });
  await withTimeout(run.ended, 10_000, 'the end');
  const outEvent = main.events.find(e => e.type === 'output' && e.run === run.id);
  const [ms, iso, offset] = main.output(run).trim().split(' ');
  const off = Number(ms) - wallAt(outEvent.at);
  return {
    passed: Math.abs(off) < 2000 && offset === hostOffset(),
    detail: `guest ${iso} (${offset}, host ${hostOffset()}), ${round(off)} ms from the host clock`,
  };
});

await runCase(main, 'class-app', async () => {
  const run = main.start({ 'main.py': program('app_class.py') });
  const { event, window } = await main.window(run, w => w.title === 'My app' && w.mapped && w.root);
  // Not the centre: the label's text is centred there, and a glyph may cover that pixel.
  const drawnMs = await main.drawn(window.x + 8, window.y + 8, '#aa3355', run.t0);
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  return {
    passed: window.w === 320 && window.h === 200 && drawnMs !== null && ended.code === 0,
    detail: `"${window.title}" ${window.w}x${window.h}, root ${window.root}; ${describe(ended)}`,
    windowMs: event.at - run.t0,
    drawnMs,
  };
});

await runCase(main, 'grid', async () => {
  const run = main.start({ 'main.py': program('grid.py') });
  const { event } = await main.window(run, w => w.title === 'Grid' && w.mapped);
  const cells = await main.json(run, '0,0');
  const expected = { '0,0': '#cc0000', '1,1': '#00cccc', '2,2': '#004400', '0,2': '#0000cc' };
  const seen = {};
  for (const [cell, colour] of Object.entries(expected)) {
    await main.drawn(...cells[cell], colour, run.t0, 3000);
    seen[cell] = main.pixel(...cells[cell]);
  }
  return {
    passed: Object.entries(expected).every(([cell, colour]) => seen[cell] === colour),
    detail: `cell colours ${JSON.stringify(seen)}`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'photo', async () => {
  const run = main.start({ 'main.py': program('photo.py'), 'picture.png': png(64, 48, '#ff8800', '#0088ff') });
  const { event } = await main.window(run, w => w.title === 'Picture' && w.mapped);
  const { size, at: [x, y] } = await main.json(run, 'size');
  const drawnMs = await main.drawn(x + 8, y + 8, '#ff8800', run.t0);
  const right = main.pixel(x + 56, y + 40);
  return {
    passed: size[0] === 64 && size[1] === 48 && drawnMs !== null && right === '#0088ff',
    detail: `PhotoImage ${size.join('x')} from the run's own file; halves ${main.pixel(x + 8, y + 8)} and ${right}`,
    windowMs: event.at - run.t0,
    drawnMs,
  };
});

await runCase(main, 'turtle', async () => {
  const run = main.start({ 'main.py': program('turtle_line.py') });
  const { event, window } = await main.window(run, w => w.title === 'Python Turtle Graphics' && w.mapped && w.root);
  const { line: [x, y] } = await main.json(run, 'line');
  const drawnMs = await main.drawn(x, y, '#0000ff', run.t0);
  const seen = main.pixel(x, y);
  // The first WINDOW holds the root before turtle gives it its geometry.
  const sized = main.windows(run).at(-1).windows.find(w => w.root);
  main.vm.closeWindow(window.xid);
  const ended = await withTimeout(run.ended, 10_000, 'the end after CLOSE');
  // turtle.done() runs _tkinter's own mainloop, which the prelude's watch_mainloop does not
  // see. No hint is right only because the root is gone by the time the program ends.
  const hint = main.events.find(e => e.type === 'hint' && e.run === run.id);
  return {
    passed: drawnMs !== null && ended.reason === 'exit' && ended.code === 0 && !hint,
    detail: `"${sized.title}" ${sized.w}x${sized.h}; line at ${x},${y} ${seen}; hint ${hint?.kind ?? 'none'}; ${describe(ended)}`,
    windowMs: event.at - run.t0,
    drawnMs,
  };
});

await runCase(main, 'setup', async () => {
  const report = 'import json, os, turtle\nprint(json.dumps({"delay": turtle._CFG["delay"], "files": os.listdir(".")}), flush=True)\n';
  const run = main.start({ 'main.py': report, 'icc_setup.py': 'import turtle\nturtle._CFG["delay"] = 0\n' });
  const ended = await withTimeout(run.ended, 10_000, 'the end');
  const { delay, files } = await main.json(run, 'delay');
  await main.vm.stop();

  const broken = main.start({ 'main.py': report, 'icc_setup.py': 'raise ValueError("broken setup")\n' });
  const brokenEnded = await withTimeout(broken.ended, 10_000, 'the end');
  const after = await main.json(broken, 'delay');
  const stderr = main.output(broken, 'stderr');
  return {
    passed: delay === 0 && files.join() === 'main.py' && ended.code === 0
      && after.delay === 10 && brokenEnded.code === 0
      && stderr.includes('icc_setup.py", line 1') && stderr.includes('raise ValueError("broken setup")'),
    detail: `delay ${delay}, files ${JSON.stringify(files)}, ${describe(ended)}; broken setup: delay ${after.delay}, `
      + `${describe(brokenEnded)}, stderr ${JSON.stringify(stderr.trim().split('\n').slice(-2).join(' | '))}`,
  };
});

await runCase(main, 'traceback', async () => {
  const run = main.start({ 'main.py': program('exception.py') });
  const ended = await withTimeout(run.ended, 10_000, 'the end');
  const stderr = main.output(run, 'stderr');
  const frames = stderr.split('\n').filter(line => line.startsWith('  File '));
  return {
    passed: ended.code === 1 && main.output(run) === 'start\n' &&
      stderr.startsWith('Traceback (most recent call last):\n  File "/run/icc/work/main.py", line 10, in <module>') &&
      frames.length === 3 && frames.every(line => line.includes('"/run/icc/work/main.py"')) &&
      stderr.trim().endsWith('ZeroDivisionError: division by zero'),
    detail: `${describe(ended)} after ${round(ended.ms)} ms; ${frames.length} frames, all main.py: ${frames.every(line => line.includes('main.py'))}; stderr ${JSON.stringify(stderr)}`,
    exitMs: ended.ms,
  };
});

await runCase(main, 'stop', async () => {
  const run = main.start({ 'main.py': program('busy.py') });
  await main.waitFor(e => e.type === 'started' && e.run === run.id, { from: run.from });
  await sleep(500);
  const from = main.events.length;
  const pressed = performance.now();
  const parked = main.vm.stop();
  const ended = await run.ended;
  const endedMs = performance.now() - pressed;
  await parked;
  const parkedMs = performance.now() - pressed;
  const answered = main.events.slice(from).find(e => e.type === 'stop-answered');
  const reaped = main.events.slice(from).find(e => e.type === 'log' && /reaped/.test(e.message));
  summary.stop = { endedMs, answeredMs: answered?.ms, parkedMs, reaped: reaped?.message };
  return {
    passed: ended.reason === 'stopped' && endedMs < 5 && answered?.ms !== null && answered.ms <= 50,
    detail: `ended for the caller ${endedMs.toFixed(1)} ms after stop(); EXIT ${answered?.ms?.toFixed(1)} ms after STOP; parked after ${round(parkedMs)} ms; agent: ${reaped?.message ?? 'no reap logged'}`,
  };
});

await runCase(main, 'print-loop', async () => {
  const run = main.start({ 'main.py': program('print_loop.py') });
  const ended = await withTimeout(run.ended, 60_000, 'the end');
  const bytes = Buffer.byteLength(main.output(run));
  return {
    passed: ended.reason === 'exit' && ended.code === 0 && ended.truncated && bytes === 262_144,
    detail: `1 MiB printed, ${bytes} B forwarded; ${describe(ended)} after ${round(ended.ms)} ms`,
  };
});

await runCase(main, 'no-mainloop', async () => {
  const run = main.start({ 'main.py': program('no_mainloop.py') });
  const ended = await withTimeout(run.ended, 10_000, 'the end');
  const hint = main.events.find(e => e.type === 'hint' && e.run === run.id);
  return {
    passed: hint?.kind === 'tk_no_mainloop' && ended.code === 0 && hint.at <= ended.at,
    detail: `hint ${hint?.kind} before ${describe(ended)}`,
  };
});

await runCase(main, 'sandbox', async () => {
  const run = main.start({ 'main.py': program('sandbox.py') });
  const report = await main.json(run, 'uid');
  const ended = await withTimeout(run.ended, 20_000, 'the end');
  const expected = {
    uid: 1000,
    agent: true,
    icc_in: 'PermissionError',
    ttyS1: 'PermissionError',
    signal_agent: 'PermissionError',
    agent_environ: 'PermissionError',
    root_home: 'PermissionError',
    write_root: 'OSError',
    setuid: 'PermissionError',
    no_new_privs: '1',
    write_tmp: 'ok',
    write_work: 'ok',
    // The prelude's status pipe: the program itself has to keep it for the hint, a child it
    // forks does not get it.
    status_fd_in_child: 'OSError',
    cgroup: '0::/run',
    leave_cgroup: 'PermissionError',
    flood: 'ok',
  };
  const wrong = Object.entries(expected).filter(([key, value]) => report[key] !== value);
  if (!(report.shm_kb > 0 && report.shm_kb <= 8192)) wrong.push(['shm_kb']);
  // No setuid binary to reach for, and no_new_privs would void one anyway.
  if (report.su === 0 || report.su === undefined) wrong.push(['su']);
  if (!Array.isArray(report.setuid_files) || report.setuid_files.length) wrong.push(['setuid_files']);
  // 2,000 hint lines, half of a kind the protocol does not have, and a line too long to be one.
  const hints = tap.of('HINT', { id: run.id });
  const hintEvents = main.events.filter(e => e.type === 'hint' && e.run === run.id);
  const hintsOk = hints.length <= 1 && hints.every(f => f.body.kind === 'tk_no_mainloop') && hintEvents.length <= 1;
  return {
    passed: wrong.length === 0 && hintsOk && ended.reason === 'exit' && ended.code === 0,
    detail: `${wrong.length ? `unexpected: ${JSON.stringify(Object.fromEntries(wrong.map(([k]) => [k, report[k]])))}; ` : ''}` +
      `the flood gave ${hints.length} HINT frames (${[...new Set(hints.map(f => f.body.kind))].join(', ') || 'none'}); ${describe(ended)}; ${JSON.stringify(report)}`,
  };
});

await runCase(main, 'oom', async () => {
  const consoleBefore = main.vm.consoleText().length;
  const run = main.start({ 'main.py': program('oom.py') });
  const ended = await withTimeout(run.ended, 120_000, 'the end');
  const counted = main.output(run).trim().split('\n').map(Number).filter(Number.isFinite);
  // The kernel's report of the kill is KERN_ERR, which the console only shows at level 4 or up.
  const reported = main.vm.consoleText().slice(Math.max(0, consoleBefore - 100)).split(/\r?\n/).find(line => /out of memory: killed process/i.test(line));
  return {
    passed: ended.reason === 'oom' && ended.signal === 9 && reported !== undefined,
    detail: `${describe(ended)} after ${round(ended.ms)} ms; ${counted.at(-1) ?? 0} MiB allocated before the kill, as far as it printed; ` +
      `console: ${JSON.stringify(reported?.trim() ?? 'nothing')}`,
  };
});

await runCase(main, 'memory', async () => {
  const run = main.start({ 'main.py': program('memory.py') });
  const ended = await withTimeout(run.ended, 120_000, 'the end');
  const lines = main.output(run).trim().split('\n').map(line => {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  }).filter(Boolean);
  const [mounts] = lines;
  const fills = lines.filter(line => line.mount).map(line => `${line.mount} ${line.mib} MiB (${line.error})`);
  const allocated = lines.filter(line => line.memory_mib).at(-1)?.memory_mib ?? 0;
  return {
    passed: ended.reason === 'oom' && mounts?.shm_kb <= 8192,
    detail: `/dev/shm ${mounts?.shm_kb} kB, /tmp ${mounts?.tmp_kb} kB, home ${mounts?.home_kb} kB, cgroup ${JSON.stringify(mounts?.cgroup)}; ` +
      `filled ${fills.join(', ') || 'nothing'}, then ${allocated} MiB allocated; ${describe(ended)} after ${round(ended.ms)} ms`,
  };
});

await runCase(main, 'big-files', async () => {
  // The largest run the host sends: 8 MiB of files together. The agent copies them into a tmpfs,
  // whose pages are the agent's, not the run's, and the budget has to leave room for them.
  const source = new TextEncoder().encode(program('big_files.py'));
  const data = new Uint8Array(8 * 1024 * 1024 - source.length).fill(7);
  const run = main.start({ 'main.py': source, 'data.bin': data });
  const ended = await withTimeout(run.ended, 120_000, 'the end');
  const { size, max_kb: maxKb } = await main.json(run, 'max_kb', 1000);
  const allocated = main.output(run).trim().split('\n').map(line => {
    try {
      return JSON.parse(line).memory_mib;
    } catch {
      return undefined;
    }
  }).filter(Boolean).at(-1) ?? 0;
  const budget = main.events.slice(run.from).map(e => e.type === 'log' && /^memory\.max (\d+) kB: the budget less (\d+) kB/.exec(e.message)).find(Boolean);
  const fetched = main.fetched(run.from);
  return {
    passed: ended.reason === 'oom' && size === data.length && fetched.length === 0 && budget !== undefined &&
      maxKb === Number(budget[1]) && Number(budget[2]) >= 8192,
    detail: `${size} B of data; memory.max ${maxKb} kB${budget ? ` (the budget less ${budget[2]} kB for the files)` : ''}; ` +
      `${allocated} MiB allocated; ${describe(ended)} after ${round(ended.ms)} ms; ${fetched.length} fetches during the run`,
  };
});

await runCase(main, 'window-follows', async () => {
  const run = main.start({ 'main.py': program('window_follows.py') });
  const { places } = await main.json(run, 'places');
  const names = Object.keys(places);
  const pixelAt = {};
  const until = performance.now() + 20_000;
  while (performance.now() < until && names.some(name => pixelAt[name] === undefined)) {
    for (const name of names) {
      const [x, y, colour] = places[name];
      if (pixelAt[name] === undefined && main.pixel(x, y) === colour) pixelAt[name] = performance.now();
    }
    await sleep(2);
  }
  // Longer than the host's PING interval, so a list that waits for the next wakeup shows as late.
  await sleep(2500);
  const windowAt = {};
  for (const event of main.windows(run)) {
    for (const w of event.windows) if (w.mapped && windowAt[w.title] === undefined) windowAt[w.title] = event.at;
  }
  const lags = names.map(name => (windowAt[name] === undefined || pixelAt[name] === undefined ? null : windowAt[name] - pixelAt[name]));
  const worst = Math.max(...lags.map(lag => lag ?? Infinity));
  summary.windowFollows = { lags: lags.map(round) };
  // The agent keeps the stacking order from events alone, so the last list is held to what the
  // server says, which the program asks it through `wm stackorder` once every window is up.
  const { stack } = await main.json(run, 'stack');
  const last = main.windows(run).at(-1)?.windows ?? [];
  const order = last.map(w => w.title);
  const placed = names.every(name => {
    const w = last.find(entry => entry.title === name);
    const [x, y] = places[name];
    return w && w.x === x - 10 && w.y === y - 10 && w.w === 120 && w.h === 80 && w.mapped;
  });
  const inOrder = stack.length === names.length + 1 && JSON.stringify(order) === JSON.stringify(stack);
  return {
    passed: lags.every(lag => lag !== null && lag <= 100) && inOrder && placed,
    detail: `WINDOW after the window's pixels, per window (ms): ${lags.map(lag => (lag === null ? 'never' : round(lag))).join(', ')}; worst ${round(worst)}; ` +
      `the last list in the server's stacking order: ${inOrder}, every window at its geometry: ${placed}${inOrder ? '' : ` (agent: ${order.join(', ')}; server: ${stack.join(', ')})`}`,
  };
});

await runCase(main, 'x-grab', async () => {
  const run = main.start({ 'main.py': program('x_grab.py') });
  await main.window(run, w => w.title === 'Grab' && w.mapped);
  // The first window turns blue once the short grab is over.
  const releasedMs = await main.drawn(25, 305, '#0000ff', run.t0, 15_000);
  const released = releasedMs === null ? null : run.t0 + releasedMs;
  const { first, second } = await main.json(run, 'second');
  const listed = xid => main.windows(run).find(e => e.windows.some(w => w.xid === xid && w.mapped));
  const queued = listed(second);
  const queuedLag = queued && released !== null ? queued.at - released : null;
  await main.waitForOutput(run, /grabbed/);
  const grabbedAt = performance.now();
  const after = await main.json(run, 'released', 20_000).catch(() => null);
  const releasedAt = performance.now();
  const ended = await withTimeout(run.ended, 20_000, 'the end');
  const pongs = tap.of('PONG', { from: grabbedAt, to: releasedAt }).length;
  const third = after && listed(after.released);
  return {
    passed: queuedLag !== null && queuedLag <= 100 && listed(first) !== undefined && after !== null && pongs >= 2 &&
      third !== undefined && ended.reason === 'exit' && ended.code === 0,
    detail: `short grab: the window mapped during the watcher's reply wait listed ${queuedLag === null ? 'never' : `${round(queuedLag)} ms`} after the release; ` +
      `long grab: ${pongs} PONGs in ${round(releasedAt - grabbedAt)} ms, its window listed ${third ? `${round(third.at - releasedAt)} ms after the release` : 'never'}; ${describe(ended)}`,
  };
});

await runCase(main, 'big-canvas', async () => {
  const run = main.start({ 'main.py': program('big_canvas.py') });
  await main.waitForOutput(run, /started/);
  const from = performance.now();
  const ended = await withTimeout(run.ended, 90_000, 'the end');
  const pongs = tap.of('PONG', { from, to: ended.at }).map(f => f.at);
  const gaps = pongs.slice(1).map((at, i) => at - pongs[i]);
  const stderr = main.output(run, 'stderr').trim().split('\n').at(-1);
  // What TkinterScreenViewModelBase matches to say the canvas is too large for the machine, rather
  // than show a crash of the student's own program.
  const badAlloc = /X Error of failed request:\s+BadAlloc/.test(main.output(run, 'stderr'));
  return {
    passed: ended.reason === 'exit' && ended.code === 1 && badAlloc,
    detail: `${describe(ended)} ${round(ended.at - from)} ms after it began; ${pongs.length} PONGs meanwhile, the longest gap ${round(Math.max(0, ...gaps))} ms; ` +
      `drawn: ${/drawn/.test(main.output(run))}; BadAlloc in stderr: ${badAlloc}; last stderr line ${JSON.stringify(stderr)}`,
  };
});

await runCase(main, 'hd-canvas', async () => {
  const run = main.start({ 'main.py': program('hd_canvas.py') });
  const ended = run.ended.then(value => value);
  const first = await Promise.race([main.json(run, 'drawn').catch(() => ({})), ended]);
  const hdMs = first.drawn ? await main.drawn(200, 200, '#0000ff', run.t0) : null;
  const hdGreen = main.pixel(50, 50) === '#00ff00';
  const second = first.drawn ? await Promise.race([
    main.waitFor(e => e.type === 'output' && e.run === run.id && /1600x1600/.test(e.text), { from: run.from, what: 'the 1600 x 1600 line' })
      .then(() => main.output(run).split('\n').filter(Boolean).map(line => JSON.parse(line)).find(line => line.drawn === '1600x1600'))
      .catch(() => null),
    ended,
  ]) : null;
  const squareMs = second?.drawn ? await main.drawn(50, 50, '#ff00ff', run.t0) : null;
  const done = await withTimeout(run.ended, 20_000, 'the end');
  const before = (await main.json(run, 'before', 1000).catch(() => ({}))).before;
  const stderr = main.output(run, 'stderr').trim();
  summary.hdCanvas = { before, hd: first.xorg_kb ?? null, square: second?.xorg_kb ?? null };
  return {
    passed: hdMs !== null && hdGreen && squareMs !== null && done.reason === 'exit' && done.code === 0 && stderr === '',
    detail: `1920 x 1080 drawn ${hdMs === null ? 'never' : `${round(hdMs)} ms after run()`} (green around it: ${hdGreen}), ` +
      `1600 x 1600 ${squareMs === null ? 'never' : `${round(squareMs)} ms`}; Xorg VmData / VmHWM kB before ${before?.VmData} / ${before?.VmHWM}, ` +
      `at 1920 x 1080 ${first.xorg_kb?.VmData} / ${first.xorg_kb?.VmHWM}, at 1600 x 1600 ${second?.xorg_kb?.VmData} / ${second?.xorg_kb?.VmHWM}; ` +
      `${describe(done)}${stderr ? `; stderr ${JSON.stringify(stderr.split('\n').slice(0, 2).join(' '))}` : ''}`,
    drawnMs: hdMs ?? undefined,
  };
});

await runCase(main, 'near-budget', async () => {
  const run = main.start({ 'main.py': program('near_budget.py') });
  const ended = run.ended.then(value => value);
  const filled = await Promise.race([main.json(run, 'max_kb').catch(() => ({})), ended]);
  const drawn = filled.max_kb ? await Promise.race([main.json(run, 'drawn').catch(() => null), ended]) : null;
  const drawnMs = drawn?.drawn ? await main.drawn(400, 300, '#00ffff', run.t0) : null;
  const done = await withTimeout(run.ended, 20_000, 'the end');
  const fetched = main.fetched(run.from);
  const peak = main.events.slice(run.from).map(e => e.type === 'log' && /^memory\.peak (\d+) kB$/.exec(e.message)).find(Boolean);
  const peakKb = peak ? Number(peak[1]) : null;
  const stage = value => value ? `free ${value.MemFree}, cached ${value.Cached}, mapped ${value.Mapped}, group ${value.current_kb}` : 'none';
  summary.nearBudget = { filled, drawn: drawn?.drawn ?? null, peakKb };
  return {
    passed: drawnMs !== null && done.reason === 'exit' && done.code === 0 && fetched.length === 0 &&
      peakKb !== null && filled.max_kb - peakKb < 2048,
    detail: `memory.max ${filled.max_kb} kB, ${filled.ballast_kb} kB of it filled, memory.peak ${peakKb} kB; ` +
      `the 1920 x 1080 Canvas ${drawnMs === null ? 'never drawn' : `drawn ${round(drawnMs)} ms after run()`}; kB before: ${stage(filled.before)}; ` +
      `filled: ${stage(filled.after_ballast)}; drawn: ${stage(drawn?.drawn)}; ${describe(done)}; ${fetched.length} fetches during the run`,
    drawnMs: drawnMs ?? undefined,
  };
});

await runCase(main, 'lingering', async () => {
  const run = main.start({ 'main.py': program('lingering.py') });
  await main.waitForOutput(run, /done/, { timeoutMs: 30_000 });
  const printed = main.events.find(e => e.type === 'output' && e.run === run.id && /done/.test(e.text));
  const ended = await withTimeout(run.ended, 60_000, 'the end');
  const lateMs = ended.at - printed.at;
  return {
    passed: ended.reason === 'exit' && ended.code === 0 && lateMs < 1500,
    detail: `10 children still spinning; ${describe(ended)} ${round(lateMs)} ms after the program's last line`,
  };
});

await runCase(main, 'hidden', async () => {
  const run = main.start({ 'main.py': program('animation.py') });
  const { event } = await main.window(run, w => w.title === 'Animation' && w.mapped);
  await main.waitForOutput(run, /^20 /m);
  main.vm.setVisible(false);
  await sleep(300);
  const hiddenFrom = main.events.length;
  await sleep(8000);
  const whileHidden = main.events.slice(hiddenFrom).filter(e => e.run === run.id);
  const linesBefore = main.output(run).trim().split('\n').length;
  main.vm.setVisible(true);
  await sleep(3000);
  const lines = main.output(run).trim().split('\n');
  const last = lines.at(-1).split(' ').map(Number);
  const lastEvent = main.events.filter(e => e.type === 'output' && e.run === run.id).at(-1);
  const clockOff = last[2] * 1000 - wallAt(lastEvent.at);
  const endedEarly = main.events.some(e => e.type === 'ended' && e.run === run.id);
  return {
    passed: whileHidden.length === 0 && !endedEarly && lines.length > linesBefore + 2 && Math.abs(clockOff) < 2000 && main.vm.state === 'running',
    detail: `8 s hidden: ${whileHidden.length} events from the run meanwhile, not ended: ${!endedEarly}; ${lines.length - linesBefore} lines after it came back; clock ${round(clockOff)} ms off after the resume`,
    windowMs: event.at - run.t0,
  };
});

await runCase(main, 'park', async () => {
  const consoleBefore = main.vm.consoleText().length;
  const parkedAt = Date.now();
  while (Date.now() - parkedAt < parkMinutes * 60_000) {
    await sleep(60_000);
    console.log(`  parked ${((Date.now() - parkedAt) / 60_000).toFixed(1)} min`);
  }
  const run = main.start({ 'main.py': `
import time, tkinter as tk
t0 = time.monotonic()
root = tk.Tk()
fired = []
root.after(300, lambda: (fired.append(time.monotonic() - t0), root.destroy()))
root.mainloop()
print(f"{time.time() * 1000:.0f} {fired[0]:.3f}", flush=True)
` });
  const ended = await withTimeout(run.ended, 20_000, 'the end');
  const outEvent = main.events.find(e => e.type === 'output' && e.run === run.id);
  const [ms, fired] = main.output(run).trim().split(' ').map(Number);
  const off = ms - wallAt(outEvent.at);
  const alarms = main.vm.consoleText().slice(Math.max(0, consoleBefore - 100)).split(/\r?\n/).filter(line => ALARM.test(line));
  return {
    passed: ended.code === 0 && Math.abs(off) < 2000 && fired > 0.25 && fired < 3 && alarms.length === 0,
    detail: `after ${parkMinutes} min parked: clock ${round(off)} ms off, after(300) fired at ${fired} s; console alarms: ${alarms.length ? alarms.join(' | ') : 'none'}`,
  };
});

summary.mainStats = main.vm.stats;
await main.vm.destroy();

// A rootfs file that cannot be fetched (F3)

if (wanted('fetch-failure')) {
  // The stdlib is named for the interpreter's minor version, which the Alpine release decides.
  const stdlib = `/usr/lib/python${/^Python (\d+\.\d+)/.exec(summary.load.manifest.interpreter.python)[1]}`;
  const victim = `${stdlib}/antigravity.py`;
  const flakyVictim = `${stdlib}/this.py`;
  const plan = {};
  const failedOnce = new Set();
  const session = new Session(imageBase, {
    async fetchFile(url, signal) {
      const name = path.basename(url);
      if (plan[name] === 'missing') throw Object.assign(new Error('HTTP 404'), { status: 404 });
      if (plan[name] === 'flaky' && !failedOnce.has(name)) {
        failedOnce.add(name);
        throw Object.assign(new Error('HTTP 503'), { status: 503 });
      }
      return new Uint8Array(await fs.promises.readFile(url, { signal }));
    },
  });
  await session.vm.load();
  const blob = file => session.emulator.fs9p.inodes[session.emulator.fs9p.SearchPath(file).id].sha256sum;
  plan[blob(victim)] = 'missing';
  plan[blob(flakyVictim)] = 'flaky';
  await runCase(session, 'fetch-failure', async () => {
    const run = session.start({ 'main.py': `print("before", flush=True)\nopen("${victim}").read()\nprint("after")\n` });
    const ended = await withTimeout(run.ended, 10_000, 'the end');
    await session.vm.stop();
    const failed = session.events.find(e => e.type === 'fetch-failed');
    const flaky = session.start({ 'main.py': `open("${flakyVictim}").read()\nprint("read")\n` });
    const flakyEnded = await withTimeout(flaky.ended, 15_000, 'the end');
    await session.vm.stop();
    const after = session.start({ 'main.py': program('dice.py') });
    const afterEnded = await withTimeout(after.ended, 10_000, 'the end');
    return {
      passed: ended.reason === 'fetch' && session.output(run) === 'before\n' && failed?.status === 404 &&
        flakyEnded.code === 0 && session.output(flaky).trim() === 'read' && afterEnded.code === 0,
      detail: `404: ${describe(ended)} ${round(ended.at - run.t0)} ms after run(), "${ended.message}"; a 503 once: retried, ${describe(flakyEnded)}; the next run: ${describe(afterEnded)}`,
    };
  });
  await session.vm.destroy();
}

// A stopped agent, on the debug bundle (F2's other half: a guest that cannot answer)

if (wanted('agent-stopped')) {
  const debugBase = opts['debug-image'].endsWith('/') ? opts['debug-image'] : `${opts['debug-image']}/`;
  if (!fs.existsSync(path.join(debugBase, 'manifest.json'))) {
    record({ name: 'agent-stopped', passed: false, detail: `no debug bundle at ${debugBase}; run \`just build-vm-state --debug-shell\``, fetches: 0, fetched: [] });
  } else {
    const session = new Session(debugBase);
    await session.vm.load();
    const stopAgent = () => session.emulator.serial0_send('kill -STOP $(pidof icc-agent)\n');
    await runCase(session, 'agent-stopped', async () => {
      // No Stop pressed: the watchdog notices on its own.
      const run = session.start({ 'main.py': program('label.py') });
      await session.window(run, w => w.mapped);
      const stoppedAt = performance.now();
      stopAgent();
      const ended = await withTimeout(run.ended, 10_000, 'the end');
      const watchdogMs = performance.now() - stoppedAt;
      await session.vm.stop();
      const watchdogParkedMs = performance.now() - stoppedAt;

      // Stop pressed with the agent gone: the park does not wait on it.
      const second = session.start({ 'main.py': program('label.py') });
      await session.window(second, w => w.mapped);
      stopAgent();
      await sleep(300);
      const pressed = performance.now();
      await session.vm.stop();
      const stopParkedMs = performance.now() - pressed;
      const secondEnded = await second.ended;

      const third = session.start({ 'main.py': program('dice.py') });
      const thirdEnded = await withTimeout(third.ended, 10_000, 'the end');
      summary.agentStopped = { watchdogMs, watchdogParkedMs, stopParkedMs };
      return {
        passed: ended.reason === 'unresponsive' && watchdogMs < 3500 && secondEnded.reason === 'stopped' &&
          stopParkedMs < 750 && thirdEnded.code === 0 && session.vm.state !== 'failed',
        detail: `watchdog: ${describe(ended)} ${round(watchdogMs)} ms after SIGSTOP, parked at ${round(watchdogParkedMs)} ms; ` +
          `Stop with the agent stopped: parked ${round(stopParkedMs)} ms after stop(); the next run: ${describe(thirdEnded)}`,
      };
    });
    await session.vm.destroy();
  }
}

// A long pause in the middle of a run, with the kernel's lockup and stall detectors switched back
// on. The shipped kernel runs with them off (machine.mjs), which would make their silence prove
// nothing, so this case turns them on through the debug bundle's shell first. It drives the
// machine directly: a run through the Vm would end in a park, and a restore brings the
// detectors' settings back to the snapshot's.

if (wanted('park-detectors')) {
  let outcome;
  const parkFetched = [];
  try {
    const debugBase = opts['debug-image'];
    const { imageId } = JSON.parse(fs.readFileSync(path.join(debugBase, 'manifest.json'), 'utf8'));
    const bundle = await loadBundle(path.join(debugBase, imageId));
    const { host, line } = await openHost(bundle, {
      onEvent(event) {
        if (event.type === 'rootfs-fetched') parkFetched.push(event.path);
      },
    });
    const shell = new ConsoleShell(host.emulator);
    await restoreAndGreet(bundle, host, line);
    const detectors = await shell.run('echo 1 > /proc/sys/kernel/watchdog; echo 1 > /proc/sys/kernel/soft_watchdog; ' +
      'echo 0 > /sys/module/rcupdate/parameters/rcu_cpu_stall_suppress; ' +
      'echo "soft_watchdog=$(cat /proc/sys/kernel/soft_watchdog) stall_suppress=$(cat /sys/module/rcupdate/parameters/rcu_cpu_stall_suppress)"; dmesg | wc -l');
    const [setting, dmesgLines] = detectors.out.trim().split('\n');
    const id = line.reserveId();
    await host.emulator.create_file(`/icc/in/r${id}-main.py`, new TextEncoder().encode(program('animation.py')));
    const ticks = [];
    let text = '';
    line.onMessage = message => {
      if (message.id !== id || message.type !== 'STDOUT') return;
      text += new TextDecoder().decode(message.data);
      const lines = text.split('\n');
      text = lines.pop();
      for (const tick of lines) ticks.push({ at: performance.now(), values: tick.split(' ').map(Number) });
    };
    line.send('RUN', { entry: 'main.py', files: ['main.py'], argv: [], stdin: false, output_cap: 262_144 }, { id });
    await sleep(4000);
    const before = ticks.length;
    await host.pause();
    const pausedAt = Date.now();
    while (Date.now() - pausedAt < parkMinutes * 60_000) {
      await sleep(60_000);
      console.log(`  paused mid-run ${((Date.now() - pausedAt) / 60_000).toFixed(1)} min`);
    }
    await host.resume();
    // What the page does after a resume from hidden: HELLO sets the wall clock.
    await line.request('HELLO', { now_ms: Date.now(), tz: 'UTC', entropy: '00'.repeat(64) }, { answers: ['READY'] });
    await sleep(15_000);
    const dmesg = (await shell.run(`dmesg | tail -n +${Number(dmesgLines) + 1}`)).out;
    const alarms = dmesg.split('\n').filter(l => ALARM.test(l));
    const steps = ticks.map(t => t.values);
    const gaps = steps.slice(1).map((v, i) => v[1] - steps[i][1]);
    const after = steps.slice(before);
    const last = ticks.at(-1);
    const clockOff = last.values[2] * 1000 - wallAt(last.at);
    line.send('STOP', {}, { id });
    await host.destroy();
    outcome = {
      passed: /soft_watchdog=1 stall_suppress=0/.test(setting) && alarms.length === 0 && Math.max(...gaps) < 1 &&
        after.length > 20 && Math.abs(clockOff) < 2000,
      detail: `${setting}; paused ${parkMinutes} min mid-run: ${before} tick lines before, ${after.length} in the 15 s after; ` +
        `largest monotonic step between lines ${Math.max(...gaps).toFixed(2)} s (0.5 s apart when running); wall clock ${round(clockOff)} ms off after HELLO; ` +
        `dmesg since: ${alarms.length ? alarms.join(' | ') : 'no lockup or stall'} (${dmesg.split('\n').filter(Boolean).length} new lines)`,
    };
  } catch (error) {
    outcome = { passed: false, detail: `threw: ${error.stack ?? error}` };
  }
  record({ name: 'park-detectors', ...outcome, fetches: parkFetched.length, fetched: parkFetched });
}

// Processes that leave the program's process group, on one machine without a restore in between,
// so a later program can look for what an earlier one left behind.

if (wanted('escape')) {
  let outcome;
  const fetched = [];
  try {
    const bundle = await loadBundle(path.join(imageBase, JSON.parse(fs.readFileSync(path.join(imageBase, 'manifest.json'), 'utf8')).imageId));
    const { host, line } = await openHost(bundle, {
      onEvent(event) {
        if (event.type === 'rootfs-fetched') fetched.push(event.path);
      },
    });
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    await restoreAndGreet(bundle, host, line);
    const stdout = id => line.received.filter(m => m.id === id && m.type === 'STDOUT').map(m => decoder.decode(m.data)).join('');
    const runOnce = async (source, { argv = [], stopOn } = {}) => {
      await line.request('HELLO', { now_ms: Date.now(), tz: 'UTC', entropy: '00'.repeat(64) }, { answers: ['READY'] });
      const id = line.reserveId();
      await host.emulator.create_file(`/icc/in/r${id}-main.py`, encoder.encode(source));
      const exited = line.waitFor(m => m.id === id && m.type === 'EXIT', 60_000, 'EXIT');
      line.send('RUN', { entry: 'main.py', files: ['main.py'], argv, stdin: false, output_cap: 262_144 }, { id });
      if (stopOn) {
        const until = performance.now() + 30_000;
        while (!stdout(id).includes(stopOn) && performance.now() < until) await sleep(20);
        line.send('STOP', {}, { id });
      }
      const exit = await exited;
      return { exit: exit.body, out: stdout(id) };
    };
    const leftovers = async () => JSON.parse((await runOnce(program('leftovers.py'))).out.trim().split('\n').at(-1));
    const byItself = await runOnce(program('escape.py'));
    const afterExit = await leftovers();
    const stopped = await runOnce(program('escape.py'), { argv: ['stay'], stopOn: 'escaped' });
    const afterStop = await leftovers();
    await host.destroy();
    const clean = found => found.remaining.length === 0 && (found.heartbeat === null || found.heartbeat > 0.8);
    outcome = {
      passed: byItself.out.includes('escaped') && stopped.exit.reason === 'stopped' && clean(afterExit) && clean(afterStop),
      detail: `after a program that ended by itself (${byItself.exit.reason} ${byItself.exit.code}): ${JSON.stringify(afterExit)}; ` +
        `after one that was stopped: ${JSON.stringify(afterStop)}`,
    };
  } catch (error) {
    outcome = { passed: false, detail: `threw: ${error.stack ?? error}` };
  }
  record({ name: 'escape', ...outcome, fetches: fetched.length, fetched });
}

// The cold interpreter: a RUN that finds no warm one waiting

if (wanted('cold')) {
  let outcome;
  const fetched = [];
  try {
    const bundle = await loadBundle(path.join(imageBase, JSON.parse(fs.readFileSync(path.join(imageBase, 'manifest.json'), 'utf8')).imageId));
    const { host, line } = await openHost(bundle, {
      onEvent(event) {
        if (event.type === 'rootfs-fetched') fetched.push(event.path);
      },
    });
    const encoder = new TextEncoder();
    await restoreAndGreet(bundle, host, line);
    const runOnce = async source => {
      const id = line.reserveId();
      await host.emulator.create_file(`/icc/in/r${id}-main.py`, encoder.encode(source));
      const sent = performance.now();
      line.send('RUN', { entry: 'main.py', files: ['main.py'], argv: [], stdin: false, output_cap: 262_144 }, { id });
      const started = await line.waitFor(m => m.id === id && (m.type === 'STARTED' || m.type === 'ERROR'), 10_000, 'STARTED');
      const window = await line.waitFor(m => m.id === id && m.type === 'WINDOW' && m.body.windows.some(w => w.mapped), 60_000, 'WINDOW');
      line.send('STOP', {}, { id });
      const exit = await line.waitFor(m => m.id === id && m.type === 'EXIT', 5_000, 'EXIT');
      return { started: started.body, windowMs: window.at - sent, exit: exit.body };
    };
    const warm = await runOnce(program('label.py'));
    // No restore between the two: the warm interpreter served the first and is gone.
    await line.request('HELLO', { now_ms: Date.now(), tz: 'UTC', entropy: '00'.repeat(64) }, { answers: ['READY'] });
    const cold = await runOnce(program('label.py'));
    await host.destroy();
    outcome = {
      passed: warm.started.warm === true && cold.started.warm === false && cold.exit.reason === 'stopped',
      detail: `first run warm ${warm.started.warm}, window after ${round(warm.windowMs)} ms; a second RUN without a restore: warm ${cold.started.warm}, window after ${round(cold.windowMs)} ms`,
      windowMs: cold.windowMs,
    };
  } catch (error) {
    outcome = { passed: false, detail: `threw: ${error.stack ?? error}` };
  }
  record({ name: 'cold', ...outcome, fetches: fetched.length, fetched });
}

const passed = results.every(r => r.passed);
const report = { image: summary.load?.manifest?.imageId, stateBytes: summary.load?.manifest?.state?.bytes, summary, results };
fs.writeFileSync(opts.out ?? path.join(buildDir, opts.only ? `corpus-${opts.only.join('-')}.json` : 'corpus.json'), JSON.stringify(report, null, 1) + '\n');
console.log(`\n| case | window (ms) | drawn (ms) | rootfs fetches | memory.peak (kB) | result |\n|---|---:|---:|---:|---:|---|`);
for (const r of results) {
  console.log(`| ${r.name} | ${r.windowMs === undefined ? '' : round(r.windowMs)} | ${r.drawnMs === undefined || r.drawnMs === null ? '' : round(r.drawnMs)} | ${r.fetches} | ${r.peakKb ?? ''} | ${r.passed ? 'pass' : 'FAIL'} |`);
}
console.log(`\n${results.filter(r => r.passed).length} of ${results.length} cases passed`);
process.exit(passed ? 0 : 1);
