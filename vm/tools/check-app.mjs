// The app from build/web/ in headless Chrome, driven the way a student drives it: the catalog, the
// Tkinter page and its machine, real clicks and keys into Tk, Stop, leaving the page, Flutter UI
// drawn over the display, and the display cropped to the program's windows at full size and shrunk.
// Writes vm/build/check-app.json and screenshots to vm/build/check-app/, and exits 1 if a check
// failed.
//
// Usage: node check-app.mjs [--root build/web] [--base /] [--lesson ADDRESS --lesson-code CODE]
//                           [--chrome PATH] [--out FILE] [--shots DIR]
//
// Needs `just build` (build/web/ with web/vm/image/ copied in) and Google Chrome. --base is the
// build's --base-href. --lesson also runs one lesson step, such as
// `learn-python/uitvoer/zelf-printen` with --lesson-code 'print("Hallo")', and wants "Correct!".
//
// Flutter draws into a canvas, so the checks find things through the semantics tree on a survey
// page, then click by position on pages without semantics, as most students have them. The served
// vm/vm_host.js is a wrapper that re-exports the real one and copies every host event into
// window.__vmEvents: that is how a check reads output and why a run ended. Nothing else differs from
// the build.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { parseArgs } from 'node:util';

import puppeteer from 'puppeteer-core';

const toolsDir = path.dirname(new URL(import.meta.url).pathname);
const repoDir = path.resolve(toolsDir, '../..');

const { values: opts } = parseArgs({
  options: {
    root: { type: 'string', default: path.join(repoDir, 'build/web') },
    base: { type: 'string', default: '/' },
    lesson: { type: 'string' },
    'lesson-code': { type: 'string', default: 'print("Hallo")' },
    chrome: { type: 'string', default: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' },
    out: { type: 'string', default: path.join(repoDir, 'vm/build/check-app.json') },
    shots: { type: 'string', default: path.join(repoDir, 'vm/build/check-app') },
  },
});
const BASE = opts.base.endsWith('/') ? opts.base : `${opts.base}/`;

/** The task's floor: stop well before the disk fills. */
const MIN_FREE_KB = 5_767_168;

const statfs = fs.statfsSync('/Users');
if (statfs.bavail * statfs.bsize / 1024 < MIN_FREE_KB) {
  console.error(`DISK_LOW: under ${MIN_FREE_KB} KB free on /Users.`);
  process.exit(3);
}
if (!fs.existsSync(path.join(opts.root, 'main.dart.js')) || !fs.existsSync(path.join(opts.root, 'vm/image/manifest.json'))) {
  console.error(`${opts.root} has no build with a VM bundle in it; run \`just build\` after \`just build-vm-image\` or \`just fetch-vm-image\`.`);
  process.exit(2);
}
fs.mkdirSync(opts.shots, { recursive: true });

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const log = (...parts) => console.log(new Date().toISOString().slice(11, 23), ...parts);

const results = { startedAt: new Date().toISOString(), checks: [], numbers: {}, memory: [], screenshots: [], console: [] };
function check(name, passed, detail) {
  results.checks.push({ name, passed, detail });
  log(passed ? 'PASS' : 'FAIL', name, '-', detail);
}

// The server: the build under BASE, with the headers the app's dev server sends.

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.md': 'text/markdown',
  '.css': 'text/css', '.zip': 'application/zip',
};

const TEE = `export * from './vm_host.js?real';
import { openVm as realOpenVm } from './vm_host.js?real';
export function openVm(options) {
  const events = (globalThis.__vmEvents ??= []);
  const onEvent = options.onEvent;
  const vm = realOpenVm({ ...options, onEvent: event => { events.push({ ...event, at: performance.now() }); onEvent?.(event); } });
  // Weak: a strong reference here would keep a destroyed machine's memory alive and fail the check on it.
  (globalThis.__vms ??= []).push(new WeakRef(vm));
  return vm;
}
`;

const served = { requests: 0, stateRequests: 0, rootfsRequests: 0, notFound: [] };
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://x');
  let urlPath = decodeURIComponent(url.pathname);
  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  response.setHeader('Cache-Control', 'no-cache');
  if (!urlPath.startsWith(BASE)) {
    response.writeHead(404);
    response.end();
    return;
  }
  urlPath = urlPath.slice(BASE.length);
  if (urlPath === 'vm/vm_host.js' && !url.searchParams.has('real')) {
    response.writeHead(200, { 'Content-Type': 'text/javascript', 'Content-Length': Buffer.byteLength(TEE) });
    response.end(TEE);
    return;
  }
  let file = path.join(opts.root, urlPath);
  let stat = null;
  try {
    stat = fs.statSync(file);
    if (stat.isDirectory()) {
      file = path.join(file, 'index.html');
      stat = fs.statSync(file);
    }
  } catch {
    stat = null;
  }
  if (!stat) {
    served.notFound.push(urlPath);
    response.writeHead(404);
    response.end('Not found');
    return;
  }
  const etag = `"${stat.size}-${stat.mtimeMs}"`;
  response.setHeader('ETag', etag);
  if (request.headers['if-none-match'] === etag) {
    response.writeHead(304);
    response.end();
    return;
  }
  served.requests++;
  if (urlPath.endsWith('state.bin.zst')) served.stateRequests++;
  if (urlPath.includes('/rootfs/')) served.rootfsRequests++;
  const type = TYPES[path.extname(file)] ?? 'application/octet-stream';
  // A single Range gets a 206, as GitHub Pages answers it, so the state comes
  // down in the pieces the host keeps.
  const range = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? '');
  if (range) {
    const start = Number(range[1]);
    const end = range[2] === '' ? stat.size - 1 : Math.min(Number(range[2]), stat.size - 1);
    if (start > end) {
      response.writeHead(416, { 'Content-Range': `bytes */${stat.size}` });
      response.end();
      return;
    }
    served.ranges = (served.ranges ?? 0) + 1;
    response.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Content-Length': end - start + 1 });
    fs.createReadStream(file, { start, end }).pipe(response);
    return;
  }
  response.writeHead(200, { 'Content-Type': type, 'Content-Length': stat.size });
  fs.createReadStream(file).pipe(response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const appUrl = `http://127.0.0.1:${server.address().port}${BASE}`;
log('serving', opts.root, 'at', appUrl);

const profile = path.join(opts.shots, `profile-${Date.now()}`);
const browser = await puppeteer.launch({
  executablePath: opts.chrome,
  headless: true,
  userDataDir: profile,
  protocolTimeout: 300_000,
  defaultViewport: { width: 1440, height: 1000, deviceScaleFactor: 1 },
  args: [
    '--lang=en-US',
    // measureUserAgentSpecificMemory otherwise waits for the next GC, up to 20 s.
    '--enable-blink-features=ForceEagerMeasureMemory',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-component-update',
    '--window-size=1440,1000',
  ],
});
results.chrome = await browser.version();

function watch(page, label) {
  page.on('console', message => {
    const text = message.text();
    // Our own getImageData readbacks, not the app.
    if (text.includes('willReadFrequently')) return;
    if (['error', 'warn', 'warning'].includes(message.type())) results.console.push(`${label} ${message.type()}: ${text.slice(0, 400)}`);
  });
  page.on('pageerror', error => results.console.push(`${label} pageerror: ${error.message.slice(0, 400)}`));
}

async function shot(page, name) {
  const file = path.join(opts.shots, name);
  await page.screenshot({ path: file });
  results.screenshots.push(file);
}

// The semantics tree

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 60_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.waitForSelector('flt-semantics-host flt-semantics', { timeout: 20_000 });
}

/** The smallest semantics element whose label or own text holds `text`, as a rect, or null. */
async function findText(page, text, { exact = false, timeout = 20_000, visible = true } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const rect = await page.evaluate((text, exact, visible) => {
      const host = document.querySelector('flt-semantics-host');
      if (!host) return null;
      const match = value => typeof value === 'string' && (exact ? value.trim() === text : value.includes(text));
      let best = null;
      for (const element of host.querySelectorAll('*')) {
        const label = element.getAttribute('aria-label');
        const own = [...element.childNodes].filter(node => node.nodeType === 3).map(node => node.textContent).join('');
        if (!match(label) && !match(own)) continue;
        const r = element.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;
        if (visible && (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth)) continue;
        const area = r.width * r.height;
        if (!best || area < best.area) best = { x: r.x, y: r.y, w: r.width, h: r.height, area, text: label ?? own };
      }
      return best;
    }, text, exact, visible);
    if (rect || Date.now() > deadline) return rect;
    await sleep(100);
  }
}

/** findText once the rect stops moving: screens slide in, and a rect read mid-slide is not where a later click lands. */
async function findSettled(page, text, options = {}) {
  let last = await findText(page, text, options);
  for (let i = 0; i < 20 && last; i++) {
    await sleep(250);
    const now = await findText(page, text, { ...options, timeout: 2000 });
    if (now && Math.abs(now.x - last.x) < 1 && Math.abs(now.y - last.y) < 1) return now;
    last = now;
  }
  return last;
}

const hasText = async (page, text) => (await findText(page, text, { timeout: 0, visible: false })) !== null;
const waitText = (page, text, timeout = 20_000) => findText(page, text, { timeout, visible: false });

async function clickRect(page, rect) {
  await page.mouse.click(rect.x + rect.w / 2, rect.y + rect.h / 2);
}

async function clickText(page, text, options) {
  const rect = await findText(page, text, options);
  if (!rect) throw new Error(`no "${text}" on screen`);
  await clickRect(page, rect);
}

// The display: v86's canvas, read back as the student sees it

/** The dialog's frame, from WindowFrame and ProgramDialog: a strip over a bezel, never narrower
 *  than `minInside`, with the cross at the strip's right behind its own padding. */
const FRAME = { strip: 44, bezel: 10, minInside: 320, close: 32, rightPad: 6 };

/** The box the display is laid out in, which the crop sits centred in. Null with no dialog up. */
async function viewBox(page) {
  return page.evaluate(() => {
    const view = document.querySelector('.icc-vm-view');
    if (!view?.isConnected) return null;
    const r = view.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  });
}

/** Where the cross that ends the program is, worked out from the display's own box. */
async function stopPoint(page) {
  const view = await viewBox(page);
  if (!view) return null;
  const inside = Math.max(view.width, FRAME.minInside);
  const right = view.left + view.width / 2 + inside / 2 + FRAME.bezel;
  return { x: right - FRAME.rightPad - FRAME.close / 2, y: view.top - FRAME.strip / 2 };
}

/** Ends the program the way a student does, with the cross on the dialog. */
async function clickStop(page) {
  const point = await stopPoint(page);
  if (!point) throw new Error('no program dialog to stop');
  await page.mouse.click(point.x, point.y);
}

/** Waits for the dialog to go, which is what the end of a run looks like. */
async function waitDialogGone(page, timeout = 10_000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await viewBox(page)) === null) return Date.now() - t0;
    await sleep(20);
  }
  return null;
}

async function screenBox(page) {
  return page.evaluate(() => {
    const canvas = document.querySelector('.icc-vm-screen > canvas');
    if (!canvas?.isConnected) return null;
    const r = canvas.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height, cw: canvas.width, ch: canvas.height };
  });
}

/**
 * The window at +0+0, where a window with no geometry of its own opens with no window manager: its
 * size, found where the black root begins; a checksum of all but its bottom `cut` rows; and `bottom`,
 * the lowest row in the middle column that is not the window's background, which is the starter
 * program's button.
 */
async function tkWindow(page, cut = 0) {
  return page.evaluate(cut => {
    const canvas = document.querySelector('.icc-vm-screen > canvas');
    if (!canvas?.width) return null;
    const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
    const px = (x, y) => { const i = (y * canvas.width + x) * 4; return [data[i], data[i + 1], data[i + 2]]; };
    const black = p => p[0] < 6 && p[1] < 6 && p[2] < 6;
    if (black(px(3, 3))) return { w: 0, h: 0, sum: 0, bottom: -1 };
    let w = 0;
    while (w < canvas.width && !black(px(w, 3))) w++;
    let h = 0;
    while (h < canvas.height && !black(px(3, h))) h++;
    let sum = 0;
    for (let y = 0; y < Math.max(0, h - cut); y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * canvas.width + x) * 4;
        sum = (sum * 31 + data[i] + data[i + 1] * 3 + data[i + 2] * 7) >>> 0;
      }
    }
    const bg = px(3, h - 2);
    let bottom = -1;
    for (let y = h - 2; y > 0; y--) {
      const p = px(Math.floor(w / 2), y);
      if (Math.abs(p[0] - bg[0]) + Math.abs(p[1] - bg[1]) + Math.abs(p[2] - bg[2]) > 30) {
        bottom = y;
        break;
      }
    }
    return { w, h, sum, bottom };
  }, cut);
}

async function waitWindow(page, timeout = 20_000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const w = await tkWindow(page);
    if (w && w.w > 20 && w.h > 20) return w;
    await sleep(20);
  }
  return null;
}

/** The window once two looks 300 ms apart agree: a slow machine is caught part way through drawing it. */
async function waitSettled(page, timeout = 30_000) {
  const t0 = Date.now();
  let last = null;
  while (Date.now() - t0 < timeout) {
    const w = await tkWindow(page);
    if (w && w.w > 20 && w.bottom > 0 && last && w.sum === last.sum && w.w === last.w) return w;
    last = w;
    await sleep(300);
  }
  return null;
}

/** Waits until the window's checksum or width differs from `before`, and says how long that took. */
async function waitChanged(page, before, timeout = 6000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const w = await tkWindow(page, 50);
    if (w.sum !== before.sum || w.w !== before.w) return { ...w, ms: Date.now() - t0 };
    await sleep(15);
  }
  return null;
}

async function clickGuest(page, gx, gy) {
  const box = await screenBox(page);
  const scale = box.width / box.cw;
  await page.mouse.click(box.left + gx * scale, box.top + gy * scale);
}

/** The guest pixel under page point (x, y), or null when the point is not over the display. */
async function guestAt(page, x, y) {
  const box = await screenBox(page);
  const scale = box.width / box.cw;
  const gx = Math.floor((x - box.left) / scale);
  const gy = Math.floor((y - box.top) / scale);
  return gx >= 0 && gy >= 0 && gx < box.cw && gy < box.ch ? { gx, gy } : null;
}

/**
 * What the display shows of the guest's screen: its size on the page, the scale, and the part of the
 * screen in guest pixels, all read back from the DOM that v86 maps clicks through. Null without one.
 */
async function displayCrop(page) {
  return page.evaluate(() => {
    const crop = document.querySelector('.icc-vm-crop');
    const canvas = crop?.querySelector('canvas');
    if (!crop?.isConnected || !canvas?.width) return null;
    const view = crop.parentElement.getBoundingClientRect();
    const drawn = canvas.getBoundingClientRect();
    const scale = drawn.width / canvas.width;
    return {
      width: view.width, height: view.height, scale,
      x: (view.left - drawn.left) / scale, y: (view.top - drawn.top) / scale,
      w: view.width / scale, h: view.height / scale,
      pixelated: getComputedStyle(canvas).imageRendering === 'pixelated',
    };
  });
}

/** The page's rule: the smallest rectangle around every mapped window, each clipped to the screen. */
function regionOf(windows, screen = { w: 800, h: 600 }) {
  let box = null;
  for (const w of windows ?? []) {
    if (!w.mapped) continue;
    const left = Math.max(0, w.x), top = Math.max(0, w.y);
    const right = Math.min(screen.w, w.x + w.w), bottom = Math.min(screen.h, w.y + w.h);
    if (right <= left || bottom <= top) continue;
    box = box
      ? { left: Math.min(box.left, left), top: Math.min(box.top, top), right: Math.max(box.right, right), bottom: Math.max(box.bottom, bottom) }
      : { left, top, right, bottom };
  }
  return box && { x: box.left, y: box.top, w: box.right - box.left, h: box.bottom - box.top };
}

/** The region the last WINDOW since `from` asks for. */
async function latestRegion(page, from) {
  const last = (await eventsSince(page, from)).filter(event => event.type === 'window').at(-1);
  return last ? regionOf(last.windows) : null;
}

/** Within one CSS pixel of showing `region`, however it is scaled. */
const shows = (crop, region) => !!crop && !!region && ['x', 'y', 'w', 'h'].every(key => Math.abs(crop[key] - region[key]) * crop.scale < 1);

async function waitCrop(page, region, timeout = 3000) {
  const t0 = Date.now();
  let crop = null;
  while (Date.now() - t0 < timeout) {
    crop = await displayCrop(page);
    if (shows(crop, region)) return { ...crop, ms: Date.now() - t0 };
    await sleep(20);
  }
  return null;
}

const describeCrop = crop => crop
  ? `${Math.round(crop.w)}x${Math.round(crop.h)}+${Math.round(crop.x)}+${Math.round(crop.y)} guest px at scale ${crop.scale.toFixed(3)}, ${Math.round(crop.width)}x${Math.round(crop.height)} CSS px`
  : 'no display';

const describeRegion = region => region ? `${region.w}x${region.h}+${region.x}+${region.y}` : 'none';

async function guestPixel(page, gx, gy) {
  return page.evaluate(([gx, gy]) => {
    const canvas = document.querySelector('.icc-vm-screen > canvas');
    return canvas ? [...canvas.getContext('2d').getImageData(gx, gy, 1, 1).data.slice(0, 3)] : null;
  }, [gx, gy]);
}

async function waitPixel(page, gx, gy, want, timeout) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const pixel = await guestPixel(page, gx, gy);
    if (pixel && want(pixel)) return Date.now() - t0;
    await sleep(20);
  }
  return null;
}

const isBlue = p => p[0] < 60 && p[2] > 150;
const isRed = p => p[0] > 180 && p[1] < 40 && p[2] < 40;

// Keys and the editor

/**
 * Types `text` the way a person does. Puppeteer's own type() sends a capital without pressing Shift,
 * and v86 goes by the physical key, so the guest would see a lower-case letter.
 */
async function typeLikeAPerson(page, text) {
  for (const char of text) {
    if (/[A-Z]/.test(char)) {
      await page.keyboard.down('Shift');
      await page.keyboard.press(`Key${char}`);
      await page.keyboard.up('Shift');
    } else {
      await page.keyboard.type(char);
    }
    await sleep(25);
  }
}

/**
 * Replaces what the code editor holds, one line at a time through insertText, as an IME delivers
 * text: re_editor pairs brackets and quotes typed key by key, and edits through a one-line input.
 * The editor keeps the previous line's indent, so the programs below are flat.
 */
async function setEditor(page, point, source) {
  await page.mouse.click(point.x, point.y);
  await sleep(200);
  await page.keyboard.down('Meta');
  await page.keyboard.press('KeyA');
  await page.keyboard.up('Meta');
  await page.keyboard.press('Backspace');
  const lines = source.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) await page.keyboard.press('Enter');
    if (lines[i]) await page.keyboard.sendCharacter(lines[i]);
    await sleep(30);
  }
  await sleep(300);
}

// Host events, through the tee

const eventMark = page => page.evaluate(() => (globalThis.__vmEvents ?? []).length);
const eventsSince = (page, from) => page.evaluate(from => JSON.parse(JSON.stringify((globalThis.__vmEvents ?? []).slice(from))), from);
const pageNow = page => page.evaluate(() => performance.now());
const outputOf = events => events.filter(event => event.type === 'output').map(event => event.text).join('');

async function waitEvent(page, from, predicate, timeout = 20_000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const events = await eventsSince(page, from);
    const hit = events.find(predicate);
    if (hit) return { event: hit, events };
    await sleep(20);
  }
  return null;
}

// Memory

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
    type: /--type=(\S+)/.exec(row.command)?.[1] ?? 'browser',
    rssMiB: Math.round(row.rssKiB / 1024),
    footprintMiB: footprint(row.pid),
  }));
}

function footprint(pid) {
  try {
    const text = execFileSync('footprint', ['--noCategories', String(pid)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const found = /Footprint:\s*([\d.]+)\s*(B|KB|MB|GB)/.exec(text);
    return found ? Math.round(Number(found[1]) * { B: 1 / 2 ** 20, KB: 1 / 1024, MB: 1, GB: 1024 }[found[2]]) : null;
  } catch {
    return null;
  }
}

/** The page's JS and wasm heap after a garbage collection, and the largest renderer's footprint and RSS. */
async function memory(page, label) {
  const cdp = await page.createCDPSession();
  await cdp.send('HeapProfiler.collectGarbage');
  await sleep(1500);
  await cdp.send('HeapProfiler.collectGarbage');
  await cdp.detach();
  const bytes = await page.evaluate(async () => (await performance.measureUserAgentSpecificMemory()).bytes);
  const processes = chromeProcesses(browser.process().pid);
  const renderer = processes.filter(p => p.type === 'renderer').sort((a, b) => (b.footprintMiB ?? 0) - (a.footprintMiB ?? 0))[0];
  const out = {
    label,
    heapMiB: Number((bytes / 2 ** 20).toFixed(1)),
    rendererFootprintMiB: renderer?.footprintMiB ?? null,
    rendererRssMiB: renderer?.rssMiB ?? null,
    chromeFootprintMiB: processes.reduce((sum, p) => sum + (p.footprintMiB ?? 0), 0),
  };
  log('memory', JSON.stringify(out));
  results.memory.push(out);
  return out;
}

// The programs

const ENTRY_PROGRAM = [
  'import tkinter as tk',
  'root = tk.Tk()',
  'root.title("Input")',
  'e = tk.Entry(root, width=30)',
  'e.pack(padx=20, pady=20)',
  'e.focus_set()',
  'e.bind("<Return>", lambda event: print("typed:", e.get(), flush=True))',
  'root.mainloop()',
].join('\n');

const LOOP_PROGRAM = 'print("started", flush=True)\nwhile True: pass';

const TRACEBACK_PROGRAM = 'def divide(a, b): return a / b\nprint("before the error")\nprint(divide(1, 0))';

const NO_MAINLOOP_PROGRAM = 'import tkinter as tk\nroot = tk.Tk()\ntk.Label(root, text="hi").pack()';

/** Fills the screen, and turns red and says where when clicked: whether a click reached the guest. */
const CLICK_PROGRAM = [
  'import tkinter as tk',
  'root = tk.Tk()',
  'root.geometry("800x600+0+0")',
  'root.configure(bg="#2255aa")',
  'root.bind("<Button-1>", lambda e: (root.configure(bg="#cc0000"), print("click", e.x, e.y, flush=True)))',
  'root.mainloop()',
].join('\n');

/** A small window whose button asks a question in a messagebox, and says what came back. */
const DIALOG_PROGRAM = [
  'import tkinter as tk',
  'from tkinter import messagebox',
  'root = tk.Tk()',
  'root.title("Small")',
  'def ask():',
  '    answer = messagebox.showinfo("Hello", "A messagebox is wider than this window.")',
  '    print("answer", answer, flush=True)',
  'tk.Button(root, text="Ask", command=ask).pack(padx=12, pady=12)',
  'root.mainloop()',
].join('\n');

/** A canvas far larger than the screen, which says where each click landed in it. */
const BIG_CANVAS_PROGRAM = [
  'import tkinter as tk',
  'root = tk.Tk()',
  'root.title("Big canvas")',
  'c = tk.Canvas(root, width=1920, height=1080, bg="#2255aa", highlightthickness=0)',
  'c.pack()',
  'c.create_line(0, 300, 1920, 300, fill="white")',
  'c.bind("<Button-1>", lambda e: print("click", e.x, e.y, flush=True))',
  'root.mainloop()',
].join('\n');

const DRAFT_KEY = 'draft.tkinter.python';

/** Sets the Tkinter page's draft before the app starts, which puts `source` in its editor. */
const withDraft = (page, source) => page.evaluateOnNewDocument((key, source) => {
  if (source === null) localStorage.removeItem(key);
  else localStorage.setItem(key, JSON.stringify(source));
}, DRAFT_KEY, source);

// Survey: with semantics on, where everything is, and what a screen reader is told

async function survey() {
  const page = await browser.newPage();
  watch(page, 'survey');
  await withDraft(page, null);
  const layout = {};
  await page.goto(appUrl, { waitUntil: 'load' });
  await enableSemantics(page);

  // The initialization screen says "Starting Python" first.
  await waitText(page, 'What do you want to learn?', 60_000);
  layout.python = await findSettled(page, 'Python');
  await clickRect(page, layout.python);
  const heading = await waitText(page, 'Extra', 10_000);
  layout.scrollSteps = 0;
  let card = await findSettled(page, 'Windows with Tkinter', { timeout: 500 });
  while (!(card && card.y > 80 && card.y + card.h < 950) && layout.scrollSteps < 12) {
    await page.mouse.move(700, 600);
    await page.mouse.wheel({ deltaY: 400 });
    layout.scrollSteps++;
    await sleep(400);
    card = await findSettled(page, 'Windows with Tkinter', { timeout: 500 });
  }
  layout.card = card;
  check('the catalog lists the Tkinter page under Extra', !!card && !!heading, card ? `after ${layout.scrollSteps} wheel steps`
    : 'no card: was the build made without --dart-define=ICC_VM_IMAGE=true? `just build` passes it when web/vm/image/ holds a bundle');
  if (!card) throw new Error('no Tkinter card');

  await clickRect(page, card);
  const opened = await page.waitForFunction(() => location.href.includes('learn-python/tkinter'), { timeout: 10_000 }).then(() => true, () => false);
  check('the card opens the Tkinter page', opened, await page.evaluate(() => location.href));
  const ready = await waitText(page, 'Tk 8.6', 60_000);
  check('the editor names the machine once it is ready', !!ready, `"${ready?.text}"`);

  layout.run = await findSettled(page, 'Run', { exact: true });
  const editorLabel = await findSettled(page, 'main.py', { exact: true });
  layout.editorPoint = { x: editorLabel.x + 200, y: editorLabel.y + 120 };
  check('the page holds no screen until a program runs', (await viewBox(page)) === null, 'no .icc-vm-view before Run');

  const from = await eventMark(page);
  await clickRect(page, layout.run);
  const win = await waitSettled(page);
  const title = await waitText(page, 'Mijn eerste venster', 5000);
  await sleep(500);
  const focus = await page.evaluate(() => document.activeElement?.className || document.activeElement?.tagName);
  const hint = await hasText(page, 'Esc, then Tab');
  check('with semantics on, the dialog reads the window\'s title', !!win && !!title, `window ${win?.w}x${win?.h}; "${title?.text}"`);
  check('with semantics on, Run moves the keyboard into the display', focus === 'icc-vm-view' && hint, `DOM focus on ${focus}; leave hint shown: ${hint}`);
  if (win) {
    const before = await tkWindow(page, 50);
    await clickGuest(page, Math.floor(win.w / 2), win.bottom - 12);
    const after = await waitChanged(page, before);
    check('with semantics on, a click reaches the Tk button', !!after, after ? `${after.ms} ms` : 'the label never changed');
  }
  // The cross is found by what a screen reader is told here, and by geometry on every page without
  // semantics, so the two are held against each other once.
  const cross = await findText(page, 'Stop the program', { exact: true, timeout: 3000 });
  const guessed = await stopPoint(page);
  const close = cross && guessed && Math.abs(cross.x + cross.w / 2 - guessed.x) < 4 && Math.abs(cross.y + cross.h / 2 - guessed.y) < 4;
  check('the cross that ends the program is where the frame\'s own measurements put it', !!close,
    `read ${cross ? `${Math.round(cross.x + cross.w / 2)},${Math.round(cross.y + cross.h / 2)}` : 'nothing'}; worked out ${guessed ? `${Math.round(guessed.x)},${Math.round(guessed.y)}` : 'nothing'}`);
  await clickRect(page, cross);
  await waitEvent(page, from, event => event.type === 'parked', 10_000);
  await page.close();
  return layout;
}

// The page as most students have it: no semantics, everything by position

async function main(layout) {
  const page = await browser.newPage();
  watch(page, 'main');
  await withDraft(page, null);
  await page.goto(appUrl, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view', { timeout: 60_000 });
  // No semantics to wait on here, so the picker is clicked until the address says it went.
  const atCatalog = () => page.evaluate(() => /learn-python\/?$/.test(location.href));
  for (let i = 0; i < 30 && !(await atCatalog()); i++) {
    await sleep(1000);
    await clickRect(page, layout.python);
  }
  await sleep(1000);
  for (let i = 0; i < layout.scrollSteps; i++) {
    await page.mouse.move(700, 600);
    await page.mouse.wheel({ deltaY: 400 });
    await sleep(400);
  }
  await memory(page, 'the catalog');

  // A cold cache and a 20 Mbit/s line, so the download is seen.
  await page.evaluate(async () => {
    for (const key of await caches.keys()) await caches.delete(key);
  });
  const cdp = await page.createCDPSession();
  await cdp.send('Network.clearBrowserCache');
  await cdp.detach();
  await page.emulateNetworkConditions({ download: 20e6 / 8, upload: 10e6 / 8, latency: 20 });
  const opened = Date.now();
  await clickRect(page, layout.card);
  const onPage = await page.waitForFunction(() => location.href.includes('learn-python/tkinter'), { timeout: 5000 }).then(() => true, () => false);
  if (!onPage) {
    await shot(page, 'no-tkinter-page.png');
    throw new Error(`the card did not open the Tkinter page: ${await page.evaluate(() => location.href)}`);
  }
  await sleep(2500);
  const progress = (await eventsSince(page, 0)).filter(event => event.type === 'progress').at(-1);
  await shot(page, 'loading-panel.png');
  check('the loading panel shows the download', !!progress && progress.loaded < progress.total, progress ? `${progress.loaded} of ${progress.total} B after 2.5 s` : 'no progress');
  const measured = await waitEvent(page, 0, event => event.type === 'progress' && event.phase === 'download' && event.rate !== null && event.remainingMs !== null, 8000);
  if (measured) await shot(page, 'loading-panel-speed.png');
  check('the download measures its speed and the time left while it runs', !!measured && measured.event.loaded < measured.event.total,
    measured ? `${(measured.event.rate / 1e6).toFixed(2)} MB/s on a 2.5 MB/s line, ${(measured.event.remainingMs / 1000).toFixed(1)} s left at ${measured.event.loaded} of ${measured.event.total} B` : 'no speed within 8 s');
  await page.emulateNetworkConditions(null);
  const ready = await waitEvent(page, 0, event => event.type === 'ready' || event.type === 'failed', 60_000);
  results.numbers.coldOpenToReadyMs = Date.now() - opened;
  check('the machine becomes ready', ready?.event.type === 'ready', `${ready?.event.python} and Tk ${ready?.event.tk}, ${results.numbers.coldOpenToReadyMs} ms after the click`);
  const phases = (await eventsSince(page, 0)).filter(event => event.type === 'progress').map(event => event.phase);
  const kept = await page.evaluate(async () => (await (await caches.open('icc-vm')).keys()).map(request => request.url).filter(url => url.includes('state.bin.zst')));
  check('the state comes down in Range pieces, each kept in the Cache API, then unpacks and starts',
    kept.length > 1 && kept.every(url => /\?bytes=\d+-\d+$/.test(url)) && phases.join(' ').endsWith('download unpack start'),
    `${kept.length} pieces kept, ${served.ranges ?? 0} Range answers; phases ${[...new Set(phases)].join(', ')}`);
  await sleep(500);
  const parkedOnArrival = await memory(page, 'the Tkinter page, parked');

  // The starter program
  let from = await eventMark(page);
  const t0 = Date.now();
  await clickRect(page, layout.run);
  const first = await waitWindow(page);
  results.numbers.runToWindowOnCanvasMs = first ? Date.now() - t0 : null;
  const listed = await waitEvent(page, from, event => event.type === 'window' && event.windows.some(w => w.mapped), 5000);
  const root = listed?.event.windows.find(w => w.root);
  check('Run draws the starter program\'s window in the display', !!first && root?.title === 'Mijn eerste venster',
    `${results.numbers.runToWindowOnCanvasMs} ms after Run; WINDOW lists "${root?.title}" ${root?.w}x${root?.h}`);
  const starterRegion = await latestRegion(page, from);
  const starterCrop = await waitCrop(page, starterRegion);
  check('the display shows the starter program\'s window alone, at its real size', !!starterCrop && starterCrop.scale === 1 && starterCrop.pixelated,
    `${describeCrop(starterCrop ?? await displayCrop(page))}; WINDOW asks for ${describeRegion(starterRegion)}; pixelated ${starterCrop?.pixelated}`);
  const focused = await page.evaluate(() => document.activeElement?.classList.contains('icc-vm-view'));
  check('Run moves DOM focus into the display', focused, await page.evaluate(() => document.activeElement?.className || document.activeElement?.tagName));
  await sleep(300);
  await shot(page, 'starter-running.png');

  const win = await waitSettled(page);
  if (win) {
    const before = await tkWindow(page, 50);
    await clickGuest(page, Math.floor(win.w / 2), win.bottom - 12);
    const once = await waitChanged(page, before);
    results.numbers.clickToLabelMs = once?.ms ?? null;
    check('a real click on the Tk button changes its label', !!once, once ? `${before.w} -> ${once.w} wide in ${once.ms} ms` : 'the label never changed');
    const settled = await waitSettled(page);
    const again = await tkWindow(page, 50);
    await clickGuest(page, Math.floor(settled.w / 2), settled.bottom - 12);
    const twice = await waitChanged(page, again);
    check('a second click changes it again', !!twice, twice ? `${twice.ms} ms` : 'unchanged');
    const followed = await waitEvent(page, from, event => event.type === 'window' && event.windows.some(w => w.root && w.w === settled.w), 3000);
    check('WINDOW follows the window as its label grows', !!followed, `root ${settled.w} wide`);
    const grown = await waitCrop(page, regionOf(followed?.event.windows));
    check('the display follows the window as it grows', !!grown && grown.scale === 1 && starterCrop && grown.w > starterCrop.w,
      `${describeCrop(grown ?? await displayCrop(page))}, ${grown?.ms} ms after this check first looked; it was ${Math.round(starterCrop?.w)} wide`);
    await sleep(200);
    await shot(page, 'starter-clicked-twice.png');
  }

  let tStop = await pageNow(page);
  await clickStop(page);
  const stopped = await waitEvent(page, from, event => event.type === 'ended', 5000);
  const parked = await waitEvent(page, from, event => event.type === 'parked', 10_000);
  const closed = await waitDialogGone(page, 5000);
  check('the cross ends the program, parks the machine and closes the dialog', stopped?.event.reason === 'stopped' && !!parked && closed !== null,
    `ended "${stopped?.event.reason}" ${Math.round(stopped?.event.at - tStop)} ms after the click, parked after ${Math.round(parked?.event.at - tStop)} ms, dialog gone after ${closed} ms`);

  // Keys into an Entry, and the way out
  await setEditor(page, layout.editorPoint, ENTRY_PROGRAM);
  from = await eventMark(page);
  await clickRect(page, layout.run);
  const entry = await waitEvent(page, from, event => event.type === 'window' && event.windows.some(w => w.mapped && w.title === 'Input'), 20_000);
  await sleep(300);
  await typeLikeAPerson(page, 'Hello Sanne');
  await page.keyboard.press('Enter');
  const typed = await waitEvent(page, from, event => event.type === 'output' && event.text.includes('typed:'), 8000);
  check('keys typed after Run reach the Tk Entry, capitals included', !!entry && typed?.event.text === 'typed: Hello Sanne\n', `output ${JSON.stringify(typed?.event.text)}`);
  await shot(page, 'entry-typed.png');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Tab');
  await sleep(300);
  const left = await page.evaluate(() => !document.activeElement?.classList.contains('icc-vm-view'));
  await page.keyboard.type('zz');
  await sleep(300);
  // Back in through the window's own margin, beside the Entry: Return then prints what it holds.
  const back = await eventMark(page);
  await clickGuest(page, 4, 4);
  await sleep(300);
  await page.keyboard.press('Enter');
  const line = await waitEvent(page, back, event => event.type === 'output', 5000);
  check('Escape then Tab leaves the display, and keys typed then stay out of the guest', left && line?.event.text === 'typed: Hello Sanne\n',
    `focus left: ${left}; Return after clicking back in printed ${JSON.stringify(line?.event.text)}`);
  await clickStop(page);
  await waitEvent(page, from, event => event.type === 'parked', 10_000);

  // while True
  await setEditor(page, layout.editorPoint, LOOP_PROGRAM);
  from = await eventMark(page);
  await clickRect(page, layout.run);
  const began = await waitEvent(page, from, event => event.type === 'output' && event.text.includes('started'), 10_000);
  await sleep(2000);
  const endedEarly = (await eventsSince(page, from)).some(event => event.type === 'ended');
  tStop = await pageNow(page);
  await clickStop(page);
  const loopEnded = await waitEvent(page, from, event => event.type === 'ended', 5000);
  const answered = await waitEvent(page, from, event => event.type === 'stop-answered', 5000);
  const loopParked = await waitEvent(page, from, event => event.type === 'parked', 10_000);
  results.numbers.busyStop = {
    endedMs: Math.round(loopEnded?.event.at - tStop),
    exitAfterStopMs: answered?.event.ms === null || answered?.event.ms === undefined ? null : Math.round(answered.event.ms),
    parkedMs: Math.round(loopParked?.event.at - tStop),
  };
  check('while True runs until Stop, and Stop ends it', !!began && !endedEarly && loopEnded?.event.reason === 'stopped' && !!loopParked,
    `still running after 2 s: ${!endedEarly}; ${JSON.stringify(results.numbers.busyStop)}`);

  // No mainloop()
  await setEditor(page, layout.editorPoint, NO_MAINLOOP_PROGRAM);
  from = await eventMark(page);
  await clickRect(page, layout.run);
  const hintEnded = await waitEvent(page, from, event => event.type === 'ended', 15_000);
  const hint = hintEnded?.events.find(event => event.type === 'hint');
  check('a program without mainloop() gets the hint', hint?.kind === 'tk_no_mainloop' && hintEnded.event.reason === 'exit', `hint ${hint?.kind}; ended ${hintEnded?.event.reason}`);
  await sleep(500);
  await shot(page, 'no-mainloop-hint.png');

  // A traceback, last, because turning semantics on to read the page leaves the editor untypeable.
  await setEditor(page, layout.editorPoint, TRACEBACK_PROGRAM);
  from = await eventMark(page);
  await clickRect(page, layout.run);
  const crashed = await waitEvent(page, from, event => event.type === 'ended', 15_000);
  const stderr = (crashed?.events ?? []).filter(event => event.type === 'output' && event.stream === 'stderr').map(event => event.text).join('');
  check('a traceback reaches the page, and starts at the program', crashed?.event.reason === 'exit' && crashed.event.code === 1 &&
    outputOf(crashed.events).startsWith('before the error') && stderr.includes('ZeroDivisionError') && !stderr.includes('prelude'),
    `ended ${crashed?.event.reason} code ${crashed?.event.code}; last line ${JSON.stringify(stderr.trim().split('\n').at(-1))}`);
  await sleep(500);
  await shot(page, 'traceback-notice.png');
  // The run is over, so its dialog is too: nothing of it is left holding the keyboard.
  const closedAfterCrash = await waitDialogGone(page, 5000);
  const focusAfterCrash = await page.evaluate(() => document.activeElement?.className || document.activeElement?.tagName || 'none');
  await enableSemantics(page);
  const notice = await waitText(page, 'Your program stopped with an error', 5000);
  const card = await waitText(page, 'ZeroDivisionError', 3000);
  check('the page shows the crash notice and the traceback', !!notice && !!card, `notice ${!!notice}; output card ${!!card}`);
  const staleHint = await hasText(page, 'Esc, then Tab');
  check('a program that ends takes its dialog with it, and nothing of it keeps the keyboard',
    closedAfterCrash !== null && !focusAfterCrash.includes('icc-vm-view') && !staleHint,
    `dialog gone after ${closedAfterCrash} ms; DOM focus on ${focusAfterCrash}; leave hint shown: ${staleHint}`);

  // Leaving the page
  const beforeLeaving = await memory(page, 'the Tkinter page, after the runs');
  await clickText(page, 'Python', { exact: true });
  await page.waitForFunction(() => /learn-python\/?$/.test(location.href), { timeout: 10_000 });
  await sleep(1500);
  const states = await page.evaluate(() => (globalThis.__vms ?? []).map(ref => ref.deref()?.state ?? 'collected'));
  const gone = await page.evaluate(() => document.querySelector('.icc-vm-screen') === null);
  const afterLeaving = await memory(page, 'the catalog, after leaving the Tkinter page');
  check('leaving the page destroys the machine and gives its memory back', gone && ['destroyed', 'collected'].includes(states.at(-1)) && afterLeaving.heapMiB < beforeLeaving.heapMiB - 100,
    `host ${states.at(-1)}; heap ${parkedOnArrival.heapMiB} parked, ${beforeLeaving.heapMiB} after the runs, ${afterLeaving.heapMiB} after leaving; renderer footprint ${beforeLeaving.rendererFootprintMiB} -> ${afterLeaving.rendererFootprintMiB} MiB`);

  // Back again: the bundle comes out of the Cache API
  const stateRequests = served.stateRequests;
  const t2 = Date.now();
  let again = null;
  for (let i = 0; i < 12 && !again; i++) {
    again = await findText(page, 'Windows with Tkinter', { timeout: 500 });
    if (again && (again.y < 80 || again.y + again.h > 950)) again = null;
    if (!again) {
      await page.mouse.move(700, 600);
      await page.mouse.wheel({ deltaY: 400 });
      await sleep(400);
    }
  }
  await clickRect(page, again);
  const readyAgain = await waitText(page, 'Tk 8.6', 30_000);
  results.numbers.secondVisitReadyMs = Date.now() - t2;
  check('a second visit is ready again without downloading the state', !!readyAgain && served.stateRequests === stateRequests,
    `${results.numbers.secondVisitReadyMs} ms from the catalog; state requests ${served.stateRequests - stateRequests}`);
  await page.close();
}

// Flutter drawn over the display: the dim around the dialog, and the settings menu, which comes from
// above the router and so is drawn over the dialog as well.

/** The middle of what `a` and `b` share, or null where they do not meet. */
function overlap(a, b) {
  if (!a || !b) return null;
  const left = Math.max(a.x ?? a.left, b.x ?? b.left);
  const top = Math.max(a.y ?? a.top, b.y ?? b.top);
  const right = Math.min((a.x ?? a.left) + (a.w ?? a.width), (b.x ?? b.left) + (b.w ?? b.width));
  const bottom = Math.min((a.y ?? a.top) + (a.h ?? a.height), (b.y ?? b.top) + (b.h ?? b.height));
  return right > left && bottom > top ? { x: (left + right) / 2, y: (top + bottom) / 2 } : null;
}

async function overDisplay() {
  // Small enough that the settings menu, which drops from the bar, reaches over the dialog.
  const { page, run } = await openWithDraft('over', { width: 820, height: 700, deviceScaleFactor: 1 }, CLICK_PROGRAM);
  // The page's own scroll, read before the dialog blocks its semantics and again once it is gone.
  const editorBefore = await findText(page, 'main.py', { exact: true });
  const from = await eventMark(page);
  await clickRect(page, run);
  const blue = await waitPixel(page, 400, 300, isBlue, 20_000);
  check('the draft put the program back in the editor, and it runs', blue !== null, blue !== null ? `screen filled ${blue} ms after Run` : 'no blue screen');
  if (blue === null) {
    await page.close();
    return;
  }
  const box = await viewBox(page);
  await shot(page, 'program-dialog.png');
  const clicksSoFar = async () => outputOf(await eventsSince(page, from));

  await page.mouse.move(box.left + box.width / 2, box.top + 60);
  await page.mouse.wheel({ deltaY: 300 });
  await sleep(600);
  const afterWheel = await viewBox(page);
  check('the wheel over the display does not move the program\'s own box', Math.abs(afterWheel.top - box.top) < 1,
    `display top ${Math.round(box.top)} -> ${Math.round(afterWheel.top)}`);

  // The dim beside the program: it takes the press, and nothing of it reaches the guest.
  const beside = { x: Math.max(8, box.left / 2), y: box.top + box.height / 2 };
  await page.mouse.click(beside.x, beside.y);
  await sleep(1200);
  const stillBlue = await guestPixel(page, 400, 300);
  const afterDim = await clicksSoFar();
  check('a press on the dim beside the program does not reach the guest, and leaves it running',
    isBlue(stillBlue) && !afterDim.includes('click') && (await viewBox(page)) !== null,
    `pressed ${Math.round(beside.x)},${Math.round(beside.y)}; guest 400,300 rgb(${stillBlue}); guest output ${JSON.stringify(afterDim)}`);

  const cog = await findSettled(page, 'Settings', { exact: true });
  await clickRect(page, cog);
  await sleep(600);
  await shot(page, 'menu-over-display.png');
  let item = null;
  for (const label of ['System', 'Light', 'Dark', 'Device language', 'English']) {
    const rect = await findText(page, label, { exact: true, timeout: 1000 });
    const point = overlap(rect, box);
    if (point) {
      item = { label, point };
      break;
    }
  }
  if (item) {
    const under = await guestAt(page, item.point.x, item.point.y);
    await page.mouse.click(item.point.x, item.point.y);
    await sleep(1200);
    const pixel = await guestPixel(page, under.gx, under.gy);
    const clicks = await clicksSoFar();
    check('a click on the settings menu over the display does not reach the guest', isBlue(pixel) && !clicks.includes('click'),
      `"${item.label}" over guest ${under.gx},${under.gy} rgb(${pixel}); guest output ${JSON.stringify(clicks)}`);
  } else {
    check('the settings menu lies over the display', false, JSON.stringify(box));
  }
  await page.keyboard.press('Escape');
  await sleep(500);

  const t = Date.now();
  await clickGuest(page, 400, 400);
  const red = await waitPixel(page, 400, 400, isRed, 5000);
  const clicks = await clicksSoFar();
  check('a click on the display itself reaches the guest', red !== null && /click (39\d|40\d) (39\d|40\d)/.test(clicks), `red after ${Date.now() - t} ms; guest output ${JSON.stringify(clicks.trim())}`);

  await clickStop(page);
  await waitEvent(page, from, event => event.type === 'parked', 10_000);
  await sleep(500);
  const editorAfter = await findText(page, 'main.py', { exact: true });
  check('the page behind the dialog is where it was left, and readable again',
    !!editorAfter && Math.abs(editorAfter.y - editorBefore.y) < 1,
    `editor ${Math.round(editorBefore.y)} -> ${editorAfter ? Math.round(editorAfter.y) : 'gone'}`);
  await page.close();
}

// The display cropped to the program's windows: a small one at its real size, a messagebox that widens
// the crop and a click on its OK, and a canvas larger than the screen shrunk to fit. Semantics stay on
// to find Run: the programs come in as drafts, so nothing is typed into the editor.

/** The Tkinter page by its address, with `source` in the editor, the machine ready and Run found. */
async function openWithDraft(label, viewport, source) {
  const page = await browser.newPage();
  await page.setViewport(viewport);
  watch(page, label);
  await withDraft(page, source);
  await page.goto(`${appUrl}#/learn-python/tkinter`, { waitUntil: 'load' });
  await enableSemantics(page);
  await waitText(page, 'Tk 8.6', 60_000);
  const run = await findSettled(page, 'Run', { exact: true, visible: false });
  return { page, run };
}

/**
 * The OK button in the bottom band of `dialog`, found in the canvas as the box of pixels that differ from
 * the dialog's own background there, or null. tk_messageBox centres its buttons in a strip along the
 * bottom, which is all this leans on.
 */
async function dialogButton(page, dialog) {
  return page.evaluate(d => {
    const canvas = document.querySelector('.icc-vm-screen > canvas');
    const data = canvas.getContext('2d').getImageData(d.x, d.y, d.w, d.h).data;
    const px = (x, y) => { const i = (y * d.w + x) * 4; return [data[i], data[i + 1], data[i + 2]]; };
    const bg = px(2, d.h - 3);
    const differs = p => Math.abs(p[0] - bg[0]) + Math.abs(p[1] - bg[1]) + Math.abs(p[2] - bg[2]) > 30;
    let box = null;
    for (let y = Math.max(0, d.h - 36); y < d.h - 1; y++) {
      for (let x = 1; x < d.w - 1; x++) {
        if (!differs(px(x, y))) continue;
        box = box ? { left: Math.min(box.left, x), top: Math.min(box.top, y), right: Math.max(box.right, x), bottom: Math.max(box.bottom, y) }
          : { left: x, top: y, right: x, bottom: y };
      }
    }
    return box && { gx: d.x + Math.round((box.left + box.right) / 2), gy: d.y + Math.round((box.top + box.bottom) / 2), w: box.right - box.left + 1, h: box.bottom - box.top + 1 };
  }, dialog);
}

async function crop() {
  // A small window, and a messagebox over it.
  {
    const { page, run } = await openWithDraft('crop-dialog', { width: 1440, height: 1000, deviceScaleFactor: 1 }, DIALOG_PROGRAM);
    const from = await eventMark(page);
    await clickRect(page, run);
    const listed = await waitEvent(page, from, event => event.type === 'window' && event.windows.some(w => w.root && w.mapped), 20_000);
    const root = listed?.event.windows.find(w => w.root);
    await waitSettled(page);
    const small = await waitCrop(page, await latestRegion(page, from));
    await shot(page, 'crop-small-window.png');
    check('a small window is shown cropped to itself, at 1x', !!small && small.scale === 1 && small.x === 0 && small.y === 0 && small.w < 200,
      `${describeCrop(small ?? await displayCrop(page))}; root ${root?.w}x${root?.h}+${root?.x}+${root?.y}`);

    // The button, found the way the starter's is: the lowest row in the middle column that is not the window's own background.
    const win = await tkWindow(page);
    const asked = await eventMark(page);
    if (win?.bottom > 0) await clickGuest(page, Math.floor(win.w / 2), win.bottom - 6);
    const opened = await waitEvent(page, asked, event => event.type === 'window' && event.windows.some(w => w.mapped && w.transient_for), 10_000);
    const dialog = opened?.event.windows.find(w => w.mapped && w.transient_for);
    await sleep(800);
    const region = await latestRegion(page, asked);
    const grown = await waitCrop(page, region);
    await shot(page, 'crop-messagebox.png');
    check('a click on the small window\'s button reaches it, and its messagebox widens the crop to hold both',
      !!dialog && !!grown && grown.w >= dialog.w && grown.w > small?.w,
      `dialog "${dialog?.title}" ${dialog?.w}x${dialog?.h}+${dialog?.x}+${dialog?.y}; region ${describeRegion(region)}; shown ${describeCrop(grown ?? await displayCrop(page))}`);

    if (dialog) {
      const ok = await dialogButton(page, dialog);
      const answered = await eventMark(page);
      if (ok) await clickGuest(page, ok.gx, ok.gy);
      const printed = await waitEvent(page, answered, event => event.type === 'output' && event.text.includes('answer'), 8000);
      const closed = await waitEvent(page, answered, event => event.type === 'window' && !event.windows.some(w => w.mapped && w.transient_for), 5000);
      const back = closed && await waitCrop(page, regionOf(closed.event.windows));
      await sleep(300);
      await shot(page, 'crop-after-ok.png');
      check('a click on the messagebox\'s OK answers it, and the crop shrinks back to the window',
        printed?.event.text === 'answer ok\n' && !!back && small && Math.abs(back.w - small.w) < 1 && Math.abs(back.h - small.h) < 1,
        `OK found at guest ${ok?.gx},${ok?.gy} (${ok?.w}x${ok?.h}); output ${JSON.stringify(printed?.event.text)}; shown ${describeCrop(back ?? await displayCrop(page))}`);
    }
    await clickText(page, 'Stop the program', { exact: true });
    await waitEvent(page, from, event => event.type === 'parked', 10_000);
    await page.close();
  }

  // A canvas larger than the screen, in a window too short to show the screen at 1:1.
  {
    const { page, run } = await openWithDraft('crop-big', { width: 1100, height: 760, deviceScaleFactor: 1 }, BIG_CANVAS_PROGRAM);
    const from = await eventMark(page);
    await clickRect(page, run);
    const listed = await waitEvent(page, from, event => event.type === 'window' && event.windows.some(w => w.root && w.mapped), 20_000);
    const root = listed?.event.windows.find(w => w.root);
    const blue = await waitPixel(page, 400, 200, isBlue, 20_000);
    const region = await latestRegion(page, from);
    const shrunk = await waitCrop(page, region);
    // The white line across the canvas comes after its fill, and the shot is for looking at it.
    await sleep(500);
    await shot(page, 'crop-big-canvas.png');
    check('a 1920x1080 canvas is cropped to the screen and scaled down, resampled rather than nearest-neighbour',
      blue !== null && !!shrunk && shrunk.w === 800 && shrunk.h === 600 && shrunk.scale < 1 && !shrunk.pixelated,
      `root ${root?.w}x${root?.h}; ${describeCrop(shrunk ?? await displayCrop(page))}; pixelated ${shrunk?.pixelated}`);

    const landed = [];
    for (const [gx, gy] of [[400, 300], [780, 580], [15, 20]]) {
      const mark = await eventMark(page);
      await clickGuest(page, gx, gy);
      const printed = await waitEvent(page, mark, event => event.type === 'output' && event.text.startsWith('click'), 5000);
      const [, x, y] = printed?.event.text.trim().split(' ').map(Number) ?? [];
      landed.push({ at: [gx, gy], got: printed ? [x, y] : null });
      await sleep(200);
    }
    // One CSS pixel is 1/scale guest pixels, and a click is rounded to a CSS pixel.
    const slack = shrunk ? Math.ceil(1 / shrunk.scale) : 2;
    check('clicks on the shrunk canvas land where they were aimed', landed.every(({ at, got }) => got && Math.abs(got[0] - at[0]) <= slack && Math.abs(got[1] - at[1]) <= slack),
      `${JSON.stringify(landed)}, within ${slack} guest px`);
    await clickText(page, 'Stop the program', { exact: true });
    await waitEvent(page, from, event => event.type === 'parked', 10_000);
    await page.close();
  }
}

// The Tkinter page at 4× CPU, opened by its address

async function throttled(layout, rate) {
  const page = await browser.newPage();
  watch(page, `${rate}x`);
  await withDraft(page, null);
  await page.emulateCPUThrottling(rate);
  const t0 = Date.now();
  await page.goto(`${appUrl}#/learn-python/tkinter`, { waitUntil: 'load' });
  await waitEvent(page, 0, event => event.type === 'ready', 120_000);
  results.numbers[`${rate}x: address to ready`] = Date.now() - t0;
  await sleep(500);
  const runs = [];
  for (let i = 0; i < 3; i++) {
    const from = await eventMark(page);
    const t = Date.now();
    await clickRect(page, layout.run);
    const win = await waitWindow(page, 30_000);
    const onCanvasMs = win ? Date.now() - t : null;
    let clickMs = null;
    const settled = win && await waitSettled(page);
    if (settled) {
      const before = await tkWindow(page, 50);
      await clickGuest(page, Math.floor(settled.w / 2), settled.bottom - 12);
      clickMs = (await waitChanged(page, before, 10_000))?.ms ?? null;
    }
    const tStop = await pageNow(page);
    await clickStop(page);
    const parked = await waitEvent(page, from, event => event.type === 'parked', 20_000);
    runs.push({ onCanvasMs, clickMs, parkedMs: parked ? Math.round(parked.event.at - tStop) : null });
    await sleep(500);
  }
  results.numbers[`${rate}x: runs`] = runs;
  check(`at ${rate}x CPU the starter program runs, takes a click and stops`, runs.every(r => r.onCanvasMs !== null && r.clickMs !== null && r.parkedMs !== null), JSON.stringify(runs));
  await page.close();
}

// A lesson step, which runs through python.wasm rather than the machine

async function lesson(address, code) {
  const survey = await browser.newPage();
  watch(survey, 'lesson-survey');
  await survey.goto(`${appUrl}#/${address}`, { waitUntil: 'load' });
  await enableSemantics(survey);
  await waitText(survey, 'Check code', 30_000);
  const checkButton = await findSettled(survey, 'Check code', { exact: true });
  const editorLabel = await findSettled(survey, 'main.py', { exact: true, timeout: 3000 });
  await survey.close();

  const page = await browser.newPage();
  watch(page, 'lesson');
  await page.goto(`${appUrl}#/${address}`, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view', { timeout: 60_000 });
  await sleep(3000);
  await setEditor(page, { x: editorLabel.x + 200, y: editorLabel.y + 45 }, code);
  await clickRect(page, checkButton);
  await sleep(4000);
  await shot(page, 'lesson-step.png');
  await enableSemantics(page);
  const passed = await waitText(page, 'Correct!', 20_000);
  check(`the lesson step ${address} runs and passes`, !!passed, passed ? '"Correct!"' : 'no verdict');
  await page.close();
}

let failed = true;
try {
  const layout = await survey();
  await main(layout);
  await overDisplay();
  await crop();
  await throttled(layout, 4);
  if (opts.lesson) await lesson(opts.lesson, opts['lesson-code']);
  failed = results.checks.some(c => !c.passed);
} catch (error) {
  check('the run itself', false, String(error.stack ?? error).split('\n').slice(0, 3).join(' | '));
} finally {
  results.served = served;
  results.finishedAt = new Date().toISOString();
  fs.mkdirSync(path.dirname(opts.out), { recursive: true });
  fs.writeFileSync(opts.out, `${JSON.stringify(results, null, 1)}\n`);
  await browser.close();
  server.close();
  fs.rmSync(profile, { recursive: true, force: true });
  log(`${results.checks.filter(c => c.passed).length} of ${results.checks.length} checks passed; written to ${path.relative(repoDir, opts.out)}`);
  for (const line of results.console) log('console', line);
}
process.exit(failed ? 1 : 0);
