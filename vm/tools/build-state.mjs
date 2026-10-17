// Turns the image in vm/build/ into the bundle a page loads. It boots the image once, has the
// agent PREPARE the warm machine, saves that machine, and writes web/vm/image/<imageId>/: the
// state, the rootfs it refers to, the v86 build that saved it, and manifest.json. The report
// lands in vm/build/build-state.json. See docs/vm-build.md.
//
// Usage: node build-state.mjs [--reserve-mib N] [--resident PATH]... [--echo] [--debug-shell]
//                             [--memory-mib N] [--out DIR]
//
// --debug-shell saves a machine with a root shell on ttyS0 into vm/build/debug-image/ instead,
// for checks that have to reach inside the guest, such as stopping the agent. It never ships.
// --memory-mib and --out build a machine of another size into another directory, to measure what
// a size costs beside the shipped one; machine.mjs stays the size that ships.

import { createHash, randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

import { VERSION as AGENT_PROTO } from '../../web/vm/vm_protocol.js';
import { machine } from '../image/machine.mjs';
import { AgentLine } from './lib/agent_line.mjs';
import { loadBundle, openHost, restoreAndGreet } from './lib/bundle.mjs';
import { imageDir } from './lib/dirs.mjs';
import { bootImage, buildDir, repoDir } from './lib/image-boot.mjs';
import { renderNotices } from './lib/notices.mjs';
import { readCrates, readKernel, readLock } from './lib/packages.mjs';
import { sourceHash } from './lib/source-hash.mjs';

/** zstd's maximum, which is also the first level that emits a single-segment frame. */
const zstdLevel = 22;

/** Files the agent reads back into the page cache besides the ones Xorg and the warm
 *  interpreter map, as paths or patterns over vm/build/fs.json. Each file a run reads that is not
 *  resident is a fetch over the network. */
const RESIDENT = [
  // A second interpreter in one program (a second Tk(), or Tcl()) runs Tcl's and Tk's library
  // scripts again, and a messagebox on it loads msgcat. The warm-up read them all once, but
  // nothing maps a script, so dropping the caches let them go.
  /^\/usr\/lib\/tk8\.6\/(ttk\/)?[^/]+\.tcl$/,
  '/usr/lib/tk8.6/tclIndex',
  '/usr/lib/tcl8.6/init.tcl',
  '/usr/lib/tcl8.6/auto.tcl',
  '/usr/lib/tcl8.6/tm.tcl',
  '/usr/lib/tcl8.6/tclIndex',
  /^\/usr\/lib\/tcl8\/8\.5\/msgcat-[^/]+\.tm$/,
  // Tcl reads them to fill in tcl_platform(user) when an interpreter starts.
  '/etc/passwd',
  '/etc/group',
  // What fontconfig picks for the families programs name (Arial, Helvetica, Times, Courier and
  // the rest) in each of the four styles. Only the faces the warm-up drew are mapped already.
  /^\/usr\/share\/fonts\/dejavu\/DejaVu(Sans|Serif|SansMono)(-(Bold|Oblique|Italic|BoldOblique|BoldItalic))?\.ttf$/,
  // Every run reads the zone HELLO names. These are the zones the app's students are in; any
  // other zone costs the first run of a page one fetch of a few kB. A zone per file: tzdata's
  // links are files of their own in the guest, each with its own page cache.
  '/usr/share/zoneinfo/Europe/Amsterdam',
  '/usr/share/zoneinfo/Europe/Brussels',
];

/** README 6.16: free memory left unzeroed. Above the kernel's watermarks (under 2 MiB at 96 and
 *  128 MiB; the agent LOGs them), so zeroing never makes it reclaim the page cache the snapshot
 *  keeps. */
const RESERVE_MIB = 2;

const MIN_FREE_KB = 5767168;

const { values: opts } = parseArgs({
  options: {
    'reserve-mib': { type: 'string' },
    resident: { type: 'string', multiple: true },
    echo: { type: 'boolean', default: false },
    'debug-shell': { type: 'boolean', default: false },
    'memory-mib': { type: 'string' },
    out: { type: 'string' },
  },
});

const debugShell = opts['debug-shell'];
const memoryMiB = Number(opts['memory-mib'] ?? machine.memoryMiB);
const imageRoot = opts.out ? path.resolve(opts.out) : debugShell ? path.join(buildDir, 'debug-image') : imageDir;
const reportName = debugShell ? 'build-state-debug' : 'build-state';
// An experiment's report goes beside its bundle, so it leaves the shipped build's alone.
const reportDir = opts.out ? imageRoot : buildDir;
const v86Build = path.dirname(new URL(import.meta.resolve('v86')).pathname);
const report = { settings: { ...machine, memoryMiB } };
const log = message => console.log(`build-state: ${message}`);

setTimeout(() => {
  console.error('build-state: gave up after 30 minutes');
  process.exit(2);
}, 30 * 60_000).unref();

checkDisk('before the boot');

const t0 = performance.now();
const booted = await bootImage({ debugShell, echo: opts.echo && debugShell, memoryMiB });
const { emu } = booted;
const consoleOutput = [];
emu.add_listener('serial0-output-byte', byte => {
  consoleOutput.push(byte);
  if (opts.echo) process.stdout.write(String.fromCharCode(byte));
});
const line = new AgentLine(emu, {
  onMessage(message) {
    if (message.type === 'LOG') log(`agent ${message.body.level}: ${message.body.message}`);
  },
});

// bootImage() waits for the debug shell, and the agent has said its unasked READY by then.
if (!debugShell) {
  const hello = await line.waitFor(m => m.type === 'READY' && m.id === 0, 10 * 60_000, 'READY from the booting agent');
  report.bootToAgentMs = Math.round(hello.at - t0);
  log(`agent ${hello.body.agent} up after ${report.bootToAgentMs} ms`);
}
report.bootFetches = { files: booted.fetches.everything.length, bytes: booted.fetches.everything.reduce((n, e) => n + e.size, 0) };

const ready = await line.request('HELLO', {
  now_ms: Date.now(),
  tz: 'UTC',
  entropy: randomBytes(64).toString('hex'),
}, { answers: ['READY'] });
log(`READY ${JSON.stringify(ready.body)}`);

const prepare = {
  resident: [...residentFiles(RESIDENT), ...(opts.resident ?? [])],
  reserve_mib: Number(opts['reserve-mib'] ?? RESERVE_MIB),
};
const fetchedBefore = booted.fetches.everything.length;
let started = performance.now();
const parked = await line.request('PREPARE', prepare, { answers: ['PARKED'], timeoutMs: 20 * 60_000 });
report.prepare = prepare;
report.prepareMs = Math.round(performance.now() - started);
report.prepareFetches = booted.fetches.everything.slice(fetchedBefore).map(e => e.path);
report.parked = parked.body;
report.agentLogs = line.received.filter(m => m.type === 'LOG').map(m => `${m.body.level}: ${m.body.message}`);
log(`PARKED after ${report.prepareMs} ms: ${JSON.stringify(parked.body)}`);
if (!parked.body.warm) throw new Error('PARKED without a warm interpreter; README 6.17 forbids saving that');

// README 6.17: nothing may reach the agent between PARKED and the save.
await emu.stop();
started = performance.now();
const raw = new Uint8Array(await emu.save_state());
report.saveMs = Math.round(performance.now() - started);
const stateVersion = new DataView(raw.buffer).getInt32(4, true);
started = performance.now();
const state = zlib.zstdCompressSync(raw, {
  params: {
    // The student downloads this once per image, so the build spends the time: 22 is 1.1 MB under
    // 19 on the same raw state, and v86's decoder reads the single-segment frame it produces at
    // the same speed and in the same memory.
    [zlib.constants.ZSTD_c_compressionLevel]: zstdLevel,
    // A download that is corrupt but the right size then fails at decompression, v86's decoder
    // included, instead of restoring into a guest that is wrong in ways only a run finds.
    [zlib.constants.ZSTD_c_checksumFlag]: 1,
  },
});
report.compressMs = Math.round(performance.now() - started);
// Frame_Header_Descriptor, after the 4-byte magic: bit 2 is Content_Checksum_flag.
if (!(state[4] & 0x04)) throw new Error('the zstd state has no content checksum');
report.stateRawBytes = raw.byteLength;
report.stateBytes = state.byteLength;
log(`state: ${raw.byteLength} B raw, ${state.byteLength} B zstd -${zstdLevel} (${(state.byteLength / 2 ** 20).toFixed(2)} MiB)`);
fs.mkdirSync(imageRoot, { recursive: true });
fs.writeFileSync(path.join(reportDir, opts.out ? `${reportName}-console.log` : `logs/${reportName}-console.log`), Buffer.from(consoleOutput));
await emu.destroy();

checkDisk('before writing the bundle');
const stateSha256 = sha256(state);
const imageId = stateSha256.slice(0, 16);
const bundle = path.join(imageRoot, imageId);
fs.mkdirSync(path.join(bundle, 'rootfs'), { recursive: true });
fs.writeFileSync(path.join(bundle, 'state.bin.zst'), state);
const rootfs = linkRootfs(path.join(buildDir, 'rootfs-flat'), path.join(bundle, 'rootfs'));
for (const file of ['libv86.mjs', 'v86.wasm']) fs.copyFileSync(path.join(v86Build, file), path.join(bundle, file));

const v86Version = JSON.parse(fs.readFileSync(path.join(v86Build, '../package.json'), 'utf8')).version;
const wasm = fs.readFileSync(path.join(bundle, 'v86.wasm'));
const manifest = {
  imageId,
  v86: { version: v86Version, lib: 'libv86.mjs', wasm: 'v86.wasm', wasmBytes: wasm.byteLength, wasmSha256: sha256(wasm) },
  stateVersion,
  state: { file: 'state.bin.zst', bytes: state.byteLength, sha256: stateSha256, rawBytes: raw.byteLength, zstdChecksum: true },
  rootfs: { dir: 'rootfs/', files: rootfs.files, bytes: rootfs.bytes },
  memoryMiB,
  vgaMiB: machine.vgaMiB,
  uart1: machine.uart1,
  screen: machine.screen,
  agentProto: AGENT_PROTO,
  debugShell,
  agent: ready.body.agent,
  interpreter: null,
  sourceHash: sourceHash(repoDir).hash,
  builtAt: new Date().toISOString(),
};
report.notices = writeNotices(bundle, manifest);
writeManifest(manifest, { entry: false });

// The state as a page gets it: a fresh host, restored, must find the warm interpreter waiting.
// Its READY is also the only place the interpreter names itself, since PARKED does not.
const loaded = await loadBundle(bundle);
const opened = await openHost(loaded);
report.hostLoadMs = Math.round(opened.loadMs);
const restored = await restoreAndGreet(loaded, opened.host, opened.line);
await opened.host.destroy();
report.restore = { readyMs: Math.round(restored.readyMs), restoreMs: Math.round(restored.restoreMs), syncMs: Math.round(restored.syncMs), ready: restored.ready };
log(`restored in a fresh host: READY ${JSON.stringify(restored.ready)} ${report.restore.readyMs} ms after the restore began`);
if (!restored.ready.warm) throw new Error('the restored agent has no warm interpreter');
manifest.interpreter = { python: restored.ready.python, tk: restored.ready.tk };
writeManifest(manifest, { entry: true });

report.removedBundles = removeOtherBundles(imageId);
report.manifest = manifest;
report.totalMs = Math.round(performance.now() - t0);
fs.writeFileSync(path.join(reportDir, `${reportName}.json`), JSON.stringify(report, null, 1) + '\n');
log(`wrote ${path.relative(repoDir, bundle)}/ (${rootfs.files} rootfs files) in ${report.totalMs} ms`);
checkDisk('after writing the bundle');
process.exit(0);

/**
 * Writes the bundle's NOTICES.txt and names it in the manifest, from what build-image.sh left in
 * the build directory. A build directory made without them still gets a bundle, which
 * package-image.mjs then refuses to release.
 */
function writeNotices(bundle, manifest) {
  const inputs = ['packages.lock', 'agent-crates.txt', 'bios/SOURCE', 'kernel.txt'].map(name => path.join(buildDir, name));
  const missing = inputs.filter(file => !fs.existsSync(file));
  if (missing.length) {
    log(`no NOTICES.txt: ${missing.map(file => path.relative(buildDir, file)).join(', ')} missing; run \`just build-vm-image\``);
    return null;
  }
  const [lock, crates, bios, kernel] = inputs.map(file => fs.readFileSync(file, 'utf8'));
  const text = Buffer.from(renderNotices({
    lock: readLock(lock),
    agent: readCrates(crates),
    v86: { version: manifest.v86.version, license: fs.readFileSync(path.join(v86Build, '../LICENSE'), 'utf8') },
    biosSource: bios.trim(),
    sourceHash: manifest.sourceHash,
    kernel: readKernel(kernel),
  }));
  fs.writeFileSync(path.join(bundle, 'NOTICES.txt'), text);
  manifest.notices = { file: 'NOTICES.txt', bytes: text.byteLength, sha256: sha256(text) };
  return manifest.notices;
}

/** The regular files of the image that `entries` name, a pattern matching any number of them. */
function residentFiles(entries) {
  const files = [];
  const walk = (nodes, dir) => {
    for (const node of nodes) {
      const file = `${dir}/${node[0]}`;
      if ((node[3] & 0xF000) === 0x4000) walk(node[6], file);
      else if ((node[3] & 0xF000) === 0x8000) files.push(file);
    }
  };
  walk(JSON.parse(fs.readFileSync(path.join(buildDir, 'fs.json'), 'utf8')).fsroot, '');
  const chosen = files.filter(file => entries.some(entry => typeof entry === 'string' ? entry === file : entry.test(file)));
  for (const entry of entries) {
    if (!chosen.some(file => typeof entry === 'string' ? entry === file : entry.test(file))) {
      throw new Error(`no file in the image matches the resident entry ${entry}`);
    }
  }
  return chosen.sort();
}

/** Into the bundle, and with `entry` also as the entry point beside it that a page fetches
 *  first, which only a bundle that restored MAY become. */
function writeManifest(manifest, { entry }) {
  const text = JSON.stringify(manifest, null, 1) + '\n';
  fs.writeFileSync(path.join(imageRoot, manifest.imageId, 'manifest.json'), text);
  if (entry) fs.writeFileSync(path.join(imageRoot, 'manifest.json'), text);
}

/** Hard links, so a bundle costs no second copy of the 50 MiB store; a copy where links fail. */
function linkRootfs(from, to) {
  let files = 0;
  let bytes = 0;
  for (const name of fs.readdirSync(from)) {
    const target = path.join(to, name);
    if (!fs.existsSync(target)) {
      try {
        fs.linkSync(path.join(from, name), target);
      } catch (error) {
        if (error.code !== 'EXDEV' && error.code !== 'EPERM') throw error;
        fs.copyFileSync(path.join(from, name), target);
      }
    }
    files++;
    bytes += fs.statSync(target).size;
  }
  return { files, bytes };
}

/** Earlier bundles this script wrote: directories beside the new one that hold a manifest. */
function removeOtherBundles(keep) {
  const removed = [];
  for (const entry of fs.readdirSync(imageRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === keep) continue;
    if (!fs.existsSync(path.join(imageRoot, entry.name, 'manifest.json'))) continue;
    fs.rmSync(path.join(imageRoot, entry.name), { recursive: true });
    removed.push(entry.name);
  }
  return removed;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function checkDisk(when) {
  const free = fs.statfsSync(repoDir);
  const freeKb = Math.floor(free.bavail * free.bsize / 1024);
  log(`disk: ${Math.round(freeKb / 1024)} MiB free ${when}`);
  if (freeKb < MIN_FREE_KB) {
    console.error(`ERROR: DISK_LOW: under ${MIN_FREE_KB / 1024} MiB free, stopping.`);
    process.exit(1);
  }
}
