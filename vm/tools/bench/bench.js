// The page half of run-bench.mjs. It opens the VM the way the app will, through
// web/vm/vm_host.js and vm_screen.js, and records what the main thread and the
// screen go through. The runner drives it over CDP through window.bench.
//
// With ?app it also frames the app itself (see appFrame below).
//
// It measures by wrapping browser APIs, never the host: WebAssembly.instantiate
// for the one compile of v86.wasm, the Cache API for the bundle's reads, and
// V86.prototype.restore_state for every restore. A restore is one synchronous
// call inside v86, so the wrapper's time is the time the thread was blocked.

import { inflateState } from '../vm/vm_bundle.js';
import { createVmHost, openVm, prefetchBundle } from '../vm/vm_host.js';
import { createVmScreen } from '../vm/vm_screen.js';
import { decodeMessage, encodeMessage, FrameDecoder, MAX_PAYLOAD_TO_HOST } from '../vm/vm_protocol.js';

const now = () => performance.now();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const PROGRAM_FILES = ['label.py', 'canvas.py', 'ttk_widgets.py', 'animation.py', 'busy.py', 'entry.py'];

/** Prints loop iterations per second of guest time, for comparing emulation speed. */
const SPEED_PROGRAM = `import time
n = 0
end = time.monotonic() + 3
while time.monotonic() < end:
    for _ in range(1000):
        n += 1
print("speed", n // 3, flush=True)
`;

/**
 * What each program draws, so the bench can tell when it is on screen: the
 * window to wait for, a point inside it and the colour there. A colour that
 * starts with `!` waits for anything but that colour. `early` is the same point
 * for a window at +0+0, where every one of these lands with no window manager,
 * so the pixels can be watched from Run on rather than from the WINDOW frame.
 */
const CHECKS = {
  'label.py': { title: 'Label', at: w => [w.x + 5, w.y + 5], early: [5, 5], colour: '#3366cc' },
  'canvas.py': { title: 'Canvas', at: w => [w.x + 100, w.y + 70], early: [100, 70], colour: '#22aa44' },
  'ttk_widgets.py': { title: 'ttk', at: w => [w.x + (w.w >> 1), w.y + (w.h >> 1)], early: [20, 20], colour: '!#000000' },
  'animation.py': { title: 'Animation', at: w => [w.x + 150, w.y + 10], early: [150, 10], colour: '#ffffff' },
};

// Frames: every requestAnimationFrame timestamp since the page opened.

const frames = new Float64Array(1 << 18);
let frameCount = 0;

/** Loop iterations each frame spends, standing in for the app's own build, layout and paint. */
let frameWork = 0;
let sink = 0;
function work(iterations) {
  let x = sink;
  for (let i = 0; i < iterations; i++) x = (Math.imul(x, 1103515245) + 12345) | 0;
  sink = x;
}

function onFrame(timestamp) {
  if (frameCount < frames.length) frames[frameCount++] = timestamp;
  if (frameWork > 0) work(frameWork);
  requestAnimationFrame(onFrame);
}
requestAnimationFrame(onFrame);

const longTasks = [];
new PerformanceObserver(list => {
  for (const entry of list.getEntries()) longTasks.push({ start: entry.startTime, duration: entry.duration });
}).observe({ type: 'longtask', buffered: true });

const longFrames = [];
try {
  new PerformanceObserver(list => {
    for (const entry of list.getEntries()) {
      const top = [...(entry.scripts ?? [])].sort((a, b) => b.duration - a.duration)[0];
      longFrames.push({
        start: entry.startTime,
        duration: entry.duration,
        blocking: entry.blockingDuration,
        script: top ? `${top.invoker} ${top.sourceFunctionName ?? ''} (${Math.round(top.duration)} ms)`.trim() : null,
      });
    }
  }).observe({ type: 'long-animation-frame', buffered: true });
} catch {
  // Long animation frames are Chrome 123 and later; long tasks cover the rest.
}

performance.setResourceTimingBufferSize(20_000);

// Instrumentation

const compiles = [];
let jitModules = 0;
const instantiate = WebAssembly.instantiate;
WebAssembly.instantiate = function (source, imports) {
  const bytes = source?.byteLength;
  // v86's JIT instantiates a small module per compiled block of guest code.
  if (!(bytes > 1_000_000)) {
    jitModules++;
    return instantiate.call(WebAssembly, source, imports);
  }
  const started = now();
  return instantiate.call(WebAssembly, source, imports).then(result => {
    compiles.push({ started, ms: now() - started, bytes });
    return result;
  });
};

const cacheOps = [];
const match = Cache.prototype.match;
Cache.prototype.match = async function (request, options) {
  const started = now();
  const response = await match.call(this, request, options);
  const entry = { op: 'match', url: typeof request === 'string' ? request : request.url, started, ms: now() - started, hit: Boolean(response) };
  cacheOps.push(entry);
  if (response) {
    const read = response.arrayBuffer.bind(response);
    response.arrayBuffer = async () => {
      const readStarted = now();
      const body = await read();
      entry.bodyMs = now() - readStarted;
      entry.bytes = body.byteLength;
      return body;
    };
  }
  return response;
};
const put = Cache.prototype.put;
Cache.prototype.put = async function (request, response) {
  const started = now();
  const entry = { op: 'put', url: typeof request === 'string' ? request : request.url, started };
  cacheOps.push(entry);
  try {
    return await put.call(this, request, response);
  } finally {
    entry.ms = now() - started;
  }
};

// How v86 hands the thread back between its ~1 ms slices. The host replaces v86's own, a round
// trip through a blob worker, with a MessageChannel (vm_machine.js, yieldThroughChannel).
// ?yield=v86 puts v86's worker back, to compare the two; ?yield=blocking tries scheduler.postTask
// at user-blocking priority, which starves the rest of the thread, the runner's CDP calls included.
const yieldMode = new URLSearchParams(location.search).get('yield');

function patchYield(inner) {
  if (!yieldMode || yieldMode === 'channel' || inner.iccYield) return;
  inner.iccYield = yieldMode;
  if (Object.hasOwn(inner, 'yield')) {
    inner.unregister_yield();
    delete inner.yield;
    delete inner.register_yield;
    delete inner.unregister_yield;
  }
  if (yieldMode === 'v86') {
    inner.register_yield();
  } else if (yieldMode === 'blocking') {
    inner.yield = (t, tick) => {
      globalThis.scheduler.postTask(() => inner.yield_callback(tick), { priority: 'user-blocking', delay: Math.max(0, t) });
    };
  } else {
    throw new Error(`unknown yield mode ${yieldMode}`);
  }
}

function yieldOf(inner) {
  if (!inner) return null;
  return inner.iccYield ?? (Object.hasOwn(inner, 'yield') ? 'channel' : 'v86');
}

const restores = [];
const patchedLibs = new Set();
async function patchV86(libUrl) {
  if (patchedLibs.has(libUrl)) return;
  patchedLibs.add(libUrl);
  const { V86 } = await import(libUrl);
  const restore = V86.prototype.restore_state;
  V86.prototype.restore_state = function (state) {
    patchYield(this.v86);
    const started = now();
    const result = restore.call(this, state);
    const entry = { started, syncMs: now() - started, bytes: state.byteLength };
    restores.push(entry);
    return result.then(value => {
      entry.ms = now() - started;
      return value;
    });
  };
}

// The VM and what it reports

const screen = createVmScreen({ width: 800, height: 600 });
document.getElementById('display').appendChild(screen.viewElement(1));
const status = document.getElementById('status');

let vm = null;
const events = [];
const outputs = new Map();
/** Every stdout chunk with when it arrived, for checks that compare the guest's clock with the page's. */
const outputLog = [];
const waiters = new Set();

function onEvent(event) {
  event.at = now();
  if (event.type === 'output') {
    const output = outputs.get(event.run) ?? { stdout: '', stderr: '' };
    output[event.stream] += event.text;
    outputs.set(event.run, output);
    if (event.stream === 'stdout' && outputLog.length < 20_000) {
      outputLog.push({ run: event.run, at: event.at, wall: Date.now(), text: event.text });
    }
    return;
  }
  events.push(event);
  if (event.type !== 'rootfs-fetched' && event.type !== 'progress') status.textContent = `${event.type} ${event.reason ?? ''}`;
  for (const waiter of [...waiters]) {
    if (!waiter.test(event)) continue;
    waiters.delete(waiter);
    clearTimeout(waiter.timer);
    waiter.resolve(event);
  }
}

function waitFor(test, timeoutMs, what) {
  const found = events.find(test);
  if (found) return Promise.resolve(found);
  return new Promise((resolve, reject) => {
    const waiter = { test, resolve };
    waiter.timer = setTimeout(() => {
      waiters.delete(waiter);
      reject(new Error(`no ${what} within ${timeoutMs} ms`));
    }, timeoutMs);
    waiters.add(waiter);
  });
}

// With ?app the page also holds the app itself, served from build/web/ at the server's root, in a
// same-origin frame. That shares this page's renderer process, so the memory the page reports is
// the app's and the VM's together.
const appFrame = new URLSearchParams(location.search).has('app') ? document.createElement('iframe') : null;
if (appFrame) {
  appFrame.src = '/';
  appFrame.style.cssText = 'position: fixed; inset: 0; width: 100vw; height: 100vh; border: 0; z-index: 0;';
  document.getElementById('display').style.cssText += 'position: relative; z-index: 1;';
  document.body.appendChild(appFrame);
}

const programs = {};
const loaded = Promise.all(PROGRAM_FILES.map(async name => {
  programs[name] = await (await fetch(`../corpus/${name}`)).text();
})).then(() => {
  programs['speed.py'] = SPEED_PROGRAM;
  status.textContent = 'Ready to measure.';
});

// Reading the screen

function hex(r, g, b) {
  return `#${[r, g, b].map(v => v.toString(16).padStart(2, '0')).join('')}`;
}

/** The guest's framebuffer: what v86 would draw next. */
function framebufferPixel(x, y) {
  const vga = vm.emulator.v86.cpu.devices.vga;
  const at = (vga.svga_offset + y * vga.svga_width + x) * 4;
  return hex(vga.svga_memory[at + 2], vga.svga_memory[at + 1], vga.svga_memory[at]);
}

/** The page's canvas: what v86 has drawn. */
function canvasPixel(x, y) {
  const canvas = screen.container.querySelector('canvas');
  const data = canvas.getContext('2d').getImageData(x, y, 1, 1).data;
  return hex(data[0], data[1], data[2]);
}

function matches(pixel, colour) {
  return colour.startsWith('!') ? pixel !== colour.slice(1) : pixel === colour;
}

// Statistics

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  return sorted[Math.min(sorted.length - 1, Math.ceil(p / 100 * sorted.length) - 1)];
}

/** rAF deltas between `from` and `to`, counting the frames either side so a
 *  block that straddles an edge still shows. */
function frameStats(from, to) {
  let first = 0;
  while (first < frameCount && frames[first] < from) first++;
  first = Math.max(0, first - 1);
  let last = first;
  while (last < frameCount && frames[last] <= to) last++;
  last = Math.min(frameCount - 1, last);
  const deltas = [];
  for (let i = first + 1; i <= last; i++) deltas.push(frames[i] - frames[i - 1]);
  const sorted = [...deltas].sort((a, b) => a - b);
  const span = frames[last] - frames[first];
  return {
    frames: deltas.length,
    fps: span > 0 ? deltas.length / (span / 1000) : null,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
    max: sorted.at(-1) ?? null,
    over50: deltas.filter(d => d > 50).length,
    over100: deltas.filter(d => d > 100).length,
  };
}

function tasksBetween(list, from, to) {
  return list.filter(entry => entry.start + entry.duration >= from && entry.start <= to);
}

// Runs

function startRun(name) {
  const t0 = now();
  const handle = vm.run({ files: { 'main.py': programs[name] }, entry: 'main.py' });
  return { name, id: handle.id, ended: handle.ended, t0 };
}

/** Waits for `run`'s window and for its colour in the framebuffer and on the canvas. */
/**
 * Watches `check.early` from Run on, independently of WINDOW frames: when the
 * program's colour reached the framebuffer and the canvas. Stops at `until()`.
 */
async function watchEarly(check, t0, until) {
  const [x, y] = check.early;
  let drawnAt = null;
  let paintedAt = null;
  while ((drawnAt === null || paintedAt === null) && !until()) {
    // Before the machine exists, and while it restores, there is nothing to read.
    if (vm?.emulator?.v86 && vm.state === 'running') {
      if (drawnAt === null && matches(framebufferPixel(x, y), check.colour)) drawnAt = now();
      if (paintedAt === null && matches(canvasPixel(x, y), check.colour)) paintedAt = now();
    }
    await sleep(4);
  }
  return { drawnMs: drawnAt === null ? null : drawnAt - t0, paintedMs: paintedAt === null ? null : paintedAt - t0 };
}

async function shown(run, timeoutMs) {
  const check = CHECKS[run.name];
  // A window that is not at +0+0 after all never matches; give up on it shortly
  // after the WINDOW-based check has seen the program's colour.
  let giveUpAt = Infinity;
  const early = watchEarly(check, run.t0, () => now() > giveUpAt || now() - run.t0 > timeoutMs);
  try {
    const byWindow = await shownByWindow(run, check, timeoutMs);
    giveUpAt = now() + 250;
    return { ...byWindow, early: await early };
  } finally {
    giveUpAt = 0;
  }
}

async function shownByWindow(run, check, timeoutMs) {
  const started = await waitFor(e => e.type === 'started' && e.run === run.id, timeoutMs, 'STARTED');
  const windowEvent = await waitFor(
    e => e.type === 'window' && e.run === run.id && e.windows.some(w => w.mapped && w.title === check.title),
    timeoutMs, 'the window');
  const win = windowEvent.windows.find(w => w.mapped && w.title === check.title);
  const [x, y] = check.at(win);
  let drawnAt = null;
  let paintedAt = null;
  const until = now() + timeoutMs;
  while ((drawnAt === null || paintedAt === null) && now() < until) {
    if (drawnAt === null && matches(framebufferPixel(x, y), check.colour)) drawnAt = now();
    if (paintedAt === null && matches(canvasPixel(x, y), check.colour)) paintedAt = now();
    await sleep(4);
  }
  return {
    startedMs: started.at - run.t0,
    warm: started.warm,
    windowMs: windowEvent.at - run.t0,
    drawnMs: drawnAt === null ? null : drawnAt - run.t0,
    paintedMs: paintedAt === null ? null : paintedAt - run.t0,
    window: { title: win.title, x: win.x, y: win.y, w: win.w, h: win.h },
    fetches: events.filter(e => e.type === 'rootfs-fetched' && e.at >= run.t0).length,
  };
}

function failures(from = 0) {
  return events.filter(e => e.at >= from && (
    e.type === 'failed' ||
    (e.type === 'ended' && !['stopped', 'exit', 'closed'].includes(e.reason)) ||
    (e.type === 'log' && (e.level === 'warn' || e.level === 'error')) ||
    (e.type === 'stop-answered' && e.ms === null) ||
    e.type === 'fetch-failed'
  )).map(({ at, ...rest }) => ({ at: Math.round(at), ...rest }));
}

// Downloads, for the runner's download section

/** The download started last: its reports as they came, and how it ended. */
let download = null;

/**
 * What a download's reports say about the rate and the time left: when the first
 * estimate came, the rate at the end, and how far each estimate's finishing time
 * was from the real one, in seconds, over the estimates made while at least 5 %
 * of the download was still to come.
 */
function summarizeDownload(reports, endAt) {
  const withRate = reports.filter(report => report.rate !== null);
  const errors = reports
    .filter(report => report.remainingMs !== null && report.loaded <= report.total * 0.95)
    .map(report => ({ at: report.at, error: (report.at + report.remainingMs - endAt) / 1000 }));
  const abs = errors.map(entry => Math.abs(entry.error)).sort((a, b) => a - b);
  const quantile = q => (abs.length ? abs[Math.min(abs.length - 1, Math.floor(q * abs.length))] : null);
  const near = fraction => errors.find(entry => {
    const report = reports.find(r => r.at === entry.at);
    return report.loaded >= report.total * fraction;
  })?.error ?? null;
  return {
    reports: reports.length,
    firstRateMs: withRate[0]?.at ?? null,
    rateAtEnd: withRate.at(-1)?.rate ?? null,
    etaErrorS: { median: quantile(0.5), p90: quantile(0.9), at25: near(0.25), at50: near(0.5), at75: near(0.75) },
    stalledReports: reports.filter(report => report.stalled).length,
    keeps: reports.at(-1)?.keeps ?? null,
  };
}

// Driven from the runner

let nudging = null;

window.bench = {

  loaded,

  now,

  info() {
    return {
      userAgent: navigator.userAgent,
      crossOriginIsolated: globalThis.crossOriginIsolated,
      devicePixelRatio: devicePixelRatio,
      hardwareConcurrency: navigator.hardwareConcurrency,
      deviceMemory: navigator.deviceMemory ?? null,
      visibility: document.visibilityState,
      navigation: performance.getEntriesByType('navigation')[0]?.toJSON() ?? null,
      screenScale: screen.scale,
      screenBox: [screen.container.offsetWidth, screen.container.offsetHeight],
    };
  },

  /**
   * Opens the VM and presses Run at once, as a student who opens the screen and
   * runs the starter program. Resolves once the program is on the canvas; the
   * program is left running.
   */
  async start({ baseUrl, libUrl, program = 'label.py', timeoutMs = 180_000 }) {
    await loaded;
    const t0 = now();
    vm = openVm({ baseUrl, onEvent, screen });
    // The restore wrapper has to be in place before the first restore, and must
    // not fetch the library ahead of the host: by the first progress event the
    // host has asked for it.
    const patched = waitFor(e => e.type === 'progress', timeoutMs, 'progress').then(() => patchV86(libUrl));
    const loading = vm.load();
    const run = startRun(program);
    const ready = await loading;
    await patched.catch(() => {});
    if (ready.type !== 'ready') return { t0, ready, failures: failures() };
    let result;
    try {
      result = await shown(run, timeoutMs);
    } catch (error) {
      result = { error: error.message };
    }
    const progress = events.filter(e => e.type === 'progress');
    return {
      t0,
      readyMs: ready.at - t0,
      ready: { python: ready.python, tk: ready.tk, imageId: ready.imageId },
      bundleReadMs: progress.length ? progress.at(-1).at - t0 : null,
      compile: compiles[0] ?? null,
      restoresDuringLoad: restores.filter(r => r.started < ready.at),
      loadFrames: frameStats(t0, ready.at),
      loadLongTasks: tasksBetween(longTasks, t0, ready.at).map(task => Math.round(task.duration)),
      cacheOps: cacheOps.map(({ url, ...rest }) => ({ url: url.replace(/^.*\/vm\/image\//, ''), ...rest })),
      run: { name: program, ...result },
      failures: failures(),
    };
  },

  /**
   * Runs `name` on the parked machine; resolves once it is on the canvas. With
   * `nudge`, a lone 0x00 goes to the agent every 50 ms until then: an empty
   * frame, which the agent ignores, but which wakes its poll(2).
   */
  async runProgram(name, { timeoutMs = 60_000, nudge = false } = {}) {
    const run = startRun(name);
    const nudging = nudge ? setInterval(() => vm.emulator.serial_send_bytes(1, Uint8Array.of(0)), 50) : null;
    try {
      return { name, id: run.id, ...await shown(run, timeoutMs), failures: failures(run.t0) };
    } catch (error) {
      return { name, id: run.id, error: error.message, failures: failures(run.t0) };
    } finally {
      clearInterval(nudging);
    }
  },

  /**
   * Opens the VM on a bundle this page assembles, from the state at `stateUrl`
   * (raw or zstd), rather than from web/vm/image/ through the Cache API.
   */
  async startWithBundle({ baseUrl, libUrl, wasmUrl, stateUrl, rootfsUrl, manifest, program = 'label.py', timeoutMs = 180_000 }) {
    await loaded;
    await patchV86(libUrl);
    const [{ V86 }, wasm, state] = await Promise.all([
      import(libUrl),
      fetch(wasmUrl).then(response => response.arrayBuffer()),
      fetch(stateUrl).then(response => response.arrayBuffer()),
    ]);
    const t0 = now();
    vm = openVm({ baseUrl, bundle: { manifest, V86, wasm: new Uint8Array(wasm), state, rootfsUrl }, onEvent, screen });
    const loading = vm.load();
    const run = startRun(program);
    const ready = await loading;
    if (ready.type !== 'ready') return { t0, ready, failures: failures() };
    const result = await shown(run, timeoutMs).catch(error => ({ error: error.message }));
    return {
      readyMs: ready.at - t0,
      stateBytes: state.byteLength,
      restoresDuringLoad: restores.filter(r => r.started >= t0 && r.started < ready.at),
      run: { name: program, ...result },
      failures: failures(),
    };
  },

  /** Loop iterations that take `ms` on this page as it is throttled now. */
  calibrate(ms) {
    let iterations = 100_000;
    for (;;) {
      const started = now();
      work(iterations);
      const took = now() - started;
      if (took >= 20) return Math.round(iterations * ms / took);
      iterations *= 2;
    }
  },

  setFrameWork(iterations) {
    frameWork = iterations;
  },

  /** Starts `name` without waiting for a window, and resolves on STARTED. */
  async startProgram(name, { timeoutMs = 60_000 } = {}) {
    const run = startRun(name);
    try {
      const started = await waitFor(e => e.type === 'started' && e.run === run.id, timeoutMs, 'STARTED');
      return { name, id: run.id, t0: run.t0, startedMs: started.at - run.t0 };
    } catch (error) {
      return { name, id: run.id, error: error.message, failures: failures(run.t0) };
    }
  },

  /** Runs `name` to its end and resolves with the `ended` event and its output. */
  async runToEnd(name, { timeoutMs = 120_000 } = {}) {
    const run = startRun(name);
    const ended = await Promise.race([run.ended, sleep(timeoutMs).then(() => null)]);
    return { name, id: run.id, ms: now() - run.t0, ended, output: outputs.get(run.id) ?? null, failures: failures(run.t0) };
  },

  /** Frame times, long tasks and the run's output over the next `ms`. */
  async hold(ms, { run = null } = {}) {
    const from = now();
    await sleep(ms);
    const to = now();
    await sleep(100);
    const text = run === null ? '' : (outputs.get(run)?.stdout ?? '');
    return {
      from,
      to,
      frames: frameStats(from, to),
      longTasks: tasksBetween(longTasks, from, to),
      longFrames: tasksBetween(longFrames, from, to),
      jitModules,
      stdout: text.slice(-4000),
      failures: failures(from),
    };
  },

  /** Stop: ends the run and resolves once the machine is parked again. */
  async stop() {
    const from = now();
    await vm.stop();
    const parkedAt = now();
    // Long tasks are reported after they end, from a task of their own.
    await sleep(300);
    const restore = restores.filter(r => r.started >= from).at(-1) ?? null;
    return {
      parkedMs: parkedAt - from,
      restore,
      frames: frameStats(from, parkedAt + 50),
      longTasks: tasksBetween(longTasks, from, parkedAt + 50),
      longFrames: tasksBetween(longFrames, from, parkedAt + 50),
      stopAnswered: events.find(e => e.type === 'stop-answered' && e.at >= from)?.ms ?? null,
      failures: failures(from),
    };
  },

  failures,

  jitModules: () => jitModules,

  output: run => outputs.get(run) ?? null,

  state: () => vm?.state ?? null,

  stats: () => vm?.stats ?? null,

  resources() {
    return performance.getEntriesByType('resource').map(entry => ({
      name: entry.name.replace(/^.*?\/\/[^/]+/, ''),
      start: entry.startTime,
      duration: entry.duration,
      transferSize: entry.transferSize,
      decodedBodySize: entry.decodedBodySize,
    }));
  },

  async memory() {
    const result = {
      at: now(),
      visibility: document.visibilityState,
      vm: vm?.stats?.memory ?? null,
      jsHeap: performance.memory
        ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize }
        : null,
    };
    try {
      const measured = await performance.measureUserAgentSpecificMemory();
      const byType = {};
      for (const entry of measured.breakdown) {
        const key = entry.types.join('+') || 'unattributed';
        byType[key] = (byType[key] ?? 0) + entry.bytes;
      }
      // Keyed by where the memory belongs: this page, a worker, or the ?app frame.
      const byScope = {};
      for (const entry of measured.breakdown) {
        const key = entry.attribution
          .map(a => `${a.scope} ${a.container ? 'in a frame ' : ''}${new URL(a.url, location.href).pathname}`)
          .join(' + ') || 'unattributed';
        byScope[key] = (byScope[key] ?? 0) + entry.bytes;
      }
      result.userAgentSpecific = { bytes: measured.bytes, byType, byScope };
    } catch (error) {
      result.userAgentSpecificError = String(error);
    }
    return result;
  },

  /** Reads each URL from the bundle's Cache Storage, `repeats` times: every piece
   *  of a file kept in pieces (vm_cache.js), as a load does. */
  async cacheRead({ urls, repeats = 5 }) {
    const cache = await caches.open('icc-vm');
    const out = {};
    for (const url of urls) {
      out[url] = [];
      for (let i = 0; i < repeats; i++) {
        const started = now();
        const keys = await cache.keys(url, { ignoreSearch: true });
        if (keys.length === 0) {
          out[url].push(null);
          continue;
        }
        let bytes = 0;
        for (const key of keys) bytes += (await (await match.call(cache, key)).arrayBuffer()).byteLength;
        out[url].push({ ms: now() - started, bytes, pieces: keys.length });
      }
    }
    return out;
  },

  /**
   * Puts `url` into a Cache Storage cache of its own, reads it back `repeats`
   * times and deletes the cache: what a park would pay to keep a raw state on
   * disk instead of in memory.
   */
  async cacheRoundTrip({ url, repeats = 5 }) {
    const name = 'icc-vm-bench';
    await caches.delete(name);
    const cache = await caches.open(name);
    const fetched = await fetch(url);
    const putStarted = now();
    await put.call(cache, url, fetched);
    const putMs = now() - putStarted;
    const reads = [];
    for (let i = 0; i < repeats; i++) {
      const from = now();
      const response = await match.call(cache, url);
      const body = await response.arrayBuffer();
      const to = now();
      await sleep(200);
      reads.push({ ms: to - from, bytes: body.byteLength, frames: frameStats(from, to), longTasks: tasksBetween(longTasks, from, to).map(t => Math.round(t.duration)) });
    }
    await caches.delete(name);
    return { putMs, reads };
  },

  /** Compiles v86.wasm on its own, from bytes and streamed from the HTTP cache. */
  async compile({ wasmUrl, repeats = 5 }) {
    const bytes = new Uint8Array(await (await fetch(wasmUrl)).arrayBuffer());
    const fromBytes = [];
    for (let i = 0; i < repeats; i++) {
      const started = now();
      await WebAssembly.compile(bytes);
      fromBytes.push(now() - started);
    }
    const streamed = [];
    for (let i = 0; i < repeats; i++) {
      const started = now();
      await WebAssembly.compileStreaming(fetch(wasmUrl));
      streamed.push(now() - started);
    }
    return { bytes: bytes.byteLength, fromBytes, streamed };
  },

  /**
   * Restores the state over and over with createVmHost, which a page with an
   * openVm() MUST NOT do, since there is one machine per page. Compares the zstd
   * state against a raw one, and a decompression on the main thread against one
   * in v86's own zstd worker.
   */
  async restoreExperiment({ libUrl, wasmUrl, stateUrl, rootfsUrl, manifest, repeats = 5 }) {
    const { V86 } = await import(libUrl);
    await patchV86(libUrl);
    const wasm = new Uint8Array(await (await fetch(wasmUrl)).arrayBuffer());
    const zstd = await (await fetch(stateUrl)).arrayBuffer();
    const host = await createVmHost({
      V86,
      wasm: wasm.slice(),
      memoryMiB: manifest.memoryMiB,
      vgaMiB: manifest.vgaMiB,
      uart1: manifest.uart1,
      rootfsUrl,
      screen: screen.container,
      trackVisibility: false,
    });
    const rawBytes = manifest.state.rawBytes;
    const out = { zstd: [], mainDecompress: [], raw: [], workerDecompress: [], hostInflate: [], ready: {} };

    const measure = async (list, work) => {
      const from = now();
      const value = await work();
      const to = now();
      await sleep(300);
      list.push({
        ...value,
        wallMs: to - from,
        frames: frameStats(from, to + 50),
        longTasks: tasksBetween(longTasks, from, to + 50).map(t => Math.round(t.duration)),
      });
    };

    for (let i = 0; i < repeats; i++) await measure(out.zstd, () => host.restoreSnapshot(zstd));
    out.ready.zstd = await greet(host);

    let raw = null;
    for (let i = 0; i < repeats; i++) {
      await measure(out.mainDecompress, async () => {
        const started = now();
        raw = host.emulator.zstd_decompress(rawBytes, new Uint8Array(zstd));
        return { decompressMs: now() - started };
      });
    }
    for (let i = 0; i < repeats; i++) await measure(out.raw, () => host.restoreSnapshot(raw));
    out.ready.raw = await greet(host);

    // v86 starts its zstd worker from the wasm it loaded itself; this host
    // handed it bytes instead, so it gets a copy of its own.
    host.emulator.wasm_source = wasm.slice().buffer;
    for (let i = 0; i < repeats; i++) {
      await measure(out.workerDecompress, async () => {
        const started = now();
        const copy = new Uint8Array(zstd.slice(0));
        const decompressed = await host.emulator.zstd_decompress_worker(rawBytes, copy);
        const decompressMs = now() - started;
        const restored = await host.restoreSnapshot(decompressed);
        return { decompressMs, restoreMs: restored.ms, restoreSyncMs: restored.syncMs };
      });
    }
    out.ready.worker = await greet(host);

    // What the host ships: its own worker, started and ended per decompression.
    for (let i = 0; i < repeats; i++) {
      await measure(out.hostInflate, async () => {
        const inflated = await inflateState(zstd.slice(0), wasm, rawBytes);
        const restored = await host.restoreSnapshot(inflated.state);
        return { where: inflated.where, decompressMs: inflated.ms, restoreMs: restored.ms, restoreSyncMs: restored.syncMs };
      });
    }
    out.ready.host = await greet(host);
    out.memory = host.memoryUsage();
    out.memoryByScope = await memoryByScope();
    await host.destroy();
    return out;
  },

  /**
   * Starts prefetchBundle() without waiting for it: the runner polls
   * downloadStatus() and may take the network away meanwhile. `download` is
   * vm_download.js's knobs, `{ranges: false}` for one plain GET.
   */
  startDownload({ baseUrl, download: knobs = {} }) {
    const started = now();
    const reports = [];
    const state = { started, reports, result: null, error: null, endAt: null };
    state.promise = prefetchBundle({
      baseUrl,
      download: knobs,
      onProgress: progress => {
        reports.push({ at: now() - started, ...progress });
        if (progress.loaded >= progress.total && state.endAt === null) state.endAt = now() - started;
      },
    }).then(result => {
      state.result = result;
    }, error => {
      state.error = { message: String(error?.message ?? error), reason: error?.reason ?? null };
    }).finally(() => {
      state.ms = now() - started;
    });
    download = state;
    return true;
  },

  downloadStatus() {
    const last = download?.reports.at(-1) ?? null;
    return last ? { at: last.at, loaded: last.loaded, total: last.total, stalled: last.stalled } : null;
  },

  async downloadDone() {
    await download.promise;
    const { reports, result, error, ms, endAt } = download;
    return { ms, result, error, ...summarizeDownload(reports, endAt ?? ms) };
  },

  /**
   * A cold load to ready through openVm(), with vm_download.js's knobs, and when
   * each phase began. The machine is destroyed afterwards.
   */
  async coldLoad({ baseUrl, download: knobs = {} }) {
    await loaded;
    const started = now();
    const reports = [];
    const phases = {};
    vm = openVm({
      baseUrl,
      screen,
      download: knobs,
      onEvent: event => {
        if (event.type === 'progress') {
          const at = now() - started;
          phases[event.phase] ??= at;
          if (event.phase === 'download') reports.push({ at, ...event });
        }
        onEvent(event);
      },
    });
    const ready = await vm.load();
    const readyMs = now() - started;
    const downloadEnd = reports.find(report => report.loaded >= report.total)?.at ?? null;
    await vm.destroy();
    vm = null;
    return {
      ready: ready.type,
      readyMs,
      downloadMs: downloadEnd,
      phases,
      ...summarizeDownload(reports, downloadEnd ?? readyMs),
    };
  },

  /** Removes the page's Cache Storage and nothing else, for a cold load in a kept profile. */
  async clearCache() {
    await caches.delete('icc-vm');
  },

  /**
   * Waits for the app in the ?app frame to draw, then `settleMs` more for its
   * initialization screen to finish, and says where it ended up.
   */
  async appSettled({ timeoutMs = 60_000, settleMs = 10_000 } = {}) {
    if (!appFrame) return { error: 'the page was opened without ?app' };
    const started = now();
    while (!appFrame.contentDocument?.querySelector('flutter-view')) {
      if (now() - started > timeoutMs) return { error: `no flutter-view within ${timeoutMs} ms` };
      await sleep(50);
    }
    const drawnMs = now() - started;
    await sleep(settleMs);
    return { drawnMs, path: appFrame.contentWindow.location.pathname, isolated: appFrame.contentWindow.crossOriginIsolated };
  },

  /**
   * Starts entry.py with the keyboard and mouse on, and resolves once both of its
   * windows are mapped and it has printed where its first Entry is. The runner
   * then clicks and types through CDP, which Chrome delivers as real input events.
   */
  async inputStart({ timeoutMs = 60_000 } = {}) {
    screen.setKeyboardEnabled(true);
    screen.setMouseEnabled(true);
    const run = startRun('entry.py');
    try {
      const windowEvent = await waitFor(
        e => e.type === 'window' && e.run === run.id && ['Input', 'Second window'].every(t => e.windows.some(w => w.mapped && w.title === t)),
        timeoutMs, 'both windows');
      let entry = null;
      while (!entry && now() - run.t0 < timeoutMs) {
        const found = /\{"name": \[([-\d, ]+)\]\}/.exec(outputs.get(run.id)?.stdout ?? '');
        if (found) entry = found[1].split(',').map(Number);
        else await sleep(20);
      }
      const rect = screen.container.getBoundingClientRect();
      return {
        id: run.id,
        windowMs: windowEvent.at - run.t0,
        windows: windowEvent.windows.map(({ title, x, y, w, h }) => ({ title, x, y, w, h })),
        entry,
        box: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
        scale: screen.scale,
      };
    } catch (error) {
      return { id: run.id, error: error.message, failures: failures(run.t0) };
    }
  },

  /** The line entry.py prints on Return, once it has. */
  async inputResult(id, { timeoutMs = 20_000 } = {}) {
    const started = now();
    while (now() - started < timeoutMs) {
      const found = /\{"name": "[^\n]*\}/.exec(outputs.get(id)?.stdout ?? '');
      if (found) {
        screen.setKeyboardEnabled(false);
        screen.setMouseEnabled(false);
        return { ms: now() - started, line: JSON.parse(found[0]) };
      }
      await sleep(20);
    }
    return { error: `no line within ${timeoutMs} ms`, stdout: outputs.get(id)?.stdout ?? '' };
  },

  /** Adds a program for runProgram and the rest to run by `name`, for probing by hand. */
  define(name, source) {
    programs[name] = source;
  },

  /** Wakes the agent's poll(2) every 50 ms with an empty frame until called with false. */
  nudge(enabled) {
    clearInterval(nudging);
    nudging = enabled ? setInterval(() => vm.emulator.serial_send_bytes(1, Uint8Array.of(0)), 50) : null;
  },

  /** Lets the keyboard and the mouse through to the guest, or stops them. */
  setInput(enabled) {
    screen.setKeyboardEnabled(enabled);
    screen.setMouseEnabled(enabled);
  },

  /** What the page and the machine are doing now, readable while the page is hidden. */
  probe() {
    return {
      at: now(),
      wall: Date.now(),
      visibility: document.visibilityState,
      emulatorRunning: vm?.emulator?.is_running?.() ?? null,
      state: vm?.state ?? null,
      yield: yieldOf(vm?.emulator?.v86),
    };
  },

  /** The stdout chunks of run `id` that arrived from `from` on, with their arrival times. */
  outputSince(id, from = 0) {
    return outputLog.filter(entry => entry.run === id && entry.at >= from);
  },

  /** Every event from `from` on, output aside, without the bulky window lists. */
  eventsSince(from = 0) {
    return events.filter(e => e.at >= from && e.type !== 'rootfs-fetched')
      .map(({ windows, ...rest }) => (windows ? { ...rest, windows: windows.length } : rest));
  },

};

/** The page's memory as measureUserAgentSpecificMemory attributes it: the page, and each worker. */
async function memoryByScope() {
  try {
    const measured = await performance.measureUserAgentSpecificMemory();
    const byScope = {};
    for (const entry of measured.breakdown) {
      const scopes = entry.attribution.map(a => a.scope).join('+') || 'unattributed';
      byScope[scopes] = (byScope[scopes] ?? 0) + entry.bytes;
    }
    return { bytes: measured.bytes, byScope };
  } catch (error) {
    return { error: String(error) };
  }
}

/** Resumes a restored machine and times HELLO to READY, to show it runs. */
async function greet(host) {
  const emulator = host.emulator;
  const decoder = new FrameDecoder({ maxPayload: MAX_PAYLOAD_TO_HOST });
  let listener;
  const ready = new Promise(resolve => {
    listener = byte => {
      for (const event of decoder.push(Uint8Array.of(byte))) {
        if (!event.frame) continue;
        const decoded = decodeMessage(event.frame, { from: 'agent' });
        if (decoded.message?.type === 'READY' && decoded.message.id === 7) resolve(decoded.message.body);
      }
    };
    emulator.add_listener('serial1-output-byte', listener);
  });
  await host.resume();
  const started = now();
  const entropy = Array.from(crypto.getRandomValues(new Uint8Array(64)), b => b.toString(16).padStart(2, '0')).join('');
  emulator.serial_send_bytes(1, encodeMessage({ type: 'HELLO', id: 7, body: { now_ms: Date.now(), tz: 'UTC', entropy } }));
  const body = await Promise.race([ready, sleep(20_000).then(() => null)]);
  const ms = now() - started;
  emulator.remove_listener('serial1-output-byte', listener);
  await host.pause();
  return body ? { ms, warm: body.warm, python: body.python } : { ms: null };
}
