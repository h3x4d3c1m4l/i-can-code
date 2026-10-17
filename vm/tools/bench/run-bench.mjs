// Measures the VM in headless Chrome: the bench page (bench.js) opens web/vm/image/ through
// web/vm/vm_host.js and vm_screen.js the way the app will, and this drives it over CDP, with
// Chrome's CPU and network throttling standing in for a school Chromebook and a classroom line.
// Writes vm/build/bench/bench.json.
//
// Usage: node run-bench.mjs [--only SECTION]... [--repeats 3] [--rates 1,4,6]
//                           [--sweep 8,10,12,16,20,30,40] [--frame-work-ms 6] [--page-query QUERY]
//                           [--chrome PATH] [--out FILE]
//
// Sections, in the order they run: node (the same programs in Node, for comparison), matrix
// (cold and warm loads and three programs), download (the bundle in Range pieces against one plain
// GET at 20 and 50 Mbit/s, and a download interrupted by a dropped connection and by a reload),
// micro (Cache Storage reads and the wasm compile),
// restore (the park's restore, zstd against raw and a worker), park (the host's own park, as the
// app gets it, and the state's decompression during the load), frames (the main thread during
// busy and animated programs), frame-load (the same with a page that spends time on every frame,
// as the app does), window-delay (whether a WINDOW waits for the next PING), memory (one tab and
// two), app (the app from build/web/ alone and beside the VM), raw-memory (the tab with a raw
// state instead of the zstd one), raw-cache (reading a raw state back from Cache Storage), input
// (real clicks and keys into Tk), hidden (a run in a tab sent to the background) and sweep
// (heavier throttling, to find where it breaks).
//
// Every browser gets a profile of its own under vm/build/bench/profiles/, deleted afterwards.
// A cold load is a fresh profile; a warm one relaunches Chrome on the profile a cold load filled.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

import puppeteer from 'puppeteer-core';

import { startServer } from './serve.mjs';

const benchDir = path.dirname(new URL(import.meta.url).pathname);
const repoDir = path.resolve(benchDir, '../../..');
const outDir = path.join(repoDir, 'vm/build/bench');
const profilesDir = path.join(outDir, 'profiles');

const SECTIONS = ['node', 'matrix', 'download', 'micro', 'restore', 'park', 'frames', 'frame-load', 'window-delay', 'memory', 'app', 'raw-memory', 'raw-cache', 'input', 'hidden', 'sweep'];

const { values: opts } = parseArgs({
  options: {
    only: { type: 'string', multiple: true },
    repeats: { type: 'string', default: '3' },
    rates: { type: 'string', default: '1,4,6' },
    sweep: { type: 'string', default: '8,10,12,16,20,30,40' },
    'frame-work-ms': { type: 'string', default: '6' },
    // The host yields through a MessageChannel; `--page-query yield=v86` puts v86's own blob
    // worker back, and `yield=blocking` tries scheduler.postTask at user-blocking priority.
    'page-query': { type: 'string', default: '' },
    chrome: { type: 'string', default: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' },
    out: { type: 'string', default: path.join(outDir, 'bench.json') },
  },
});

const unknown = (opts.only ?? []).filter(section => !SECTIONS.includes(section));
if (unknown.length) {
  console.error(`Unknown section ${unknown.join(', ')}; the sections are ${SECTIONS.join(', ')}.`);
  process.exit(2);
}
const wanted = section => !opts.only || opts.only.includes(section);
const repeats = Number(opts.repeats);
const rates = opts.rates.split(',').map(Number);
const sweepRates = opts.sweep.split(',').filter(Boolean).map(Number);

/** The task's floor: stop well before the disk fills. */
const MIN_FREE_KB = 5_767_168;

/** Classroom lines, in Mbit/s. Upload and latency are what DevTools' presets pair with them. */
const NETS = [null, 50, 20];
const NET_LATENCY_MS = 20;
const NET_UPLOAD_MBIT = 10;

const PROGRAMS = ['label.py', 'canvas.py', 'ttk_widgets.py'];

/** What frame-load spends per frame on an unthrottled page: a stand-in for the app's own frame. */
const FRAME_WORK_MS = Number(opts['frame-work-ms']);

const imageRoot = path.join(repoDir, 'web/vm/image');
const manifest = JSON.parse(fs.readFileSync(path.join(imageRoot, 'manifest.json'), 'utf8'));

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const round = (value, digits = 0) => (typeof value === 'number' ? Number(value.toFixed(digits)) : value ?? null);

function freeKb() {
  const stats = fs.statfsSync('/Users');
  return Math.floor(stats.bavail * stats.bsize / 1024);
}

function checkDisk() {
  const free = freeKb();
  if (free < MIN_FREE_KB) {
    console.error(`DISK_LOW: ${free} KB free on /Users, under ${MIN_FREE_KB}.`);
    process.exit(3);
  }
  return free;
}

checkDisk();
fs.mkdirSync(profilesDir, { recursive: true });

const server = await startServer();
const baseUrl = `${server.url}vm/image/`;
const bundleUrl = `${baseUrl}${manifest.imageId}/`;
const urls = {
  lib: `${bundleUrl}${manifest.v86.lib}`,
  wasm: `${bundleUrl}${manifest.v86.wasm}`,
  state: `${bundleUrl}${manifest.state.file}`,
  rootfs: `${bundleUrl}${manifest.rootfs.dir}`,
};

const results = {
  startedAt: new Date().toISOString(),
  machine: {
    model: execFileSync('sysctl', ['-n', 'hw.model'], { encoding: 'utf8' }).trim(),
    cpu: os.cpus()[0].model,
    cores: os.cpus().length,
    memoryGiB: Math.round(os.totalmem() / 2 ** 30),
    os: `${os.type()} ${os.release()}`,
    node: process.version,
  },
  manifest: { imageId: manifest.imageId, v86: manifest.v86.version, stateBytes: manifest.state.bytes, rawBytes: manifest.state.rawBytes, wasmBytes: manifest.v86.wasmBytes },
  settings: { repeats, rates, sweepRates, nets: NETS, netLatencyMs: NET_LATENCY_MS, netUploadMbit: NET_UPLOAD_MBIT },
};

function save() {
  fs.mkdirSync(path.dirname(opts.out), { recursive: true });
  fs.writeFileSync(opts.out, `${JSON.stringify(results, null, 1)}\n`);
}

// Chrome

let profileCount = 0;
function newProfile(name) {
  const dir = path.join(profilesDir, `${Date.now()}-${profileCount++}-${name}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

async function withBrowser(profileDir, fn) {
  checkDisk();
  const browser = await puppeteer.launch({
    executablePath: opts.chrome,
    headless: true,
    userDataDir: profileDir,
    protocolTimeout: 900_000,
    defaultViewport: { width: 1280, height: 900, deviceScaleFactor: 1 },
    args: [
      // measureUserAgentSpecificMemory otherwise waits for the next GC, up to 20 s.
      '--enable-blink-features=ForceEagerMeasureMemory',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-component-update',
      '--window-size=1280,900',
    ],
  });
  results.chrome ??= await browser.version();
  try {
    return await fn(browser);
  } finally {
    await browser.close().catch(() => {});
  }
}

/** Opens the bench page in `browser` with the throttling applied before it loads. */
async function openBench(browser, { rate = 1, net = null, fresh = false, query = '' } = {}) {
  const pages = await browser.pages();
  const page = !fresh && pages.length ? pages[0] : await browser.newPage();
  const logs = [];
  page.on('console', message => {
    if (['error', 'warn', 'warning'].includes(message.type())) logs.push(`${message.type()}: ${message.text().slice(0, 300)}`);
  });
  page.on('pageerror', error => logs.push(`pageerror: ${error.message.slice(0, 300)}`));
  if (rate > 1) await page.emulateCPUThrottling(rate);
  if (net) {
    await page.emulateNetworkConditions({
      download: net * 1e6 / 8,
      upload: NET_UPLOAD_MBIT * 1e6 / 8,
      latency: NET_LATENCY_MS,
    });
  }
  const search = [opts['page-query'], query].filter(Boolean).join('&');
  await page.goto(`${server.url}bench/${search ? `?${search}` : ''}`, { waitUntil: 'load' });
  await page.evaluate(() => window.bench.loaded);
  return { page, logs };
}

const bench = (page, fn, arg) => page.evaluate(fn, arg);

/** Every process of the browser whose pid is `root`, with RSS and macOS's footprint. */
function chromeProcesses(root) {
  const rows = execFileSync('ps', ['-Ao', 'pid=,ppid=,rss=,command='], { encoding: 'utf8', maxBuffer: 64 << 20 })
    .split('\n')
    .map(line => line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/))
    .filter(Boolean)
    .map(([, pid, ppid, rss, command]) => ({ pid: Number(pid), ppid: Number(ppid), rssKiB: Number(rss), command }));
  const tree = new Set([root]);
  for (let grew = true; grew;) {
    grew = false;
    for (const row of rows) {
      if (!tree.has(row.pid) && tree.has(row.ppid)) {
        tree.add(row.pid);
        grew = true;
      }
    }
  }
  return rows.filter(row => tree.has(row.pid)).map(row => ({
    pid: row.pid,
    type: /--type=(\S+)/.exec(row.command)?.[1] ?? 'browser',
    subtype: /--utility-sub-type=(\S+)/.exec(row.command)?.[1] ?? null,
    rssMiB: round(row.rssKiB / 1024, 1),
    footprintMiB: footprint(row.pid),
  })).sort((a, b) => (b.footprintMiB ?? 0) - (a.footprintMiB ?? 0));
}

/** CPU time every process of the browser whose pid is `root` has used so far, in seconds. */
function cpuSeconds(root) {
  const rows = execFileSync('ps', ['-Ao', 'pid=,ppid=,time='], { encoding: 'utf8', maxBuffer: 64 << 20 })
    .split('\n')
    .map(line => line.trim().split(/\s+/))
    .filter(parts => parts.length === 3)
    .map(([pid, ppid, time]) => ({ pid: Number(pid), ppid: Number(ppid), time }));
  const tree = new Set([root]);
  for (let grew = true; grew;) {
    grew = false;
    for (const row of rows) {
      if (!tree.has(row.pid) && tree.has(row.ppid)) {
        tree.add(row.pid);
        grew = true;
      }
    }
  }
  // ps prints [[hh:]mm:]ss.cc.
  const seconds = time => time.split(':').reduce((total, part) => total * 60 + Number(part), 0);
  return rows.filter(row => tree.has(row.pid)).reduce((total, row) => total + seconds(row.time), 0);
}

/** `fn`'s result, with the share of one core the whole browser used while it ran. */
async function withCpu(browser, fn) {
  const root = browser.process().pid;
  const cpuBefore = cpuSeconds(root);
  const started = performance.now();
  const result = await fn();
  const wallS = (performance.now() - started) / 1000;
  return { ...result, cpuShare: round((cpuSeconds(root) - cpuBefore) / wallS, 3) };
}

function footprint(pid) {
  try {
    const text = execFileSync('footprint', ['--noCategories', String(pid)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const found = /Footprint:\s*([\d.]+)\s*(B|KB|MB|GB)/.exec(text);
    if (!found) return null;
    const scale = { B: 1 / 2 ** 20, KB: 1 / 1024, MB: 1, GB: 1024 }[found[2]];
    return round(Number(found[1]) * scale, 1);
  } catch {
    return null;
  }
}

function loadAverage() {
  return os.loadavg().map(value => round(value, 2));
}

// The flow every matrix session runs

/** Opens the VM with Run pressed at once on `first`, then runs each program from the parked machine. */
async function flow(page, first) {
  const out = { load: loadAverage(), first, runs: [], parks: [] };
  out.start = await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: first });
  if (out.start.readyMs !== undefined) {
    out.parks.push(await bench(page, () => window.bench.stop()));
    for (const name of PROGRAMS) {
      out.runs.push(await bench(page, n => window.bench.runProgram(n), name));
      out.parks.push(await bench(page, () => window.bench.stop()));
    }
  }
  out.info = await bench(page, () => window.bench.info());
  delete out.info.navigation;
  out.resources = summarizeResources(await bench(page, () => window.bench.resources()));
  out.failures = await bench(page, () => window.bench.failures());
  out.stats = await bench(page, () => window.bench.stats());
  return out;
}

function summarizeResources(entries) {
  const pick = suffix => entries.filter(entry => entry.name.endsWith(suffix)).map(entry => ({
    ms: round(entry.duration, 1),
    start: round(entry.start, 1),
    transferSize: entry.transferSize,
    decodedBodySize: entry.decodedBodySize,
  }));
  const rootfs = entries.filter(entry => entry.name.includes('/rootfs/'));
  return {
    manifest: pick('/vm/image/manifest.json'),
    lib: pick(`/${manifest.v86.lib}`),
    wasm: pick(`/${manifest.v86.wasm}`),
    state: pick(`/${manifest.state.file}`),
    rootfs: { count: rootfs.length, transferSize: rootfs.reduce((sum, entry) => sum + entry.transferSize, 0) },
    page: entries.filter(entry => /\/(bench|vm)\/[^/]+\.(js|html)$/.test(entry.name)).length,
    transferSize: entries.reduce((sum, entry) => sum + (entry.transferSize ?? 0), 0),
  };
}

function serverTotals() {
  let requests = 0;
  let notModified = 0;
  let bytes = 0;
  for (const entry of server.stats.values()) {
    requests += entry.requests;
    notModified += entry.notModified;
    bytes += entry.bytes;
  }
  return { requests, notModified, bytes };
}

/** One browser session on `profile`: the flow, the server's view of it and Chrome's warnings. */
async function session(profile, { rate, net = null, label, first = 'label.py' }) {
  server.resetStats();
  const started = performance.now();
  try {
    return await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate, net });
      const out = await flow(page, first);
      out.server = serverTotals();
      out.logs = logs;
      out.wallMs = round(performance.now() - started);
      return out;
    });
  } catch (error) {
    return { error: String(error.stack ?? error), wallMs: round(performance.now() - started) };
  } finally {
    console.log(`  ${label} done in ${round((performance.now() - started) / 1000, 1)} s`);
  }
}

function describeSession(out) {
  if (out.error) return `ERROR ${out.error.split('\n')[0]}`;
  const start = out.start ?? {};
  const runs = out.runs.map(run => `${run.name.replace('.py', '')} ${round(run.windowMs)}/${round(run.early?.paintedMs)}`).join(', ');
  const restores = out.parks.map(park => round(park.restore?.syncMs)).join('/');
  return `ready ${round(start.readyMs)} ms, first window (${out.first}) ${round(start.run?.windowMs)} on the canvas ${round(start.run?.early?.paintedMs)}; ` +
    `runs (WINDOW/on the canvas) ${runs}; park restores ${restores} ms; failures ${out.failures?.length ?? '?'}`;
}

// Sections

async function nodeBaseline() {
  const { openVm } = await import('../../../web/vm/vm_host.js');
  const events = [];
  const vm = openVm({
    baseUrl: `${imageRoot}/`,
    trackVisibility: false,
    onEvent: event => {
      event.at = performance.now();
      events.push(event);
    },
  });
  const out = { load: loadAverage(), runs: [] };
  const t0 = performance.now();
  const ready = await vm.load();
  out.readyMs = round(performance.now() - t0, 1);
  out.ready = ready.type;
  const until = async (test, timeoutMs) => {
    const end = performance.now() + timeoutMs;
    while (performance.now() < end) {
      const found = events.find(test);
      if (found) return found;
      await sleep(2);
    }
    return null;
  };
  const titles = { 'label.py': 'Label', 'canvas.py': 'Canvas', 'ttk_widgets.py': 'ttk' };
  for (let round_ = 0; round_ < repeats; round_++) {
    for (const name of PROGRAMS) {
      const source = fs.readFileSync(path.join(repoDir, 'vm/tools/corpus', name), 'utf8');
      const started = performance.now();
      const handle = vm.run({ files: { 'main.py': source }, entry: 'main.py' });
      const shown = await until(e => e.type === 'window' && e.run === handle.id && e.windows.some(w => w.mapped && w.title === titles[name]), 30_000);
      out.runs.push({ name, windowMs: shown ? round(shown.at - started, 1) : null });
      const stopping = performance.now();
      await vm.stop();
      out.runs.at(-1).parkedMs = round(performance.now() - stopping, 1);
    }
  }
  const speedSource = `import time
n = 0
end = time.monotonic() + 3
while time.monotonic() < end:
    for _ in range(1000):
        n += 1
print("speed", n // 3, flush=True)
`;
  out.speed = [];
  for (let i = 0; i < repeats; i++) {
    const handle = vm.run({ files: { 'main.py': speedSource }, entry: 'main.py' });
    await handle.ended;
    const text = events.filter(e => e.type === 'output' && e.run === handle.id).map(e => e.text).join('');
    out.speed.push(Number(/speed (\d+)/.exec(text)?.[1] ?? NaN));
    await vm.stop();
  }
  await vm.destroy();
  return out;
}

/** The ways the state can come down: vm_download.js's Range pieces, and one plain GET. */
const DOWNLOAD_MODES = { pieces: {}, single: { ranges: false } };

/** Where the interrupted downloads are cut: this share of the bundle in, at 20 Mbit/s. */
const CUT_AT = 0.4;

function describeDownload(out) {
  if (out.error) return `ERROR ${out.error.message ?? out.error}`;
  const eta = out.etaErrorS ?? {};
  return `${round(out.ms ?? out.readyMs)} ms${out.downloadMs ? `, download ${round(out.downloadMs)} ms` : ''}; ` +
    `first estimate at ${round(out.firstRateMs)} ms, rate at the end ${round((out.rateAtEnd ?? 0) / 1e6, 2)} MB/s; ` +
    `ETA error median ${round(eta.median, 1)} s, p90 ${round(eta.p90, 1)} s`;
}

/** Waits until the page's download has `fraction` of the bundle, and returns when that was. */
async function downloadReaches(page, fraction, timeoutMs = 120_000) {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const status = await bench(page, () => window.bench.downloadStatus());
    if (status && status.loaded >= status.total * fraction) return status;
    if (Date.now() > end) throw new Error(`the download did not reach ${fraction * 100} % within ${timeoutMs} ms`);
    await sleep(50);
  }
}

/**
 * The bundle into the Cache API: a cold load to ready at 20 and 50 Mbit/s, in pieces and as one
 * GET; the same download with the server's connections dropped for 3 s at 40 % (serve.mjs's cut:
 * Chrome's offline mode only holds a response that is under way, and nothing is lost); and one
 * whose page is reloaded at 40 % and then asked again, which is what resumes from the pieces kept.
 */
async function downloads() {
  const out = { cold: [], dropped: [], reloaded: [] };
  const stateBytes = () => server.stats.get(`/vm/image/${manifest.imageId}/${manifest.state.file}`)?.bytes ?? 0;
  const stateRequests = () => server.stats.get(`/vm/image/${manifest.imageId}/${manifest.state.file}`)?.requests ?? 0;
  for (let rep = 0; rep < repeats; rep++) {
    for (const net of [20, 50]) {
      for (const [mode, knobs] of Object.entries(DOWNLOAD_MODES)) {
        const profile = newProfile(`download-${mode}-${net}`);
        server.resetStats();
        const label = `rep ${rep + 1} ${mode} at ${net} Mbit/s`;
        try {
          const measured = await withBrowser(profile, async browser => {
            const { page, logs } = await openBench(browser, { net });
            const load = await bench(page, o => window.bench.coldLoad(o), { baseUrl, download: knobs });
            const cold = { ...load, logs, stateRequests: stateRequests(), stateBytesServed: stateBytes() };
            // The same bundle again from a fresh page: the state from the Cache API,
            // in the pieces the cold load kept or in the one it got.
            await page.reload({ waitUntil: 'load' });
            await page.evaluate(() => window.bench.loaded);
            const warm = await bench(page, o => window.bench.coldLoad(o), { baseUrl, download: knobs });
            return { ...cold, warm: { readyMs: warm.readyMs, downloadMs: warm.downloadMs, phases: warm.phases, stateRequests: stateRequests() - cold.stateRequests } };
          });
          out.cold.push({ rep, net, mode, load: loadAverage(), ...measured });
          console.log(`  cold ${label}: ${describeDownload(measured)}; state requests ${measured.stateRequests}; ` +
            `warm again ${round(measured.warm.readyMs)} ms to ready, the bundle read in ${round(measured.warm.downloadMs)} ms`);
        } catch (error) {
          out.cold.push({ rep, net, mode, error: String(error.stack ?? error) });
          console.log(`  cold ${label}: ERROR ${error.message}`);
        }
        fs.rmSync(profile, { recursive: true, force: true });
        results.download = out;
        save();
      }
    }
    for (const [mode, knobs] of Object.entries(DOWNLOAD_MODES)) {
      const net = 20;
      const conditions = { download: net * 1e6 / 8, upload: NET_UPLOAD_MBIT * 1e6 / 8, latency: NET_LATENCY_MS };

      let profile = newProfile(`dropped-${mode}`);
      server.resetStats();
      try {
        const measured = await withBrowser(profile, async browser => {
          const { page } = await openBench(browser, { net });
          await bench(page, o => window.bench.startDownload(o), { baseUrl, download: knobs });
          const cut = await downloadReaches(page, CUT_AT);
          server.cut(3000);
          const done = await bench(page, () => window.bench.downloadDone());
          return { cutAtMs: cut.at, cutAtBytes: cut.loaded, ...done, stateRequests: stateRequests(), stateBytesServed: stateBytes() };
        });
        out.dropped.push({ rep, net, mode, offlineMs: 3000, ...measured });
        console.log(`  dropped ${mode}: cut at ${round(measured.cutAtBytes / 1e6, 1)} MB, ${describeDownload(measured)}; ` +
          `fetched ${round((measured.result?.fetched ?? 0) / 1e6, 1)} MB of ${round((measured.result?.total ?? 0) / 1e6, 1)}; state requests ${measured.stateRequests}`);
      } catch (error) {
        out.dropped.push({ rep, net, mode, error: String(error.stack ?? error) });
        console.log(`  dropped ${mode}: ERROR ${error.message}`);
      }
      fs.rmSync(profile, { recursive: true, force: true });

      profile = newProfile(`reloaded-${mode}`);
      server.resetStats();
      try {
        const measured = await withBrowser(profile, async browser => {
          const { page } = await openBench(browser, { net });
          const started = Date.now();
          await bench(page, o => window.bench.startDownload(o), { baseUrl, download: knobs });
          const cut = await downloadReaches(page, CUT_AT);
          await page.reload({ waitUntil: 'load' });
          await page.evaluate(() => window.bench.loaded);
          await page.emulateNetworkConditions(conditions);
          await bench(page, o => window.bench.startDownload(o), { baseUrl, download: knobs });
          const done = await bench(page, () => window.bench.downloadDone());
          return { cutAtMs: cut.at, cutAtBytes: cut.loaded, wallMs: Date.now() - started, ...done, stateRequests: stateRequests(), stateBytesServed: stateBytes() };
        });
        out.reloaded.push({ rep, net, mode, ...measured });
        console.log(`  reloaded ${mode}: cut at ${round(measured.cutAtBytes / 1e6, 1)} MB; the second download took ${round(measured.ms)} ms, ` +
          `${round((measured.result?.cached ?? 0) / 1e6, 1)} MB from the cache and ${round((measured.result?.fetched ?? 0) / 1e6, 1)} MB fetched; ` +
          `${round(measured.wallMs / 1000, 1)} s from the first start`);
      } catch (error) {
        out.reloaded.push({ rep, net, mode, error: String(error.stack ?? error) });
        console.log(`  reloaded ${mode}: ERROR ${error.message}`);
      }
      fs.rmSync(profile, { recursive: true, force: true });
      results.download = out;
      save();
    }
  }
  return out;
}

/** Every repeat presses Run on the next of PROGRAMS first, so each is timed from a cold and a warm load. */
async function matrix() {
  const sessions = [];
  for (let rep = 0; rep < repeats; rep++) {
    const first = PROGRAMS[rep % PROGRAMS.length];
    for (const rate of rates) {
      for (const net of NETS) {
        const profile = newProfile(`cold-${rate}x-${net ?? 'full'}`);
        const label = `rep ${rep + 1} cpu ${rate}x net ${net ?? 'unthrottled'} cold`;
        const cold = await session(profile, { rate, net, label, first });
        sessions.push({ rep, rate, net, mode: 'cold', ...cold });
        console.log(`    ${describeSession(cold)}`);
        if (net === null) {
          const warm = await session(profile, { rate, label: `rep ${rep + 1} cpu ${rate}x warm`, first });
          sessions.push({ rep, rate, net, mode: 'warm', ...warm });
          console.log(`    ${describeSession(warm)}`);
        }
        fs.rmSync(profile, { recursive: true, force: true });
        results.matrix = sessions;
        save();
      }
    }
  }
  return sessions;
}

/** A profile whose Cache Storage and HTTP cache already hold the bundle. */
async function warmProfile() {
  const profile = newProfile('warm');
  await session(profile, { rate: 1, label: 'filling the warm profile' });
  return profile;
}

async function micro(profile) {
  const out = [];
  for (const rate of rates) {
    const measured = await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate });
      const cache = await bench(page, o => window.bench.cacheRead(o), { urls: [urls.state, urls.wasm], repeats: 5 });
      const compile = await bench(page, o => window.bench.compile(o), { wasmUrl: urls.wasm, repeats: 5 });
      return { cache, compile, logs };
    });
    out.push({ rate, load: loadAverage(), ...measured });
    const reads = measured.cache[urls.state].map(read => round(read?.ms));
    console.log(`  micro cpu ${rate}x: state read ${reads.join('/')} ms; compile ${measured.compile.fromBytes.map(v => round(v)).join('/')} ms; streamed ${measured.compile.streamed.map(v => round(v)).join('/')} ms`);
  }
  return out;
}

async function restore(profile) {
  const out = [];
  for (const rate of rates) {
    const measured = await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate });
      const experiment = await bench(page, o => window.bench.restoreExperiment(o), {
        libUrl: urls.lib,
        wasmUrl: urls.wasm,
        stateUrl: urls.state,
        rootfsUrl: urls.rootfs,
        manifest,
        repeats: 5,
      });
      return { ...experiment, logs };
    });
    out.push({ rate, load: loadAverage(), ...measured });
    const show = list => list.map(entry => round(entry.syncMs ?? entry.decompressMs)).join('/');
    console.log(`  restore cpu ${rate}x: zstd ${show(measured.zstd)} ms; main-thread decompress ${show(measured.mainDecompress)} ms; ` +
      `raw ${show(measured.raw)} ms; worker decompress ${show(measured.workerDecompress)} ms then raw ${measured.workerDecompress.map(e => round(e.restoreSyncMs)).join('/')} ms; ` +
      `the host's worker ${show(measured.hostInflate)} ms then raw ${measured.hostInflate.map(e => round(e.restoreSyncMs)).join('/')} ms; ` +
      `READY after zstd ${round(measured.ready.zstd.ms)} raw ${round(measured.ready.raw.ms)} worker ${round(measured.ready.worker.ms)} host ${round(measured.ready.host.ms)} ms`);
  }
  return out;
}

/**
 * The host's park as the app gets it: openVm() with Run pressed at once, then label.py run and
 * stopped again and again. Every park restores the raw state the load decompressed in a worker.
 */
async function park(profile) {
  const out = [];
  for (const rate of rates) {
    const measured = await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate });
      const result = { load: loadAverage() };
      result.start = await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
      result.parks = [await bench(page, () => window.bench.stop())];
      for (let i = 0; i < repeats + 2; i++) {
        await bench(page, n => window.bench.runProgram(n), 'label.py');
        result.parks.push(await bench(page, () => window.bench.stop()));
      }
      result.stats = await bench(page, () => window.bench.stats());
      result.failures = await bench(page, () => window.bench.failures());
      result.logs = logs;
      return result;
    });
    out.push({ rate, ...measured });
    const parks = measured.parks;
    const list = values => values.map(value => round(value)).join('/');
    const longest = park => Math.max(0, ...park.longTasks.map(task => task.duration));
    console.log(`  park cpu ${rate}x: ready ${round(measured.start.readyMs)} ms, state inflated ${measured.stats?.inflate?.where} in ` +
      `${round(measured.stats?.inflate?.ms)} ms, load restore ${list(measured.start.restoresDuringLoad?.map(r => r.syncMs) ?? [])} ms; ` +
      `park restores ${list(parks.map(p => p.restore?.syncMs))} ms; longest task ${list(parks.map(longest))} ms; ` +
      `longest frame ${list(parks.map(p => p.frames.max))} ms; stop to parked ${list(parks.map(p => p.parkedMs))} ms; failures ${measured.failures.length}`);
  }
  return out;
}

/** Steps a second and the guest's clock, from animation.py's lines over the last `seconds`. */
function animationRate(stdout, seconds) {
  const lines = stdout.trim().split('\n').map(line => line.split(' ').map(Number)).filter(parts => parts.length === 3 && parts.every(Number.isFinite));
  if (lines.length < 2) return null;
  const last = lines.at(-1);
  const first = lines.find(parts => parts[1] >= last[1] - seconds) ?? lines[0];
  if (last[1] === first[1]) return null;
  return round((last[0] - first[0]) / (last[1] - first[1]), 1);
}

async function frames(profile) {
  const out = [];
  for (const rate of rates) {
    const measured = await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate });
      const result = { load: loadAverage() };
      result.start = await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
      result.idleTk = await withCpu(browser, () => bench(page, () => window.bench.hold(3000)));
      result.parkAfterIdle = await bench(page, () => window.bench.stop());
      result.parked = await withCpu(browser, () => bench(page, () => window.bench.hold(3000)));
      result.busyStart = await bench(page, () => window.bench.startProgram('busy.py'));
      await sleep(1000);
      result.busy = await bench(page, () => window.bench.hold(6000));
      result.parkAfterBusy = await bench(page, () => window.bench.stop());
      const animation = await bench(page, () => window.bench.runProgram('animation.py'));
      result.animationStart = animation;
      await sleep(1000);
      result.animation = await bench(page, id => window.bench.hold(6000, { run: id }), animation.id);
      result.animation.stepsPerSecond = animationRate(result.animation.stdout, 6);
      delete result.animation.stdout;
      result.parkAfterAnimation = await bench(page, () => window.bench.stop());
      result.speed = await bench(page, () => window.bench.runToEnd('speed.py'));
      result.speed.iterationsPerSecond = Number(/speed (\d+)/.exec(result.speed.output?.stdout ?? '')?.[1] ?? NaN);
      result.parkAfterSpeed = await bench(page, () => window.bench.stop());
      result.probe = await bench(page, () => window.bench.probe());
      result.failures = await bench(page, () => window.bench.failures());
      result.logs = logs;
      return result;
    });
    out.push({ rate, ...measured });
    const f = stats => `p50 ${round(stats.p50, 1)} p95 ${round(stats.p95, 1)} max ${round(stats.max, 1)} (>50 ms: ${stats.over50})`;
    console.log(`  frames cpu ${rate}x, yield ${measured.probe.yield}: idle Tk ${f(measured.idleTk.frames)}, ${measured.idleTk.cpuShare} of a core; ` +
      `parked ${f(measured.parked.frames)}, ${measured.parked.cpuShare} of a core; busy ${f(measured.busy.frames)}; ` +
      `animation ${f(measured.animation.frames)} at ${measured.animation.stepsPerSecond} steps/s; speed ${measured.speed.iterationsPerSecond}/s; ` +
      `STOP to EXIT, busy ${round(measured.parkAfterBusy.stopAnswered, 1)} ms; failures ${measured.failures.length}`);
  }
  return out;
}

async function memory(profile) {
  return withBrowser(profile, async browser => {
    const root = browser.process().pid;
    const snapshots = [];
    const snap = async (label, pages) => {
      await sleep(1500);
      const entry = {
        label,
        pages: await Promise.all(pages.map(page => bench(page, () => window.bench.memory()))),
        processes: chromeProcesses(root),
      };
      snapshots.push(entry);
      const renderers = entry.processes.filter(p => p.type === 'renderer').map(p => `${p.footprintMiB}/${p.rssMiB}`).join(', ');
      const total = entry.processes.reduce((sum, p) => sum + (p.footprintMiB ?? 0), 0);
      console.log(`  memory, ${label}: page ${entry.pages.map(p => round((p.userAgentSpecific?.bytes ?? 0) / 2 ** 20, 1)).join(' + ')} MiB; ` +
        `renderers footprint/RSS ${renderers} MiB; all of Chrome ${round(total, 1)} MiB footprint`);
    };
    const a = await openBench(browser);
    await snap('tab A open, no VM', [a.page]);
    await bench(a.page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
    await snap('tab A running label.py', [a.page]);
    await bench(a.page, () => window.bench.stop());
    await snap('tab A parked', [a.page]);
    await bench(a.page, () => window.bench.runProgram('ttk_widgets.py'));
    await snap('tab A running ttk_widgets.py', [a.page]);
    await bench(a.page, () => window.bench.stop());
    await snap('tab A parked after runs', [a.page]);
    const b = await openBench(browser, { fresh: true });
    await b.page.bringToFront();
    await bench(b.page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
    await bench(b.page, () => window.bench.stop());
    await bench(b.page, () => window.bench.runProgram('ttk_widgets.py'));
    await snap('tab A parked in the background, tab B running ttk_widgets.py', [a.page, b.page]);
    await bench(b.page, () => window.bench.stop());
    await snap('both tabs parked', [a.page, b.page]);
    return { load: loadAverage(), snapshots, logs: [...a.logs, ...b.logs] };
  });
}

async function frameLoad(profile) {
  const iterations = await withBrowser(profile, async browser => {
    const { page } = await openBench(browser);
    return bench(page, ms => window.bench.calibrate(ms), FRAME_WORK_MS);
  });
  const out = { frameWorkMs: FRAME_WORK_MS, iterations, rates: [] };
  for (const rate of rates) {
    const measured = await withBrowser(profile, async browser => {
      const { page, logs } = await openBench(browser, { rate });
      await bench(page, n => window.bench.setFrameWork(n), iterations);
      const result = { load: loadAverage() };
      result.noVm = await bench(page, () => window.bench.hold(3000));
      result.start = await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
      result.parkAfterStart = await bench(page, () => window.bench.stop());
      result.parked = await bench(page, () => window.bench.hold(3000));
      result.busyStart = await bench(page, () => window.bench.startProgram('busy.py'));
      await sleep(1000);
      result.busy = await bench(page, () => window.bench.hold(6000));
      result.parkAfterBusy = await bench(page, () => window.bench.stop());
      const animation = await bench(page, () => window.bench.runProgram('animation.py'));
      result.animationStart = animation;
      await sleep(1000);
      result.animation = await bench(page, id => window.bench.hold(6000, { run: id }), animation.id);
      result.animation.stepsPerSecond = animationRate(result.animation.stdout, 6);
      delete result.animation.stdout;
      result.parkAfterAnimation = await bench(page, () => window.bench.stop());
      result.speed = await bench(page, () => window.bench.runToEnd('speed.py'));
      result.speed.iterationsPerSecond = Number(/speed (\d+)/.exec(result.speed.output?.stdout ?? '')?.[1] ?? NaN);
      await bench(page, () => window.bench.stop());
      result.probe = await bench(page, () => window.bench.probe());
      result.failures = await bench(page, () => window.bench.failures());
      result.logs = logs;
      return result;
    });
    out.rates.push({ rate, ...measured });
    const f = stats => `p50 ${round(stats.p50, 1)} p95 ${round(stats.p95, 1)} max ${round(stats.max, 1)} (>50 ms: ${stats.over50})`;
    console.log(`  frame-load cpu ${rate}x, ${FRAME_WORK_MS} ms a frame at 1x: no VM ${f(measured.noVm.frames)}; parked ${f(measured.parked.frames)}; ` +
      `busy ${f(measured.busy.frames)}; animation ${f(measured.animation.frames)} at ${measured.animation.stepsPerSecond} steps/s; ` +
      `first window ${round(measured.start.run?.windowMs)} ms, on the canvas ${round(measured.start.run?.early?.paintedMs)} ms; ` +
      `speed ${measured.speed.iterationsPerSecond}/s; yield ${measured.probe.yield}`);
  }
  return out;
}

/** Runs label.py again and again, every other run with the agent's poll(2) woken every 50 ms. */
async function windowDelay(profile) {
  const out = [];
  for (const rate of rates) {
    const runs = await withBrowser(profile, async browser => {
      const { page } = await openBench(browser, { rate });
      await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
      await bench(page, () => window.bench.stop());
      const list = [];
      for (let i = 0; i < 8; i++) {
        for (const nudge of [false, true]) {
          const run = await bench(page, o => window.bench.runProgram(o.name, { nudge: o.nudge }), { name: 'label.py', nudge });
          list.push({
            nudge,
            startedMs: round(run.startedMs, 1),
            windowMs: round(run.windowMs, 1),
            paintedMs: round(run.paintedMs, 1),
            onCanvasMs: round(run.early?.paintedMs, 1),
            error: run.error ?? null,
          });
          await bench(page, () => window.bench.stop());
        }
      }
      return list;
    });
    out.push({ rate, runs });
    const late = nudge => runs.filter(run => run.nudge === nudge && run.windowMs - run.startedMs > 1900).length;
    const windows = nudge => runs.filter(run => run.nudge === nudge).map(run => round(run.windowMs)).join('/');
    const canvas = nudge => runs.filter(run => run.nudge === nudge).map(run => round(run.onCanvasMs)).join('/');
    console.log(`  window-delay cpu ${rate}x: plain ${windows(false)} ms (${late(false)} of 8 over 1.9 s after STARTED; on the canvas ${canvas(false)}); ` +
      `nudged ${windows(true)} ms (${late(true)} of 8; on the canvas ${canvas(true)})`);
  }
  return out;
}

/** Writes the bundle's state decompressed to vm/build/bench/data/, where /bench-data/ serves it. */
function writeRawState() {
  const dataDir = path.join(outDir, 'data');
  const rawFile = path.join(dataDir, 'state.raw');
  checkDisk();
  const raw = zlib.zstdDecompressSync(fs.readFileSync(path.join(imageRoot, manifest.imageId, manifest.state.file)));
  if (raw.byteLength !== manifest.state.rawBytes) throw new Error(`The raw state is ${raw.byteLength} B, not ${manifest.state.rawBytes}.`);
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(rawFile, raw);
  return rawFile;
}

async function rawCache(profile) {
  const rawFile = writeRawState();
  const out = [];
  try {
    for (const rate of rates) {
      const measured = await withBrowser(profile, async browser => {
        const { page } = await openBench(browser, { rate });
        return bench(page, o => window.bench.cacheRoundTrip(o), { url: `${server.url}bench-data/state.raw`, repeats: 5 });
      });
      out.push({ rate, ...measured });
      console.log(`  raw-cache cpu ${rate}x: put ${round(measured.putMs)} ms; read ${measured.reads.map(r => round(r.ms)).join('/')} ms; ` +
        `frame max ${measured.reads.map(r => round(r.frames.max)).join('/')} ms; long tasks ${JSON.stringify(measured.reads.map(r => r.longTasks))}`);
    }
  } finally {
    fs.rmSync(rawFile, { force: true });
  }
  return out;
}

/** The tab through openVm() on a bundle the page builds, with the zstd state and then a raw one. */
async function rawMemory(profile) {
  const rawFile = writeRawState();
  const out = [];
  try {
    for (const [kind, stateUrl] of [['zstd', urls.state], ['raw', `${server.url}bench-data/state.raw`]]) {
      const measured = await withBrowser(profile, async browser => {
        const root = browser.process().pid;
        const { page, logs } = await openBench(browser);
        const snap = async label => {
          await sleep(1500);
          return { label, page: await bench(page, () => window.bench.memory()), processes: chromeProcesses(root) };
        };
        const result = { load: loadAverage(), snapshots: [], parks: [] };
        result.start = await bench(page, o => window.bench.startWithBundle(o), {
          baseUrl, libUrl: urls.lib, wasmUrl: urls.wasm, stateUrl, rootfsUrl: urls.rootfs, manifest,
        });
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.ttk = await bench(page, () => window.bench.runProgram('ttk_widgets.py'));
        result.snapshots.push(await snap('running ttk_widgets.py'));
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.label = await bench(page, () => window.bench.runProgram('label.py'));
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.snapshots.push(await snap('parked after runs'));
        result.failures = await bench(page, () => window.bench.failures());
        result.logs = logs;
        return result;
      });
      out.push({ kind, ...measured });
      const last = measured.snapshots.at(-1);
      const renderer = last.processes.filter(p => p.type === 'renderer').sort((a, b) => b.footprintMiB - a.footprintMiB)[0];
      console.log(`  raw-memory ${kind}: ready ${round(measured.start.readyMs)} ms; park restores ${measured.parks.map(p => round(p.restore?.syncMs)).join('/')} ms; ` +
        `wasm ${round(last.page.vm.wasmBytes / 2 ** 20, 1)} MiB; page ${round(last.page.userAgentSpecific.bytes / 2 ** 20, 1)} MiB; ` +
        `renderer ${renderer.footprintMiB} MiB footprint, ${renderer.rssMiB} MiB RSS`);
    }
  } finally {
    fs.rmSync(rawFile, { force: true });
  }
  return out;
}

async function sweep(profile) {
  const out = [];
  for (const rate of sweepRates) {
    const started = performance.now();
    let measured;
    try {
      measured = await withBrowser(profile, async browser => {
        const { page, logs } = await openBench(browser, { rate });
        const result = { load: loadAverage() };
        result.start = await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py', timeoutMs: 300_000 });
        if (result.start.readyMs === undefined) return { ...result, logs };
        result.parks = [await bench(page, () => window.bench.stop())];
        const animation = await bench(page, () => window.bench.runProgram('animation.py', { timeoutMs: 120_000 }));
        result.animationStart = animation;
        result.animation = await bench(page, id => window.bench.hold(5000, { run: id }), animation.id);
        result.animation.stepsPerSecond = animationRate(result.animation.stdout, 5);
        delete result.animation.stdout;
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.busyStart = await bench(page, () => window.bench.startProgram('busy.py', { timeoutMs: 120_000 }));
        result.busy = await bench(page, () => window.bench.hold(5000));
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.ttk = await bench(page, () => window.bench.runProgram('ttk_widgets.py', { timeoutMs: 120_000 }));
        result.parks.push(await bench(page, () => window.bench.stop()));
        result.failures = await bench(page, () => window.bench.failures());
        result.state = await bench(page, () => window.bench.state());
        result.logs = logs;
        return result;
      });
    } catch (error) {
      measured = { error: String(error.stack ?? error) };
    }
    out.push({ rate, wallMs: round(performance.now() - started), ...measured });
    const s = measured.start ?? {};
    console.log(`  sweep cpu ${rate}x: ready ${round(s.readyMs)} ms (restores during load ${s.restoresDuringLoad?.length}), first window ${round(s.run?.windowMs)} ms; ` +
      `animation ${measured.animation?.stepsPerSecond} steps/s, frame max ${round(measured.animation?.frames?.max)} ms; busy frame max ${round(measured.busy?.frames?.max)} ms; ` +
      `ttk window ${round(measured.ttk?.windowMs)} ms; failures ${measured.failures?.length ?? '?'} ${JSON.stringify(measured.failures ?? measured.error ?? '').slice(0, 400)}`);
    results.sweep = out;
    save();
  }
  return out;
}

/** measureUserAgentSpecificMemory on any page of the server, the app's own included. */
function measurePage(page) {
  return page.evaluate(async () => {
    try {
      const measured = await performance.measureUserAgentSpecificMemory();
      const byScope = {};
      for (const entry of measured.breakdown) {
        const key = entry.attribution
          .map(a => `${a.scope} ${a.container ? 'in a frame ' : ''}${new URL(a.url, location.href).pathname}`)
          .join(' + ') || 'unattributed';
        byScope[key] = (byScope[key] ?? 0) + entry.bytes;
      }
      return { bytes: measured.bytes, byScope };
    } catch (error) {
      return { error: String(error) };
    }
  });
}

/**
 * The app from build/web/ on its own, then framed by the bench page beside the VM, in one tab and
 * in two. The frame shares the bench page's renderer, so each renderer is the app and the VM.
 */
async function app(profile) {
  if (!fs.existsSync(path.join(repoDir, 'build/web/main.dart.js'))) {
    console.log('  app: skipped, build/web/ has no build of the app');
    return { skipped: 'build/web/ has no build of the app' };
  }
  const built = fs.statSync(path.join(repoDir, 'build/web/main.dart.js')).mtime.toISOString();
  return withBrowser(profile, async browser => {
    const root = browser.process().pid;
    const snapshots = [];
    const snap = async (label, pages) => {
      await sleep(1500);
      const entry = { label, pages: [], processes: chromeProcesses(root) };
      for (const page of pages) entry.pages.push(await measurePage(page));
      snapshots.push(entry);
      const renderers = entry.processes.filter(p => p.type === 'renderer').map(p => `${p.footprintMiB}/${p.rssMiB}`).join(', ');
      const total = entry.processes.reduce((sum, p) => sum + (p.footprintMiB ?? 0), 0);
      console.log(`  app, ${label}: page ${entry.pages.map(p => round((p.bytes ?? 0) / 2 ** 20, 1)).join(' + ')} MiB; ` +
        `renderers footprint/RSS ${renderers} MiB; all of Chrome ${round(total, 1)} MiB footprint`);
    };
    const out = { built, load: loadAverage() };

    const alone = (await browser.pages())[0];
    await alone.goto(server.url, { waitUntil: 'load' });
    await alone.waitForSelector('flutter-view', { timeout: 60_000 });
    await sleep(10_000);
    out.alonePath = await alone.evaluate(() => location.pathname);
    await snap('the app alone, on its first screen', [alone]);
    await alone.close();

    const a = await openBench(browser, { fresh: true, query: 'app' });
    out.a = { settled: await bench(a.page, () => window.bench.appSettled()) };
    await snap('tab A: the app, no VM', [a.page]);
    out.a.start = await bench(a.page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
    out.a.parks = [await bench(a.page, () => window.bench.stop())];
    out.a.ttk = await bench(a.page, () => window.bench.runProgram('ttk_widgets.py'));
    await snap('tab A: the app, the VM running ttk_widgets.py', [a.page]);
    out.a.parks.push(await bench(a.page, () => window.bench.stop()));
    await snap('tab A: the app, the VM parked', [a.page]);
    out.a.speed = await bench(a.page, () => window.bench.runToEnd('speed.py'));
    out.a.speed.iterationsPerSecond = Number(/speed (\d+)/.exec(out.a.speed.output?.stdout ?? '')?.[1] ?? NaN);
    out.a.parks.push(await bench(a.page, () => window.bench.stop()));

    const b = await openBench(browser, { fresh: true, query: 'app' });
    await b.page.bringToFront();
    out.b = { settled: await bench(b.page, () => window.bench.appSettled()) };
    out.b.start = await bench(b.page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
    out.b.parks = [await bench(b.page, () => window.bench.stop())];
    out.b.ttk = await bench(b.page, () => window.bench.runProgram('ttk_widgets.py'));
    await snap('tab A parked in the background, tab B running ttk_widgets.py', [a.page, b.page]);
    out.b.parks.push(await bench(b.page, () => window.bench.stop()));
    await snap('both tabs parked', [a.page, b.page]);

    out.snapshots = snapshots;
    out.failures = [...await bench(a.page, () => window.bench.failures()), ...await bench(b.page, () => window.bench.failures())];
    out.logs = [...a.logs, ...b.logs];
    console.log(`  app: speed beside the idle app ${out.a.speed.iterationsPerSecond}/s; failures ${out.failures.length}`);
    return out;
  });
}

/**
 * Real input events through vm_screen.js and v86's adapters: keys typed with nothing clicked go to
 * the newest window (F4), a click moves them to the window clicked into, and Return reaches Tk.
 * Each rate runs twice, the second time with the agent's poll(2) woken every 50 ms, which tells a
 * focus the agent set late from one it never set.
 */
async function input(profile) {
  const out = [];
  for (const rate of rates) {
    for (const nudge of [false, true]) {
      const measured = await withBrowser(profile, async browser => {
        const { page, logs } = await openBench(browser, { rate });
        await bench(page, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
        await bench(page, () => window.bench.stop());
        if (nudge) await bench(page, () => window.bench.nudge(true));
        const result = { start: await bench(page, () => window.bench.inputStart()) };
        if (result.start.error || !result.start.entry) return { ...result, passed: false, logs };
        const { box, scale, entry: [x, y, w, h] } = result.start;
        const typed = performance.now();
        await typeLikeAPerson(page, 'Delft');
        await page.mouse.click(box.left + (x + w / 2) * scale, box.top + (y + h / 2) * scale);
        // The click reaches Tk through the agent's passive grab; keys typed before it lands would
        // still go to the other window.
        await sleep(300 * rate);
        await typeLikeAPerson(page, 'Sanne');
        await page.keyboard.press('Enter');
        result.result = await bench(page, id => window.bench.inputResult(id), result.start.id);
        result.typedToLineMs = round(performance.now() - typed);
        result.passed = result.result.line?.naam === 'Sanne' && result.result.line?.stad === 'Delft';
        await bench(page, () => window.bench.nudge(false));
        await bench(page, () => window.bench.stop());
        result.failures = await bench(page, () => window.bench.failures());
        result.logs = logs;
        return result;
      });
      out.push({ rate, nudge, ...measured });
      console.log(`  input cpu ${rate}x${nudge ? ', agent woken' : ''}: ${measured.passed ? 'pass' : 'FAIL'}; ` +
        `windows after ${round(measured.start.windowMs)} ms; line ${JSON.stringify(measured.result?.line ?? measured.result ?? measured.start.error)}`);
    }
  }
  return out;
}

/**
 * Types `text` the way a person does. Puppeteer's own type() sends a capital without pressing
 * Shift, and v86 goes by the physical key, so the guest would see a lower-case letter.
 */
async function typeLikeAPerson(page, text) {
  for (const char of text) {
    const upper = char !== char.toLowerCase();
    if (upper) await page.keyboard.down('Shift');
    await page.keyboard.press(upper ? `Key${char}` : char);
    if (upper) await page.keyboard.up('Shift');
    await sleep(30);
  }
}

/** Whole animation.py lines, `steps monotonic wall`, each with the page's clock when it arrived. */
function animationLines(chunks) {
  const lines = [];
  let rest = '';
  for (const chunk of chunks) {
    const parts = (rest + chunk.text).split('\n');
    rest = parts.pop();
    for (const line of parts) {
      const [steps, monotonic, wall] = line.split(' ').map(Number);
      if ([steps, monotonic, wall].every(Number.isFinite)) lines.push({ steps, monotonic, wall, at: chunk.at, pageWall: chunk.wall });
    }
  }
  return lines;
}

/**
 * F2 in a real browser: an animation keeps running in tab A while tab B is in front for
 * `hiddenS`, and must come back where it was, with no watchdog verdict and its clock set again.
 */
async function hidden(profile, hiddenS = 20) {
  return withBrowser(profile, async browser => {
    const { page: a, logs } = await openBench(browser);
    await bench(a, o => window.bench.start(o), { baseUrl, libUrl: urls.lib, program: 'label.py' });
    await bench(a, () => window.bench.stop());
    const animation = await bench(a, () => window.bench.runProgram('animation.py'));
    await sleep(3000);
    const probes = [await bench(a, () => window.bench.probe())];
    const b = await browser.newPage();
    await b.goto(`${server.url}bench/`, { waitUntil: 'load' });
    await b.bringToFront();
    const hiddenFrom = performance.now();
    await sleep(2000);
    probes.push(await bench(a, () => window.bench.probe()));
    await sleep(hiddenS * 1000 - 2000);
    probes.push(await bench(a, () => window.bench.probe()));
    await a.bringToFront();
    const hiddenMs = performance.now() - hiddenFrom;
    await sleep(500);
    probes.push(await bench(a, () => window.bench.probe()));
    await sleep(4000);
    probes.push(await bench(a, () => window.bench.probe()));
    const [before, early, late, back] = probes;
    const lines = animationLines(await bench(a, id => window.bench.outputSince(id), animation.id));
    const at = when => lines.filter(line => line.at <= when).at(-1);
    const after = lines.filter(line => line.at > back.at);
    const out = {
      hiddenMs: round(hiddenMs),
      probes,
      windowMs: animation.windowMs,
      stepsBefore: at(before.at)?.steps ?? null,
      stepsWhileHidden: (at(late.at)?.steps ?? 0) - (at(early.at)?.steps ?? 0),
      stepsAfter: after.length > 1 ? after.at(-1).steps - after[0].steps : 0,
      stepsPerSecondAfter: after.length > 1
        ? round((after.at(-1).steps - after[0].steps) / (after.at(-1).monotonic - after[0].monotonic), 1) : null,
      // A line is printed on its step and reaches the page within one output batch.
      wallClockOffsetsMs: after.slice(-5).map(line => round(line.wall * 1000 - line.pageWall)),
      events: await bench(a, from => window.bench.eventsSince(from), before.at),
      failures: await bench(a, () => window.bench.failures()),
      logs,
    };
    out.passed = early.visibility === 'hidden' && back.visibility === 'visible' && back.state === 'running' &&
      out.failures.length === 0 && out.stepsAfter > 0;
    await bench(a, () => window.bench.stop());
    console.log(`  hidden ${round(hiddenMs / 1000, 1)} s: ${out.passed ? 'pass' : 'FAIL'}; while hidden ${early.visibility}, emulator running ` +
      `${early.emulatorRunning}/${late.emulatorRunning}, ${out.stepsWhileHidden} steps; back ${back.visibility} ${back.state}, ` +
      `${out.stepsPerSecondAfter} steps/s, wall clock off ${out.wallClockOffsetsMs.join('/')} ms; failures ${out.failures.length}`);
    return out;
  });
}

// Running it

try {
  if (wanted('node')) {
    console.log('node: the same programs through openVm() under Node');
    results.node = await nodeBaseline();
    console.log(`  ready ${results.node.readyMs} ms; windows ${results.node.runs.map(r => `${r.name} ${r.windowMs}`).join(', ')}; speed ${results.node.speed.join('/')}/s`);
    save();
  }
  if (wanted('matrix')) {
    console.log('matrix: cold and warm loads');
    results.matrix = await matrix();
    save();
  }
  if (wanted('download')) {
    console.log('download: Range pieces against one GET, and interrupted downloads');
    results.download = await downloads();
    save();
  }
  const needsWarm = SECTIONS.slice(3).some(wanted);
  const warm = needsWarm ? await warmProfile() : null;
  if (wanted('micro')) {
    console.log('micro: Cache Storage and the wasm compile');
    results.micro = await micro(warm);
    save();
  }
  if (wanted('restore')) {
    console.log('restore: zstd, raw and a worker');
    results.restore = await restore(warm);
    save();
  }
  if (wanted('park')) {
    console.log('park: the host\'s own park, from the raw state');
    results.park = await park(warm);
    save();
  }
  if (wanted('frames')) {
    console.log('frames: the main thread while programs run');
    results.frames = await frames(warm);
    save();
  }
  if (wanted('frame-load')) {
    console.log(`frame-load: the main thread with ${FRAME_WORK_MS} ms of the page's own work a frame`);
    results.frameLoad = await frameLoad(warm);
    save();
  }
  if (wanted('window-delay')) {
    console.log('window-delay: WINDOW with and without the agent woken');
    results.windowDelay = await windowDelay(warm);
    save();
  }
  if (wanted('memory')) {
    console.log('memory: one tab and two');
    results.memory = await memory(warm);
    save();
  }
  if (wanted('app')) {
    console.log('app: the app from build/web/, alone and beside the VM');
    results.app = await app(warm);
    save();
  }
  if (wanted('raw-memory')) {
    console.log('raw-memory: the zstd state against a raw one');
    results.rawMemory = await rawMemory(warm);
    save();
  }
  if (wanted('raw-cache')) {
    console.log('raw-cache: a raw state read back from Cache Storage');
    results.rawCache = await rawCache(warm);
    save();
  }
  if (wanted('input')) {
    console.log('input: clicks and keys through Chrome into Tk');
    results.input = await input(warm);
    save();
  }
  if (wanted('hidden')) {
    console.log('hidden: a run in a tab that goes to the background');
    results.hidden = await hidden(warm);
    save();
  }
  if (wanted('sweep')) {
    console.log(`sweep: CPU throttling ${sweepRates.join(', ')}x`);
    results.sweep = await sweep(warm);
    save();
  }
  if (warm) fs.rmSync(warm, { recursive: true, force: true });
} finally {
  results.finishedAt = new Date().toISOString();
  results.freeKbAtEnd = freeKb();
  save();
  await server.close();
  console.log(`Wrote ${path.relative(repoDir, opts.out)}`);
}
